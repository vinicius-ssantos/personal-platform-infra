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

function Get-CommandPath([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    if ($Name -eq "ngrok") {
        $candidate = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter ngrok.exe -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($candidate) { return $candidate.FullName }
    }
    throw "$Name not found in PATH"
}

function Read-EnvMap([string]$Path) {
    $map = [ordered]@{}
    if (-not (Test-Path $Path)) { return $map }
    foreach ($line in Get-Content $Path) {
        if ($line -match "^\s*#" -or $line -match "^\s*$") { continue }
        if ($line -match "^([^=]+)=(.*)$") { $map[$matches[1]] = $matches[2].TrimEnd("`r") }
    }
    $map
}

function Set-EnvValues([string]$Path, [hashtable]$Values) {
    $seen = @{}
    $lines = Get-Content $Path
    $updated = foreach ($line in $lines) {
        if ($line -match "^([^#][^=]+)=") {
            $key = $matches[1]
            if ($Values.ContainsKey($key)) { $seen[$key] = $true; "$key=$($Values[$key])" }
            else { $line.TrimEnd("`r") }
        } else { $line.TrimEnd("`r") }
    }
    foreach ($key in $Values.Keys) {
        if (-not $seen.ContainsKey($key)) { $updated += "$key=$($Values[$key])" }
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
            if (Test-Path $stderr) { $logText += Get-Content $stderr -Raw }
            if (Test-Path $stdout) { $logText += Get-Content $stdout -Raw }
            if ($logText -match "ERR_NGROK_4018|requires a verified account and authtoken|authentication failed") {
                throw "ngrok requires a verified account and authtoken. Run: ngrok config add-authtoken <token>"
            }
            throw "ngrok exited before publishing a URL. Check .tmp-ngrok/ngrok.err.log"
        }
        try {
            $response = Invoke-RestMethod -Uri "http://127.0.0.1:4040/api/tunnels" -TimeoutSec 2
            $publicUrl = $response.tunnels |
                Where-Object { $_.proto -eq "https" -and $_.public_url } |
                Select-Object -First 1 -ExpandProperty public_url
            if ($publicUrl) { return $publicUrl.TrimEnd("/") }
        } catch { Start-Sleep -Milliseconds 500 }
    }
    throw "Timed out waiting for ngrok public URL from http://127.0.0.1:4040/api/tunnels"
}

# ── main ────────────────────────────────────────────────────────────────────

$Ngrok = Get-CommandPath "ngrok"

if (-not (Test-Path $EnvFile)) {
    throw ".env not found at $EnvFile. Run 'just env-init' first."
}

$currentEnv = Read-EnvMap $EnvFile
$staticDomain = $currentEnv["NGROK_STATIC_DOMAIN"]

# Verify Caddy proxy is reachable before starting ngrok
Write-Host "Checking local proxy is up (localhost:8088)..."
$proxyOk = $false
try {
    Invoke-RestMethod -Uri "http://localhost:8088/healthz" -TimeoutSec 5 | Out-Null
    $proxyOk = $true
} catch {
    # Docker Desktop on Windows can swallow HTTP responses through port-forwarding even when
    # the container is healthy — fall back to checking container state directly.
    $containerRunning = & docker inspect compose-ngrok-proxy-1 --format '{{.State.Running}}' 2>$null
    if ($containerRunning -eq "true") {
        Write-Host "  (HTTP healthz failed; container is running — proceeding)"
        $proxyOk = $true
    }
}
if (-not $proxyOk) {
    throw "Caddy proxy not reachable at http://localhost:8088. Run 'just compose-up' first."
}

$ngrokArgs = @("http", "http://localhost:8088", "--log", "stdout")
if (-not [string]::IsNullOrWhiteSpace($staticDomain)) {
    $ngrokArgs += "--domain=$staticDomain"
    $ngrokArgs += "--pooling-enabled"
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
    DOMAIN                        = (($publicBaseUrl -replace "^https?://", "") -replace "/.*$", "")
    NGROK_PUBLIC_URL              = $publicBaseUrl
    CENTRAL_MCP_GATEWAY_PUBLIC_URL = $publicBaseUrl
}
foreach ($route in $Routes) {
    $publicValues[$route.Env] = "$publicBaseUrl/$($route.Path)"
}

Set-EnvValues $EnvFile $publicValues
foreach ($key in $publicValues.Keys) {
    [System.Environment]::SetEnvironmentVariable($key, $publicValues[$key], "Process")
}

Write-Host ""
Write-Host "Ngrok tunnel ready:"
foreach ($route in $Routes) {
    Write-Host "  $($route.Path): $publicBaseUrl/$($route.Path)"
}
Write-Host "  gateway: $publicBaseUrl/mcp"
