# Personal platform status page

Cloudflare Worker that checks the public health endpoints for the ready
services and renders a small HTML status page.

## Local development

```bash
npx wrangler dev --config cloudflare/workers/status-page/wrangler.toml
```

## Deploy

```bash
npx wrangler deploy --config cloudflare/workers/status-page/wrangler.toml
```

Copy `wrangler.toml.example` to `wrangler.toml` and adjust the routes and
service hostnames for the target domain. Protect the route with Cloudflare
Access before exposing it publicly.
