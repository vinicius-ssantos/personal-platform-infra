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

## Future GitHub trigger

After the local command is validated, a later PR may add a GitHub Actions trigger for comments such as `/opencode fix this` or a project-specific label.