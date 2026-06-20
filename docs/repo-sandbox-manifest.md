# Repo sandbox manifest — personal-platform-infra

This repo's `.sandbox/manifest.yaml` is the first implementation of the
**Repo Sandbox Runner** contract defined in
[ADR 0020](adr/0020-repo-sandbox-runner.md) and governed by
[`docs/repo-sandbox-security.md`](repo-sandbox-security.md).

## Current scope

Only the **declarative manifest and the underlying check scripts** exist
today. There is no sandbox isolation yet — `scripts/sandbox-preflight.sh`
and `scripts/sandbox-test.sh` run directly on whatever machine invokes them,
the same as any other script in `scripts/`. Implementing the actual isolated
execution (`repo_sandbox.run` calling `mcp-code-sandbox`'s `run_workspace`)
is tracked separately in #221 — see ADR 0020's "Phased rollout plan". The
manifest's shape does not change when that lands; it just gains a real
isolated executor behind the same `commands` it already declares.

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
