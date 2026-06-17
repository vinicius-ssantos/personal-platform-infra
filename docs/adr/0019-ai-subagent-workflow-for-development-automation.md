# ADR 0019: AI Subagent Workflow for Development Automation

**Date:** 2026-06-16
**Status:** Accepted — Phase 1 only; Phases 2–3 are proposed and require separate decisions

## Context

The platform is maintained with three AI coding tools that serve distinct roles
and have distinct customization mechanisms. Each tool is a MCP client only —
none can expose itself as an upstream MCP server for external clients.

### OpenCode (`opencode`)

The primary interactive assistant for this repository. Already configured with
agents and skills in `.opencode/`.

**Agent spec (`.opencode/agent/<name>.md`):**

```yaml
---
description: Used by OpenCode to select the right agent for a task
mode: primary | subagent | all   # primary = shown in UI; subagent = only callable via task; all = both
model: provider/model-id          # optional: override default model for this agent
temperature: 0.0–1.0
top_p: 0.0–1.0                   # alternative to temperature
steps: N                          # max agentic iterations before forced text-only response
permission:
  edit: allow | ask | deny
  bash: allow | ask | deny
  read: allow | ask | deny
  webfetch: allow | ask | deny
  task: allow | ask | deny        # can this agent delegate via the task tool?
  # also: grep, glob, lsp, question, websearch, external_directory
disable: false
hidden: false
---
```

**Skill spec (`.opencode/skills/<name>/SKILL.md`):** Minimal — only `name` and
`description` in frontmatter. The body is the prompt template displayed to the
agent when the skill is invoked.

**Custom commands (`.opencode/commands/<name>.md`):** Slash commands for
high-frequency local tasks. Unlike skills, commands can receive positional
arguments (`$ARGUMENTS`, `$1`, `$2`) and embed shell output inline via
`` !`command` `` syntax. Better than skills for short, user-triggered workflows.

**Plugin system:** TypeScript/JavaScript modules in `.opencode/plugin/`
discovered automatically. Uses `@opencode-ai/plugin` SDK. Plugins can intercept
`tool.execute.before`, `tool.execute.after`, `session.*`, `permission.*`, and
other lifecycle events.

> **Path note:** This repository uses `.opencode/agent/` and `.opencode/plugin/`
> (singular) because that is what the installed OpenCode version resolves.
> Upstream documentation uses `.opencode/agents/` and `.opencode/plugins/`
> (plural). Migration to the canonical paths is tracked separately and should
> be tested before renaming.

**Known limitation — `task-router.ts` as versioned workaround:**
The built-in `task` tool's `subagent_type` parameter is hardcoded to built-in
types (`explore`, `general`). Custom agents defined with `mode: subagent` are
not yet invocable via the task tool in the version currently in use. The
`task-router.ts` plugin works around this by intercepting task calls and
injecting the named agent's context into the prompt.

This is a workaround, not a permanent architectural decision. It should be
removed once the upstream resolves native routing support. Removal checklist:

- [ ] Record `opencode --version` at time of validation
- [ ] Manual test: `@reviewer` mention triggers correct agent behavior
- [ ] Manual test: `task` call with agent name routes without plugin
- [ ] Remove `task-router.ts` and confirm behavior is unchanged
- [ ] Update this ADR to reflect native routing is in use

**Project instruction files (load order for OpenCode):**

1. `~/.config/opencode/AGENTS.md` — global user rules (lowest priority)
2. `CLAUDE.md` — project context: structure, services, commands, ADRs. Read by all three tools.
3. `.AGENTS.md` — AI-only behavioral rules: what never to do, agent delegation flows,
   environment safety rules. Higher priority than `CLAUDE.md` in OpenCode. Not meant
   for human readers — no architecture explanation, only directives.

The split is intentional: `CLAUDE.md` serves both humans and AI; `.AGENTS.md` is
exclusively for agent behavior enforcement.

**Current state of this repository:**

| Resource | Status |
|---|---|
| 6 agents (explorer, infra-engineer, reviewer, scripter, operations, orquestrador) | Configured |
| 3 skills (adicionar-servico, debug-k8s-pod, secrets-management) | Configured |
| `task-router.ts` plugin | Auto-discovered from `.opencode/plugin/`. Injects agent context into `task` calls when an agent name appears in the prompt. |
| `context-guard.ts` plugin | Auto-discovered from `.opencode/plugin/`. Intercepts bash calls and annotates descriptions with `[VPS]`/`[k3d]` context; blocks dangerous `kubectl delete` variants on VPS. |
| `steps` field on agents | Added by this ADR — was missing, no iteration limit protection prior. |

### Claude Code

Secondary interactive assistant, used for complex reasoning, cross-repo tasks,
and sessions that benefit from built-in orchestration types (Explore, Plan,
code-reviewer). Not configured per-project yet.

**Customization mechanisms:**

- **`.claude/agents/*.md`** — one file per custom subagent. YAML frontmatter
  (`name`, `description`, `tools`, `model`, `maxTurns`) + Markdown body as
  system prompt. Invoked automatically when Claude detects a matching task, or
  manually. Different from built-in orchestration types (Explore, Plan).
- **`.claude/skills/<name>/SKILL.md`** — repeatable procedure or checklist,
  invoked as a slash command. (`.claude/commands/` is deprecated.)
- **Dynamic Workflows** — a Claude Code feature (GA June 2026), not a file format
  you author by hand. Claude writes the orchestration script itself, at runtime,
  when asked directly ("create a workflow for X") or when the `ultracode` effort
  level is active (`/effort ultracode`) and Claude judges the task warrants it.
  A workflow can be saved for reuse by pressing `s` in the workflow menu during a
  run, which checks it into `~/.claude/workflows` (user-level). For project-level
  repeatable orchestration, use `.claude/agents/*.md` + manually-invoked subagents
  (Phase 1, section C below), or a `.claude/skills/<name>/SKILL.md` that instructs
  the same multi-step sequence in prose. See CLAUDE.md, "Quando usar Dynamic
  Workflows", for when each approach is worth the cost.
- **`CLAUDE.md`** — project context loaded at session start. Hierarchical:
  subdirectory files load on demand when Claude reads files in that subtree.

**Lifecycle hooks (`.claude/settings.json`):** Claude Code exposes
project-configurable lifecycle hooks. Safety-relevant hooks for this repo:

```json
{
  "hooks": {
    "PreToolUse": [{
      "matcher": "Bash",
      "hooks": [{
        "type": "command",
        "command": "scripts/ai-guardrail-check.sh"
      }]
    }]
  }
}
```

Use `PreToolUse` to block dangerous bash commands against VPS context and secret
files. Use `PostToolUse` for audit logging. Available hooks include:
`PreToolUse`, `PostToolUse`, `PermissionRequest`, `SubagentStart`,
`WorktreeCreate`, `FileChanged`, `UserPromptSubmit`, `TaskCreated`.

**Worktree isolation:** Claude Code supports `--worktree <name>` and
`isolation: worktree` on subagents for isolated sessions in
`.claude/worktrees/<name>/`. Use for broad edits, migrations, or multi-agent
tasks where partial state must not contaminate the main working tree. Add
`.claude/worktrees/` to `.gitignore`. Do not use `.worktreeinclude` to copy
`.env` files — production credentials must not flow into worktrees.

**`ultracode` effort level:** Claude Code has an `ultracode` effort level
(`/effort ultracode`) that combines maximum reasoning with automatic workflow
orchestration. It must not be set as a project default — it uses significantly
more tokens and latency. Use explicitly for large one-off tasks only.

**Agent Teams:** Experimental, disabled by default. Enable only via
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` for parallel research/review tasks.
Must not be used for write-heavy tasks until worktree isolation and hooks are
validated in this repo.

### Codex CLI (`codex`)

Agentic execution engine for automated and semi-automated tasks.

**Customization mechanisms:**

- **`AGENTS.md`** — project context and operating rules (same file Claude Code
  reads; Codex also loads it).
- **`.codex/agents/*.toml`** — project-scoped custom agents. One TOML file per
  agent, with fields: `name`, `description`, `model`, `sandbox_mode`,
  `developer_instructions`. Project agents only load when the project is trusted.
- **`.agents/skills/<name>/SKILL.md`** — reusable task workflows (Agent Skills
  open standard). Shared across tools. Optional `agents/openai.yaml` for
  metadata and tool dependencies.
- **`.codex/config.toml`** — project-scoped defaults for sandbox, approval,
  MCP servers, and agent thread limits.
- **`codex exec "prompt"`** — non-interactive/headless execution for CI
  pipelines and scripted tasks.
- **`codex mcp-server`** — exposes Codex as an MCP upstream (Phase 2+).

**Project configuration (`.codex/config.toml`):**

```toml
[agents]
max_threads = 4
max_depth   = 1

approval_policy = "on-request"
sandbox_mode    = "workspace-write"

[sandbox_workspace_write]
network_access  = false
writable_roots  = []

[shell_environment_policy]
inherit  = "core"           # pass only PATH, HOME, LANG, TZ, TERM, USER, SHELL
exclude  = [
  "*TOKEN*", "*SECRET*", "*KEY*",
  "CLOUDFLARE_*", "GH_TOKEN", "GITHUB_TOKEN",
  "SOPS_*", "AGE_*",
]

[history]
persistence = "none"        # do not save transcripts to history.jsonl
```

## Decision

Adopt a three-phase roadmap. Only Phase 1 is accepted by this ADR.

### Phase 1 — Local DX: harden and complete existing configuration (accepted)

**A. `.AGENTS.md` — AI-only behavioral rules**

Create `.AGENTS.md` at the repo root with agent directives that should not live
in `CLAUDE.md` (which is also read by humans). Content includes: hard rules
(never commit to main, never expose secrets, never use Helm), recommended agent
delegation flows per task type, environment safety rules (VPS vs local kubectl
context), and a list of actions that always require human review before execution.

Every application repository should have its own `.AGENTS.md` with rules
tailored to its stack and risk profile.

**B. OpenCode — add `steps` to all agents**


Every agent gains a `steps` limit to prevent runaway agentic loops and
unbounded cost. Read-only agents (no edit side-effects) get a lower cap; write
agents get a higher cap since they may need more iterations.

| Agent | steps | Rationale |
|---|---|---|
| `explorer` | 30 | Read-only; rarely needs more than a few rounds of grep + read |
| `reviewer` | 30 | Read-only; structured checklist is bounded |
| `orquestrador` | 20 | Delegates to subagents; should not do deep work itself |
| `operations` | 40 | Bash-heavy; may iterate on diagnostics |
| `scripter` | 50 | Creates/edits scripts; may need test-fix cycles |
| `infra-engineer` | 50 | Complex manifests; may need validate-fix cycles |

**C. Claude Code — add `.claude/agents/`**

Mirror the OpenCode agent roles for sessions in Claude Code. Claude Code uses
individual `.md` files per agent in `.claude/agents/`, with YAML frontmatter
(`name`, `description`, `tools`, `model`, `maxTurns`) and the Markdown body as
the system prompt:

```
.claude/agents/
  explorer.md
  infra-engineer.md
  reviewer.md
  scripter.md
```

Example format:

```markdown
---
name: explorer
description: Read-only codebase research. Maps structure, traces dependencies. Never modifies files.
tools: Read, Glob, Grep
maxTurns: 30
---

You are a read-only researcher. Map the codebase, trace dependencies, summarize
architecture. Never write files, never run mutating commands. Report findings
with file paths and line numbers.
```

```markdown
---
name: infra-engineer
description: Kubernetes, Terraform, Ansible, Kustomize. Creates and edits k8s manifests, overlays, terraform resources.
tools: Read, Edit, Write, Glob, Grep, Bash
maxTurns: 50
---

You are an infrastructure engineer for this platform. Follow CLAUDE.md conventions:
replicas=0 in base, Kustomize not Helm, namespaces mcp/bff/vos/monitoring,
SOPS+age for secrets. Always include probes and resource limits.
```

```markdown
---
name: reviewer
description: Code and infra review. Checks security, ADR compliance, YAML/Terraform syntax. Never modifies files.
tools: Read, Glob, Grep, Bash
maxTurns: 30
---

You are a senior reviewer. Check security (secrets in plaintext?, runAsNonRoot?),
ADR compliance (0001 replicas, 0002 storage, 0004 secrets, 0007 kustomize),
and syntax (kustomize build, terraform validate, bash -n). Output structured
findings: blockers, recommendations, ok.
```

```markdown
---
name: scripter
description: Shell, PowerShell, Justfile, smoke tests. Creates and maintains operational scripts.
tools: Read, Edit, Write, Glob, Grep, Bash
maxTurns: 50
---

You are a scripting specialist. Follow conventions in CLAUDE.md: set -euo pipefail,
info/error helpers, curl-based healthchecks. Validate with bash -n. Add Justfile
recipe for every new script.
```

**D. Codex CLI — add `.codex/config.toml`**

Establish project-scoped defaults and make the repo-research MCP server
available to Codex during automated tasks:

```toml
[agents]
max_threads = 4
max_depth   = 1

[approval]
approval_policy = "on-request"
```

**E. Safety guardrails and environment hardening**

All AI clients that can run shell commands must enforce equivalent safety rules:

- **OpenCode:** `context-guard.ts` already blocks destructive `kubectl delete`
  on VPS and annotates bash descriptions. Extend if new dangerous patterns emerge.
- **Claude Code:** add `PreToolUse` hook in `.claude/settings.json` pointing to
  a shared `scripts/ai-guardrail-check.sh` that rejects secret file reads,
  VPS-context deletes, and `git push --force` on main.
- **Codex:** `shell_environment_policy` in `.codex/config.toml` excludes
  credential env vars by default. `history.persistence = "none"` prevents
  transcripts from persisting tokens to disk.

Rule: any client allowed to run shell commands must block or prompt on
dangerous commands against VPS/production contexts, secret files, destructive
`kubectl` operations, and git history rewriting.

**F. OpenCode commands**

Add `.opencode/commands/` for high-frequency local workflows that benefit from
positional arguments and inline shell output:

```
.opencode/commands/
  review-diff.md        → /review-diff
  smoke-local.md        → /smoke-local
  add-mcp-service.md    → /add-mcp-service <name>
  debug-k3d.md          → /debug-k3d <pod>
```

**G. `just ai-dx-check` smoke**

Add a Justfile recipe that validates the AI DX configuration files are present
and parseable — ensuring the ADR's promises are enforced in the repo:

```bash
# scripts/ai-dx-check.sh
# Verifies AI agent/skill/workflow/config files exist and are valid
check .opencode/agent/*.md
check .opencode/skills/*/SKILL.md
check .opencode/commands/*.md
check .claude/agents/*.md
check .claude/skills/*/SKILL.md
check .codex/agents/*.toml        # warn only if missing (optional)
check .agents/skills/*/SKILL.md   # warn only if missing (optional)
check .codex/config.toml
check .AGENTS.md
```

**H. Repo-scoped workflows and automation primitives**

Add the following directories across repos as needed, following the open Agent
Skills standard shared by all three tools:

```
<repo>/
  .claude/
    agents/          ← specialized roles (Claude Code)
    skills/          ← repeatable procedures (Claude Code)
  .opencode/
    agent/           ← specialized roles (OpenCode)
    skills/          ← repeatable procedures (OpenCode)
    plugin/          ← hooks and automation (OpenCode)
  .codex/
    agents/          ← specialized roles as TOML (Codex)
    config.toml      ← sandbox, approval, thread defaults (Codex)
  .agents/
    skills/          ← shared skills read by Codex (Agent Skills standard)
  .AGENTS.md         ← AI-only rules, read by all three tools
  CLAUDE.md          ← project context, read by all three tools
```

Distinction by use case:

| Mechanism | Use when |
|---|---|
| `agents/` | You need a reusable specialized role or persona |
| `skills/` | You need a repeatable procedure or step-by-step checklist |
| Dynamic Workflows (Claude only, ephemeral) | A one-off task needs scripted orchestration across many subagents at scale; ask Claude directly or use `ultracode` effort — not a directory you populate by hand |

Repeatable multi-step orchestration for this repo (explorer → reviewer/infra-engineer
in sequence or parallel, then synthesize) should be run by hand via the `Agent` tool,
or turned into a `.claude/skills/<name>/SKILL.md` prompt if needed repeatedly. Reserve
Dynamic Workflows for the cases in CLAUDE.md's "Quando usar Dynamic Workflows".

**What Phase 1 does not include:**
- No new services, no gateway changes, no infrastructure changes.
- Codex CLI is not wired as a gateway upstream yet.
- Local orchestration (manual subagent calls or Dynamic Workflows) is local DX only —
  no autonomous writes, no gateway exposure, no VPS execution.

---

### Phase 2 — `codex-orchestrator-mcp` as gateway upstream (proposed)

Create a thin FastMCP wrapper service (`codex-orchestrator-mcp`) that launches
`codex mcp-server` as a subprocess and exposes a controlled tool catalog to the
gateway. The service runs on **WSL2 local only** during the initial period —
not on VPS while production secrets are co-located.

The wrapper translates high-level gateway calls into `codex` / `codex-reply`:

| Gateway tool | Underlying Codex call | Side-effects | Confirmation |
|---|---|---|---|
| `codex.map_task` | `codex(prompt, approval_policy=on-request, sandbox=read-only)` | none | not required |
| `codex.plan_change` | `codex(prompt, approval_policy=on-request, sandbox=read-only)` | none | not required |
| `codex.review_diff` | `codex(prompt, approval_policy=on-request, sandbox=read-only)` | none | not required |
| `codex.apply_simple_fix` | `codex(prompt, approval_policy=on-request, sandbox=workspace-write)` | workspace-write | required |
| `codex.apply_hard_fix` | `codex(prompt, approval_policy=on-request, sandbox=workspace-write)` | workspace-write | required (strong) |

Multi-turn sessions use `codex-reply` with the `threadId` from the initial
`codex` call. The wrapper maps `threadId` to a `task_id` for the gateway's
idempotency layer.

**Phase 2 minimum safety requirements** (pre-requisite before connecting to the
gateway — not deferred to Phase 3):

- `task_id` + idempotency key on every call (gateway already provides this)
- Repo allowlist: Codex may only operate on explicitly listed repos
- `cwd` allowlist: reject any path outside pre-approved working directories
- `sandbox = workspace-write` with `network_access = false` for write tools
- Timeout per execution (`max_runtime_seconds`)
- Diff summary returned before the response is sent to the gateway caller
- Human confirmation via `confirm_channel` for any workspace-write tool
- Prompt injection hardening: user-supplied `task`, `repo`, `cwd` treated as
  untrusted and sanitized before passing to Codex `prompt` or `base_instructions`

Gateway additions:

```
GATEWAY_UPSTREAM_CODEX_URL: http://codex-orchestrator-mcp.mcp.svc.cluster.local:8000/mcp
GATEWAY_TOOL_ALLOWLIST: ...existing...,codex.map_task,codex.plan_change,codex.review_diff,codex.apply_simple_fix,codex.apply_hard_fix
```

---

### Phase 3 — Audit, budget, and risk evolution (proposed)

Once Phase 2 is stable (prompt injection hardening and basic audit are already
required in Phase 2):

- **Per-task budget cap** — `max_runtime_seconds`, `max_model_cost_usd` enforced
  by the orchestrator before dispatching to Codex.
- **Full audit log** — every execution records: `task_id`, `repo`, `cwd`, model,
  agent, files changed, commands run, diff summary, approval status, cost.
- **Prompt injection regression suite** — adversarial test cases covering
  `task`, `repo`, `cwd`, branch names, issue text, PR descriptions, and file
  contents as injection vectors.
- **Policy evaluation report** — periodic review of blocked/allowed commands,
  confirmation decisions, and false positives to tune guardrails over time.

---

### Phase 4 — CI auto-fix via Codex (proposed)

Codex documents a two-job CI pattern for automated fix PRs:

1. **Job A** (`contents: read` only) — runs `codex exec` against a CI failure,
   exports a patch file as a GitHub Actions artifact. No write permissions,
   no `GITHUB_TOKEN` exposed to the Codex process.
2. **Job B** (`contents: write`, `pull-requests: write`) — downloads the patch
   artifact, applies it, and opens a PR. Receives no `OPENAI_API_KEY`.

This separation prevents credential cross-contamination between the AI execution
environment and the PR-creation environment.

Not adopted in Phase 1–3. Pre-requisites: Phase 2 stable, repo allowlist,
cwd allowlist, and diff-preview gate all validated in production.

---

## Tool responsibility matrix

| Capability | OpenCode | Claude Code | Codex CLI |
|---|---|---|---|
| Interactive dev session | primary | secondary | no |
| Project context | `.AGENTS.md` + `CLAUDE.md` | `.AGENTS.md` + `CLAUDE.md` | `.AGENTS.md` + `.codex/config.toml` |
| Custom agents | `.opencode/agent/*.md` | `.claude/agents/*.md` | `.codex/agents/*.toml` |
| Repeatable skills | `.opencode/skills/<name>/SKILL.md` | `.claude/skills/<name>/SKILL.md` | `.agents/skills/<name>/SKILL.md` |
| Scripted workflows | plugin/task router | manual `Agent` calls, or Dynamic Workflows (ephemeral, not file-based) | skill + agents + `codex exec` |
| Custom commands | `.opencode/commands/*.md` | `.claude/skills/` (slash) | — |
| Plugin/hook system | `@opencode-ai/plugin` | `.claude/settings.json` hooks | `.codex/config.toml` hooks |
| Safety guardrails | `context-guard.ts` plugin | `PreToolUse` hook | `shell_environment_policy` |
| Session isolation | — | `--worktree` / `isolation: worktree` | sandbox modes |
| Headless/CI execution | no | no | `codex exec` |
| Expose as MCP server | no | no | yes (`codex mcp-server`) |
| Automated tasks via gateway | no | no | yes (Phase 2+) |
| Custom subagents via task tool | partial (workaround via plugin) | yes (`.claude/agents/*.md`) | via `.codex/agents/*.toml` |

## Compatibility matrix

| Tool | Min validated version | Key features required |
|---|---|---|
| OpenCode | TBD | `.opencode/agent/`, `.opencode/skills/`, `.opencode/commands/`, `.opencode/plugin/`, `steps` field |
| Claude Code | TBD (Dynamic Workflows GA June 2026) | `.claude/agents/`, `.claude/skills/`, hooks, worktrees |
| Codex CLI | TBD | `.codex/agents/`, `.agents/skills/`, `codex exec`, `codex mcp-server`, `shell_environment_policy` |

`just ai-dx-check` should print installed versions alongside config validation.

## AI task risk levels

| Risk | Examples | Phase 1 allowed | Confirmation |
|---|---|---|---|
| R0 read-only | map repo, review diff, explain CI failure | yes | no |
| R1 local write | edit docs, scripts, manifests locally | yes | recommended |
| R2 external write | create issue, open PR, publish package | no | required |
| R3 prod/VPS action | kubectl apply/delete, tunnel, DNS, secrets | no | required + separate ADR |
| R4 destructive | delete data, force push, rotate prod secrets | no | always blocked |

This table maps directly to the gateway risk classification in Phase 2+.

## Recommended local workflow

1. Use OpenCode for normal interactive development in this repo.
2. Use `/review-diff` before committing.
3. In Claude Code, use manual `.claude/agents/*.md` subagent calls (or, for
   genuinely large one-off tasks, ask for a Dynamic Workflow / `ultracode`) for
   broad audits, migrations, or cross-repo analysis.
4. Use `codex exec` only for explicit local reports or scripted checks.
5. Run `just ai-dx-check` before changing AI configuration files.
6. Never run AI write tasks against VPS/production contexts.

## Phase promotion criteria

Phase 2 cannot start until:

- [ ] `just ai-dx-check` passes locally and in CI.
- [ ] Guardrail tests cover secret file reads, destructive `kubectl`, force push
      on main, and VPS-context detection.
- [x] At least one multi-subagent orchestration (manual `.claude/agents/*.md`
      calls) has been used successfully without gateway exposure — done
      2026-06-17, ad hoc platform audit (explorer → reviewer + explorer in
      parallel → synthesis).
- [ ] Codex `sandbox_mode` and `network_access = false` behavior has been
      manually validated against a test repo.
- [ ] Phase 1 config files are reviewed and committed to all affected repos.

## Tool-specific policies

### OpenCode

- **Path policy:** use documented plural paths for new configuration
  (`.opencode/agents/`, `.opencode/plugins/`). Legacy singular paths
  (`.opencode/agent/`, `.opencode/plugin/`) remain until the installed version
  is validated against the plural layout.
- **Agent steps:** all agents must declare `steps`. No agent may run unbounded.
- **MCP policy:** project MCP servers are disabled by default. Local servers
  must declare explicit `cwd`, `enabled`, and timeout. Remote servers must not
  embed bearer tokens in config files.
- **Plugin workaround:** `task-router.ts` is a versioned compatibility shim,
  not permanent architecture. Remove when upstream resolves native routing.

### Claude Code

- **Memory hygiene:** `CLAUDE.md` must contain only stable project facts and
  conventions (commands, layout, service table, ADR references). Move
  step-by-step procedures to `.claude/skills/`, subtree rules to
  `.claude/rules/`. A bloated `CLAUDE.md` increases token cost on every session.
- **Hook decision policy:** hooks have two modes — block and annotate.
  - **Block:** secret file reads, destructive VPS `kubectl delete`, `git push --force` on main, direct writes to SOPS-encrypted material.
  - **Annotate/audit:** `kubectl get`, `terraform plan`, `kustomize build`, smoke tests, `gh pr view`.
  - Prefer annotation over blocking for read-only diagnostics.
- **Status line:** Claude Code supports a configurable status line (configure
  via the `statusline-setup` agent or `.claude/settings.json`). Recommended
  fields: git branch, dirty state, current repo, active Kubernetes context.
  Never display secret values or token contents.
- **Worktree isolation:** prefer `isolation: worktree` for subagents that
  perform broad edits, migrations, or multi-agent implementation tasks. Never
  copy `.env` into worktrees via `.worktreeinclude`.
- **Agent Teams:** experimental only, off by default. Do not use for write-heavy
  tasks until hooks and worktrees are validated.

### Codex CLI

- **Config boundary:** project `.codex/config.toml` may not override
  user-owned keys. Codex ignores and warns on: `openai_base_url`,
  `chatgpt_base_url`, `model_provider`, `model_providers`, `notify`, `profile`,
  `profiles`, `otel`, `experimental_realtime_ws_base_url`. Keep credentials,
  provider selection, and telemetry in `~/.codex/config.toml`.
- **Subagent sandbox rule:** every `.codex/agents/*.toml` must declare
  `sandbox_mode` explicitly. Read-only agents (`explorer`, `reviewer`) use
  `read-only`; write agents (`scripter`, `infra-engineer`) use `workspace-write`.
  `danger-full-access` is prohibited in this repository.
- **MCP tool allowlist:** every Codex MCP server block should declare:
  `enabled_tools`, `disabled_tools`, `default_tools_approval_mode = "prompt"`,
  per-tool `approval_mode`, `tool_timeout_sec`, and `startup_timeout_sec`.
  This prevents the same allowlist drift that caused the `social.prepare_post`
  incident at the gateway layer.
- **Reasoning budget:** default `model_reasoning_effort = "medium"`.
  Use `high` only for architecture decisions, security review, and hard CI
  failures. `xhigh` is manual-only, never a project default.
- **History:** `history.persistence = "none"` to prevent transcripts containing
  tokens from persisting to `history.jsonl`.

## What is explicitly out of scope

- Running `codex-orchestrator-mcp` on VPS while production secrets are co-located.
- `approval_policy=never` (equivalent of `danger-full-access`) on any gateway tool.
- Autonomous PR merges — the orchestrator may open PRs, merging requires human action.
- Embedding orchestration logic in `central-mcp-gateway` core.
- Automatic task-difficulty classification to route between agents (deferred until
  Phase 2 behavior is well understood in production).

## Consequences

**Phase 1 (immediate):**
- OpenCode agents gain `steps` limits — prevents runaway loops and cost overruns.
- `task-router.ts` plugin closes the gap between CLAUDE.md documentation and
  actual behavior: agent context is injected automatically on task calls.
- Claude Code sessions gain named, system-prompt-backed agents consistent with
  the OpenCode configuration.
- Codex CLI has project-scoped sandbox and thread defaults.

**Phase 2 and beyond:**
- A new upstream service enters the dependency graph, following existing patterns
  (GHCR image, Compose, k8s manifests, smoke script, Justfile recipe, gateway
  allowlist entry). The same static catalog validation that caught the
  `social.prepare_post` regression applies to `codex.*` tools.
- `apply_simple_fix` and `apply_hard_fix` are the highest-risk tools added to
  the platform. `confirm_channel` is mandatory.

## References

- ADR 0006: CI validates configurations, does not build images
- ADR 0009: Cloudflare as the single network layer
- ADR 0018: CI runner boundary — `ci-self-hosted-runner`
- OpenCode documentation: agents, skills, plugins, permissions — opencode.ai/docs
- Claude Code documentation: subagents (`.claude/agents/*.md`), skills (`.claude/skills/`)
- Codex CLI documentation: `codex mcp-server`, `.codex/config.toml`
