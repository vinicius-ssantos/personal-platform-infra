/**
 * review-release-readiness
 *
 * Pre-deploy checklist: validates the branch is safe to merge and deploy to VPS.
 * Run on any branch before opening a PR that touches k8s/ or Terraform.
 *
 * Usage (Claude Code): /workflow review-release-readiness
 */

export default async function reviewReleaseReadiness({ claude }) {
  // Step 1: Explorer checks git state and what changed
  const gitState = await claude.task({
    subagentType: "explorer",
    prompt: `Report the current git state in personal-platform-infra:

1. Current branch name: \`git branch --show-current\`
2. Files changed vs main: \`git diff main --name-only\`
3. Commits ahead of main: \`git log main..HEAD --oneline\`
4. Any untracked or uncommitted changes: \`git status --short\`
5. For each changed k8s file, note which service and overlay it belongs to

Report: branch name, list of changed files grouped by category (k8s, terraform, scripts, docs, compose).`,
  });

  // Step 2: Reviewer checks compliance on changed files
  const [complianceResult, syntaxResult] = await Promise.all([
    claude.task({
      subagentType: "reviewer",
      prompt: `Run ADR compliance check on the changes in this branch of personal-platform-infra.

Git state from explorer:
${gitState.output}

Focus on changed files only. Check:
- replicas: 0 in any new/modified base deployments (ADR 0001)
- No plaintext secrets in any changed file (ADR 0004)
- No Helm additions (ADR 0007)
- Namespace consistency (ADR 0010)
- Image tags pinned, not :latest
- No REPLACE_WITH_ placeholders left in VPS overlay
- Gateway GATEWAY_TOOL_ALLOWLIST matches upstream tool names if configmap changed

Output structured: Blockers / Recommendations / OK`,
    }),

    claude.task({
      subagentType: "explorer",
      prompt: `Validate syntax of changed infrastructure files in personal-platform-infra.

Git state:
${gitState.output}

Run these validation commands and report pass/fail:
1. kubectl kustomize k8s/overlays/local (if k8s/ files changed)
2. kubectl kustomize k8s/overlays/vps (if k8s/ files changed)
3. bash -n <script>.sh for any changed shell scripts
4. docker compose -f compose/docker-compose.yml config (if compose changed)
5. terraform fmt -check terraform/cloudflare/ (if terraform files changed)

Report each validation with PASS or FAIL and any error output.`,
    }),
  ]);

  // Step 3: Smoke readiness check
  const smokeCheck = await claude.task({
    subagentType: "explorer",
    prompt: `Check smoke test coverage for personal-platform-infra.

Git state:
${gitState.output}

For each service affected by the changes:
1. Does scripts/smoke-<service>.sh exist?
2. Does the Justfile have a smoke-<service> recipe?
3. Is the service listed in the smoke-all and smoke-all-sh recipes?

Report: which services have smoke coverage and which are missing.`,
  });

  const hasBlockers =
    complianceResult.output.includes("Blockers") &&
    !complianceResult.output.includes("### ❌ Blockers\n(none)") &&
    !complianceResult.output.includes("### ❌ Blockers\n- (none)");

  const syntaxFailed = syntaxResult.output.includes("FAIL");

  const verdict =
    hasBlockers || syntaxFailed
      ? "❌ NOT READY — fix blockers before merge"
      : "✅ READY — safe to open PR and deploy";

  return `# Release Readiness Review

**Verdict: ${verdict}**

---

## Git State
${gitState.output}

---

## ADR Compliance
${complianceResult.output}

---

## Syntax Validation
${syntaxResult.output}

---

## Smoke Test Coverage
${smokeCheck.output}

---

## Merge checklist
- [ ] All Blockers resolved
- [ ] Syntax validation: all PASS
- [ ] Smoke tests cover affected services
- [ ] PR description explains the change and links relevant ADRs
- [ ] \`VPS_KUBECONFIG\` secret configured in GitHub if this touches k8s/
`;
}
