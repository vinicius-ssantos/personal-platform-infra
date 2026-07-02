$ErrorActionPreference = "Stop"

$configPath = "opencode.json"

if (-not (Test-Path -LiteralPath $configPath)) {
    throw "$configPath not found."
}

$config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
$gateway = $config.mcp.'central-mcp-gateway'

if (-not $gateway) {
    throw "Missing mcp.central-mcp-gateway block."
}

if ($gateway.PSObject.Properties.Name -contains "headers") {
    throw "opencode.json must not contain live headers."
}

if ($gateway.url -ne "http://localhost:8040/mcp") {
    throw "Unexpected MCP URL in opencode.json: $($gateway.url)"
}

Write-Host "opencode.json OK: no committed credentials and local MCP URL is sanitized."
