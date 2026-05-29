#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=== Parando Compose ==="
docker compose -f compose/docker-compose.yml --env-file .env down -v 2>/dev/null || true

echo "=== Deletando cluster k3d ==="
k3d cluster delete personal-platform 2>/dev/null || true

echo "=== Removendo volumes Docker não utilizados ==="
docker volume prune -f 2>/dev/null || true

echo ""
echo "Ambiente local limpo."
echo "Para recomeçar: just compose-up  ou  just k8s-local-up"
