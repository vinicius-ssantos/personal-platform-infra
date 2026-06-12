#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
# shellcheck source=scripts/lib.sh
source scripts/lib.sh

ENV_FILE="${ENV_FILE:-.env}"
HEALTH_URL="${DEPLOY_ORCHESTRATOR_MCP_HEALTH_URL:-http://localhost:8001/healthz}"

require_env_file "$ENV_FILE"

docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml --profile deploy up -d deploy-orchestrator-mcp

wait_health "$HEALTH_URL"

docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml --profile deploy ps deploy-orchestrator-mcp
