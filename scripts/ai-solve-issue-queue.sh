#!/usr/bin/env bash
set -euo pipefail

# Low-risk autonomous issue queue for solve-issue (issue #227).
#
# This is the last, most autonomous phase of the solve-issue workflow
# (docs/ai-solve-issue-workflow.md): instead of a human naming a specific
# issue, this script picks at most one eligible issue from a label-based
# queue and runs the exact same scripts/ai-solve-issue.sh on it. It never
# merges and never bypasses sandbox validation — auto-picked work has no
# human in the loop choosing the issue, so this script holds itself to a
# stricter bar than a human-triggered run: if sandbox validation tooling
# isn't available, it refuses to run at all instead of falling back.

# PATH fallback para GitHub CLI no WSL
if uname -s | grep -qi "linux" && grep -qi microsoft /proc/version 2>/dev/null; then
  export PATH="$PATH:/mnt/c/Program Files/GitHub CLI"
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "required command not found: $1" >&2
    exit 127
  fi
}

require_cmd git

if command -v gh >/dev/null 2>&1; then
  GH_CMD="gh"
elif command -v gh.exe >/dev/null 2>&1; then
  GH_CMD="gh.exe"
else
  echo "required command not found: gh" >&2
  exit 127
fi

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

DRY_RUN="${AI_SOLVE_QUEUE_DRY_RUN:-0}"
READY_LABEL="ai:ready"
BLOCKED_LABEL="ai:blocked"

# Auto-pick must be able to actually run sandbox validation, not just
# request it — unlike scripts/ai-solve-issue.sh's own AI_SOLVE_SANDBOX
# fallback (which proceeds unvalidated when tooling is missing, for a human
# who explicitly chose to run a specific issue), an issue nobody pointed at
# by name must not slip through unvalidated.
PYTHON_BIN=""
if [[ -n "${PYTHON:-}" ]]; then
  PYTHON_BIN="$PYTHON"
elif command -v python3 >/dev/null 2>&1 && python3 -c "" >/dev/null 2>&1; then
  PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1 && python -c "" >/dev/null 2>&1; then
  PYTHON_BIN="python"
elif command -v py >/dev/null 2>&1; then
  PYTHON_BIN="py -3"
fi

if [[ -z "$PYTHON_BIN" ]]; then
  echo "Auto-pick requires a Python interpreter for sandbox validation (issue #227) — none found on PATH." >&2
  exit 1
fi

if ! $PYTHON_BIN -c "import yaml" >/dev/null 2>&1; then
  echo "Auto-pick requires pyyaml for sandbox validation (issue #227) — not installed." >&2
  echo "Install with: pip install -r scripts/requirements-sandbox.txt" >&2
  exit 1
fi

if [[ ! -f .sandbox/manifest.yaml ]]; then
  echo "Auto-pick requires .sandbox/manifest.yaml — not found in this repository." >&2
  exit 1
fi

if ! $PYTHON_BIN -c '
import sys
import yaml

with open(".sandbox/manifest.yaml", encoding="utf-8") as f:
    manifest = yaml.safe_load(f) or {}

sys.exit(0 if "safe-test" in (manifest.get("profiles") or {}) else 1)
'; then
  echo "Auto-pick requires a 'safe-test' profile declared in .sandbox/manifest.yaml — not found." >&2
  exit 1
fi

echo ""
echo "==== Low-risk issue queue (label: $READY_LABEL) ===="
echo ""

ELIGIBLE_JSON="$("$GH_CMD" issue list --state open --label "$READY_LABEL" \
  --json number,title,body,labels,createdAt --limit 200)"

ELIGIBLE_TSV="$(printf '%s' "$ELIGIBLE_JSON" | $PYTHON_BIN "$REPO_ROOT/scripts/ai_solve_queue_filter.py")"

if [[ -z "$ELIGIBLE_TSV" ]]; then
  echo "No eligible issues found."
  echo "Eligibility: open, has '$READY_LABEL', has one of ai:risk-low/ai:docs-only/ai:test-only,"
  echo "does not have '$BLOCKED_LABEL', and title/body do not mention forbidden scopes"
  echo "(secrets, deploy, VPS, credentials, release, destroy, GitHub Actions changes)."
  exit 0
fi

echo "Eligible issues (oldest first):"
while IFS=$'\t' read -r num title; do
  echo "  #$num  $title"
done <<<"$ELIGIBLE_TSV"

if [[ "$DRY_RUN" == "1" ]]; then
  echo ""
  echo "AI_SOLVE_QUEUE_DRY_RUN=1 — listing only, not running."
  exit 0
fi

SELECTED_NUM="$(head -n1 <<<"$ELIGIBLE_TSV" | cut -f1)"
SELECTED_TITLE="$(head -n1 <<<"$ELIGIBLE_TSV" | cut -f2-)"

echo ""
echo "Selected issue #$SELECTED_NUM: $SELECTED_TITLE"
echo ""

"$GH_CMD" issue comment "$SELECTED_NUM" --body "Auto-pick: starting an automated solve-issue run for this issue from the low-risk queue (issue #227). Sandbox validation is required for this run. A PR will be opened for review if it succeeds; merge remains manual."

AI_SOLVE_SANDBOX=1 bash "$REPO_ROOT/scripts/ai-solve-issue.sh" "$SELECTED_NUM"
