#!/usr/bin/env bash
set -uo pipefail

ISSUE="${1:-}"
if [[ -z "$ISSUE" ]]; then
  echo "usage: scripts/ai-solve-issue.sh <issue-number>" >&2
  exit 2
fi

OUTFILE="$(mktemp -t opencode_run.XXXXXX)"
cleanup() {
  local rc=$?
  if [ "$rc" -eq 0 ]; then
    rm -f "$OUTFILE"
  else
    echo "" >&2
    echo "Log salvo em: $OUTFILE" >&2
  fi
}
trap cleanup EXIT

if [[ -n "${AI_SOLVE_MODEL:-}" ]]; then
  MODELS=("$AI_SOLVE_MODEL")
else
  MODELS=(
    "opencode/deepseek-v4-flash-free"
    "openrouter/deepseek/deepseek-v4-flash-free"
    "deepseek-v4-flash-free"
  )
fi

PREFLIGHT_TIMEOUT="${AI_SOLVE_PREFLIGHT_TIMEOUT:-60}"
SOLVE_TIMEOUT="${AI_SOLVE_TIMEOUT:-1800}"
RUN_FORMAT="${OPENCODE_RUN_FORMAT:-default}"
PROMPT="Siga docs/ai-solve-issue-workflow.md para trabalhar a issue #${ISSUE} ate abrir PR."
PREFLIGHT_PROMPT="responda apenas: ok"

run_opencode() {
  local timeout_seconds="$1"
  local model="$2"
  local prompt="$3"

  if command -v timeout &>/dev/null; then
    timeout "$timeout_seconds" opencode run \
      --model "$model" \
      --agent orquestrador \
      --format "$RUN_FORMAT" \
      "$prompt" 2>&1 | tee "$OUTFILE"
    return "${PIPESTATUS[0]}"
  fi

  opencode run \
    --model "$model" \
    --agent orquestrador \
    --format "$RUN_FORMAT" \
    "$prompt" 2>&1 | tee "$OUTFILE"
  return "${PIPESTATUS[0]}"
}

SELECTED_MODEL=""

for model in "${MODELS[@]}"; do
  [[ -z "$model" ]] && continue
  : > "$OUTFILE"

  echo ""
  echo "==== Preflight modelo: $model ===="
  echo ""

  set +e
  run_opencode "$PREFLIGHT_TIMEOUT" "$model" "$PREFLIGHT_PROMPT"
  rc=$?
  set -e

  if [ "$rc" -eq 0 ]; then
    SELECTED_MODEL="$model"
    echo ""
    echo "Modelo selecionado: $SELECTED_MODEL"
    break
  fi

  if grep -q "ProviderModelNotFoundError" "$OUTFILE" 2>/dev/null; then
    echo "  -> Modelo nao disponivel, tentando proximo..."
    continue
  fi

  if [ "$rc" -eq 124 ]; then
    echo "  -> Preflight excedeu ${PREFLIGHT_TIMEOUT}s, tentando proximo modelo..."
    continue
  fi

  echo "  -> Preflight falhou com codigo $rc, tentando proximo modelo..."
done

if [[ -z "$SELECTED_MODEL" ]]; then
  echo "Nenhum modelo disponivel passou no preflight." >&2
  echo "Rode: opencode models opencode --refresh" >&2
  echo "Ou defina AI_SOLVE_MODEL=provider/model com um modelo valido." >&2
  exit 1
fi

: > "$OUTFILE"
echo ""
echo "==== Executando issue #$ISSUE com modelo: $SELECTED_MODEL ===="
echo "Timeout de execucao: ${SOLVE_TIMEOUT}s"
echo ""

set +e
run_opencode "$SOLVE_TIMEOUT" "$SELECTED_MODEL" "$PROMPT"
rc=$?
set -e

if [ "$rc" -eq 0 ]; then
  echo ""
  echo "OK - Concluido com modelo: $SELECTED_MODEL"
  exit 0
fi

if grep -q "ProviderModelNotFoundError" "$OUTFILE" 2>/dev/null; then
  echo "" >&2
  echo "Modelo deixou de estar disponivel durante a execucao: $SELECTED_MODEL" >&2
  echo "Rode: opencode models opencode --refresh" >&2
  exit 1
fi

if [ "$rc" -eq 124 ]; then
  echo "" >&2
  echo "TIMEOUT (${SOLVE_TIMEOUT}s) — execucao da issue nao terminou dentro do prazo." >&2
  echo "" >&2
  echo "Isso nao significa que outro modelo resolveria com seguranca." >&2
  echo "Nao houve fallback automatico apos o inicio da execucao para evitar diff parcial inconsistente." >&2
  echo "" >&2
  echo "Proximos passos:" >&2
  echo "  1. Ver log: cat '$OUTFILE'" >&2
  echo "  2. Aumentar timeout: AI_SOLVE_TIMEOUT=3600 just ai-solve-issue $ISSUE" >&2
  echo "  3. Debug em JSON: OPENCODE_RUN_FORMAT=json just ai-solve-issue $ISSUE" >&2
  exit 124
fi

echo "" >&2
echo "ERRO (codigo $rc) durante execucao com modelo $SELECTED_MODEL." >&2
echo "Veja o log: cat '$OUTFILE'" >&2
exit "$rc"
