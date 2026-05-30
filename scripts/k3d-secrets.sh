#!/usr/bin/env bash
# Injects real token values from .env into the local k3d cluster as Kubernetes
# Secrets. Run once after `just k8s-local-up`, then again whenever .env changes.
# Services are automatically restarted to pick up the new values.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Run: just env-init" >&2
  exit 1
fi

# Load .env without exporting — we'll read values explicitly
_get() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- | tr -d '"' || true
}

GITHUB_TOKEN="$(_get GITHUB_TOKEN)"
MCP_BEARER_TOKEN="$(_get MCP_BEARER_TOKEN)"
MCP_SERVER_API_KEY="$(_get MCP_SERVER_API_KEY)"
SOCIAL_MCP_ACCESS_TOKEN="$(_get SOCIAL_MCP_ACCESS_TOKEN)"

# Warn for any token still at placeholder value
WARN=0
for var in GITHUB_TOKEN MCP_BEARER_TOKEN MCP_SERVER_API_KEY SOCIAL_MCP_ACCESS_TOKEN; do
  val="${!var}"
  if [[ -z "$val" || "$val" == "change-me" || "$val" == "paste-"* ]]; then
    echo "WARNING: $var is not set or still has a placeholder value in $ENV_FILE" >&2
    WARN=$((WARN + 1))
  fi
done
if [[ "$WARN" -gt 0 ]]; then
  echo "Continuing with placeholder values — services will start but API calls will fail." >&2
fi

upsert_secret() {
  local name="$1" namespace="$2"
  shift 2
  # Build --from-literal args dynamically
  local args=()
  for kv in "$@"; do
    args+=("--from-literal=$kv")
  done

  if kubectl get secret "$name" -n "$namespace" >/dev/null 2>&1; then
    kubectl delete secret "$name" -n "$namespace" --ignore-not-found
  fi
  kubectl create secret generic "$name" -n "$namespace" "${args[@]}"
  echo "  OK: secret/$name in $namespace"
}

echo "=== Injecting platform secrets into k3d ==="

# mcp namespace: github-unified-mcp + deploy-orchestrator-mcp + mcp-social
upsert_secret platform-secrets mcp \
  "GITHUB_TOKEN=${GITHUB_TOKEN}" \
  "MCP_BEARER_TOKEN=${MCP_BEARER_TOKEN}" \
  "MCP_SERVER_API_KEY=${MCP_SERVER_API_KEY}" \
  "SOCIAL_MCP_ACCESS_TOKEN=${SOCIAL_MCP_ACCESS_TOKEN}"

# bff namespace: github-unified-mcp-bff
upsert_secret platform-secrets bff \
  "MCP_TOKEN=${MCP_BEARER_TOKEN}"

# vos namespace: vos-studio-mcp (no sensitive tokens currently)
upsert_secret platform-secrets vos \
  "PLACEHOLDER=none"

echo ""
echo "=== Patching deployments to use real secrets ==="

# github-unified-mcp
kubectl set env deployment/github-unified-mcp -n mcp \
  --from=secret/platform-secrets \
  --keys=GITHUB_TOKEN,MCP_BEARER_TOKEN
echo "  OK: github-unified-mcp"

# deploy-orchestrator-mcp
kubectl set env deployment/deploy-orchestrator-mcp -n mcp \
  --from=secret/platform-secrets \
  --keys=MCP_SERVER_API_KEY
echo "  OK: deploy-orchestrator-mcp"

# mcp-social
kubectl set env deployment/mcp-social -n mcp \
  --from=secret/platform-secrets \
  --keys=SOCIAL_MCP_ACCESS_TOKEN
echo "  OK: mcp-social"

# github-unified-mcp-bff
kubectl set env deployment/github-unified-mcp-bff -n bff \
  --from=secret/platform-secrets \
  --keys=MCP_TOKEN
echo "  OK: github-unified-mcp-bff"

echo ""
echo "Secrets injected. Deployments are rolling out with real credentials."
echo "Run 'just smoke-k3d' after rollout to verify all services are healthy."
