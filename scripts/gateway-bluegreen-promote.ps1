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

$stateDirectory = Join-Path $env:LOCALAPPDATA "personal-platform"
New-Item -ItemType Directory -Force -Path $stateDirectory | Out-Null
$statePath = Join-Path $stateDirectory "gateway-slot.json"
$temporary = "$statePath.tmp"
@{ slot = $Target } | ConvertTo-Json -Compress | Set-Content -LiteralPath $temporary -NoNewline -Encoding ascii
Move-Item -LiteralPath $temporary -Destination $statePath -Force

Write-Host "Promoted $Target. New wake-proxy requests use this slot; keep the previous slot running until drain metrics reach zero."
