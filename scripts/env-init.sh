#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-.env}"

if [[ -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE já existe. Edite manualmente ou remova-o para recriar." >&2
  exit 1
fi

cp .env.example "$ENV_FILE"
echo "$ENV_FILE criado a partir de .env.example."
echo ""
echo "Preencha os seguintes valores antes de subir os serviços:"
echo ""
echo "  GITHUB_TOKEN          — https://github.com/settings/tokens"
echo "                          scopes necessários: repo, read:packages"
echo ""
echo "  MCP_BEARER_TOKEN      — token livre, gere com:"
echo "                          openssl rand -hex 32"
echo ""
echo "  MCP_SERVER_API_KEY    — token livre, gere com:"
echo "                          openssl rand -hex 32"
echo ""
echo "  SOCIAL_MCP_ACCESS_TOKEN — token da plataforma social configurada"
echo ""
echo "Depois de preencher: just check-env && just compose-up"
