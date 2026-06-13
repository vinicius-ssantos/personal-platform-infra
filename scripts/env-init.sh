#!/usr/bin/env bash
set -euo pipefail

if [[ -f .env ]]; then
  echo "ERROR: .env already exists. Edit it manually or remove it to recreate." >&2
  exit 1
fi

cp .env.example .env

cat <<'MSG'
.env created from .env.example.

Fill these values before starting services:
  GITHUB_TOKEN             - https://github.com/settings/tokens (repo, read:packages)
  MCP_BEARER_TOKEN         - local bearer token, e.g. openssl rand -hex 32
  MCP_SERVER_API_KEY       - local deploy token, e.g. openssl rand -hex 32
  SOCIAL_MCP_ACCESS_TOKEN  - social integration access token
  REPO_RESEARCH_SIDECAR_API_KEY - shared gateway/sidecar token, e.g. openssl rand -hex 32
  REPO_RESEARCH_GITHUB_TOKEN - GitHub PAT used only by repo-research-sidecar
  REPO_RESEARCH_ALLOWED_REPOSITORIES - JSON array repo allowlist, e.g. '["owner/repo"]'
  CENTRAL_MCP_GATEWAY_ADMIN_TOKEN - local Admin UI token, e.g. openssl rand -hex 32

Then run:
  just check-env
  just compose-up
MSG
