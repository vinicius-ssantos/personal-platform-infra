# Repo sandbox manifest — personal-platform-infra

This repo's `.sandbox/manifest.yaml` is the first implementation of the
**Repo Sandbox Runner** contract defined in
[ADR 0020](adr/0020-repo-sandbox-runner.md) and governed by
[`docs/repo-sandbox-security.md`](repo-sandbox-security.md).

## Current scope

The declarative manifest, the underlying check scripts, and a local
prototype orchestrator (`scripts/repo_sandbox_run.py`, #221) exist today.
There is **no container isolation yet** — neither the plain scripts nor the
orchestrator call `mcp-code-sandbox`. `run_workspace`, the tool ADR 0020
proposes adding to `mcp-code-sandbox` to provide that isolation, does not
exist yet; wiring it in is explicit follow-up work, not assumed here. The
manifest's shape does not change when that lands; it just gains a real
isolated executor behind the same `commands` it already declares.

## Orchestrator prototype: `repo_sandbox_run.py`

```bash
pip install -r scripts/requirements-sandbox.txt
python scripts/repo_sandbox_run.py --repository . --command-group preflight
python scripts/repo_sandbox_run.py --repository . --command-group test
```

This is the `repo_sandbox.run` MVP from #221: it checks out a repo at a ref
(or accepts a local path directly, as above), reads `.sandbox/manifest.yaml`,
validates the requested profile/command group, runs the declared command
with a timeout (subprocess, not yet container-isolated), and returns a
structured JSON result:

```json
{
  "ok": true,
  "exit_code": 0,
  "logs_uri": "file:///tmp/repo-sandbox-log-xxxx.log",
  "artifacts": [],
  "changed_files": [],
  "duration_seconds": 3.7,
  "error": null
}
```

It refuses any profile other than `safe-test` and any command group not
declared in the manifest, rejects manifest `env` values that look
credential-shaped (`docs/repo-sandbox-security.md` "Secrets policy"),
enforces `timeout_seconds`, and always destroys its temporary workspace —
pass, fail, or timeout. It never pushes, merges, publishes, deploys, or
creates a PR; there is no code path in the script that could.

Tests: `pytest scripts/test_repo_sandbox_run.py -v` — covers a fixture
repository plus two tests that run for real against this repo's own
`preflight`/`test` command groups.

## Profiles

- **`safe-test`** — runs `scripts/sandbox-preflight.sh` then
  `scripts/sandbox-test.sh`. Non-destructive only: shell syntax checks,
  `just --list`, and this repo's existing `scripts/ai-dx-check.sh`. No
  network access (`network: none`), no real secrets (see
  `.sandbox/env.safe.example`).
- **`mock`** — runs only `scripts/sandbox-preflight.sh`, for a fast
  syntax/tooling sanity check without the fuller AI DX check.

Both profiles match this repo's actual risk posture: `personal-platform-infra`
has no application source code to build/test in the usual sense, so its
sandbox-validatable surface is shell syntax, tool availability, and the
repo's own configuration/doc consistency checks — not unit tests against a
language runtime.

## Running it locally

```bash
bash scripts/sandbox-preflight.sh
bash scripts/sandbox-test.sh
```

Both scripts are plain, non-destructive bash — no manifest parser is needed
to run them directly today. `.sandbox/manifest.yaml` exists so that once
#221 implements `repo_sandbox.run`, it has an explicit, versioned contract
to read instead of needing this repo's specifics hardcoded into the runner.

## Env

Copy `.sandbox/env.safe.example` to `.sandbox/env.safe` (gitignored) if you
want a local file to source before running the scripts above. Every value in
the example is a placeholder — neither script currently reads it, since
neither needs real credentials, but it establishes the convention the
manifest's `env` block expects once the runner enforces it.

## What's deliberately not here

- No `integration`/`prod-like` profile — this repo's manifest only declares
  `mock`/`safe-test`, matching the scope ADR 0020 and #220's security policy
  put in scope for the current phase.
- No Docker Compose service startup, no VPS access, no real GitHub PR
  creation from inside a sandboxed run — all explicitly out of scope per
  issue #219.
