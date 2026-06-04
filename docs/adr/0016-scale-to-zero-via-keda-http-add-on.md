# ADR 0016: Scale-to-zero via KEDA HTTP Add-on

## Status

Accepted — extended from pilot (2 services) to full platform (all 7 services)

## Context

The platform sleeps workloads by setting replicas to zero, but waking services
manually is operational friction. The first implementation should stay native to
Kubernetes and use the centralized logs added before this decision.

The initial pilot covered `github-unified-mcp` and `github-unified-mcp-bff`.
After validating the routing model, scale-to-zero was extended to all remaining
platform services.

## Decision

Use KEDA HTTP Add-on as the scale-to-zero mechanism for **all 7 platform
services**:

| Service | Namespace | `InterceptorRoute` hostname |
|---|---|---|
| `github-unified-mcp` | mcp | `mcp-github.<domain>` |
| `github-unified-mcp-bff` | bff | `github-bff.<domain>` |
| `deploy-orchestrator-mcp` | mcp | `deploy-mcp.<domain>` |
| `mcp-social` | mcp | `social-mcp.<domain>` |
| `vos-studio-mcp` | vos | `vos-mcp.<domain>` |
| `vos-studio-bff` | bff | `vos-bff.<domain>` |
| `central-mcp-gateway` | mcp | `mcp-gateway.<domain>` |

Hostnames use `__VPS_DOMAIN__` tokens in the manifests. `keda-http-install.sh`
renders them at apply time via `kustomize build | sed`. For local/k3d testing,
`VPS_DOMAIN` defaults to `example.com` (matching `smoke-keda-http.sh` Host
headers). For VPS production: `VPS_DOMAIN=your.domain just keda-http-install`.

The HTTP Add-on deploys an interceptor, scaler, and operator. Traffic must be
routed to the interceptor proxy, which then forwards to the target service while
KEDA scales the backing deployment.

## central-mcp-gateway min-replicas decision

The gateway is the public OAuth edge for ChatGPT and the ingress point for all
upstream MCP services. `minReplicaCount: 0` was chosen — cold-start latency
(typically 5–15 s) on the first request after a 10-minute idle period is
acceptable for personal use. If this becomes a problem, raise `minReplicaCount`
to `1` in `k8s/addons/keda-http/pilot/central-mcp-gateway.yaml`.

## Consequences

- All services use `InterceptorRoute` (KEDA HTTP API `v1beta1`) and explicit
  `ScaledObject` resources (`keda.sh/v1alpha1`).
- The cooldown period is 600 seconds (10 minutes of inactivity) for all
  services, including the gateway.
- Ingress/DNS must route service hostnames to the interceptor proxy, not
  directly to the services.
- KEDA is the replica lifecycle owner for all platform workloads during normal
  operation. The `wake-*.sh` scripts are **break-glass only** — do not use them
  to wake KEDA-managed services during normal operation; send an HTTP request
  through the interceptor proxy instead.
- `sleep-all.sh` should be used only during maintenance; KEDA will scale services
  back up on the next incoming request.
- `mcp-social` scale-to-zero is safe — SQLite handles process restart cleanly.

See `docs/lifecycle.md` for the operator rules that define when replicas are
manual-managed, overlay-managed, or KEDA-managed.
