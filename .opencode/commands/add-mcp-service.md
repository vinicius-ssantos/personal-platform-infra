---
description: Scaffold all files to add a new MCP service to the platform
---

Add a new MCP service to the platform: $ARGUMENTS

Expected arguments: `<name> <namespace> <port> <image> <health-path>`
Example: `my-new-mcp mcp 8000 ghcr.io/org/my-new-mcp:1.0.0 /healthz`

If arguments are incomplete, ask the user for missing values.

Steps (follow ADRs):
1. k8s base — create `k8s/base/apps/<name>/`: deployment.yaml (replicas:0, liveness+readiness probes, resource limits), service.yaml (ClusterIP), kustomization.yaml. Register in `k8s/base/kustomization.yaml`.
2. k8s overlay local — add replica patch > 0 in `k8s/overlays/local/replicas-local.yaml`
3. Compose — add service to `compose/docker-compose.yml` with profile, ports, healthcheck
4. Smoke script — create `scripts/smoke-<name>.sh` and `scripts/smoke-<name>.ps1`
5. Justfile — add `smoke-<name>` and `smoke-<name>-sh` recipes
6. Docs — update `CLAUDE.md` service table and docs
7. Validate — run `kubectl kustomize k8s/overlays/local`, check for REPLACE_WITH_ placeholders
