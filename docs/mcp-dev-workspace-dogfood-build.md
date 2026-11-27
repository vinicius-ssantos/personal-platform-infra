# P1 — isolated Java/Node/OpenSpec dogfood image (candidate)

This change versions a **local-only candidate** for the `mcp-dev-workspace` project. It does not wire a service, publish a port, rotate OAuth credentials, register a GitHub runner, change the Gateway, or deploy anything. Track acceptance in [workspace #132](https://github.com/vinicius-ssantos/mcp-dev-workspace/issues/132), with M4 closure separately in #87 of that repository.

## Source and build order

- `compose/mcp-dev-workspace-dogfood-base.Dockerfile`: Maven 3.9.11, Java 25, Python and Git, non-root runtime.
- `compose/mcp-dev-workspace-dogfood-full.Dockerfile`: Node.js 24 and OpenSpec 2.1.0 layered on the previous local image. Telemetry disabled.
- Build using this repository as Docker context, with a dedicated local tag. These files are **not** part of `compose/docker-compose.yml` and must not be used as an automatic deployment override.

```sh
docker build -f compose/mcp-dev-workspace-dogfood-base.Dockerfile -t mcp-dev-workspace-dogfood:java25-python .
docker build -f compose/mcp-dev-workspace-dogfood-full.Dockerfile -t mcp-dev-workspace-dogfood:full .
```

Before marking the PR ready, pin and independently verify base manifest digests, review supply-chain scans (including transitive npm dependencies), and preserve a known-good rollback image. Local tags here are not release references.

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

## Observations from 26 November 2026

The original local image reported Node 24.22.3, npm 11.19.1, OpenSpec 2.1.0 and `openspec validate --all --strict` **5/5 passed**. Maven dependency prefetch returned `BUILD SUCCESS`; an online compilation/packaging with tests skipped also passed, but a full offline test run still required additional Surefire provider artifacts at the time of drafting. These are **development observations**, not release acceptance.

Related: Gateway [#415](https://github.com/vinicius-ssantos/central-mcp-gateway/issues/415), infra [#329](https://github.com/vinicius-ssantos/personal-platform-infra/issues/329), workspace [#87](https://github.com/vinicius-ssantos/mcp-dev-workspace/issues/87) and [#132](https://github.com/vinicius-ssantos/mcp-dev-workspace/issues/132).
