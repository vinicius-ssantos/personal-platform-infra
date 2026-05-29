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

| service | repository | role | Dockerfile | GHCR image | Compose wired | .env.example wired | local smoke check | k8s/k3d manifests | status | next issue | notes |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| `github-unified-mcp` | `vinicius-ssantos/github-unified-mcp` | GitHub MCP server | upstream | `ghcr.io/vinicius-ssantos/github-unified-mcp:main` configured | yes, profile `github` | yes, `GITHUB_UNIFIED_MCP_IMAGE` | `just smoke-github` | yes | ready | none | Compose is image-driven and read-only by default. |
| `deploy-orchestrator-mcp` | `vinicius-ssantos/deploy-orchestrator-mcp` | Deployment orchestration MCP server | upstream | `ghcr.io/vinicius-ssantos/deploy-orchestrator-mcp:main` configured; GHCR access not confirmed | yes, profile `deploy` | yes, `DEPLOY_ORCHESTRATOR_MCP_IMAGE` | missing | yes | blocked | `#6` | Compose is image-driven with read-only and confirmation flags enabled. Confirm package visibility or tag availability before closing. |
| `mcp-social` | `vinicius-ssantos/mcp-social` | Social integration MCP server | unknown | `ghcr.io/vinicius-ssantos/mcp-social:latest` configured | yes, profile `social` | yes, `MCP_SOCIAL_IMAGE` | missing | yes | wired | none | Uses a local Compose volume for SQLite data. |
| `github-unified-mcp-bff` | `vinicius-ssantos/github-unified-mcp-bff` | BFF for GitHub MCP flows | unknown | `ghcr.io/vinicius-ssantos/github-unified-mcp-bff:latest` configured | yes, profile `github-bff` | yes, `GITHUB_UNIFIED_MCP_BFF_IMAGE` | missing | yes | wired | none | Depends on `github-unified-mcp` at `http://github-unified-mcp:8765`. |
| `vos-studio-mcp` | `vinicius-ssantos/vos-studio-mcp` | VOS Studio MCP server | unknown | `ghcr.io/vinicius-ssantos/vos-studio-mcp:latest` configured | yes, profile `vos` | yes, `VOS_STUDIO_MCP_IMAGE` | missing | yes | wired | none | Exposes MCP runtime on port `8000` inside the container. |
| `vos-studio-bff` | `vinicius-ssantos/vos-studio-bff` | BFF for VOS Studio flows | unknown | `ghcr.io/vinicius-ssantos/vos-studio-bff:latest` configured | yes, profile `vos` | yes, `VOS_STUDIO_BFF_IMAGE` | missing | yes | wired | none | Depends on `vos-studio-mcp` at `http://vos-studio-mcp:8000`. |

## Validation checklist

- Compare the service list with `compose/docker-compose.yml`.
- Compare image variables with `.env.example`.
- Compare Kubernetes coverage with `k8s/base/apps/*`.
- Keep committed config free of real secrets.
- Update this matrix whenever a service changes image source, profile, port,
  smoke check, or Kubernetes readiness.

## Current blockers

- `deploy-orchestrator-mcp:main` is configured, but GHCR access still needs to
  be confirmed with Docker auth or upstream package visibility before `#6` is
  closed.
