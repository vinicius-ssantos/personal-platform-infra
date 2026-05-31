#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SOPS_CONFIG="${SOPS_CONFIG:-.sops.yaml}"
AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.age/personal-platform.txt}"
ERRORS=0

if [[ ! -f "$SOPS_CONFIG" ]]; then
  echo "ERROR: $SOPS_CONFIG not found." >&2
  exit 1
fi

if grep -q "REPLACE_WITH" "$SOPS_CONFIG"; then
  echo "ERROR: $SOPS_CONFIG still contains REPLACE_WITH placeholders." >&2
  echo "Generate an age key with: age-keygen -o ~/.age/personal-platform.txt" >&2
  echo "Then copy the public key into $SOPS_CONFIG." >&2
  ERRORS=$((ERRORS + 1))
fi

if [[ ! -f "$AGE_KEY_FILE" ]]; then
  echo "ERROR: age private key not found at $AGE_KEY_FILE." >&2
  echo "Set SOPS_AGE_KEY_FILE or generate one with: age-keygen -o ~/.age/personal-platform.txt" >&2
  ERRORS=$((ERRORS + 1))
fi

if [[ "$ERRORS" -gt 0 ]]; then
  exit 1
fi

echo "SOPS/age readiness OK."
