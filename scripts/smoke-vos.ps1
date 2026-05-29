$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
Set-Location $rootDir

$envFile = if ($env:ENV_FILE) { $env:ENV_FILE } else { ".env" }
$mcpHealthUrl = if ($env:VOS_STUDIO_MCP_HEALTH_URL) { $env:VOS_STUDIO_MCP_HEALTH_URL } else { "http://localhost:8020/health" }
$bffHealthUrl = if ($env:VOS_STUDIO_BFF_HEALTH_URL) { $env:VOS_STUDIO_BFF_HEALTH_URL } else { "http://localhost:8030/healthz" }

if (-not (Test-Path -LiteralPath $envFile)) {
    Write-Error "Missing $envFile. Copy .env.example to .env and fill local secrets first."
}

docker compose --env-file $envFile -f compose/docker-compose.yml --profile vos up -d vos-studio-mcp vos-studio-bff
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Checking VOS MCP at $mcpHealthUrl"
curl.exe -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors $mcpHealthUrl
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Checking VOS BFF at $bffHealthUrl"
curl.exe -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors $bffHealthUrl
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

docker compose --env-file $envFile -f compose/docker-compose.yml --profile vos ps vos-studio-mcp vos-studio-bff
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
