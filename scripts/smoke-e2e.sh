#!/usr/bin/env bash
# End-to-end smoke for central-mcp-gateway: authenticate and exercise the real
# request path (initialize -> tools/list -> tools/call) plus an allowlist
# rejection. This catches breakage that per-service health checks cannot:
# gateway<->upstream auth, tool allowlist, and routing.
#
# The gateway must already be running. Point at it via GATEWAY_URL:
#   - Compose:          http://localhost:8040  (default)
#   - k3d port-forward: http://localhost:18040
#
# The public bearer token is read from CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN
# or, if unset, from $ENV_FILE (default .env).
#
# Usage:
#   just smoke-e2e
#   GATEWAY_URL=http://localhost:18040 bash scripts/smoke-e2e.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE_URL="${GATEWAY_URL:-http://localhost:8040}"
BASE_URL="${BASE_URL%/}"
ENV_FILE="${ENV_FILE:-$ROOT_DIR/.env}"

# An allowlisted tool (GATEWAY_TOOL_ALLOWLIST) and one that must be rejected.
ALLOWED_TOOL="${E2E_ALLOWED_TOOL:-gateway.status}"
BLOCKED_TOOL="${E2E_BLOCKED_TOOL:-github.delete_branch}"

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required for the E2E smoke." >&2
  exit 1
fi

BEARER="${CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN:-}"
if [[ -z "$BEARER" && -f "$ENV_FILE" ]]; then
  BEARER="$(grep -E '^CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN=' "$ENV_FILE" | tail -n1 | cut -d= -f2- | tr -d '"')"
fi
if [[ -z "$BEARER" ]]; then
  echo "ERROR: CENTRAL_MCP_GATEWAY_PUBLIC_BEARER_TOKEN not set (env or $ENV_FILE)." >&2
  exit 1
fi

step() { echo; echo "--- $* ---"; }

# POST a JSON-RPC body to the gateway with auth. Fails the script on HTTP error.
mcp() {
  curl -fsS -X POST "$BASE_URL/mcp" \
    -H "Authorization: Bearer ${BEARER}" \
    -H "Content-Type: application/json" \
    --data "$1"
}

echo "E2E smoke against $BASE_URL (allowed=$ALLOWED_TOOL, blocked=$BLOCKED_TOOL)"

step "1. Health"
curl -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors "$BASE_URL/healthz" >/dev/null
echo "OK: /healthz"

step "2. MCP initialize"
mcp '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"e2e-smoke","version":"1.0"}}}' \
  | jq -e '.result != null' >/dev/null
echo "OK: initialize returned a result"

step "3. tools/list — allowlisted tool present"
TOOLS="$(mcp '{"jsonrpc":"2.0","id":2,"method":"tools/list"}')"
echo "$TOOLS" | jq -e --arg t "$ALLOWED_TOOL" '.result.tools[]? | select(.name == $t)' >/dev/null \
  || { echo "FAIL: $ALLOWED_TOOL not present in tools/list" >&2; exit 1; }
echo "OK: $ALLOWED_TOOL present"

step "4. tools/call $ALLOWED_TOOL"
mcp "$(jq -nc --arg t "$ALLOWED_TOOL" '{jsonrpc:"2.0",id:3,method:"tools/call",params:{name:$t,arguments:{}}}')" \
  | jq -e '.result != null and (.error == null)' >/dev/null \
  || { echo "FAIL: tools/call $ALLOWED_TOOL did not return a result" >&2; exit 1; }
echo "OK: $ALLOWED_TOOL call succeeded"

step "5. non-allowlisted tool is rejected"
# Do not use -f here: a rejection may be an HTTP 4xx OR a JSON-RPC error body.
BODY_FILE="$(mktemp)"; trap 'rm -f "$BODY_FILE"' EXIT
CODE="$(curl -sS -o "$BODY_FILE" -w '%{http_code}' -X POST "$BASE_URL/mcp" \
  -H "Authorization: Bearer ${BEARER}" -H "Content-Type: application/json" \
  --data "$(jq -nc --arg t "$BLOCKED_TOOL" '{jsonrpc:"2.0",id:4,method:"tools/call",params:{name:$t,arguments:{}}}')")"
if [[ "$CODE" -ge 400 ]] || jq -e '.error != null' "$BODY_FILE" >/dev/null 2>&1; then
  echo "OK: $BLOCKED_TOOL correctly rejected (http=$CODE)"
else
  echo "FAIL: $BLOCKED_TOOL was not rejected (http=$CODE)" >&2
  cat "$BODY_FILE" >&2
  exit 1
fi

echo
echo "E2E smoke passed."
