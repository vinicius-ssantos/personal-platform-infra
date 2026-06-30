#!/usr/bin/env bash
# Rotate gateway bearer tokens in .env and .mcp.json atomically.
# Uses sed line-by-line (never loads the whole file as a string) to avoid
# regex corruption when the file contains multi-byte UTF-8 sequences.
#
# Usage: bash scripts/env-rotate-tokens.sh
set -euo pipefail

ENV_FILE=".env"
MCP_FILE=".mcp.json"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Run from repo root." >&2
  exit 1
fi

# Backup first
BACKUP=".env.bak.$(date +%Y%m%d-%H%M%S)"
cp "$ENV_FILE" "$BACKUP"
echo "Backed up $ENV_FILE → $BACKUP"

# Generate tokens using /dev/urandom (portable, no PowerShell)
NEW_BEARER=$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c 64)
NEW_PLATFORM=$(LC_ALL=C tr -dc 'a-f0-9' </dev/urandom | head -c 64)

# Rotate in .env using sed (line-by-line, safe for UTF-8 files)
sed -i.tmp \
  "s|^CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN=.*|CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN=${NEW_BEARER}|" \
  "$ENV_FILE"
sed -i.tmp \
  "s|^MCP_BEARER_TOKEN=.*|MCP_BEARER_TOKEN=${NEW_PLATFORM}|" \
  "$ENV_FILE"
rm -f "${ENV_FILE}.tmp"

echo "Tokens rotated in $ENV_FILE"

# Rotate in .mcp.json if it exists
if [[ -f "$MCP_FILE" ]]; then
  cp "$MCP_FILE" "${MCP_FILE}.bak"
  sed -i.tmp \
    "s|\"Authorization\": \"Bearer [a-f0-9]*\"|\"Authorization\": \"Bearer ${NEW_BEARER}\"|" \
    "$MCP_FILE"
  sed -i.tmp \
    "s|\"X-Platform-Token\": \"[a-f0-9]*\"|\"X-Platform-Token\": \"${NEW_PLATFORM}\"|" \
    "$MCP_FILE"
  rm -f "${MCP_FILE}.tmp"
  echo "Tokens synced in $MCP_FILE"
fi

echo ""
echo "Done. Restart the gateway to apply: just compose-up"
echo "Remove backups when confirmed working: rm $BACKUP ${MCP_FILE}.bak"
