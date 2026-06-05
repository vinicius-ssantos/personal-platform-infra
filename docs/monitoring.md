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

## Alerting

This is a logs-only stack (Loki, no Prometheus/kube-state-metrics), so all alert
rules are **LogQL-based** and provisioned on startup from the
`grafana-alerting` ConfigMap (mounted at
`/etc/grafana/provisioning/alerting`). Config is in git — no manual UI clicks.

### Provisioned rules

| Rule | Severity | Fires when |
|---|---|---|
| `platform-service-fatal` | critical | `fatal`/`panic`/`crashloopbackoff` log lines appear in `mcp\|bff\|vos` (5m window) |
| `platform-high-error-rate` | warning | > 10 error log lines in `mcp\|bff\|vos` (5m) |
| `gateway-auth-failures` | warning | > 10 gateway `401`/`403` responses (5m) |

All three live in the `Platform Health` folder, evaluated every minute.

### Notification channel (Telegram)

The provisioned contact point `telegram` reads credentials from env vars
`TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID`, which Grafana expands via `$__env{}`.
Those come from the `grafana-alerting` Secret (`monitoring` namespace,
`secretKeyRef` with `optional: true`).

Set it up:

1. Create a bot via [@BotFather](https://t.me/BotFather) → copy the token.
2. Message the bot once, then read your chat id from
   `https://api.telegram.org/bot<TOKEN>/getUpdates`.
3. Fill the encrypted secret and apply:

   ```bash
   # in secrets/platform-secrets-vps.enc.yaml, monitoring/grafana-alerting:
   #   telegram-bot-token: <token>
   #   telegram-chat-id: <chat-id>
   just secrets-edit-vps-k8s   # edit encrypted in place
   just k8s-vps-secrets        # decrypt + kubectl apply -f -
   kubectl rollout restart deployment/grafana -n monitoring
   ```

Without the Secret (e.g. local k3d), the contact point is still provisioned but
delivers nothing — Grafana boots normally and rules still evaluate.

### Test an alert

Force the fatal-signal rule by injecting a matching log line, or scale a service
and watch error logs. To verify end-to-end delivery, temporarily lower a
threshold in `grafana-alerting.yaml` or emit matching log lines:

```bash
# emit a fatal line into a namespace Alloy scrapes
kubectl run alert-test -n mcp --restart=Never --image=busybox:1.36 \
  -- sh -c 'echo "FATAL: alert provisioning test"; sleep 5'
kubectl delete pod/alert-test -n mcp
```

Within ~1–2 evaluation cycles the `platform-service-fatal` alert should fire and,
if Telegram is configured, deliver a message.

### Adding a new rule

Append a rule object under `groups[].rules` in
`k8s/base/monitoring/grafana-alerting.yaml`. Each rule needs a unique `uid`, a
`condition` refId, a Loki query node (`datasourceUid: loki`) and a threshold
node (`datasourceUid: __expr__`). Re-apply the overlay and restart Grafana (or
let the provisioning reload pick it up).
