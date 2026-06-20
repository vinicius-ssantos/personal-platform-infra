#!/usr/bin/env bash
set -euo pipefail

# Utility to restart a single service or all platform services.
# This is NOT the path for deploying new code — that's covered by image digest
# bumps via Renovate. See docs/image-pinning.md.
#
# Usage:
#   ./scripts/rollout-restart.sh all
#   ./scripts/rollout-restart.sh github-unified-mcp

usage() {
  cat <<EOF
Usage: $0 <service-name|all>

Services:
  github-unified-mcp, deploy-orchestrator-mcp, mcp-social,
  repo-research-sidecar, central-mcp-gateway, github-unified-mcp-bff,
  vos-studio-mcp, vos-studio-bff, workflow-engine
EOF
  exit 1
}

rollout_one() {
  local name="$1"
  local ns="$2"
  echo "=== Rolling restart $name (namespace: $ns) ==="
  kubectl rollout restart "deploy/$name" -n "$ns"
  kubectl rollout status "deploy/$name" -n "$ns" --timeout=120s
}

if [ $# -eq 0 ]; then
  usage
fi

case "${1}" in
  all)
    rollout_one github-unified-mcp mcp
    rollout_one deploy-orchestrator-mcp mcp
    rollout_one mcp-social mcp
    rollout_one repo-research-sidecar mcp
    rollout_one central-mcp-gateway mcp
    rollout_one github-unified-mcp-bff bff
    rollout_one vos-studio-mcp vos
    rollout_one vos-studio-bff bff
    rollout_one workflow-engine mcp
    echo ""
    echo "All services restarted."
    ;;
  github-unified-mcp)     rollout_one github-unified-mcp mcp ;;
  deploy-orchestrator-mcp) rollout_one deploy-orchestrator-mcp mcp ;;
  mcp-social)             rollout_one mcp-social mcp ;;
  repo-research-sidecar)  rollout_one repo-research-sidecar mcp ;;
  central-mcp-gateway)    rollout_one central-mcp-gateway mcp ;;
  github-unified-mcp-bff) rollout_one github-unified-mcp-bff bff ;;
  vos-studio-mcp)         rollout_one vos-studio-mcp vos ;;
  vos-studio-bff)         rollout_one vos-studio-bff bff ;;
  workflow-engine)        rollout_one workflow-engine mcp ;;
  *)                      usage ;;
esac
