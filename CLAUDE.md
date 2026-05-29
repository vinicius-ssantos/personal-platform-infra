# CLAUDE.md â€” personal-platform-infra

Guia de contexto para AI assistants que trabalham neste repositÃ³rio.

## O que Ã© este repo

Infraestrutura centralizada para uma plataforma pessoal de MCP servers e BFFs.
Gerencia dois ambientes: **local** (Windows 11 + WSL2) e **VPS** (Ubuntu + k3s).
NÃ£o contÃ©m cÃ³digo de aplicaÃ§Ã£o nem Dockerfiles â€” apenas configuraÃ§Ã£o e automaÃ§Ã£o.

## Estrutura de diretÃ³rios

```
ansible/          Bootstrap de mÃ¡quinas (WSL2 e VPS)
  inventory/      local.ini e vps.ini
  playbooks/      bootstrap-wsl.yml, bootstrap-vps.yml, install-tools.yml

compose/          Docker Compose para desenvolvimento local
  docker-compose.yml

k8s/
  base/           Manifestos Kubernetes compartilhados entre ambientes
    apps/         Um diretÃ³rio por serviÃ§o (deployment.yaml + service.yaml + kustomization.yaml)
    namespaces.yaml
  overlays/
    local/        Patches para k3d local (replicas-local.yaml, k3d-config.yaml)
    vps/          Patches para VPS k3s (vazio por ora â€” workloads dormem em replicas=0)

terraform/
  cloudflare/     DNS records e Tunnel (provider declarado, recursos a completar â€” issue #27)

scripts/          Scripts operacionais e de smoke test
  smoke-k3d.sh        Smoke completo via Kubernetes local
  smoke-*.sh          Smokes individuais via Compose
  wake-github.sh      Acorda serviÃ§os GitHub no cluster
  wake-vos.sh         Acorda serviÃ§os VOS no cluster
  sleep-all.sh        Coloca todos os serviÃ§os para dormir

secrets/
  *.enc.yaml.example  Templates de secrets (commitados)
  *.enc.yaml          Arquivos reais encriptados com SOPS (NÃƒO commitados)

docs/
  adr/            Architecture Decision Records (ADR 0001â€“0013)
  local-setup.md  Setup do ambiente local
  vps-setup.md    Setup do VPS
  secrets.md      Guia SOPS + age
  runbook.md      OperaÃ§Ãµes do dia a dia

.github/workflows/
  ci.yml          ValidaÃ§Ã£o de YAML, Compose, Terraform, shell
  deploy-vps.yml  Aplica k8s/overlays/vps no merge para main
```

## ServiÃ§os gerenciados

| ServiÃ§o | Namespace k8s | Porta container | Health path | Status |
|---|---|---|---|---|
| `github-unified-mcp` | mcp | 8765 | `/healthz` | ready |
| `deploy-orchestrator-mcp` | mcp | 8000 | `/healthz` | ready |
| `mcp-social` | mcp | 8080 | `/health` | ready |
| `github-unified-mcp-bff` | bff | 8000 | `/healthz` | ready |
| `vos-studio-mcp` | vos | 8000 | `/health` | ready |
| `vos-studio-bff` | bff | 8000 | `/healthz` | ready |

**Portas Compose (host):** github-mcp=8765, deploy-mcp=8001, social=8080, github-bff=8010, vos-mcp=8020, vos-bff=8030

**Portas port-forward k3d (smoke):** github-mcp=19765, deploy-mcp=18000, social=18080, github-bff=18010, vos-mcp=18020, vos-bff=18030

## Comandos essenciais

```bash
# Desenvolvimento local â€” Compose
just compose-up          # sobe todos os serviÃ§os
just compose-down
just compose-logs
just smoke-all           # smoke em todos os serviÃ§os ready via Compose (PowerShell)

# Desenvolvimento local â€” Kubernetes
just k8s-local-up        # cria cluster k3d e aplica overlay local
just k8s-local-down      # destroi o cluster
just smoke-k3d           # smoke completo via k3d (bash)

# VPS
just wake-github         # escala github-mcp + bff para 1 rÃ©plica
just wake-vos            # escala vos-studio-mcp + bff para 1 rÃ©plica
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

### MudanÃ§a em manifestos k8s
1. Editar `k8s/base/apps/<serviÃ§o>/` ou os overlays
2. `just k8s-local-up` + `just smoke-k3d` para validar localmente
3. Abrir PR â†’ CI valida YAML e Terraform
4. Merge â†’ `deploy-vps.yml` aplica automaticamente no VPS

### MudanÃ§a em scripts ou Ansible
1. Editar o arquivo
2. `bash -n scripts/<arquivo>.sh` para checar sintaxe
3. Abrir PR â†’ CI valida automaticamente

### Adicionar um novo serviÃ§o
1. Criar `k8s/base/apps/<nome>/` com `deployment.yaml`, `service.yaml`, `kustomization.yaml`
2. Adicionar em `k8s/base/kustomization.yaml`
3. Adicionar serviÃ§o em `compose/docker-compose.yml` com profile
4. Adicionar variÃ¡veis em `.env.example`
5. Criar smoke script em `scripts/smoke-<nome>.sh`
6. Adicionar recipe em `Justfile`
7. Atualizar `docs/service-integration-matrix.md`

## ConvenÃ§Ãµes importantes

- **Todos os deployments nascem com `replicas: 0`** â€” sobem via overlay ou `kubectl scale` (ADR 0001)
- **Sem storage no cluster** â€” SQLite, PostgreSQL, Redis ficam fora (ADR 0002). ExceÃ§Ã£o: `mcp-social` vai receber PVC (issue #16)
- **Sem Dockerfiles aqui** â€” imagens vÃªm de repos upstream via GHCR
- **CI valida, nÃ£o deploya imagens** â€” o CI Ã© sÃ³ validaÃ§Ã£o de config (ADR 0006)
- **Kustomize, nÃ£o Helm** â€” base+overlays, sem template engine (ADR 0007)
- **`just`, nÃ£o `make`** â€” compatibilidade Windows/WSL2 (ADR 0008)
- **Namespaces:** `mcp` para MCP servers, `bff` para BFFs, `vos` para VOS Studio (ADR 0010)

## Armadilhas conhecidas

- **`smoke-all` usa PowerShell** (`.ps1`) â€” no Linux/CI, usar os scripts `.sh` diretamente
- **`community.general` nÃ£o instalado por padrÃ£o** â€” rodar `ansible-galaxy collection install -r ansible/requirements.yml` antes do bootstrap (issue #17, arquivo ainda nÃ£o existe)
- **`mcp-social` perde dados no k8s** â€” PVC ainda nÃ£o declarado (issue #16)
- **`deploy-vps.yml` precisa do secret `VPS_KUBECONFIG`** â€” base64 do kubeconfig k3s do VPS; sem ele o workflow falha silenciosamente
- **SOPS precisa da chave age em `~/.age/personal-platform.txt`** â€” sem a chave, `just secrets-edit-*` nÃ£o funciona

## DecisÃµes arquiteturais

Todas as decisÃµes estÃ£o em `docs/adr/`. As mais relevantes para entender o projeto:

- [ADR 0001](docs/adr/0001-sleep-pattern-replicas-zero.md) â€” Sleep pattern
- [ADR 0004](docs/adr/0004-sops-age-para-secrets.md) â€” SOPS + age
- [ADR 0005](docs/adr/0005-k3d-local-k3s-vps.md) â€” k3d local / k3s VPS
- [ADR 0007](docs/adr/0007-kustomize-em-vez-de-helm.md) â€” Kustomize vs Helm
- [ADR 0009](docs/adr/0009-cloudflare-como-camada-de-rede.md) â€” Cloudflare networking

## Backlog aberto (issues relevantes)

| # | Prioridade | DescriÃ§Ã£o |
|---|---|---|
| #16 | alta | `mcp-social` sem PVC no k8s (bug de dados) |
| #17 | alta | Ansible sem `requirements.yml` |
| #18 | mÃ©dia | CI validar `kustomize build` |
| #23 | alta | Auditar `.gitignore` |
| #26 | mÃ©dia | `deploy-vps.yml` verificar rollout |
| #27 | mÃ©dia | Completar Terraform Cloudflare |
| #28 | baixa | `just status` |
| #29 | baixa | Renovate para image tags |
