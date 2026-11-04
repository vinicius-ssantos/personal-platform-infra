"""Compose owner identity opt-in is fail-closed and cannot elevate by OAuth client ID.

All cases use fabricated values and invoke only the entrypoint shell with a
synthetic print probe. No Gateway, Redis, OAuth or external service is called.
"""
from __future__ import annotations

import os
import re
import subprocess
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
COMPOSE = ROOT / "compose" / "docker-compose.yml"


def gateway_command() -> str:
    compose = yaml.safe_load(COMPOSE.read_text(encoding="utf-8"))
    command = compose["services"]["central-mcp-gateway"]["command"][0]
    assert command.count("exec central-mcp-gateway") == 1
    return command


def run_fixture(*, enabled: str, subjects: str) -> subprocess.CompletedProcess[str]:
    probe = (
        'if env | grep -q "^GATEWAY_OWNER_SUBJECTS="; then '
        'echo "OWNER_SUBJECTS_PRESENT=yes"; else echo "OWNER_SUBJECTS_PRESENT=no"; fi; '
        'if [ "$GATEWAY_OWNER_SUBJECTS" = "oauth:owner" ]; then '
        'echo "EXPECTED_SUBJECT_MATCH=yes"; '
        'else echo "EXPECTED_SUBJECT_MATCH=no"; fi; '
        'if env | grep -q "^GATEWAY_OWNER_SUBJECTS_FORWARD_ENABLED="; then '
        'echo "INTERNAL_FLAG_LEAKED=yes"; else echo "INTERNAL_FLAG_LEAKED=no"; fi'
    )
    command = gateway_command().replace("exec central-mcp-gateway", probe)
    # Docker Compose resolves doubled dollar signs before the container shell.
    command = command.replace("$$", "$")
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "GATEWAY_TOOL_ALLOWLIST": "gateway.status",
        "GATEWAY_OAUTH_DEFAULT_SCOPES": "gateway:read",
        "GATEWAY_OAUTH_ALLOWED_SCOPES": "",
        "GATEWAY_OAUTH_SCOPE_SPLIT_ENABLED": "false",
        "GATEWAY_WORKSPACE_OWNER_TOOLS_ENABLED": "false",
        "GATEWAY_OAUTH_ALLOWED_REDIRECT_URIS": "",
        "GATEWAY_OWNER_SUBJECTS_FORWARD_ENABLED": enabled,
        "GATEWAY_OWNER_SUBJECTS": subjects,
        "GATEWAY_OWNER_CLIENT_IDS": "chatgpt",
    }
    return subprocess.run(
        ["sh", "-ec", command],
        env=env, text=True, capture_output=True, check=False, timeout=10
    )


class GatewayOwnerSubjectsComposeTests(unittest.TestCase):
    def test_opt_in_is_disabled_in_rendered_compose_by_default(self) -> None:
        compose = yaml.safe_load(COMPOSE.read_text(encoding="utf-8"))
        env = compose["services"]["central-mcp-gateway"]["environment"]
        self.assertEqual(
            env["GATEWAY_OWNER_SUBJECTS_FORWARD_ENABLED"],
            "${GATEWAY_OWNER_SUBJECTS_FORWARD_ENABLED:-false}",
        )
        self.assertEqual(env["GATEWAY_OWNER_SUBJECTS"], "${GATEWAY_OWNER_SUBJECTS:-}")

    def test_entrypoint_keeps_shell_variables_escaped_for_compose(self) -> None:
        self.assertIsNone(re.search(r"(?<!\$)\$(?!\$)", gateway_command()))

    def test_disabled_mode_drops_subject_even_if_env_contains_one(self) -> None:
        result = run_fixture(enabled="false", subjects="oauth:owner")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("OWNER_SUBJECTS_PRESENT=no", result.stdout)
        self.assertIn("INTERNAL_FLAG_LEAKED=no", result.stdout)

    def test_enabled_mode_forwards_explicit_subject_only(self) -> None:
        result = run_fixture(enabled="true", subjects="oauth:owner")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("OWNER_SUBJECTS_PRESENT=yes", result.stdout)
        self.assertIn("EXPECTED_SUBJECT_MATCH=yes", result.stdout)
        self.assertIn("INTERNAL_FLAG_LEAKED=no", result.stdout)

    def test_enabled_with_no_subject_fails_closed(self) -> None:
        result = run_fixture(enabled="true", subjects="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("needs an explicit subject", result.stderr)

    def test_invalid_flag_fails_closed(self) -> None:
        result = run_fixture(enabled="treu", subjects="oauth:owner")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("flag must be true or false", result.stderr)


if __name__ == "__main__":
    unittest.main()
