#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"

echo "=== Stopping Compose ==="
if [[ -f "$ENV_FILE" ]]; then
  docker compose -f compose/docker-compose.yml --env-file "$ENV_FILE" down -v 2>/dev/null || true
else
  docker compose -f compose/docker-compose.yml down -v 2>/dev/null || true
fi

echo "=== Deleting k3d cluster ==="
if command -v k3d >/dev/null 2>&1; then
  k3d cluster delete personal-platform 2>/dev/null || true
else
  echo "k3d not found; skipping cluster delete."
fi

echo "Local environment reset. Use 'just compose-up' or 'just k8s-local-up' to start again."
