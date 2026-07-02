---
description: Plan a feature into an executable plans/*.plan.md file
agent: orquestrador
subtask: true
---

Create an implementation plan for:

$ARGUMENTS

Use the contract in @docs/ai-plan-workflow.md.

Do not implement the feature.
Do not modify files outside `plans/`.
Do not read or print secrets.

Create one new file at:

`plans/<slug>.plan.md`

The plan must include:

- objective;
- scope;
- out of scope;
- safety constraints;
- pre-checks;
- atomic tasks;
- suggested agent per task;
- likely files per task;
- validation per task;
- acceptance criteria;
- rollback guidance;
- final validation;
- PR notes.

Planning rules:

- Prefer existing agents before proposing new agents.
- Prefer commands over plugin/router changes for model-cost policy.
- Keep tasks independently reviewable and independently validatable.
- Mark tasks that require user confirmation.
- Avoid deploy, merge, release, delete, destroy, and prune operations unless
  explicitly requested.
- If the work is issue-based, include the issue number and map each acceptance
  criterion into one or more tasks.

Output rules:

- Write the plan file.
- Then summarize the plan path, task count, risk, and recommended executor model.
- Do not start implementation.
