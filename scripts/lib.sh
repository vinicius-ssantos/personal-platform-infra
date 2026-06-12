#!/usr/bin/env bash
# Shared helpers sourced by smoke-*.sh scripts.
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
#   or after cd "$ROOT_DIR": source scripts/lib.sh

# Verify an env file exists; exit with a clear message if missing.
require_env_file() {
  local env_file="${1:-.env}"
  if [[ ! -f "$env_file" ]]; then
    echo "Missing $env_file. Copy .env.example to .env and fill local secrets first." >&2
    exit 1
  fi
}

# Probe a URL with retries (up to 20 × 1 s). Prints the label and exits on failure.
wait_health() {
  local url="$1" label="${2:-}"
  echo "Checking ${label:-$url}"
  curl -fsS --retry 20 --retry-delay 1 --retry-connrefused --retry-all-errors "$url"
  echo
}
