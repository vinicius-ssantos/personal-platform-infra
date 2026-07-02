---
description: Diagnose why a pod is unhealthy in the local k3d cluster
---

Debug the unhealthy pod: $ARGUMENTS

If no service name provided, ask which service to debug. Namespace defaults to `mcp`.

Triage sequence:
1. `kubectl get pods -n <ns> -l app=<service>` — pod status
2. `kubectl describe pod -n <ns> -l app=<service>` — events (ImagePullBackOff, OOMKilled, CrashLoopBackOff)
3. `kubectl logs -n <ns> -l app=<service> --tail=100` — current logs
4. `kubectl logs -n <ns> -l app=<service> --previous --tail=50` — previous logs if restart > 0
5. Verify referenced Secrets/ConfigMaps exist in namespace
6. If image pull issue: suggest `just create-ghcr-secret`

Common fixes:
- ImagePullBackOff → wrong tag or missing GHCR secret → `just create-ghcr-secret`
- CrashLoopBackOff → missing env var or secret → check envFrom, run `just k3d-secrets`
- 0/1 Ready probe fail → health path wrong or app not started → check logs, verify path
