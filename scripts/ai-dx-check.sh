#!/bin/bash
set -euo pipefail

info()  { echo "[INFO]  $*"; }
ok()    { echo "[OK]    $*"; }
error() { echo "[ERROR] $*" >&2; }
warn()  { echo "[WARN]  $*"; }

PASS=0
FAIL=0

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

check_file() {
  local label=$1
  local path=$2
  if [ -f "$path" ]; then
    ok "$label: $path"
    PASS=$((PASS + 1))
  else
    error "$label: $path (MISSING)"
    FAIL=$((FAIL + 1))
  fi
}

info "=== AI DX Check — Phase 1 ==="
echo ""

info "--- Claude Code agents ---"
check_file "explorer agent"      ".claude/agents/explorer.md"
check_file "infra-engineer agent" ".claude/agents/infra-engineer.md"
check_file "reviewer agent"      ".claude/agents/reviewer.md"
check_file "scripter agent"      ".claude/agents/scripter.md"

echo ""
info "--- OpenCode commands ---"
check_file "review-diff command"    ".opencode/commands/review-diff.md"
check_file "smoke-local command"    ".opencode/commands/smoke-local.md"
check_file "add-mcp-service command" ".opencode/commands/add-mcp-service.md"
check_file "debug-k3d command"     ".opencode/commands/debug-k3d.md"

echo ""
info "--- OpenCode agents (steps limits) ---"
for agent in explorer reviewer orquestrador operations scripter infra-engineer; do
  path=".opencode/agent/${agent}.md"
  if [ -f "$path" ]; then
    if grep -q "^steps:" "$path"; then
      ok "steps limit: $path"
      PASS=$((PASS + 1))
    else
      warn "steps limit missing: $path"
      FAIL=$((FAIL + 1))
    fi
  else
    warn "agent not found (skip): $path"
  fi
done

echo ""
info "--- Codex config ---"
check_file "Codex config" ".codex/config.toml"
if [ -f ".codex/config.toml" ]; then
  if grep -q 'approval_policy.*=.*"on-request"' .codex/config.toml; then
    ok "approval_policy = on-request"
    PASS=$((PASS + 1))
  else
    error "approval_policy not set to on-request in .codex/config.toml"
    FAIL=$((FAIL + 1))
  fi
  if grep -q 'persistence.*=.*"none"' .codex/config.toml; then
    ok "history.persistence = none"
    PASS=$((PASS + 1))
  else
    warn "history.persistence not set to none in .codex/config.toml"
  fi
fi

echo ""
info "--- Claude Code hooks ---"
check_file "settings.json (PreToolUse hook)" ".claude/settings.json"
check_file "ai-guardrail-check.sh"           "scripts/ai-guardrail-check.sh"
if [ -f ".claude/settings.json" ]; then
  if grep -q 'ai-guardrail-check' .claude/settings.json; then
    ok "PreToolUse hook wired to ai-guardrail-check.sh"
    PASS=$((PASS + 1))
  else
    error "PreToolUse hook in settings.json does not reference ai-guardrail-check.sh"
    FAIL=$((FAIL + 1))
  fi
fi

echo ""
info "--- AI rules ---"
check_file ".AGENTS.md" ".AGENTS.md"

echo ""
info "--- Backlog config ---"
check_file "repo list (backlog source of truth)" "docs/repos.json"
if [ -f "docs/repos.json" ]; then
  if [ -z "$PYTHON_BIN" ]; then
    warn "no python interpreter found — skipping docs/repos.json validation"
  elif $PYTHON_BIN -c "import json; json.load(open('docs/repos.json'))" 2>/dev/null; then
    ok "docs/repos.json is valid JSON"
    PASS=$((PASS + 1))
    OWNER=$($PYTHON_BIN -c "import json; print(json.load(open('docs/repos.json'))['owner'])" 2>/dev/null)
    COUNT=$($PYTHON_BIN -c "import json; print(len(json.load(open('docs/repos.json'))['repos']))" 2>/dev/null)
    ok "Owner: $OWNER, Repos: $COUNT"
    PASS=$((PASS + 1))
  else
    error "docs/repos.json is not valid JSON"
    FAIL=$((FAIL + 1))
  fi
fi

echo ""
echo "============================================"
if [ "$FAIL" -eq 0 ]; then
  info "All checks passed ($PASS/$PASS)"
  exit 0
else
  error "$FAIL check(s) failed, $PASS passed"
  exit 1
fi
