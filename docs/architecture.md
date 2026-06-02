# Architecture

## Visão geral

A plataforma é composta por duas camadas:

- **Aplicação**: MCPs e BFFs rodando como containers (imagens GHCR de repos upstream)
- **Infraestrutura**: este repositório — Compose, k3d/k3s, overlays, secrets, DNS, tunnels

Os ambientes local e VPS usam os mesmos manifestos base (`k8s/base`). Diferenças são expressas apenas em overlays (`k8s/overlays/local` e `k8s/overlays/vps`).

## Ambientes

### Local (desenvolvimento)

```
Windows 11
  └── WSL2 Ubuntu
        ├── Docker Compose (modo simples)
        │     └── Containers: MCPs + BFFs + central-mcp-gateway
        └── k3d (modo Kubernetes)
              └── Cluster k3s em containers Docker
                    ├── namespace: mcp  → github-unified-mcp, deploy-orchestrator-mcp, mcp-social
                    ├── namespace: bff  → github-unified-mcp-bff, vos-studio-bff
                    ├── namespace: vos  → vos-studio-mcp
                    └── namespace: monitoring → loki, alloy, grafana
```

Exposição externa (opcional, para testes com clientes reais):

```
Internet
  └── Cloudflare Quick Tunnel / Ngrok
        └── localhost (Compose ou k3d port-forward)
```

### VPS (produção)

```
Internet
  └── Cloudflare DNS (proxy ativado)
        └── VPS Ubuntu (Hetzner)
              └── k3s single-node
                    ├── Traefik (ingress controller padrão)
                    │     └── Roteia por hostname para cada serviço
                    ├── namespace: mcp  → github-unified-mcp, deploy-orchestrator-mcp, mcp-social, central-mcp-gateway
                    ├── namespace: bff  → github-unified-mcp-bff, vos-studio-bff
                    ├── namespace: vos  → vos-studio-mcp
                    └── namespace: monitoring → loki (PVC 5Gi), alloy, grafana
```

TLS é terminado pelo proxy Cloudflare. O Traefik recebe HTTP no port 80.

## Fluxo de uma requisição (VPS)

```
Cliente (browser / AI assistant)
  │
  ▼ HTTPS
Cloudflare DNS → proxy Cloudflare
  │  TLS termina aqui
  ▼ HTTP
VPS:80 → Traefik
  │  roteamento por hostname (ex: mcp-github.example.com)
  ▼
Service Kubernetes (ClusterIP)
  │
  ▼
Pod do serviço (ex: github-unified-mcp:8765)
  │  pode chamar outros serviços internamente
  ▼
Serviço upstream via FQDN interno
  ex: http://github-unified-mcp.mcp.svc.cluster.local:8765
```

### Com KEDA HTTP Add-on (piloto)

Para `github-unified-mcp` e `github-unified-mcp-bff`, o fluxo muda:

```
Traefik
  │  hostname aponta para interceptor KEDA, não para o serviço direto
  ▼
KEDA HTTP Interceptor (namespace: keda)
  │  se réplicas=0: acorda o deployment e aguarda
  │  se réplicas=1: encaminha imediatamente
  ▼
Serviço alvo
```

## Namespaces e responsabilidades

| Namespace | Serviços | Propósito |
|---|---|---|
| `mcp` | github-unified-mcp, deploy-orchestrator-mcp, mcp-social, central-mcp-gateway | MCP servers — interface para AI assistants |
| `bff` | github-unified-mcp-bff, vos-studio-bff | Backend-for-Frontend — interface para UIs |
| `vos` | vos-studio-mcp | VOS Studio — namespace isolado |
| `monitoring` | loki, alloy, grafana | Observabilidade — logs centralizados |
| `keda` | keda-operator, interceptor, scaler | Scale-to-zero (piloto) |

Comunicação entre namespaces usa FQDN completo:

```
http://<serviço>.<namespace>.svc.cluster.local:<porta>
```

## Camada de rede (Cloudflare)

Todo o DNS e exposição pública passa pelo Cloudflare:

| Necessidade | Solução |
|---|---|
| DNS | Cloudflare DNS gerenciado via Terraform |
| Exposição local | Cloudflare Tunnel (`cloudflared`) ou Quick Tunnel |
| TLS | Automático pelo proxy Cloudflare |
| Autorização | Cloudflare Access (opcional, via Terraform) |
| Frontends | Cloudflare Pages (fora do VPS) |

O Terraform neste repo gerencia: DNS records, Tunnel, Access applications e políticas.

## Serviços e contratos

| Serviço | Namespace | Porta | Health path | Auth |
|---|---|---|---|---|
| github-unified-mcp | mcp | 8765 | `/healthz` | Bearer token (`MCP_BEARER_TOKEN`) |
| deploy-orchestrator-mcp | mcp | 8000 | `/healthz` | API key (`MCP_SERVER_API_KEY`) |
| mcp-social | mcp | 8080 | `/health` | Access token (`SOCIAL_MCP_ACCESS_TOKEN`) |
| central-mcp-gateway | mcp | 8080 | `/healthz` + `/readyz` | Bearer token público |
| github-unified-mcp-bff | bff | 8000 | `/healthz` | Cookie de sessão |
| vos-studio-mcp | vos | 8000 | `/health` | — |
| vos-studio-bff | bff | 8000 | `/healthz` | Cookie de sessão |

## Secrets e configuração

A configuração é dividida em três camadas:

| Camada | Propósito | Exemplos |
|---|---|---|
| `k8s/base/` | Defaults neutros — iguais em todos os ambientes | Ports, labels, FQDN internos, referências a Secrets |
| `k8s/overlays/local/` | Overrides para dev local | `BFF_ENV: development`, `COOKIE_SECURE: false`, `FRONTEND_URL: localhost` |
| `k8s/overlays/vps/` | Overrides para VPS | `BFF_ENV: production`, `COOKIE_SECURE: true`, domínios reais |

Valores sensíveis (tokens, API keys) são injetados via Kubernetes `Secret` (`platform-secrets`) em cada namespace. O `k8s/base` nunca contém tokens reais.

Para local/k3d:

```bash
just k3d-secrets    # lê .env e cria platform-secrets em mcp, bff, vos
```

Para VPS, os secrets devem ser criados antes de acordar os workloads (ver `docs/secrets.md`).

## Observabilidade

Loki, Grafana Alloy e Grafana rodam no namespace `monitoring`:

- **Alloy**: coleta logs de todos os pods via Kubernetes API e envia para Loki
- **Loki**: armazena e indexa logs (efêmero localmente; PVC 5Gi no VPS)
- **Grafana**: UI de consulta — acesso via `just logs-ui` (port-forward para localhost:3000)

```bash
# Criar secret admin antes do primeiro acesso
GRAFANA_ADMIN_PASSWORD='senha-local' just grafana-secret

# Acessar UI
just logs-ui
```

## Sleep pattern (ADR 0001)

Todos os deployments de aplicação nascem com `replicas: 0`. No VPS, isso significa que nenhum serviço consome CPU/memória quando não está em uso.

Fluxo de vida típico no VPS:

```
deploy → replicas=0 (dormindo)
  │
  ▼ just wake-github
replicas=1 → rollout → healthcheck OK → pronto para uso
  │
  ▼ just sleep-all (ou inatividade + KEDA cooldown)
replicas=0 (dormindo)
```

Custo de cold start: ~5–15 segundos. Aceitável para uso pessoal.

## Storage

Nenhum banco de dados roda no cluster (ADR 0002). Exceção: `mcp-social` usa PVC SQLite.

| Dado | Destino |
|---|---|
| Dados de aplicação | Serviços externos (Supabase, Upstash, R2) |
| Logs de curto prazo | Loki no cluster (PVC 5Gi no VPS) |
| SQLite do mcp-social | PVC no namespace `mcp` |
| Secrets | SOPS + age em `secrets/*.enc.yaml` |

## Frontends

Nenhum frontend roda no cluster (ADR 0003). As UIs ficam em plataformas CDN externas. O BFF expõe a API que a UI consome; a origem é configurada via `FRONTEND_URL` e `ALLOWED_ORIGINS` nos overlays.

## Propriedade dos manifestos (ADR 0017)

Este repositório é a única fonte de verdade para os manifestos Kubernetes da plataforma. Repositórios de aplicação publicam imagens e documentam contratos de runtime; este repo é dono do Compose, k3d/k3s, overlays, secrets e roteamento.

Antes de mudar o wiring de Compose ou Kubernetes, verificar no repositório upstream:

- Nome e tag da imagem
- Porta do container
- Paths de health e readiness
- Variáveis de ambiente obrigatórias
- Headers de autenticação esperados

## Referências

- [ADR 0001](adr/0001-sleep-pattern-replicas-zero.md) — sleep pattern
- [ADR 0002](adr/0002-storage-fora-do-cluster.md) — storage fora do cluster
- [ADR 0005](adr/0005-k3d-local-k3s-vps.md) — k3d local / k3s VPS
- [ADR 0009](adr/0009-cloudflare-como-camada-de-rede.md) — Cloudflare networking
- [ADR 0010](adr/0010-namespaces-por-dominio-funcional.md) — namespaces
- [ADR 0015](adr/0015-logs-centralizados-com-loki-alloy.md) — observabilidade
- [ADR 0016](adr/0016-scale-to-zero-via-keda-http-add-on.md) — KEDA
- [ADR 0017](adr/0017-kubernetes-ownership-in-infra-repo.md) — ownership dos manifestos
