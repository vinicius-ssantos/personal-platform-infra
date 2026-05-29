# ADR 0015: Logs centralizados com Loki e Alloy

## Status

Accepted

## Context

Debugging the VPS requires checking logs pod by pod. The platform needs a
lightweight log aggregation path before automatic scale-to-zero is introduced.

## Decision

Run Loki, Grafana Alloy, and Grafana in a dedicated `monitoring` namespace.
Alloy uses Kubernetes API log tailing and sends pod logs to Loki.

## Consequences

- Operators get one query surface for logs across MCP and BFF services.
- The initial storage is ephemeral and intentionally lightweight.
- Production retention and persistent storage remain future hardening work.
