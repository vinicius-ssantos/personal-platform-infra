# Safe first execution task for `mcp-dev-workspace`

The Java workspace server has a fail-closed task registry. Without an operator-controlled
task policy, `workspace.task_list(mcp-dev-workspace)` correctly returns an empty list,
even though the MCP protocol exposes `task_run` and `validate`.

This change registers **one** bounded, one-shot server task only for the separately
trusted `mcp-dev-workspace` repository. No arbitrary command, shell, environment
variable, repository-controlled `.mcp-workspace.yml`, or Maven runner is enabled.

| Setting | Value |
| --- | --- |
| Workspace | `mcp-dev-workspace` (`TRUSTED`) |
| TaskId | `java-version` |
| Literal argv | `/opt/java/openjdk/bin/java --version` |
| Timeout | 10s |
| Environment | Empty |
| Persistent | false |
| Validation | `java-version` only |
| Aggregate `dev` workspace | remains `READ_ONLY`, without any registered tasks |

The task runs in the already isolated Java container with user `10001:10001`,
read-only root filesystem, `cap_drop: ALL`, no host-published workspace
port and only the private `workspace-private` network. It cannot build Maven
projects and is not a substitute for a separate build runner.

## Deployment and acceptance

1. Confirm that both this infrastructure PR and the Java capability-description
   PR have CI and reviews approved. Validate the rendered Compose against
   `scripts/verify_workspace_private_topology.py` *without printing env*.
2. Keep the previous JAR/image/Compose state available for rollback. Recreate
   **only** `mcp-dev-workspace`, not Gateway/Redis/other upstreams.
3. From the existing ChatGPT OAuth connection, run
   `workspace.list`, `workspace.describe(dev)`,
   `workspace.task_list(dev)`, and `workspace.task_list(mcp-dev-workspace)`.
   Only the trusted repo must expose task `java-version`.
4. Call `workspace.task_run(mcp-dev-workspace, java-version)` and
   `workspace.validate(mcp-dev-workspace)` **only after completing any
   explicit tool confirmation**. Do not bypass a `CONFIRMATION_REQUIRED`
   response with direct raw MCP HTTP, bearer reuse or an alternate connector.
5. Inspect bounded output: only a Java version should appear, never credentials,
   filesystem roots or arbitrary environment. Confirm read-only `dev` task
   execution is denied before child-process launch. Verify Git and read MCP
   calls still work after service recreation.
6. For file write E2E, prepare an isolated disposable repository/workspace
   separate from the live source tree, with a uniquely named file and rollback.
   Do not create test files in `dev` or the live source repository.

## Further work

Running Maven tests from the ChatGPT MCP requires a **separate build runtime**
with Maven and JDK, narrowly registered command shapes and controlled
network/filesystem access. Do **not** mount the Docker socket into the workspace
container or activate arbitrary `exec` / raw shell tasks to accomplish this.

Related work: [mcp-dev-workspace #85](https://github.com/vinicius-ssantos/mcp-dev-workspace/issues/85).
