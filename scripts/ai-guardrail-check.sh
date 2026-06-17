#!/bin/bash
# Claude Code PreToolUse hook — blocks dangerous bash commands
# Receives the tool call as JSON on stdin.
# Exit 0 = allow, exit 2 = block (stderr shown as reason).

set -uo pipefail

INPUT=$(cat)

# Extract the "command" field from the JSON tool_input.
# Uses sed as the primary parser (no runtime deps, handles all guardrail patterns).
# Tries jq/python only if sed returns empty (edge cases with escaped chars).
# Falls back to empty string — a parsing miss is a non-block (fail open).
_extract_command() {
  local raw=$1
  local result

  # sed — works for any command that does not contain escaped double-quotes
  result=$(printf '%s' "$raw" \
    | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -1)
  [ -n "$result" ] && { printf '%s' "$result"; return; }

  # jq — validate it actually runs before using it
  if command -v jq >/dev/null 2>&1 && jq --version >/dev/null 2>&1; then
    printf '%s' "$raw" | jq -r '.tool_input.command // empty' 2>/dev/null
    return
  fi

  # python3/python — validate they actually import sys (guards against OS stubs)
  for py in python3 python; do
    if command -v "$py" >/dev/null 2>&1 && "$py" -c "import sys" >/dev/null 2>&1; then
      printf '%s' "$raw" \
        | "$py" -c "import sys,json; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('command',''))" \
        2>/dev/null
      return
    fi
  done
}

COMMAND=$(_extract_command "$INPUT")

[ -z "$COMMAND" ] && exit 0

# ── 1. Secret file reads ─────────────────────────────────────────────────────
# Block direct reads of .env, age keys, or SOPS-encrypted material
if printf '%s' "$COMMAND" | grep -qEi \
  '(cat|head|tail|less|more|bat)\s+.*(\.env\b|\.age|secrets/.*\.enc\.yaml|AGE_KEY|SOPS_KEY)'; then
  printf '[GUARDRAIL] Blocked: direct read of a secret file.\n' >&2
  printf 'Use "just secrets-edit-*" or SOPS to inspect encrypted material.\n' >&2
  exit 2
fi

# ── 2. kubectl delete on VPS/production context ──────────────────────────────
if printf '%s' "$COMMAND" | grep -qE 'kubectl\s+delete'; then
  CURRENT_CTX=$(kubectl config current-context 2>/dev/null || echo "")
  if printf '%s' "$CURRENT_CTX" | grep -qiE 'vps|k3s|prod|remote'; then
    printf '[GUARDRAIL] Blocked: kubectl delete on VPS/production context "%s".\n' "$CURRENT_CTX" >&2
    printf 'Switch to the local k3d context first, or confirm this is intentional.\n' >&2
    exit 2
  fi
fi

# ── 3. git push --force on main / master ─────────────────────────────────────
if printf '%s' "$COMMAND" | grep -qE 'git\s+push\b.*(\s--force\b|\s-f\b)'; then
  if printf '%s' "$COMMAND" | grep -qE '\bmain\b|\bmaster\b'; then
    printf '[GUARDRAIL] Blocked: git push --force on main/master is not allowed.\n' >&2
    exit 2
  fi
fi

# ── 4. SOPS plaintext dump ───────────────────────────────────────────────────
# Block sops --decrypt piped without an explicit review intent
if printf '%s' "$COMMAND" | grep -qE 'sops\s+(--decrypt|-d)\b' \
  && ! printf '%s' "$COMMAND" | grep -qE '\|\s*(grep|jq|python|head)'; then
  printf '[GUARDRAIL] Blocked: bare "sops --decrypt" would print secrets to terminal.\n' >&2
  printf 'Pipe to grep/jq, or use "just secrets-edit-*" for interactive editing.\n' >&2
  exit 2
fi

exit 0
