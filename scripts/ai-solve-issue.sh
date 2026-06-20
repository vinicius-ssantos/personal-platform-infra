#!/usr/bin/env bash
set -uo pipefail

ISSUE="${1:-}"
if [[ -z "$ISSUE" ]]; then
  echo "usage: scripts/ai-solve-issue.sh <issue-number>" >&2
  exit 2
fi

OUTFILE="$(mktemp -t opencode_run.XXXXXX)"
trap 'rm -f "$OUTFILE"' EXIT

# Fallback de modelos gratuitos. O primeiro que funcionar é usado.
# Para forçar um modelo específico: AI_SOLVE_MODEL=provider/model
MODELS=(
  "${AI_SOLVE_MODEL:-}"
  "opencode/deepseek-v4-flash-free"
  "openrouter/deepseek/deepseek-v4-flash-free"
  "deepseek-v4-flash-free"
)

PROMPT="Siga docs/ai-solve-issue-workflow.md para trabalhar a issue #${ISSUE} ate abrir PR."

for m in "${MODELS[@]}"; do
  [[ -z "$m" ]] && continue

  echo ""
  echo "==== Modelo: $m | Issue: #$ISSUE ===="
  echo ""

  # Timeout padrão: 5 minutos. Ajuste com AI_SOLVE_TIMEOUT (segundos).
  TIMEOUT="${AI_SOLVE_TIMEOUT:-300}"

  # Roda mostrando saída ao vivo (tee) e salva em $OUTFILE
  # para detectar erro de modelo automaticamente.
  set +e
  if command -v timeout &>/dev/null; then
    timeout "$TIMEOUT" opencode run --model "$m" --agent orquestrador "$PROMPT" 2>&1 | tee "$OUTFILE"
    RC=${PIPESTATUS[0]}
  else
    opencode run --model "$m" --agent orquestrador "$PROMPT" 2>&1 | tee "$OUTFILE"
    RC=${PIPESTATUS[0]}
  fi
  set -e

  if [ $RC -eq 0 ]; then
    echo ""
    echo "OK - Concluido com modelo: $m"
    exit 0
  fi

  # Se for erro de modelo não encontrado, tenta próximo automaticamente
  if grep -q "ProviderModelNotFoundError" "$OUTFILE" 2>/dev/null; then
    echo "  -> Modelo nao disponivel, tentando proximo..."
    continue
  fi

  # Outro erro: mostra e morre
  echo ""
  echo "ERRO (codigo $RC) com modelo $m. Nao e erro de modelo - abortando."
  exit $RC
done

echo "Nenhum modelo disponível funcionou." >&2
echo "Defina AI_SOLVE_MODEL=provider/model com um modelo válido." >&2
exit 1
