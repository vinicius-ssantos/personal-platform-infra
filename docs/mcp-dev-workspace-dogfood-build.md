# P1 — isolated Java/Node/OpenSpec dogfood image (candidate)

This change versions a **local-only candidate** for the `mcp-dev-workspace` project. It does not wire a service, publish a port, rotate OAuth credentials, register a GitHub runner, change the Gateway, or deploy anything. Track acceptance in [workspace #132](https://github.com/vinicius-ssantos/mcp-dev-workspace/issues/132), with M4 closure separately in #87 of that repository.

## Source and build order

- `compose/mcp-dev-workspace-dogfood-base.Dockerfile`: Maven 3.9.11, Java 25, Python and Git, non-root runtime.
- `compose/mcp-dev-workspace-dogfood-full.Dockerfile`: Node.js 24 and OpenSpec 2.1.0 layered on the previous local image. Telemetry disabled.
- Build using this repository as Docker context, with a dedicated local tag. These files are **not** part of `compose/docker-compose.yml` and must not be used as an automatic deployment override.

```sh
docker build -f compose/mcp-dev-workspace-dogfood-base.Dockerfile -t mcp-dev-workspace-dogfood:java25-python .
docker build --build-arg BASE_IMAGE=mcp-dev-workspace-dogfood:java25-python -f compose/mcp-dev-workspace-dogfood-full.Dockerfile -t mcp-dev-workspace-dogfood:full .
```

The image bases are pinned to independently inspected multi-platform OCI index digests as of 2026-11-27: Maven `sha256:407c4423cec0cf2981055bc2c6c0dc211d9605b6669279b95997f2d1c7e91e2c`, Node `sha256:873f586f3794f52281bd039bf02c048a0be08fde619338f9941bad1eb6b34530`. Keep checking vulnerability advisories and transitive npm dependencies; digest pinning does not imply a passing security scan. Preserve the known-good original image; local tags are not releases.

For an isolated evaluation **without replacing an existing local tag**, set an alternate base tag and pass it as the `BASE_IMAGE` build argument. The [P1 image CI workflow](../.github/workflows/p1-dogfood-image.yml) runs the same builds and a network-disabled, non-root runtime smoke test on a hosted runner, without secrets or deployment. It does **not** replace the full Java suite or vulnerability scanning.

## Reproducible acceptance

Use a disposable copy of the source checkout inside the container, mount the original checkout **read-only**, and run as non-root with read-only root filesystem, dropped capabilities, bounded memory/CPU/PIDs and no published ports.

1. Confirm `node --version`, `npm --version` and `openspec --version`. Use `OPENSPEC_TELEMETRY=0`, then `openspec validate --all --strict` with network disabled.
2. Populate a **dedicated, non-secret Maven cache** through a controlled network-enabled dependency resolution step. `dependency:go-offline` alone is not enough for Spotless and Surefire dynamic providers. Resolve explicitly reported artifacts; never disable format or test gates to claim acceptance.
3. Run a **new** offline `mvn -o -B -ntp -Dmaven.repo.local=/cache verify` in the copied project with `--network none` and cache mounted read-only. Record the final exit code, test totals and skipped tests, plus the source commit and image digest. Do not call an online build with `-DskipTests` an accepted test run.
4. Validate the exact registered tasks over the Gateway and ensure `dev=READ_ONLY` continues to reject execution. The ChatGPT static-tool catalog `confirmation_token` refresh is a separate client gate, not a reason to relax the Java/Gateway policies.

## Security and rollout gates

- Do not add global `git safe.directory` exceptions or a wildcard. Restrict Git trust to a command's configured canonical workspace root.
- No shell-unrestricted MCP capability, public Java workspace port, production overrides, `.env` material, OAuth scope change or secret in logs.
- Add targeted CI for the Dockerfiles, vulnerability/SBOM review, Java/Python/OpenSpec gates and negative network tests before merge.
- Keep actual canary/rollback operations as **separately reviewed, explicit operator actions**, using existing infra preflight tooling. This PR does not start/stop any production container or promote any release.

## Acceptance evidence — 27 November 2026

- Pinned candidate digest (local image ID): `sha256:30ebc716243f58ba4cbdf101eaa42809eef924b63b1f850bddb6cfa60bcefe75`.
- The candidate builds successfully, runs with UID 10001, has no system-level `git safe.directory` exception, and passed OpenSpec strict **5/5** in a read-only, network-disabled container.
- Full Maven `-o verify` on Java source commit `b2c61b3`: **454 tests, 0 failures, 0 errors, 10 skipped, BUILD SUCCESS, exit 0**. Read-only source/cache, disposable copy, no network.
- GitHub Actions: [image build/smoke](https://github.com/vinicius-ssantos/personal-platform-infra/actions/runs/45993398275) and [regular CI](https://github.com/vinicius-ssantos/personal-platform-infra/actions/runs/45993398362) both SUCCESS at the earlier checkout-tag-pin commit. No image push/deploy.

## Vulnerability scan status — NOT ACCEPTED

- Docker Scout `cves` requires a Docker ID login on the authorized machine and returned exit 1. No credentials were requested, created or changed.
- An isolated, non-root Grype 0.122.0 scanner with pinned OCI index `sha256:013e16ae96bd64108973e3e9fecec63f7ff276358d34c46c25d33e2aac96539f` was tested against a **Docker archive**, with no Docker socket and no source checkout access.
- The first attempt failed because the tmpfs database exceeded its quota. The second, Windows-bind-mounted attempt expanded a database of approximately 2.86 GB but did not complete a CVE report in a reasonable controlled run; it was explicitly stopped (exit 143), and its dedicated temporary artifacts were removed. **This is an inconclusive scan, not proof of no vulnerabilities.**
- Next security gate: run a trusted scanner with a Linux-native cache or operator-authenticated Docker Scout, capture dated HIGH/CRITICAL findings and SBOM, remediate or explicitly accept any exceptions, then add reproducible scan CI. Pin every third-party action or scanner by immutable digest/SHA; never attach the Docker socket to an unreviewed scanner container.
- Independent review and the separate Gateway/ChatGPT catalog/E2E gates remain open. Do not mark P1 ready/merge or deploy based solely on green build/test jobs.

## Versioned no-network canary (opt-in only)

The fixture [`compose/mcp-dev-workspace-dogfood-canary.yml`](../compose/mcp-dev-workspace-dogfood-canary.yml) is a separate Docker Compose project (`p1-dogfood-validation`) with a gated `p1-dogfood` profile and **no ports, network, mounts, secrets or application processes**. It has read-only root, UID 10001, no Linux capabilities, no-new-privileges, resource limits, and a transient `/tmp`. It does **not** amend any production Compose file, Gateway routing or OAuth configuration.

After explicitly building the candidate under a *separate* tag:

```sh
docker compose -f compose/mcp-dev-workspace-dogfood-canary.yml --profile p1-dogfood config --quiet
P1_DOGFOOD_IMAGE=mcp-dev-workspace-dogfood:p1-full-20261127 \
  docker compose -f compose/mcp-dev-workspace-dogfood-canary.yml --profile p1-dogfood run --rm candidate
```

On PowerShell, set `$env:P1_DOGFOOD_IMAGE='mcp-dev-workspace-dogfood:p1-full-20261127'` before the `docker compose` invocation. On 2026-11-27 this canary finished with `P1_CANARY_EXIT=0` in the local Docker Linux runtime. Its command only checks the runtime versions and effective UID; it is **not** the full Maven/Java suite or a Gateway E2E. The independent image CI also runs the same opt-in canary with a CI-only image tag.

## Rollback and canary (local only)

Do not connect this image to production Compose. Build the candidate under new local tags, leaving `mcp-dev-workspace-dogfood:full` untouched. Record `docker image inspect --format '{{.Id}}'` for candidate and known-good images. Run acceptance in disposable containers with no published ports and `--network none`; no process switch is required. If acceptance fails, stop only the candidate test container (if any) and return to the preserved known-good image tag. Avoid removing images used by existing containers. A real blue/green promotion or rollback needs a separate approved change and preflight, including monitored traffic and the configured Gateway policy.

## Observations from 26 November 2026

The original local image reported Node 24.22.3, npm 11.19.1, OpenSpec 2.1.0 and `openspec validate --all --strict` **5/5 passed**. Maven dependency prefetch returned `BUILD SUCCESS`; an online compilation/packaging with tests skipped also passed; later the full offline `mvn -o verify` passed with **454 tests, 0 failures/errors and 10 skipped** after controlled cache warmup, on the original local image. The pinned candidate must be independently tested. These are **development observations**, not release acceptance.

Related: Gateway [#415](https://github.com/vinicius-ssantos/central-mcp-gateway/issues/415), infra [#329](https://github.com/vinicius-ssantos/personal-platform-infra/issues/329), workspace [#87](https://github.com/vinicius-ssantos/mcp-dev-workspace/issues/87) and [#132](https://github.com/vinicius-ssantos/mcp-dev-workspace/issues/132).
