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

## Subagents

- Use subagents only for read-heavy, naturally parallel work such as review,
  exploration, log triage, or independent service audits.
- Do not use subagents for a single-file patch or a sequential design decision.
