param(
    [ValidateSet("blue", "green")]
    [string]$Target,
    [string]$EnvFile = ".env"
)

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $root

if (-not (Test-Path -LiteralPath $EnvFile)) {
    throw "Missing $EnvFile. The deployment controller never creates or prints environment values."
}

$service = "central-mcp-gateway-$Target"
$port = if ($Target -eq "blue") { 8041 } else { 8042 }
$compose = @("compose", "--env-file", $EnvFile, "-f", "compose/docker-compose.yml", "--profile", "gateway", "--profile", "github", "--profile", "repo-research")

& docker @compose pull $service
if ($LASTEXITCODE -ne 0) { throw "Unable to pull $service" }
& docker @compose up -d --wait $service
if ($LASTEXITCODE -ne 0) { throw "Unable to start $service" }

$deadline = (Get-Date).AddSeconds(60)
do {
    try {
        $ready = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/readyz" -TimeoutSec 3
        if ($ready.StatusCode -eq 200) { break }
    } catch {}
    Start-Sleep -Seconds 1
} while ((Get-Date) -lt $deadline)
if (-not $ready -or $ready.StatusCode -ne 200) { throw "$service did not become ready" }

$proxyId = (& docker @compose ps -q ngrok-proxy).Trim()
if (-not $proxyId) { throw "ngrok-proxy is not running; start it before promotion" }

# Caddy reload is atomic and retains established connections on the old upstream.
$temporary = Join-Path $env:TEMP "Caddyfile.gateway-$Target"
try {
    (Get-Content "compose/Caddyfile.ngrok" -Raw).Replace("central-mcp-gateway:8080", "$service`:8080") |
        Set-Content -LiteralPath $temporary -NoNewline -Encoding ascii
    & docker cp $temporary "${proxyId}:/tmp/Caddyfile"
    if ($LASTEXITCODE -ne 0) { throw "Unable to copy Caddy configuration" }
    & docker exec $proxyId caddy reload --config /tmp/Caddyfile --adapter caddyfile
    if ($LASTEXITCODE -ne 0) { throw "Caddy reload failed; the existing route was retained" }
} finally {
    Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
}

Write-Host "Promoted $Target. Keep the previous slot running until its drain metrics reach zero."
