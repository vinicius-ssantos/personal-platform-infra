#!/usr/bin/env bash
set -euo pipefail

compose_project="compose"
k3d_container="k3d-personal-platform-server-0"
gateway_container="compose-central-mcp-gateway-1"
days="${1:-14}"

if ! [[ "$days" =~ ^[1-9][0-9]*$ ]] || (( days > 365 )); then
  echo "Usage: $0 [days: 1-365]" >&2
  exit 2
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "WARNING: Docker is not installed; local runtime status is unavailable." >&2
  exit 0
fi

compose_containers="$(docker ps --filter "label=com.docker.compose.project=${compose_project}" --format '{{.Names}}|{{.Image}}|{{.Status}}' 2>/dev/null || true)"
k3d_containers="$(docker ps --filter "name=${k3d_container}" --format '{{.Names}}|{{.Status}}' 2>/dev/null || true)"

echo "Compose platform containers: $(printf '%s\n' "$compose_containers" | sed '/^$/d' | wc -l | tr -d ' ')"
if [[ -n "$compose_containers" ]]; then
  printf '%s\n' "$compose_containers" | sed 's/^/  /'
else
  echo "  none"
fi

if [[ -n "$k3d_containers" ]]; then
  echo "k3d personal-platform: 1"
  printf '%s\n' "$k3d_containers" | sed 's/^/  /'
else
  echo "k3d personal-platform: 0"
fi

if [[ -n "$compose_containers" && -n "$k3d_containers" ]]; then
  echo "WARNING: Both runtimes are active. Prefer Compose for daily work and k3d only while validating Kubernetes manifests." >&2
fi

if ! printf '%s\n' "$compose_containers" | cut -d'|' -f1 | grep -Fxq "$gateway_container"; then
  echo "Gateway audit report: unavailable (gateway container is not running)."
  exit 0
fi

audit_program="$(cat <<'PY'
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
PY
)"
audit_base64="$(printf '%s' "$audit_program" | base64 | tr -d '\n')"
audit_query="import base64; exec(base64.b64decode('${audit_base64}'))"

if ! audit_rows="$(docker exec "$gateway_container" /app/.venv/bin/python -c "$audit_query" "$days" 2>/dev/null)"; then
  echo "Gateway audit report: audit database unavailable."
  exit 0
fi

if [[ -z "$audit_rows" ]]; then
  echo "Gateway audit report: no events."
  exit 0
fi

echo "Gateway audit report (last ${days} days; payloads are excluded):"
echo "  upstream rows: UPSTREAM | name | classification | events | last use (UTC) | avg latency ms"
echo "  tool rows: TOOL | upstream | public tool | events | last use (UTC)"
printf '%s\n' "$audit_rows" | sed 's/^/  /'
