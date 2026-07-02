#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-.env}"
BASE_CONFIG="${OPENCODE_BASE_CONFIG:-opencode.json}"
OUT_CONFIG="${OPENCODE_LOCAL_CONFIG:-opencode.local.json}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE not found. Run: just env-init" >&2
  exit 1
fi

if [[ ! -f "$BASE_CONFIG" ]]; then
  echo "ERROR: $BASE_CONFIG not found." >&2
  exit 1
fi

read_env_value() {
  local key="$1"
  local value
  value="$(grep -E "^${key}=" "$ENV_FILE" | tail -n 1 | cut -d= -f2- | tr -d '\r' || true)"
  if [[ "$value" == \"*\" && "$value" == *\" ]]; then
    value="${value:1:${#value}-2}"
  elif [[ "$value" == \'*\' && "$value" == *\' ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s' "$value"
}

require_env_value() {
  local key="$1"
  local value
  value="$(read_env_value "$key")"
  if [[ -z "$value" || "$value" == "change-me" || "$value" == "paste-"* ]]; then
    echo "ERROR: $key must be set in $ENV_FILE." >&2
    exit 1
  fi
  printf '%s' "$value"
}

if [[ -n "${PYTHON:-}" ]]; then
  PYTHON_CMD=("$PYTHON")
elif command -v python3 >/dev/null 2>&1; then
  PYTHON_CMD=(python3)
elif command -v python >/dev/null 2>&1; then
  PYTHON_CMD=(python)
elif command -v py >/dev/null 2>&1; then
  PYTHON_CMD=(py -3)
else
  echo "ERROR: python3, python, or py is required." >&2
  exit 1
fi

URL="$(require_env_value OPENCODE_MCP_GATEWAY_URL)"
BEARER="$(require_env_value OPENCODE_MCP_GATEWAY_BEARER_TOKEN)"
PLATFORM="$(require_env_value OPENCODE_MCP_GATEWAY_PLATFORM_TOKEN)"
ENABLED_RAW="$(read_env_value OPENCODE_MCP_GATEWAY_ENABLED)"
ENABLED_RAW="${ENABLED_RAW:-false}"

case "${ENABLED_RAW,,}" in
  true|1|yes|on) ENABLED_JSON=true ;;
  false|0|no|off) ENABLED_JSON=false ;;
  *)
    echo "ERROR: OPENCODE_MCP_GATEWAY_ENABLED must be true or false." >&2
    exit 1
    ;;
esac

export OPENCODE_MCP_GATEWAY_URL="$URL"
export OPENCODE_MCP_GATEWAY_BEARER_TOKEN="$BEARER"
export OPENCODE_MCP_GATEWAY_PLATFORM_TOKEN="$PLATFORM"
export OPENCODE_MCP_GATEWAY_ENABLED_JSON="$ENABLED_JSON"
export OPENCODE_BASE_CONFIG="$BASE_CONFIG"
export OPENCODE_LOCAL_CONFIG="$OUT_CONFIG"

"${PYTHON_CMD[@]}" - <<'PY'
from __future__ import annotations

import json
import os
from pathlib import Path

base_path = Path(os.environ["OPENCODE_BASE_CONFIG"])
out_path = Path(os.environ["OPENCODE_LOCAL_CONFIG"])

config = json.loads(base_path.read_text(encoding="utf-8"))
gateway = config.setdefault("mcp", {}).setdefault("central-mcp-gateway", {})
gateway["type"] = "remote"
gateway["url"] = os.environ["OPENCODE_MCP_GATEWAY_URL"]
gateway["headers"] = {
    "Authorization": f"Bearer {os.environ['OPENCODE_MCP_GATEWAY_BEARER_TOKEN']}",
    "X-Platform-Token": os.environ["OPENCODE_MCP_GATEWAY_PLATFORM_TOKEN"],
}
gateway["enabled"] = os.environ["OPENCODE_MCP_GATEWAY_ENABLED_JSON"] == "true"

out_path.write_text(
    json.dumps(config, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY

echo "Rendered $OUT_CONFIG from $BASE_CONFIG and $ENV_FILE."
echo "Do not commit $OUT_CONFIG."
