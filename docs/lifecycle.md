# Runtime lifecycle ownership

This document defines who controls Kubernetes replicas in each environment.

## Rule of thumb

Only one controller should own replicas for a workload at a time.

A workload is either:

1. **Manual-managed** — operators use `just wake-*`, `just sleep-all`, or direct `kubectl scale`.
2. **Overlay-managed** — Kustomize overlay values define the desired replica count.
3. **KEDA-managed** — KEDA HTTP Add-on owns scale-from-zero and cooldown behavior.

Do not mix manual scale commands with KEDA-managed workloads during normal operation.

## Local/k3d

Local/k3d is manual/overlay-managed:

- `k8s/overlays/local` brings the ready services up for development.
- `just wake-*` can be used to bring specific services up.
- `just sleep-all` can be used to return workloads to zero.
- KEDA HTTP Add-on is not the default local lifecycle owner.

## VPS before KEDA

The VPS overlay is conservative:

- `k8s/overlays/vps` keeps application workloads sleeping by default with replicas set to zero.
- Operators use `just wake-*` for the service they need.
- `just sleep-all` returns non-KEDA workloads to zero after use.

This mode is simple and explicit, but requires manual wake-up.

## VPS with KEDA HTTP Add-on

When a workload is onboarded to the KEDA HTTP Add-on:

- Traffic must route to the KEDA interceptor service, not directly to the target service.
- KEDA owns scale-from-zero and cooldown for that workload.
- Manual `wake-*` and `sleep-all` should not be used for that workload during normal operation.
- Manual scale may still be used as break-glass recovery, but the operator should document what happened and restore the KEDA resources after recovery.

Current pilot workloads:

- `github-unified-mcp`
- `github-unified-mcp-bff`

Other services remain manual-managed until they are explicitly onboarded to KEDA.

## Operator decision table

| Environment | Workload state | Replica owner | Normal command |
| --- | --- | --- | --- |
| local/k3d | default local development | overlay/manual | `just smoke-k3d`, `just wake-*`, `just sleep-all` |
| VPS | not onboarded to KEDA | manual | `just wake-*`, `just sleep-all` |
| VPS | onboarded to KEDA HTTP Add-on | KEDA | send traffic through KEDA interceptor |
| VPS | break-glass incident | operator | direct `kubectl scale`, then restore intended owner |

## Script behavior policy

Manual scripts should remain safe for non-KEDA workloads.

When a script may touch a KEDA-managed workload, it should either:

- skip that workload by default; or
- print a clear warning that KEDA should be the lifecycle owner.

Expanding KEDA to additional services requires updating this document and the KEDA pilot manifests in the same change.
