param(
    [string]$EnvFile = ".env"
)

$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

$Routes = @(
    @{ Env = "GITHUB_MCP_PUBLIC_URL"; Path = "github-mcp" },
    @{ Env = "DEPLOY_MCP_PUBLIC_URL"; Path = "deploy-mcp" },
    @{ Env = "SOCIAL_MCP_PUBLIC_URL"; Path = "social-mcp" },
    @{ Env = "GITHUB_BFF_PUBLIC_URL"; Path = "github-bff" },
    @{ Env = "VOS_MCP_PUBLIC_URL"; Path = "vos-mcp" },
    @{ Env = "VOS_BFF_PUBLIC_URL"; Path = "vos-bff" }
)

function New-HexToken([int]$Bytes = 32) {
    $buffer = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
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
        Copy-Item ".env.quick-tunnel.example" $Path
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

function Get-NgrokPublicUrl {
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        $ngrokProcess = Get-Process ngrok -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $ngrokProcess) {
            $stderr = Join-Path $Root ".tmp-ngrok\ngrok.err.log"
            $stdout = Join-Path $Root ".tmp-ngrok\ngrok.out.log"
            $logText = ""
            if (Test-Path $stderr) {
                $logText += Get-Content $stderr -Raw
            }
            if (Test-Path $stdout) {
                $logText += Get-Content $stdout -Raw
            }

            if ($logText -match "ERR_NGROK_4018|requires a verified account and authtoken|authentication failed") {
                throw "ngrok requires a verified account and authtoken. Run: ngrok config add-authtoken <your-token>. Get the token at https://dashboard.ngrok.com/get-started/your-authtoken"
            }

            throw "ngrok exited before publishing a URL. Check .tmp-ngrok/ngrok.err.log and .tmp-ngrok/ngrok.out.log."
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
Get-CommandPath "docker" | Out-Null
docker version | Out-Null

if (-not (Test-Path $EnvFile)) {
    Copy-Item ".env.quick-tunnel.example" $EnvFile
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

foreach ($key in @("MCP_BEARER_TOKEN", "MCP_SERVER_API_KEY", "SOCIAL_MCP_ACCESS_TOKEN", "PUBLIC_EDGE_TOKEN")) {
    if (Test-Placeholder $currentEnv[$key]) {
        $initialValues[$key] = New-HexToken
    }
}

if ($initialValues.Count -gt 0) {
    Set-EnvValues $EnvFile $initialValues
    $currentEnv = Read-EnvMap $EnvFile
}

$edgeToken = $currentEnv["PUBLIC_EDGE_TOKEN"]
if (Test-Placeholder $edgeToken) {
    throw "PUBLIC_EDGE_TOKEN is missing. Re-run just ngrok-up so it can generate one, or set it manually in .env."
}

Write-Host "Pulling latest Compose images..."
docker compose -f compose/docker-compose.yml --env-file $EnvFile --profile all pull

Write-Host "Starting local Compose services and path proxy..."
docker compose -f compose/docker-compose.yml --env-file $EnvFile --profile all up -d --wait

Write-Host "Validating local proxy routes..."
$edgeHeaders = @{ "X-Platform-Token" = $edgeToken }
Invoke-RestMethod -Uri "http://localhost:8088/healthz" -Headers $edgeHeaders -TimeoutSec 10 | Out-Null
Invoke-RestMethod -Uri "http://localhost:8088/github-mcp/healthz" -Headers $edgeHeaders -TimeoutSec 10 | Out-Null
Invoke-RestMethod -Uri "http://localhost:8088/deploy-mcp/healthz" -Headers $edgeHeaders -TimeoutSec 10 | Out-Null
Invoke-RestMethod -Uri "http://localhost:8088/social-mcp/health" -Headers $edgeHeaders -TimeoutSec 10 | Out-Null
Invoke-RestMethod -Uri "http://localhost:8088/github-bff/healthz" -Headers $edgeHeaders -TimeoutSec 10 | Out-Null
Invoke-RestMethod -Uri "http://localhost:8088/vos-mcp/health" -Headers $edgeHeaders -TimeoutSec 10 | Out-Null
Invoke-RestMethod -Uri "http://localhost:8088/vos-bff/healthz" -Headers $edgeHeaders -TimeoutSec 10 | Out-Null

$staticDomain = $currentEnv["NGROK_STATIC_DOMAIN"]
$ngrokArgs = @("http", "http://localhost:8088", "--log", "stdout")
if (-not [string]::IsNullOrWhiteSpace($staticDomain)) {
    $ngrokArgs += "--domain=$staticDomain"
}

Write-Host "Starting ngrok..."
Stop-ExistingNgrok
$logDir = Join-Path $Root ".tmp-ngrok"
New-Item -ItemType Directory -Force -Path $logDir | Out-Null
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

$publicValues = @{
    DOMAIN = (($publicBaseUrl -replace "^https?://", "") -replace "/.*$", "")
    NGROK_PUBLIC_URL = $publicBaseUrl
}

foreach ($route in $Routes) {
    $publicValues[$route.Env] = "$publicBaseUrl/$($route.Path)"
}

Set-EnvValues $EnvFile $publicValues

Write-Host "Validating public path routes..."
just status-public

Write-Host ""
Write-Host "Ngrok path-routed environment is ready:"
foreach ($route in $Routes) {
    Write-Host "$($route.Path): $publicBaseUrl/$($route.Path)"
}
