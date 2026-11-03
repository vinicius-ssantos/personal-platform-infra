# Git support for the Java MCP workspace container

This is an opt-in rollout for `mcp-dev-workspace`, following the successful ChatGPT OAuth `workspace:read` E2E on Gateway v0.45.0. It does **not** change the Gateway, Redis, ChatGPT sessions, OAuth scopes, or the private workspace port.

## Why this is needed

The existing `eclipse-temurin:25-jre` container does not ship `git`. The Windows host's Git is not available inside Linux containers, and the `/projects` bind mount is an aggregate folder, not a Git repository. Git on Docker Desktop also sees host bind-mounted repositories as owned by uid 0, while the service runs as uid 10001:10001; without a narrowly scoped exception, Git reports `dubious ownership`.

This change builds a dedicated local runtime with Git. The Java application change (mcp-dev-workspace PR #99) passes `-c safe.directory=<configured canonical root>` **per invocation**, never `safe.directory=*` or a global Git trust exception.

## Registrations and containment

- `dev` -> `/projects`, `READ_ONLY`, retains bounded cross-repository navigation/search. It is not a Git root; `workspace.git_status(dev)` should return `NOT_A_GIT_REPOSITORY` rather than `GIT_OPERATION_FAILED` once Git is installed.
- `mcp-dev-workspace` -> `/projects/mcp-dev-workspace`, `TRUSTED`, enables bounded Git inspection and separately authorized file/task operations against this repo only.
- `/projects/mcp-dev-workspace` must exist in the host root mounted through `MCP_DEV_WORKSPACE_HOST_ROOT`. Missing roots fail closed at startup. For other layouts, adapt the explicit registration before applying.
- The bind mount remains private to the workspace container and Gateway private network. There is no new public port or capability grant.

## Controlled rollout

1. Complete CI/review for mcp-dev-workspace PR #99, build the matching Java 25 JAR, and verify its artifact version. Keep the old JAR available for rollback.
2. Review this infra PR and run `docker compose -f compose/docker-compose.yml --profile workspace config --quiet` using the existing operator environment. Do not print the fully expanded config (it may contain secrets).
3. Build the dedicated image from this repo root:

   ```powershell
   docker build --pull=false -t mcp-dev-workspace-java:25-git -f compose/mcp-dev-workspace-git.Dockerfile compose
   docker run --rm --entrypoint git mcp-dev-workspace-java:25-git --version
   ```

4. With the reviewed JAR at `MCP_DEV_WORKSPACE_JAR_PATH` and host root present, recreate **only** the workspace service:

   ```powershell
   docker compose -f compose/docker-compose.yml --profile workspace up -d --no-deps --build mcp-dev-workspace
   ```

5. Verify the service readiness and Gateway upstream; from the ChatGPT OAuth connection call `workspace.list`, `workspace.describe(mcp-dev-workspace)`, and `workspace.git_status(mcp-dev-workspace)`. The final command must return a bounded status payload (not `GIT_OPERATION_FAILED` or `dubious ownership`). Test denied operations under `dev` and verify audit correlation. Do not log credentials or raw host paths.
6. Recheck `gateway.explain_authorization(workspace.list)` under the canonical ChatGPT connection. Do not touch older connections until read + refresh E2E is separately verified.

## Rollback

Keep the Gateway and its OAuth tokens unchanged. If the new workspace service fails readiness/Git smoke, restore the previous pinned compose image/registration and Java JAR and recreate **only** `mcp-dev-workspace`. The old `dev` aggregate may still be used for read-only navigation. Do not revoke any OAuth link as part of this rollout.

## Local evidence (2 November 2026)

- Dedicated image built successfully using the reviewed Temurin 25 JRE base and Ubuntu packages: Git 2.53.0 available.
- Non-root disposable container with `/projects` mounted read-only: `git -C /projects/mcp-dev-workspace ...` failed with exit 128 (`dubious ownership`). The scoped command `git -c safe.directory=/projects/mcp-dev-workspace -C /projects/mcp-dev-workspace status --porcelain -uno` exited 0.
- Production Java service not replaced by this probe. OAuth v0.45.0 remains live.
