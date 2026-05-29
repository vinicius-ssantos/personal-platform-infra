$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
Set-Location $rootDir

$envFile = if ($env:ENV_FILE) { $env:ENV_FILE } else { ".env" }
$healthUrl = if ($env:MCP_SOCIAL_HEALTH_URL) { $env:MCP_SOCIAL_HEALTH_URL } else { "http://localhost:8080/health" }

if (-not (Test-Path -LiteralPath $envFile)) {
    Write-Error "Missing $envFile. Copy .env.example to .env and fill local secrets first."
}

docker compose --env-file $envFile -f compose/docker-compose.yml --profile social up -d mcp-social
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Checking $healthUrl"
curl.exe -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors $healthUrl
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

docker compose --env-file $envFile -f compose/docker-compose.yml --profile social ps mcp-social
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
