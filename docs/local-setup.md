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

```bash
just k8s-local-up
kubectl get pods -A
just k8s-local-down
```

## Expose local services

```bash
just tunnel
```
