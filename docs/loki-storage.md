# Loki storage

## Local/k3d

The local overlay keeps Loki lightweight and ephemeral. The base deployment uses `emptyDir` for `/loki`, so logs are lost when the pod is recreated.

This is intentional for local smoke tests and short-lived troubleshooting sessions.

## VPS

The VPS overlay adds a `PersistentVolumeClaim` named `monitoring/loki-data` and patches the Loki deployment to mount `/loki` from that claim.

Default request:

```yaml
storage: 5Gi
```

On a single-node k3s VPS, this is meant to preserve recent troubleshooting logs across basic Loki pod restarts or rescheduling. It is not a long-term log archive.

## Retention

Retention is enforced by Loki itself, configured in
`k8s/base/monitoring/loki-config.yaml`:

| Setting | Value | Meaning |
|---|---|---|
| `limits_config.retention_period` | `168h` | logs are kept for 7 days |
| `compactor.retention_enabled` | `true` | the compactor deletes data past the period |
| `compactor.delete_request_store` | `filesystem` | delete markers live on the PVC |
| `schema_config … index.period` | `24h` | index files rotate daily |

So even on the VPS, Loki is a **rolling 7-day window**, not an archive. To keep
logs longer, raise `retention_period` and size the PVC accordingly (a larger
window needs more than the default 5Gi).

## Backup

The Loki PVC is intentionally **not** backed up: it holds transient operational
logs within the 7-day window, not data of record. On full VPS loss, accept the
log gap and let Loki repopulate from new traffic.

If a specific incident window must be preserved, export the relevant lines ad
hoc instead of backing up the whole volume — for example via Grafana's Explore
"Download logs", or `logcli query` against the Loki API while the pod is awake.

## Trade-offs

- PVC storage is simple and local to the VPS.
- It avoids losing all logs on a pod restart.
- It does not protect against full VPS loss (acceptable — see Backup above).
- Future external object storage should be decided through a separate ADR if retention needs grow.

## Resize / rollback

To increase capacity, edit `k8s/overlays/vps/loki-pvc.yaml` and apply the VPS overlay again.

To go back to ephemeral storage on VPS, remove `loki-pvc.yaml` and `loki-volume-patch.yaml` from the VPS overlay and re-apply it.
