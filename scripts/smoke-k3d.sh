#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CLUSTER_NAME="personal-platform"
TIMEOUT="${K3D_SMOKE_TIMEOUT:-120s}"

# Prerequisites check
for cmd in docker k3d kubectl curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "ERROR: $cmd is not installed or not in PATH." >&2
    exit 1
  fi
done

if ! docker info >/dev/null 2>&1; then
  echo "ERROR: Docker is not running or current user lacks access." >&2
  exit 1
fi

# Warn if no .env exists (services may start with missing env vars)
if [[ ! -f .env ]]; then
  echo "WARNING: .env not found. Services that require GITHUB_TOKEN or MCP_BEARER_TOKEN" >&2
  echo "         will start but may not be fully functional. Copy .env.example to .env" >&2
  echo "         and fill in local secrets for full validation." >&2
fi

# Create or reuse cluster
if k3d cluster list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx "$CLUSTER_NAME"; then
  echo "Cluster $CLUSTER_NAME already exists, reusing."
else
  echo "Creating k3d cluster $CLUSTER_NAME..."
  k3d cluster create "$CLUSTER_NAME" --config k8s/overlays/local/k3d-config.yaml
fi

# Apply local overlay (idempotent; replicas-local.yaml scales ready services to 1)
echo "Applying k8s local overlay..."
kubectl apply -k k8s/overlays/local

# Wait for rollouts of the ready services
echo "Waiting for rollouts (timeout: $TIMEOUT each)..."
kubectl rollout status deploy/github-unified-mcp      -n mcp --timeout="$TIMEOUT"
kubectl rollout status deploy/deploy-orchestrator-mcp -n mcp --timeout="$TIMEOUT"
kubectl rollout status deploy/mcp-social              -n mcp --timeout="$TIMEOUT"
kubectl rollout status deploy/repo-research-sidecar   -n mcp --timeout="$TIMEOUT"
kubectl rollout status deploy/central-mcp-gateway     -n mcp --timeout="$TIMEOUT"
kubectl rollout status deploy/github-unified-mcp-bff  -n bff --timeout="$TIMEOUT"
kubectl rollout status deploy/vos-studio-mcp          -n vos --timeout="$TIMEOUT"
kubectl rollout status deploy/vos-studio-bff          -n bff --timeout="$TIMEOUT"

# Health checks via port-forward
# Use high local ports to avoid clashing with Compose (8765, 8001, 8080, 8010, 8020, 8030)
PIDS=()

cleanup() {
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT

start_pf() {
  local name="$1" namespace="$2" svc_port="$3" local_port="$4"
  kubectl port-forward "svc/$name" "${local_port}:${svc_port}" -n "$namespace" >/dev/null 2>&1 &
  PIDS+=($!)
}

# Poll a TCP port until it accepts connections (port-forward process is ready).
wait_for_port() {
  local port="$1" attempts=0 max="${2:-15}"
  until (: < /dev/tcp/127.0.0.1/"$port") 2>/dev/null; do
    if (( ++attempts >= max )); then
      echo "ERROR: port $port did not open within ${max}s" >&2
      return 1
    fi
    sleep 1
  done
}

check_health() {
  local name="$1" local_port="$2" path="$3"
  if [[ "$path" == "tcp" ]]; then
    echo "  OK: $name"
    return 0
  fi
  local url="http://localhost:${local_port}${path}"
  echo "  Checking $name -> $url"
  if curl -fsS --retry 12 --retry-delay 2 --retry-connrefused --retry-all-errors "$url" >/dev/null; then
    echo "  OK: $name"
  else
    echo "  FAIL: $name health check failed at $url" >&2
    exit 1
  fi
}

# Single source of truth for services: name:namespace:svc_port:local_port:health_path
# Local ports use high numbers (18xxx/19xxx) to avoid clashing with Compose.
SERVICES=(
  "github-unified-mcp:mcp:8765:19765:/healthz"
  "deploy-orchestrator-mcp:mcp:8000:18000:/healthz"
  "mcp-social:mcp:8080:18080:/health"
  "repo-research-sidecar:mcp:8081:18081:tcp"
  "central-mcp-gateway:mcp:8080:18040:/healthz"
  "github-unified-mcp-bff:bff:8000:18010:/healthz"
  "vos-studio-mcp:vos:8000:18020:/health"
  "vos-studio-bff:bff:8000:18030:/healthz"
)

echo "Starting port-forwards..."
for _svc in "${SERVICES[@]}"; do
  IFS=: read -r _name _ns _sport _lport _path <<< "$_svc"
  start_pf "$_name" "$_ns" "$_sport" "$_lport"
done

echo "Waiting for port-forwards to accept connections..."
for _svc in "${SERVICES[@]}"; do
  IFS=: read -r _name _ns _sport _lport _path <<< "$_svc"
  wait_for_port "$_lport"
done

echo "Running health checks..."
for _svc in "${SERVICES[@]}"; do
  IFS=: read -r _name _ns _sport _lport _path <<< "$_svc"
  check_health "$_name" "$_lport" "$_path"
done

echo ""
echo "k3d smoke passed: all 8 ready services are healthy."

# End-to-end path through the gateway (auth + tools). Needs the public bearer
# token; skip with a notice if it is not configured so the health smoke still
# stands on its own.
if [[ -n "${CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN:-}" ]] || \
   { [[ -f .env ]] && grep -qE '^CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN=.+' .env; }; then
  echo ""
  echo "Running end-to-end gateway smoke (including upstream routing)..."
  # E2E_UPSTREAM_TOOL forces verification of the gateway↔upstream path.
  # github.search_issues is always in the default GATEWAY_TOOL_ALLOWLIST and is read-only.
  GATEWAY_URL="http://localhost:18040" \
  E2E_UPSTREAM_TOOL="${E2E_UPSTREAM_TOOL:-github.search_issues}" \
  bash "$ROOT_DIR/scripts/smoke-e2e.sh"
else
  echo ""
  echo "Skipping E2E gateway smoke: CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN not set (env or .env)."
fi

echo ""
kubectl get pods -n mcp -o wide
kubectl get pods -n bff -o wide
kubectl get pods -n vos -o wide
