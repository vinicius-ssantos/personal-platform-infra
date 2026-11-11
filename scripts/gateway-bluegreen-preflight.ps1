#Requires -Version 5.1
<#
.SYNOPSIS
  Read-only fail-closed preflight for the central Gateway blue/green release.
.DESCRIPTION
  Does not pull, start, restart, switch, deploy, approve or log credentials.
  An actual promotion is a separate operator-controlled step. This script
  deliberately refuses to approve a locally modified deployment compose file.
#>
[CmdletBinding()]
param(
    [ValidateSet("blue", "green")]
    [string]$Target = "green",

    [ValidatePattern('^v[0-9]+\.[0-9]+\.[0-9]+$')]
    [string]$CandidateTag = "v0.47.0",

    [ValidateSet("blue", "green")]
    [string]$ExpectedActive = "blue",

    [string]$InfraRoot = (Join-Path $PSScriptRoot ".."),

    [string]$EnvFile = ".env"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-GatewayVersion {
    param([string]$Slot)
    $port = if ($Slot -eq "blue") { 8041 } else { 8042 }
    try {
        $response = Invoke-RestMethod -Uri "http://127.0.0.1:$port/readyz" -TimeoutSec 4
        if ($response.status -ne "ready" -or -not $response.runtime.version) {
            throw "unhealthy"
        }
        return [string]$response.runtime.version
    } catch {
        throw "GATEWAY_$($Slot.ToUpperInvariant())_NOT_READY"
    }
}

function Get-ComposeImages {
    param([string]$Root, [string]$ResolvedEnv)
    $params = @(
        "compose", "--env-file", $ResolvedEnv,
        "-f", (Join-Path $Root "compose/docker-compose.yml"),
        "--profile", "gateway", "--profile", "github",
        "--profile", "repo-research", "config", "--format", "json"
    )
    $raw = & docker @params 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $raw) {
        throw "COMPOSE_CONFIG_INVALID"
    }
    try {
        $cfg = ($raw | Out-String | ConvertFrom-Json)
        $images = @{}
        foreach ($slot in @("blue", "green")) {
            $service = "central-mcp-gateway-$slot"
            $entry = $cfg.services.PSObject.Properties[$service]
            if ($null -eq $entry -or -not $entry.Value.image) {
                throw "COMPOSE_GATEWAY_SERVICE_MISSING"
            }
            $images[$slot] = [string]$entry.Value.image
        }
        return $images
    } catch {
        throw "COMPOSE_CONFIG_INVALID"
    }
}

try {
    $root = (Resolve-Path -LiteralPath $InfraRoot).Path
    $envPath = if ([System.IO.Path]::IsPathRooted($EnvFile)) {
        $EnvFile
    } else {
        Join-Path $root $EnvFile
    }
    if (-not (Test-Path -LiteralPath $envPath -PathType Leaf)) {
        throw "ENV_FILE_MISSING"
    }

    $stateFile = Join-Path $env:LOCALAPPDATA "personal-platform/gateway-slot.json"
    if (-not (Test-Path -LiteralPath $stateFile -PathType Leaf)) {
        throw "ACTIVE_SLOT_STATE_MISSING"
    }
    $current = Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json
    if ($current.slot -notin @("blue", "green")) {
        throw "ACTIVE_SLOT_STATE_INVALID"
    }
    Write-Output "ACTIVE_SLOT=$($current.slot)"
    if ($current.slot -ne $ExpectedActive -or $Target -eq $ExpectedActive) {
        throw "UNEXPECTED_ACTIVE_OR_TARGET_SLOT"
    }

    $versions = @{}
    foreach ($slot in @("blue", "green")) {
        $versions[$slot] = Get-GatewayVersion -Slot $slot
        Write-Output "$($slot.ToUpperInvariant())_READY_VERSION=$($versions[$slot])"
    }

    $images = Get-ComposeImages -Root $root -ResolvedEnv $envPath
    $prefix = "ghcr.io/vinicius-ssantos/central-mcp-gateway:"
    foreach ($slot in @("blue", "green")) {
        $expected = $prefix + "v" + $versions[$slot]
        if ($images[$slot] -ne $expected) {
            throw "RUNNING_VERSION_AND_COMPOSE_IMAGE_MISMATCH"
        }
    }

    # Local deployment changes may alter mounts, ports and security policy.
    $dirty = @(& git -C $root status --porcelain -- compose/docker-compose.yml scripts/gateway-bluegreen-promote.ps1)
    if ($LASTEXITCODE -ne 0 -or $dirty.Count -gt 0) {
        throw "DEPLOYMENT_CONFIG_HAS_UNREVIEWED_LOCAL_CHANGES"
    }

    # Docker Compose honors process-level environment overrides. Resolve the
    # candidate into memory only, never modify .env or print the full config.
    $key = "CENTRAL_MCP_GATEWAY_$($Target.ToUpperInvariant())_IMAGE"
    $previous = [Environment]::GetEnvironmentVariable($key, "Process")
    try {
        [Environment]::SetEnvironmentVariable(
            $key, ($prefix + $CandidateTag), "Process"
        )
        $candidate = Get-ComposeImages -Root $root -ResolvedEnv $envPath
    } finally {
        [Environment]::SetEnvironmentVariable($key, $previous, "Process")
    }
    if ($candidate[$Target] -ne ($prefix + $CandidateTag)) {
        throw "CANDIDATE_IMAGE_RESOLUTION_MISMATCH"
    }
    if ($candidate[$ExpectedActive] -ne $images[$ExpectedActive]) {
        throw "ACTIVE_SLOT_WOULD_CHANGE"
    }

    Write-Output "CANDIDATE_TARGET=$Target"
    Write-Output "CANDIDATE_TAG=$CandidateTag"
    Write-Output "PREFLIGHT=PASS_READ_ONLY"
    Write-Output "REQUIRES_SEPARATE_OPERATOR_APPROVAL=TRUE"
    exit 0
} catch {
    # Print controlled codes only; never raw environment, host paths or exceptions.
    $known = @(
        "ENV_FILE_MISSING", "ACTIVE_SLOT_STATE_MISSING",
        "ACTIVE_SLOT_STATE_INVALID", "UNEXPECTED_ACTIVE_OR_TARGET_SLOT",
        "GATEWAY_BLUE_NOT_READY", "GATEWAY_GREEN_NOT_READY",
        "COMPOSE_CONFIG_INVALID", "RUNNING_VERSION_AND_COMPOSE_IMAGE_MISMATCH",
        "DEPLOYMENT_CONFIG_HAS_UNREVIEWED_LOCAL_CHANGES",
        "CANDIDATE_IMAGE_RESOLUTION_MISMATCH", "ACTIVE_SLOT_WOULD_CHANGE"
    )
    $code = if ($_.Exception.Message -in $known) { $_.Exception.Message } else { "UNEXPECTED_PREFLIGHT_ERROR" }
    Write-Output "PREFLIGHT=BLOCKED"
    Write-Output "REASON=$code"
    exit 2
}
