#!/usr/bin/env bash
# Render the VPS kustomize overlay with runtime tokens substituted.
#
# Token → env var mapping:
#   __VPS_DOMAIN__    VPS_DOMAIN    (required)
#   __R2_ENDPOINT__   R2_ENDPOINT   (required when backup-config-vps.yaml patch is present)
#   __R2_BUCKET__     R2_BUCKET     (required when backup-config-vps.yaml patch is present)
#
# Usage:
#   VPS_DOMAIN=example.org \
#   R2_ENDPOINT=https://abc.r2.cloudflarestorage.com \
#   R2_BUCKET=my-bucket \
#   scripts/render-vps-overlay.sh
#
#   # Pipe directly to kubectl:
#   ... scripts/render-vps-overlay.sh | kubectl apply -f -
#
# In GitHub Actions, set VPS_DOMAIN / R2_ENDPOINT / R2_BUCKET as repository
# variables (vars.*) — they are non-sensitive configuration, not secrets.
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

if [[ -n "${R2_BUCKET:-}" ]] && [[ ! "$R2_BUCKET" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "ERROR: R2_BUCKET '${R2_BUCKET}' contains characters outside [a-zA-Z0-9_-]." >&2
  exit 1
fi

if [[ -n "${R2_ENDPOINT:-}" ]] && [[ ! "$R2_ENDPOINT" =~ ^https://[a-zA-Z0-9._:/@%-]+$ ]]; then
  echo "ERROR: R2_ENDPOINT '${R2_ENDPOINT}' must be a plain HTTPS URL (no special characters)." >&2
  echo "       Expected format: https://<account-id>.r2.cloudflarestorage.com" >&2
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

# R2 tokens are only present when backup-config-vps.yaml is included in the overlay.
# Require the env vars only if the tokens actually appear in the rendered output.
if printf '%s\n' "$rendered" | grep -q '__R2_ENDPOINT__'; then
  if [[ -z "${R2_ENDPOINT:-}" ]]; then
    echo "ERROR: R2_ENDPOINT is not set but the backup config patch requires it." >&2
    echo "       Set it as a GitHub Actions repository variable (vars.R2_ENDPOINT)." >&2
    echo "       Format: https://<account-id>.r2.cloudflarestorage.com" >&2
    exit 1
  fi
  rendered="$(printf '%s\n' "$rendered" | sed "s|__R2_ENDPOINT__|$(sed_escape "${R2_ENDPOINT}" "|")|g")"
fi

if printf '%s\n' "$rendered" | grep -q '__R2_BUCKET__'; then
  if [[ -z "${R2_BUCKET:-}" ]]; then
    echo "ERROR: R2_BUCKET is not set but the backup config patch requires it." >&2
    echo "       Set it as a GitHub Actions repository variable (vars.R2_BUCKET)." >&2
    exit 1
  fi
  rendered="$(printf '%s\n' "$rendered" | sed "s/__R2_BUCKET__/$(sed_escape "${R2_BUCKET}" "/")/g")"
fi

# ---------------------------------------------------------------------------
# Safety gate: fail if any token or placeholder remains unsubstituted
# ---------------------------------------------------------------------------

if printf '%s\n' "$rendered" | grep -qE '__[A-Z_]+__|REPLACE_WITH_'; then
  echo "ERROR: Unsubstituted tokens or placeholders found in rendered output; aborting." >&2
  printf '%s\n' "$rendered" | grep -nE '__[A-Z_]+__|REPLACE_WITH_' >&2 || true
  exit 1
fi

printf '%s\n' "$rendered"
