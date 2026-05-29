#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-.env}"
HEALTH_URL="${GITHUB_UNIFIED_MCP_HEALTH_URL:-http://localhost:8765/healthz}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Copy .env.example to .env and fill local secrets first." >&2
  exit 1
fi

docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml --profile github up -d github-unified-mcp

echo "Checking $HEALTH_URL"
curl -fsS "$HEALTH_URL"
echo

docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml --profile github ps github-unified-mcp
