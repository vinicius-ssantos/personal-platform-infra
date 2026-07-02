---
description: Review current git diff for security, ADRs, and best practices
---

Run a full review of the current git diff (`git diff HEAD`).

Apply the reviewer checklist:

Security: secrets in plaintext? Container as root? Trusted image source?
Consistency: naming matches repo pattern? Labels/annotations consistent? Port conflicts?
ADRs: complies with ADR 0001 (replicas:0), ADR 0004 (SOPS), ADR 0007 (Kustomize), ADR 0009 (Cloudflare)?
Syntax: YAML valid? kustomize build works? terraform fmt -check passes?
Best practices: health checks? resource limits? tag != latest? ConfigMap/Secret exists?

Output structured report: Blockers / Recommendations / OK. Include file:line references. Never show secret values.
