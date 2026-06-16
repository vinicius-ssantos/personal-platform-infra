# debug-k3d

Diagnose why a service is unhealthy in the local k3d cluster.

## What this does

Runs a structured triage sequence against the k3d cluster to identify why a pod is not ready.

## Arguments

```
/debug-k3d <service-name> [namespace]
```

Namespace defaults to `mcp`. Examples:
```
/debug-k3d central-mcp-gateway
/debug-k3d vos-studio-mcp vos
/debug-k3d grafana monitoring
```

## Triage steps

1. **Pod status** — `kubectl get pods -n <ns> -l app=<service>`
2. **Events** — `kubectl describe pod -n <ns> -l app=<service>` (look for ImagePullBackOff, OOMKilled, CrashLoopBackOff)
3. **Logs** — `kubectl logs -n <ns> -l app=<service> --tail=100`
4. **Previous logs** — `kubectl logs -n <ns> -l app=<service> --previous --tail=50` (if restart count > 0)
5. **Health probe** — port-forward and `curl -v http://localhost:<port><health-path>`
6. **Secret existence** — verify referenced Secrets/ConfigMaps exist in namespace
7. **Image pull** — check if image tag exists in GHCR (`ghcr.io/...`)

## Common fixes

| Symptom | Likely cause | Fix |
|---|---|---|
| `ImagePullBackOff` | Wrong tag or missing GHCR secret | `just create-ghcr-secret` |
| `CrashLoopBackOff` | Missing env var or secret | Check `envFrom` sources, run `just k3d-secrets` |
| `0/1 Ready` probe fail | Health path wrong or app not started | Check logs, verify health path in deployment |
| Pod stuck `Pending` | No nodes with capacity | `kubectl describe node` |

## Usage

```
/debug-k3d central-mcp-gateway
```
