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
| `mcp-code-sandbox` | `vinicius-ssantos/mcp-code-sandbox` | Isolated code execution MCP server | upstream | n/a, runs host-local to access Docker daemon | external host process | yes, `SANDBOX_API_KEY`, `GATEWAY_UPSTREAM_SANDBOX_URL` | direct sandbox smoke, then `just smoke-gateway` | not enabled by default | no, consumed as external gateway upstream | ready | none | Runs on host port `8766`; gateway reaches it via `http://host.docker.internal:8766/mcp` in Compose. Not containerized to avoid mounting Docker socket into a container. |
| `repo-research-sidecar` | `vinicius-ssantos/repo-research-mcp` | Repo research MCP sidecar behind central gateway | upstream | `ghcr.io/vinicius-ssantos/repo-research-mcp:main` | yes, profile `gateway` | yes, `REPO_RESEARCH_GITHUB_TOKEN`, `REPO_RESEARCH_ALLOWED_REPOSITORIES` as JSON array | `just smoke-gateway-sh` / `just smoke-gateway-ps` checks `/readyz` | `just smoke-k3d` | yes | ready | none | Internal-only sidecar on port `8081`; gateway reaches it via `GATEWAY_UPSTREAM_REPO_RESEARCH_URL`. |
| `github-unified-mcp-bff` | `vinicius-ssantos/-github-unified-mcp-bff` | BFF for GitHub MCP flows | upstream | `ghcr.io/vinicius-ssantos/github-unified-mcp-bff:main` configured and verified | yes, profile `github-bff` | yes, `GITHUB_UNIFIED_MCP_BFF_IMAGE` | `just smoke-github-bff` | `just smoke-k3d` | yes | ready | none | Depends on `github-unified-mcp` at `http://github-unified-mcp:8765`. k3d port-forward: 18010. |
| `vos-studio-mcp` | `vinicius-ssantos/vos-studio-mcp` | VOS Studio MCP server | upstream | `ghcr.io/vinicius-ssantos/vos-studio-mcp:main` configured and verified | yes, profile `vos` | yes, `VOS_STUDIO_MCP_IMAGE` | `just smoke-vos` | `just smoke-k3d` | yes | ready | #51 | Exposes MCP runtime on port `8000` inside the container. k3d port-forward: 18020. Compose healthcheck uses `/health` with relaxed timeout until the upstream service exposes a lightweight `/live` endpoint. |
| `vos-studio-bff` | `vinicius-ssantos/vos-studio-bff` | BFF for VOS Studio flows | upstream | `ghcr.io/vinicius-ssantos/vos-studio-bff:main` configured and verified | yes, profile `vos` | yes, `VOS_STUDIO_BFF_IMAGE` | `just smoke-vos` | `just smoke-k3d` | yes | ready | none | Depends on `vos-studio-mcp` at `http://vos-studio-mcp:8000`. k3d port-forward: 18030. |
| `job-hunter-agent` | `vinicius-ssantos/jobHunterAgent` | Automated job search agent | upstream | `ghcr.io/vinicius-ssantos/jobhunteragent:main` | yes, profile `job-hunter` | yes, `JOB_HUNTER_IMAGE` | `just smoke-job-hunter` | not enabled | no | ready | #117 | CLI scheduler/worker (no HTTP port). Requires Ollama for LLM features. Profile includes optional `ollama` service. Config via bind-mount. |
| `github-unified-mcp-frontend` | `vinicius-ssantos/github-unified-mcp-frontend` | Frontend SPA for GitHub MCP | upstream | n/a (Cloudflare Pages) | n/a (CDN-hosted) | `FRONTEND_URL` in BFF overlays | n/a | n/a | no (ADR 0003) | wired | #119 | Hosted on Cloudflare Pages per ADR 0003. No k8s manifest, no compose entry. BFF overlays contain `FRONTEND_URL` and `ALLOWED_ORIGINS`. |
| `workflow-engine` | `vinicius-ssantos/WorkflowEngine` | Event-driven workflow orchestration engine | upstream | `ghcr.io/vinicius-ssantos/workflow-engine:main` configured, but current `:main` fails healthcheck (Redis env binding bug, fix in upstream PR #91) | yes, profile `workflow-engine` (not in `all` until #91 ships) | yes, `WORKFLOW_ENGINE_IMAGE`, `WORKFLOW_ENGINE_KAFKA_BOOTSTRAP_SERVERS` | `just smoke-workflow-engine` (currently fails against `:main`) | not enabled | yes | blocked | WorkflowEngine#91 | Java 21 / Spring Boot 4.0.6. Port 8080 (host 8081), health `/actuator/health`. Requires PostgreSQL (Compose-local `postgres-workflow-engine`) + Redis + Redpanda/Kafka; k8s deployment expects all three as external services via `platform-secrets` (ADR 0002). |

## Validation checklist

- Compare the service list with `compose/docker-compose.yml`.
- Compare image variables with `.env.example`.
- Compare Kubernetes coverage with `k8s/base/apps/*`.
- Keep committed config free of real secrets.
- Update this matrix whenever a service changes image source, profile, port,
  smoke check, or Kubernetes readiness.

## Current blockers

No current blockers for services marked `ready`.
