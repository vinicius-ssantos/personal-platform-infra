"""Offline fail-closed blue/green preflight regression tests.

The child PowerShell process overrides docker, git, and Invoke-RestMethod
with in-memory fakes. It only reads synthetic temporary state and can never
connect to production infrastructure or load the real .env.
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PREFLIGHT = ROOT / "scripts" / "gateway-bluegreen-preflight.ps1"
SHELL = shutil.which("pwsh") or shutil.which("powershell.exe")

HARNESS = r"""
$ErrorActionPreference = 'Stop'
function docker {
    if (@($args) -notcontains 'config') { throw 'UNSAFE_DOCKER_ACTION' }
    $global:LASTEXITCODE = 0
    $blue = 'ghcr.io/vinicius-ssantos/central-mcp-gateway:v0.46.3'
    if ($env:MOCK_BAD_BLUE -eq '1') {
        $blue = 'ghcr.io/vinicius-ssantos/central-mcp-gateway:v0.42.0'
    }
    if ($env:MOCK_CHANGE_ACTIVE -eq '1' -and $env:CENTRAL_MCP_GATEWAY_GREEN_IMAGE) {
        $blue = 'ghcr.io/vinicius-ssantos/central-mcp-gateway:v0.47.0'
    }
    $green = 'ghcr.io/vinicius-ssantos/central-mcp-gateway:v0.45.0'
    if ($env:MOCK_IGNORE_OVERRIDE -ne '1' -and $env:CENTRAL_MCP_GATEWAY_GREEN_IMAGE) {
        $green = $env:CENTRAL_MCP_GATEWAY_GREEN_IMAGE
    }
    return (@{services=@{
        'central-mcp-gateway-blue'=@{image=$blue}
        'central-mcp-gateway-green'=@{image=$green}
    }} | ConvertTo-Json -Depth 4 -Compress)
}
function git {
    $global:LASTEXITCODE = 0
    if ($env:MOCK_DIRTY_COMPOSE -eq '1') {
        ' M compose/docker-compose.yml'
    }
}
function Invoke-RestMethod {
    param([string]$Uri, [int]$TimeoutSec)
    if ($Uri -match '8041') {
        return @{status='ready';runtime=@{version='0.46.3'}}
    }
    if ($Uri -match '8042') {
        if ($env:MOCK_GREEN_UNHEALTHY -eq '1') { throw 'green down' }
        return @{status='ready';runtime=@{version='0.45.0'}}
    }
    throw 'UNEXPECTED_REMOTE_REQUEST'
}
& '__PREFLIGHT__' -InfraRoot '__ROOT__' -Target '__TARGET__' -ExpectedActive 'blue' -CandidateTag v0.47.0
"""


@unittest.skipUnless(SHELL, "PowerShell is needed for offline preflight tests")
class GatewayBlueGreenPreflightTests(unittest.TestCase):
    def setUp(self) -> None:
        temporary = tempfile.TemporaryDirectory(prefix="gateway-preflight-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.infra = self.root / "infra"
        (self.infra / "compose").mkdir(parents=True)
        (self.infra / "scripts").mkdir(parents=True)
        (self.infra / "compose" / "docker-compose.yml").write_text(
            "services: {}\n", encoding="utf-8"
        )
        (self.infra / ".env").write_text(
            "FIXTURE_ONLY=1\n", encoding="utf-8"
        )
        self.state_dir = self.root / "appdata" / "personal-platform"
        self.state_dir.mkdir(parents=True)
        self.set_active_slot("blue")

    def set_active_slot(self, slot: str) -> None:
        (self.state_dir / "gateway-slot.json").write_text(
            '{"slot":"' + slot + '"}', encoding="utf-8"
        )

    def run_case(
        self, *,
        target: str = "green",
        dirty: bool = False,
        green_unhealthy: bool = False,
        bad_blue: bool = False,
        ignore_override: bool = False,
        change_active: bool = False,
    ) -> subprocess.CompletedProcess[str]:
        harness = (
            HARNESS.replace("__PREFLIGHT__", PREFLIGHT.as_posix().replace("'", "''"))
            .replace("__ROOT__", self.infra.as_posix().replace("'", "''"))
            .replace("__TARGET__", target)
        )
        harness_file = self.root / "harness.ps1"
        harness_file.write_text(harness, encoding="utf-8")
        env = dict(os.environ)
        env.update(
            {
                "LOCALAPPDATA": str(self.root / "appdata"),
                "MOCK_DIRTY_COMPOSE": str(int(dirty)),
                "MOCK_GREEN_UNHEALTHY": str(int(green_unhealthy)),
                "MOCK_BAD_BLUE": str(int(bad_blue)),
                "MOCK_IGNORE_OVERRIDE": str(int(ignore_override)),
                "MOCK_CHANGE_ACTIVE": str(int(change_active)),
                "GATEWAY_PRIVATE_TOKEN": "synthetic-secret-not-in-output",
            }
        )
        # Prevent an inherited CI/process override from altering the fixture.
        env.pop("CENTRAL_MCP_GATEWAY_GREEN_IMAGE", None)
        result = subprocess.run(
            [SHELL, "-NoProfile", "-NonInteractive", "-File", str(harness_file)],
            env=env,
            cwd=self.root,
            capture_output=True,
            text=True,
            timeout=15,
            check=False,
        )
        self.assertNotIn("synthetic-secret-not-in-output", result.stdout)
        self.assertNotIn("synthetic-secret-not-in-output", result.stderr)
        return result

    def assert_blocked(
        self, result: subprocess.CompletedProcess[str], reason: str
    ) -> None:
        self.assertEqual(result.returncode, 2, result.stdout + result.stderr)
        self.assertIn("PREFLIGHT=BLOCKED", result.stdout)
        self.assertIn("REASON=" + reason, result.stdout)
        self.assertNotIn("PREFLIGHT=PASS_READ_ONLY", result.stdout)

    def test_clean_inactive_slot_is_safe_for_read_only_preflight(self) -> None:
        result = self.run_case()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("ACTIVE_SLOT=blue", result.stdout)
        self.assertIn("BLUE_READY_VERSION=0.46.3", result.stdout)
        self.assertIn("GREEN_READY_VERSION=0.45.0", result.stdout)
        self.assertIn("CANDIDATE_TAG=v0.47.0", result.stdout)
        self.assertIn("PREFLIGHT=PASS_READ_ONLY", result.stdout)
        self.assertIn("REQUIRES_SEPARATE_OPERATOR_APPROVAL=TRUE", result.stdout)

    def test_dirty_compose_blocks_promotion(self) -> None:
        self.assert_blocked(
            self.run_case(dirty=True), "DEPLOYMENT_CONFIG_HAS_UNREVIEWED_LOCAL_CHANGES"
        )

    def test_wrong_active_slot_blocks_promotion(self) -> None:
        self.set_active_slot("green")
        self.assert_blocked(
            self.run_case(), "UNEXPECTED_ACTIVE_OR_TARGET_SLOT"
        )

    def test_targeting_the_active_slot_is_rejected(self) -> None:
        self.assert_blocked(
            self.run_case(target="blue"), "UNEXPECTED_ACTIVE_OR_TARGET_SLOT"
        )

    def test_unhealthy_standby_is_rejected(self) -> None:
        self.assert_blocked(
            self.run_case(green_unhealthy=True), "GATEWAY_GREEN_NOT_READY"
        )

    def test_existing_compose_image_mismatch_is_rejected(self) -> None:
        self.assert_blocked(
            self.run_case(bad_blue=True), "RUNNING_VERSION_AND_COMPOSE_IMAGE_MISMATCH"
        )

    def test_candidate_override_must_be_honored(self) -> None:
        self.assert_blocked(
            self.run_case(ignore_override=True), "CANDIDATE_IMAGE_RESOLUTION_MISMATCH"
        )

    def test_candidate_must_not_change_active_image(self) -> None:
        self.assert_blocked(
            self.run_case(change_active=True), "ACTIVE_SLOT_WOULD_CHANGE"
        )

    def test_missing_environment_is_rejected(self) -> None:
        (self.infra / ".env").unlink()
        self.assert_blocked(self.run_case(), "ENV_FILE_MISSING")

    def test_missing_active_state_is_rejected(self) -> None:
        (self.state_dir / "gateway-slot.json").unlink()
        self.assert_blocked(
            self.run_case(), "ACTIVE_SLOT_STATE_MISSING"
        )


if __name__ == "__main__":
    unittest.main()
