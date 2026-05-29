$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
Set-Location $rootDir

$envFile = if ($env:ENV_FILE) { $env:ENV_FILE } else { ".env" }
$healthUrl = if ($env:GITHUB_UNIFIED_MCP_BFF_HEALTH_URL) { $env:GITHUB_UNIFIED_MCP_BFF_HEALTH_URL } else { "http://localhost:8010/healthz" }
$mcpHealthUrl = if ($env:GITHUB_UNIFIED_MCP_HEALTH_URL) { $env:GITHUB_UNIFIED_MCP_HEALTH_URL } else { "http://localhost:8765/healthz" }

if (-not (Test-Path -LiteralPath $envFile)) {
    Write-Error "Missing $envFile. Copy .env.example to .env and fill local secrets first."
}

docker compose --env-file $envFile -f compose/docker-compose.yml --profile github --profile github-bff up -d github-unified-mcp github-unified-mcp-bff
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Checking upstream MCP at $mcpHealthUrl"
curl.exe -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors $mcpHealthUrl
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Checking $healthUrl"
curl.exe -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors $healthUrl
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

docker compose --env-file $envFile -f compose/docker-compose.yml --profile github --profile github-bff ps github-unified-mcp github-unified-mcp-bff
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
