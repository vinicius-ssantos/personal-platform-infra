#!/bin/bash
# Automated guardrail tests — feeds controlled JSON inputs to ai-guardrail-check.sh
# and verifies exit codes.
#
# Usage: bash scripts/test-ai-guardrail.sh
#   exit 0 = all tests pass
#   exit 1 = one or more tests fail

set -euo pipefail

info()  { printf "[INFO]  %s\n" "$*"; }
ok()    { printf "[OK]    %s\n" "$*"; }
fail()  { printf "[FAIL]  %s\n" "$*" >&2; }

GUARDRAIL="bash scripts/ai-guardrail-check.sh"
PASS=0
FAIL=0

# Helper: run the guardrail with a JSON input on stdin, expect a specific exit code.
expect_exit() {
  local expected_exit=$1
  local label=$2
  local json=$3

  local actual_exit=0
  printf '%s' "$json" | bash scripts/ai-guardrail-check.sh 2>/dev/null || actual_exit=$?

  if [ "$actual_exit" -eq "$expected_exit" ]; then
    ok "$label (exit $actual_exit)"
    PASS=$((PASS + 1))
  else
    fail "$label: expected exit $expected_exit, got $actual_exit"
    printf '  input: %s\n' "$json" >&2
    FAIL=$((FAIL + 1))
  fi
}

echo ""
info "=== Guardrail Rule 1: Secret file reads ==="

expect_exit 2 \
  "Block: cat .env" \
  '{"tool_input":{"command":"cat .env"}}'

expect_exit 2 \
  "Block: cat secrets/prod.enc.yaml" \
  '{"tool_input":{"command":"cat secrets/prod.enc.yaml"}}'

expect_exit 2 \
  "Block: head -n5 .env" \
  '{"tool_input":{"command":"head -n5 .env"}}'

expect_exit 2 \
  "Block: less secrets/db.enc.yaml" \
  '{"tool_input":{"command":"less secrets/db.enc.yaml"}}'

expect_exit 2 \
  "Block: cat ~/.age/personal-platform.txt" \
  '{"tool_input":{"command":"cat ~/.age/personal-platform.txt"}}'

echo ""
info "=== Guardrail Rule 2: kubectl delete on VPS ==="
info "(only blocks when kubectl context matches vps/k3s/prod/remote)"
info "(in CI this test is informational — no kubectl context is set)"

# With no kubectl context, this should pass through (exit 0)
expect_exit 0 \
  "Allow: kubectl delete (no VPS context in CI)" \
  '{"tool_input":{"command":"kubectl delete pod foo"}}'

echo ""
info "=== Guardrail Rule 3: git push --force on main/master ==="

expect_exit 2 \
  "Block: git push --force origin main" \
  '{"tool_input":{"command":"git push --force origin main"}}'

expect_exit 2 \
  "Block: git push -f origin master" \
  '{"tool_input":{"command":"git push -f origin master"}}'

expect_exit 2 \
  "Block: git push --force-with-lease origin main" \
  '{"tool_input":{"command":"git push --force-with-lease origin main"}}'

echo ""
info "=== Guardrail Rule 4: SOPS plaintext dump ==="

expect_exit 2 \
  "Block: sops --decrypt secrets/prod.enc.yaml" \
  '{"tool_input":{"command":"sops --decrypt secrets/prod.enc.yaml"}}'

expect_exit 2 \
  "Block: sops -d secrets/prod.enc.yaml" \
  '{"tool_input":{"command":"sops -d secrets/prod.enc.yaml"}}'

# Piped to grep/jq should be allowed (intentional review pattern)
expect_exit 0 \
  "Allow: sops --decrypt | grep KEY" \
  '{"tool_input":{"command":"sops --decrypt secrets/prod.enc.yaml | grep API_KEY"}}'

expect_exit 0 \
  "Allow: sops -d secrets/prod.enc.yaml | jq .key" \
  '{"tool_input":{"command":"sops -d secrets/prod.enc.yaml | jq .key"}}'

echo ""
info "=== Safe commands (should always allow) ==="

expect_exit 0 \
  "Allow: git push origin feat/my-branch" \
  '{"tool_input":{"command":"git push origin feat/my-branch"}}'

expect_exit 0 \
  "Allow: kubectl get pods" \
  '{"tool_input":{"command":"kubectl get pods"}}'

expect_exit 0 \
  "Allow: just compose-up" \
  '{"tool_input":{"command":"just compose-up"}}'

expect_exit 0 \
  "Allow: bash scripts/ai-dx-check.sh" \
  '{"tool_input":{"command":"bash scripts/ai-dx-check.sh"}}'

expect_exit 0 \
  "Allow: empty input (no command)" \
  '{"tool_input":{}}'

echo ""
echo "============================================"
if [ "$FAIL" -eq 0 ]; then
  info "All guardrail tests passed ($PASS/$PASS)"
  exit 0
else
  fail "$FAIL test(s) failed, $PASS passed"
  exit 1
fi