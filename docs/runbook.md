# Runbook

## Service readiness

Before changing runtime wiring, check the [service integration matrix](service-integration-matrix.md).

## Recovery and rebuild

For VPS rebuilds or local workstation resets, use the [recovery and bootstrap runbook](disaster-recovery.md).

## VPS image releases

For immutable image versions, rollback guidance, and mutable tag policy, use the [image pinning strategy](image-pinning.md).

## Start local compose

```bash
just compose-up
```

Compose reads image tags from `.env`. To test a temporary local or branch image,
override the relevant image variable in `.env` instead of editing
`compose/docker-compose.yml`.

## Stop local compose

```bash
just compose-down
```

## Reset Local Environment

```bash
just clean
```

This stops Compose with volumes and deletes the local `personal-platform` k3d
cluster. Use `just clean-compose` or `just clean-k3d` for narrower cleanup.

## Start local Kubernetes

```bash
just k8s-local-up
```

## Sleep all Kubernetes workloads

```bash
just sleep-all
```

## Wake GitHub MCP stack

```bash
just wake-github
```

## Smoke GitHub MCP locally

```bash
just smoke-github
```

The smoke check starts only the `github` Compose profile, calls the configured
health URL, and prints the service status. By default it checks
`http://localhost:8765/healthz`; override it with
`GITHUB_UNIFIED_MCP_HEALTH_URL` if the upstream service exposes a different
health endpoint.

Common failure modes:

- missing `.env`: copy `.env.example` to `.env` and fill local values.
- missing image: confirm `GITHUB_UNIFIED_MCP_IMAGE` points to an available GHCR
  or local image tag.
- port already in use: free local port `8765` or override the Compose port for
  a local-only test.
- invalid token: refresh `GITHUB_TOKEN` or `MCP_BEARER_TOKEN` in `.env`.
- container exited: inspect logs with `just compose-logs`.

Teardown:

```bash
docker compose --env-file .env -f compose/docker-compose.yml --profile github down
```

## Wake VOS stack

```bash
just wake-vos
```

## Logs

```bash
just logs
```

## Centralized Logs

```bash
just logs-ui
```

Create the Grafana admin Secret before first access:

```bash
GRAFANA_ADMIN_PASSWORD='change-me-local-only' just grafana-secret
```

Open `http://localhost:3000` and sign in with the credentials from the
`monitoring/grafana-admin` Secret. The Grafana deployment is wired to the
in-cluster Loki service.

## KEDA HTTP Pilot

Install KEDA and the HTTP Add-on, then apply the GitHub MCP pilot routes:

```bash
just keda-http-install
```

Run the smoke through the interceptor proxy:

```bash
just smoke-keda-http
```

The pilot covers `github-unified-mcp` and `github-unified-mcp-bff`. Production
ingress must route `mcp-github.example.com` and `github-bff.example.com` to the
KEDA interceptor proxy service for scale-from-zero to work.

The checked-in hostnames are placeholders. Use the same names managed by the
Cloudflare layer for each environment:

| Environment | GitHub MCP hostname | GitHub BFF hostname |
|---|---|---|
| Local tunnel | `mcp-github.<domain>` | `github-bff.<domain>` |
| VPS | `mcp-github.<domain>` | `github-bff.<domain>` |

For local tunnel mode, Cloudflare Tunnel routes those hostnames to local Compose
ports. For VPS mode, DNS points at the VPS and ingress must forward those
hostnames to the KEDA HTTP interceptor proxy. Keep the pilot limited to these
two services until the ownership and routing model is proven.

When the pilot is enabled for a workload, KEDA owns its replica lifecycle during
normal operation. Do not use manual `wake-*` or `sleep-all` for that workload
except as break-glass recovery. See `docs/lifecycle.md` for the full ownership
rules.

## Platform status

```bash
just status
```

Prints k3d cluster state, all pods, Compose container health, and VPS cluster
reachability. Set `KUBECONFIG_VPS=/path/to/vps-kubeconfig` to include the VPS
section.

## Public access

Use Cloudflare Access before exposing MCP/BFF hostnames publicly. See
`docs/cloudflare-access.md` for Terraform variables, human identity policy and
service token request headers.

For account-less temporary Cloudflare URLs, Terraform is not involved. Start one
quick tunnel per local service with `cloudflared tunnel --url
http://localhost:<port>`, copy the generated `trycloudflare.com` URLs into
`.env`, and validate them with:

```bash
just status-public
```

On Windows, the full local quick-tunnel workflow is automated:

```bash
just quick-tunnel-up
```

This starts Compose, restarts one quick tunnel per service, writes the generated
public URLs into `.env`, preserves existing tokens, generates missing local
tokens, and runs local/public smoke checks.

By default, the command keeps existing `trycloudflare.com` URLs when they are
still healthy. This avoids Cloudflare Quick Tunnel rate limits. To force new
temporary URLs, run:

```bash
just quick-tunnel-refresh
```

Quick Tunnel creation can return Cloudflare `429 Too Many Requests` if tunnels
are recreated repeatedly in a short window. Wait a few minutes and retry.

Use `.env.quick-tunnel.example` as the template for this mode. Use
`terraform/cloudflare/terraform.tfvars.local-tunnel.example` only after you own
a domain and want stable Cloudflare-managed DNS.

## Ngrok Static Domain

Ngrok is the preferred no-owned-domain option when you need one stable public
URL. Authenticate ngrok once on the workstation:

```bash
ngrok config add-authtoken <your-token>
```

If your free ngrok account has a reserved static domain, set it in `.env`:

```env
NGROK_STATIC_DOMAIN=your-domain.ngrok-free.app
```

Then run:

```bash
just ngrok-up
```

This starts Compose, pulls the latest images, starts the local path proxy on
`localhost:8088`, starts ngrok, writes the public path-routed URLs into `.env`,
and runs public smoke checks. The exposed paths are:

```text
/github-mcp
/deploy-mcp
/social-mcp
/github-bff
/vos-mcp
/vos-bff
```

## Upgrade k3s (VPS)

Run on the VPS as root:

```bash
just k3s-upgrade
```

The script:
1. Scales all workloads to 0 (safe drain)
2. Drains the node
3. Installs the latest stable k3s
4. Waits for the node to be `Ready`
5. Uncordons the node

After upgrade, restore workloads:

```bash
kubectl apply -k k8s/overlays/vps
just wake-github
```

**Rollback:** install a specific version with:
```bash
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.29.4+k3s1 sh -
```

## Reset local environment

```bash
just clean
```

Stops Compose (with volumes), deletes the k3d cluster, and prunes orphaned
Docker volumes. Use when something is stuck or you need a clean slate.
