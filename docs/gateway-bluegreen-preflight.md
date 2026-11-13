# M4 — Safe Gateway blue/green preflight

**Status (2026-11-13):** read-only diagnostics, not authorization to deploy, change OAuth or run writes on real repositories.

## Context

Release `v0.48.0` is published; the observed deployment remains **active blue v0.46.3**, **standby green v0.45.0**. The local `.env` still selects these tags, and the Compose file has uncommitted changes from separate infrastructure work. Running the old promotion controller without reviewing this state may deploy the wrong image or apply unrelated changes.

## Read-only command

From the infrastructure repo root in PowerShell 5.1+:

```powershell
.\scripts\gateway-bluegreen-preflight.ps1 -Target green -CandidateTag v0.48.0 -ExpectedActive blue
```

May be run from an isolated checkout using `-InfraRoot` pointing to the actual installation. It only checks the existence of `.env` (never prints its contents), the active slot state file, loopback `/readyz` on both slots, currently resolved Compose images in memory, absence of unreviewed local changes to the deployment Compose and promotion controller, and a **process-only** interpolation of the candidate target image. The environment override is restored immediately. It also refuses candidate changes to the active slot.

Returns `PREFLIGHT=PASS_READ_ONLY` exit 0 or `PREFLIGHT=BLOCKED` exit 2 with a controlled diagnostic reason. **A successful preflight is not a deploy authorization** and does not prove that the candidate image exists, that ChatGPT refreshed its tools or that a human approved an operation.

### Expected result for the observed 2026-11-10 state

The modified Compose file should produce `DEPLOYMENT_CONFIG_HAS_UNREVIEWED_LOCAL_CHANGES`. Do not discard or revert unrelated work to make it pass.

## Optional remote manifest digest verification

Use `-ExpectedManifestDigest` to require the candidate's OCI manifest index digest to equal a **separately reviewed SHA-256 digest** from GHCR. The script uses `docker buildx imagetools inspect` (metadata only), without pulling image layers, and fails closed on unavailable, malformed or mismatched registry data. The flag is optional; without it the output reports `CANDIDATE_MANIFEST_CHECK=NOT_REQUESTED`. When supplied and validated, it reports `CANDIDATE_MANIFEST_CHECK=VERIFIED`.

```powershell
.\scripts\gateway-bluegreen-preflight.ps1 -Target green -CandidateTag v0.48.0 -ExpectedActive blue `
  -ExpectedManifestDigest sha256:833bd971971bc0024a2b41859c9f4e7d229f3ad6698d049eb262702edad2eacb
```

This digest is the OCI **index** digest observed for v0.48.0 on 13 Nov 2026. Validate it independently before each deployment. Matching a registry digest does **not** prove source provenance, signature verification, or that a tag cannot move between inspection and deployment. For deployment, pin the reviewed image by digest through a separately approved configuration change; the preflight does not do so. Existing dirty-Compose checks run before registry access.

## Separate operator-controlled deployment

Once configuration is reviewed and the preflight passes, independently verify the GHCR image tag/digest, CI, security and exact Compose change. Persistently configure the **inactive green** image to the reviewed v0.48.0 digest via a reviewed configuration update; the preflight never modifies `.env`. Only then should an authorized operator consider the existing `gateway-bluegreen-promote.ps1 -Target green`, which starts the target, waits for readiness and atomically changes the route state. Keep blue v0.46.3 alive for rollback and verify both slots plus OAuth, catalog contract and request correlation.

A live ChatGPT plugin refresh requires a **separate authorized UI action** followed by a new conversation. No machine retry token can substitute for verifiable human consent (Gateway #415), and no dynamic workspace invocation bypass is allowed.

## M4 exit gates

- [ ] Reviewed Compose and pinned release image digest
- [ ] Passing read-only preflight with no conflicting local changes
- [ ] Controlled promotion and safe rollback readiness
- [ ] Server catalog verified without leaking secrets; ChatGPT refresh separately approved
- [ ] Disposable TRUSTED write E2E after independent human approval
- [ ] M4 #84/#85/#87 security, audit, rotation and regressions accepted

Sources: [Docker Compose environment precedence](https://docs.docker.com/compose/how-tos/environment-variables/envvars-precedence/), [Compose up](https://docs.docker.com/reference/cli/docker/compose/up), [OpenAI custom MCP servers](https://help.openai.com/en/articles/12584461-connecting-custom-mcp-servers-in-chatgpt).
