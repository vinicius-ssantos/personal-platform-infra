param(
    [switch]$Quiet,
    [ValidateRange(1, 365)]
    [int]$Days = 14
)

$ErrorActionPreference = "Stop"
$ComposeProject = "compose"
$K3dContainer = "k3d-personal-platform-server-0"
$GatewayContainer = "compose-central-mcp-gateway-1"

function Get-DockerLines([string[]]$Arguments) {
    try {
        return @(& docker @Arguments 2>$null | Where-Object { $_ })
    }
    catch {
        return @()
    }
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Warning "Docker is not installed; local runtime status is unavailable."
    exit 0
}

$composeContainers = Get-DockerLines @(
    "ps", "--filter", "label=com.docker.compose.project=$ComposeProject",
    "--format", "{{.Names}}|{{.Image}}|{{.Status}}"
)
$k3dContainers = Get-DockerLines @(
    "ps", "--filter", "name=$K3dContainer", "--format", "{{.Names}}|{{.Status}}"
)

if ($Quiet) {
    if ($composeContainers.Count -gt 0 -and $k3dContainers.Count -gt 0) {
        Write-Warning "Compose and k3d are both active. This can duplicate platform workloads; run 'just runtime-status' for details."
    }
    exit 0
}

Write-Host "Compose platform containers: $($composeContainers.Count)"
if ($composeContainers.Count -eq 0) {
    Write-Host "  none"
}
else {
    $composeContainers | ForEach-Object { Write-Host "  $_" }
}

$k3dCount = if ($k3dContainers.Count -gt 0) { 1 } else { 0 }
Write-Host "k3d personal-platform: $k3dCount"
if ($k3dContainers.Count -gt 0) {
    $k3dContainers | ForEach-Object { Write-Host "  $_" }
}

if ($composeContainers.Count -gt 0 -and $k3dContainers.Count -gt 0) {
    Write-Warning "Both runtimes are active. Prefer Compose for daily work and k3d only while validating Kubernetes manifests."
}

if (-not ($composeContainers | Where-Object { $_ -like "$GatewayContainer|*" })) {
    Write-Host "Gateway audit report: unavailable (gateway container is not running)."
    exit 0
}

$auditProgram = @'
import sqlite3
import sys

days = int(sys.argv[1])
connection = sqlite3.connect("/data/audit.db")
expected_upstreams = ("github", "deploy", "social", "vos", "sandbox", "repo-research", "higgsfield")
summary = {
    upstream: (events, last_use, latency)
    for upstream, events, last_use, latency in connection.execute(
    """
    select coalesce(upstream_service, 'unassigned'), count(*), max(timestamp), round(avg(latency_ms), 1)
    from audit_events
    where timestamp >= datetime('now', ?)
    group by coalesce(upstream_service, 'unassigned')
    order by count(*) desc
    """, (f"-{days} days",)
    )
}
for upstream in expected_upstreams:
    events, last_use, latency = summary.get(upstream, (0, "-", "-"))
    classification = "no-observed-use" if events == 0 else "occasional" if events < 25 else "active"
    print(f"UPSTREAM|{upstream}|{classification}|{events}|{last_use}|{latency}")
for upstream in ("gateway", "unassigned"):
    if upstream in summary:
        events, last_use, latency = summary[upstream]
        print(f"UPSTREAM|{upstream}|active|{events}|{last_use}|{latency}")
print("TOP_TOOLS")
for upstream, tool, events, last_use in connection.execute(
    """
    select coalesce(upstream_service, 'unassigned'), coalesce(public_tool_name, 'unassigned'), count(*), max(timestamp)
    from audit_events
    where timestamp >= datetime('now', ?)
    group by upstream_service, public_tool_name
    order by count(*) desc
    limit 20
    """, (f"-{days} days",)
):
    print(f"TOOL|{upstream}|{tool}|{events}|{last_use}")
'@
$auditProgramBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($auditProgram))
$auditQuery = "import base64; exec(base64.b64decode('$auditProgramBase64'))"

$auditRows = @(& docker exec $GatewayContainer /app/.venv/bin/python -c $auditQuery $Days 2>$null | Where-Object { $_ })
if ($LASTEXITCODE -ne 0) {
    $auditRows = @()
}

if ($auditRows.Count -eq 0) {
    Write-Host "Gateway audit report: no events or audit database unavailable."
    exit 0
}

Write-Host "Gateway audit report (last $Days days; payloads are excluded):"
Write-Host "  upstream rows: UPSTREAM | name | classification | events | last use (UTC) | avg latency ms"
Write-Host "  tool rows: TOOL | upstream | public tool | events | last use (UTC)"
$auditRows | ForEach-Object { Write-Host "  $_" }
