# add-mcp-service

Scaffold all files needed to add a new MCP service to the platform.

## What this does

Creates k8s manifests, Compose entry, smoke script, Justfile recipe, and docs stubs for a new service — following all ADRs.

## Arguments

```
/add-mcp-service <name> <namespace> <port> <image> <health-path>
```

Example:
```
/add-mcp-service my-new-mcp mcp 8000 ghcr.io/org/my-new-mcp:1.0.0 /healthz
```

## Steps

1. **k8s base** — create `k8s/base/apps/<name>/`:
   - `deployment.yaml` with `replicas: 0`, liveness + readiness probes, resource limits
   - `service.yaml` ClusterIP on `<port>`
   - `kustomization.yaml` listing both
   - Register in `k8s/base/kustomization.yaml`

2. **k8s overlay** — add replica patch to `k8s/overlays/local/replicas-local.yaml`

3. **Compose** — add service to `compose/docker-compose.yml` with profile, ports, healthcheck

4. **Smoke script** — create `scripts/smoke-<name>.sh` (bash) and `.ps1` (PowerShell)

5. **Justfile** — add `smoke-<name>` and `smoke-<name>-sh` recipes

6. **Docs** — append row to `docs/service-integration-matrix.md` and update `CLAUDE.md` service table

7. **Validate** — run `kubectl kustomize k8s/overlays/local` and check for `REPLACE_WITH_` placeholders

## Constraints (ADRs)

- `replicas: 0` in base (ADR 0001)
- No Dockerfiles, image from GHCR (ADR 0006)
- Kustomize not Helm (ADR 0007)
- Namespace must be `mcp`, `bff`, or `vos` (ADR 0010)
- No plaintext secrets (ADR 0004)
