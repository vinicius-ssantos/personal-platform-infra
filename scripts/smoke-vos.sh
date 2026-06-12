#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

ENV_FILE="${ENV_FILE:-.env}"
MCP_HEALTH_URL="${VOS_STUDIO_MCP_HEALTH_URL:-http://localhost:8020/health}"
BFF_HEALTH_URL="${VOS_STUDIO_BFF_HEALTH_URL:-http://localhost:8030/healthz}"

require_env_file "$ENV_FILE"

docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml --profile vos up -d vos-studio-mcp vos-studio-bff

wait_health "$MCP_HEALTH_URL" "VOS MCP"
wait_health "$BFF_HEALTH_URL" "VOS BFF"

docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml --profile vos ps vos-studio-mcp vos-studio-bff
