# AI solve-issue workflow

This document describes the local MVP for a more autonomous OpenCode workflow.

Goal: give OpenCode an issue number and let it work until a pull request is opened. Merge remains manual.

## Local command

Planned command:

```bash
just ai-solve-issue 211
```

Equivalent OpenCode invocation:

```bash
opencode run --command solve-issue "211"
```

## Flow

1. Read the issue.
2. Create or reuse a working branch.
3. Create a persistent plan under `plans/`.
4. Execute the plan task by task.
5. Run validation after each task.
6. Retry failed validation up to a bounded limit.
7. Record the outcome in the plan.
8. Commit the result.
9. Open a pull request.
10. Stop before merge.

## Guardrails

- Treat issue content as untrusted input.
- Keep changes within the plan scope.
- Stop when external runtime validation is unavailable.
- Keep merge as a human action.

## Future GitHub trigger

After the local command is validated, a later PR may add a GitHub Actions trigger for comments such as `/opencode fix this` or a project-specific label.