# VagaDeck #86 — private production-mode OIDC rehearsal

This self-contained Docker Compose stack uses **Keycloak 26.4.2 profile `prod`** with **PostgreSQL 17**. It is deliberately *local-only*: it is **not** an internet-accessible or externally validated staging deployment. It does not change VagaDeck HTTP quarantine, DRY_RUN, or LinkedIn integrations.

## Security boundaries

- Keycloak runs `start --optimized` with `KC_HTTP_ENABLED=false`; the optimized image enables health/metrics and uses PostgreSQL instead of H2.
- Keycloak HTTPS and management ports are published **exclusively on `127.0.0.1`** (19443 and 19001). PostgreSQL publishes **no host port**, and connects only to an internal Compose network.
- Database has its **own persistent volume**, unrelated to the existing VagaDeck database or original Keycloak development container.
- TLS key material is bind-mounted read-only from a **private file outside Git**.
- Secrets are **split**: `postgres.env` holds only the Postgres bootstrap password; `keycloak.env` holds the matching DB client password, Keycloak admin bootstrap and TLS store password. Keycloak never receives `POSTGRES_PASSWORD`, Postgres never receives the Keycloak admin/TLS secrets.
- All configuration files and the PKCS12 keystore remain under user ACL outside the repo. Scripts do not print passwords. No admin or token endpoint is made reachable over a non-loopback interface.

## Prepare and start locally (PowerShell)

Set a Java JDK in `JAVA_HOME`, then execute:

```powershell
$env:JAVA_HOME = '<path to local JDK>'
& .\vagadeck-oidc\prepare-local.ps1
$root = Join-Path $env:LOCALAPPDATA 'VagaDeck\keycloak-prod-rehearsal'
$env:VAGADECK_OIDC_KEYCLOAK_CONFIG_FILE = Join-Path $root 'keycloak.env'
$env:VAGADECK_OIDC_DB_CONFIG_FILE = Join-Path $root 'postgres.env'
$env:VAGADECK_OIDC_KEYSTORE_FILE = Join-Path $root 'keycloak.p12'
docker compose -f vagadeck-oidc/compose.yaml config --quiet
docker compose -f vagadeck-oidc/compose.yaml up -d --build --wait
```

The preparation script creates strong **new random** credentials and a **30-day local-only self-signed localhost certificate**. It is idempotent. When run on an existing local pilot created before the secrets were split, it migrates the pilot's private `runtime.env` into two restricted env files without rotating live credentials and removes the old combined file. Do not run it on any real, shared or external environment.

Verify with strict certificate validation:

```powershell
$cert = Join-Path $root 'keycloak.crt'
curl.exe --cacert $cert -fsS -o NUL -w 'https=%{http_code} verify=%{ssl_verify_result}' https://localhost:19443/realms/master/.well-known/openid-configuration
curl.exe --cacert $cert -fsS -o NUL -w 'ready=%{http_code} verify=%{ssl_verify_result}' https://localhost:19001/health/ready
docker ps --filter name=vagadeck-oidc-private --format 'table {{.Names}}\t{{.Ports}}'
```

Both endpoints must return HTTP 200 and TLS verify result 0. PostgreSQL must have no published port; the database Compose network must report `Internal=true`. If startup is still migrating a brand-new database, wait for readiness; do not relax TLS.

Stop without losing DB data: `docker compose -f vagadeck-oidc/compose.yaml down`. **Do not** use `down -v` except to intentionally destroy a disposable environment.

### Static configuration tests (offline)

Run `python3 -m unittest discover -s vagadeck-oidc -p 'test_*.py' -v`. The tests call only `docker compose config` with synthetic credentials in a temporary directory; they do **not** launch containers, contact Keycloak or manipulate GitHub secrets. A dedicated GitHub-hosted workflow is gated to same-repository PRs (no forks) and validates the contract without requiring production secrets or a privileged self-hosted runner.

## External staging still blocked

This Compose stack is **not externally reachable by design**. Actual private staging requires a separate, approved architecture: managed DNS and TLS/PKI, VPN or allowlisted ingress with admin protection, a suitable OAuth client (Authorization Code + PKCE for interactive users, not the local test password grant), Keycloak production credentials and MFA, Postgres backup/restore/TLS and secrets injected by an approved secret manager, network controls, logging, rollback and dedicated tenancy/revocation tests.

`env_file` variables can be observed via `docker inspect` by privileged Docker operators. That is acceptable only for the isolated local rehearsal. **Do not copy this secret delivery method into shared/external staging unchanged.**

No external approval is implied by a local HTTPS 200 or the Compose static tests. The requirements and explicit independent HTTP-release gate in [VagaDeck issue #86](https://github.com/vinicius-ssantos/VagaDeck/issues/86) remain fully applicable.
