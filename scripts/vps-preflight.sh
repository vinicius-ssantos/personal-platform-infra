#!/usr/bin/env bash
# Pre-deploy checklist for the VPS cluster. Run this before triggering the
# first automated deploy or after re-provisioning the VPS.
set -euo pipefail

OK=0
WARN=0
FAIL=0

pass()  { echo "  OK   $*"; OK=$((OK+1)); }
warn()  { echo "  WARN $*"; WARN=$((WARN+1)); }
fail()  { echo "  FAIL $*"; FAIL=$((FAIL+1)); }
header(){ echo ""; echo "=== $* ==="; }

header "kubectl cluster connectivity"
if ! command -v kubectl >/dev/null 2>&1; then
  fail "kubectl not found"
elif ! kubectl cluster-info --request-timeout=5s >/dev/null 2>&1; then
  fail "kubectl cannot reach the cluster — check KUBECONFIG"
  echo ""
  echo "  To point kubectl at the VPS:"
  echo "    ssh <operator>@<vps-ip> 'cat ~/.kube/config' > /tmp/vps-kubeconfig.yaml"
  echo "    export KUBECONFIG=/tmp/vps-kubeconfig.yaml"
else
  pass "kubectl can reach the cluster"
  CONTEXT=$(kubectl config current-context 2>/dev/null || echo "unknown")
  pass "current context: $CONTEXT"
fi

header "Namespaces"
for ns in mcp bff vos monitoring; do
  if kubectl get namespace "$ns" >/dev/null 2>&1; then
    pass "namespace $ns exists"
  else
    warn "namespace $ns missing — will be created by kustomize apply"
  fi
done

header "GHCR pull secrets"
for ns in mcp bff vos; do
  if kubectl get secret ghcr-pull-secret -n "$ns" >/dev/null 2>&1; then
    pass "ghcr-pull-secret in $ns"
  else
    fail "ghcr-pull-secret missing in $ns"
    echo "  Fix: GHCR_USERNAME=<user> GHCR_TOKEN=<token> just create-ghcr-secret"
  fi
done

header "Platform secrets"
for ns in mcp bff vos; do
  if kubectl get secret platform-secrets -n "$ns" >/dev/null 2>&1; then
    pass "platform-secrets in $ns"
  else
    fail "platform-secrets missing in $ns"
    echo "  Fix: see k8s/overlays/vps/platform-secrets-vps.yaml.example"
  fi
done

header "Overlay domain placeholders"
PLACEHOLDER_FILES=()
while IFS= read -r -d '' f; do
  if grep -q 'example\.com' "$f" 2>/dev/null; then
    PLACEHOLDER_FILES+=("$f")
  fi
done < <(find k8s/overlays/vps -name '*.yaml' -print0)

if [ ${#PLACEHOLDER_FILES[@]} -eq 0 ]; then
  pass "no example.com placeholders found in VPS overlay"
else
  for f in "${PLACEHOLDER_FILES[@]}"; do
    warn "example.com placeholder in $f — replace with your real domain"
  done
fi

header "GitHub Actions secret"
echo "  Cannot check VPS_KUBECONFIG from here — verify it exists in:"
echo "  GitHub → Settings → Secrets → Actions → VPS_KUBECONFIG"
echo ""
echo "  To get the value:"
echo "    ssh <operator>@<vps-ip> 'cat ~/.kube/config' | base64 -w0"

header "Summary"
echo "  Passed: $OK  Warnings: $WARN  Failed: $FAIL"
echo ""
if [ "$FAIL" -gt 0 ]; then
  echo "  One or more preflight checks failed. Resolve them before triggering the VPS deploy."
  exit 1
elif [ "$WARN" -gt 0 ]; then
  echo "  Preflight passed with warnings. Review warnings above before deploying."
  exit 0
else
  echo "  All checks passed. VPS is ready for automated deploy."
fi
