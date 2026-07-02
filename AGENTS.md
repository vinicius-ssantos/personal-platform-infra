# Agent Instructions - personal-platform-infra

Short operational rules for Codex, OpenCode, Claude, and other coding agents.
For project structure, service inventory, and known traps, read `CLAUDE.md` only
when that context is needed.

## Absolute Rules

- Never commit directly to `main`; use a branch and PR.
- Never expose secrets in plaintext. Do not read `.env`, `.env.*`, `.mcp.json`,
  `opencode.local.json`, kubeconfigs, age keys, or `secrets/*.enc.yaml`.
- Never run destructive `kubectl` commands against a VPS/prod/k3s context
  without explicit human confirmation.
- Never use Helm in this repo. Kubernetes manifests use Kustomize only.
- Never add `latest` image tags to production-oriented Kubernetes manifests.
- Do not place storage in the cluster without an explicit PVC and ADR/context.

## Scope And Context

- Start with targeted search (`rg`, `rg --files`) before opening full files.
- Avoid reading generated or bulky paths: `node_modules/`,
  `.opencode/node_modules/`, `.tmp-*`, `.pytest_cache/`, `.sandbox/`, `dist/`,
  `.wrangler/`, and logs.
- Keep patches small and scoped to the requested service, script, or overlay.
- If a change touches more than one subsystem, summarize the intended files
  before editing.

## Token Discipline

- Prefer `git diff --stat`, `git status --short`, and targeted `rg` results
  before opening full diffs or files.
- Read only the relevant file ranges when possible; avoid dumping long logs,
  generated manifests, or full command output into the conversation.
- For bugfixes and narrow edits, investigate first, then apply the smallest
  patch that resolves the issue.
- Run the most specific validation route first; use broad suites only after
  targeted checks pass or when shared wiring changed.
- Keep final reports short: what changed, what was validated, and any remaining
  risk or blocker.
- Avoid token-burning phrasings — prefer the scoped alternative:
  - "analise o repo k8s" → "foque em `k8s/base/apps/<serviço>/`"
  - "rode todos os smokes" → `just smoke-<serviço>-sh` específico
  - "explique o ADR detalhadamente" → "resuma em 3 bullets"
  - `kubectl get pods -A` → `kubectl get pods -n <namespace>`
  - "mostre todos os manifestos" → `git diff --stat` + diff do arquivo alterado
  - "investigue tudo no cluster" → `kubectl describe <pod>` + `kubectl logs <pod>`
  - "refatore completamente" → "refatore só a função X, mantendo o comportamento"

## Validation Routes

- Kubernetes changes: run `kubectl kustomize k8s/overlays/local` and
  `kubectl kustomize k8s/overlays/vps`; use `just smoke-k3d` only when runtime
  validation is needed.
- Script changes: run `bash -n scripts/<file>.sh` or PowerShell parse checks.
- Environment/config changes: run `bash scripts/check-env-drift.sh` and
  `bash scripts/check-policy.sh`.
- Agent/AI workflow changes: run `bash scripts/ai-dx-check.sh` and
  `bash scripts/test-ai-guardrail.sh`.
- Prefer service-specific smokes such as `just smoke-gateway-sh` over broad
  suites unless the change affects cross-service wiring.

## OpenCode Local MCP Config

- Keep real OpenCode MCP credentials in `.env`, never in `opencode.json`.
- Generate the local ignored config with `just opencode-local-config`.
- Treat `opencode.local.json` as secret material; do not commit or paste it.

## Token Economy Across Tools

This repo is worked on by Codex, Claude Code, and OpenCode. Apply economy per
tool when starting a non-trivial task:

- **Codex** (`.codex/config.toml`): drop to a low-effort profile for trivial
  edits and routine smokes; reserve `model_reasoning_effort = "high"` for
  migrations, ADRs, or cross-service refactors.
- **Claude Code**: prefer the `task` tool with `subagent_type: "explore"` (free)
  for investigation; avoid `general` — it costs the same as the main session and
  the orchestrator can do the work directly.
- **OpenCode**: invoke the `economy-mode` skill for quick tasks; route subagents
  via `explore` (free) / `dev-free` / `dev-light` / `dev-medium` / `dev-heavy`
  by complexity, and never use `general`.

## Subagents

- Use subagents only for read-heavy, naturally parallel work such as review,
  exploration, log triage, or independent service audits.
- Do not use subagents for a single-file patch or a sequential design decision.
