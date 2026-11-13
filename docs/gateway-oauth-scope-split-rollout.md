# Opt-in OAuth scope split for Gateway v0.46+

Addresses [infra #313](https://github.com/vinicius-ssantos/personal-platform-infra/issues/313) and [Gateway #411](https://github.com/vinicius-ssantos/central-mcp-gateway/issues/411).

The Gateway's OAuth allowed scopes must be separated from grants issued when a
client omits `scope`. This is a **deployment preparation**, not a production
change, and it does not alter the existing ChatGPT OAuth connection.

## Compatibility contract

- `GATEWAY_OAUTH_SCOPE_SPLIT_ENABLED=false` (default): preserve the legacy
  behavior. The Compose startup script **unsets**
  `GATEWAY_OAUTH_ALLOWED_SCOPES` before starting Gateway. With the workspace
  owner-tool opt-in enabled, the legacy startup script still extends
  `GATEWAY_OAUTH_DEFAULT_SCOPES` with read, write and execute.
- `GATEWAY_OAUTH_SCOPE_SPLIT_ENABLED=true`: require an **explicit, non-empty**
  `GATEWAY_OAUTH_ALLOWED_SCOPES`, containing `workspace:read`. Read is
  included in defaults; write/execute are forbidden in defaults. If workspace
  owner tools are enabled, both `workspace:write` and
  `workspace:execute` must be explicitly present in allowed scopes, without
  being added automatically. Invalid configurations fail **before** the
  Gateway starts.
- In split mode, the Compose entrypoint also rejects a default scope absent from
  `GATEWAY_OAUTH_ALLOWED_SCOPES` **before** launching Gateway. This includes
  non-workspace namespaces (for example `github:read`) and prevents invalid
  combinations from reaching the runtime. It does not add privileges or adjust
  existing grants. The allowed list must contain every existing default plus
  any additional scopes the operator intends clients to request.
- Gateway v0.46+ independently validates `DEFAULT ⊆ ALLOWED`. The split flag
  must **not** be enabled on an older v0.45.x image: older versions do not
  implement allowed-scope separation.
- `offline_access` remains an explicitly requested OAuth grant and still
  requires the separate refresh flag and Redis; never add it to defaults.

## Reviewed example (not an active configuration)

Use these only in a *non-routed* candidate once the reviewed Gateway v0.46+
image and rollback slot are available. Include other namespaces that the
operator actually needs.

```dotenv
GATEWAY_OAUTH_SCOPE_SPLIT_ENABLED=true
GATEWAY_OAUTH_DEFAULT_SCOPES=gateway:read github:read workspace:read
GATEWAY_OAUTH_ALLOWED_SCOPES=gateway:read github:read github:write workspace:read workspace:write workspace:execute
GATEWAY_WORKSPACE_OWNER_TOOLS_ENABLED=true
```

The settings above preserve **requestable** write/execute capability for the
owner. They do not grant those capabilities implicitly to an OAuth client
that omits `scope`. This setting **also changes the scopes of the legacy
owner/public bearer fallback**; review all integrations before enabling it.
Existing OAuth access tokens keep their original grants until expiry/revocation.
Previously issued refresh grants are revalidated against the new allowed list.

## Deployment gates

1. Verify CI and code review of the Compose/entrypoint and its synthetic
   non-network tests; test the actual image that will be deployed.
2. Keep the old live Gateway and its Redis/tokens unchanged. Verify the
   new candidate supports `GATEWAY_OAUTH_ALLOWED_SCOPES`.
3. Prepare a non-routed canary using the **approved** authenticated OAuth
   procedure. Validate explicit vs omitted `scope`, metadata, owner
   policy, refresh rotation across slots, and denial of scope escalation.
   Do not use live bearer values in commands, tickets or logs.
4. Ensure `mcp-dev-workspace`'s aggregate `dev` is `READ_ONLY` and
   each explicitly authorized repository has its own `TRUSTED` workspace.
   OAuth policy alone does not provide local filesystem isolation.
5. Before promotion: run `docker compose --profile gateway --profile workspace
   -f compose/docker-compose.yml config --quiet` in the reviewed
   environment, and verify readiness/audit without exposing full environment.
6. Promote only after approved canary and rollback plan. The ChatGPT user
   must authorize any deliberately changed scope grants themselves; never
   disconnect the only functioning link before its replacement works.

## Rollback

Disable the split flag **on a compatible reviewed image** or revert to
the previous known-good image/config using the established blue/green plan.
Restore the operator-approved default scopes and confirm metadata,
`gateway.status` and read-only workspace invocation. Do not delete Redis
state, rotate unrelated upstream secrets or revoke old OAuth connections as
part of a generic configuration rollback.

## CI evidence

`tests/test_compose_oauth_scope_split.py` replaces the final gateway
process launch with a dummy print command in the source Compose shell and
tests both modes with fabricated scopes. It never starts Gateway, never
sends a token and never reaches the private workspace.
