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

## Frontend rule

Frontends should be hosted outside the VPS, preferably using Cloudflare Pages, Vercel, or Netlify.
