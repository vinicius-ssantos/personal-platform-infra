# Architecture

## Local

```txt
Windows
  -> WSL2 Ubuntu
    -> Docker Compose or k3d
      -> MCPs / BFFs / Redis when needed
    -> Cloudflare Tunnel when exposed externally
```

## VPS

```txt
Internet
  -> Cloudflare DNS
    -> VPS Ubuntu
      -> k3s
        -> Traefik
          -> MCPs / BFFs with replicas=0 by default
```

## Runtime rule

The local environment may run multiple services together. The VPS should stay lean and use manual wake/sleep or future HTTP scale-to-zero.

## Kubernetes configuration boundaries

The source of truth for this platform's Kubernetes runtime is this repository.
Application repositories publish images and document runtime contracts; this
repository owns the Compose, k3d/k3s, overlay, secret and routing wiring. See
[ADR 0017](adr/0017-kubernetes-ownership-in-infra-repo.md).

- `k8s/base` describes service shape: names, labels, images, ports, probes,
  stable internal service URLs and generic resources.
- `k8s/overlays/local` describes local/k3d behavior: local development modes,
  localhost frontend origins, local smoke replicas and non-production
  placeholder secrets.
- `k8s/overlays/vps` describes VPS behavior: production modes, secure cookie
  settings, real-domain placeholders and sleep-by-default workloads.

Sensitive runtime values are referenced from Kubernetes `Secret` objects. Base
deployments must not contain final token values. Local/k3d can create
`platform-secrets` from `.env` with `just k3d-secrets`; VPS secrets should come
from the encrypted secrets flow before workloads are woken.

## Frontend rule

Frontends should be hosted outside the VPS, preferably using Cloudflare Pages, Vercel, or Netlify.
