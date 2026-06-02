# Runtime contracts

Este documento operacionaliza o ADR 0017: define exatamente o que cada repositório de aplicação é responsável por publicar, e o que este repositório é responsável por configurar.

Use este documento antes de mudar qualquer wiring de Compose ou Kubernetes, e antes de mudar o runtime contract de um serviço no repositório upstream.

## Divisão de responsabilidades

### Repositório de aplicação (upstream) é dono de:

- Código-fonte da aplicação
- Testes unitários e de integração
- Dockerfile e `.dockerignore`
- Pipeline de publicação de imagem no GHCR
- Porta exposta pelo container
- Contrato de health/readiness endpoint
- Contrato de variáveis de ambiente
- Defaults de segurança no nível de aplicação (modo read-only, confirmações obrigatórias)

### Este repositório (`personal-platform-infra`) é dono de:

- Wiring Docker Compose
- Namespaces, service accounts, Deployments, Services e overlays Kubernetes
- Injeção de secrets compartilhados
- Seleção de imagem para ambientes local e VPS
- Orquestração k3d local
- Deploy k3s VPS
- Tunnels, roteamento público e infra DNS/TLS
- Smoke tests de plataforma e runbooks operacionais

## Contrato por serviço

### github-unified-mcp

| Atributo | Valor |
|---|---|
| Repositório | `vinicius-ssantos/github-unified-mcp` |
| Imagem | `ghcr.io/vinicius-ssantos/github-unified-mcp:main` |
| Porta | 8765 |
| Health path | `/healthz` |
| Readiness path | `/healthz` |
| Auth | Bearer token via header `Authorization: Bearer <token>` |
| Variáveis obrigatórias | `MCP_BEARER_TOKEN`, `GITHUB_TOKEN`, `GITHUB_ALLOWED_REPOS` |
| Modo seguro | `GITHUB_READ_ONLY=true`, `GITHUB_REQUIRE_ALLOWED_REPOS=true` |
| Namespace k8s | `mcp` |

### deploy-orchestrator-mcp

| Atributo | Valor |
|---|---|
| Repositório | `vinicius-ssantos/deploy-orchestrator-mcp` |
| Imagem | `ghcr.io/vinicius-ssantos/deploy-orchestrator-mcp:main` |
| Porta | 8000 |
| Health path | `/healthz` |
| Readiness path | `/healthz` |
| Auth | API key via variável de ambiente |
| Variáveis obrigatórias | `MCP_SERVER_API_KEY`, `PORT` |
| Modo seguro | `MCP_READ_ONLY=true`, `MCP_REQUIRE_CONFIRMATION=true` |
| Namespace k8s | `mcp` |

### mcp-social

| Atributo | Valor |
|---|---|
| Repositório | `vinicius-ssantos/mcp-social` |
| Imagem | `ghcr.io/vinicius-ssantos/mcp-social:main` |
| Porta | 8080 |
| Health path | `/health` |
| Readiness path | `/health` |
| Auth | Access token via variável de ambiente |
| Variáveis obrigatórias | `SOCIAL_MCP_ACCESS_TOKEN`, `SOCIAL_DB_URL` |
| Storage | SQLite via PVC em `/data` (k8s) ou volume Compose |
| Namespace k8s | `mcp` |

### central-mcp-gateway

| Atributo | Valor |
|---|---|
| Repositório | `vinicius-ssantos/central-mcp-gateway` |
| Imagem | `ghcr.io/vinicius-ssantos/central-mcp-gateway:main` |
| Porta | 8080 |
| Health path | `/healthz` |
| Readiness path | `/readyz` |
| Auth | Bearer token via `Authorization: Bearer <token>` |
| Variáveis obrigatórias | `GATEWAY_PUBLIC_BEARER_TOKEN`, `GATEWAY_OAUTH_CLIENT_SECRET`, `GATEWAY_SESSION_SECRET`, `GATEWAY_PUBLIC_BASE_URL`, `GATEWAY_OAUTH_ISSUER` |
| Upstreams | github-unified-mcp, deploy-orchestrator-mcp, mcp-social, vos-studio-mcp |
| Namespace k8s | `mcp` |

### github-unified-mcp-bff

| Atributo | Valor |
|---|---|
| Repositório | `vinicius-ssantos/-github-unified-mcp-bff` |
| Imagem | `ghcr.io/vinicius-ssantos/github-unified-mcp-bff:main` |
| Porta | 8000 |
| Health path | `/healthz` |
| Readiness path | `/healthz` |
| Auth | Cookie de sessão (lado do cliente) |
| Variáveis obrigatórias | `MCP_URL`, `MCP_TOKEN`, `BFF_ENV`, `FRONTEND_URL`, `COOKIE_SECURE` |
| Upstream | github-unified-mcp via `MCP_URL` |
| Namespace k8s | `bff` |

### vos-studio-mcp

| Atributo | Valor |
|---|---|
| Repositório | `vinicius-ssantos/vos-studio-mcp` |
| Imagem | `ghcr.io/vinicius-ssantos/vos-studio-mcp:main` |
| Porta | 8000 |
| Health path | `/health` |
| Readiness path | `/health` |
| Auth | — (sem auth no nível MCP atualmente) |
| Variáveis obrigatórias | `MCP_SERVER_HOST`, `MCP_SERVER_PORT`, `PORT`, `APP_ENV` |
| Nota | Healthcheck lento — `/health` faz verificações de dependência. Timeout configurado em 10s no Compose e k8s |
| Namespace k8s | `vos` |

### vos-studio-bff

| Atributo | Valor |
|---|---|
| Repositório | `vinicius-ssantos/vos-studio-bff` |
| Imagem | `ghcr.io/vinicius-ssantos/vos-studio-bff:main` |
| Porta | 8000 |
| Health path | `/healthz` |
| Readiness path | `/healthz` |
| Auth | Cookie de sessão (lado do cliente) |
| Variáveis obrigatórias | `MCP_URL`, `BFF_ENV`, `FRONTEND_URL`, `ALLOWED_ORIGINS`, `COOKIE_SECURE`, `PORT` |
| Upstream | vos-studio-mcp via `MCP_URL` |
| Namespace k8s | `bff` |

## Regra operacional

### Antes de mudar wiring neste repositório

Verifique no repositório upstream:

1. O nome e tag da imagem ainda são válidos?
2. A porta do container mudou?
3. Novos paths de health/readiness foram adicionados?
4. Novas variáveis de ambiente obrigatórias foram introduzidas?
5. O modo de autenticação mudou?
6. O modo de segurança (read-only, confirmações) mudou?

### Antes de mudar o contrato de runtime no repositório upstream

Atualize este repositório no mesmo ciclo de entrega:

1. `compose/docker-compose.yml` — environment, ports, healthcheck
2. `k8s/base/apps/<serviço>/configmap.yaml` — variáveis não-sensíveis
3. `k8s/base/apps/<serviço>/deployment.yaml` — porta, probes, envFrom/env
4. `k8s/overlays/*/` — overrides de ambiente
5. `docs/runtime-contracts.md` — esta tabela
6. `docs/service-integration-matrix.md` — status atualizado
7. `scripts/smoke-<serviço>.sh` — path de health atualizado

## Mudanças de breaking contract

Se um serviço upstream muda porta, auth ou health path de forma incompatível:

1. Abrir issue neste repo documentando a mudança necessária
2. Atualizar Compose e k8s/base em um único PR para manter consistência
3. Atualizar smoke tests
4. Validar com `just smoke-k3d` antes do merge
5. Atualizar esta tabela

## Versões de imagem

Em desenvolvimento local e k3d, use `:main` (mutable tag).

No VPS, prefira tags imutáveis (digest ou commit SHA). Veja `docs/image-pinning.md` para a política completa e como configurar via `k8s/overlays/vps/kustomization.yaml`.
