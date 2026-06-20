# Repo Sandbox Runner — threat model and execution policy

This document formalizes the security boundaries that
[ADR 0020](adr/0020-repo-sandbox-runner.md) commits to for the **Repo Sandbox
Runner** (`repo_sandbox.run`, built on `mcp-code-sandbox`'s `run_workspace`
extension). It is the policy reference for every later sandbox issue:
`.sandbox/manifest.yaml` implementation (#219), `repo_sandbox.run` MVP
(#221), `solve-issue` integration (#222), and anything that touches the
runner after that.

If a future change to the runner conflicts with this document, the document
wins — update it explicitly and intentionally, don't let implementation
drift past it silently. That silent-drift failure mode is exactly what
ADR 0016 in `central-mcp-gateway` (catalog vs. runtime metadata) documents as
expensive to correct after the fact, and what ADR 0020's reuse-vs-new
decision was written to avoid repeating for isolation mechanisms.

## Trusted vs untrusted inputs

| Input | Trust level | Why |
|---|---|---|
| Repository content at the requested ref (code, `.sandbox/manifest.yaml`, scripts) | **Untrusted** | The runner may be asked to validate any repo, including ones whose content an attacker controls (a malicious PR, a compromised dependency, a forked repo). |
| Issue body, PR description, PR/issue comment text | **Untrusted** | `docs/ai-solve-issue-workflow.md` already requires `solve-issue` to treat issue content as untrusted; the sandbox runner inherits that posture. Text in these fields can attempt prompt injection against the agent that decides *what* to run, not just *that* something runs. |
| `.sandbox/manifest.yaml` declared commands and env keys | **Untrusted, but constrained** | The manifest lives in the (untrusted) repo, so its *content* is untrusted — but its *shape* is constrained by this policy (declarative commands only, no credential-shaped env values accepted, see below) so that even a fully adversarial manifest cannot ask for more than the sandbox is willing to grant. |
| Runtime profile name (`mock`, `safe-test`, `integration`, `prod-like`) | **Trusted** | Selected by the caller (`solve-issue` or a human), not read from repo content. |
| Injected `env` for `integration`/`prod-like` profiles | **Trusted** | Provisioned by the runner itself from a scoped, non-production credential store — never read from the manifest or any repo file. |

**Prompt injection risk.** Issue bodies, PR descriptions, and comments are a
documented prompt-injection vector against any agent that reads them
(`docs/ai-solve-issue-workflow.md`'s own guardrails exist because of this).
The sandbox runner's job is to make sure that even a fully successful prompt
injection — one that convinces `solve-issue`'s agent to ask the sandbox to
run something malicious — cannot turn into a host compromise, secret leak, or
unauthorized push. The container/network/filesystem boundaries below are the
backstop for when the upstream prompt-injection defenses fail, not a
redundant second line that's safe to skip.

## Allowed profiles

| Profile | Purpose | In scope now | Network | Secrets |
|---|---|---|---|---|
| `mock` | Fast syntax/shape check, no real execution | #219–#222 | `none` | none |
| `safe-test` | Unit tests, lint, build — the profile `solve-issue` integration (#222) targets first | #219–#222 | `none` (registry cache only if explicitly declared) | none — fake/in-memory values only |
| `integration` | Cross-service tests against sandboxed dependencies | named only, not implemented | restricted, allowlisted internal hosts only | scoped, non-production credentials, runner-injected |
| `prod-like` | Staging-equivalent validation | named only, not implemented | restricted | scoped, non-production credentials only |

Only `mock` and `safe-test` are implemented in the phase covered by
#219–#222. `integration` and `prod-like` are reserved in the schema so it
doesn't need a breaking change later, but **using either of them requires a
separate security review before implementation** — they introduce
non-production credentials into the runner's environment, which `mock` and
`safe-test` never have.

## Forbidden defaults

These are defaults, not configurable-away footguns. A profile cannot opt out
of them without a new ADR/policy change reviewed the same way this document
was:

- **No production secrets.** The runner has no code path that reads `.env`,
  `secrets/*.enc.yaml`, or any `platform-secrets` Kubernetes Secret.
- **No privileged containers.** Every sandbox container runs unprivileged.
- **No host Docker socket mount.** The runner talks to Docker exclusively
  through `docker-socket-proxy`, scoped to `CONTAINERS=1`, `VOLUMES=1`,
  `POST=1` — every other endpoint (`IMAGES`, `EXEC`, `NETWORKS`, `BUILD`,
  etc.) is `0`. This is the floor `mcp-code-sandbox` already enforces
  (PR #198); extending it for workspace persistence must not widen this
  scope.
- **No broad internet access.** `network: none` is the default for every
  profile. Wider access is an explicit, reviewed, per-profile opt-in (see
  Network policy), never a global toggle.
- **No write, push, or merge from the sandbox.** The sandbox container has
  no git credentials and no GitHub token. It executes commands and reports
  results; it cannot push a branch, open a PR, or merge anything. That stays
  exclusively `solve-issue`'s wrapper responsibility, unchanged by this
  runner's existence.

## Network policy

- Default: **deny** (`network: none` in the manifest). A sandbox run with no
  explicit network declaration gets no network access at all, matching
  `mcp-code-sandbox`'s existing per-execution container posture.
  - **Why this is enforceable, not just configured:** `docker-socket-proxy`'s
    `NETWORKS=0` scoping means the workspace container cannot create or
    attach to a Docker network it wasn't started with, regardless of what a
    malicious manifest or compromised command inside the container asks for
    — the daemon-facing credential the runner holds simply has no capability
    to grant it. A manifest claiming `network: none-with-registry-cache`
    cannot self-upgrade its own access at runtime.
  - Manifest authors do not get to decide enforcement; this policy and the
    runner's pre-validated allowlist do.
- The only declared exception: `network: none-with-registry-cache`, for
  `safe-test`'s `install` step needing a package registry (npm, PyPI, Maven
  Central, etc.). This is an **allowlisted egress to known package
  registries only** — not general internet access — resolved by the runner
  from a fixed allowlist, never from a host or URL supplied by the manifest.
- `integration`/`prod-like` profiles (not implemented yet) get a separate,
  explicit allowlist of internal hosts when they're built — general internet
  access is never in scope for any profile.

## Filesystem policy

- The repo is checked out into a fresh **temporary directory** created for
  that run only, never into a path under the operator's home directory or
  any other pre-existing developer workspace.
- **No bind mount of the developer's home directory**, or any host path
  outside the run's own temporary checkout, into the sandbox container.
- The sandbox container's filesystem is isolated per run — no two runs share
  a container or a writable layer.
- Only the artifacts a manifest's profile explicitly declares under
  `output_files` are collected back out of the container. Nothing else in
  the container's filesystem is read by the runner after the run completes.
- The temporary checkout (and the container, via `mcp-code-sandbox`'s
  existing per-execution lifecycle) is torn down after the run, whether it
  passed, failed, or timed out.

## Secrets policy

- Manifest loading **rejects** any `env` key whose name matches a
  credential-shaped pattern (`*_TOKEN`, `*_KEY`, `*_SECRET`, `*_PASSWORD`)
  if it carries a non-empty literal value in the manifest. A manifest cannot
  smuggle a real-looking credential into a `safe-test` run by declaring it
  inline.
- `safe-test` and `mock` profiles never receive real credentials of any
  kind — only fake/in-memory values the manifest itself declares (e.g.
  `DATABASE_URL: "sqlite:///:memory:"`).
- `integration`/`prod-like` profiles (when implemented) receive credentials
  exclusively from the runner's own scoped, non-production credential
  injection — never read from the manifest, never the platform's real
  `platform-secrets`/SOPS-encrypted values.

## Resource policy

Sandbox containers inherit `mcp-code-sandbox`'s existing resource controls
(`SANDBOX_MEMORY_LIMIT`, `SANDBOX_CPU_PERIOD`/`SANDBOX_CPU_QUOTA`,
`SANDBOX_PIDS_LIMIT`, `SANDBOX_MAX_OUTPUT_BYTES`), extended with:

- A per-manifest `timeout_seconds` cap, enforced by the orchestrator
  (`repo_sandbox.run`) regardless of what the manifest requests — a manifest
  cannot declare an unbounded or excessive timeout to defeat this.
- Disk usage bounded by the temporary checkout's own size plus whatever the
  declared commands write inside the container; the per-run temporary
  directory is removed on teardown so nothing accumulates across runs.

## Log policy

- Logs and audit records are **redacted** for any value matching a
  credential-shaped pattern before being persisted or returned to a caller —
  the same shape-based check used for manifest `env` rejection applies to
  command stdout/stderr capture.
- Every sandbox run is audited with: repo, ref, profile, commands run, exit
  codes, duration, and triggering actor — mirroring `central-mcp-gateway`'s
  existing `mcp_gateway_audit` event pattern rather than inventing a new log
  shape for this runner.
- Audit records are retained independently of whether the run passed,
  failed, or timed out — a failed or suspicious run is exactly the case
  where the audit trail matters most.

## Required human checkpoints before external side effects

The sandbox runner itself has no external side effects to gate — it cannot
push, open a PR, merge, or call any production API. The human checkpoint
this policy requires sits one layer up, in how a *caller* (`solve-issue`,
#222) is allowed to use the runner's result:

- A `repo_sandbox.run` result of `passed` is a signal `solve-issue` can use
  to proceed toward its own existing PR-creation flow — it is not, by
  itself, authorization to skip any guardrail `solve-issue` already enforces
  (risk classification from #223, the high-risk opt-in gate, the forbidden-file
  diff check).
- A `failed` or `timeout` result must block `solve-issue` from creating a PR
  for that run, the same way a missing diff already does today — #222 defines
  exactly where in the wrapper this check happens.
- Merge approval remains a human action regardless of sandbox result, per
  ADR 0019's and ADR 0020's existing "merge stays manual" position. Nothing
  in this policy changes that.

## References

- [ADR 0020](adr/0020-repo-sandbox-runner.md) — architecture this policy
  formalizes; see its "Threat model" and "Security policy" sections for the
  commitments this document expands on.
- PR #198 — `mcp-code-sandbox` Docker access hardening
  (`docker-socket-proxy`, `network_mode="none"`) that this policy treats as
  the enforced floor, not just a design intent.
- `docs/ai-solve-issue-workflow.md` — existing "treat issue content as
  untrusted input" guardrail this policy extends to the sandbox runner.
- Issue #218 and its comments — the reuse-vs-new decision and
  `mcp-code-sandbox` API gap analysis this policy assumes as context.
