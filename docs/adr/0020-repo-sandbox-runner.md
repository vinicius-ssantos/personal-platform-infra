# ADR 0020: Repo Sandbox Runner architecture

**Date:** 2026-06-20
**Status:** Proposed

## Context

`solve-issue` (`scripts/ai-solve-issue.sh`, `docs/ai-solve-issue-workflow.md`)
can already drive a GitHub issue to a reviewable diff and open a PR, with
merge staying a human action. The agent runs against the operator's own local
machine and "runs only safe local validations allowed by the agent" — there
is no enforced, reproducible environment, no declared command contract, and
no isolation between what the agent runs and the operator's real filesystem,
network, and credentials.

This ADR defines a **Repo Sandbox Runner** (a.k.a. **Reproducible Repo
Runtime**): a generic architecture to check out a repository at a given ref,
inject a safe (non-production) environment, run a declared set of commands
inside an isolated container, collect logs/artifacts, and tear the
environment down — conceptually close to Dev Containers, Codespaces, or a CI
ephemeral runner, but exposed through this platform's MCP tooling so
`solve-issue` (and later, other agentic flows) can call it directly.

### Reuse vs new runner decision

Before proposing a new implementation, this ADR evaluates whether the
existing `mcp-code-sandbox` service can serve as the runner's execution
layer. This requirement was added explicitly during issue discussion
(vinicius-ssantos/personal-platform-infra#218) to avoid duplicating
isolation and policy logic across two independently evolving sandboxes — the
same class of drift ADR 0016 in `central-mcp-gateway` (catalog vs. runtime
metadata) documents as expensive to correct after the fact.

**Proven isolation baseline.** `mcp-code-sandbox` was hardened in PR #198
(merged): the server talks to the Docker daemon through `docker-socket-proxy`
(`tecnativa/docker-socket-proxy`, scoped to `CONTAINERS=1`, `VOLUMES=1`,
`POST=1`, every other endpoint `0` — no `IMAGES`, no `EXEC`, no `NETWORKS`,
no `BUILD`) instead of mounting the raw host `docker.sock`. Every
per-execution container additionally runs with `network_mode="none"`
(`server/sandbox.py:285,485`), and the sandbox images themselves are built
from a read-only mounted Dockerfile set with no privilege escalation. This is
real, already-deployed isolation — not a design on paper.

**Execution-contract gap.** `mcp-code-sandbox`'s current API
(`server/tools.py` in that repo) is:

```python
def run_code(self, language, code, *, env=None, output_files=None)
def run_command(self, command, *, env=None, output_files=None)
def run_file(self, language, files: Mapping[str, str], *, env=None, output_files=None)
```

Every one of these spins up a **fresh ephemeral container per call**, and the
file content is supplied **inline** (`code: str` or `files: Mapping[str,
str]`) — there is no repo checkout/tarball ingestion, and no workspace
persists between calls. `npm install` in one `run_command` call and `npm
test` in the next would lose `node_modules`, because each call is a new
container. This is a real, fact-checked limitation, not a guess.

**Decision: extend, don't replace.** Reuse `mcp-code-sandbox`'s isolation
layer (the docker-socket-proxy + `network_mode="none"` + ephemeral-container
model already proven in production) and add the one capability it is
missing: a workspace that persists for the lifetime of one sandbox run,
seeded from a real repo checkout rather than inline file content. Concretely,
this means adding a new tool — `run_workspace` (see "MCP tool API proposal"
below) — to `mcp-code-sandbox` itself, rather than building a second,
independently-evolving sandbox service.

| Option | Verdict |
|---|---|
| 1. Extend `mcp-code-sandbox` with a workspace-aware tool | **Selected.** Isolation is proven; only the execution contract needs to grow. |
| 2. Wrap `mcp-code-sandbox` with a repo-aware orchestration layer that still calls `run_command` per step | Rejected as the primary mechanism — without a persisting container, multi-step lifecycles (install → lint → test) cannot share state, defeating the purpose. Acceptable only as a transitional shim if extending `mcp-code-sandbox` is blocked. |
| 3. Build a separate sandbox runner from scratch | Rejected. No isolation requirement identified here that `docker-socket-proxy` + `network_mode="none"` + a persisting workspace container cannot satisfy. A second isolation mechanism would drift from `mcp-code-sandbox`'s hardening independently — the exact failure mode this section exists to avoid. |

## Goals and non-goals

**Goals:**

- Run any supported repository's declared commands in an isolated,
  reproducible environment, independent of the operator's local machine.
- Make the set of commands and the environment profile explicit and
  versioned in the repository being validated (`.sandbox/manifest.yaml`).
- Produce structured, collectible logs and artifacts per run.
- Integrate with `solve-issue` as a pre-commit/pre-PR validation gate
  (issue #222), without requiring `solve-issue` itself to know how isolation
  is implemented.

**Non-goals (this ADR):**

- Implementing the runner (tracked in #221).
- Adding a GitHub Actions trigger for `solve-issue` (#226).
- Running real deployments or touching VPS/production infrastructure.
- Storing or injecting production secrets into any sandbox run.
- An autonomous low-risk queue (#227).

## Architecture overview

```
repo_sandbox.run (MCP tool)
  |
  v
checkout repo @ ref into a temporary workspace
  |
  v
read .sandbox/manifest.yaml from that checkout
  |
  v
resolve the requested runtime profile (mock | safe-test | integration | prod-like)
  |
  v
call mcp-code-sandbox's run_workspace(files=<tarball>, commands=<manifest commands>, env=<resolved safe env>)
  |
  v
mcp-code-sandbox: one persisting container, network_mode="none" by default,
  docker-socket-proxy-mediated host access, commands run in declared order
  |
  v
collect stdout/stderr per command, exit codes, declared output_files
  |
  v
return a structured result (commands run, pass/fail per step, logs, artifacts) to the caller
```

`repo_sandbox.run` is a **repo-aware orchestrator**, not a second isolation
mechanism. It owns checkout, manifest parsing, env resolution, and result
shaping. `mcp-code-sandbox` owns the only thing that needs root-adjacent
trust: talking to the Docker daemon.

## Repo manifest contract

Each repository opting into sandbox validation declares `.sandbox/manifest.yaml`
at its root:

```yaml
version: "1"

# Declarative only — what runs, not how isolation is implemented.
runtime:
  language: node        # node | python | java | generic — selects the base sandbox image
  version: "20"

profiles:
  safe-test:
    env:
      # Fake/non-production values only. Real secrets are never read from
      # the host or injected here — see threat model.
      DATABASE_URL: "sqlite:///:memory:"
      NODE_ENV: "test"
    commands:
      - name: install
        run: "npm ci"
      - name: lint
        run: "npm run lint"
      - name: test
        run: "npm test -- --ci"
    timeout_seconds: 600
    network: none          # none (default) | none-with-registry-cache
    output_files:
      - "coverage/**"
      - "test-results/**"

  mock:
    env: {}
    commands:
      - name: syntax-check
        run: "node --check src/index.js"
    timeout_seconds: 60
    network: none
```

Rules:

- A manifest with no `safe-test` profile is treated as "this repo has not
  opted into sandbox validation" — `solve-issue` falls back to its current
  unenforced local-validation behavior (#222 decides exactly how this gate
  is surfaced).
- `env` values in the manifest are committed, non-secret defaults. Anything
  resembling a credential (`*_TOKEN`, `*_KEY`, `*_SECRET`) is rejected at
  manifest load time — see Security policy.
- `commands` run in declared order inside one persisting container/workspace.
  A failing command stops the run; later commands do not execute.
- `network` defaults to `none`. Profiles that need package-registry access
  during `install` must opt in explicitly (`none-with-registry-cache`) — see
  Security policy for what that is allowed to mean.

## Runtime profiles

| Profile | Purpose | Network | Secrets |
|---|---|---|---|
| `mock` | Fast syntax/shape check, no real execution | `none` | none |
| `safe-test` | Unit tests, lint, build — the profile `solve-issue` integration (#222) targets first | `none` (registry cache only if declared) | none — fake/in-memory values only |
| `integration` | Cross-service tests against sandboxed dependencies | restricted, allowlisted internal hosts only | scoped, non-production credentials, injected by the runner, never read from the manifest |
| `prod-like` | Staging-equivalent validation | restricted | scoped, non-production credentials only |

Only `mock` and `safe-test` are in scope for the Phase covered by #219–#222.
`integration` and `prod-like` are named here so the manifest schema and
runtime-profile concept do not need a breaking change later, but their
implementation is out of scope for this ADR.

## Threat model

Tracked in detail by issue #220 (`security(sandbox): define repo sandbox
threat model and execution policy`); this ADR commits to the boundaries that
issue must formalize:

- **Untrusted input:** repository content (including the manifest itself) is
  treated as untrusted, the same posture `docs/ai-solve-issue-workflow.md`
  already requires for issue content. A malicious or compromised repo must
  not be able to escape the container, reach the host Docker daemon directly,
  reach other containers, or exfiltrate anything beyond what it's explicitly
  given.
- **No production secrets, ever.** The runner has no code path that can read
  `.env`, `secrets/*.enc.yaml`, or any `platform-secrets` Kubernetes Secret.
  `integration`/`prod-like` profiles use separately-provisioned, scoped,
  non-production credentials — never values lifted from this platform's real
  secret stores.
- **No privileged containers by default.** Every sandbox container runs
  unprivileged, with `network_mode="none"` unless a profile explicitly
  requests otherwise, matching `mcp-code-sandbox`'s existing posture.
- **No broad internet by default.** `none` is the default network mode for
  every profile; any wider access is an explicit, reviewed opt-in per
  profile, not a global toggle.
- **No automatic push/merge.** The sandbox runner only executes and reports —
  it has no credentials for `git push` or `gh pr create`. That stays the
  wrapper's responsibility in `solve-issue`, unchanged from today.

## Security policy

- Manifest loading rejects any `env` key matching a credential-shaped pattern
  (`*_TOKEN`, `*_KEY`, `*_SECRET`, `*_PASSWORD`) with a non-empty literal
  value — these must come from the runner's own scoped injection, never from
  a value committed in the repo being validated.
- `docker-socket-proxy`'s scoping (`CONTAINERS=1`, `VOLUMES=1`, `POST=1`,
  everything else `0`) is the floor, not the ceiling — extending
  `mcp-code-sandbox` for workspace persistence must not widen this scope
  (e.g. no `IMAGES=1` to support arbitrary image pulls from manifests; the
  base image set stays curated, the same way `mcp-sandbox-python:local` /
  `-node:local` / `-java:local` are pre-built today).
- Resource limits (memory, CPU, PIDs, output size) follow the same model
  already configured for `mcp-code-sandbox`
  (`SANDBOX_MEMORY_LIMIT`, `SANDBOX_CPU_PERIOD`/`SANDBOX_CPU_QUOTA`,
  `SANDBOX_PIDS_LIMIT`, `SANDBOX_MAX_OUTPUT_BYTES`), extended with a
  per-manifest `timeout_seconds` cap enforced by the orchestrator regardless
  of what the manifest requests.
- All sandbox runs are audited: repo, ref, profile, commands, exit codes,
  duration, triggering actor. This mirrors the gateway's existing
  `mcp_gateway_audit` event pattern rather than inventing a new log shape.

## MCP tool API proposal

```
repo_sandbox.run
  inputs:
    repo: string            # owner/repo
    ref: string              # branch, tag, or commit SHA
    profile: string           # must match a profile declared in .sandbox/manifest.yaml
  output:
    status: "passed" | "failed" | "manifest_missing" | "profile_missing" | "timeout"
    steps: [{ name, command, exit_code, duration_seconds }]
    logs_ref: string          # pointer to collected stdout/stderr
    artifacts: [string]       # collected output_files, if any
```

`repo_sandbox.run` calls a new tool added to `mcp-code-sandbox`:

```
run_workspace
  inputs:
    files: <tarball or directory mapping>   # repo checkout contents
    commands: [{ name, run }]                # executed in order, one persisting container
    env: dict[str, str]                       # pre-validated, non-secret-shaped only
    network: "none" | "none-with-registry-cache"
    timeout_seconds: int
    output_files: [string]
  output:
    steps: [{ name, exit_code, stdout, stderr, duration_seconds }]
    artifacts: dict[str, bytes]
```

`run_workspace` is additive to `mcp-code-sandbox`'s existing `run_code` /
`run_command` / `run_file` — it does not replace them, since those remain
the right shape for the platform's other use case (ad hoc snippet execution
unrelated to repo validation).

## Phased rollout plan

1. **#218 (this ADR)** — architecture decision: reuse, don't duplicate.
2. **#220** — formalize the threat model and execution policy this ADR
   commits to above.
3. **#219** — implement `.sandbox/manifest.yaml` parsing and the `safe-test`
   profile only (`mock` and the manifest schema for `integration`/`prod-like`
   may be stubbed).
4. **#221** — implement `repo_sandbox.run` as an MVP: the orchestration steps
   in "Architecture overview", calling `mcp-code-sandbox`'s new
   `run_workspace` tool (or, if that extension turns out to be blocked, the
   transitional per-step `run_command` shim noted in the reuse-decision
   table — but only as an explicitly-justified fallback, not silently).
5. **#222** — wire `repo_sandbox.run` into `solve-issue` as a pre-commit/
   pre-PR validation gate for repos that declare a `safe-test` profile.
6. **#226 (later phase, not this ADR)** — controlled GitHub trigger
   (`workflow_dispatch`, label, or comment) for `solve-issue`, only after the
   sandbox gate from #222 exists to validate what the trigger produces.
7. **#227 (later phase, not this ADR)** — autonomous low-risk issue queue,
   only after #226 has been used under manual triggering first.

## Relationship with `solve-issue`

`solve-issue` does not need to know how isolation is implemented — it calls
`repo_sandbox.run` with a profile name and acts on the structured result
(#222 defines exactly where in the wrapper this call happens and how a
`failed`/`timeout` result affects whether a PR is opened). This keeps the
risk-scoring work in #223 and the PR-body work in #225 decoupled from sandbox
implementation details: those issues only need to know "validation passed,
failed, or wasn't available," not which container ran it.

## Why merge stays manual

Nothing in this ADR changes who can merge. `repo_sandbox.run` reports
pass/fail; it does not grant `solve-issue` (or any future GitHub trigger)
the ability to merge. This matches the platform's existing pattern — the
agent works in a branch/PR, but merge governance stays a human action, the
same model documented in ADR 0019 for the broader AI subagent workflow and
unchanged by `docs/ai-solve-issue-workflow.md` today.

## Consequences

- **Positive:** no second isolation mechanism to keep in sync with
  `mcp-code-sandbox`'s hardening — one Docker-facing trust boundary for the
  whole platform.
- **Positive:** repo authors get an explicit, versioned, reviewable contract
  (`.sandbox/manifest.yaml`) for what "safe to validate automatically" means
  for their repo, instead of an implicit "whatever the agent's local
  environment allows."
- **Positive:** `solve-issue` gains a real pre-PR validation gate without
  absorbing sandbox complexity itself.
- **Negative:** `mcp-code-sandbox` gains a second, more complex execution
  mode (`run_workspace`) alongside its existing snippet-execution tools —
  more surface to maintain and to keep aligned with the `docker-socket-proxy`
  scoping policy.
- **Negative:** repos that don't author a `.sandbox/manifest.yaml` get no
  validation gate — adoption is opt-in per repo, not automatic.
- **Negative:** `integration`/`prod-like` profiles introduce scoped
  non-production credentials into the runner's environment, which is new
  attack surface that `mock`/`safe-test` do not have; their implementation
  (deferred past this ADR) needs its own security review before use.

## References

- PR #198 (`personal-platform-infra`) — `mcp-code-sandbox` Docker access
  hardening: `docker-socket-proxy`, `network_mode="none"`.
- `mcp-code-sandbox` `server/tools.py` / `server/sandbox.py` — current
  `run_code`/`run_command`/`run_file` contract and isolation implementation.
- Issue #218 and its comments — reuse-vs-new requirement and the
  `run_workspace` API gap analysis this ADR is built on.
- ADR 0016 (`central-mcp-gateway`) — upstream-declared tool contract; cited
  here as the precedent for why duplicated/divergent metadata or isolation
  mechanisms are expensive to reconcile after the fact.
- ADR 0019 (this repo) — AI subagent workflow; merge-stays-manual precedent.
- Dev Containers (`devcontainer.json`) — reference for a versioned,
  declarative environment manifest; this ADR's `.sandbox/manifest.yaml` is
  narrower and execution-focused, not a full dev-environment spec.
