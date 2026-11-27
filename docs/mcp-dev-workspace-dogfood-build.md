# P1 — disposable, security-reviewed Java/Node/OpenSpec dogfood image

**Scope:** An opt-in, **local-only candidate** for `mcp-dev-workspace`. This PR does not modify production Compose, Gateway routing, Java workspace endpoints, OAuth scopes, credentials, runner registration or deployment. No new ports or host-wide Git trust are granted.

Tracking: [workspace #132](https://github.com/vinicius-ssantos/mcp-dev-workspace/issues/132), [M4 closure #87](https://github.com/vinicius-ssantos/mcp-dev-workspace/issues/87), [Gateway static write #415](https://github.com/vinicius-ssantos/central-mcp-gateway/issues/415).

## Immutable upstream inputs (verified 27 November 2026)

| Purpose | Version | OCI index digest |
|---|---|---|
| Maven distribution only (copied as a stage) | Maven 3.9.14 | `sha256:304ea1e9675d07612c36d5d70d8bd1dbd8aac64c307253bbde4e488857f90faa` |
| Actual base JDK | Temurin Java **25.0.5.1** | `sha256:4ddc1a8bdaf283421df5487411aff10b797ccf1e06a339041005114c8f489b5c` |
| Node runtime | Node 24.22.3 | `sha256:873f586f3794f52281bd039bf02c048a0be08fde619338f9941bad1eb6b34530` |
| CVE scanner | Grype 0.122.0 | `sha256:013e16ae96bd64108973e3e9fecec63f7ff276358d34c46c25d33e2aac96539f` |
| SBOM generator | Syft pinned image | `sha256:e97e20b6e6d1699c60296b66ab337941724f9bd06ac279d893eda89601fc4b2a` |

The Maven stage alone still ships Java 25.0.2 and vulnerable libraries; it is **never the final runtime base**. The final image uses the separate Temurin 25.0.5.1 stage and copies only Maven's distribution. Replace Maven's two vulnerable bundled JARs with HTTPS-fetched artifacts whose SHA-256 is verified inside the Docker build:

- `plexus-utils-3.6.1.jar` SHA-256 `05a63effd67e2d6b9d610cc82e2bd7473289d34802e57a529b28110f28af5679`
- `guava-33.7.2-jre.jar` SHA-256 `b530942257fb935f8b2cfaa5f8eb5bd59c555fd8e8d01b8ce98912e077ea606c`

The Node stage is multi-stage and carries npm **12.2.3** plus OpenSpec **2.1.0**. Builds run an Ubuntu security package upgrade before installing Python and Git. A pinned base digest does **not** fix apt or npm transitive resolutions at the byte level: evaluate the actual produced image digest and CVE/SBOM evidence on every build.

## Local build (do not replace the known-good tags)

Run from the **infra repository root**. These tags are separate from `mcp-dev-workspace-dogfood:full` and `:java25-python`, which may be used by existing containers.

```sh
docker build --platform linux/amd64 -f compose/mcp-dev-workspace-dogfood-base.Dockerfile -t mcp-dev-workspace-dogfood:p1-secfix-base-20261127 .
docker build --platform linux/amd64 --build-arg BASE_IMAGE=mcp-dev-workspace-dogfood:p1-secfix-base-20261127 -f compose/mcp-dev-workspace-dogfood-full.Dockerfile -t mcp-dev-workspace-dogfood:p1-secfix-full-20261127 .
docker image inspect mcp-dev-workspace-dogfood:p1-secfix-full-20261127 --format '{{.Id}} {{.Config.User}}'
```

The second Dockerfile's default `BASE_IMAGE` is only a convenience; always override it to point at the **newly built** corresponding base tag. **Never** use `docker compose up` against the production stack to validate this candidate.

## Versioned isolated canary

[`compose/mcp-dev-workspace-dogfood-canary.yml`](../compose/mcp-dev-workspace-dogfood-canary.yml) is a different Compose project, gated by the `p1-dogfood` profile. It runs **only** the version/UID smoke command with no network, ports, source mounts, secrets, process services, writable root or Linux capabilities.

```sh
P1_DOGFOOD_IMAGE=mcp-dev-workspace-dogfood:p1-secfix-full-20261127 \
  docker compose -f compose/mcp-dev-workspace-dogfood-canary.yml --profile p1-dogfood run --rm candidate
```

In PowerShell, set `$env:P1_DOGFOOD_IMAGE='mcp-dev-workspace-dogfood:p1-secfix-full-20261127'` before the `docker compose` command. Candidate canary ran locally with `exit 0`.

## Functional regression acceptance

Mount the source checkout and **dedicated, non-secret** Maven cache read-only into a disposable container. Copy source into temporary container storage, drop all caps, enable `no-new-privileges`, cap memory/CPU/PIDs, use a read-only root and `--network none`. Use an executable `/tmp` tmpfs for Maven Jansi/format dependencies. Run `mvn -o -B -ntp -Dmaven.repo.local=/cache verify` with tests enabled. A prior online `-DskipTests` warm-up is **not** an acceptable test result; `dependency:go-offline` alone may not fetch Surefire dynamic providers.

| Verification on 27/11/2026, Java source commit `b2c61b3` | Result |
|---|---|
| Maven offline `verify`, **corrected** image | **454 tests; 0 failures, 0 errors, 10 skipped; BUILD SUCCESS; exit 0** |
| OpenSpec `validate --all --strict`, corrected image | **5/5 passed; exit 0** |
| Docker Compose opt-in canary, corrected image | **exit 0**, UID 10001, no network |
| Final local candidate image ID | `sha256:def540bcac4a4ec800fc7ce8da3dad7a4cd99e5bcc31f15aab99bb7454ca30ab` |
| Global Git `safe.directory` exception | Absent by design; do not add one |

## Security scan and machine-readable evidence

The **original** candidate (ID `sha256:30ebc716243f58ba4cbdf101eaa42809eef924b63b1f850bddb6cfa60bcefe75`) scanned with **1,257 findings, 29 HIGH, 0 CRITICAL**. HIGH findings were in old OpenJDK, Ubuntu/OpenSSL, npm, Guava and Plexus.

After remediation, Grype 0.122.0 used its Linux-native vulnerability database to scan the **corrected candidate** via a Docker image archive, **without Docker socket, repository access or secrets**:

- **509 total findings; 0 HIGH, 0 CRITICAL, 489 MEDIUM, 17 LOW, 3 NEGLIGIBLE; exit 0.**
- Syft produced **SPDX 2.3 SBOM with 425 packages; exit 0**.
- MEDIUM/LOW residual findings are **not** proof of a vulnerability-free image; follow the organization's severity/exception policy and re-evaluate on each build.
- The security workflow is [`.github/workflows/p1-dogfood-image.yml`](../.github/workflows/p1-dogfood-image.yml). It **must fail** if a CI-built candidate contains HIGH/CRITICAL issues, and attach its Grype JSON plus SPDX SBOM as GitHub Actions artifacts. An externally reachable vulnerability DB is needed for the first scanner run; the scan container has **no Docker socket or credentials**.

Independent review and CI for the **exact final PR HEAD** are mandatory before lifting draft status or merging. GitHub checks are not substitutes for actual Gateway read/write E2E, which is tracked under #87 and Gateway #415.

## Rollback and separation of concerns

- No production image switch/deploy/release in this change. Preserve the existing known-good local image and its container. Candidate tags never replace existing tags.
- For a failed candidate test, stop/remove **only** its disposable test container and return to the known-good tag. This is an **isolated canary**, not a production blue/green cutover or proof of production rollback.
- Keep Java workspace policy authoritative: `dev=READ_ONLY` must deny mutations. The ChatGPT static `confirmation_token` is a **technical retry token, not human consent** (ADR 0020). A positive write test needs a separately registered TRUSTED **disposable fixture**; do not write to real repositories.
- M5 browser isolation and optional UI/UX console work are separate milestones. This PR does not authorize web browsing in the Java process or start UI prototypes.
