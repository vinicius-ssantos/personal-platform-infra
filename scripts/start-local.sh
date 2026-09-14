#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if [[ "${1:-}" == "--full-stack" ]]; then
  docker compose -f compose/docker-compose.yml --env-file .env --profile all up -d
  exit 0
fi

docker compose -f compose/docker-compose.yml --env-file .env \
  --profile gateway \
  --profile github \
  --profile repo-research \
  up -d
