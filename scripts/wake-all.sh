#!/usr/bin/env bash
set -euo pipefail

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Waking all platform services ==="
bash "$SCRIPTS_DIR/wake-github.sh"
bash "$SCRIPTS_DIR/wake-deploy.sh"
bash "$SCRIPTS_DIR/wake-social.sh"
bash "$SCRIPTS_DIR/wake-vos.sh"
echo ""
echo "All services awake."
