#!/usr/bin/env bash
# Validate local prerequisites for working with this repo.
# Usage: just doctor   (or: bash scripts/doctor.sh)
#
# Hard requirements fail the check (exit 1); optional tools only warn.
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ERRORS=0
WARNINGS=0

ok()   { printf '  OK    %s\n' "$*"; }
miss() { printf '  FAIL  %s\n' "$*"; ERRORS=$((ERRORS + 1)); }
warn() { printf '  WARN  %s\n' "$*"; WARNINGS=$((WARNINGS + 1)); }

check_cmd() {
  local level="$1" cmd="$2" hint="$3"
  if command -v "$cmd" >/dev/null 2>&1; then
    ok "$cmd ($(command -v "$cmd"))"
  elif [[ "$level" == "required" ]]; then
    miss "$cmd not found — $hint"
  else
    warn "$cmd not found (optional) — $hint"
  fi
}

echo "Required tools:"
check_cmd required docker  "https://docs.docker.com/get-docker/"
check_cmd required kubectl "just bootstrap-local (or https://kubernetes.io/docs/tasks/tools/)"
check_cmd required k3d     "just bootstrap-local (or https://k3d.io)"
check_cmd required curl    "install via your package manager"
check_cmd required just    "just bootstrap-local (or https://just.systems)"

echo ""
echo "Optional tools:"
check_cmd optional helm             "just bootstrap-local"
check_cmd optional sops             "just bootstrap-local — needed for secrets-edit-*"
check_cmd optional age              "needed to generate/inspect age keys"
check_cmd optional terraform        "needed for terraform-plan/apply"
check_cmd optional ansible-playbook "pipx install ansible — needed for bootstrap-*"
check_cmd optional npx              "Node.js — needed for status-page-dev/deploy (wrangler)"
check_cmd optional pre-commit       "pipx install pre-commit — needed for hooks-install"

echo ""
echo "Environment:"
if command -v docker >/dev/null 2>&1; then
  if docker info >/dev/null 2>&1; then
    ok "Docker daemon is running"
  else
    miss "Docker daemon not reachable — start Docker Desktop / dockerd"
  fi
fi

if [[ -f .env ]]; then
  ok ".env exists"
  if command -v bash >/dev/null 2>&1 && [[ -x scripts/check-env.sh || -f scripts/check-env.sh ]]; then
    if bash scripts/check-env.sh >/dev/null 2>&1; then
      ok ".env passes check-env"
    else
      warn ".env present but check-env reports problems — run: just check-env"
    fi
  fi
else
  warn ".env missing — run: just env-init (Compose/smokes need it)"
fi

AGE_KEY="${SOPS_AGE_KEY_FILE:-$HOME/.age/personal-platform.txt}"
if [[ -f "$AGE_KEY" ]]; then
  ok "age key found at $AGE_KEY"
else
  warn "age key missing at $AGE_KEY — just secrets-edit-* will not work (see docs/secrets.md)"
fi

if command -v ansible-galaxy >/dev/null 2>&1; then
  if ansible-galaxy collection list community.general 2>/dev/null | grep -q community.general; then
    ok "ansible collection community.general installed"
  else
    warn "community.general missing — run: ansible-galaxy collection install -r ansible/requirements.yml"
  fi
fi

if command -v k3d >/dev/null 2>&1 && k3d cluster list 2>/dev/null | awk 'NR>1 {print $1}' | grep -qx personal-platform; then
  ok "k3d cluster personal-platform exists"
else
  warn "k3d cluster personal-platform not created yet — run: just k8s-local-up"
fi

echo ""
if [[ "$ERRORS" -gt 0 ]]; then
  echo "doctor: $ERRORS required check(s) failed, $WARNINGS warning(s)." >&2
  exit 1
fi
echo "doctor: all required checks passed, $WARNINGS warning(s)."
