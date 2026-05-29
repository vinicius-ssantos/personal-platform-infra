# Runbook

## Service readiness

Before changing runtime wiring, check the [service integration matrix](service-integration-matrix.md).

## Start local compose

```bash
just compose-up
```

Compose reads image tags from `.env`. To test a temporary local or branch image,
override the relevant image variable in `.env` instead of editing
`compose/docker-compose.yml`.

## Stop local compose

```bash
just compose-down
```

## Start local Kubernetes

```bash
just k8s-local-up
```

## Sleep all Kubernetes workloads

```bash
just sleep-all
```

## Wake GitHub MCP stack

```bash
just wake-github
```

## Smoke GitHub MCP locally

```bash
just smoke-github
```

The smoke check starts only the `github` Compose profile, calls the configured
health URL, and prints the service status. By default it checks
`http://localhost:8765/healthz`; override it with
`GITHUB_UNIFIED_MCP_HEALTH_URL` if the upstream service exposes a different
health endpoint.

Common failure modes:

- missing `.env`: copy `.env.example` to `.env` and fill local values.
- missing image: confirm `GITHUB_UNIFIED_MCP_IMAGE` points to an available GHCR
  or local image tag.
- port already in use: free local port `8765` or override the Compose port for
  a local-only test.
- invalid token: refresh `GITHUB_TOKEN` or `MCP_BEARER_TOKEN` in `.env`.
- container exited: inspect logs with `just compose-logs`.

Teardown:

```bash
docker compose --env-file .env -f compose/docker-compose.yml --profile github down
```

## Wake VOS stack

```bash
just wake-vos
```

## Logs

```bash
just logs
```
