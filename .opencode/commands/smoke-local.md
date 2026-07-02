---
description: Run smoke tests against the local Compose stack
---

Run smoke tests for the local Compose stack.

Detect the shell: use `smoke-all-sh` in bash/WSL/CI, `smoke-all` in PowerShell.

Parse output for `[OK]` / `[FAIL]` per service. If any failure: show the service URL, last curl response, and suggest `just compose-logs-profile <service>` for investigation.

Services checked: github-mcp:8765, deploy-mcp:8001, social:8080, gateway:8040, github-bff:8010, vos-mcp:8020, vos-bff:8030.
