#!/usr/bin/env bash
set -uo pipefail

ISSUE="${1:-}"
if [[ -z "$ISSUE" ]]; then
  echo "usage: scripts/ai-solve-issue.sh <issue-number>" >&2
  exit 2
fi

OUTFILE="$(mktemp -t opencode_run.XXXXXX)"
# Só limpa em caso de sucesso. Timeout/erro mantém o log para diagnóstico.
cleanup() {
  local rc=$?
  if [ $rc -eq 0 ]; then
    rm -f "$OUTFILE"
  else
    echo ""
    echo "Log salvo em: $OUTFILE" >&2
  fi
}
trap cleanup EXIT

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

  # Timeout — mudar o modelo não vai resolver (todos usam o mesmo provider)
  if [ $RC -eq 124 ]; then
    echo ""
    echo "TIMEOUT (5min) — opencode run nao completou dentro do prazo."
    echo ""
    echo "Possiveis causas:"
    echo "  1. A execucao realmente levou mais de 5 min"
    echo "     -> Aumente o timeout: AI_SOLVE_TIMEOUT=600 just ai-solve-issue $ISSUE"
    echo ""
    echo "  2. O opencode run travou esperando API ou confirmacao"
    echo "     -> Veja o log: cat '$OUTFILE'"
    echo "     -> Rode manualmente para ver onde trava:"
    echo "        opencode run --agent orquestrador \"$PROMPT\""
    echo ""
    echo "  3. O orquestrador entrou em loop ou requereu input"
    echo "     -> Nesse caso, o workflow doc pode precisar de mais约束"
    exit 124
  fi

  # Outro erro: mostra e morre
  echo ""
  echo "ERRO (codigo $RC) com modelo $m. Nao e erro de modelo - abortando."
  exit $RC
done

echo "Nenhum modelo disponível funcionou." >&2
echo "Defina AI_SOLVE_MODEL=provider/model com um modelo válido." >&2
exit 1
