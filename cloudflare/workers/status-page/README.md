# Personal platform status page

Cloudflare Worker that checks the public health endpoints for the ready
services and renders a small HTML status page.

## Local development

```bash
just status-page-init
npx wrangler dev --config cloudflare/workers/status-page/wrangler.toml
```

## Deploy

```bash
just status-page-init
npx wrangler deploy --config cloudflare/workers/status-page/wrangler.toml
```

`just status-page-init` copies `wrangler.toml.example` to `wrangler.toml` only
when the local file is missing. Adjust the routes and service hostnames for the
target domain. Protect the route with Cloudflare Access before exposing it
publicly.
