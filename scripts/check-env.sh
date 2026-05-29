#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-.env}"
EXAMPLE_FILE=".env.example"
ERRORS=0

if [[ ! -f "$ENV_FILE" ]]; then
  echo "ERROR: $ENV_FILE não encontrado. Execute: just env-init" >&2
  exit 1
fi

# Variáveis presentes no .env.example mas ausentes no .env
while IFS= read -r line; do
  [[ "$line" =~ ^#.*$  || -z "$line" ]] && continue
  key="${line%%=*}"
  if ! grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
    echo "MISSING: $key"
    ((ERRORS++))
  fi
done < "$EXAMPLE_FILE"

# Variáveis ainda com valor padrão 'change-me'
while IFS= read -r line; do
  [[ "$line" =~ ^#.*$ || -z "$line" ]] && continue
  key="${line%%=*}"
  if grep -q "^${key}=change-me$" "$ENV_FILE" 2>/dev/null; then
    echo "DEFAULT: $key ainda com valor padrão 'change-me'"
    ((ERRORS++))
  fi
done < "$EXAMPLE_FILE"

if [[ $ERRORS -gt 0 ]]; then
  echo ""
  echo "$ERRORS problema(s) encontrado(s) em $ENV_FILE. Corrija antes de subir os serviços." >&2
  exit 1
fi

echo ".env OK — todas as variáveis presentes e preenchidas."
