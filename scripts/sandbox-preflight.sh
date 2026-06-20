#!/usr/bin/env bash
# Sandbox safe-test profile — preflight step (.sandbox/manifest.yaml).
#
# Non-destructive sanity checks only: shell syntax and tool availability.
# No network access, no secrets, no writes outside this process's own
# temp/log output. Safe to run on a developer machine directly, or inside
# the eventual sandbox runner (#221).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

FAIL=0

check_syntax() {
  local f="$1"
  if [ ! -f "$f" ]; then
    echo "[SKIP] $f (not found)"
    return
  fi
  if bash -n "$f" 2>&1; then
    echo "[OK]   bash -n $f"
  else
    echo "[FAIL] bash -n $f"
    FAIL=1
  fi
}

echo "=== Sandbox preflight: shell syntax ==="
for f in scripts/*.sh; do
  check_syntax "$f"
done

echo ""
echo "=== Sandbox preflight: tooling ==="
if command -v just >/dev/null 2>&1; then
  echo "[OK]   just available"
  just --list >/dev/null
  echo "[OK]   just --list runs"
else
  echo "[FAIL] just not found"
  FAIL=1
fi

if command -v bash >/dev/null 2>&1; then
  echo "[OK]   bash available ($(bash --version | head -n1))"
else
  echo "[FAIL] bash not found"
  FAIL=1
fi

echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "Preflight passed."
  exit 0
else
  echo "Preflight failed." >&2
  exit 1
fi
