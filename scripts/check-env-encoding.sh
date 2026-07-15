#!/usr/bin/env bash
# Encoding sanity check for .env, meant to be sourced (not executed) by
# check-env.sh and k3d-secrets.sh.
#
# Catches the failure mode where a tool re-encodes UTF-8 bytes as Latin-1/
# CP1252 (e.g. PowerShell ReadAllText + -replace + WriteAllText on a file
# with accented comments). Each re-encode multiplies mojibake sequences like
# "ÃƒÆ’" onto a single line, bloating it to hundreds of KB. Never edit .env
# that way — use the Edit tool for single keys or scripts/env-rotate-tokens.sh
# for bulk changes.
#
# Sets ENCODING_ERRORS to the number of problems found. Caller decides
# whether to exit.

check_env_encoding() {
  local env_file="$1"
  ENCODING_ERRORS=0

  if ! iconv -f UTF-8 -t UTF-8 "$env_file" >/dev/null 2>&1; then
    echo "ERROR: $env_file is not valid UTF-8 — likely encoding corruption." >&2
    echo "  Restore from a .env.bak.* backup (just env-backup makes these) and fix keys with the Edit tool, not PowerShell string ops." >&2
    ENCODING_ERRORS=$((ENCODING_ERRORS + 1))
  fi

  if grep -qE 'ÃƒÆ|ÃƒÂ|Ã¢â‚¬|Ã‚Â' "$env_file" 2>/dev/null; then
    echo "ERROR: $env_file contains mojibake byte sequences (ÃƒÆ..., Ã¢â‚¬... etc.) — a UTF-8 comment or value was re-encoded as Latin-1/CP1252." >&2
    echo "  Restore from a .env.bak.* backup and fix the affected line(s) with the Edit tool." >&2
    ENCODING_ERRORS=$((ENCODING_ERRORS + 1))
  fi

  local max_len
  max_len="$(awk '{ print length($0) }' "$env_file" | sort -rn | head -1)"
  if [[ "${max_len:-0}" -gt 4000 ]]; then
    echo "ERROR: $env_file has a line with $max_len characters (sane max ~4000). This is the signature of runaway encoding corruption, not a legitimate secret." >&2
    ENCODING_ERRORS=$((ENCODING_ERRORS + 1))
  fi

  return 0
}
