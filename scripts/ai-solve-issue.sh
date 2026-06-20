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
PREFLIGHT_TIMEOUT="${AI_SOLVE_PREFLIGHT_TIMEOUT:-120}"
SOLVE_TIMEOUT="${AI_SOLVE_TIMEOUT:-3600}"
RUN_FORMAT="${OPENCODE_RUN_FORMAT:-default}"

ISSUE_TITLE="$("$GH_CMD" issue view "$ISSUE" --json title --jq '.title')"
ISSUE_BODY="$("$GH_CMD" issue view "$ISSUE" --json body --jq '.body // ""')"
ISSUE_LABELS="$("$GH_CMD" issue view "$ISSUE" --json labels --jq '[.labels[].name] | join(", ")')"
ISSUE_URL="$("$GH_CMD" issue view "$ISSUE" --json url --jq '.url')"

# Execution-risk classification (issue #223). This is a heuristic over the
# issue's own title/body/labels, run before any agent work starts — there is
# no diff yet to inspect, so it cannot know the real blast radius, only guess
# from what the issue says it's about. AI_SOLVE_RISK_OVERRIDE lets a human
# correct a wrong guess without editing this script.
#
# Categories, in matching precedence order (first match wins):
#   security-sensitive, blocked-external, ops-runtime, infra,
#   test-only, docs-only, code-medium, code-small (default)
classify_issue_risk() {
  local text title_lower title_type
  text="$(printf '%s\n%s\n%s' "$ISSUE_TITLE" "$ISSUE_BODY" "$ISSUE_LABELS" | tr '[:upper:]' '[:lower:]')"
  title_lower="$(printf '%s' "$ISSUE_TITLE" | tr '[:upper:]' '[:lower:]')"
  # Conventional-commit prefix, e.g. "docs(adr): ..." -> "docs", "security(sandbox): ..." -> "security".
  # This repo's issue titles consistently follow this convention; it is a far
  # more reliable signal than scanning the body for loose keywords.
  title_type="$(printf '%s' "$title_lower" | sed -nE 's/^([a-z]+)(\([^)]*\))?:.*/\1/p')"

  if echo "$text" | grep -qE '(^|[^a-z])(secret|credential|password|token|auth[a-z]*|vulnerab[a-z]*|cve[-_][0-9]|rbac|privilege escalation|exploit|prompt injection|\bsops\b|age key)([^a-z]|$)'; then
    echo "security-sensitive"
    return
  fi
  if [[ "$title_type" == "security" ]]; then
    echo "security-sensitive"
    return
  fi
  if echo "$text" | grep -qE 'blocked.on|blocked-external|waiting.on|depends.on.external|external.blocker'; then
    echo "blocked-external"
    return
  fi
  if echo "$text" | grep -qE 'ops-runtime|production incident|\brollback\b|on-call|canary deploy'; then
    echo "ops-runtime"
    return
  fi
  if echo "$text" | grep -qE 'terraform|kubernetes|\bk8s\b|\bansible\b|\bvps\b|kustomize|\bhelm\b|docker-compose|dockerfile|\binfra\b|\bufw\b|deploy-vps|\.github/workflows'; then
    echo "infra"
    return
  fi
  if [[ "$title_type" == "test" ]] || echo "$text" | grep -qE '(^|[^a-z])test-only([^a-z]|$)'; then
    echo "test-only"
    return
  fi
  if [[ "$title_type" == "docs" || "$title_type" == "doc" ]] || echo "$text" | grep -qE 'docs-only|documentation only'; then
    echo "docs-only"
    return
  fi
  if echo "$text" | grep -qE '\brefactor\b|\bmigrate\b|\brewrite\b|\bredesign\b|breaking change'; then
    echo "code-medium"
    return
  fi
  echo "code-small"
}

# Categories that must not auto-create a PR without explicit operator opt-in
# (AI_SOLVE_ALLOW_HIGH_RISK=1). Matches the routing table in issue #223.
HIGH_RISK_CATEGORIES=(infra ops-runtime security-sensitive blocked-external)

is_high_risk_category() {
  local category="$1" c
  for c in "${HIGH_RISK_CATEGORIES[@]}"; do
    [[ "$c" == "$category" ]] && return 0
  done
  return 1
}

RISK_CATEGORY="${AI_SOLVE_RISK_OVERRIDE:-$(classify_issue_risk)}"

echo ""
echo "==== Risk classification: $RISK_CATEGORY ===="
if is_high_risk_category "$RISK_CATEGORY"; then
  echo "High-risk category — will not auto-create a PR unless AI_SOLVE_ALLOW_HIGH_RISK=1 is set."
fi
echo ""

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

Classificacao de risco (heuristica do wrapper, baseada no titulo/corpo/labels
da issue, antes de qualquer mudanca real): $RISK_CATEGORY
$(if is_high_risk_category "$RISK_CATEGORY"; then cat <<RISK
Esta e uma categoria de alto risco. O wrapper NAO vai criar PR
automaticamente para este resultado, mesmo com diff valido, a menos que o
operador defina AI_SOLVE_ALLOW_HIGH_RISK=1. Priorize deixar um plano claro em
plans/ explicando o que seria feito e por que precisa de revisao humana antes
de qualquer commit, em vez de assumir que o PR sera aberto automaticamente.
RISK
fi)

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
- Se ao investigar a issue voce concluir que os criterios de aceite ja estao
  satisfeitos e nenhuma mudanca de codigo e necessaria, NAO crie um diff
  artificial so para ter algo a commitar. Em vez disso, termine sua resposta
  com estas duas linhas, nesta ordem exata, cada uma sozinha em sua linha:
  SOLVE_ISSUE_RESULT=NOOP
  <uma frase curta explicando por que a issue ja esta resolvida>
EOF
)

PREFLIGHT_PROMPT="responda apenas: ok"

run_opencode_model() {
  local timeout_seconds="$1"
  local model="$2"
  local prompt="$3"

  if command -v timeout >/dev/null 2>&1; then
    timeout "$timeout_seconds" opencode run \
      --model "$model" \
      --format "$RUN_FORMAT" \
      "$prompt" 2>&1 | tee "$OUTFILE"
    return "${PIPESTATUS[0]}"
  fi

  opencode run \
    --model "$model" \
    --format "$RUN_FORMAT" \
    "$prompt" 2>&1 | tee "$OUTFILE"
  return "${PIPESTATUS[0]}"
}

run_opencode_agent() {
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

assert_agent_available() {
  : > "$OUTFILE"
  echo ""
  echo "==== Verificando agente: $AGENT ===="
  echo ""

  if ! opencode agent list 2>&1 | tee "$OUTFILE" | grep -q "\b${AGENT}\b"; then
    echo "Agente '$AGENT' nao encontrado pelo OpenCode." >&2
    echo "Esperado: .opencode/agents/${AGENT}.md" >&2
    echo "Rode: opencode agent list" >&2
    echo "Ou teste: opencode run --agent $AGENT --model <model> \"responda apenas: ok\"" >&2
    exit 1
  fi
}

SELECTED_MODEL=""
for model in "${MODELS[@]}"; do
  [[ -z "$model" ]] && continue
  : > "$OUTFILE"

  echo ""
  echo "==== Preflight modelo: $model ===="
  echo ""

  set +e
  run_opencode_model "$PREFLIGHT_TIMEOUT" "$model" "$PREFLIGHT_PROMPT"
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
    echo "  -> Preflight de modelo excedeu ${PREFLIGHT_TIMEOUT}s, tentando proximo modelo..."
    continue
  fi

  echo "  -> Preflight de modelo falhou com codigo $rc, tentando proximo modelo..."
done

if [[ -z "$SELECTED_MODEL" ]]; then
  echo "Nenhum modelo disponivel passou no preflight de modelo." >&2
  echo "Rode: opencode models opencode --refresh" >&2
  echo "Ou defina AI_SOLVE_MODEL=provider/model com um modelo valido." >&2
  exit 1
fi

assert_agent_available

: > "$OUTFILE"
echo ""
echo "==== Preflight agente: $AGENT | modelo: $SELECTED_MODEL ===="
echo ""

set +e
run_opencode_agent "$PREFLIGHT_TIMEOUT" "$SELECTED_MODEL" "$PREFLIGHT_PROMPT"
rc=$?
set -e

if [ "$rc" -eq 124 ]; then
  echo "Preflight do agente '$AGENT' excedeu ${PREFLIGHT_TIMEOUT}s." >&2
  echo "Isso isola o problema em agent/config/plugin, nao no modelo." >&2
  echo "Debug sugerido:" >&2
  echo "  opencode run --pure --print-logs --log-level DEBUG --agent $AGENT --model $SELECTED_MODEL \"responda apenas: ok\"" >&2
  exit 124
fi

if [ "$rc" -ne 0 ]; then
  echo "Preflight do agente '$AGENT' falhou com codigo $rc." >&2
  echo "Veja o log: cat '$OUTFILE'" >&2
  exit "$rc"
fi

: > "$OUTFILE"
echo ""
echo "==== Preparando diff da issue #$ISSUE com modelo: $SELECTED_MODEL ===="
echo "Branch: $TARGET_BRANCH"
echo "Timeout de execucao: ${SOLVE_TIMEOUT}s"
echo ""

set +e
run_opencode_agent "$SOLVE_TIMEOUT" "$SELECTED_MODEL" "$PROMPT"
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

NOOP_MARKER="SOLVE_ISSUE_RESULT=NOOP"

if [[ -z "$(git status --porcelain --untracked-files=no)" ]]; then
  if grep -q "^${NOOP_MARKER}$" "$OUTFILE" 2>/dev/null; then
    NOOP_REASON="$(grep -A1 "^${NOOP_MARKER}$" "$OUTFILE" | tail -n1)"
    echo ""
    echo "NOOP: a issue #$ISSUE ja parece estar resolvida — nenhuma mudanca foi necessaria."
    if [[ -n "$NOOP_REASON" && "$NOOP_REASON" != "$NOOP_MARKER" ]]; then
      echo "Motivo informado pelo agente: $NOOP_REASON"
    fi
    echo "Nenhum commit, push ou PR sera criado."
    exit 0
  fi
  echo "opencode concluiu, mas nao deixou alteracoes no working tree." >&2
  echo "Nenhuma evidencia de NOOP ($NOOP_MARKER) foi encontrada no log." >&2
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

if is_high_risk_category "$RISK_CATEGORY" && [[ "${AI_SOLVE_ALLOW_HIGH_RISK:-}" != "1" ]]; then
  echo "" >&2
  echo "Categoria de risco '$RISK_CATEGORY' nao cria PR automaticamente." >&2
  echo "O diff preparado pelo agente permanece no working tree (branch: $TARGET_BRANCH) para revisao manual." >&2
  echo "Para permitir PR automatico nesta categoria: AI_SOLVE_ALLOW_HIGH_RISK=1 just ai-solve-issue $ISSUE" >&2
  exit 3
fi

COMMIT_TITLE="${AI_SOLVE_COMMIT_TITLE:-chore(ai): resolve issue #$ISSUE}"
PR_TITLE="${AI_SOLVE_PR_TITLE:-Resolve issue #$ISSUE: $ISSUE_TITLE}"

git add -A
git commit -m "$COMMIT_TITLE"
git push -u origin "$TARGET_BRANCH"

MERGE_BASE="$(git merge-base HEAD "origin/$BASE_BRANCH" 2>/dev/null || echo "")"
if [[ -n "$MERGE_BASE" ]]; then
  FILES_CHANGED="$(git diff --stat "$MERGE_BASE" HEAD)"
else
  FILES_CHANGED="$(git show --stat --format='' HEAD)"
fi

cat > "$PR_BODY_FILE" <<EOF
## Summary

Automated solve-issue run for #$ISSUE: $ISSUE_TITLE.

Issue: $ISSUE_URL

## Risk

- Category: \`$RISK_CATEGORY\` (heuristic classification, see docs/ai-solve-issue-workflow.md)
- External blockers: see "Limitations" below and the full run log for anything the agent flagged

## Agent

- Agent: $AGENT
- Model: $SELECTED_MODEL

## Files changed

\`\`\`
$FILES_CHANGED
\`\`\`

## Validation

- git diff --check
- Additional validations are reported by the agent output/log when available.

## Sandbox result

Not enabled for this run. Sandbox-backed validation is tracked separately (#218–#222) and is not yet wired into solve-issue.

## Limitations

See the agent's own response in the run log for anything it flagged as a blocker, assumption, or out-of-scope item. The wrapper does not parse or summarize this automatically.

## Manual review checklist

- [ ] Diff matches the issue's acceptance criteria
- [ ] No changes outside the issue's stated scope
- [ ] Risk category above looks correct for what actually changed
- [ ] CI passes

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
