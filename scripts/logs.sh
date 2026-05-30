#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-all}"
TAIL="${TAIL:-100}"

usage() {
  cat <<'EOF'
Usage: scripts/logs.sh [all|github|deploy|social|vos|SERVICE]

Groups:
  all      Show recent logs for all platform workloads.
  github   Show GitHub MCP and GitHub BFF logs.
  deploy   Show Deploy Orchestrator MCP logs.
  social   Show Social MCP logs.
  vos      Show VOS MCP and VOS BFF logs.

Set TAIL=<n> to change the number of log lines. Default: 100.
EOF
}

log_deployment() {
  local namespace="$1"
  local deployment="$2"

  echo ""
  echo "=== ${namespace}/${deployment} ==="

  if ! kubectl get namespace "$namespace" >/dev/null 2>&1; then
    echo "skip: namespace '${namespace}' not found"
    return 0
  fi

  if ! kubectl get deployment "$deployment" -n "$namespace" >/dev/null 2>&1; then
    echo "skip: deployment '${deployment}' not found in namespace '${namespace}'"
    return 0
  fi

  local replicas ready
  replicas="$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath='{.status.replicas}' 2>/dev/null || true)"
  ready="$(kubectl get deployment "$deployment" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || true)"

  if [[ -z "${replicas}" || "${replicas}" == "0" ]]; then
    echo "skip: deployment is asleep or has zero replicas"
    return 0
  fi

  if [[ -z "${ready}" || "${ready}" == "0" ]]; then
    echo "warn: deployment has replicas but no ready pods yet"
  fi

  kubectl logs -n "$namespace" "deployment/${deployment}" --tail="$TAIL" --prefix=true || {
    echo "warn: failed to read logs for ${namespace}/${deployment}"
    return 0
  }
}

logs_github() {
  log_deployment mcp github-unified-mcp
  log_deployment bff github-unified-mcp-bff
}

logs_deploy() {
  log_deployment mcp deploy-orchestrator-mcp
}

logs_social() {
  log_deployment mcp mcp-social
}

logs_vos() {
  log_deployment vos vos-studio-mcp
  log_deployment bff vos-studio-bff
}

case "$TARGET" in
  -h|--help|help)
    usage
    ;;
  all)
    logs_github
    logs_deploy
    logs_social
    logs_vos
    ;;
  github)
    logs_github
    ;;
  deploy)
    logs_deploy
    ;;
  social)
    logs_social
    ;;
  vos)
    logs_vos
    ;;
  github-unified-mcp)
    log_deployment mcp github-unified-mcp
    ;;
  github-unified-mcp-bff)
    log_deployment bff github-unified-mcp-bff
    ;;
  deploy-orchestrator-mcp)
    log_deployment mcp deploy-orchestrator-mcp
    ;;
  mcp-social)
    log_deployment mcp mcp-social
    ;;
  vos-studio-mcp)
    log_deployment vos vos-studio-mcp
    ;;
  vos-studio-bff)
    log_deployment bff vos-studio-bff
    ;;
  *)
    echo "error: unknown logs target '${TARGET}'" >&2
    echo "" >&2
    usage >&2
    exit 2
    ;;
esac
