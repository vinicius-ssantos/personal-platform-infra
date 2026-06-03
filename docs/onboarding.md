# Onboarding — personal-platform-infra

Este guia cobre tudo que você precisa para ir do zero até rodar e validar a plataforma localmente. Leia na ordem — cada seção depende da anterior.

## O que é este repositório

Este repo não contém código de aplicação. Ele é a camada de infraestrutura que conecta os serviços em dois ambientes:

- **Local**: Windows 11 + WSL2 + Docker Compose ou k3d
- **VPS**: Ubuntu + k3s (single-node)

Os serviços gerenciados (MCPs, BFFs) vivem em repositórios upstream separados e são consumidos aqui como imagens GHCR.

## Pré-requisitos

### Windows / WSL2

Você precisa de:

- Windows 11 com WSL2 ativo
- Docker Desktop com integração WSL2 habilitada
- WSL2 Ubuntu como distribuição padrão

Dentro do WSL2, o bootstrap instala tudo mais:

```bash
# Instalar Ansible collections antes de qualquer coisa
ansible-galaxy collection install -r ansible/requirements.yml

# Bootstrap completo do ambiente WSL2
just bootstrap-local
```

Isso instala: Terraform, kubectl, k3d, Helm, cloudflared, just, sops, age.

### Conta GitHub

Você precisa de um GitHub PAT com escopos `repo` e `read:packages` para:

- Autenticar nas imagens GHCR privadas
- Usar o `github-unified-mcp` com um token real

## Primeiro uso: modo Compose

O modo Compose é o caminho mais rápido para validar que tudo funciona.

### 1. Criar o .env

```bash
just env-init
```

Isso copia `.env.example` para `.env`. Edite os valores marcados como `change-me`:

| Variável | Como obter |
|---|---|
| `GITHUB_TOKEN` | github.com/settings/tokens — escopos: `repo`, `read:packages` |
| `MCP_BEARER_TOKEN` | `openssl rand -hex 32` |
| `MCP_SERVER_API_KEY` | `openssl rand -hex 32` |
| `SOCIAL_MCP_ACCESS_TOKEN` | token da integração social |
| `PUBLIC_EDGE_TOKEN` | `openssl rand -hex 32` |
| `CENTRAL_MCP_GATEWAY_*` | cada um com `openssl rand -hex 32` |

### 2. Validar o .env

```bash
just check-env
```

Falha se alguma variável obrigatória estiver ausente ou com valor `change-me`.

### 3. Subir os serviços

```bash
just compose-up
```

Sobe todos os serviços definidos no perfil `all`. Aguarda o healthcheck de cada container antes de retornar.

### 4. Validar

```bash
just smoke-all
```

Executa smoke tests individuais para cada serviço via PowerShell (Windows). No Linux/CI, use:

```bash
just smoke-all-sh
```

### 5. Parar

```bash
just compose-down
```

## Segundo uso: modo Kubernetes (k3d)

Use k3d quando quiser validar manifestos Kubernetes antes de aplicar no VPS.

### 1. Criar o cluster e aplicar overlay

```bash
just k8s-local-up
```

Cria (ou reutiliza) o cluster `personal-platform` com k3d e aplica `k8s/overlays/local`, que inclui replicas=1 para todos os serviços prontos.

### 2. Criar o pull secret GHCR

```bash
GHCR_USERNAME="seu-usuario" GHCR_TOKEN="seu-token" just create-ghcr-secret
```

Necessário para que os pods consigam baixar imagens privadas do GHCR.

### 3. Injetar secrets reais

```bash
just k3d-secrets
```

Lê o `.env` e cria os Kubernetes Secrets `platform-secrets` em cada namespace. Sem isso, os serviços sobem com tokens placeholder e chamadas de API vão falhar.

### 4. Validar

```bash
just smoke-k3d
```

Smoke completo: cria ou reutiliza cluster → aplica overlay → aguarda rollouts → health check via port-forward em cada serviço.

### 5. Derrubar

```bash
just k8s-local-down
```

## Estrutura de portas

### Compose (host)

| Serviço | Porta host |
|---|---|
| github-unified-mcp | 8765 |
| deploy-orchestrator-mcp | 8001 |
| mcp-social | 8080 |
| github-unified-mcp-bff | 8010 |
| vos-studio-mcp | 8020 |
| vos-studio-bff | 8030 |
| central-mcp-gateway | 8040 |

### k3d (port-forward)

| Serviço | Porta local |
|---|---|
| github-unified-mcp | 19765 |
| deploy-orchestrator-mcp | 18000 |
| mcp-social | 18080 |
| github-unified-mcp-bff | 18010 |
| vos-studio-mcp | 18020 |
| vos-studio-bff | 18030 |
| central-mcp-gateway | 18040 |

As portas k3d são propositalmente altas para não conflitar com Compose quando ambos rodam simultaneamente.

## Exposição pública local

Para expor serviços locais com URL pública temporária:

```bash
# Cloudflare Quick Tunnel (sem conta)
just quick-tunnel-up

# Ngrok (requer conta e authtoken configurado)
just ngrok-up

# Tailscale Funnel (requer Tailscale logado e Funnel habilitado)
just tailscale-funnel-up
```

`quick-tunnel-up` gera URLs `trycloudflare.com` e as escreve no `.env` automaticamente. Use `quick-tunnel-refresh` para forçar novas URLs (sujeito a rate limit do Cloudflare).

`tailscale-funnel-up` exposes only `central-mcp-gateway` on `localhost:8040`
through a public `*.ts.net` URL. Use the printed URL in ChatGPT:

```text
https://<device>.<tailnet>.ts.net/mcp
```

Configure the ChatGPT connector as OAuth with client ID `chatgpt`, an empty
client secret, token endpoint auth method `none`, and OIDC disabled. If the
OAuth browser redirect times out on Windows, run:

```powershell
& "C:\Program Files\Tailscale\tailscale.exe" up --accept-dns=false
just tailscale-funnel-up
```

## Secrets

O repositório usa duas camadas de secrets:

- **`.env`**: para Compose e uso local. Nunca commitado.
- **`secrets/*.enc.yaml`**: YAML encriptado com SOPS + age para uso estruturado e k8s.

Para configurar SOPS pela primeira vez:

```bash
age-keygen -o ~/.age/personal-platform.txt
# Copie a public key para .sops.yaml (substitua os placeholders)
just secrets-check
```

Veja `docs/secrets.md` para o fluxo completo.

## O que fazer quando algo não funciona

| Sintoma | Comando |
|---|---|
| Container não sobe | `just compose-logs` |
| Pod em CrashLoopBackOff | `kubectl logs -n <ns> deploy/<nome>` |
| Imagem não baixa | Verificar `GHCR_TOKEN` e `just create-ghcr-secret` |
| Health check falha | Verificar se o serviço upstream está saudável primeiro |
| `.env` com valores errados | `just check-env` para diagnóstico |
| Quero resetar tudo | `just clean` |

## Próximos passos

Após validar o ambiente local:

- Leia `docs/architecture.md` para entender o fluxo de rede completo
- Leia `docs/secrets.md` antes de configurar o VPS
- Leia `docs/vps-setup.md` para o deploy no cluster real
- Leia `docs/runbook.md` para operações do dia a dia
