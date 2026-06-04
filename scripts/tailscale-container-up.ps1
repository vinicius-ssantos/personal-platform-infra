param(
    [string]$EnvFile = ".env"
)

$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

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
        Copy-Item ".env.example" $Path
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

function Invoke-Compose([string[]]$Arguments) {
    docker compose -f compose/docker-compose.yml --env-file $EnvFile @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose failed: $($Arguments -join ' ')"
    }
}

function Invoke-ComposeExec([string[]]$Arguments) {
    $output = docker compose -f compose/docker-compose.yml --env-file $EnvFile exec -T tailscale-gateway @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "docker compose exec tailscale-gateway failed: $($Arguments -join ' ')"
    }
    $output
}

function Get-TailscaleContainerPublicUrl() {
    $statusRaw = Invoke-ComposeExec @("tailscale", "status", "--json")
    $status = $statusRaw | ConvertFrom-Json
    $dnsName = [string]$status.Self.DNSName
    if ([string]::IsNullOrWhiteSpace($dnsName)) {
        throw "Tailscale container DNSName is empty. Check TAILSCALE_AUTHKEY, MagicDNS, and HTTPS certificates in your tailnet."
    }

    "https://$($dnsName.TrimEnd('.'))"
}

if (-not (Test-Path $EnvFile)) {
    Copy-Item ".env.example" $EnvFile
}

$currentEnv = Read-EnvMap $EnvFile

if (Test-Placeholder $currentEnv["TAILSCALE_AUTHKEY"]) {
    throw "TAILSCALE_AUTHKEY is missing. Generate an auth key at https://login.tailscale.com/admin/settings/keys and set it in .env."
}

if (Test-Placeholder $currentEnv["TAILSCALE_CONTAINER_HOSTNAME"]) {
    Set-EnvValues $EnvFile @{ TAILSCALE_CONTAINER_HOSTNAME = "personal-platform-gateway" }
    $currentEnv = Read-EnvMap $EnvFile
}

$httpsPort = $currentEnv["TAILSCALE_CONTAINER_HTTPS_PORT"]
if (Test-Placeholder $httpsPort) {
    $httpsPort = "443"
    Set-EnvValues $EnvFile @{ TAILSCALE_CONTAINER_HTTPS_PORT = $httpsPort }
}

$profiles = @("--profile", "gateway", "--profile", "github", "--profile", "deploy", "--profile", "social", "--profile", "vos", "--profile", "tailscale")

Write-Host "Pulling latest gateway and Tailscale images..."
Invoke-Compose @("pull", "central-mcp-gateway", "tailscale-gateway")

Write-Host "Starting Compose gateway runtime with Tailscale sidecar..."
Invoke-Compose ($profiles + @("up", "-d", "--wait", "central-mcp-gateway", "tailscale-gateway"))

Write-Host "Discovering Tailscale container public URL..."
$publicBaseUrl = Get-TailscaleContainerPublicUrl
Write-Host "TAILSCALE_CONTAINER_PUBLIC_URL=$publicBaseUrl"

Set-EnvValues $EnvFile @{
    TAILSCALE_CONTAINER_PUBLIC_URL = $publicBaseUrl
    CENTRAL_MCP_GATEWAY_PUBLIC_URL = $publicBaseUrl
}

Write-Host "Recreating central MCP gateway with container Funnel OAuth URL..."
Invoke-Compose ($profiles + @("up", "-d", "--force-recreate", "--wait", "central-mcp-gateway", "tailscale-gateway"))

Write-Host "Starting Tailscale Funnel in the container..."
Invoke-ComposeExec @("tailscale", "funnel", "--bg", "--yes", "--https=$httpsPort", "http://127.0.0.1:8080") | Out-Host

Write-Host "Validating local gateway..."
Invoke-RestMethod -Uri "http://127.0.0.1:8040/healthz" -TimeoutSec 20 | Out-Null

Write-Host "Validating public gateway through Tailscale container..."
Invoke-RestMethod -Uri "$publicBaseUrl/healthz" -TimeoutSec 45 | Out-Null
Invoke-RestMethod -Uri "$publicBaseUrl/.well-known/oauth-authorization-server" -Headers @{ Accept = "application/json" } -TimeoutSec 45 | Out-Null

Write-Host ""
Write-Host "Tailscale container Funnel environment is ready."
Write-Host "ChatGPT MCP URL: $publicBaseUrl/mcp"
Write-Host "Admin UI URL: $publicBaseUrl/admin/ui/login"
