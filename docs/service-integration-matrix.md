# Service integration matrix

This matrix tracks runtime readiness for services managed by this repository.
Use it before changing Compose, Kubernetes manifests, image tags, or local
operator scripts.

## Status legend

- `ready`: wired in this repo and has a known local validation path.
- `wired`: declared in this repo, but not yet smoke-tested here.
- `blocked`: waiting on an upstream image, repository access, or runtime contract.
- `unknown`: not yet verified from this repo.

## Matrix

| service | repository | role | Dockerfile | GHCR image | Compose wired | .env.example wired | local smoke check | k3d smoke check | k8s/k3d manifests | status | next issue | notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `github-unified-mcp` | `vinicius-ssantos/github-unified-mcp` | GitHub MCP server | upstream | `ghcr.io/vinicius-ssantos/github-unified-mcp:main` configured | yes, profile `github` | yes, `GITHUB_UNIFIED_MCP_IMAGE` | `just smoke-github` | `just smoke-k3d` | yes | ready | none | Compose is image-driven and read-only by default. k3d port-forward: 19765. |
| `deploy-orchestrator-mcp` | `vinicius-ssantos/deploy-orchestrator-mcp` | Deployment orchestration MCP server | upstream | `ghcr.io/vinicius-ssantos/deploy-orchestrator-mcp:main` configured and verified | yes, profile `deploy` | yes, `DEPLOY_ORCHESTRATOR_MCP_IMAGE` | `just smoke-deploy` | `just smoke-k3d` | yes | ready | none | Compose exposes host port `8001`. k3d port-forward: 18000. |
| `mcp-social` | `vinicius-ssantos/mcp-social` | Social integration MCP server | upstream | `ghcr.io/vinicius-ssantos/mcp-social:main` configured and verified | yes, profile `social` | yes, `MCP_SOCIAL_IMAGE` | `just smoke-social` | `just smoke-k3d` | yes | ready | none | Uses a local Compose volume for SQLite data. k3d port-forward: 18080. |
| `mcp-code-sandbox` | `vinicius-ssantos/mcp-code-sandbox` | Isolated code execution MCP server | upstream | local build `mcp-code-sandbox-server:local` via `MCP_CODE_SANDBOX_REPO_PATH` | yes, profile `sandbox` | yes, `SANDBOX_API_KEY`, `MCP_CODE_SANDBOX_REPO_PATH`, `GATEWAY_UPSTREAM_SANDBOX_URL` | `just compose-up`, then `just smoke-gateway` | not enabled by default | no, consumed as external gateway upstream | ready | none | Compose exposes host port `8766`; gateway reaches it via `http://mcp-code-sandbox:8766/mcp`. Local Compose mounts the Docker socket so the sandbox server can create ephemeral execution containers. |
| `github-unified-mcp-bff` | `vinicius-ssantos/-github-unified-mcp-bff` | BFF for GitHub MCP flows | upstream | `ghcr.io/vinicius-ssantos/github-unified-mcp-bff:main` configured and verified | yes, profile `github-bff` | yes, `GITHUB_UNIFIED_MCP_BFF_IMAGE` | `just smoke-github-bff` | `just smoke-k3d` | yes | ready | none | Depends on `github-unified-mcp` at `http://github-unified-mcp:8765`. k3d port-forward: 18010. |
| `vos-studio-mcp` | `vinicius-ssantos/vos-studio-mcp` | VOS Studio MCP server | upstream | `ghcr.io/vinicius-ssantos/vos-studio-mcp:main` configured and verified | yes, profile `vos` | yes, `VOS_STUDIO_MCP_IMAGE` | `just smoke-vos` | `just smoke-k3d` | yes | ready | #51 | Exposes MCP runtime on port `8000` inside the container. k3d port-forward: 18020. Compose healthcheck uses `/health` with relaxed timeout until the upstream service exposes a lightweight `/live` endpoint. |
| `vos-studio-bff` | `vinicius-ssantos/vos-studio-bff` | BFF for VOS Studio flows | upstream | `ghcr.io/vinicius-ssantos/vos-studio-bff:main` configured and verified | yes, profile `vos` | yes, `VOS_STUDIO_BFF_IMAGE` | `just smoke-vos` | `just smoke-k3d` | yes | ready | none | Depends on `vos-studio-mcp` at `http://vos-studio-mcp:8000`. k3d port-forward: 18030. |

## Validation checklist

- Compare the service list with `compose/docker-compose.yml`.
- Compare image variables with `.env.example`.
- Compare Kubernetes coverage with `k8s/base/apps/*`.
- Keep committed config free of real secrets.
- Update this matrix whenever a service changes image source, profile, port,
  smoke check, or Kubernetes readiness.

## Current blockers

No current blockers for services marked `ready`.
