param(
    [string]$EnvFile = ".env",
    [switch]$ForceRefresh
)

$ErrorActionPreference = "Stop"

$Root = Resolve-Path (Join-Path $PSScriptRoot "..")
Set-Location $Root

$Services = @(
    @{ Env = "GITHUB_MCP_PUBLIC_URL"; Name = "github-mcp"; Port = 8765; HealthPath = "/healthz" },
    @{ Env = "DEPLOY_MCP_PUBLIC_URL"; Name = "deploy-mcp"; Port = 8001; HealthPath = "/healthz" },
    @{ Env = "SOCIAL_MCP_PUBLIC_URL"; Name = "social-mcp"; Port = 8080; HealthPath = "/health" },
    @{ Env = "GITHUB_BFF_PUBLIC_URL"; Name = "github-bff"; Port = 8010; HealthPath = "/healthz" },
    @{ Env = "VOS_MCP_PUBLIC_URL"; Name = "vos-mcp"; Port = 8020; HealthPath = "/health" },
    @{ Env = "VOS_BFF_PUBLIC_URL"; Name = "vos-bff"; Port = 8030; HealthPath = "/healthz" },
    @{ Env = "CENTRAL_MCP_GATEWAY_PUBLIC_URL"; Name = "central-mcp-gateway"; Port = 8040; HealthPath = "/healthz" }
)

function New-HexToken([int]$Bytes = 32) {
    $buffer = New-Object byte[] $Bytes
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::Create()
    try {
        $rng.GetBytes($buffer)
    }
    finally {
        $rng.Dispose()
    }

    -join ($buffer | ForEach-Object { $_.ToString("x2") })
}

function Get-CommandPath([string]$Name) {
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue
    if ($cmd) {
        return $cmd.Source
    }

    if ($Name -eq "cloudflared") {
        $candidate = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Recurse -Filter cloudflared.exe -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($candidate) {
            return $candidate.FullName
        }
    }

    throw "$Name not found in PATH"
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

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Resolve-Path $Path), (($updated -join "`n") + "`n"), $utf8NoBom)
}

function Stop-ExistingQuickTunnels {
    $ports = $Services | ForEach-Object { $_.Port }
    $processes = Get-CimInstance Win32_Process -Filter "name = 'cloudflared.exe'" -ErrorAction SilentlyContinue

    foreach ($process in $processes) {
        foreach ($port in $ports) {
            if ($process.CommandLine -like "*tunnel*--url*localhost:$port*") {
                Stop-Process -Id $process.ProcessId -Force -ErrorAction SilentlyContinue
                break
            }
        }
    }
}

function Start-QuickTunnel([string]$Cloudflared, [hashtable]$Service, [string]$LogDir) {
    $out = Join-Path $LogDir "$($Service.Name).out.log"
    $err = Join-Path $LogDir "$($Service.Name).err.log"
    Remove-Item $out, $err -Force -ErrorAction SilentlyContinue

    Start-Process `
        -FilePath $Cloudflared `
        -ArgumentList @("tunnel", "--url", "http://localhost:$($Service.Port)", "--no-autoupdate") `
        -WindowStyle Hidden `
        -RedirectStandardOutput $out `
        -RedirectStandardError $err

    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $err) {
            $text = Get-Content $err -Raw
            if (-not [string]::IsNullOrWhiteSpace($text)) {
                if ($text -match "429 Too Many Requests|error code: 1015") {
                    throw "Cloudflare Quick Tunnel rate limit reached while creating $($Service.Name). Wait a few minutes before retrying, or keep existing healthy URLs by running quick-tunnel-up instead of quick-tunnel-refresh."
                }

                $match = [regex]::Match($text, "https://[-a-z0-9]+\.trycloudflare\.com")
                if ($match.Success) {
                    return $match.Value
                }
            }
        }
        Start-Sleep -Milliseconds 500
    }

    throw "Timed out waiting for quick tunnel URL for $($Service.Name). Check $err"
}

Write-Host "Checking required tools..."
$Cloudflared = Get-CommandPath "cloudflared"
Get-CommandPath "docker" | Out-Null

docker version | Out-Null

if (-not (Test-Path $EnvFile)) {
    Copy-Item ".env.quick-tunnel.example" $EnvFile
}

$currentEnv = Read-EnvMap $EnvFile
$initialValues = @{
    DOMAIN = "trycloudflare.com"
}

if (Test-Placeholder $currentEnv["GITHUB_TOKEN"]) {
    $ghToken = (& gh auth token 2>$null).Trim()
    if (Test-Placeholder $ghToken) {
        throw "GITHUB_TOKEN is missing and gh auth token is not available. Run gh auth login or set GITHUB_TOKEN in .env."
    }
    $initialValues["GITHUB_TOKEN"] = $ghToken
}

foreach ($key in @("MCP_BEARER_TOKEN", "MCP_SERVER_API_KEY", "SOCIAL_MCP_ACCESS_TOKEN", "PUBLIC_EDGE_TOKEN", "CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN", "CENTRAL_MCP_GATEWAY_SESSION_SECRET", "CENTRAL_MCP_GATEWAY_ADMIN_TOKEN")) {
    if (Test-Placeholder $currentEnv[$key]) {
        $initialValues[$key] = New-HexToken
    }
}

if (Test-Placeholder $currentEnv["CENTRAL_MCP_GATEWAY_OAUTH_ALLOWED_REDIRECT_URIS"]) {
    $initialValues["CENTRAL_MCP_GATEWAY_OAUTH_ALLOWED_REDIRECT_URIS"] = "http://localhost:3000/oauth/callback,https://chat.openai.com/aip/oauth/callback"
}

Set-EnvValues $EnvFile $initialValues

Write-Host "Pulling latest Compose images..."
docker compose -f compose/docker-compose.yml --env-file $EnvFile --profile all pull --ignore-pull-failures

Write-Host "Starting local Compose services..."
docker compose -f compose/docker-compose.yml --env-file $EnvFile --profile all up -d --wait

Write-Host "Validating local health checks..."
just smoke-all

if (-not $ForceRefresh) {
    Write-Host "Checking existing public URLs..."
    & bash scripts/status-public.sh
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "Existing quick tunnel URLs are healthy; keeping them."
        exit 0
    }

    Write-Host "Existing public URLs are missing or unhealthy; creating fresh quick tunnels..."
}

Write-Host "Restarting quick tunnels..."
$LogDir = Join-Path $Root ".tmp-cloudflared"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
Stop-ExistingQuickTunnels
Start-Sleep -Seconds 2

$publicUrls = @{}
foreach ($service in $Services) {
    $url = Start-QuickTunnel $Cloudflared $service $LogDir
    $publicUrls[$service.Env] = $url
    Write-Host "$($service.Env)=$url"
}

Set-EnvValues $EnvFile $publicUrls

Write-Host "Restarting central MCP gateway with public OAuth URL..."
docker compose -f compose/docker-compose.yml --env-file $EnvFile --profile all up -d --force-recreate central-mcp-gateway

Write-Host "Validating public health checks..."
just status-public

Write-Host ""
Write-Host "Quick tunnel environment is ready. Current public URLs:"
foreach ($service in $Services) {
    Write-Host "$($service.Name): $($publicUrls[$service.Env])"
}
