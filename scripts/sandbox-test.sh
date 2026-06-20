#!/usr/bin/env bash
# Sandbox safe-test profile — test step (.sandbox/manifest.yaml).
#
# Runs this repo's existing non-destructive validation: the AI DX check.
# No network access, no secrets, no writes outside this process's own
# temp/log output. Safe to run on a developer machine directly, or inside
# the eventual sandbox runner (#221).
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "=== Sandbox test: AI DX check ==="
bash scripts/ai-dx-check.sh
