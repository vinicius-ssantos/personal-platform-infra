# Contributing

Guia para contribuir com mudanças neste repositório de infraestrutura.

## Antes de começar

Leia `CLAUDE.md` — ele descreve a estrutura, convenções e armadilhas conhecidas do projeto. É a referência principal para qualquer mudança.

Leia também o ADR relevante para a área que você vai mudar. Cada decisão arquitetural está documentada em `docs/adr/` e explica o contexto e as trocas aceitas.

## Tipos de mudança e fluxo

### Mudança em manifestos Kubernetes

1. Editar em `k8s/base/apps/<serviço>/` ou nos overlays
2. Validar localmente:
   ```bash
   just k8s-local-up
   just k3d-secrets
   just smoke-k3d
   ```
3. Abrir PR — CI valida YAML, Kustomize e sintaxe de scripts
4. Merge em `main` → deploy automático no VPS quando `k8s/**` muda e `VPS_KUBECONFIG` está configurado

**Antes de mudar wiring de Compose ou k8s, verifique o contrato upstream** (ver `docs/runtime-contracts.md`).

### Mudança em scripts ou Ansible

1. Editar o arquivo
2. Validar sintaxe:
   ```bash
   bash -n scripts/<arquivo>.sh
   ```
3. Abrir PR — CI valida sintaxe automaticamente

### Adicionar um novo serviço

Checklist completo (não pule etapas):

- [ ] Criar `k8s/base/apps/<nome>/` com `deployment.yaml`, `service.yaml`, `configmap.yaml` (se necessário) e `kustomization.yaml`
- [ ] Adicionar em `k8s/base/kustomization.yaml`
- [ ] Adicionar réplicas=1 em `k8s/overlays/local/replicas-local.yaml`
- [ ] Adicionar env overrides em `k8s/overlays/local/` e `k8s/overlays/vps/runtime-env-vps.yaml` conforme necessário
- [ ] Adicionar serviço em `compose/docker-compose.yml` com profile, ports e healthcheck
- [ ] Adicionar variáveis em `.env.example`
- [ ] Adicionar ao `k8s/overlays/vps/ingress-vps.yaml`
- [ ] Criar smoke script em `scripts/smoke-<nome>.sh` (e `.ps1` se relevante)
- [ ] Adicionar recipe em `Justfile` para o smoke
- [ ] Atualizar `docs/service-integration-matrix.md`
- [ ] Atualizar `docs/architecture.md` (tabela de serviços)
- [ ] Atualizar `cloudflare/workers/status-page/src/index.ts` (DEFAULT_SERVICES)
- [ ] Atualizar `cloudflare/workers/status-page/wrangler.toml.example`

### Criar um ADR

Crie um ADR quando a mudança envolve uma decisão arquitetural significativa que afeta o projeto a longo prazo — escolha de ferramenta, padrão de infraestrutura, mudança de convenção.

Você não precisa de ADR para mudanças operacionais como adicionar um serviço seguindo padrões já estabelecidos.

Formato:

```markdown
# ADR XXXX — Título curto

**Data:** YYYY-MM-DD
**Status:** Accepted | Proposed | Superseded

## Contexto

Por que essa decisão era necessária.

## Decisão

O que foi decidido.

## Consequências

Positivos e negativos aceitos.
```

Adicione ao índice em `docs/adr/README.md`.

## Convenções de código

### YAML / Kubernetes

- Use `camelCase` para chaves de recursos Kubernetes (padrão da API)
- Deployments de aplicação nascem com `replicas: 0` no base — réplicas sobem via overlay ou wake scripts
- Nunca coloque valores sensíveis em `k8s/base` — apenas referências a Secrets
- Nunca coloque valores locais (`localhost`, `development`, `false` para COOKIE_SECURE) em `k8s/base`

O CI detecta violações dessas regras via `scripts/check-policy.sh`.

### Shell scripts

- Sempre comece com `#!/usr/bin/env bash` e `set -euo pipefail`
- Use `"${VAR:-default}"` para variáveis com fallback
- Funções de diagnóstico: `echo "ERROR: ..." >&2; exit 1`
- Scripts `.sh` devem funcionar no Linux/CI; scripts `.ps1` são para Windows/PowerShell

### Justfile

- Recipes que chamam scripts Bash: `bash scripts/<nome>.sh`
- Recipes que chamam PowerShell: `powershell.exe -ExecutionPolicy Bypass -File scripts/<nome>.ps1`
- Recipes que dependem de `.env`: adicione `check-env` como dependência quando relevante

### Terraform

- `terraform fmt` antes de qualquer commit (verificado pelo CI e pre-commit)
- Variáveis sensíveis via `TF_VAR_*` — nunca em `terraform.tfvars` commitado
- Mantenha `terraform.tfvars.example` atualizado quando adicionar variáveis

## CI

O CI (`ci.yml`) valida:

1. Sintaxe de todos os `.yml`/`.yaml`
2. `docker compose config` (valida Compose sem subir containers)
3. Sintaxe de shell scripts (`bash -n`)
4. Sintaxe de PowerShell scripts
5. `scripts/check-policy.sh` — detecta valores locais em `k8s/base`
6. `scripts/check-env-drift.sh` — detecta drift entre `.env.example`, Compose e `check-env.sh`
7. Terraform `fmt`, `init -backend=false`, `validate`
8. Kustomize overlays (`kubectl kustomize`)

O CI **não** executa smoke tests — eles requerem Docker e k3d e são responsabilidade do autor do PR antes de abrir.

## Pre-commit hooks

```bash
just hooks-install
```

Instala:
- `check-yaml` — valida sintaxe YAML
- `end-of-file-fixer` e `trailing-whitespace`
- `gitleaks` — detecta tokens e secrets acidentais no diff
- `terraform fmt`
- `docker compose config`

**O gitleaks é crítico.** Se você commitar um token acidentalmente, assuma que ele está comprometido e rotacione-o imediatamente.

## Tamanho e escopo dos PRs

PRs pequenos e focados são preferidos:

- Uma mudança de serviço por PR
- ADR separado do código que implementa a decisão quando possível
- Não misture mudanças de observabilidade com mudanças de serviço

## O que não fazer

- Não commite `.env`, `*.enc.yaml` decriptado, kubeconfig ou qualquer secret real
- Não adicione `localhost`, `development` ou `change-me` em `k8s/base` — use overlays
- Não mude réplicas diretamente no base — use `replicas-local.yaml` no overlay local
- Não adicione Dockerfiles — imagens vêm de repos upstream
- Não adicione frontends ao cluster — vão para Cloudflare Pages
- Não adicione databases ao cluster (exceto casos excepcionais com ADR) — vão para serviços externos
- Não ignore falhas do CI — corrija antes de pedir review
