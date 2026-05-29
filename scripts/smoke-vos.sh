#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-.env}"
MCP_HEALTH_URL="${VOS_STUDIO_MCP_HEALTH_URL:-http://localhost:8020/health}"
BFF_HEALTH_URL="${VOS_STUDIO_BFF_HEALTH_URL:-http://localhost:8030/healthz}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Copy .env.example to .env and fill local secrets first." >&2
  exit 1
fi

docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml --profile vos up -d vos-studio-mcp vos-studio-bff

echo "Checking VOS MCP at $MCP_HEALTH_URL"
curl -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors "$MCP_HEALTH_URL"
echo

echo "Checking VOS BFF at $BFF_HEALTH_URL"
curl -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors "$BFF_HEALTH_URL"
echo

docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml --profile vos ps vos-studio-mcp vos-studio-bff
