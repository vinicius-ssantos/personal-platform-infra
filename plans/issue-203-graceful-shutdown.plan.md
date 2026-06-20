# Implementar graceful shutdown patch e rollout-restart tooling

## Metadata

- Slug: issue-203-graceful-shutdown
- Source: Issue #203
- Planner model: opencode/deepseek-v4-flash
- Intended executor model: opencode/deepseek-v4-flash-free
- Risk: low
- Created at: 2026-06-19

## Objective

Adicionar graceful shutdown aos 9 Deployments via patch k8s e criar script/recipe padronizado de rollout-restart manual, seguindo os mesmos padrões existentes (`update-strategy-patch.yaml`, `wake-github.sh`).

## Scope

- `k8s/base/graceful-shutdown-patch.yaml` (novo)
- `k8s/base/kustomization.yaml` (adicionar resource)
- `scripts/rollout-restart.sh` (novo)
- `Justfile` (nova recipe)
- `docs/runbook.md` (nova seção)
- `docs/lifecycle.md` (nota complementar)

## Out of scope

- Alterar `update-strategy-patch.yaml` ou qualquer mecanismo existente.
- Alterar replicas, probes, env vars, secrets ou image tags.
- Alterar overlay específico (local ou VPS) — o patch é global como o de update-strategy.
- Adicionar ADR nova ou alterar pipeline de deploy.
- Qualquer alteração em runtime de cluster — apenas arquivos.

## Safety constraints

- Não ler secrets, kubeconfig, `.env`, `.env.*`, `terraform.tfvars`.
- Não executar `kubectl`, `helm`, `terraform apply` ou qualquer comando destrutivo.
- Não fazer deploy, merge, release ou delete.
- Confirmar branch não é `main`.

## Pre-checks

- [ ] Ler `k8s/base/update-strategy-patch.yaml` para entender o padrão de JSON6902 patch.
- [ ] Ler `k8s/base/kustomization.yaml` para ver onde inserir o novo resource.
- [ ] Ler `scripts/wake-github.sh` para entender o padrão de script operacional.
- [ ] Ler `Justfile` para ver receitas `logs`, `wake-*`, `smoke-*` como referência.
- [ ] Ler `docs/runbook.md` para identificar seção adequada.
- [ ] Ler `docs/lifecycle.md` para identificar seção adequada.

## Atomic tasks

### Task 1 — Inspecionar padrões existentes

- Agent: explorer
- Type: read
- Files likely touched:
  - `k8s/base/update-strategy-patch.yaml`
  - `k8s/base/kustomization.yaml`
  - `scripts/wake-github.sh`
  - `Justfile`
  - `docs/runbook.md`
  - `docs/lifecycle.md`
- Instruction:
  - Ler cada arquivo para entender o padrão antes de criar/editr.
  - Retornar os trechos relevantes: estrutura do patch JSON6902, posição no kustomization.yaml, estrutura do script operacional, recipes do Justfile que usam `target`.
- Validation:
  - Arquivos lidos com sucesso e trechos registrados.
- Acceptance criteria:
  - Conhecimento dos padrões documentado para as tasks seguintes.
- Rollback:
  - N/A — task read-only.

### Task 2 — Criar graceful-shutdown-patch.yaml

- Agent: infra-engineer
- Type: edit
- Files likely touched:
  - `k8s/base/graceful-shutdown-patch.yaml` (novo)
- Instruction:
  - Criar `k8s/base/graceful-shutdown-patch.yaml` no mesmo estilo de `update-strategy-patch.yaml`.
  - Patch JSON6902 que adiciona:
    - `spec.template.spec.terminationGracePeriodSeconds: 30`
    - `spec.template.spec.containers[0].lifecycle.preStop.exec.command: ["/bin/sh", "-c", "sleep 5"]`
  - Usar `target:` com `kind: Deployment` e `managed-by: platform` (label), sem filtro de namespace.
  - Validar sintaxe YAML.
- Validation:
  - `kubectl kustomize k8s/base` mostra os campos nos Deployments.
- Acceptance criteria:
  - Patch criado, YAML válido, kustomize renderiza sem erro.
- Rollback:
  - `git rm k8s/base/graceful-shutdown-patch.yaml`.

### Task 3 — Registrar patch no kustomization.yaml

- Agent: infra-engineer
- Type: edit
- Files likely touched:
  - `k8s/base/kustomization.yaml`
- Instruction:
  - Adicionar `graceful-shutdown-patch.yaml` na lista de `patchesStrategicMerge` (ou `patches`, conforme o estilo usado por `update-strategy-patch.yaml`).
  - Posicionar logo após `update-strategy-patch.yaml` para manter agrupamento lógico.
- Validation:
  - `kubectl kustomize k8s/base` mostra `terminationGracePeriodSeconds` e `lifecycle` nos 9 Deployments, `spec.strategy` inalterado.
  - `kubectl kustomize k8s/overlays/local` renderiza sem erro.
  - `kubectl kustomize k8s/overlays/vps` renderiza sem erro.
- Acceptance criteria:
  - kustomization.yaml atualizado, renders funcionam.
- Rollback:
  - Reverter a linha adicionada em `k8s/base/kustomization.yaml`.

### Task 4 — Criar scripts/rollout-restart.sh

- Agent: scripter
- Type: edit
- Files likely touched:
  - `scripts/rollout-restart.sh` (novo)
- Instruction:
  - Criar script seguindo o padrão de `scripts/wake-github.sh`: `set -euo pipefail`, função `usage()`, parâmetro posicional `$1` (nome do serviço ou `all`).
  - Se `$1` for `all`, rodar `kubectl rollout restart` em todos os namespaces relevantes (mcp, bff, vos).
  - Se `$1` for um serviço específico, extrair namespace da convenção (ex: `github-unified-mcp` → namespace `mcp`; `vos-studio-bff` → `bff`).
  - Depois do rollout, rodar `kubectl rollout status --timeout=120s -n <ns> deployment/<nome>`.
  - Incluir `set -euo pipefail`, `errexit`, funções `info`/`error`.
- Validation:
  - `bash -n scripts/rollout-restart.sh` sem erro.
  - `shellcheck scripts/rollout-restart.sh` sem warning novo.
- Acceptance criteria:
  - Script criado, sintaxe válida.
- Rollback:
  - `git rm scripts/rollout-restart.sh`.

### Task 5 — Adicionar recipe no Justfile

- Agent: scripter
- Type: edit
- Files likely touched:
  - `Justfile`
- Instruction:
  - Adicionar recipe `rollout-restart target="all":` que chama `scripts/rollout-restart.sh {{target}}`.
  - Seguir o mesmo padrão de `logs target="all":`.
  - Agrupar próximo das recipes de operação (wake, sleep, logs).
- Validation:
  - `just --list` mostra `rollout-restart`.
  - `just rollout-restart --dry-run` mostra o comando esperado.
- Acceptance criteria:
  - Recipe adicionada, `just` reconhece.
- Rollback:
  - Reverter a recipe adicionada.

### Task 6 — Atualizar docs/runbook.md

- Agent: orquestrador (ou scripter)
- Type: edit
- Files likely touched:
  - `docs/runbook.md`
- Instruction:
  - Adicionar seção "Rollout-restart" próxima das seções "Wake" e "Sleep".
  - Documentar: `just rollout-restart <serviço>` ou `just rollout-restart all`.
  - Explicar que é restart sem troca de imagem — não é deploy de código novo.
  - Referenciar `docs/image-pinning.md` para deploy de código novo.
- Validation:
  - Revisão visual do markdown.
- Acceptance criteria:
  - Documentação adicionada, markdown válido.
- Rollback:
  - Reverter as linhas adicionadas.

### Task 7 — Atualizar docs/lifecycle.md

- Agent: orquestrador (ou scripter)
- Type: edit
- Files likely touched:
  - `docs/lifecycle.md`
- Instruction:
  - Adicionar nota de que rollout-restart é ortogonal à ownership de réplicas (sleep/wake pattern).
- Validation:
  - Revisão visual do markdown.
- Acceptance criteria:
  - Nota adicionada, markdown válido.
- Rollback:
  - Reverter as linhas adicionadas.

### Task 8 — Revisão final (reviewer)

- Agent: reviewer
- Type: review
- Files likely touched:
  - Todos os arquivos modificados.
- Instruction:
  - Revisar todos os arquivos alterados.
  - Verificar consistência: kustomize build, sintaxe shell, markdown, escopo vs plano.
  - Verificar que nenhum arquivo fora do escopo foi alterado.
  - Verificar que nenhum placeholder `REPLACE_WITH_` ou segredo foi commitado.
- Validation:
  - N/A — é a task de revisão.
- Acceptance criteria:
  - Nenhum problema encontrado, ou problemas documentados.
- Rollback:
  - N/A.

## Final validation

- [ ] `kubectl kustomize k8s/base` mostra `terminationGracePeriodSeconds: 30` e `lifecycle.preStop` nos 9 Deployments.
- [ ] `kubectl kustomize k8s/base` mostra `spec.strategy` inalterado.
- [ ] `kubectl kustomize k8s/overlays/local` renderiza sem erro.
- [ ] `kubectl kustomize k8s/overlays/vps` renderiza sem erro.
- [ ] `bash -n scripts/rollout-restart.sh`.
- [ ] `just --list` mostra `rollout-restart`.
- [ ] `git diff` revisado — apenas os 6 arquivos do escopo.
- [ ] Nenhum segredo, `.env` ou kubeconfig no diff.

## PR notes

- Summary: Adiciona graceful shutdown (terminationGracePeriodSeconds: 30 + preStop sleep 5) via patch k8s global, e script/recipe de rollout-restart manual.
- Tests: kustomize build x3, bash -n, just --list.
- Risk: baixo — patch reusa mecanismo existente e testado (update-strategy-patch.yaml); script é utilitário manual.
