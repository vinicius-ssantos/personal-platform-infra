# ADR 0018: CI runner infrastructure lives in ci-self-hosted-runner

**Date:** 2026-06-04
**Status:** Accepted

## Context

The platform uses GitHub Actions for CI validation (`ci.yml`) and VPS deployment
(`deploy-vps.yml`). A separate repository, `vinicius-ssantos/ci-self-hosted-runner`,
owns the self-hosted runner fleet used by multiple application repositories.

The open question is how `personal-platform-infra` relates to that repository
without absorbing runner implementation concerns.

## Decision

CI runner infrastructure (Dockerfiles, Compose services, registration entrypoints,
PAT/token handling, runner runtime volumes) stays in `ci-self-hosted-runner`.

`personal-platform-infra`:

- documents which runner label each repository targets;
- documents workload placement rules (local runner vs VPS runner vs GitHub-hosted);
- owns the `runs-on:` values in its own workflow files;
- does **not** own runner Dockerfiles, Compose services, or registration tokens.

## Runner label matrix

| Repository | Recommended label | Rationale |
|---|---|---|
| `personal-platform-infra` | `ubuntu-latest` (GitHub-hosted) | Infra validation needs no local tooling |
| `github-unified-mcp` | `python-ci` | Python test suite, GHCR push |
| `deploy-orchestrator-mcp` | `python-ci` | Python test suite |
| `mcp-social` | `python-ci` | Python test suite |
| `central-mcp-gateway` | `python-ci` | Python test suite |
| `github-unified-mcp-frontend` | `frontend-ci` | Node/Vite build |
| `jobHunterAgent` | `python-ci` | Python + Playwright |
| `WorkflowEngine` | `java-ci` | Java/Maven or Gradle |

Labels are defined and provisioned by `ci-self-hosted-runner`. Update the matrix
here when a new label is created or a repository changes its build toolchain.

## Workflow placement rules

### Use GitHub-hosted runners when

- The job does not require local tooling installed by the runner (e.g. Python
  versions, Playwright browsers, Docker images pre-pulled).
- The job runs on untrusted input such as fork PRs.
- The job produces no artifacts that need to persist beyond the run.

### Use self-hosted runners when

- The job must run tests that depend on locally installed tooling or cached
  layers not worth reinstalling every run.
- The job builds or pushes images to GHCR using a pre-authenticated Docker
  daemon on the runner.
- The job benefits from local network access (e.g. reaching an internal
  registry).

### Current state of this repository

Both `ci.yml` and `deploy-vps.yml` use `ubuntu-latest` (GitHub-hosted). Moving
to a self-hosted `infra-ci` label is low-priority — the validation jobs are fast
and have no external tool dependencies beyond what `actions/setup-*` provides.

## Safety rules

- **Never route fork PR workflows to self-hosted runners.** Fork PRs run
  untrusted code in the job; a self-hosted runner could be compromised.
  Use `github.event.pull_request.head.repo.full_name == github.repository` to
  guard sensitive steps if mixed-trust workflows are ever needed.
- **Never store runner PATs or registration tokens in `personal-platform-infra`
  `.env` or secrets.** Runner credentials belong to `ci-self-hosted-runner`.
- **Never expose runner containers through Cloudflare Tunnel or public DNS.**
  Runners should be reachable only from GitHub's IP ranges.
- **Keep runtime deployment secrets separate from runner registration secrets.**
  `VPS_KUBECONFIG`, `SOPS_AGE_KEY`, and application bearer tokens must not be
  shared with runner registration flows.
- **Documentation-only PRs** do not require self-hosted runners — GitHub-hosted
  is sufficient and avoids runner fleet pressure.

## Consequences

- **Positive:** runner fleet changes (scaling, OS upgrades, new labels) are
  isolated to `ci-self-hosted-runner` without touching this repository.
- **Positive:** `personal-platform-infra` workflows remain portable — they run
  on GitHub-hosted runners without any local setup.
- **Negative:** if a future `infra-ci` label is introduced, this document and the
  workflow `runs-on:` values both need updating.

## References

- `ci-self-hosted-runner` repository: `vinicius-ssantos/ci-self-hosted-runner`
- Related: `vinicius-ssantos/ci-self-hosted-runner#8`
- ADR 0006: CI validates configurations, does not build images
- ADR 0012: VPS deploy via GitHub Actions
