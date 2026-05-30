# Loki log ingestion smoke

Use this smoke test after the monitoring stack is running in local/k3d or VPS.

```bash
just smoke-logs
```

The script validates more than pod readiness:

1. `kubectl` can reach a cluster.
2. The `monitoring` namespace exists.
3. Loki and Alloy pods are running.
4. Loki `/ready` is reachable through a temporary port-forward.
5. Loki returns recent log streams for the configured selector.

## Configuration

Optional environment variables:

```bash
LOKI_NAMESPACE=monitoring
LOKI_SERVICE=loki
LOKI_PORT=3100
LOKI_LOCAL_PORT=13100
LOKI_QUERY_SELECTOR='{namespace=~"mcp|bff|vos|monitoring"}'
LOKI_QUERY_LIMIT=5
LOKI_SINCE_SECONDS=3600
```

## Interpreting failures

- Missing Loki pod: check the monitoring overlay and Loki rollout.
- Missing Alloy pod: check Alloy manifests and DaemonSet/Deployment status.
- Port-forward failure: check `svc/loki`, pod readiness, and local port conflicts.
- Empty query result: Loki is reachable, but no matching streams were ingested recently. Check Alloy RBAC/config, workload labels, and whether workloads emitted logs in the selected time window.

The smoke is intentionally manual/optional because it requires a live Kubernetes cluster with running workloads.
