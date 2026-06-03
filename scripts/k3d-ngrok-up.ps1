param(
    [string]$EnvFile = ".env",
    [string]$ClusterName = "personal-platform",
    [int]$LocalPort = 18040
)

$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

function New-HexToken([int]$Bytes = 32) {
    $buffer = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($buffer)
    }
    finally {
        $rng.Dispose()
    }

    -join ($buffer | ForEach-Object { $_.ToString("x2") })
}

function Get-CommandPath([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    if ($Name -eq "ngrok") {
        $candidate = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter ngrok.exe -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
    }

    throw "$Name not found in PATH"
}

function Invoke-Checked([string]$File, [string[]]$Arguments) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $File $($Arguments -join ' ')"
    }
}

function Read-EnvMap([string]$Path) {
    $map = [ordered]@{}
    if (-not (Test-Path $Path)) {
        return $map
    }

    foreach ($line in Get-Content $Path) {
        if ($line -match "^\s*#" -or $line -match "^\s*$") {
            continue
        }
        if ($line -match "^([^=]+)=(.*)$") {
            $map[$matches[1]] = $matches[2].TrimEnd("`r")
        }
    }
    $map
}

function Test-Placeholder([string]$Value) {
    [string]::IsNullOrWhiteSpace($Value) -or
    $Value -eq "change-me" -or
    $Value -eq "changeme" -or
    $Value.StartsWith("paste-") -or
    $Value.StartsWith("replace-with")
}

function Set-EnvValues([string]$Path, [hashtable]$Values) {
    if (-not (Test-Path $Path)) {
        Copy-Item ".env.example" $Path
    }

    $seen = @{}
    $lines = Get-Content $Path
    $updated = foreach ($line in $lines) {
        if ($line -match "^([^#][^=]+)=") {
            $key = $matches[1]
            if ($Values.ContainsKey($key)) {
                $seen[$key] = $true
                "$key=$($Values[$key])"
            }
            else {
                $line.TrimEnd("`r")
            }
        }
        else {
            $line.TrimEnd("`r")
        }
    }

    foreach ($key in $Values.Keys) {
        if (-not $seen.ContainsKey($key)) {
            $updated += "$key=$($Values[$key])"
        }
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Resolve-Path $Path), (($updated -join "`n") + "`n"), $utf8NoBom)
}

function Stop-ExistingNgrok {
    Get-Process ngrok -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
}

function Stop-ComposePortConflicts {
    if (Test-Path "compose/docker-compose.yml") {
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            & (Get-CommandPath "docker") compose -f compose/docker-compose.yml --env-file $EnvFile stop ngrok-proxy 2>&1 | Out-Null
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        if ($exitCode -ne 0) {
            Write-Host "compose ngrok-proxy was not running or could not be stopped; continuing."
        }
    }
}

function Stop-ExistingGatewayPortForward {
    $processes = Get-CimInstance Win32_Process -Filter "name = 'kubectl.exe'" -ErrorAction SilentlyContinue
    foreach ($process in $processes) {
        if ($process.CommandLine -like "*port-forward*" -and
            $process.CommandLine -like "*central-mcp-gateway*" -and
            $process.CommandLine -like "*${LocalPort}:8080*") {
            Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
        }
    }
}

function Start-GatewayPortForward {
    param([string]$LogDir)

    Stop-ExistingGatewayPortForward
    $stdout = Join-Path $LogDir "kubectl-port-forward.out.log"
    $stderr = Join-Path $LogDir "kubectl-port-forward.err.log"
    Remove-Item $stdout, $stderr -Force -ErrorAction SilentlyContinue

    Start-Process `
        -FilePath (Get-CommandPath "kubectl") `
        -ArgumentList @("port-forward", "-n", "mcp", "svc/central-mcp-gateway", "${LocalPort}:8080") `
        -WindowStyle Hidden `
        -RedirectStandardOutput $stdout `
        -RedirectStandardError $stderr

    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline) {
        try {
            Invoke-RestMethod -Uri "http://localhost:${LocalPort}/healthz" -TimeoutSec 2 | Out-Null
            return
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }

    throw "Timed out waiting for kubectl port-forward on http://localhost:${LocalPort}. Check $stderr"
}

function Get-NgrokPublicUrl {
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        $ngrokProcess = Get-Process ngrok -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $ngrokProcess) {
            $stderr = Join-Path $Root ".tmp-k3d-ngrok\ngrok.err.log"
            $stdout = Join-Path $Root ".tmp-k3d-ngrok\ngrok.out.log"
            $logText = ""
            if (Test-Path $stderr) {
                $logText += Get-Content $stderr -Raw
            }
            if (Test-Path $stdout) {
                $logText += Get-Content $stdout -Raw
            }

            if ($logText -match "ERR_NGROK_4018|requires a verified account and authtoken|authentication failed") {
                throw "ngrok requires a verified account and authtoken. Run: ngrok config add-authtoken <your-token>."
            }

            throw "ngrok exited before publishing a URL. Check .tmp-k3d-ngrok/ngrok.err.log and .tmp-k3d-ngrok/ngrok.out.log."
        }

        try {
            $response = Invoke-RestMethod -Uri "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 2
            $publicUrl = $response.tunnels |
                Where-Object { $_.proto -eq "https" -and $_.public_url } |
                Select-Object -First 1 -ExpandProperty public_url
            if ($publicUrl) {
                return $publicUrl.TrimEnd("/")
            }
        }
        catch {
            Start-Sleep -Milliseconds 500
        }
    }

    throw "Timed out waiting for ngrok public URL from http://127.0.0.1:4040/api/tunnels"
}

Write-Host "Checking required tools..."
$Ngrok = Get-CommandPath "ngrok"
$Docker = Get-CommandPath "docker"
$K3d = Get-CommandPath "k3d"
$Kubectl = Get-CommandPath "kubectl"
$Bash = Get-CommandPath "bash"
Invoke-Checked $Docker @("version")

if (-not (Test-Path $EnvFile)) {
    Copy-Item ".env.example" $EnvFile
}

$currentEnv = Read-EnvMap $EnvFile
$initialValues = @{}

if (Test-Placeholder $currentEnv["GITHUB_TOKEN"]) {
    $ghToken = (& gh auth token 2>$null).Trim()
    if (Test-Placeholder $ghToken) {
        throw "GITHUB_TOKEN is missing and gh auth token is not available. Run gh auth login or set GITHUB_TOKEN in .env."
    }
    $initialValues["GITHUB_TOKEN"] = $ghToken
}

foreach ($key in @("MCP_BEARER_TOKEN", "MCP_SERVER_API_KEY", "SOCIAL_MCP_ACCESS_TOKEN", "PUBLIC_EDGE_TOKEN", "CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN", "CENTRAL_MCP_GATEWAY_SESSION_SECRET", "CENTRAL_MCP_GATEWAY_ADMIN_TOKEN")) {
    if (Test-Placeholder $currentEnv[$key]) {
        $initialValues[$key] = New-HexToken
    }
}

if (Test-Placeholder $currentEnv["CENTRAL_MCP_GATEWAY_OAUTH_ALLOWED_REDIRECT_URIS"]) {
    $initialValues["CENTRAL_MCP_GATEWAY_OAUTH_ALLOWED_REDIRECT_URIS"] = "http://localhost:3000/oauth/callback,https://chat.openai.com/aip/oauth/callback"
}

if ($initialValues.Count -gt 0) {
    Set-EnvValues $EnvFile $initialValues
    $currentEnv = Read-EnvMap $EnvFile
}

Write-Host "Creating or reusing k3d cluster..."
Stop-ComposePortConflicts
$clusterExists = (& $K3d cluster list 2>$null | Select-String -Pattern "^$ClusterName\s") -ne $null
if (-not $clusterExists) {
    Invoke-Checked $K3d @("cluster", "create", $ClusterName, "--config", "k8s/overlays/local/k3d-config.yaml")
}
else {
    Invoke-Checked $K3d @("cluster", "start", $ClusterName)
}
$KubeconfigPath = Join-Path $env:USERPROFILE ".config\k3d\kubeconfig-$ClusterName.yaml"
if (-not (Test-Path $KubeconfigPath)) {
    Invoke-Checked $K3d @("kubeconfig", "write", $ClusterName)
}
$kubeconfigText = [System.IO.File]::ReadAllText($KubeconfigPath)
$normalizedKubeconfigText = $kubeconfigText -replace "https://host\.docker\.internal:", "https://127.0.0.1:"
if ($normalizedKubeconfigText -ne $kubeconfigText) {
    [System.IO.File]::WriteAllText($KubeconfigPath, $normalizedKubeconfigText, [System.Text.UTF8Encoding]::new($false))
}
$env:KUBECONFIG = $KubeconfigPath
Invoke-Checked $Kubectl @("config", "use-context", "k3d-$ClusterName")

Write-Host "Applying local Kubernetes overlay..."
Invoke-Checked $Kubectl @("apply", "-k", "k8s/overlays/local")

Write-Host "Injecting .env secrets into k3d..."
Invoke-Checked $Bash @("scripts/k3d-secrets.sh")

Write-Host "Waiting for Kubernetes rollouts..."
$timeout = "180s"
Invoke-Checked $Kubectl @("rollout", "status", "deploy/github-unified-mcp", "-n", "mcp", "--timeout=$timeout")
Invoke-Checked $Kubectl @("rollout", "status", "deploy/deploy-orchestrator-mcp", "-n", "mcp", "--timeout=$timeout")
Invoke-Checked $Kubectl @("rollout", "status", "deploy/mcp-social", "-n", "mcp", "--timeout=$timeout")
Invoke-Checked $Kubectl @("rollout", "status", "deploy/central-mcp-gateway", "-n", "mcp", "--timeout=$timeout")
Invoke-Checked $Kubectl @("rollout", "status", "deploy/github-unified-mcp-bff", "-n", "bff", "--timeout=$timeout")
Invoke-Checked $Kubectl @("rollout", "status", "deploy/vos-studio-mcp", "-n", "vos", "--timeout=$timeout")
Invoke-Checked $Kubectl @("rollout", "status", "deploy/vos-studio-bff", "-n", "bff", "--timeout=$timeout")

$logDir = Join-Path $Root ".tmp-k3d-ngrok"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

Write-Host "Starting local port-forward for central MCP gateway..."
Start-GatewayPortForward -LogDir $logDir

$staticDomain = $currentEnv["NGROK_STATIC_DOMAIN"]
$ngrokArgs = @("http", "http://localhost:${LocalPort}", "--log", "stdout")
if (-not [string]::IsNullOrWhiteSpace($staticDomain)) {
    $ngrokArgs += "--domain=$staticDomain"
}

Write-Host "Starting ngrok..."
Stop-ExistingNgrok
$stdout = Join-Path $logDir "ngrok.out.log"
$stderr = Join-Path $logDir "ngrok.err.log"
Remove-Item $stdout, $stderr -Force -ErrorAction SilentlyContinue

Start-Process `
    -FilePath $Ngrok `
    -ArgumentList $ngrokArgs `
    -WindowStyle Hidden `
    -RedirectStandardOutput $stdout `
    -RedirectStandardError $stderr

$publicBaseUrl = Get-NgrokPublicUrl
Write-Host "NGROK_PUBLIC_URL=$publicBaseUrl"

Set-EnvValues $EnvFile @{
    DOMAIN = (($publicBaseUrl -replace "^https?://", "") -replace "/.*$", "")
    NGROK_PUBLIC_URL = $publicBaseUrl
    CENTRAL_MCP_GATEWAY_PUBLIC_URL = $publicBaseUrl
}
$currentEnv = Read-EnvMap $EnvFile

Write-Host "Updating gateway OAuth issuer to public URL..."
Invoke-Checked $Kubectl @("set", "env", "deployment/central-mcp-gateway", "-n", "mcp", "GATEWAY_PUBLIC_BASE_URL=$publicBaseUrl", "GATEWAY_OAUTH_ISSUER=$publicBaseUrl")
Invoke-Checked $Kubectl @("rollout", "status", "deploy/central-mcp-gateway", "-n", "mcp", "--timeout=$timeout")

Write-Host "Restarting port-forward after gateway rollout..."
Start-GatewayPortForward -LogDir $logDir

Write-Host "Validating public gateway..."
$bearer = $currentEnv["CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN"]
$headers = @{
    Authorization = "Bearer $bearer"
    Accept = "application/json"
    "ngrok-skip-browser-warning" = "true"
}

Invoke-RestMethod -Uri "$publicBaseUrl/healthz" -Headers @{ "ngrok-skip-browser-warning" = "true" } -TimeoutSec 15 | Out-Null
Invoke-RestMethod -Uri "$publicBaseUrl/.well-known/oauth-authorization-server" -Headers @{ Accept = "application/json"; "ngrok-skip-browser-warning" = "true" } -TimeoutSec 15 | Out-Null
$body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
$tools = Invoke-RestMethod -Uri "$publicBaseUrl/mcp" -Method Post -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec 20

Write-Host ""
Write-Host "k3d ngrok environment is ready."
Write-Host "ChatGPT MCP URL: $publicBaseUrl/mcp"
Write-Host "Tools:"
$tools.result.tools | ForEach-Object { Write-Host "  - $($_.name)" }
