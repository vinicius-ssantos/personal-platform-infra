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
| `github-unified-mcp-bff` | `vinicius-ssantos/github-unified-mcp-bff` | BFF for GitHub MCP flows | upstream | `ghcr.io/vinicius-ssantos/github-unified-mcp-bff:main` configured and verified | yes, profile `github-bff` | yes, `GITHUB_UNIFIED_MCP_BFF_IMAGE` | `just smoke-github-bff` | `just smoke-k3d` | yes | ready | none | Depends on `github-unified-mcp` at `http://github-unified-mcp:8765`. k3d port-forward: 18010. |
| `vos-studio-mcp` | `vinicius-ssantos/vos-studio-mcp` | VOS Studio MCP server | upstream | `ghcr.io/vinicius-ssantos/vos-studio-mcp:main` configured and verified | yes, profile `vos` | yes, `VOS_STUDIO_MCP_IMAGE` | `just smoke-vos` | `just smoke-k3d` | yes | ready | #51 | Exposes MCP runtime on port `8000` inside the container. k3d port-forward: 18020. Compose healthcheck uses `/health` with relaxed timeout until the upstream service exposes a lightweight `/live` endpoint. |
| `vos-studio-bff` | `vinicius-ssantos/vos-studio-bff` | BFF for VOS Studio flows | upstream | `ghcr.io/vinicius-ssantos/vos-studio-bff:main` configured and verified | yes, profile `vos` | yes, `VOS_STUDIO_BFF_IMAGE` | `just smoke-vos` | `just smoke-k3d` | yes | ready | none | Depends on `vos-studio-mcp` at `http://vos-studio-mcp:8000`. k3d port-forward: 18030. |
| `central-mcp-gateway` | `vinicius-ssantos/central-mcp-gateway` | Unified public MCP gateway (auth, allowlist, audit) | upstream | `ghcr.io/vinicius-ssantos/central-mcp-gateway:main` configured | yes, profile `gateway` | yes, `CENTRAL_MCP_GATEWAY_IMAGE` | `just smoke-gateway-sh` | not yet | yes (k8s base, replicas=0) | wired | none | Aggregates github, deploy, social and vos MCPs. Port 8040 (Compose), 8080 (container). Env-specific values in overlays. |
| `jobHunterAgent` | `vinicius-ssantos/jobHunterAgent` | Job search automation agent (FastAPI + Playwright) | upstream | not confirmed | no | no | no | no | no | blocked | #117 | Python/FastAPI + SQLite + Playwright browser automation. LinkedIn session state is sensitive. Contract (port, health path, image) must be confirmed before integration. |
| `WorkflowEngine` | `vinicius-ssantos/WorkflowEngine` | Workflow orchestration backend | upstream | not confirmed | no | no | no | no | no | blocked | #118 | Java. External dependencies (DB, queue) unknown. Runtime contract must be confirmed and dependency strategy decided per ADR 0002 before integration. |
| `github-unified-mcp-frontend` | `vinicius-ssantos/github-unified-mcp-frontend` | React/Vite SPA for GitHub MCP flows | Cloudflare Pages | n/a — static SPA | no (Cloudflare Pages) | no | no | no | no (frontend stays in CDN per ADR 0003) | blocked | #119 | Infra role: update `FRONTEND_URL` in VPS overlay once Pages domain is confirmed. No Dockerfile or k8s manifests needed. |

## Validation checklist

- Compare the service list with `compose/docker-compose.yml`.
- Compare image variables with `.env.example`.
- Compare Kubernetes coverage with `k8s/base/apps/*`.
- Keep committed config free of real secrets.
- Update this matrix whenever a service changes image source, profile, port,
  smoke check, or Kubernetes readiness.

## Current blockers

| Service | Blocker | Tracking issue |
|---|---|---|
| `jobHunterAgent` | Runtime contract (image, port, health path, env, browser automation strategy) not confirmed | #117 |
| `WorkflowEngine` | Runtime contract and external dependency strategy not confirmed | #118 |
| `github-unified-mcp-frontend` | Cloudflare Pages domain and BFF `FRONTEND_URL` not confirmed | #119 |
