# Local setup

Expected local stack:

- Windows 11
- WSL2 Ubuntu
- Docker Desktop with WSL integration
- Ansible
- Terraform
- k3d
- kubectl
- helm
- cloudflared
- just

## Bootstrap

```bash
# Instalar Ansible collections necessárias primeiro
ansible-galaxy collection install -r ansible/requirements.yml

# Executar bootstrap completo
just bootstrap-local
```

## Compose mode

```bash
just env-init
just check-env
just compose-up
just compose-logs
just compose-down
```

`compose-up`, `compose-logs`, and `compose-down` are stable aliases for the full
`all` profile. For incremental work, use the profile-specific targets:

```bash
just compose-up-profile github
just compose-logs-profile github
just compose-down-profile github

just compose-up-profile vos
just compose-up-profile all
```

This is useful when validating one service family without starting the complete
local platform. Full-stack smoke validation should still use `just compose-up`
and `just smoke-all`.

The managed services consume images published by their upstream
repositories:

- `ghcr.io/vinicius-ssantos/github-unified-mcp:main`
- `ghcr.io/vinicius-ssantos/deploy-orchestrator-mcp:main`
- `ghcr.io/vinicius-ssantos/mcp-social:main`
- `ghcr.io/vinicius-ssantos/github-unified-mcp-bff:main`
- `ghcr.io/vinicius-ssantos/vos-studio-mcp:main`
- `ghcr.io/vinicius-ssantos/vos-studio-bff:main`

To test a different image locally, edit only your uncommitted `.env` file and
override the matching `*_IMAGE` variable.

If GHCR returns `denied` for an image, confirm that the package exists, the tag
is published, and Docker is logged in with access to the package.

To smoke-test only the GitHub MCP service:

```bash
just smoke-github
```

### Central MCP Gateway Admin UI

The local Compose runtime enables the gateway Admin UI. Access it through the
local port, not through a public tunnel:

```text
http://localhost:8040/admin/ui/login
```

Login with the value of `CENTRAL_MCP_GATEWAY_ADMIN_TOKEN` from your uncommitted
`.env` file. `just tailscale-funnel-up`, `just quick-tunnel-up`, and
`just k3d-ngrok-up` generate this token when it is missing or still set to
`change-me`.

## Kubernetes mode

`just k8s-local-up` creates (or reuses) the `personal-platform` k3d cluster and
applies the local Kustomize overlay. The overlay includes a replica patch that
starts the six ready services automatically.

```bash
just k8s-local-up
GHCR_USERNAME="<github-username>" GHCR_TOKEN="<token-with-read-packages>" just create-ghcr-secret
kubectl get pods -A
just k8s-local-down
```

### k3d smoke test

`just smoke-k3d` is the single-command validation for the Kubernetes local path.
It covers the full cycle: prerequisite check â†’ cluster create-or-reuse â†’ overlay
apply â†’ rollout wait â†’ per-service health check via `kubectl port-forward`.

```bash
just smoke-k3d
```

Services validated and their local port-forward addresses:

| Service | k8s namespace | local port | health path |
|---|---|---|---|
| `github-unified-mcp` | mcp | 19765 | `/healthz` |
| `deploy-orchestrator-mcp` | mcp | 18000 | `/healthz` |
| `mcp-social` | mcp | 18080 | `/health` |
| `github-unified-mcp-bff` | bff | 18010 | `/healthz` |
| `vos-studio-mcp` | vos | 18020 | `/health` |
| `vos-studio-bff` | bff | 18030 | `/healthz` |

The smoke uses high local ports (18000â€“19765) so it does not clash with the
Compose mode ports (8765, 8001, 8080, 8010, 8020, 8030).

**Secrets in k3d**: the base k8s manifests do not inject env-var secrets.
The local overlay creates non-production `platform-secrets` placeholder values
so services can start and respond to health probes. For full end-to-end testing
with real auth, inject local values from `.env`:

```bash
just k3d-secrets
```

**Teardown**:

```bash
just k8s-local-down
```

### Compose vs k3d

| | Compose | k3d |
|---|---|---|
| Command | `just compose-up` | `just k8s-local-up` |
| Smoke | `just smoke-all` | `just smoke-k3d` |
| Runtime | Docker Compose | Kubernetes (k3s in k3d) |
| Networking | host ports | port-forward or loadbalancer (8088/8443) |
| Env vars | `.env` file | manifests / future Secrets |
| Best for | fast iteration | validating k8s manifests before VPS |

## Expose local services

```bash
just tunnel
```

## Status page

```bash
just status-page-init
just status-page-dev
```

`status-page-init` creates a local `cloudflare/workers/status-page/wrangler.toml`
from the tracked example if it does not already exist. Edit domains and routes
before deploying it.
