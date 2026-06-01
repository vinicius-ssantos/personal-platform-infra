#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
BASE_URL="${CENTRAL_MCP_GATEWAY_URL:-http://localhost:8040}"
BASE_URL="${BASE_URL%/}"

read_env() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" | tail -n 1 | cut -d= -f2-
}

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Missing $ENV_FILE. Copy .env.example to .env and fill local secrets first." >&2
  exit 1
fi

docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml --profile gateway --profile github --profile deploy --profile social --profile vos up -d central-mcp-gateway

curl -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors "$BASE_URL/healthz"
curl -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors "$BASE_URL/readyz"

bearer="$(read_env CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN)"

curl -fsS \
  -X POST "$BASE_URL/mcp" \
  -H "Authorization: Bearer ${bearer}" \
  -H "Content-Type: application/json" \
  --data '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'

docker compose --env-file "$ENV_FILE" -f compose/docker-compose.yml --profile all ps central-mcp-gateway
