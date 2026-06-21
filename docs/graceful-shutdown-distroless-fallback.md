# Graceful shutdown: distroless image fallback (issue #208)

`k8s/base/graceful-shutdown-patch.yaml` applies the same `preStop` hook to
every Deployment in this repo:

```yaml
- op: add
  path: /spec/template/spec/containers/0/lifecycle
  value:
    preStop:
      exec:
        command: ["/bin/sh", "-c", "sleep 5"]
```

This depends on `/bin/sh` existing in the container image. Distroless or
`scratch`-based images don't have a shell — the kubelet would log a
`FailedPreStopHook` event and the drain window would be skipped entirely.

## Finding: no image currently in use lacks `/bin/sh`

Checked every image referenced by `k8s/base/apps/*/deployment.yaml` and
`k8s/base/monitoring/*.yaml` directly (`docker run --rm --entrypoint /bin/sh
<image> -c "echo ok"`), as of 2026-06-21:

| Image | Has `/bin/sh` |
|---|---|
| `ghcr.io/vinicius-ssantos/central-mcp-gateway:main` | yes |
| `ghcr.io/vinicius-ssantos/deploy-orchestrator-mcp:main` | yes |
| `ghcr.io/vinicius-ssantos/github-unified-mcp-bff:main` | yes |
| `ghcr.io/vinicius-ssantos/github-unified-mcp:main` | yes |
| `ghcr.io/vinicius-ssantos/mcp-social:main` | yes |
| `ghcr.io/vinicius-ssantos/repo-research-mcp:main` | yes |
| `ghcr.io/vinicius-ssantos/vos-studio-bff:main` | yes |
| `ghcr.io/vinicius-ssantos/vos-studio-mcp:main` | yes |
| `ghcr.io/vinicius-ssantos/workflow-engine:main` | yes |
| `grafana/alloy:v1.7.4` | yes |
| `grafana/grafana:11.5.2` | yes |
| `grafana/loki:3.4.2` | yes |
| `prom/prometheus:v3.2.1` | yes |

**Conclusion: the current `exec`-based preStop hook works for every
deployment in this platform today.** Per the issue's own scoping ("não
remover o patch atual até confirmar falha real"), no patch change is being
made in this PR — there is no confirmed (or even possible, given the above)
`FailedPreStopHook` to fix yet.

Re-run the check above whenever a new service/image is added to
`k8s/base/apps/`:

```bash
MSYS_NO_PATHCONV=1 docker run --rm --entrypoint /bin/sh <image> -c "echo ok"
```
(`MSYS_NO_PATHCONV=1` is only needed on Git Bash/Windows — it stops the
`/bin/sh` argument from being mangled into a Windows path before reaching
Docker.)

## If a fallback is ever needed: use `sleep`, not `httpGet`/`tcpSocket`

The issue proposed investigating `lifecycle.preStop.httpGet` or
`lifecycle.preStop.tcpSocket` as shell-free alternatives. Neither actually
replicates "wait N seconds while the LB/endpoint deregisters" — they require
an actual endpoint or open port to hit, not just a pause, and `tcpSocket` is
[deprecated](https://kubernetes.io/docs/concepts/containers/container-lifecycle-hooks/)
as a lifecycle hook handler.

The correct shell-free equivalent is the native **`sleep` action**
(`PodLifecycleSleepAction`, [KEP-3960](https://github.com/kubernetes/enhancements/tree/master/keps/sig-node/3960-pod-lifecycle-sleep-action)):

| Stage | Kubernetes version |
|---|---|
| Alpha | 1.29 |
| Beta (default on) | 1.30 |
| GA | 1.31 |
| Feature gate removed (locked on) | 1.33 |

This repo pins `k3s_version: "v1.36.1+k3s1"` (`ansible/vars/tool-versions.yml`)
— Kubernetes 1.36, well past GA. No feature gate or version check is needed
if this is ever applied.

The drop-in replacement, if a future image without `/bin/sh` is ever added,
is:

```yaml
- op: add
  path: /spec/template/spec/containers/0/lifecycle
  value:
    preStop:
      sleep:
        seconds: 5
```

Since this is a global patch applied via `target: { kind: Deployment }` with
no name filter (`k8s/base/kustomization.yaml`), switching `exec` → `sleep`
globally is safe for every image checked above (the `sleep` action has no
dependency on a shell existing at all) — there is no need for a *second*,
narrower patch scoped only to affected deployments unless a specific image
needs a different drain duration than the rest.

Before applying that change to any overlay: validate in k3d first
(`just k8s-local-up`, then `kubectl describe pod` after a rollout to confirm
no `FailedPreStopHook` event), per this issue's own acceptance criteria.
