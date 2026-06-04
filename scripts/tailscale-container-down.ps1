param(
    [string]$EnvFile = ".env"
)

$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

function Invoke-Compose([string[]]$Arguments, [bool]$AllowFailure = $false) {
    docker compose -f compose/docker-compose.yml --env-file $EnvFile @Arguments
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        throw "docker compose failed: $($Arguments -join ' ')"
    }
}

Write-Host "Disabling Tailscale Funnel in the container..."
Invoke-Compose @("exec", "-T", "tailscale-gateway", "tailscale", "funnel", "--https=443", "off") $true
Invoke-Compose @("exec", "-T", "tailscale-gateway", "tailscale", "funnel", "--https=8443", "off") $true
Invoke-Compose @("exec", "-T", "tailscale-gateway", "tailscale", "funnel", "--https=10000", "off") $true

Write-Host "Stopping Tailscale gateway sidecar..."
Invoke-Compose @("--profile", "tailscale", "stop", "tailscale-gateway") $true
Invoke-Compose @("--profile", "tailscale", "rm", "-f", "tailscale-gateway") $true

Write-Host "Tailscale container Funnel stopped. The tailscale-gateway-state volume was preserved."
