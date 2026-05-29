#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-.env}"
HEALTH_URL="${GITHUB_UNIFIED_MCP_BFF_HEALTH_URL:-http://localhost:8010/healthz}"
MCP_HEALTH_URL="${GITHUB_UNIFIED_MCP_HEALTH_URL:-http://localhost:8765/healthz}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Copy .env.example to .env and fill local secrets first." >&2
  exit 1
fi

docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml --profile github --profile github-bff up -d github-unified-mcp github-unified-mcp-bff

echo "Checking upstream MCP at $MCP_HEALTH_URL"
curl -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors "$MCP_HEALTH_URL"
echo

echo "Checking $HEALTH_URL"
curl -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors "$HEALTH_URL"
echo

docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml --profile github --profile github-bff ps github-unified-mcp github-unified-mcp-bff
