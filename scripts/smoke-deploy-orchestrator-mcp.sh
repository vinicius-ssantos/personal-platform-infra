#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-.env}"
HEALTH_URL="${DEPLOY_ORCHESTRATOR_MCP_HEALTH_URL:-http://localhost:8001/healthz}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Copy .env.example to .env and fill local secrets first." >&2
  exit 1
fi

docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml --profile deploy up -d deploy-orchestrator-mcp

echo "Checking $HEALTH_URL"
curl -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors "$HEALTH_URL"
echo

docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml --profile deploy ps deploy-orchestrator-mcp
