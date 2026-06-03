param(
    [string]$EnvFile = ".env",
    [int]$LocalPort = 8040,
    [int]$HttpsPort = 443
)

$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

function Get-CommandPath([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    if ($Name -eq "tailscale") {
        $candidates = @(
            "$env:ProgramFiles\Tailscale\tailscale.exe",
            "${env:ProgramFiles(x86)}\Tailscale\tailscale.exe"
        )
        foreach ($candidate in $candidates) {
            if ($candidate -and (Test-Path $candidate)) {
                return $candidate
            }
        }
    }

    throw "$Name not found in PATH. Install Tailscale and make sure the CLI is available."
}

function New-HexToken([int]$Bytes = 32) {
    $buffer = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $rng.GetBytes($buffer)
    }
    finally {
        $rng.Dispose()
    }

    -join ($buffer | ForEach-Object { $_.ToString("x2") })
}

function Read-EnvMap([string]$Path) {
    $map = [ordered]@{}
    if (-not (Test-Path $Path)) {
        return $map
    }

    foreach ($line in Get-Content $Path) {
        if ($line -match "^\s*#" -or $line -match "^\s*$") {
            continue
        }
        if ($line -match "^([^=]+)=(.*)$") {
            $map[$matches[1]] = $matches[2].TrimEnd("`r")
        }
    }
    $map
}

function Test-Placeholder([string]$Value) {
    [string]::IsNullOrWhiteSpace($Value) -or
    $Value -eq "change-me" -or
    $Value -eq "changeme" -or
    $Value.StartsWith("paste-") -or
    $Value.StartsWith("replace-with")
}

function Set-EnvValues([string]$Path, [hashtable]$Values) {
    if (-not (Test-Path $Path)) {
        Copy-Item ".env.quick-tunnel.example" $Path
    }

    $seen = @{}
    $lines = Get-Content $Path
    $updated = foreach ($line in $lines) {
        if ($line -match "^([^#][^=]+)=") {
            $key = $matches[1]
            if ($Values.ContainsKey($key)) {
                $seen[$key] = $true
                "$key=$($Values[$key])"
            }
            else {
                $line.TrimEnd("`r")
            }
        }
        else {
            $line.TrimEnd("`r")
        }
    }

    foreach ($key in $Values.Keys) {
        if (-not $seen.ContainsKey($key)) {
            $updated += "$key=$($Values[$key])"
        }
    }

    [System.IO.File]::WriteAllText((Resolve-Path $Path), (($updated -join "`n") + "`n"), [System.Text.UTF8Encoding]::new($false))
}

function Invoke-Checked([string]$File, [string[]]$Arguments) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Command failed with exit code ${LASTEXITCODE}: $File $($Arguments -join ' ')"
    }
}

function Get-TailscalePublicUrl([string]$Tailscale) {
    $statusJson = & $Tailscale status --json | ConvertFrom-Json
    if (-not $statusJson.Self) {
        throw "Tailscale is not logged in or status did not include Self. Run: tailscale up"
    }

    $dnsName = [string]$statusJson.Self.DNSName
    if ([string]::IsNullOrWhiteSpace($dnsName)) {
        throw "Tailscale DNSName is empty. Enable MagicDNS and HTTPS certificates for your tailnet before using Funnel."
    }

    "https://$($dnsName.TrimEnd('.'))"
}

Write-Host "Checking required tools..."
$Docker = Get-CommandPath "docker"
$Tailscale = Get-CommandPath "tailscale"
Invoke-Checked $Docker @("version")
Invoke-Checked $Tailscale @("version")

if (-not (Test-Path $EnvFile)) {
    Copy-Item ".env.quick-tunnel.example" $EnvFile
}

$currentEnv = Read-EnvMap $EnvFile
$initialValues = @{}

if (Test-Placeholder $currentEnv["GITHUB_TOKEN"]) {
    $ghToken = (& gh auth token 2>$null).Trim()
    if (Test-Placeholder $ghToken) {
        throw "GITHUB_TOKEN is missing and gh auth token is not available. Run gh auth login or set GITHUB_TOKEN in .env."
    }
    $initialValues["GITHUB_TOKEN"] = $ghToken
}

foreach ($key in @("MCP_BEARER_TOKEN", "MCP_SERVER_API_KEY", "SOCIAL_MCP_ACCESS_TOKEN", "PUBLIC_EDGE_TOKEN", "CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN", "CENTRAL_MCP_GATEWAY_SESSION_SECRET")) {
    if (Test-Placeholder $currentEnv[$key]) {
        $initialValues[$key] = New-HexToken
    }
}

if (Test-Placeholder $currentEnv["CENTRAL_MCP_GATEWAY_OAUTH_ALLOWED_REDIRECT_URIS"]) {
    $initialValues["CENTRAL_MCP_GATEWAY_OAUTH_ALLOWED_REDIRECT_URIS"] = "http://localhost:3000/oauth/callback,https://chat.openai.com/aip/oauth/callback"
}

if ($initialValues.Count -gt 0) {
    Set-EnvValues $EnvFile $initialValues
    $currentEnv = Read-EnvMap $EnvFile
}

Write-Host "Starting Compose gateway runtime..."
docker compose -f compose/docker-compose.yml --env-file $EnvFile --profile gateway --profile github --profile deploy --profile social --profile vos up -d --wait central-mcp-gateway
if ($LASTEXITCODE -ne 0) {
    throw "docker compose failed to start central-mcp-gateway runtime."
}

Write-Host "Checking local gateway..."
Invoke-RestMethod -Uri "http://127.0.0.1:${LocalPort}/healthz" -TimeoutSec 15 | Out-Null

$publicBaseUrl = Get-TailscalePublicUrl $Tailscale
Write-Host "TAILSCALE_FUNNEL_PUBLIC_URL=$publicBaseUrl"

Write-Host "Starting Tailscale Funnel..."
Invoke-Checked $Tailscale @("funnel", "--bg", "--yes", "--https=$HttpsPort", "127.0.0.1:$LocalPort")

Set-EnvValues $EnvFile @{
    TAILSCALE_FUNNEL_PUBLIC_URL = $publicBaseUrl
    TAILSCALE_FUNNEL_HTTPS_PORT = "$HttpsPort"
    CENTRAL_MCP_GATEWAY_PUBLIC_URL = $publicBaseUrl
}
$currentEnv = Read-EnvMap $EnvFile
$env:TAILSCALE_FUNNEL_PUBLIC_URL = $publicBaseUrl
$env:TAILSCALE_FUNNEL_HTTPS_PORT = "$HttpsPort"
$env:CENTRAL_MCP_GATEWAY_PUBLIC_URL = $publicBaseUrl

Write-Host "Restarting central MCP gateway with public OAuth URL..."
docker compose -f compose/docker-compose.yml --env-file $EnvFile --profile gateway --profile github --profile deploy --profile social --profile vos up -d --force-recreate --wait central-mcp-gateway
if ($LASTEXITCODE -ne 0) {
    throw "docker compose failed to recreate central-mcp-gateway."
}

Write-Host "Validating gateway..."
$bearer = $currentEnv["CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN"]
$headers = @{
    Authorization = "Bearer $bearer"
    Accept = "application/json"
}

$body = '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
$publicValidationOk = $false

try {
    Invoke-RestMethod -Uri "$publicBaseUrl/healthz" -TimeoutSec 30 | Out-Null
    Invoke-RestMethod -Uri "$publicBaseUrl/.well-known/oauth-authorization-server" -Headers @{ Accept = "application/json" } -TimeoutSec 30 | Out-Null
    $tools = Invoke-RestMethod -Uri "$publicBaseUrl/mcp" -Method Post -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec 30
    $publicValidationOk = $true
}
catch {
    Write-Warning "Public self-check through $publicBaseUrl failed from this workstation. This can happen when Windows resolves the Funnel name to the local Tailscale IP and cannot hairpin to itself."
    Write-Warning "Checking Funnel status and local gateway instead. Use ChatGPT or another external client for the final public test."

    $funnelStatus = & $Tailscale funnel status --json | ConvertFrom-Json
    $hostKey = "$($publicBaseUrl -replace '^https://', ''):$HttpsPort"
    if (-not $funnelStatus.AllowFunnel.$hostKey) {
        throw "Tailscale Funnel is not active for $hostKey."
    }

    Invoke-RestMethod -Uri "http://127.0.0.1:${LocalPort}/healthz" -TimeoutSec 15 | Out-Null
    $tools = Invoke-RestMethod -Uri "http://127.0.0.1:${LocalPort}/mcp" -Method Post -Headers $headers -ContentType "application/json" -Body $body -TimeoutSec 20
}

Write-Host ""
Write-Host "Tailscale Funnel environment is ready."
Write-Host "ChatGPT MCP URL: $publicBaseUrl/mcp"
if (-not $publicValidationOk) {
    Write-Host "Public validation from this workstation was skipped after a local hairpin failure; Funnel status and local gateway validation passed."
}
Write-Host "Tools:"
$tools.result.tools | ForEach-Object { Write-Host "  - $($_.name)" }
