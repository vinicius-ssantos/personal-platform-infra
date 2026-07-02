# OpenCode Local MCP Config

`opencode.json` is committed and must not contain real credentials.

Store local MCP credentials in `.env`:

```dotenv
OPENCODE_MCP_GATEWAY_URL=http://localhost:8040/mcp
OPENCODE_MCP_GATEWAY_BEARER_TOKEN=<real bearer token>
OPENCODE_MCP_GATEWAY_PLATFORM_TOKEN=<real platform token>
OPENCODE_MCP_GATEWAY_ENABLED=true
```

Render the ignored local config:

```powershell
just opencode-local-config
```

This creates `opencode.local.json` from `opencode.json` and injects the MCP
headers from `.env` without printing them. Treat `opencode.local.json` as secret
material: do not commit, paste, or attach it to issues.

If the OpenCode runtime in use cannot load an alternate local config directly,
copy the generated MCP block into your user-level OpenCode config or launch
OpenCode through the local workflow that supports `opencode.local.json`.
