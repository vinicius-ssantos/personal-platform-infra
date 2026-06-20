#!/usr/bin/env bash
set -euo pipefail

# PATH fallback para GitHub CLI no WSL
if uname -s | grep -qi "linux" && grep -qi microsoft /proc/version 2>/dev/null; then
  export PATH="$PATH:/mnt/c/Program Files/GitHub CLI"
fi

ISSUE="${1:-}"
if [[ -z "$ISSUE" ]]; then
  echo "usage: scripts/ai-solve-issue.sh <issue-number>" >&2
  exit 2
fi

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "required command not found: $1" >&2
    exit 127
  fi
}

require_cmd git
require_cmd opencode

# WSL: gh pode ser apenas gh.exe (binfmt_misc nao resolve bare name)
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

OUTFILE="$(mktemp -t opencode_run.XXXXXX)"
ISSUE_FILE="$(mktemp -t issue_${ISSUE}.XXXXXX.md)"
PR_BODY_FILE="$(mktemp -t pr_body_${ISSUE}.XXXXXX.md)"

cleanup() {
  local rc=$?
  rm -f "$ISSUE_FILE" "$PR_BODY_FILE"
  if [ "$rc" -eq 0 ]; then
    rm -f "$OUTFILE"
  else
    echo "" >&2
    echo "Log salvo em: $OUTFILE" >&2
  fi
}
trap cleanup EXIT

slugify() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' \
    | cut -c1-60
}

BASE_BRANCH="${AI_SOLVE_BASE_BRANCH:-main}"
AGENT="${AI_SOLVE_AGENT:-solve-issue}"
PREFLIGHT_TIMEOUT="${AI_SOLVE_PREFLIGHT_TIMEOUT:-60}"
SOLVE_TIMEOUT="${AI_SOLVE_TIMEOUT:-1800}"
RUN_FORMAT="${OPENCODE_RUN_FORMAT:-default}"

ISSUE_TITLE="$("$GH_CMD" issue view "$ISSUE" --json title --jq '.title')"
ISSUE_BODY="$("$GH_CMD" issue view "$ISSUE" --json body --jq '.body // ""')"
ISSUE_LABELS="$("$GH_CMD" issue view "$ISSUE" --json labels --jq '[.labels[].name] | join(", ")')"
ISSUE_URL="$("$GH_CMD" issue view "$ISSUE" --json url --jq '.url')"

SLUG="$(slugify "$ISSUE_TITLE")"
if [[ -z "$SLUG" ]]; then
  SLUG="solve"
fi

TARGET_BRANCH="${AI_SOLVE_BRANCH:-ai/issue-${ISSUE}-${SLUG}}"

if [[ -n "${AI_SOLVE_MODEL:-}" ]]; then
  MODELS=("$AI_SOLVE_MODEL")
else
  MODELS=(
    "opencode/deepseek-v4-flash-free"
    "openrouter/deepseek/deepseek-v4-flash-free"
    "deepseek-v4-flash-free"
  )
fi

cat > "$ISSUE_FILE" <<EOF
# Issue #$ISSUE — $ISSUE_TITLE

URL: $ISSUE_URL
Labels: ${ISSUE_LABELS:-none}

## Body

$ISSUE_BODY
EOF

CURRENT_BRANCH="$(git branch --show-current)"
if [[ "$CURRENT_BRANCH" != "$TARGET_BRANCH" ]]; then
  if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "working tree has pending changes; commit/stash them before running solve-issue" >&2
    exit 1
  fi

  if git show-ref --verify --quiet "refs/heads/$TARGET_BRANCH"; then
    git checkout "$TARGET_BRANCH"
  else
    git fetch origin "$BASE_BRANCH" --quiet || true
    if git show-ref --verify --quiet "refs/remotes/origin/$BASE_BRANCH"; then
      git checkout -b "$TARGET_BRANCH" "origin/$BASE_BRANCH"
    else
      git checkout -b "$TARGET_BRANCH" "$BASE_BRANCH"
    fi
  fi
fi

PROMPT=$(cat <<EOF
Voce esta no repositorio personal-platform-infra.

Trabalhe a issue #$ISSUE ate deixar o diff pronto para PR.

Contexto da issue ja foi coletado pelo wrapper:

$(cat "$ISSUE_FILE")

Contrato de execucao:
- Use docs/ai-solve-issue-workflow.md como guia.
- Crie ou atualize um plano em plans/ quando fizer sentido.
- Edite os arquivos necessarios dentro do escopo da issue.
- Rode apenas validacoes locais permitidas pelo agente.
- Nao rode git add, git commit, git push ou gh pr create.
- Nao faca merge.
- Nao altere GitHub Actions, deploy, VPS, secrets ou arquivos sensiveis.
- Se houver blocker externo, registre no plano/resposta e deixe o diff seguro.
- Ao final, informe resumo, validacoes e limitacoes.
EOF
)

PREFLIGHT_PROMPT="responda apenas: ok"

run_opencode() {
  local timeout_seconds="$1"
  local model="$2"
  local prompt="$3"

  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_seconds" opencode run \
      --model "$model" \
      --agent "$AGENT" \
      --format "$RUN_FORMAT" \
      "$prompt" 2>&1 | tee "$OUTFILE"
    return "${PIPESTATUS[0]}"
  fi

  opencode run \
    --model "$model" \
    --agent "$AGENT" \
    --format "$RUN_FORMAT" \
    "$prompt" 2>&1 | tee "$OUTFILE"
  return "${PIPESTATUS[0]}"
}

SELECTED_MODEL=""
for model in "${MODELS[@]}"; do
  [[ -z "$model" ]] && continue
  : > "$OUTFILE"

  echo ""
  echo "==== Preflight modelo: $model | agente: $AGENT ===="
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
echo "==== Preparando diff da issue #$ISSUE com modelo: $SELECTED_MODEL ===="
echo "Branch: $TARGET_BRANCH"
echo "Timeout de execucao: ${SOLVE_TIMEOUT}s"
echo ""

set +e
run_opencode "$SOLVE_TIMEOUT" "$SELECTED_MODEL" "$PROMPT"
rc=$?
set -e

if grep -q "ProviderModelNotFoundError" "$OUTFILE" 2>/dev/null; then
  echo "" >&2
  echo "Modelo deixou de estar disponivel durante a execucao: $SELECTED_MODEL" >&2
  echo "Rode: opencode models opencode --refresh" >&2
  exit 1
fi

if [ "$rc" -eq 124 ]; then
  echo "" >&2
  echo "TIMEOUT (${SOLVE_TIMEOUT}s) — execucao da issue nao terminou dentro do prazo." >&2
  echo "Nao houve fallback automatico apos o inicio da execucao para evitar diff parcial inconsistente." >&2
  echo "Proximos passos:" >&2
  echo "  1. Ver log: cat '$OUTFILE'" >&2
  echo "  2. Aumentar timeout: AI_SOLVE_TIMEOUT=3600 just ai-solve-issue $ISSUE" >&2
  echo "  3. Debug em JSON: OPENCODE_RUN_FORMAT=json just ai-solve-issue $ISSUE" >&2
  exit 124
fi

if [ "$rc" -ne 0 ]; then
  echo "" >&2
  echo "ERRO (codigo $rc) durante execucao com modelo $SELECTED_MODEL." >&2
  echo "Veja o log: cat '$OUTFILE'" >&2
  exit "$rc"
fi

if [[ -z "$(git status --porcelain --untracked-files=no)" ]]; then
  echo "opencode concluiu, mas nao deixou alteracoes no working tree." >&2
  exit 1
fi

git diff --check

BLOCKED=0
while IFS= read -r line; do
  file="${line:3}"
  file="${file##* -> }"
  case "$file" in
    .env|.env.*|*/.env|*/.env.*|*terraform.tfvars|*kubeconfig*|secrets/*|*/secrets/*|.github/workflows/*)
      echo "arquivo proibido no diff: $file" >&2
      BLOCKED=1
      ;;
  esac
done < <(git status --porcelain --untracked-files=no)

if [ "$BLOCKED" -ne 0 ]; then
  echo "abortando antes de commit por arquivo proibido" >&2
  exit 1
fi

COMMIT_TITLE="${AI_SOLVE_COMMIT_TITLE:-chore(ai): resolve issue #$ISSUE}"
PR_TITLE="${AI_SOLVE_PR_TITLE:-Resolve issue #$ISSUE: $ISSUE_TITLE}"

git add -A
git commit -m "$COMMIT_TITLE"
git push -u origin "$TARGET_BRANCH"

cat > "$PR_BODY_FILE" <<EOF
## Summary

Automated local solve-issue run for #$ISSUE.

Issue: $ISSUE_URL

## Model

- Agent: $AGENT
- Model: $SELECTED_MODEL

## Validation

- git diff --check
- Additional validations are reported by the agent output/log when available.

Closes #$ISSUE
EOF

if "$GH_CMD" pr view "$TARGET_BRANCH" --json url --jq '.url' >/dev/null 2>&1; then
  PR_URL="$("$GH_CMD" pr view "$TARGET_BRANCH" --json url --jq '.url')"
else
  PR_URL="$("$GH_CMD" pr create --base "$BASE_BRANCH" --head "$TARGET_BRANCH" --title "$PR_TITLE" --body-file "$PR_BODY_FILE")"
fi

echo ""
echo "PR aberta: $PR_URL"
echo "Merge manual obrigatório."
