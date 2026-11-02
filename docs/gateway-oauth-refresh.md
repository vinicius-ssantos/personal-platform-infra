# OAuth refresh rollout via Docker Compose (Gateway #408)

The main Gateway Compose service passes the following **opt-in** variables
into all three slots (legacy, blue, green) through the shared service anchor:

| Variable | Default | Purpose |
| --- | --- | --- |
| `GATEWAY_OAUTH_REFRESH_ENABLED` | `false` | Enables rotating refresh-token OAuth (opt-in) |
| `GATEWAY_OAUTH_REFRESH_TOKEN_TTL_SECONDS` | `604800` | Seven-day idle expiry |
| `GATEWAY_OAUTH_REFRESH_FAMILY_TTL_SECONDS` | `2592000` | 30-day absolute family expiry |

Do not enable until [central-mcp-gateway #409](https://github.com/vinicius-ssantos/central-mcp-gateway/pull/409)
has passed security review and the selected image contains the fix.

1. Keep `GATEWAY_REDIS_URL` configured to the **shared, protected Redis**
   instance; enabling refresh without Redis fails closed.
2. Set the refresh flag only in the canary slot's deployment environment
   and use a reviewed new Gateway image. Do **not** update every slot at
   once; the stable fallback must remain usable.
3. Confirm `/.well-known/oauth-authorization-server` publishes
   `offline_access` and the `refresh_token` grant. Validate renewal,
   replay denial, family revocation, and restart continuity using disposable
   OAuth credentials only.
4. Promote via the existing blue/green procedure after health, audit and
   rollback gates have passed. Preserve the previous healthy slot.
5. The ChatGPT user must re-authorize the canonical connection with
   `workspace:read offline_access`. Do not remove the older connections
   until the new connection can run the **static** `workspace.list` tool
   and produce a sanitized Gateway audit record.

## Português

O suporte a refresh é **desligado por padrão**. Após o merge e a revisão,
habilite primeiro em um canary com Redis compartilhado, confira os
metadados OAuth e execute testes com credenciais descartáveis. Não mude
os tokens existentes nem conceda `workspace:write`/`workspace:execute`
para resolver um bloqueio de leitura. Quando a nova versão estiver ativa,
o usuário precisa aprovar uma **nova autorização OAuth no ChatGPT**.

Runbook principal: `central-mcp-gateway/docs/oauth-refresh-chatgpt.md`.
