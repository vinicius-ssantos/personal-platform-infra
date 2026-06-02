#!/usr/bin/env bash
set -euo pipefail

if [[ -f .env ]]; then
  echo "ERROR: .env already exists. Edit it manually or remove it to recreate." >&2
  exit 1
fi

cp .env.example .env

# Auto-generate random values for local-only tokens.
# These never leave the machine; any random string works.
_set() {
  local key="$1" value="$2"
  if grep -q "^${key}=change-me" .env; then
    sed -i "s|^${key}=change-me|${key}=${value}|" .env
  fi
}

MCP_BEARER_TOKEN_VAL="$(openssl rand -hex 32)"
MCP_SERVER_API_KEY_VAL="$(openssl rand -hex 32)"
GW_BEARER_VAL="$(openssl rand -hex 32)"
GW_OAUTH_SECRET_VAL="$(openssl rand -hex 32)"
GW_SESSION_SECRET_VAL="$(openssl rand -hex 32)"

_set MCP_BEARER_TOKEN         "$MCP_BEARER_TOKEN_VAL"
_set MCP_SERVER_API_KEY       "$MCP_SERVER_API_KEY_VAL"
_set CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN "$GW_BEARER_VAL"
_set CENTRAL_MCP_GATEWAY_OAUTH_CLIENT_SECRET "$GW_OAUTH_SECRET_VAL"
_set CENTRAL_MCP_GATEWAY_SESSION_SECRET      "$GW_SESSION_SECRET_VAL"

cat <<'MSG'
.env created. Local tokens were auto-generated.

Still required — fill these manually:
  GITHUB_TOKEN            https://github.com/settings/tokens (scopes: repo, read:packages)
  SOCIAL_MCP_ACCESS_TOKEN social integration access token

Then run:
  just check-env   # validate before starting
  just compose-up  # Compose path
  just local-up    # k3d path (cluster + secrets + smoke)
MSG
