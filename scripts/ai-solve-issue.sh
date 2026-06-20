#!/usr/bin/env bash
set -euo pipefail

ISSUE="${1:-}"
if [[ -z "$ISSUE" ]]; then
  echo "usage: scripts/ai-solve-issue.sh <issue-number>" >&2
  exit 2
fi

opencode run \
  --model opencode/deepseek-v4-flash \
  --agent orquestrador \
  "Siga docs/ai-solve-issue-workflow.md para trabalhar a issue #${ISSUE} ate abrir PR."
