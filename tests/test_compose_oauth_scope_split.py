"""Exercise the Compose Gateway entrypoint with synthetic OAuth scope fixtures.

No MCP server is started. Only a sanitized shell script from the checked-in
Compose file is evaluated with dummy environment variables.
"""

from __future__ import annotations

import os
import subprocess
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parents[1]
COMPOSE = ROOT / "compose" / "docker-compose.yml"


def entrypoint_script() -> str:
    compose = yaml.safe_load(COMPOSE.read_text(encoding="utf-8"))
    gateway = compose["services"]["central-mcp-gateway"]
    script = gateway["command"][0]
    assert script.count("exec central-mcp-gateway") == 1
    probe = (
        'printf "DEFAULT=%s\\nALLOWED=%s\\n" '
        '"$GATEWAY_OAUTH_DEFAULT_SCOPES" "$GATEWAY_OAUTH_ALLOWED_SCOPES"; '
        'if env | grep -q "^GATEWAY_OAUTH_ALLOWED_SCOPES="; then '
        'echo "ALLOWED_PRESENT=yes"; else echo "ALLOWED_PRESENT=no"; fi'
    )
    # Docker Compose converts escaped $$ to $ before invoking the shell.
    return script.replace("exec central-mcp-gateway", probe).replace("$$", "$")


def run_fixture(*, split: bool, owner: bool, defaults: str, allowed: str) -> subprocess.CompletedProcess[str]:
    env = {
        "PATH": os.environ.get("PATH", "/usr/bin:/bin"),
        "GATEWAY_OAUTH_DEFAULT_SCOPES": defaults,
        "GATEWAY_OAUTH_ALLOWED_SCOPES": allowed,
        "GATEWAY_OAUTH_SCOPE_SPLIT_ENABLED": str(split).lower(),
        "GATEWAY_WORKSPACE_OWNER_TOOLS_ENABLED": str(owner).lower(),
        "GATEWAY_TOOL_ALLOWLIST": "gateway.status",
        "GATEWAY_OAUTH_ALLOWED_REDIRECT_URIS": "",
    }
    return subprocess.run(
        ["sh", "-ec", entrypoint_script()],
        env=env,
        text=True,
        capture_output=True,
        check=False,
        timeout=10,
    )


class OAuthScopeSplitComposeTests(unittest.TestCase):
    def test_legacy_owner_mode_preserves_defaults_and_unsets_allowed(self) -> None:
        result = run_fixture(
            split=False, owner=True,
            defaults="gateway:read", allowed="gateway:read workspace:write",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("DEFAULT=gateway:read workspace:read workspace:write workspace:execute", result.stdout)
        self.assertIn("ALLOWED_PRESENT=no", result.stdout)

    def test_split_owner_mode_keeps_write_execute_explicit_only(self) -> None:
        result = run_fixture(
            split=True, owner=True,
            defaults="gateway:read",
            allowed="gateway:read workspace:read workspace:write workspace:execute",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("DEFAULT=gateway:read workspace:read", result.stdout)
        self.assertNotIn("DEFAULT=gateway:read workspace:read workspace:write", result.stdout)
        self.assertIn("ALLOWED_PRESENT=yes", result.stdout)

    def test_split_read_only_mode_without_owner_tools(self) -> None:
        result = run_fixture(
            split=True, owner=False,
            defaults="gateway:read", allowed="gateway:read workspace:read",
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("DEFAULT=gateway:read workspace:read", result.stdout)
        self.assertIn("ALLOWED_PRESENT=yes", result.stdout)

    def test_split_requires_explicit_allowed_scope_list(self) -> None:
        result = run_fixture(split=True, owner=False, defaults="gateway:read", allowed="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires an explicit allowed-scope list", result.stderr)

    def test_split_requires_workspace_read_in_allowed(self) -> None:
        result = run_fixture(
            split=True, owner=False,
            defaults="gateway:read", allowed="gateway:read workspace:execute",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must include workspace:read", result.stderr)

    def test_split_denies_implicit_write_or_execute(self) -> None:
        for scope in ("workspace:write", "workspace:execute"):
            with self.subTest(scope=scope):
                result = run_fixture(
                    split=True, owner=True,
                    defaults=f"gateway:read {scope}",
                    allowed="gateway:read workspace:read workspace:write workspace:execute",
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("defaults cannot grant", result.stderr)

    def test_split_owner_tools_require_explicit_write_and_execute_allowed(self) -> None:
        result = run_fixture(
            split=True, owner=True,
            defaults="gateway:read",
            allowed="gateway:read workspace:read workspace:write",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing owner workspace capability", result.stderr)


if __name__ == "__main__":
    unittest.main()
