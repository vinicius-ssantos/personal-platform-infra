---
description: Execute a persisted plans/*.plan.md workflow
agent: orquestrador
model: opencode/deepseek-v4-flash-free
subtask: false
---

Execute the implementation plan at:

$ARGUMENTS

Read @docs/ai-plan-workflow.md before acting.

Execution rules:

- Read the whole plan before editing files.
- Create a todo list from the plan tasks.
- Execute exactly one atomic task at a time.
- Use the agent suggested by the plan when delegating work.
- Keep each task bounded to its listed files unless the plan is clearly missing
  a necessary adjacent file.
- Run the validation listed for each task before moving to the next task.
- Stop and explain the blocker if validation fails.
- Do not re-plan the feature unless the plan is impossible to execute safely.

Security rules:

- Do not read or print secrets.
- Do not open `.env`, `.env.*`, kubeconfig files, `terraform.tfvars`, secret
  manifests, or credential files.
- Do not run `delete`, `destroy`, `prune`, `merge`, `release`, or `deploy`
  operations without explicit user confirmation.
- Do not write to `main` or `master`.
- Prefer local render/static validation before any cluster operation.

Model/cost rules:

- Treat this command as the cheap/free executor path.
- Do not perform broad architecture exploration if the plan is sufficient.
- Use `explorer` only for bounded read-only lookups.
- Use `reviewer` before final summary.
- If any task involves reading, generating, or reasoning about real secrets,
  production/VPS credentials, customer data, or other private environment
  data — even read-only — stop before running that task and tell the user
  to rerun with `opencode/deepseek-v4-flash` (paid) instead. Do not continue
  on the free model for that task. When in doubt, treat it as sensitive.

Final validation:

- Run the final validation checklist from the plan.
- Review `git diff`.
- Summarize all files changed.
- Summarize validations run and their result.
- Mention any skipped validation and why.

If `opencode/deepseek-v4-flash-free` is unavailable or too weak for the task,
stop and recommend rerunning with `opencode/deepseek-v4-flash` instead of
continuing blindly.
