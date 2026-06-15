# CLAUDE.md — personal-platform-infra

Guia de contexto para AI assistants que trabalham neste repositório.

## Workflow de commits

**NUNCA commitar direto na `main`.** Sempre:
1. Criar branch: `git checkout -b feat/<descricao>`
2. Commitar
3. Push: `git push origin feat/<descricao>`
4. Abrir PR via `gh pr create` com descrição clara
5. Só mergear após aprovação do usuário, a menos que ele peça explicitamente para pular o PR

## Uso dos agents (.opencode/agent/)

**Antes de qualquer ação especializada, leia o agent correspondente:**

| Se for fazer... | Leia antes |
|---|---|
| Editar k8s, terraform, ansible, kustomize | `.opencode/agent/infra-engineer.md` |
| Revisar código, PR, segurança | `.opencode/agent/reviewer.md` |
| Criar/manter scripts, Justfile, automação | `.opencode/agent/scripter.md` |
| Smoke test, logs, status, wake/sleep | `.opencode/agent/operations.md` |
| Investigar algo antes de agir | `.opencode/agent/explorer.md` |

**Modelos:** o `task` tool só spawna `general`/`explore` com o mesmo modelo da sessão. Os agents `.md` são contexto especializado que você DEVE ler antes de executar — não agents autônomos.

## O que é este repo

Infraestrutura centralizada para uma plataforma pessoal de MCP servers e BFFs.
Gerencia dois ambientes: **local** (Windows 11 + WSL2) e **VPS** (Ubuntu + k3s).
Não contém código de aplicação nem Dockerfiles — apenas configuração e automação.

## Estrutura de diretórios

```text
ansible/          Bootstrap de máquinas (WSL2 e VPS)
  inventory/      local.ini e vps.ini
  playbooks/      bootstrap-wsl.yml, bootstrap-vps.yml, install-tools.yml
  requirements.yml Ansible collection requirements

compose/          Docker Compose para desenvolvimento local
  docker-compose.yml

k8s/
  base/           Manifestos Kubernetes compartilhados entre ambientes
    apps/         Um diretório por serviço (deployment.yaml + service.yaml + kustomization.yaml)
    monitoring/   Loki, Alloy e Grafana
    namespaces.yaml
    serviceaccounts.yaml
  overlays/
    local/        Patches para k3d local (replicas-local.yaml, env local, monitoring local)
    vps/          Patches para VPS k3s (workloads dormem em replicas=0)
  addons/         Add-ons opcionais, como KEDA HTTP Add-on pilot

terraform/
  cloudflare/     DNS records e Tunnel Cloudflare
  vps/            Provisionamento da VPS e firewall

scripts/          Scripts operacionais e de smoke test
  smoke-k3d.sh        Smoke completo via Kubernetes local
  smoke-*.sh          Smokes individuais via Compose
  wake-github.sh      Acorda serviços GitHub no cluster
  wake-vos.sh         Acorda serviços VOS no cluster
  sleep-all.sh        Coloca todos os serviços para dormir
  k3d-secrets.sh      Injeta secrets locais do .env no cluster k3d

secrets/
  *.enc.yaml.example  Templates de secrets (commitados)
  *.enc.yaml          Arquivos reais encriptados com SOPS (NÃO commitados)

docs/
  adr/            Architecture Decision Records (ADR 0001–0016)
  local-setup.md  Setup do ambiente local
  vps-setup.md    Setup do VPS
  secrets.md      Guia SOPS + age
  runbook.md      Operações do dia a dia

.github/workflows/
  ci.yml          Validação de YAML, Compose, Terraform, shell e Kustomize
  deploy-vps.yml  Aplica k8s/overlays/vps no merge para main quando k8s/** muda
```

## Serviços gerenciados

| Serviço | Namespace k8s | Porta container | Health path | Status |
|---|---|---:|---|---|
| `github-unified-mcp` | mcp | 8765 | `/healthz` | ready |
| `deploy-orchestrator-mcp` | mcp | 8000 | `/healthz` | ready |
| `mcp-social` | mcp | 8080 | `/health` ¹ | ready |
| `central-mcp-gateway` | mcp | 8080 | `/healthz` + `/readyz` | ready |
| `github-unified-mcp-bff` | bff | 8000 | `/healthz` | ready |
| `vos-studio-mcp` | vos | 8000 | `/health` ¹ | ready |
| `vos-studio-bff` | bff | 8000 | `/healthz` | ready |
| `mcp-code-sandbox` | host-local external | 8766 | MCP `/mcp` | ready |

¹ `/health` (sem `z`) — path upstream diferente dos demais. Padronizar para `/healthz` é uma melhoria pendente nos repos de aplicação.

**Portas Compose (host):** github-mcp=8765, deploy-mcp=8001, social=8080, gateway=8040, github-bff=8010, vos-mcp=8020, vos-bff=8030, sandbox-host=8766.

**Portas port-forward k3d (smoke):** github-mcp=19765, deploy-mcp=18000, social=18080, gateway=18040, github-bff=18010, vos-mcp=18020, vos-bff=18030.

## Comandos essenciais

```bash
# Desenvolvimento local — Compose
just doctor
just env-init
just check-env
just compose-up
just compose-down
just compose-logs
just smoke-all

# Desenvolvimento local — Kubernetes
just k8s-local-up
just k3d-secrets
just smoke-k3d
just k8s-local-down

# VPS
just wake-github
just wake-vos
just sleep-all
just logs
just status

# Secrets (SOPS + age)
just secrets-edit-local
just secrets-edit-vps

# Infra
just bootstrap-local
just bootstrap-vps
just terraform-plan
just terraform-vps-plan
just tunnel
```

## Fluxo de desenvolvimento

### Mudança em manifestos k8s

1. Editar `k8s/base/apps/<serviço>/` ou os overlays.
2. Rodar `just k8s-local-up` e `just smoke-k3d` para validar localmente.
3. Abrir PR; CI valida YAML, Compose, Terraform, shell e Kustomize.
4. Merge em `main`; `deploy-vps.yml` aplica `k8s/overlays/vps` somente quando `k8s/**` muda e `VPS_KUBECONFIG` está configurado.

### Mudança em scripts ou Ansible

1. Editar o arquivo.
2. Rodar `bash -n scripts/<arquivo>.sh` quando aplicável.
3. Abrir PR; CI valida sintaxe de scripts automaticamente.

### Adicionar um novo serviço

1. Criar `k8s/base/apps/<nome>/` com `deployment.yaml`, `service.yaml`, `configmap.yaml` se necessário e `kustomization.yaml`.
2. Adicionar em `k8s/base/kustomization.yaml`.
3. Adicionar serviço em `compose/docker-compose.yml` com profile/ports/healthcheck.
4. Adicionar variáveis em `.env.example`.
5. Criar smoke script em `scripts/smoke-<nome>.sh`.
6. Adicionar recipe em `Justfile`.
7. Atualizar `docs/service-integration-matrix.md` e docs de setup/runbook.

## Convenções importantes

- **Todos os deployments de app nascem com `replicas: 0`** — sobem via overlay local ou `kubectl scale`/wake scripts (ADR 0001).
- **Storage persistente é exceção** — bancos/cache devem ficar fora do cluster (ADR 0002); `mcp-social` possui PVC próprio para dados SQLite.
- **Sem Dockerfiles aqui** — imagens vêm de repos upstream via GHCR.
- **CI valida, não builda imagens** — o CI é só validação de config (ADR 0006).
- **Kustomize, não Helm** — base+overlays, sem template engine (ADR 0007).
- **`just`, não `make`** — compatibilidade Windows/WSL2 (ADR 0008).
- **Namespaces:** `mcp` para MCP servers, `bff` para BFFs, `vos` para VOS Studio e `monitoring` para observabilidade (ADR 0010/0015).
- **Cloudflare é a camada de rede** — DNS, Tunnel, TLS e Pages ficam centralizados no Cloudflare (ADR 0009).
- **Observabilidade leve:** Loki, Alloy, Prometheus e Grafana rodam no namespace `monitoring` com storage inicialmente efêmero (ADR 0015). Alloy coleta logs, eventos Kubernetes e métricas de pods anotados com `prometheus.io/scrape: "true"`.
- **Scale-to-zero automático é piloto:** KEDA HTTP Add-on cobre inicialmente `github-unified-mcp` e `github-unified-mcp-bff` (ADR 0016).

## Armadilhas conhecidas

- **`smoke-all` usa PowerShell** (`.ps1`) — no Linux/CI, usar os scripts `.sh` diretamente.
- **`community.general` precisa ser instalado antes do bootstrap** — rodar `ansible-galaxy collection install -r ansible/requirements.yml`.
- **`mcp-social` tem PVC no k8s** — único dado de record no cluster (SQLite em `/data/social.db`). Storage é `local-path` node-local, sem backup automático; ver `docs/mcp-social-storage.md` para retenção, backup e restore.
- **`deploy-vps.yml` precisa do secret `VPS_KUBECONFIG`** — base64 do kubeconfig k3s do VPS; sem ele o workflow registra notice e pula o deploy real.
- **SOPS precisa da chave age em `~/.age/personal-platform.txt`** — sem a chave, `just secrets-edit-*` não funciona.
- **Grafana usa o Secret `grafana-admin`** (namespace `monitoring`, via `secretKeyRef`) — crie-o antes de subir o monitoring: local com `just grafana-secret`, VPS pelo fluxo SOPS (`secrets/platform-secrets-vps.enc.yaml`). Sem o Secret o pod entra em crashloop.
- **Alguns ConfigMaps ainda têm placeholders** — valores como `REPLACE_WITH_FRONTEND_URL` devem ser substituídos em overlay/secret de VPS antes de produção.
- **`vos-studio-mcp` ainda usa `/health` como liveness/readiness** — idealmente o app upstream deve expor `/live` separado de checks pesados de dependência.

## Decisões arquiteturais relevantes

Todas as decisões estão em `docs/adr/`.

- [ADR 0001](docs/adr/0001-sleep-pattern-replicas-zero.md) — Sleep pattern
- [ADR 0002](docs/adr/0002-storage-fora-do-cluster.md) — Storage fora do cluster
- [ADR 0004](docs/adr/0004-sops-age-para-secrets.md) — SOPS + age
- [ADR 0005](docs/adr/0005-k3d-local-k3s-vps.md) — k3d local / k3s VPS
- [ADR 0007](docs/adr/0007-kustomize-em-vez-de-helm.md) — Kustomize vs Helm
- [ADR 0009](docs/adr/0009-cloudflare-como-camada-de-rede.md) — Cloudflare networking
- [ADR 0012](docs/adr/0012-deploy-vps-via-github-actions.md) — Deploy VPS via GitHub Actions
- [ADR 0014](docs/adr/0014-status-page-via-cloudflare-worker.md) — Status page via Cloudflare Worker
- [ADR 0015](docs/adr/0015-logs-centralizados-com-loki-alloy.md) — Logs centralizados com Loki e Alloy
- [ADR 0016](docs/adr/0016-scale-to-zero-via-keda-http-add-on.md) — Scale-to-zero via KEDA HTTP Add-on

## Backlog atual sugerido

| Prioridade | Descrição |
|---|---|
| alta | Configurar `VPS_KUBECONFIG` e validar deploy real no cluster VPS |
| alta | Padronizar base/overlays para separar config local e config VPS |
| alta | Declarar secrets de runtime via Kubernetes Secrets/SOPS em vez de placeholders nos manifests base |
| média | Adicionar ingress/rotas VPS e alinhar com Cloudflare DNS |
| baixa | Adotar Renovate ou rotina equivalente para image tags |
