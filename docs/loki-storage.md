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

## Trade-offs

- PVC storage is simple and local to the VPS.
- It avoids losing all logs on a pod restart.
- It does not protect against full VPS loss.
- Future external object storage should be decided through a separate ADR if retention needs grow.

## Resize / rollback

To increase capacity, edit `k8s/overlays/vps/loki-pvc.yaml` and apply the VPS overlay again.

To go back to ephemeral storage on VPS, remove `loki-pvc.yaml` and `loki-volume-patch.yaml` from the VPS overlay and re-apply it.
