#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ERRORS=0
WARNINGS=0
STRICT="${POLICY_STRICT:-0}"

fail() {
  echo "ERROR: $*" >&2
  ERRORS=$((ERRORS + 1))
}

warn() {
  echo "WARN: $*" >&2
  WARNINGS=$((WARNINGS + 1))
}

require_text() {
  local file="$1" pattern="$2" message="$3"
  if ! grep -Eq "$pattern" "$file"; then
    fail "$message ($file)"
  fi
}

# Service defaults live in terraform/cloudflare/variables.tf (var.services).
if ! grep -A 6 'deploy_mcp = {' terraform/cloudflare/variables.tf | grep -q 'backend[[:space:]]*=[[:space:]]*"http://localhost:8001"'; then
  fail "Cloudflare deploy-mcp local tunnel backend must match Compose host port 8001 (terraform/cloudflare/variables.tf)"
fi

# The Worker has no in-source defaults (it fails explicitly without
# SERVICES_JSON); the canonical service list lives in wrangler.toml.example.
for file in cloudflare/workers/status-page/wrangler.toml.example; do
  require_text "$file" 'vos-studio-mcp' "Status page defaults must include vos-studio-mcp"
  require_text "$file" 'vos-studio-bff' "Status page defaults must include vos-studio-bff"
done

if grep -q "REPLACE_WITH" .sops.yaml; then
  warn ".sops.yaml still contains placeholder age recipients; run just secrets-check before using SOPS secrets"
fi

if grep -RInE 'local-dev-token|localhost|APP_ENV: development|BFF_ENV: development|COOKIE_SECURE: "false"' k8s/base >/tmp/personal-platform-policy-local-values.txt; then
  fail "k8s/base contains local-only values that must live in overlays only; see /tmp/personal-platform-policy-local-values.txt"
fi

if grep -RInE 'ghcr\.io/.+:main' .env.example k8s >/tmp/personal-platform-policy-main-tags.txt; then
  # Renovate (docker:pinDigests) resolves this automatically via PRs —
  # see docs/image-pinning.md and .github/renovate.json.
  warn "mutable :main image tags remain in runtime examples/manifests; see docs/image-pinning.md"
fi

if [[ "$STRICT" == "1" && "$WARNINGS" -gt 0 ]]; then
  ERRORS=$((ERRORS + WARNINGS))
fi

if [[ "$ERRORS" -gt 0 ]]; then
  echo "Policy check failed with $ERRORS error(s) and $WARNINGS warning(s)." >&2
  exit 1
fi

echo "Policy check passed with $WARNINGS warning(s)."
