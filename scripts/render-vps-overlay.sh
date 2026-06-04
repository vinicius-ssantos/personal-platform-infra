#!/usr/bin/env bash
# Render the VPS kustomize overlay with the real domain substituted in.
#
# The overlay keeps a __VPS_DOMAIN__ token instead of a hard-coded domain so the
# actual domain never lives in git. This script builds the overlay and replaces
# the token with $VPS_DOMAIN, emitting ready-to-apply manifests on stdout.
#
# Usage:
#   VPS_DOMAIN=example.org scripts/render-vps-overlay.sh            # print manifests
#   VPS_DOMAIN=example.org scripts/render-vps-overlay.sh | kubectl apply -f -
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OVERLAY="${VPS_OVERLAY:-$ROOT_DIR/k8s/overlays/vps}"
TOKEN="__VPS_DOMAIN__"

if [[ -z "${VPS_DOMAIN:-}" ]]; then
  echo "ERROR: VPS_DOMAIN is not set. Export the VPS base domain (e.g. VPS_DOMAIN=example.org)." >&2
  echo "       In GitHub Actions, set it as the VPS_DOMAIN repository variable." >&2
  exit 1
fi

rendered="$(kubectl kustomize "$OVERLAY" | sed "s/${TOKEN}/${VPS_DOMAIN}/g")"

if printf '%s' "$rendered" | grep -q "$TOKEN"; then
  echo "ERROR: ${TOKEN} still present after substitution; aborting." >&2
  exit 1
fi

printf '%s\n' "$rendered"
