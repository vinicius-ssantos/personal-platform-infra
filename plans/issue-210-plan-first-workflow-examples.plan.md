# Add plan-first workflow examples and learnings

## Metadata

- Slug: issue-210-plan-first-workflow-examples
- Source: Issue #210
- Planner model: opencode/deepseek-v4-flash
- Intended executor model: opencode/deepseek-v4-flash-free
- Risk: low
- Created at: 2026-06-19

## Objective

Document the lessons learned after validating the plan-first workflow in real PRs.

## Scope

- `docs/ai-plan-workflow.md`

## Out of scope

- Commands
- Plugins
- Agents
- Model-cost policy changes

## Atomic tasks

### Task 1 — Add validated examples

- Agent: orquestrador
- Type: edit
- Files likely touched:
  - `docs/ai-plan-workflow.md`
- Instruction:
  - Add examples for PR #206 and PR #209.
- Validation:
  - Visual markdown review.
- Acceptance criteria:
  - Both PRs are cited as real validation examples.
- Rollback:
  - Revert the added section.

### Task 2 — Add routing guidance

- Agent: orquestrador
- Type: edit
- Files likely touched:
  - `docs/ai-plan-workflow.md`
- Instruction:
  - Explain when to use plan-first and when a direct command is enough.
- Validation:
  - Visual markdown review.
- Acceptance criteria:
  - Decision guidance is present.
- Rollback:
  - Revert the added section.

### Task 3 — Add blocker guidance

- Agent: orquestrador
- Type: edit
- Files likely touched:
  - `docs/ai-plan-workflow.md`
- Instruction:
  - Document that runtime or external validation gaps must be explicit blockers.
- Validation:
  - Visual markdown review.
- Acceptance criteria:
  - Issue #208 lesson is captured.
- Rollback:
  - Revert the added section.

## Final validation

- [ ] `docs/ai-plan-workflow.md` includes validated examples.
- [ ] Direct command vs plan-first guidance is documented.
- [ ] External validation blockers are documented.
- [ ] No commands, plugins, or agents are changed.

## PR notes

- Summary: Documents validated plan-first examples and post-merge learnings.
- Tests: Visual markdown review.
- Risk: low, docs-only.