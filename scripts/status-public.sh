#!/usr/bin/env bash
# Probe configured public platform endpoints independently from local/k3d state.

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok() { echo -e "  ${GREEN}✓${NC} $*"; }
fail() { echo -e "  ${RED}✗${NC} $*"; }
warn() { echo -e "  ${YELLOW}~${NC} $*"; }

TIMEOUT_SECONDS="${PUBLIC_STATUS_TIMEOUT_SECONDS:-10}"
ENV_FILE="${ENV_FILE:-.env}"

if [[ -f "$ENV_FILE" ]]; then
  set -a
  # The local .env is often edited from Windows, so strip CRLF when sourcing.
  # shellcheck disable=SC1090
  source <(tr -d '\r' < "$ENV_FILE")
  set +a
fi

trim_trailing_slash() {
  local value="$1"
  value="${value//$'\r'/}"
  echo "${value%/}"
}

probe() {
  local name="$1"
  local env_name="$2"
  local health_path="${3:-/health}"
  local base_url="${!env_name:-}"

  echo ""
  echo "=== ${name} ==="

  if [[ -z "$base_url" ]]; then
    warn "${env_name} not set — skipped"
    return 0
  fi

  base_url="$(trim_trailing_slash "$base_url")"
  local url="${base_url}${health_path}"

  if ! command -v curl >/dev/null 2>&1; then
    fail "curl is not installed"
    return 1
  fi

  local response http_code curl_status
  local headers=()
  if [[ -n "${PUBLIC_EDGE_TOKEN:-}" ]]; then
    headers+=(--header "X-Platform-Token: ${PUBLIC_EDGE_TOKEN}")
  fi

  response="$(curl \
    --silent \
    --show-error \
    --location \
    "${headers[@]}" \
    --max-time "$TIMEOUT_SECONDS" \
    --write-out '\n%{http_code}' \
    "$url" 2>&1)"
  curl_status=$?

  if [[ $curl_status -ne 0 ]]; then
    fail "unreachable: ${url}"
    echo "    ${response}"
    return 1
  fi

  http_code="$(printf '%s' "$response" | tail -n 1)"

  if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
    ok "${url} -> HTTP ${http_code}"
    return 0
  fi

  fail "${url} -> HTTP ${http_code}"
  return 1
}

main() {
  echo ""
  echo "=== public endpoints ==="
  echo "timeout: ${TIMEOUT_SECONDS}s"

  local failures=0

  probe "GitHub Unified MCP" "GITHUB_MCP_PUBLIC_URL" "/healthz" || failures=$((failures + 1))
  probe "Deploy Orchestrator MCP" "DEPLOY_MCP_PUBLIC_URL" "/healthz" || failures=$((failures + 1))
  probe "Social MCP" "SOCIAL_MCP_PUBLIC_URL" || failures=$((failures + 1))
  probe "GitHub Unified MCP BFF" "GITHUB_BFF_PUBLIC_URL" "/healthz" || failures=$((failures + 1))
  probe "VOS Studio MCP" "VOS_MCP_PUBLIC_URL" || failures=$((failures + 1))
  probe "VOS Studio BFF" "VOS_BFF_PUBLIC_URL" "/healthz" || failures=$((failures + 1))
  probe "Central MCP Gateway" "CENTRAL_MCP_GATEWAY_PUBLIC_URL" "/healthz" || failures=$((failures + 1))

  echo ""
  echo "=== summary ==="
  if [[ "$failures" -eq 0 ]]; then
    ok "all configured public endpoints are healthy"
    return 0
  fi

  fail "${failures} configured public endpoint check(s) failed"
  return 1
}

main "$@"
