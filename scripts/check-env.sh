#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"
EXAMPLE_FILE="${EXAMPLE_FILE:-.env.example}"
ERRORS=0

required_keys=(
  GITHUB_UNIFIED_MCP_IMAGE
  DEPLOY_ORCHESTRATOR_MCP_IMAGE
  MCP_SOCIAL_IMAGE
  GITHUB_UNIFIED_MCP_BFF_IMAGE
  VOS_STUDIO_MCP_IMAGE
  VOS_STUDIO_BFF_IMAGE
  CENTRAL_MCP_GATEWAY_IMAGE
  GITHUB_TOKEN
  MCP_BEARER_TOKEN
  MCP_SERVER_API_KEY
  SOCIAL_MCP_ACCESS_TOKEN
  PUBLIC_EDGE_TOKEN
  CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN
  CENTRAL_MCP_GATEWAY_SESSION_SECRET
  CENTRAL_MCP_GATEWAY_OAUTH_ALLOWED_REDIRECT_URIS
)

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Run: just env-init" >&2
  exit 1
fi

if [[ ! -f "$EXAMPLE_FILE" ]]; then
  echo "ERROR: $EXAMPLE_FILE not found." >&2
  exit 1
fi

for key in "${required_keys[@]}"; do
  if ! grep -Eq "^${key}=" "$ENV_FILE"; then
    echo "MISSING: $key"
    ERRORS=$((ERRORS + 1))
    continue
  fi

  value="$(grep -E "^${key}=" "$ENV_FILE" | tail -n 1 | cut -d= -f2-)"
  if [[ -z "$value" || "$value" == "change-me" || "$value" == "paste-"* ]]; then
    echo "DEFAULT: $key needs a real value"
    ERRORS=$((ERRORS + 1))
  fi
done

if [[ "$ERRORS" -gt 0 ]]; then
  echo ""
  echo "$ERRORS problem(s) found in $ENV_FILE. Fix them before starting services." >&2
  exit 1
fi

echo "$ENV_FILE OK."
