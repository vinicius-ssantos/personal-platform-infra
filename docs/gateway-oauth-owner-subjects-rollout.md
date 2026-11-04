# OAuth owner-subject forwarding — opt-in rollout

**Context:** The Gateway v0.46.3 logs a deprecation warning because the
Compose configuration forwards `GATEWAY_OWNER_CLIENT_IDS`. An OAuth client ID
does **not** identify an authenticated owner and must never elevate its token.
The operator's existing `GATEWAY_OWNER_SUBJECTS` setting was not forwarded
by Compose. This change makes forwarding possible, but **disabled by default**.

## Contract

- `GATEWAY_OWNER_SUBJECTS_FORWARD_ENABLED=false` (default): the entrypoint
  **unsets** `GATEWAY_OWNER_SUBJECTS` before invoking the Gateway, even when
  a local `.env` contains a value. This preserves current OAuth privileges.
- `GATEWAY_OWNER_SUBJECTS_FORWARD_ENABLED=true`: the entrypoint requires a
  non-empty `GATEWAY_OWNER_SUBJECTS` and forwards it unchanged to the Gateway.
  An empty value or invalid toggle fails **before** the app starts.
- Compose escapes shell references as `$$` so variables are interpreted in
  the container, not interpolated by Docker Compose.
- The feature does **not** alter `GATEWAY_OAUTH_DEFAULT_SCOPES`,
  `GATEWAY_OAUTH_ALLOWED_SCOPES`, `offline_access`, Redis, refresh-token
  families or static MCP schemas.
- `GATEWAY_OWNER_CLIENT_IDS` remains for the existing legacy path only.
  A follow-up migration can remove this deprecated setting after verifying
  non-OAuth clients; it grants **no OAuth owner elevation**.

## Security impact

When enabled, `GATEWAY_OWNER_SUBJECTS` can authorize **owner-only**
operations for a matching authenticated OAuth subject. This is a real
privilege change, not a cosmetic warning fix. Review the exact owner subject
and all enabled owner-write/destructive flags with the operator first.
No one should enable the flag by merely assuming that the OAuth client
ID (for example `chatgpt`) identifies an owner.

Other controls remain independent: token scope, tool allowlist, tenant
policy, idempotency, Java workspace trust and task policy. For the
`mcp-dev-workspace` stack, never make the aggregate `dev` workspace
writable to test authorization.

## Rollout gates

1. Merge only after CI, synthetic entrypoint tests, Compose rendering and
   code/security review; do not modify any live `.env` in the PR.
2. Confirm the canary is v0.46.3 or newer, not the rollback v0.45.0 slot.
   The active slot must remain healthy and routing must not change during
   the initial test.
3. Using approved operator identity, verify the expected OAuth **subject**,
   the requested scopes and the owner permissions without printing bearer
   values, refresh tokens, password hashes or complete environment maps.
4. Enable forwarding **only on the non-routed canary**, with a narrowly
   reviewed subject list. Check read-only and owner-negative cases before
   promoting. Do not enable broad write or destructive operations just to
   make a smoke test pass.
5. Keep the other healthy slot and an exact configuration rollback. Any
   changed OAuth grants require user consent; never disconnect the sole
   functioning ChatGPT connection.
6. Test the newly advertised static tool schema in a fresh ChatGPT
   conversation. The existing conversation's tool schema may remain cached.

## Rollback

Set `GATEWAY_OWNER_SUBJECTS_FORWARD_ENABLED=false` and recreate only the
candidate slot. The entrypoint will unset `GATEWAY_OWNER_SUBJECTS` again.
If it is active and unhealthy, switch routing to the known-good slot first.
Do not clear Redis, rotate unrelated secrets or revoke active OAuth tokens.

## Evidence

`tests/test_compose_oauth_owner_subjects.py` exercises forwarding, no
forwarding, missing subject, malformed flag, interpolation escaping and
default off using synthetic values. Existing OAuth scope split tests also
run with the new flag explicitly disabled. No real OAuth credentials are
read by either suite.
