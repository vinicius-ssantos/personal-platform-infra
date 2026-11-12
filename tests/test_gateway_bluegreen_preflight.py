"""Offline regression tests for Gateway blue/green preflight safety gates.

All dependencies are mocked in a temporary PowerShell session. These tests
never connect to Docker, GitHub, localhost, or a real deployment directory.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SCRIPT = REPO_ROOT / "scripts" / "gateway-bluegreen-preflight.ps1"

# Defined in the subprocess before invoking the actual preflight script.
# Fail closed if the script invokes an unexpected method / endpoint.
POWERSHELL_MOCK = r"""
$ErrorActionPreference = 'Stop'
function Invoke-RestMethod {
  param([string]$Uri, [int]$TimeoutSec)
  if ($Uri -eq 'http://127.0.0.1:8041/readyz') {
    if ($env:M4_UNHEALTHY_BLUE -eq '1') { throw 'synthetic unavailable' }
    return @{status='ready';runtime=@{version='0.46.3'}}
  }
  if ($Uri -eq 'http://127.0.0.1:8042/readyz') {
    if ($env:M4_UNHEALTHY_GREEN -eq '1') { throw 'synthetic unavailable' }
    return @{status='ready';runtime=@{version='0.45.0'}}
  }
  throw 'FORBIDDEN NETWORK CALL'
}
function docker {
  $argsText = ($args -join ' ')
  if ($argsText -notmatch 'config --format json') { throw 'FORBIDDEN DOCKER OPERATION' }
  $global:LASTEXITCODE=0
  $green='ghcr.io/vinicius-ssantos/central-mcp-gateway:v0.45.0'
  if ($env:CENTRAL_MCP_GATEWAY_GREEN_IMAGE) {
    if ($env:M4_IGNORE_OVERRIDE -ne '1') {
      $green = $env:CENTRAL_MCP_GATEWAY_GREEN_IMAGE
    }
  }
  $blue='ghcr.io/vinicius-ssantos/central-mcp-gateway:v0.46.3'
  if ($env:M4_WRONG_IMAGE -eq '1') {$blue='ghcr.io/vinicius-ssantos/central-mcp-gateway:v0.40.0'}
  if ($env:M4_MUTATE_ACTIVE -eq '1' -and $env:CENTRAL_MCP_GATEWAY_GREEN_IMAGE) {
    $blue='ghcr.io/vinicius-ssantos/central-mcp-gateway:v0.47.0'
  }
  return (@{services=@{
    'central-mcp-gateway-blue'=@{image=$blue};
    'central-mcp-gateway-green'=@{image=$green}
  }}|ConvertTo-Json -Depth 5 -Compress)
}
function git {
  $argsText=($args -join ' ')
  if ($argsText -notmatch 'status --porcelain') {throw 'FORBIDDEN GIT OPERATION'}
  $global:LASTEXITCODE=0
  if ($env:M4_DIRTY_COMPOSE -eq '1') {Write-Output ' M compose/docker-compose.yml'}
}
& $env:M4_PREFLIGHT_SCRIPT -InfraRoot $env:M4_TEST_ROOT -Target $env:M4_TARGET_SLOT -ExpectedActive blue -CandidateTag v0.47.0
exit $LASTEXITCODE
"""


class GatewayBlueGreenPreflightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.shell = shutil.which("pwsh") or shutil.which("powershell.exe")
        if cls.shell is None:
            raise unittest.SkipTest("PowerShell unavailable; the CI PowerShell step must install it")

    def run_case(
        self, *, flag: str | None = None, expected_exit: int = 2,
        expected_reason: str | None = None, active: str = "blue",
        missing_env: bool = False, missing_state: bool = False,
        target: str = "green",
    ) -> str:
        with tempfile.TemporaryDirectory(prefix="m4-preflight-mock-") as tmp:
            root = Path(tmp)
            (root / "compose").mkdir()
            (root / "scripts").mkdir()
            if not missing_env:
                (root / ".env").write_text("# synthetic\n", encoding="utf-8")
            appdata = root / "appdata"
            state_dir = appdata / "personal-platform"
            state_dir.mkdir(parents=True)
            if not missing_state:
                (state_dir / "gateway-slot.json").write_text(
                    '{"slot":"' + active + '"}', encoding="utf-8"
                )
            harness = root / "mock.ps1"
            harness.write_text(POWERSHELL_MOCK, encoding="utf-8")
            env = os.environ.copy()
            # Force deterministic test inputs even on a developer's machine.
            for key in list(env):
                if key.startswith("M4_") or key.startswith("CENTRAL_MCP_GATEWAY_"):
                    env.pop(key)
            env.update({
                "LOCALAPPDATA": str(appdata),
                "M4_PREFLIGHT_SCRIPT": str(SCRIPT),
                "M4_TEST_ROOT": str(root),
                "M4_TARGET_SLOT": target,
                "M4_SENTINEL_SECRET": "synthetic-private-secret",
            })
            if flag:
                env[flag] = "1"
            completed = subprocess.run(
                [self.shell, "-NoProfile", "-File", str(harness)],
                capture_output=True, text=True, timeout=25, check=False, env=env
            )
            # Diagnostics must not expose secret environment values.
            self.assertNotIn("synthetic-private-secret", completed.stdout)
            self.assertNotIn("synthetic-private-secret", completed.stderr)
            self.assertEqual(
                completed.returncode, expected_exit,
                f"Unexpected exit {completed.returncode}: "
                f"{completed.stdout[-1600:]} {completed.stderr[-300:]}",
            )
            if expected_exit == 0:
                self.assertIn("PREFLIGHT=PASS_READ_ONLY", completed.stdout)
                self.assertIn("REQUIRES_SEPARATE_OPERATOR_APPROVAL=TRUE", completed.stdout)
            else:
                self.assertIn("PREFLIGHT=BLOCKED", completed.stdout)
                self.assertIn("REASON=" + str(expected_reason), completed.stdout)
            return completed.stdout

    def test_clean_fixture_passes_without_promotion(self) -> None:
        self.run_case(expected_exit=0)

    def test_dirty_compose_blocks(self) -> None:
        self.run_case(
            flag="M4_DIRTY_COMPOSE",
            expected_reason="DEPLOYMENT_CONFIG_HAS_UNREVIEWED_LOCAL_CHANGES",
        )

    def test_unhealthy_inactive_slot_blocks(self) -> None:
        self.run_case(flag="M4_UNHEALTHY_GREEN", expected_reason="GATEWAY_GREEN_NOT_READY")

    def test_unexpected_active_slot_blocks(self) -> None:
        self.run_case(active="green", expected_reason="UNEXPECTED_ACTIVE_OR_TARGET_SLOT")

    def test_deployed_image_mismatch_blocks(self) -> None:
        self.run_case(
            flag="M4_WRONG_IMAGE",
            expected_reason="RUNNING_VERSION_AND_COMPOSE_IMAGE_MISMATCH",
        )

    def test_candidate_image_not_interpolated_blocks(self) -> None:
        self.run_case(
            flag="M4_IGNORE_OVERRIDE", expected_reason="CANDIDATE_IMAGE_RESOLUTION_MISMATCH"
        )

    def test_missing_env_file_blocks(self) -> None:
        self.run_case(missing_env=True, expected_reason="ENV_FILE_MISSING")

    def test_target_cannot_be_active_slot(self) -> None:
        self.run_case(target="blue", expected_reason="UNEXPECTED_ACTIVE_OR_TARGET_SLOT")

    def test_candidate_cannot_change_active_slot_image(self) -> None:
        self.run_case(flag="M4_MUTATE_ACTIVE", expected_reason="ACTIVE_SLOT_WOULD_CHANGE")

    def test_missing_active_slot_state_blocks(self) -> None:
        self.run_case(missing_state=True, expected_reason="ACTIVE_SLOT_STATE_MISSING")


if __name__ == "__main__":
    unittest.main()
