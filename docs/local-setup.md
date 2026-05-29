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
just bootstrap-local
```

## Compose mode

```bash
cp .env.example .env
just compose-up
just compose-logs
just compose-down
```

The GitHub and deploy MCP services consume images published by their upstream
repositories:

- `ghcr.io/vinicius-ssantos/github-unified-mcp:main`
- `ghcr.io/vinicius-ssantos/deploy-orchestrator-mcp:main`

To test a different image locally, edit only your uncommitted `.env` file and
override `GITHUB_UNIFIED_MCP_IMAGE` or `DEPLOY_ORCHESTRATOR_MCP_IMAGE`.

If GHCR returns `denied` for an image, confirm that the package exists, the tag
is published, and Docker is logged in with access to the package.

To smoke-test only the GitHub MCP service:

```bash
just smoke-github
```

## Kubernetes mode

`just k8s-local-up` creates (or reuses) the `personal-platform` k3d cluster and
applies the local Kustomize overlay. The overlay includes a replica patch that
starts the four ready services automatically.

```bash
just k8s-local-up
kubectl get pods -A
just k8s-local-down
```

### k3d smoke test

`just smoke-k3d` is the single-command validation for the Kubernetes local path.
It covers the full cycle: prerequisite check → cluster create-or-reuse → overlay
apply → rollout wait → per-service health check via `kubectl port-forward`.

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

The smoke uses high local ports (18000–19765) so it does not clash with the
Compose mode ports (8765, 8001, 8080, 8010).

**Secrets in k3d**: the base k8s manifests do not inject env-var secrets.
Services start without tokens and should respond to health probes. For full
end-to-end testing with auth, create a local `Secret` or `ConfigMap` from
`.env` values and reference it in the deployment. This is outside the scope of
the smoke test.

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
