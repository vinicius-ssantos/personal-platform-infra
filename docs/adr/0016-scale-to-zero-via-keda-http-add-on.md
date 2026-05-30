# ADR 0016: Scale-to-zero via KEDA HTTP Add-on

## Status

Accepted

## Context

The platform sleeps workloads by setting replicas to zero, but waking services
manually is operational friction. The first implementation should stay native to
Kubernetes and use the centralized logs added before this decision.

## Decision

Use KEDA HTTP Add-on as the pilot scale-to-zero mechanism for
`github-unified-mcp` and `github-unified-mcp-bff`.

The HTTP Add-on deploys an interceptor, scaler, and operator. Traffic must be
routed to the interceptor proxy, which then forwards to the target service while
KEDA scales the backing deployment.

## Consequences

- The pilot uses `InterceptorRoute` and explicit KEDA `ScaledObject` resources.
- The cooldown period is 600 seconds, matching the 10 minute inactivity target.
- Ingress/DNS must route pilot hostnames to the interceptor proxy instead of
  directly to the services.
- KEDA becomes the replica lifecycle owner for pilot workloads during normal
  operation. Manual wake/sleep scripts should not scale those workloads except
  during break-glass recovery.
- VOS and other services remain outside the pilot until their runtime contracts
  are confirmed.

See `docs/lifecycle.md` for the operator rules that define when replicas are
manual-managed, overlay-managed, or KEDA-managed.
