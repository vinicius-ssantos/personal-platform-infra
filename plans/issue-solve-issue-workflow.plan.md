# Add autonomous issue-to-PR OpenCode workflow

## Metadata

- Slug: solve-issue-workflow
- Source: User request
- Planner model: opencode/deepseek-v4-flash
- Intended executor model: opencode/deepseek-v4-flash-free
- Risk: medium
- Created at: 2026-06-19

## Objective

Add a local MVP that lets the user provide an issue number and have OpenCode work until a pull request is opened, while keeping merge manual.

## Scope

- `scripts/ai-solve-issue.sh`
- `Justfile`
- `docs/ai-solve-issue-workflow.md`

## Out of scope

- GitHub Actions trigger
- Automatic merge
- Deployment automation
- Plugin changes

## Atomic tasks

### Task 1 — Document the workflow

- Agent: orquestrador
- Type: edit
- Files likely touched:
  - `docs/ai-solve-issue-workflow.md`
- Instruction:
  - Document the local issue-to-PR flow, guardrails, and future GitHub trigger.
- Validation:
  - Visual markdown review.
- Acceptance criteria:
  - The local workflow is understandable.
- Rollback:
  - Remove the doc.

### Task 2 — Add wrapper script

- Agent: scripter
- Type: edit
- Files likely touched:
  - `scripts/ai-solve-issue.sh`
- Instruction:
  - Add a small bash wrapper around `opencode run --command solve-issue`.
- Validation:
  - `bash -n scripts/ai-solve-issue.sh`
- Acceptance criteria:
  - Script validates and requires an issue number.
- Rollback:
  - Remove the script.

### Task 3 — Add Justfile recipe

- Agent: scripter
- Type: edit
- Files likely touched:
  - `Justfile`
- Instruction:
  - Add `ai-solve-issue issue` recipe.
- Validation:
  - `just --list`
- Acceptance criteria:
  - Recipe appears in Justfile listing.
- Rollback:
  - Remove the recipe.

### Task 4 — Keep command file as future enhancement

- Agent: orquestrador
- Type: review
- Files likely touched:
  - N/A
- Instruction:
  - Use the self-contained wrapper for the MVP. A dedicated `.opencode/commands/solve-issue.md` can be added later if the host allows it.
- Validation:
  - N/A
- Acceptance criteria:
  - MVP works through `just ai-solve-issue <issue-number>`.
- Rollback:
  - N/A

## External blockers

The hosted gateway blocked writing directly to `.opencode/commands/solve-issue.md`. The MVP therefore uses a self-contained wrapper around `opencode run --model ... --agent ...`.

## Final validation

- [ ] `bash -n scripts/ai-solve-issue.sh`
- [ ] `just --list`
- [ ] `opencode run --help` or local equivalent confirms run flags are available
- [ ] Diff reviewed

## PR notes

- Summary: Adds local MVP for issue-to-PR OpenCode workflow.
- Tests: shell syntax, Justfile listing, AI DX check.
- Limitation: GitHub Action trigger remains future work.
