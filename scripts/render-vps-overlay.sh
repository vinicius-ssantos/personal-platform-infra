#!/usr/bin/env bash
# Render the VPS kustomize overlay with runtime tokens substituted.
#
# Token → env var mapping:
#   __VPS_DOMAIN__    VPS_DOMAIN    (required)
#
# Usage:
#   VPS_DOMAIN=example.org \
#   scripts/render-vps-overlay.sh
#
#   # Pipe directly to kubectl:
#   ... scripts/render-vps-overlay.sh | kubectl apply -f -
#
# In GitHub Actions, set VPS_DOMAIN as a repository variable (vars.*) —
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY="${VPS_OVERLAY:-$ROOT_DIR/k8s/overlays/vps}"

# ---------------------------------------------------------------------------
# Validate required variables
# ---------------------------------------------------------------------------

if [[ -z "${VPS_DOMAIN:-}" ]]; then
  echo "ERROR: VPS_DOMAIN is not set. Export the VPS base domain (e.g. VPS_DOMAIN=example.org)." >&2
  echo "       In GitHub Actions, set it as the VPS_DOMAIN repository variable." >&2
  exit 1
fi

# Validate formats and prevent sed injection.
if [[ ! "$VPS_DOMAIN" =~ ^[a-zA-Z0-9._-]+$ ]]; then
  echo "ERROR: VPS_DOMAIN '${VPS_DOMAIN}' contains characters that are not valid in a domain name." >&2
  exit 1
fi

# Escape a value for use as a sed replacement string with the given delimiter.
# Escapes backslash, ampersand (means "whole match"), and the delimiter itself.
sed_escape() {
  local value="$1" delim="${2:-/}"
  value="${value//\\/\\\\}"
  value="${value//&/\\&}"
  value="${value//$delim/\\$delim}"
  printf '%s' "$value"
}

# ---------------------------------------------------------------------------
# Build overlay
# ---------------------------------------------------------------------------

raw="$(kubectl kustomize "$OVERLAY")"

# ---------------------------------------------------------------------------
# Token substitutions
# ---------------------------------------------------------------------------

rendered="$(printf '%s\n' "$raw" | sed "s/__VPS_DOMAIN__/$(sed_escape "${VPS_DOMAIN}" "/")/g")"

# ---------------------------------------------------------------------------
# Safety gate: fail if any token or placeholder remains unsubstituted
# ---------------------------------------------------------------------------

if printf '%s\n' "$rendered" | grep -qE '__[A-Z_]+__|REPLACE_WITH_'; then
  echo "ERROR: Unsubstituted tokens or placeholders found in rendered output; aborting." >&2
  printf '%s\n' "$rendered" | grep -nE '__[A-Z_]+__|REPLACE_WITH_' >&2 || true
  exit 1
fi

printf '%s\n' "$rendered"
