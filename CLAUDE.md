# CLAUDE.md — personal-platform-infra

Guia de contexto para AI assistants que trabalham neste repositório.

## O que é este repo

Infraestrutura centralizada para uma plataforma pessoal de MCP servers e BFFs.
Gerencia dois ambientes: **local** (Windows 11 + WSL2) e **VPS** (Ubuntu + k3s).
Não contém código de aplicação nem Dockerfiles — apenas configuração e automação.

## Estrutura de diretórios

```
ansible/          Bootstrap de máquinas (WSL2 e VPS)
  inventory/      local.ini e vps.ini
  playbooks/      bootstrap-wsl.yml, bootstrap-vps.yml, install-tools.yml

compose/          Docker Compose para desenvolvimento local
  docker-compose.yml

k8s/
  base/           Manifestos Kubernetes compartilhados entre ambientes
    apps/         Um diretório por serviço (deployment.yaml + service.yaml + kustomization.yaml)
    namespaces.yaml
  overlays/
    local/        Patches para k3d local (replicas-local.yaml, k3d-config.yaml)
    vps/          Patches para VPS k3s (vazio por ora — workloads dormem em replicas=0)

terraform/
  cloudflare/     DNS records e Tunnel (provider declarado, recursos a completar — issue #27)

scripts/          Scripts operacionais e de smoke test
  smoke-k3d.sh        Smoke completo via Kubernetes local
  smoke-*.sh          Smokes individuais via Compose
  wake-github.sh      Acorda serviços GitHub no cluster
  wake-vos.sh         Acorda serviços VOS no cluster
  sleep-all.sh        Coloca todos os serviços para dormir

secrets/
  *.enc.yaml.example  Templates de secrets (commitados)
  *.enc.yaml          Arquivos reais encriptados com SOPS (NÃO commitados)

docs/
  adr/            Architecture Decision Records (ADR 0001–0013)
  local-setup.md  Setup do ambiente local
  vps-setup.md    Setup do VPS
  secrets.md      Guia SOPS + age
  runbook.md      Operações do dia a dia

.github/workflows/
  ci.yml          Validação de YAML, Compose, Terraform, shell
  deploy-vps.yml  Aplica k8s/overlays/vps no merge para main
```

## Serviços gerenciados

| Serviço | Namespace k8s | Porta container | Health path | Status |
|---|---|---|---|---|
| `github-unified-mcp` | mcp | 8765 | `/healthz` | ready |
| `deploy-orchestrator-mcp` | mcp | 8000 | `/healthz` | ready |
| `mcp-social` | mcp | 8080 | `/health` | ready |
| `github-unified-mcp-bff` | bff | 8000 | `/healthz` | ready |
| `vos-studio-mcp` | vos | 8000 | — | wired |
| `vos-studio-bff` | bff | 8000 | — | wired |

**Portas Compose (host):** github-mcp=8765, deploy-mcp=8001, social=8080, github-bff=8010, vos-mcp=8020, vos-bff=8030

**Portas port-forward k3d (smoke):** github-mcp=19765, deploy-mcp=18000, social=18080, github-bff=18010

## Comandos essenciais

```bash
# Desenvolvimento local — Compose
just compose-up          # sobe todos os serviços
just compose-down
just compose-logs
just smoke-all           # smoke em todos os serviços ready via Compose (PowerShell)

# Desenvolvimento local — Kubernetes
just k8s-local-up        # cria cluster k3d e aplica overlay local
just k8s-local-down      # destroi o cluster
just smoke-k3d           # smoke completo via k3d (bash)

# VPS
just wake-github         # escala github-mcp + bff para 1 réplica
just wake-vos            # escala vos-studio-mcp + bff para 1 réplica
just sleep-all           # escala todos para 0
just logs                # kubectl get pods -A

# Secrets (SOPS + age)
just secrets-edit-local  # edita secrets/local.enc.yaml
just secrets-edit-vps    # edita secrets/vps.enc.yaml

# Infra
just bootstrap-local     # roda ansible bootstrap-wsl.yml
just bootstrap-vps       # roda ansible bootstrap-vps.yml
just terraform-plan      # plan Cloudflare
just tunnel              # inicia cloudflared tunnel
```

## Fluxo de desenvolvimento

### Mudança em manifestos k8s
1. Editar `k8s/base/apps/<serviço>/` ou os overlays
2. `just k8s-local-up` + `just smoke-k3d` para validar localmente
3. Abrir PR → CI valida YAML e Terraform
4. Merge → `deploy-vps.yml` aplica automaticamente no VPS

### Mudança em scripts ou Ansible
1. Editar o arquivo
2. `bash -n scripts/<arquivo>.sh` para checar sintaxe
3. Abrir PR → CI valida automaticamente

### Adicionar um novo serviço
1. Criar `k8s/base/apps/<nome>/` com `deployment.yaml`, `service.yaml`, `kustomization.yaml`
2. Adicionar em `k8s/base/kustomization.yaml`
3. Adicionar serviço em `compose/docker-compose.yml` com profile
4. Adicionar variáveis em `.env.example`
5. Criar smoke script em `scripts/smoke-<nome>.sh`
6. Adicionar recipe em `Justfile`
7. Atualizar `docs/service-integration-matrix.md`

## Convenções importantes

- **Todos os deployments nascem com `replicas: 0`** — sobem via overlay ou `kubectl scale` (ADR 0001)
- **Sem storage no cluster** — SQLite, PostgreSQL, Redis ficam fora (ADR 0002). Exceção: `mcp-social` vai receber PVC (issue #16)
- **Sem Dockerfiles aqui** — imagens vêm de repos upstream via GHCR
- **CI valida, não deploya imagens** — o CI é só validação de config (ADR 0006)
- **Kustomize, não Helm** — base+overlays, sem template engine (ADR 0007)
- **`just`, não `make`** — compatibilidade Windows/WSL2 (ADR 0008)
- **Namespaces:** `mcp` para MCP servers, `bff` para BFFs, `vos` para VOS Studio (ADR 0010)

## Armadilhas conhecidas

- **`smoke-all` usa PowerShell** (`.ps1`) — no Linux/CI, usar os scripts `.sh` diretamente
- **`community.general` não instalado por padrão** — rodar `ansible-galaxy collection install -r ansible/requirements.yml` antes do bootstrap (issue #17, arquivo ainda não existe)
- **`mcp-social` perde dados no k8s** — PVC ainda não declarado (issue #16)
- **`deploy-vps.yml` precisa do secret `VPS_KUBECONFIG`** — base64 do kubeconfig k3s do VPS; sem ele o workflow falha silenciosamente
- **SOPS precisa da chave age em `~/.age/personal-platform.txt`** — sem a chave, `just secrets-edit-*` não funciona

## Decisões arquiteturais

Todas as decisões estão em `docs/adr/`. As mais relevantes para entender o projeto:

- [ADR 0001](docs/adr/0001-sleep-pattern-replicas-zero.md) — Sleep pattern
- [ADR 0004](docs/adr/0004-sops-age-para-secrets.md) — SOPS + age
- [ADR 0005](docs/adr/0005-k3d-local-k3s-vps.md) — k3d local / k3s VPS
- [ADR 0007](docs/adr/0007-kustomize-em-vez-de-helm.md) — Kustomize vs Helm
- [ADR 0009](docs/adr/0009-cloudflare-como-camada-de-rede.md) — Cloudflare networking

## Backlog aberto (issues relevantes)

| # | Prioridade | Descrição |
|---|---|---|
| #16 | alta | `mcp-social` sem PVC no k8s (bug de dados) |
| #17 | alta | Ansible sem `requirements.yml` |
| #18 | média | CI validar `kustomize build` |
| #23 | alta | Auditar `.gitignore` |
| #26 | média | `deploy-vps.yml` verificar rollout |
| #27 | média | Completar Terraform Cloudflare |
| #28 | baixa | `just status` |
| #29 | baixa | Renovate para image tags |
