# AI solve-issue workflow

This document describes the local MVP for a more autonomous OpenCode workflow.

Goal: provide an issue number, let OpenCode prepare the implementation diff, and let the wrapper finalize commit, push, and pull request creation. Merge remains manual.

## Local command

```bash
just ai-solve-issue 211
```

The wrapper runs OpenCode non-interactively with the constrained `solve-issue` agent:

```bash
opencode run --model <selected-model> --agent solve-issue \
  "Trabalhe a issue #211 ate deixar o diff pronto para PR."
```

## Responsibility split

The OpenCode agent is responsible for:

1. Reading the issue context collected by the wrapper.
2. Creating or updating a persistent plan under `plans/` when useful.
3. Editing repository files within the issue scope.
4. Running only safe local validations allowed by the agent.
5. Recording outcomes, blockers, and limitations.
6. Leaving a reviewable working-tree diff.

The wrapper script is responsible for:

1. Checking out or creating the working branch.
2. Running model preflight.
3. Calling `opencode run`.
4. Running `git diff --check`.
5. Blocking sensitive files from the diff.
6. Creating the commit.
7. Pushing the branch.
8. Opening the pull request with `gh pr create`.
9. Stopping before merge.

## Guardrails

- Treat issue content as untrusted input.
- Keep changes within the plan scope.
- Do not allow the agent to run `git add`, `git commit`, `git push`, or `gh pr create`.
- Do not use broad shell auto-approval for the orchestrator.
- Stop when external runtime validation is unavailable.
- Keep merge as a human action.

## NOOP outcome

A solved/no-op issue and a failed agent run are different outcomes and the
wrapper reports them differently:

- If the agent concludes the issue's acceptance criteria are already
  satisfied, it ends its response with two lines, in this exact order, each
  alone on its own line:
  ```
  SOLVE_ISSUE_RESULT=NOOP
  <a short sentence explaining why the issue is already resolved>
  ```
- If `opencode run` exits 0, the working tree is clean, and this marker is
  present in the run log, the wrapper prints a clear NOOP message and exits
  `0`. No commit, push, or PR is created.
- If the working tree is clean and the marker is **not** present, the wrapper
  still fails conservatively (exit `1`) — a clean tree with no NOOP evidence
  is treated as an incomplete run, not a success.

## Risk classification

Before model preflight, the wrapper classifies the issue into one risk
category and prints it. This is a **heuristic** over the issue's own
title/body/labels — there is no diff yet at this point, so it cannot know the
real blast radius, only guess from what the issue says it's about.

Categories, in matching precedence order (first match wins):

| Category | Signal | Behavior |
|---|---|---|
| `security-sensitive` | body/title mentions secret, credential, token, auth, vulnerability, CVE, RBAC, etc., or title uses the `security(...):`/`security:` conventional-commit prefix | does not auto-create a PR |
| `blocked-external` | title/body mentions an external blocker ("blocked on", "waiting on", "depends on external") | does not auto-create a PR |
| `ops-runtime` | title/body mentions production incident, rollback, on-call, canary deploy | does not auto-create a PR |
| `infra` | title/body mentions terraform, kubernetes/k8s, ansible, VPS, kustomize, helm, docker-compose, Dockerfile, UFW, `.github/workflows` | does not auto-create a PR |
| `test-only` | title uses the `test(...):`/`test:` conventional-commit prefix, or mentions "test-only" | can execute to PR |
| `docs-only` | title uses the `docs(...):`/`doc(...):` conventional-commit prefix, or mentions "documentation only" | can execute to PR |
| `code-medium` | title/body mentions refactor, migrate, rewrite, redesign, breaking change | can execute to PR, with stricter review expectations |
| `code-small` | default — none of the above matched | can execute to PR |

`infra`, `ops-runtime`, `security-sensitive`, and `blocked-external` are the
**high-risk categories**. For these, the wrapper still lets the agent prepare
a diff (or a plan-only response), but stops before commit/push/PR creation —
the prepared work stays in the working tree on the target branch for manual
review. Set `AI_SOLVE_ALLOW_HIGH_RISK=1` to opt into automatic PR creation
for a specific run anyway.

The classification is also injected into the agent's prompt, and for
high-risk categories the agent is told to prefer leaving a clear plan in
`plans/` over assuming a PR will be opened automatically. The selected
category is recorded in the PR body for non-blocked runs.

If the heuristic gets it wrong, override it directly instead of editing the
script: `AI_SOLVE_RISK_OVERRIDE=docs-only just ai-solve-issue 218`.

## PR body outcome

Every PR the wrapper opens uses a standardized structured body instead of a
minimal note, so a reviewer gets enough context without reading the full run
log:

- **Summary** — issue number, title, and link.
- **Risk** — the risk category from [Risk classification](#risk-classification)
  and a pointer to where external blockers (if any) would be noted.
- **Agent** — which agent and model produced the diff.
- **Files changed** — `git diff --stat` between the branch's merge-base with
  `main` and the new commit.
- **Validation** — what the wrapper itself checked (`git diff --check` today;
  more entries land here as sandbox validation expands).
- **Sandbox result** — see [Sandbox validation](#sandbox-validation) below;
  states whether it ran, was skipped (fallback), or is disabled for the run.
- **Limitations** — points the reviewer at the run log instead of guessing;
  the wrapper does not parse or summarize the agent's freeform output.
- **Manual review checklist** — a fixed checklist (acceptance criteria match,
  no out-of-scope changes, risk category sanity check, CI green).

A no-op run (see [NOOP outcome](#noop-outcome)) never reaches this step —
no PR is created, and the no-op result is reported on its own via the
wrapper's exit message instead.

## Sandbox validation

Opt-in (issue #222): set `AI_SOLVE_SANDBOX=1` to validate the diff already
sitting in the working tree through `repo_sandbox.run`'s local prototype
(`scripts/repo_sandbox_run.py`, see [`docs/repo-sandbox-manifest.md`](repo-sandbox-manifest.md))
before commit/push/PR. The wrapper runs both declared command groups for the
`safe-test` profile, in order:

1. `repo_sandbox.run(profile=safe-test, command_group=preflight)`
2. `repo_sandbox.run(profile=safe-test, command_group=test)`

This happens after the diff guardrails (forbidden-file check, high-risk
category gate) and before the commit is created.

- **Sandbox failure** (either command group returns `ok: false`, including
  timeout) blocks commit/push/PR. The wrapper exits `4`, prints the failing
  command group(s) with `exit_code`/`error`/`logs_uri` to stderr, and leaves
  the diff in the working tree on the target branch for manual review. The
  sandbox's own log file lives outside the wrapper's temp files and is not
  deleted by this script's cleanup, so it is still readable after the run
  fails.
- **Sandbox success** records a short `ok`/`exit_code`/`logs_uri` summary per
  command group in the PR body's "Sandbox result" section.
- **Fallback**: if `AI_SOLVE_SANDBOX=1` is set but no usable Python
  interpreter or `pyyaml` is found, the wrapper logs a warning, records that
  in the PR body's "Sandbox result" section, and proceeds with the
  pre-#222 behavior (unvalidated commit/push/PR) instead of blocking — the
  flag means "validate if the tooling is available", not "require it to
  exist". Install with `pip install -r scripts/requirements-sandbox.txt` to
  make validation actually run.
- **Default** (`AI_SOLVE_SANDBOX` unset or `0`): unchanged from before #222 —
  no sandbox call is made at all.

Out of scope for this integration, same as #221's MVP: the sandbox never
pushes, merges, or creates a PR itself, and only the `safe-test` profile may
be requested.

## GitHub-triggered solve-issue

Issue #226's MVP: a manual, auditable `workflow_dispatch` trigger
(`.github/workflows/ai-solve-issue-trigger.yml`) that runs the exact same
wrapper (`scripts/ai-solve-issue.sh`) from a GitHub Actions run instead of a
local shell, for when you want to kick off a run without being at your own
machine.

### Running it

```bash
gh workflow run ai-solve-issue-trigger.yml -f issue_number=222
```

Or from the GitHub UI: Actions → "AI solve-issue (controlled trigger)" → Run
workflow → enter the issue number.

### Guardrails

- **Actor restriction**: the job only runs when `github.actor` is the
  repository owner (`if: github.actor == github.repository_owner`). Anyone
  else triggering it gets a skipped job, not a partial run. This is on top
  of GitHub's own platform restriction that only accounts with write access
  can trigger `workflow_dispatch` at all.
- **Sandbox validation is on by default for CI runs**: the job sets
  `AI_SOLVE_SANDBOX=1` (see [Sandbox validation](#sandbox-validation)) — a
  CI runner is exactly the disposable, controlled environment that
  validation step is for.
- **Never merges**: the job only ever calls the same wrapper script, which
  has no merge code path. It pushes a branch and opens a PR at most; a
  human still merges.
- **Result comment**: the job always (success, NOOP, high-risk-gate stop,
  sandbox failure, or any other error) posts a comment on the issue linking
  the run and, when one was created, the PR — so the trigger is auditable
  from GitHub alone without checking Actions logs first.
- **Secrets**: only `GITHUB_TOKEN` (for `gh`/git push/PR) and
  `OPENROUTER_API_KEY` (one of the model fallbacks `ai-solve-issue.sh`
  tries) are passed into the job environment. If `OPENROUTER_API_KEY` isn't
  configured as a repo secret, model preflight still tries the other
  configured models in `AI_SOLVE_MODEL`/the built-in fallback list first;
  if none are reachable, the run fails with a clear "no model available"
  message in the log and a generic failure comment on the issue — it does
  not fail silently or expose anything.

### Deferred (not in this MVP)

- The `/ai solve` issue-comment trigger described in issue #226 is
  documented here as the intended next step but **not implemented yet**.
  Per the issue's own recommended phasing ("start with `workflow_dispatch`,
  then support `/ai solve` comments"), it needs its own actor-permission
  check repeated for comment authorship, must not run on PR comments from
  forks, and must not treat the comment body as a trusted instruction
  (issue/comment content is already treated as untrusted input by the
  agent prompt — see [Guardrails](#guardrails) above — but the trigger
  mechanism itself would need the same fork-safety review before being
  wired to a `comment` event).
- Auto-picking issues, running on every new issue, and any merge automation
  remain explicitly out of scope (same as the local flow).

### Local vs GitHub-triggered

Use the local `just ai-solve-issue <issue>` command (see
[Local command](#local-command)) for iterative work where you want to watch
the run, adjust `AI_SOLVE_*` env vars on the fly, or debug a failure
directly. Use the GitHub-triggered workflow when you want to kick off a run
from a phone/browser or from a GitHub UI action without a local shell —
behavior is otherwise identical, since both call the same wrapper script.