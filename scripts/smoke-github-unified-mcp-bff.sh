#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

ENV_FILE="${ENV_FILE:-.env}"
HEALTH_URL="${GITHUB_UNIFIED_MCP_BFF_HEALTH_URL:-http://localhost:8010/healthz}"
MCP_HEALTH_URL="${GITHUB_UNIFIED_MCP_HEALTH_URL:-http://localhost:8765/healthz}"

require_env_file "$ENV_FILE"

docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml --profile github --profile github-bff up -d github-unified-mcp github-unified-mcp-bff

wait_health "$MCP_HEALTH_URL" "upstream MCP"
wait_health "$HEALTH_URL"

docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml --profile github --profile github-bff ps github-unified-mcp github-unified-mcp-bff
