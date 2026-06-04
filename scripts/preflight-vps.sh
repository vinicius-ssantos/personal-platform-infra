#!/usr/bin/env bash
# Preflight go/no-go check before a real VPS deploy.
#
# Run it against the VPS cluster (kubeconfig pointing at the VPS, VPS_DOMAIN set)
# to confirm everything the overlay and wake scripts depend on is in place:
# tooling, a reachable cluster, a renderable overlay, the GHCR pull secret, the
# runtime platform-secrets and the Grafana admin secret.
#
# Usage:
#   VPS_DOMAIN=example.org scripts/preflight-vps.sh
#   just preflight-vps
#
# Exit code is non-zero if any required (FAIL) check does not pass. WARN items
# are advisory and do not fail the run.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FAILS=0
WARNS=0

ok()   { printf '  [OK]   %s\n' "$1"; }
warn() { printf '  [WARN] %s\n' "$1"; WARNS=$((WARNS + 1)); }
fail() { printf '  [FAIL] %s\n' "$1"; FAILS=$((FAILS + 1)); }

have() { command -v "$1" >/dev/null 2>&1; }

echo "== Tooling =="
if have kubectl; then ok "kubectl present"; else fail "kubectl not found"; fi

echo "== Domain =="
if [[ -n "${VPS_DOMAIN:-}" ]]; then
  ok "VPS_DOMAIN is set ($VPS_DOMAIN)"
else
  fail "VPS_DOMAIN is not set (export it; in CI it is the VPS_DOMAIN repo variable)"
fi

echo "== Overlay render =="
if have kubectl && [[ -n "${VPS_DOMAIN:-}" ]]; then
  if bash "$ROOT_DIR/scripts/render-vps-overlay.sh" >/dev/null 2>&1; then
    ok "k8s/overlays/vps renders with VPS_DOMAIN substituted"
  else
    fail "render-vps-overlay.sh failed (see: VPS_DOMAIN=$VPS_DOMAIN scripts/render-vps-overlay.sh)"
  fi
else
  warn "skipped overlay render (needs kubectl + VPS_DOMAIN)"
fi

echo "== Cluster connectivity =="
CLUSTER_OK=0
if have kubectl && kubectl cluster-info --request-timeout=10s >/dev/null 2>&1; then
  ok "cluster reachable (context: $(kubectl config current-context 2>/dev/null))"
  CLUSTER_OK=1
else
  fail "cannot reach cluster (is the VPS kubeconfig active?)"
fi

# Secret/namespace checks only make sense against a reachable cluster.
secret_exists() { kubectl get secret "$1" -n "$2" >/dev/null 2>&1; }
ns_exists()     { kubectl get namespace "$1" >/dev/null 2>&1; }

if [[ "$CLUSTER_OK" -eq 1 ]]; then
  echo "== Namespaces =="
  for ns in mcp bff vos monitoring; do
    if ns_exists "$ns"; then ok "namespace/$ns"; else warn "namespace/$ns missing (created by 'kubectl apply -k'/deploy)"; fi
  done

  echo "== GHCR pull secret (ghcr-pull-secret) =="
  for ns in mcp bff vos; do
    if secret_exists ghcr-pull-secret "$ns"; then ok "ghcr-pull-secret in $ns"; else fail "ghcr-pull-secret missing in $ns (run: just create-ghcr-secret)"; fi
  done

  echo "== Runtime platform-secrets =="
  for ns in mcp bff vos; do
    if secret_exists platform-secrets "$ns"; then ok "platform-secrets in $ns"; else fail "platform-secrets missing in $ns (run: just k8s-vps-secrets)"; fi
  done

  echo "== Grafana admin secret =="
  if secret_exists grafana-admin monitoring; then
    ok "grafana-admin in monitoring"
  else
    warn "grafana-admin missing in monitoring (Grafana crashloops if monitoring is scaled up; run: just k8s-vps-secrets)"
  fi
fi

echo
echo "Preflight finished: $FAILS failure(s), $WARNS warning(s)."
if [[ "$FAILS" -gt 0 ]]; then
  echo "NOT ready to deploy — resolve the [FAIL] items above." >&2
  exit 1
fi
echo "Ready to deploy."
