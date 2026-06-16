/**
 * add-new-mcp-upstream
 *
 * Guided workflow for adding a new MCP service to the platform.
 * Runs explorer → infra-engineer → reviewer in sequence.
 *
 * Usage (Claude Code): /workflow add-new-mcp-upstream
 * Then answer the prompts for service name, namespace, port, image, health path.
 */

export default async function addNewMcpUpstream({ claude, args }) {
  const {
    name,
    namespace = "mcp",
    port,
    image,
    healthPath = "/healthz",
  } = args;

  if (!name || !port || !image) {
    return `Missing required arguments.

Usage:
  /workflow add-new-mcp-upstream --name <service-name> --port <port> --image <ghcr-image> [--namespace mcp] [--healthPath /healthz]

Example:
  /workflow add-new-mcp-upstream --name my-tool-mcp --port 8000 --image ghcr.io/org/my-tool-mcp:1.2.0`;
  }

  // Step 1: Explorer checks for conflicts and existing patterns
  const explorerResult = await claude.task({
    subagentType: "explorer",
    prompt: `Check for conflicts before adding a new service named "${name}" to personal-platform-infra.

1. Does k8s/base/apps/${name}/ already exist?
2. Is port ${port} already used by another service in compose/docker-compose.yml?
3. Is namespace "${namespace}" valid? (allowed: mcp, bff, vos, monitoring)
4. Look at one existing service (e.g., github-unified-mcp) as a reference for structure.

Report: conflicts found (if any) + reference structure for the infra-engineer.`,
  });

  // Step 2: Infra engineer creates all files
  const infraResult = await claude.task({
    subagentType: "infra-engineer",
    prompt: `Add a new MCP service to personal-platform-infra with these parameters:
- name: ${name}
- namespace: ${namespace}
- port: ${port}
- image: ${image}
- health path: ${healthPath}

Context from explorer:
${explorerResult.output}

Create all required files following the checklist in CLAUDE.md "Adicionar um novo serviço":
1. k8s/base/apps/${name}/deployment.yaml (replicas: 0, probes on ${healthPath}, resource limits)
2. k8s/base/apps/${name}/service.yaml (ClusterIP, port ${port})
3. k8s/base/apps/${name}/kustomization.yaml
4. Register in k8s/base/kustomization.yaml
5. Add replica patch in k8s/overlays/local/replicas-local.yaml (replicas: 1)
6. Add to compose/docker-compose.yml with healthcheck
7. Create scripts/smoke-${name}.sh and scripts/smoke-${name}.ps1
8. Add smoke-${name} and smoke-${name}-sh recipes to Justfile
9. Append row to docs/service-integration-matrix.md

Validate: run kubectl kustomize k8s/overlays/local after changes.`,
  });

  // Step 3: Reviewer validates what was created
  const reviewResult = await claude.task({
    subagentType: "reviewer",
    prompt: `Review the files just created for the new service "${name}" in personal-platform-infra.

What the infra-engineer did:
${infraResult.output}

Check specifically:
- deployment.yaml has replicas: 0 in base (ADR 0001)
- Image is from GHCR, no latest tag (ADR 0006)
- Namespace is "${namespace}" (ADR 0010)
- No plaintext secrets (ADR 0004)
- Liveness + readiness probes on ${healthPath}
- Resource requests and limits set
- No REPLACE_WITH_ placeholders in VPS overlay
- kubectl kustomize k8s/overlays/local succeeds

Output: Blockers / Recommendations / OK`,
  });

  return `# Add New MCP Upstream: ${name}

## Pre-flight Check
${explorerResult.output}

---

## Files Created
${infraResult.output}

---

## Review
${reviewResult.output}

---

## Next steps
1. Fix any Blockers from the review above
2. Add secrets/env vars to .env.example and secrets/local.enc.yaml
3. Run \`just compose-up\` and \`just smoke-${name}\` to validate locally
4. Open PR: \`gh pr create\`
`;
}
