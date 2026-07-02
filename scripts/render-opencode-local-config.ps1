param(
    [string]$EnvFile = ".env",
    [string]$BaseConfig = "opencode.json",
    [string]$OutConfig = "opencode.local.json"
)

$ErrorActionPreference = "Stop"

function Get-EnvValue {
    param(
        [string]$Path,
        [string]$Key
    )

    $line = Select-String -LiteralPath $Path -Pattern "^$Key=" | Select-Object -Last 1
    if (-not $line) {
        return ""
    }

    $value = $line.Line.Substring($Key.Length + 1).Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    return $value.Trim()
}

function Require-EnvValue {
    param(
        [string]$Path,
        [string]$Key
    )

    $value = Get-EnvValue -Path $Path -Key $Key
    if ([string]::IsNullOrWhiteSpace($value) -or $value -eq "change-me" -or $value.StartsWith("paste-")) {
        throw "$Key must be set in $Path."
    }
    return $value
}

if (-not (Test-Path -LiteralPath $EnvFile)) {
    throw "$EnvFile not found. Run: just env-init"
}

if (-not (Test-Path -LiteralPath $BaseConfig)) {
    throw "$BaseConfig not found."
}

$url = Require-EnvValue -Path $EnvFile -Key "OPENCODE_MCP_GATEWAY_URL"
$bearer = Require-EnvValue -Path $EnvFile -Key "OPENCODE_MCP_GATEWAY_BEARER_TOKEN"
$platform = Require-EnvValue -Path $EnvFile -Key "OPENCODE_MCP_GATEWAY_PLATFORM_TOKEN"
$enabledRaw = Get-EnvValue -Path $EnvFile -Key "OPENCODE_MCP_GATEWAY_ENABLED"
if ([string]::IsNullOrWhiteSpace($enabledRaw)) {
    $enabledRaw = "false"
}

switch ($enabledRaw.ToLowerInvariant()) {
    "true" { $enabled = $true }
    "1" { $enabled = $true }
    "yes" { $enabled = $true }
    "on" { $enabled = $true }
    "false" { $enabled = $false }
    "0" { $enabled = $false }
    "no" { $enabled = $false }
    "off" { $enabled = $false }
    default { throw "OPENCODE_MCP_GATEWAY_ENABLED must be true or false." }
}

$config = Get-Content -LiteralPath $BaseConfig -Raw | ConvertFrom-Json
if (-not $config.mcp) {
    $config | Add-Member -NotePropertyName mcp -NotePropertyValue ([pscustomobject]@{})
}
if (-not $config.mcp.'central-mcp-gateway') {
    $config.mcp | Add-Member -NotePropertyName 'central-mcp-gateway' -NotePropertyValue ([pscustomobject]@{})
}

$gateway = $config.mcp.'central-mcp-gateway'
$gateway.type = "remote"
$gateway.url = $url
$gateway.enabled = $enabled
$gateway.headers = [ordered]@{
    Authorization = "Bearer $bearer"
    "X-Platform-Token" = $platform
}

$json = $config | ConvertTo-Json -Depth 100
Set-Content -LiteralPath $OutConfig -Value $json -Encoding utf8

Write-Host "Rendered $OutConfig from $BaseConfig and $EnvFile."
Write-Host "Do not commit $OutConfig."
