# Documentar escopo do graceful shutdown patch vs rollout-restart all

## Metadata

- Slug: issue-207-graceful-shutdown-scope-docs
- Source: Issue #207
- Planner model: opencode/deepseek-v4-flash
- Intended executor model: opencode/deepseek-v4-flash-free
- Risk: low
- Created at: 2026-06-19

## Objective

Eliminar ambiguidade entre o patch global (aplica a todos Deployments, incluindo monitoring) e o `rollout-restart all` (cobre só os 9 apps principais), documentando ambos os escopos e como reiniciar monitoring separadamente.

## Scope

- `docs/runbook.md` — esclarecer escopo do `rollout-restart all`, notar que patch é global, adicionar comando para restart de monitoring
- `docs/lifecycle.md` — se aplicável, nota complementar

## Out of scope

- Criar `just rollout-restart-monitoring`
- Alterar `scripts/rollout-restart.sh`
- Alterar manifests k8s, patches ou kustomization
- Alterar CI, Justfile ou qualquer script

## Safety constraints

- Não ler secrets, kubeconfig, `.env`, `.env.*`, `terraform.tfvars`
- Não modificar nada além de `docs/runbook.md` e `docs/lifecycle.md`
- Markdown apenas — sem comandos destrutivos

## Pre-checks

- [ ] Ler seção Rollout-restart em `docs/runbook.md` (adicionada na PR #206)
- [ ] Ler seção relevante em `docs/lifecycle.md`
- [ ] Confirmar branch não é `main`

## Atomic tasks

### Task 1 — Ler estado atual da documentação

- Agent: explorer
- Type: read
- Files likely touched:
  - `docs/runbook.md`
  - `docs/lifecycle.md`
- Instruction:
  - Ler as seções de rollout-restart e graceful shutdown para saber o que já está documentado.
- Validation:
  - Leitura completa.
- Acceptance criteria:
  - Conteúdo atual conhecido.
- Rollback:
  - N/A — read-only.

### Task 2 — Atualizar docs/runbook.md

- Agent: orquestrador (edição de markdown)
- Type: edit
- Files likely touched:
  - `docs/runbook.md`
- Instruction:
  - Na seção "Rollout-restart workloads", adicionar nota explicitando:
    - `just rollout-restart all` cobre apenas os 9 deployments de aplicação (namespaces mcp, bff, vos).
    - O `graceful-shutdown-patch.yaml` é global e aplica também ao monitoring (Alloy, Grafana, Loki, Prometheus).
    - Para restartar monitoring: `kubectl rollout restart deploy -n monitoring --all` seguido de `kubectl rollout status deploy -n monitoring --timeout=120s`.
- Validation:
  - Leitura visual do markdown.
- Acceptance criteria:
  - Escopo documentado de forma clara e sem ambiguidade.
- Rollback:
  - Reverter linhas adicionadas em `docs/runbook.md`.

### Task 3 — Atualizar docs/lifecycle.md (se necessário)

- Agent: orquestrador
- Type: edit
- Files likely touched:
  - `docs/lifecycle.md`
- Instruction:
  - Verificar se faz sentido adicionar nota similar. Se a seção atual já for consistente, pular.
  - Se alterar, adicionar nota breve de que o patch de graceful shutdown é global e cobre monitoring.
- Validation:
  - Leitura visual do markdown.
- Acceptance criteria:
  - Documentação consistente com runbook.md.
- Rollback:
  - Reverter linhas adicionadas.

### Task 4 — Revisão final

- Agent: reviewer
- Type: review
- Files likely touched:
  - `docs/runbook.md`
  - `docs/lifecycle.md`
- Instruction:
  - Revisar markdown, consistência entre docs, nenhum placeholder ou segredo.
- Validation:
  - N/A.
- Acceptance criteria:
  - Apenas arquivos de documentação modificados.
- Rollback:
  - N/A.

## Final validation

- [ ] `git diff` mostra apenas `docs/runbook.md` e opcionalmente `docs/lifecycle.md`
- [ ] Nenhum placeholder `REPLACE_WITH_` ou segredo no diff
- [ ] Markdown válido (sem quebra de lista/code block)

## PR notes

- Summary: Documenta escopo do graceful shutdown patch (global, inclui monitoring) vs rollout-restart all (só apps principais). Adiciona comando para restart manual de monitoring.
- Tests: Revisão visual do markdown.
- Risk: baixo — apenas documentação.
