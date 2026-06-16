/**
 * audit-platform-infra
 *
 * Full platform audit: security, ADR compliance, YAML validity, and drift.
 * Run periodically or before major releases.
 *
 * Usage (Claude Code): /workflow audit-platform-infra
 */

export default async function auditPlatformInfra({ claude }) {
  // Step 1: Explorer maps current state
  const mapResult = await claude.task({
    subagentType: "explorer",
    prompt: `Map the current state of the personal-platform-infra repository.
List all services in k8s/base/apps/, their namespaces, health paths, and whether they have:
- liveness + readiness probes
- resource requests and limits
- replicas: 0 in base (ADR 0001)

Also list any files containing REPLACE_WITH_ placeholders.
Report as structured markdown.`,
  });

  // Step 2: Reviewer runs compliance check in parallel with env drift check
  const [reviewResult, driftResult] = await Promise.all([
    claude.task({
      subagentType: "reviewer",
      prompt: `Run a full ADR compliance and security review of the personal-platform-infra repository.

Context from explorer:
${mapResult.output}

Check every service for:
- Secrets in plaintext (must be SOPS or {env:VAR})
- Containers running as root (securityContext.runAsNonRoot)
- replicas: 0 in base, >0 only in overlay/local (ADR 0001)
- Storage outside cluster (ADR 0002)
- Kustomize not Helm (ADR 0007)
- SOPS for secrets (ADR 0004)
- Namespace correct: mcp/bff/vos/monitoring (ADR 0010)
- No unsubstituted REPLACE_WITH_ placeholders in VPS overlay

Output structured report with Blockers / Recommendations / OK sections.`,
    }),

    claude.task({
      subagentType: "explorer",
      prompt: `Check for environment variable drift in personal-platform-infra.
Compare .env.example against compose/docker-compose.yml environment sections.
List any variables present in .env.example but missing from Compose, or vice versa.
Also check if scripts/check-env-drift.sh exists and what it validates.
Report as a concise list of drifted or missing variables.`,
    }),
  ]);

  // Step 3: Synthesize and output final report
  return `# Platform Infrastructure Audit — ${new Date().toISOString().slice(0, 10)}

## Service Map
${mapResult.output}

---

## ADR Compliance & Security Review
${reviewResult.output}

---

## Environment Variable Drift
${driftResult.output}

---

## Next steps
- Fix all Blockers before next deploy
- Review Recommendations against current sprint priorities
- Re-run \`just ai-dx-check\` after applying fixes
`;
}
