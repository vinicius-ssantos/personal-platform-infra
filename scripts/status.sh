#!/usr/bin/env bash
# Shows consolidated state of all local and remote platform components.
# Tolerant: each section is independent and never aborts the script.

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; }
warn() { echo -e "  ${YELLOW}~${NC} $*"; }

echo ""
echo "=== k3d cluster ==="
if command -v k3d &>/dev/null; then
  if k3d cluster list 2>/dev/null | grep -q "personal-platform"; then
    k3d cluster list 2>/dev/null | grep "personal-platform" | while read -r line; do
      ok "$line"
    done
  else
    warn "no cluster named 'personal-platform' found"
  fi
else
  warn "k3d not installed"
fi

echo ""
echo "=== pods (local k3d) ==="
if command -v kubectl &>/dev/null; then
  if kubectl cluster-info --request-timeout=3s &>/dev/null 2>&1; then
    kubectl get pods -A --no-headers 2>/dev/null | while read -r line; do
      if echo "$line" | grep -qE "Running|Completed"; then
        ok "$line"
      else
        fail "$line"
      fi
    done || warn "no pods found"
  else
    warn "no local cluster reachable (kubectl)"
  fi
else
  warn "kubectl not installed"
fi

echo ""
echo "=== docker compose ==="
if command -v docker &>/dev/null; then
  if docker compose -f compose/docker-compose.yml ps --format "table {{.Name}}\t{{.Status}}" 2>/dev/null | tail -n +2 | while read -r line; do
    if echo "$line" | grep -qi "running\|healthy"; then
      ok "$line"
    elif echo "$line" | grep -qi "exited\|unhealthy\|dead"; then
      fail "$line"
    else
      warn "$line"
    fi
  done; then
    :
  fi
  if ! docker compose -f compose/docker-compose.yml ps --quiet 2>/dev/null | grep -q .; then
    warn "no compose containers running"
  fi
else
  warn "docker not installed"
fi

echo ""
echo "=== VPS kubeconfig ==="
KUBECONFIG_VPS="${KUBECONFIG_VPS:-}"
if [[ -n "$KUBECONFIG_VPS" && -f "$KUBECONFIG_VPS" ]]; then
  if KUBECONFIG="$KUBECONFIG_VPS" kubectl cluster-info --request-timeout=5s &>/dev/null 2>&1; then
    ok "VPS cluster reachable"
    KUBECONFIG="$KUBECONFIG_VPS" kubectl get deployments -A --no-headers 2>/dev/null | while read -r line; do
      ok "$line"
    done
  else
    fail "VPS cluster unreachable"
  fi
else
  warn "KUBECONFIG_VPS not set — skipping VPS check"
fi

echo ""
