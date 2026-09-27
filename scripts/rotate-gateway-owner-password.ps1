param(
    [string]$EnvFile = ".env"
)

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $root

if (-not (Test-Path -LiteralPath $EnvFile)) {
    throw "Missing $EnvFile."
}

$compose = @("compose", "--env-file", $EnvFile, "-f", "compose/docker-compose.yml", "--profile", "gateway")

& docker @compose up -d --wait central-mcp-gateway
if ($LASTEXITCODE -ne 0) { throw "Unable to start central-mcp-gateway." }

$passwordBytes = New-Object byte[] 32
$rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
try { $rng.GetBytes($passwordBytes) } finally { $rng.Dispose() }

$password = [BitConverter]::ToString($passwordBytes).Replace("-", "")
$passwordBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($password))
$passwordHash = ($passwordBase64 | & docker @compose exec -T central-mcp-gateway python -c "import base64, sys; from central_mcp_gateway.oauth_routes import hash_owner_password; print(hash_owner_password(base64.b64decode(sys.stdin.read()).decode()))").Trim()
if ($LASTEXITCODE -ne 0 -or $passwordHash -notmatch "^scrypt\$") {
    throw "Unable to generate the gateway owner password hash."
}

$envPath = (Resolve-Path -LiteralPath $EnvFile).Path
$envText = [System.IO.File]::ReadAllText($envPath)
$updatedText = [System.Text.RegularExpressions.Regex]::Replace(
    $envText,
    "(?m)^(CENTRAL_MCP_GATEWAY_OWNER_LOGIN_PASSWORD_HASH=).*$",
    [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $match.Groups[1].Value + "'" + $passwordHash + "'" },
    1
)
if ($updatedText -eq $envText) {
    throw "CENTRAL_MCP_GATEWAY_OWNER_LOGIN_PASSWORD_HASH was not found in $EnvFile."
}

[System.IO.File]::WriteAllText($envPath, $updatedText, [System.Text.UTF8Encoding]::new($false))

& docker @compose up -d --force-recreate --no-deps --wait central-mcp-gateway central-mcp-gateway-blue central-mcp-gateway-green
if ($LASTEXITCODE -ne 0) { throw "The gateway slots did not restart successfully." }

Set-Clipboard -Value $password
Write-Host "New gateway owner password copied to the clipboard."
