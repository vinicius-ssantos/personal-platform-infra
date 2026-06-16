# smoke-local

Run the full smoke test suite against the local Compose stack.

## What this does

Executes `just smoke-all` (PowerShell) or `just smoke-all-sh` (bash/CI) and reports each service result.

## Steps

1. Detect shell: use `smoke-all-sh` in bash/WSL, `smoke-all` in PowerShell
2. Run the appropriate just recipe
3. Parse output for `[OK]` / `[FAIL]` per service
4. If any failure: show the service URL and last curl response
5. Suggest `just compose-logs-profile <service>` for failed services

## Services checked

| Service | Port | Health path |
|---|---|---|
| github-unified-mcp | 8765 | `/healthz` |
| deploy-orchestrator-mcp | 8001 | `/healthz` |
| mcp-social | 8080 | `/health` |
| central-mcp-gateway | 8040 | `/healthz` |
| github-unified-mcp-bff | 8010 | `/healthz` |
| vos-studio-mcp | 8020 | `/health` |
| vos-studio-bff | 8030 | `/healthz` |

## Usage

```
/smoke-local
```
