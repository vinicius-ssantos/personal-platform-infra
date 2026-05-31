#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

MODE="${1:-check}"
CONFIG="${STATUS_PAGE_CONFIG:-cloudflare/workers/status-page/wrangler.toml}"
EXAMPLE="${STATUS_PAGE_EXAMPLE:-cloudflare/workers/status-page/wrangler.toml.example}"

case "$MODE" in
  init)
    if [[ -f "$CONFIG" ]]; then
      echo "$CONFIG already exists; leaving it unchanged."
      exit 0
    fi
    if [[ ! -f "$EXAMPLE" ]]; then
      echo "ERROR: example config not found at $EXAMPLE." >&2
      exit 1
    fi
    cp "$EXAMPLE" "$CONFIG"
    echo "Created $CONFIG from $EXAMPLE."
    echo "Edit routes, account settings and SERVICES_JSON before deploying."
    ;;
  check)
    if [[ ! -f "$CONFIG" ]]; then
      echo "ERROR: $CONFIG not found." >&2
      echo "Run: just status-page-init" >&2
      exit 1
    fi
    ;;
  *)
    echo "Usage: $0 init|check" >&2
    exit 2
    ;;
esac
