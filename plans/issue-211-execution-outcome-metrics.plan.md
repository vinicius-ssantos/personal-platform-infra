# docs(ai): add execution outcome metrics to plan-first workflow

## Metadata

- Slug: issue-211-execution-outcome-metrics
- Source: Issue #211
- Planner model: opencode/deepseek-v4-flash
- Intended executor model: opencode/deepseek-v4-flash-free
- Risk: low
- Created at: 2026-06-19

## Objective

Add an `Execution outcome` section to the plan file contract in `docs/ai-plan-workflow.md`, so that plan files can record what happened during execution (executor model, task counts, re-planning, validation, PR, merge status, and notes). The outcome is filled after `/execute-plan` completes.

## Scope

- `docs/ai-plan-workflow.md` — add the outcome section to the plan file contract template and explain when it is filled.

## Out of scope

- Commands (`/plan-feature`, `/execute-plan`).
- Plugins (router, etc.).
- Agents (orquestrador, explorer, infra-engineer, scripter, reviewer, operations).
- Model-cost policy changes.
- Any existing plan files — they remain as-is; the contract change applies to new plans going forward.

## Safety constraints

- Do not read or print secrets.
- Do not open `.env`, kubeconfig, Terraform variable files containing secrets, or credential files.
- Do not run destructive commands without explicit user confirmation.
- Do not deploy, merge, release, or delete resources.

## Pre-checks

- [ ] Read `docs/ai-plan-workflow.md` to find the plan file contract section.
- [ ] Confirm the branch is not `main` or `master`.

## Atomic tasks

### Task 1 — Add Execution outcome section to plan file contract

- Agent: orquestrador
- Type: edit
- Files likely touched:
  - `docs/ai-plan-workflow.md`
- Instruction:
  - Add an `## Execution outcome` section after the `## PR notes` section in the plan file contract template.
  - The section must include fields: executor model, task counts, re-planning status, validation result, PR, merge status, and notes.
  - Outside the template, add a paragraph explaining that the outcome section is filled after `/execute-plan` completes.
- Validation:
  - Visual markdown review.
- Acceptance criteria:
  - The plan file contract includes the Execution outcome section with all required fields.
  - The explanation about when it is filled is present.
- Rollback:
  - Revert the added lines.

### Task 2 — Review final diff

- Agent: reviewer
- Type: review
- Files likely touched:
  - `docs/ai-plan-workflow.md`
- Instruction:
  - Review the diff for consistency, correct markdown, and adherence to the issue scope.
  - Confirm only `docs/ai-plan-workflow.md` is modified.
- Validation:
  - N/A — review task.
- Acceptance criteria:
  - No issues found.
- Rollback:
  - N/A.

## Final validation

- [ ] `docs/ai-plan-workflow.md` includes the Execution outcome section in the plan file contract template.
- [ ] The fields (executor model, task counts, re-planning status, validation result, PR, merge status, notes) are present.
- [ ] The explanation that the outcome is filled after `/execute-plan` is documented.
- [ ] Only `docs/ai-plan-workflow.md` is changed.
- [ ] No commands, plugins, or agents are modified.

## PR notes

- Summary: Adds an Execution outcome section to the plan file contract so plan execution results can be recorded after `/execute-plan`.
- Tests: Visual markdown review.
- Risk: low, docs-only.
- Known limitations: Existing plan files under `plans/` are not retroactively updated; the contract change applies to new plans going forward.

## Execution outcome

- Executor model: opencode/deepseek-v4-flash-free
- Tasks total: 2
- Tasks completed: 2
- Re-planning: no
- Validation result: pass
- PR: (to be created by wrapper)
  - URL:
  - Status: open
- Merge commit:
- Notes: Plan created and executed in the same session. The Execution outcome section was added both inside the plan file contract template (under `## Plan file contract`) and as explanatory text outside it. The plan file itself also now carries the outcome section, serving as a self-documenting example of the new contract.
