# VPS deploy checklist

End-to-end steps to take the platform from a configured repo to a running VPS
deploy. The repo-side configuration is done; the items below need real
credentials and a reachable cluster, so they are run by the operator (not CI).

See also: `docs/vps-setup.md` (provisioning), `docs/secrets.md` (SOPS),
`docs/image-pinning.md` (image refs), `docs/disaster-recovery.md`.

## 1. One-time GitHub configuration

| What | Where | Notes |
|---|---|---|
| `VPS_DOMAIN` | Actions → Variables (repo) | Base domain, e.g. `example.org`. Renders the `__VPS_DOMAIN__` token. Not a secret. |
| `VPS_KUBECONFIG` | Actions → Secrets (repo) | base64 of the k3s kubeconfig. Without it `deploy-vps.yml` is a no-op. |

```bash
# produce the VPS_KUBECONFIG value (run on the VPS / where you have the kubeconfig)
base64 -w0 < kubeconfig.yaml
```

## 2. Cluster bootstrap (first time)

```bash
export VPS_DOMAIN=example.org        # base domain
export KUBECONFIG=/path/to/vps.kubeconfig

# a) Namespaces + service accounts + workloads (replicas=0)
just k8s-vps-apply

# b) GHCR pull secret in mcp/bff/vos
GHCR_USERNAME=<user> GHCR_TOKEN=<read:packages token> just create-ghcr-secret

# c) Runtime secrets (platform-secrets in mcp/bff/vos + grafana-admin) via SOPS
#    (populate secrets/platform-secrets-vps.enc.yaml first — see docs/secrets.md)
just k8s-vps-secrets
```

## 3. Preflight — go/no-go

```bash
VPS_DOMAIN=example.org just preflight-vps
```

`scripts/preflight-vps.sh` verifies tooling, a reachable cluster, that the
overlay renders, and that the required secrets exist:

- `ghcr-pull-secret` in `mcp`, `bff`, `vos` — **required**
- `platform-secrets` in `mcp`, `bff`, `vos` — **required**
- `grafana-admin` in `monitoring` — recommended (Grafana crashloops without it)

It exits non-zero while any **[FAIL]** remains. Resolve them before deploying.

## 4. Deploy

- **Automated:** merge to `main` touching `k8s/**` → `deploy-vps.yml` renders the
  overlay with `VPS_DOMAIN` and applies it (skips with a notice if
  `VPS_KUBECONFIG` is unset; errors if `VPS_DOMAIN` is unset).
- **Manual:** `just k8s-vps-apply` with `VPS_DOMAIN` exported and the VPS
  kubeconfig active.

## 5. Wake and validate

```bash
just wake-github        # or wake-vos / wake-all — workloads start at replicas=0
just status
```

Check the public hostnames once Cloudflare DNS/Access is applied
(`just terraform-apply`); the `mcp-gateway.<domain>` edge is public (no Access),
the other services sit behind Cloudflare Access.

## Rollback

Workloads sleep at `replicas=0` by default; scale a service back down with
`just sleep-all` or `kubectl scale`. For image rollbacks see
`docs/image-pinning.md`; for full cluster recovery see `docs/disaster-recovery.md`.
