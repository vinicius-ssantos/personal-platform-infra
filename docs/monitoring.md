# Monitoring

## Grafana admin credentials

Grafana reads admin credentials from the Kubernetes Secret `monitoring/grafana-admin`.
The tracked manifests do not contain real Grafana credentials.

Required keys:

- `admin-user`
- `admin-password`

### Local/k3d bootstrap

Create or update the Secret before starting or restarting Grafana:

```bash
GRAFANA_ADMIN_PASSWORD='change-me-local-only' just grafana-secret
```

Optional variables:

```bash
GRAFANA_ADMIN_USER='admin'
GRAFANA_NAMESPACE='monitoring'
GRAFANA_ADMIN_SECRET_NAME='grafana-admin'
```

Then access Grafana through port-forward:

```bash
just logs-ui
```

### VPS bootstrap

For VPS/production-like environments, source `GRAFANA_ADMIN_PASSWORD` from the encrypted secrets flow, not from a committed manifest or shell history.

```bash
TARGET_ENV=vps GRAFANA_ADMIN_PASSWORD='<from-sops-secret>' just grafana-secret
```

The helper refuses `GRAFANA_ADMIN_PASSWORD=admin` when `TARGET_ENV` is not `local`.

### Recovery

If Grafana pods fail with missing Secret errors, recreate the Secret and restart the deployment:

```bash
GRAFANA_ADMIN_PASSWORD='<value>' just grafana-secret
kubectl rollout restart deployment/grafana -n monitoring
```
