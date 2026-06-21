# personal-platform-infra

[![CI](https://github.com/vinicius-ssantos/personal-platform-infra/actions/workflows/ci.yml/badge.svg)](https://github.com/vinicius-ssantos/personal-platform-infra/actions/workflows/ci.yml)
[![Deploy VPS](https://github.com/vinicius-ssantos/personal-platform-infra/actions/workflows/deploy-vps.yml/badge.svg)](https://github.com/vinicius-ssantos/personal-platform-infra/actions/workflows/deploy-vps.yml)
![Terraform](https://img.shields.io/badge/terraform-%235835CC.svg?logo=terraform&logoColor=white)
![Kubernetes](https://img.shields.io/badge/kubernetes-%23326ce5.svg?logo=kubernetes&logoColor=white)
![Cloudflare](https://img.shields.io/badge/cloudflare-F38020?logo=cloudflare&logoColor=white)

Infraestrutura centralizada para uma plataforma pessoal de MCP servers e BFFs. Gerencia dois ambientes — **local** (Windows 11 + WSL2) e **VPS** (Ubuntu + k3s) — a partir de um único repositório de configuração.

Não contém código de aplicação nem Dockerfiles. As imagens dos serviços são publicadas pelos repositórios upstream e consumidas aqui via GHCR.

---

## Arquitetura

```
Local                                    VPS
─────────────────────────────────        ─────────────────────────────────
Windows 11 + WSL2                        Ubuntu + k3s (single-node)
  ├── Docker Compose (iteração rápida)     ├── Traefik (ingress)
  └── k3d (validação k8s)                 ├── namespace: mcp
        ├── namespace: mcp                │     MCPs + central-mcp-gateway
        ├── namespace: bff                ├── namespace: bff
        ├── namespace: vos                │     BFFs
        └── namespace: monitoring         ├── namespace: vos
                                          └── namespace: monitoring
                Internet
                   │
          Cloudflare DNS + Proxy
          (TLS, Access, Tunnel)
                   │
              VPS :80 → Traefik
```

---

## Serviços gerenciados

| Serviço | Repositório | Role | Porta | Health |
|---|---|---|---|---|
| `github-unified-mcp` | [↗](https://github.com/vinicius-ssantos/github-unified-mcp) | MCP server GitHub | 8765 | `/healthz` |
| `deploy-orchestrator-mcp` | [↗](https://github.com/vinicius-ssantos/deploy-orchestrator-mcp) | MCP server de deploy | 8000 | `/healthz` |
| `mcp-social` | [↗](https://github.com/vinicius-ssantos/mcp-social) | MCP server social | 8080 | `/health` |
| `mcp-code-sandbox` | [↗](https://github.com/vinicius-ssantos/mcp-code-sandbox) | MCP server de execução isolada de código | 8766 | MCP `/mcp` |
| `central-mcp-gateway` | [↗](https://github.com/vinicius-ssantos/central-mcp-gateway) | Gateway agregador | 8080 | `/healthz` |
| `github-unified-mcp-bff` | [↗](https://github.com/vinicius-ssantos/-github-unified-mcp-bff) | BFF para GitHub flows | 8000 | `/healthz` |
| `vos-studio-mcp` | [↗](https://github.com/vinicius-ssantos/vos-studio-mcp) | MCP server VOS Studio | 8000 | `/health` |
| `vos-studio-bff` | [↗](https://github.com/vinicius-ssantos/vos-studio-bff) | BFF para VOS Studio | 8000 | `/healthz` |

Todos os deployments nascem com `replicas: 0` no VPS e sobem sob demanda via `just wake-*`.

`mcp-code-sandbox` roda como processo host-local, fora do Compose/k8s, para acessar o Docker daemon diretamente sem montar o socket Docker em um contêiner. O gateway o consome como upstream privado em `http://host.docker.internal:8766/mcp` no Compose local.

---

## Quick start

### Pré-requisitos

- Windows 11 + WSL2 + Docker Desktop com integração WSL2
- GitHub PAT com escopos `repo` e `read:packages`

```bash
# 1. Instalar ferramentas no WSL2
ansible-galaxy collection install -r ansible/requirements.yml
just bootstrap-local
```

### Modo Compose (mais rápido)

```bash
just env-init        # cria .env a partir do .env.example
# edite .env com seus tokens reais
just check-env       # valida variáveis obrigatórias
just compose-up      # sobe todos os serviços
just smoke-all-sh    # valida health de cada serviço
just compose-down
```

### Modo Kubernetes (k3d)

```bash
just k8s-local-up                                          # cria cluster + aplica overlay local
GHCR_USERNAME="user" GHCR_TOKEN="token" just create-ghcr-secret
just k3d-secrets                                           # injeta tokens reais do .env
just smoke-k3d                                             # smoke completo via port-forward
just k8s-local-down
```

### Expor localmente

```bash
just quick-tunnel-up   # Cloudflare Quick Tunnel (sem conta, URLs temporárias)
just ngrok-up          # Ngrok (requer authtoken configurado)
```

---

## Documentação

| Doc | Conteúdo |
|---|---|
| [onboarding.md](docs/onboarding.md) | Do zero ao smoke test — passo a passo completo |
| [architecture.md](docs/architecture.md) | Fluxo de requisição, namespaces, camadas de config |
| [contributing.md](docs/contributing.md) | Convenções, checklist para novo serviço, ADRs |
| [runtime-contracts.md](docs/runtime-contracts.md) | Contrato de cada serviço — porta, health, auth, vars |
| [lifecycle.md](docs/lifecycle.md) | Manual vs overlay vs KEDA — diagnóstico e break-glass |
| [runbook.md](docs/runbook.md) | Operações do dia a dia |
| [secrets.md](docs/secrets.md) | SOPS + age — setup e rotação |
| [disaster-recovery.md](docs/disaster-recovery.md) | Rebuild de workstation ou VPS do zero |
| [mcp-social-storage.md](docs/mcp-social-storage.md) | PVC SQLite do `mcp-social` — retenção, backup e restore |
| [loki-storage.md](docs/loki-storage.md) | PVC de logs do Loki — retenção e trade-offs |
| [image-pinning.md](docs/image-pinning.md) | Política de tags mutáveis vs imutáveis |
| [vps-setup.md](docs/vps-setup.md) | Provisionamento e bootstrap do VPS |
| [vps-deploy-checklist.md](docs/vps-deploy-checklist.md) | Checklist go/no-go do deploy real no VPS |
| [adr/](docs/adr/README.md) | 20 Architecture Decision Records |

---

## Stack

| Camada | Ferramenta |
|---|---|
| Runtime local | Docker Compose + k3d |
| Runtime VPS | k3s + Traefik |
| Manifests | Kustomize (base + overlays) |
| Rede / TLS | Cloudflare DNS, Tunnel, Access |
| DNS + VPS | Terraform (Cloudflare + Hetzner) |
| Bootstrap | Ansible |
| Task runner | just |
| Secrets | SOPS + age |
| Observabilidade | Loki + Alloy + Grafana |
| Scale-to-zero | KEDA HTTP Add-on (piloto) |
| Renovate | Atualização automática de imagens |
