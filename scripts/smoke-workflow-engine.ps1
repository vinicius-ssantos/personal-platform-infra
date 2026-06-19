$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
Set-Location $rootDir

$envFile = if ($env:ENV_FILE) { $env:ENV_FILE } else { ".env" }
$healthUrl = if ($env:WORKFLOW_ENGINE_HEALTH_URL) { $env:WORKFLOW_ENGINE_HEALTH_URL } else { "http://localhost:8081/actuator/health" }

if (-not (Test-Path -LiteralPath $envFile)) {
    Write-Error "Missing $envFile. Copy .env.example to .env and fill local secrets first."
}

docker compose --env-file $envFile -f compose/docker-compose.yml --profile workflow-engine up -d workflow-engine
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Checking $healthUrl"
curl.exe -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors $healthUrl
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

docker compose --env-file $envFile -f compose/docker-compose.yml --profile workflow-engine ps workflow-engine
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
