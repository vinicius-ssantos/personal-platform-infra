# review-diff

Run a full security and ADR compliance review of the current git diff.

## What this does

Calls the `reviewer` agent against staged or unstaged changes to catch blockers before opening a PR.

## Steps

1. Show the diff: `git diff HEAD` (or `git diff --cached` if staged)
2. Apply the reviewer checklist:
   - Secrets in plaintext?
   - Container running as root?
   - `replicas: 0` in base (ADR 0001)?
   - SOPS for secrets (ADR 0004)?
   - Kustomize not Helm (ADR 0007)?
   - Valid YAML? (`kubectl kustomize k8s/overlays/local`)
   - Health checks and resource limits set?
3. Output structured report: Blockers / Recommendations / OK

## Usage

```
/review-diff
```

No arguments needed. Operates on `git diff HEAD` by default.
