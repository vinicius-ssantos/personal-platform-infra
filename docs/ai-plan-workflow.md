# AI Plan Workflow

This document defines the plan-first workflow used to split expensive reasoning
from cheaper, bounded execution in OpenCode.

The workflow is intentionally small and explicit:

1. A stronger planner model creates a persistent implementation plan.
2. A cheaper/free executor model reads the plan and executes one atomic task at a
   time.
3. Existing project agents (`orquestrador`, `explorer`, `infra-engineer`,
   `scripter`, `reviewer`, and `operations`) remain the execution units.
4. The router plugin is not responsible for model-cost policy in the initial
   version.

## Why this exists

Long infra changes often mix two different workloads:

- planning: architecture reasoning, scope control, risk assessment, task slicing;
- execution: file edits, scripts, kustomize checks, smoke tests, and review loops.

Planning benefits from a stronger model. Execution should be deterministic,
bounded, and cheap when the plan is already clear.

Persisting the plan in `plans/*.plan.md` lets the user switch sessions or models
before starting the implementation.

## Commands

### `/plan-feature <goal>`

Creates a new `plans/<slug>.plan.md` file from a goal, issue, ADR, or feature
request.

Expected model profile:

- stronger paid model for planning;
- low temperature;
- no implementation side effects except writing the plan file.

### `/execute-plan <plans/file.plan.md>`

Executes a previously created plan.

Expected model profile:

- cheaper/free model when available;
- fallback to the cheapest reliable paid model;
- one task at a time;
- stop on validation failure.

## Plan file contract

Every plan must follow this structure.

```md
# <Feature title>

## Metadata

- Slug:
- Source:
- Planner model:
- Intended executor model:
- Risk: low | medium | high
- Created at:

## Objective

One short paragraph describing the expected end state.

## Scope

- Files, directories, docs, scripts, or manifests that may change.

## Out of scope

- Explicitly forbidden or deferred changes.

## Safety constraints

- Do not read or print secrets.
- Do not open `.env`, kubeconfig, Terraform variable files containing secrets,
  or credential files.
- Do not run destructive commands without explicit user confirmation.
- Do not deploy, merge, release, or delete resources unless the plan explicitly
  says so and the user confirms.

## Pre-checks

- [ ] Read relevant docs/ADRs.
- [ ] Inspect existing files before editing.
- [ ] Confirm the branch is not `main` or `master`.

## Atomic tasks

### Task 1 — <name>

- Agent: explorer | infra-engineer | scripter | reviewer | operations | orquestrador
- Type: read | edit | test | review | ops
- Files likely touched:
  - `path/to/file`
- Instruction:
  - One bounded action.
- Validation:
  - Command or manual check.
- Acceptance criteria:
  - Observable success condition.
- Rollback:
  - How to revert this task.

## Final validation

- [ ] Static checks pass.
- [ ] Relevant render/build/smoke commands pass.
- [ ] `git diff` is reviewed.
- [ ] Documentation is updated when needed.

## PR notes

- Summary bullets.
- Tests run.
- Known limitations.

## Execution outcome

Filled after `/execute-plan` completes. Records what happened during plan execution.

- Executor model:
- Tasks total:
- Tasks completed:
- Re-planning: yes | no
  - Reason (if yes):
- Validation result: pass | fail | partial
- PR:
  - URL:
  - Status: open | merged | closed
- Merge commit:
- Notes:
```

## Execution outcome

The `## Execution outcome` section is filled by the executor after `/execute-plan`
completes. It captures what actually happened during execution, including the model
used, task completion counts, whether re-planning was needed, validation results,
and the final PR status.

This section turns the plan into a persistent record of the execution, enabling
post-mortem analysis, model cost tracking, and workflow improvement over time.

Existing plan files are not retroactively updated — the outcome section applies to
plans created after this contract change.

## Task sizing rules

A task is too large when it touches unrelated areas, mixes planning and
implementation, or cannot be validated independently.

Prefer tasks that can be reviewed in isolation:

- create one manifest;
- update one kustomization;
- add one script;
- add one Justfile recipe;
- update one documentation section;
- run one validation group;
- run one reviewer pass.

## Model policy

Use the stronger model for planning when the task has architecture risk,
multiple domains, unclear constraints, or high blast radius.

Use the cheaper/free model for execution only when the plan is explicit enough
to be executed without re-planning.

If the free model is unavailable or performs poorly, use the cheapest reliable
paid executor model rather than changing the workflow.

## Security policy

The executor must avoid sensitive files by default:

- `.env`
- `.env.*`
- kubeconfig files
- `terraform.tfvars`
- secret manifests
- credential files

The executor must not run these operation classes without explicit user
confirmation:

- `delete`
- `destroy`
- `prune`
- `merge`
- `release`
- `deploy`
- direct writes to `main` or `master`

## Validated examples

The workflow has been validated on real repository changes after PR #205 added the initial commands and contract.

### PR #206 — infra feature with bounded implementation tasks

Issue #203 was implemented through `plans/issue-203-graceful-shutdown.plan.md`.

The plan split the change into 8 atomic tasks covering Kubernetes manifests, rollout-restart tooling, Justfile integration, documentation, and review. The executor used `opencode/deepseek-v4-flash-free` and completed the planned tasks without needing to re-plan in the middle of the implementation.

This is the ideal shape for plan-first work:

- multiple files and domains;
- infra or operations impact;
- explicit validation commands;
- reviewable task boundaries;
- clear rollback and safety constraints.

### PR #209 — documentation follow-up with small task set

Issue #207 was implemented through `plans/issue-207-graceful-shutdown-scope-docs.plan.md`.

The plan split the documentation follow-up into 4 atomic tasks and clarified the runtime scope difference between the global graceful shutdown patch and `just rollout-restart all`. The executor again completed the plan without re-planning.

This shows that plan-first can also work for documentation changes when the docs span multiple files or encode an operational decision. For a one-line typo or a single obvious edit, a direct command is still preferred.

## Decision guide

Use plan-first for multi-file work, operational changes, ordered validation, or tasks with external blockers. Prefer a direct command for small and obvious single-file edits.

## External validation blockers

Plans must call out checks that cannot be completed in the current environment. For example, issue #208 requires runtime observation before deciding whether a fallback is needed.

When validation is blocked, state the blocker, the impact, the safe local checks, and the follow-up needed once the environment is available.
