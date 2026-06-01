$ErrorActionPreference = "Stop"

$rootDir = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
Set-Location $rootDir

$envFile = if ($env:ENV_FILE) { $env:ENV_FILE } else { ".env" }
$baseUrl = if ($env:CENTRAL_MCP_GATEWAY_URL) { $env:CENTRAL_MCP_GATEWAY_URL.TrimEnd("/") } else { "http://localhost:8040" }

function Read-EnvValue {
    param([string]$Key)
    if (-not (Test-Path -LiteralPath $envFile)) {
        return $null
    }
    $line = Get-Content -LiteralPath $envFile |
        Where-Object { $_ -match "^$([regex]::Escape($Key))=" } |
        Select-Object -First 1
    if (-not $line) {
        return $null
    }
    return ($line -replace "^$([regex]::Escape($Key))=", "").Trim()
}

if (-not (Test-Path -LiteralPath $envFile)) {
    Write-Error "Missing $envFile. Copy .env.example to .env and fill local secrets first."
}

docker compose --env-file $envFile -f compose/docker-compose.yml --profile gateway --profile github --profile deploy --profile social --profile vos up -d central-mcp-gateway
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Checking $baseUrl/healthz"
curl.exe -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors "$baseUrl/healthz"
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host "Checking $baseUrl/readyz"
curl.exe -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors "$baseUrl/readyz"
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$bearer = Read-EnvValue "CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN"
if (-not $bearer) {
    Write-Error "CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN is missing in $envFile"
}

$initPayloadPath = Join-Path $env:TEMP "central-mcp-gateway-initialize.json"
Set-Content -LiteralPath $initPayloadPath -NoNewline -Encoding ascii -Value '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke-test","version":"1.0"}}}'

Write-Host "Checking $baseUrl/mcp initialize"
curl.exe -fsS `
    -X POST "$baseUrl/mcp" `
    -H "Authorization: Bearer $bearer" `
    -H "Content-Type: application/json" `
    --data-binary "@$initPayloadPath"
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

$payloadPath = Join-Path $env:TEMP "central-mcp-gateway-tools-list.json"
Set-Content -LiteralPath $payloadPath -NoNewline -Encoding ascii -Value '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'

Write-Host "Checking $baseUrl/mcp tools/list"
curl.exe -fsS `
    -X POST "$baseUrl/mcp" `
    -H "Authorization: Bearer $bearer" `
    -H "Content-Type: application/json" `
    --data-binary "@$payloadPath"
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

docker compose --env-file $envFile -f compose/docker-compose.yml --profile all ps central-mcp-gateway
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}
