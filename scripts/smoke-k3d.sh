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

# Apply local overlay (idempotent; replicas-local.yaml scales the 4 ready services to 1)
echo "Applying k8s local overlay..."
kubectl apply -k k8s/overlays/local

# Wait for rollouts of the 4 ready services
echo "Waiting for rollouts (timeout: $TIMEOUT each)..."
kubectl rollout status deploy/github-unified-mcp      -n mcp --timeout="$TIMEOUT"
kubectl rollout status deploy/deploy-orchestrator-mcp -n mcp --timeout="$TIMEOUT"
kubectl rollout status deploy/mcp-social              -n mcp --timeout="$TIMEOUT"
kubectl rollout status deploy/github-unified-mcp-bff  -n bff --timeout="$TIMEOUT"

# Health checks via port-forward
# Use high local ports to avoid clashing with Compose (8765, 8001, 8080, 8010)
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

check_health() {
  local name="$1" local_port="$2" path="$3"
  local url="http://localhost:${local_port}${path}"
  echo "  Checking $name → $url"
  if curl -fsS --retry 12 --retry-delay 2 --retry-connrefused --retry-all-errors "$url" >/dev/null; then
    echo "  OK: $name"
  else
    echo "  FAIL: $name health check failed at $url" >&2
    exit 1
  fi
}

echo "Starting port-forwards..."
start_pf github-unified-mcp      mcp 8765 19765
start_pf deploy-orchestrator-mcp mcp 8000 18000
start_pf mcp-social              mcp 8080 18080
start_pf github-unified-mcp-bff  bff 8000 18010

sleep 3

echo "Running health checks..."
check_health github-unified-mcp      19765 /healthz
check_health deploy-orchestrator-mcp 18000 /healthz
check_health mcp-social              18080 /health
check_health github-unified-mcp-bff  18010 /healthz

echo ""
echo "k3d smoke passed: all 4 ready services are healthy."
echo ""
kubectl get pods -n mcp -o wide
kubectl get pods -n bff -o wide
