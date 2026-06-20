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

## Future GitHub trigger

After the local command is validated, a later PR may add a GitHub Actions trigger for comments such as `/opencode fix this` or a project-specific label.