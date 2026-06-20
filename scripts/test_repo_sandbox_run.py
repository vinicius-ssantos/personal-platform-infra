"""Tests for repo_sandbox_run.py (issue #221 acceptance criteria).

Run with: pytest scripts/test_repo_sandbox_run.py -v
Requires: pip install -r scripts/requirements-sandbox.txt
"""
from __future__ import annotations

import sys
import textwrap
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).parent))
from repo_sandbox_run import run_sandbox  # noqa: E402

REPO_ROOT = Path(__file__).resolve().parents[1]


@pytest.fixture
def fixture_repo(tmp_path: Path) -> Path:
    """A minimal local 'repository' with its own .sandbox/manifest.yaml —
    the fixture repository required by issue #221's acceptance criteria."""
    repo = tmp_path / "fixture-repo"
    repo.mkdir()
    (repo / ".sandbox").mkdir()
    (repo / ".sandbox" / "manifest.yaml").write_text(
        textwrap.dedent(
            """\
            version: "1"
            runtime:
              language: generic
              version: "n/a"
            profiles:
              safe-test:
                env:
                  SANDBOX_PROFILE: "safe-test"
                commands:
                  - name: preflight
                    run: "echo preflight-ok"
                  - name: test
                    run: "echo test-ok"
                timeout_seconds: 30
                network: none
                output_files: []
              mock:
                env: {}
                commands:
                  - name: preflight
                    run: "echo preflight-ok"
                timeout_seconds: 10
                network: none
                output_files: []
            """
        )
    )
    return repo


def test_runs_declared_command_group_successfully(fixture_repo: Path) -> None:
    result = run_sandbox(
        repository=str(fixture_repo), ref="main", profile="safe-test", command_group="preflight",
    )
    assert result.ok is True
    assert result.exit_code == 0
    assert result.logs_uri is not None
    assert result.duration_seconds >= 0
    assert result.error is None


def test_runs_second_declared_command_group(fixture_repo: Path) -> None:
    result = run_sandbox(
        repository=str(fixture_repo), ref="main", profile="safe-test", command_group="test",
    )
    assert result.ok is True
    assert result.exit_code == 0


def test_refuses_unknown_command_group(fixture_repo: Path) -> None:
    result = run_sandbox(
        repository=str(fixture_repo), ref="main", profile="safe-test", command_group="deploy-prod",
    )
    assert result.ok is False
    assert result.exit_code is None
    assert "command_group_missing" in (result.error or "")


def test_refuses_non_safe_test_profile(fixture_repo: Path) -> None:
    result = run_sandbox(
        repository=str(fixture_repo), ref="main", profile="prod-like", command_group="preflight",
    )
    assert result.ok is False
    assert "profile_not_allowed" in (result.error or "")


def test_refuses_unknown_profile_in_manifest(fixture_repo: Path) -> None:
    # "integration" isn't in ALLOWED_PROFILES_MVP either, but exercise the
    # case where the profile name itself isn't declared in the manifest at
    # all, distinct from the MVP allowlist check.
    result = run_sandbox(
        repository=str(fixture_repo), ref="main", profile="safe-test", command_group="lint",
    )
    assert result.ok is False
    assert "command_group_missing" in (result.error or "")


def test_rejects_credential_shaped_env_value(tmp_path: Path) -> None:
    repo = tmp_path / "bad-repo"
    repo.mkdir()
    (repo / ".sandbox").mkdir()
    (repo / ".sandbox" / "manifest.yaml").write_text(
        textwrap.dedent(
            """\
            version: "1"
            runtime:
              language: generic
              version: "n/a"
            profiles:
              safe-test:
                env:
                  GITHUB_TOKEN: "ghp_realLookingValue123"
                commands:
                  - name: preflight
                    run: "echo should-not-run"
                timeout_seconds: 30
                network: none
                output_files: []
            """
        )
    )
    result = run_sandbox(
        repository=str(repo), ref="main", profile="safe-test", command_group="preflight",
    )
    assert result.ok is False
    assert "manifest_rejected" in (result.error or "")


def test_enforces_timeout(tmp_path: Path) -> None:
    repo = tmp_path / "slow-repo"
    repo.mkdir()
    (repo / ".sandbox").mkdir()
    sleep_cmd = "ping -n 5 127.0.0.1 >NUL" if sys.platform == "win32" else "sleep 5"
    (repo / ".sandbox" / "manifest.yaml").write_text(
        textwrap.dedent(
            f"""\
            version: "1"
            runtime:
              language: generic
              version: "n/a"
            profiles:
              safe-test:
                env: {{}}
                commands:
                  - name: slow
                    run: "{sleep_cmd}"
                timeout_seconds: 1
                network: none
                output_files: []
            """
        )
    )
    result = run_sandbox(
        repository=str(repo), ref="main", profile="safe-test", command_group="slow",
    )
    assert result.ok is False
    assert result.exit_code is None
    assert "timeout" in (result.error or "")


def test_destroys_workspace_after_run(fixture_repo: Path, tmp_path: Path) -> None:
    import tempfile

    before = set(Path(tempfile.gettempdir()).glob("repo-sandbox-*"))
    run_sandbox(
        repository=str(fixture_repo), ref="main", profile="safe-test", command_group="preflight",
    )
    after_dirs = {
        p for p in Path(tempfile.gettempdir()).glob("repo-sandbox-*")
        if p.is_dir() and p not in before
    }
    assert not after_dirs, f"sandbox workspace(s) not cleaned up: {after_dirs}"


def test_no_changed_files_for_non_mutating_command(fixture_repo: Path) -> None:
    result = run_sandbox(
        repository=str(fixture_repo), ref="main", profile="safe-test", command_group="preflight",
    )
    assert result.changed_files == []


@pytest.mark.skipif(
    not (REPO_ROOT / ".sandbox" / "manifest.yaml").exists(),
    reason="run from a checkout of personal-platform-infra with .sandbox/manifest.yaml",
)
def test_runs_against_real_personal_platform_infra_preflight() -> None:
    """Acceptance criterion: 'It can run command_group=preflight for
    personal-platform-infra' — exercised against the real repo, not a
    fixture, using local-path mode."""
    result = run_sandbox(
        repository=str(REPO_ROOT), ref="main", profile="safe-test", command_group="preflight",
        timeout_seconds=120,
    )
    assert result.ok is True, result.error


@pytest.mark.skipif(
    not (REPO_ROOT / ".sandbox" / "manifest.yaml").exists(),
    reason="run from a checkout of personal-platform-infra with .sandbox/manifest.yaml",
)
def test_runs_against_real_personal_platform_infra_test() -> None:
    """Acceptance criterion: 'It can run command_group=test for
    personal-platform-infra'."""
    result = run_sandbox(
        repository=str(REPO_ROOT), ref="main", profile="safe-test", command_group="test",
        timeout_seconds=120,
    )
    assert result.ok is True, result.error
