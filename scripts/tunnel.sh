#!/usr/bin/env bash
set -euo pipefail

TUNNEL_NAME="${CLOUDFLARE_TUNNEL_NAME:-personal-platform}"

if ! command -v cloudflared >/dev/null 2>&1; then
  echo "cloudflared is not installed."
  exit 1
fi

cloudflared tunnel run "$TUNNEL_NAME"
