# Image pinning strategy

This repository manages infrastructure for services whose images are built in upstream repositories and published to GHCR.

Mutable tags such as `:main` are useful for local iteration, but VPS deployments should be able to pin immutable application versions.

## Policy

### Local and Compose

Local development may use mutable tags:

- `:main`
- branch tags
- locally built tags

This keeps smoke testing and local iteration simple.

### Local k3d

Local k3d may also use `:main` while validating manifests and service wiring.

If a local test needs to reproduce a VPS issue, override the image to the same immutable tag or digest used by the VPS.

### VPS

VPS deployments should use immutable references once a service is considered release-ready.

Accepted forms, ordered by preference:

1. **Digest pinning**: `ghcr.io/org/image@sha256:<digest>`
2. **Commit SHA tag**: `ghcr.io/org/image:<git-sha>`
3. **Semver/release tag**: `ghcr.io/org/image:vX.Y.Z`

Avoid `:latest`, `:main`, or branch tags in production-oriented VPS overlays after a service has an immutable release reference.

## Where to set images

Base Kubernetes manifests can keep development-friendly defaults so local/k3d stays simple.

VPS-specific immutable references should be set in the VPS overlay with Kustomize `images` entries, for example:

```yaml
images:
  - name: ghcr.io/vinicius-ssantos/github-unified-mcp
    newName: ghcr.io/vinicius-ssantos/github-unified-mcp
    digest: sha256:<digest>
```

For tag pinning:

```yaml
images:
  - name: ghcr.io/vinicius-ssantos/github-unified-mcp
    newTag: <git-sha-or-release-tag>
```

Keep the exact pinned versions in reviewable commits. A VPS deploy PR should make it obvious whether it changes infra only, image versions only, or both.

## Automation (Renovate)

`renovate.json` operationalizes this policy:

- **Digest pinning** (`docker:pinDigests`): image references managed by the
  Docker, Compose and Kubernetes managers are pinned to `tag@sha256:<digest>`.
  This keeps the human-readable tag (e.g. `:main`) while making every pull
  reproducible, and Renovate opens a PR whenever the upstream digest moves.
- **Grouped platform-image PRs**: all `ghcr.io/vinicius-ssantos/*` updates land
  in a single weekly PR labelled `dependencies` (Mondays before 9am), never
  auto-merged — image bumps stay human-reviewed.
- **`.env.example` coverage**: a custom regex manager tracks the
  `*_IMAGE=ghcr.io/...:tag` entries so the Compose image vars get the same
  pinning/update treatment as the manifests.
- **GitHub Actions**: patch-level action updates auto-merge; minor/major are
  proposed for review.

Renovate updates references in place; pinning a specific immutable release tag
in the VPS overlay (above) remains a deliberate, reviewable change.

## Candidate services

- `github-unified-mcp`
- `deploy-orchestrator-mcp`
- `mcp-social`
- `github-unified-mcp-bff`
- `vos-studio-mcp`
- `vos-studio-bff`

## Rollback

Rollback should be a normal PR that reverts the image reference for the affected service to the previous known-good tag or digest.

Recommended rollback flow:

1. Find the last known-good image reference from Git history.
2. Change only the relevant `images` entry in the VPS overlay.
3. Open a small PR titled `rollback: pin <service> to <version>`.
4. Let CI validate Kustomize output.
5. Merge and let the VPS deploy workflow apply the overlay.
6. Run smoke checks for the affected service and platform status.

## Release checklist

Before pinning a new image in the VPS overlay:

- upstream image exists in GHCR;
- image tag or digest is immutable enough for the intended environment;
- service smoke test passes locally or in k3d;
- expected environment variables and secrets exist;
- rollback target is known.

## Managing Renovate PRs

Renovate opens PRs automatically. Review and handle them as follows:

| PR type | Example title | Action |
|---|---|---|
| **Digest pin (first time)** | `chore(deps): pin ghcr.io/...` | Review, merge. Pins `:main` to `:main@sha256:...` in k8s manifests, Compose and `.env.example`. |
| **Digest update** | `chore(deps): update ghcr.io/... digest to abc...` | Review changelog if available. Merge — the digest is from the same mutable `:main` stream the base already tracks. |
| **GitHub Actions patch** | `chore(deps): update actions/checkout...` | Auto-merged. Only patch-level action bumps. |

### Accepting a digest-pin PR

1. Wait for CI to pass.
2. Review the diff: only digest hashes should change, never image names or tags.
3. Merge. The VPS deploy workflow applies the update if `k8s/**` changed.

### Rejecting or modifying

If a Renovate PR is unwanted (e.g., a digest move broke something upstream):

1. Close the PR without merging.
2. Open an issue in the upstream repo.
3. The next Renovate schedule will propose the digest again once fixed.

To freeze a specific digest, pin it manually in `k8s/overlays/vps/kustomization.yaml`
and temporarily exclude the image from Renovate's `packageRules` if needed.

## Policy check

`scripts/check-policy.sh` (run in CI) warns when `.env.example` or the k8s base
manifests carry mutable `ghcr.io/...:main` tags. This warning is expected during
local development and is resolved once Renovate's digest-pinning PRs are merged.
It is a warning, not a hard failure.
