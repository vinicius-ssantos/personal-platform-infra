#!/usr/bin/env bash
set -euo pipefail

ISSUE="${1:-}"
if [[ -z "$ISSUE" ]]; then
  echo "usage: scripts/ai-solve-issue.sh <issue-number>" >&2
  exit 2
fi

opencode run --command solve-issue "$ISSUE"
