#!/usr/bin/env python3
"""repo_sandbox.run MVP (issue #221) — local prototype, not yet an MCP tool.

Implements the orchestration steps ADR 0020 describes for `repo_sandbox.run`:
checkout a repo at a ref into a temporary workspace, read
`.sandbox/manifest.yaml`, run one declared command group from one profile,
collect a structured result, and tear the workspace down.

What this is NOT (see docs/repo-sandbox-manifest.md "Current scope"): it does
not yet call mcp-code-sandbox's isolation layer (docker-socket-proxy,
network_mode="none"). `run_workspace` — the tool ADR 0020 proposes adding to
mcp-code-sandbox to provide that isolation — does not exist yet, so this
prototype runs the declared command as a plain subprocess on whatever host
invokes it, with a timeout and an environment stripped of inherited secrets.
This is the ADR's explicitly-authorized transitional state (Phased rollout
plan, step 4): a real MCP tool wired to actual container isolation is
follow-up work, not silently assumed to already exist here.

Never pushes, merges, publishes, deploys, or creates PRs — no such code path
exists in this script.
"""
from __future__ import annotations

import argparse
import getpass
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

# Only "safe-test" may be requested in this MVP (issue #221 acceptance
# criteria: "It refuses profiles other than safe-test in MVP").
ALLOWED_PROFILES_MVP = {"safe-test"}

# docs/repo-sandbox-security.md "Secrets policy": manifest env keys that look
# credential-shaped with a non-empty literal value are rejected at load time.
CREDENTIAL_KEY_PATTERN = re.compile(r"(_TOKEN|_KEY|_SECRET|_PASSWORD)$", re.IGNORECASE)

DEFAULT_TIMEOUT_SECONDS = 900


class SandboxError(Exception):
    """A refused/invalid request. Caught at the top level and turned into a
    structured ok=False result instead of propagating as a stack trace."""


@dataclass
class SandboxResult:
    ok: bool
    exit_code: int | None
    logs_uri: str | None
    artifacts: list[str]
    changed_files: list[str]
    duration_seconds: float
    error: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "ok": self.ok,
            "exit_code": self.exit_code,
            "logs_uri": self.logs_uri,
            "artifacts": self.artifacts,
            "changed_files": self.changed_files,
            "duration_seconds": round(self.duration_seconds, 3),
            "error": self.error,
        }


def _validate_manifest_env(manifest: dict) -> None:
    for profile_name, profile in (manifest.get("profiles") or {}).items():
        env = (profile or {}).get("env") or {}
        for key, value in env.items():
            if CREDENTIAL_KEY_PATTERN.search(str(key)) and value not in (None, ""):
                raise SandboxError(
                    f"manifest_rejected: profile '{profile_name}' env key '{key}' "
                    "looks credential-shaped with a literal value — not allowed "
                    "(see docs/repo-sandbox-security.md 'Secrets policy')"
                )


def _load_manifest(workspace: Path) -> dict:
    manifest_path = workspace / ".sandbox" / "manifest.yaml"
    if not manifest_path.exists():
        raise SandboxError(f"manifest_missing: {manifest_path} not found")
    with manifest_path.open("r", encoding="utf-8") as f:
        manifest = yaml.safe_load(f) or {}
    _validate_manifest_env(manifest)
    return manifest


def _run_git(args: list[str], cwd: Path, timeout: float = 30) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args],
        cwd=cwd,
        check=True,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def _resolve_workspace(repository: str, ref: str, workdir: Path) -> Path:
    """Check out `repository` at `ref` into workdir.

    `repository` is normally an `owner/repo` slug, cloned shallowly from
    GitHub. As a local-prototype convenience (not a production path), a local
    directory is accepted directly and copied in, with a throwaway git repo
    initialized over it so `changed_files` diffing works the same way for
    both cases — this is what the test suite's fixture repository uses.
    """
    local_path = Path(repository)
    dest = workdir / "repo"
    if local_path.is_dir():
        shutil.copytree(local_path, dest, ignore=shutil.ignore_patterns(".git"))
        _run_git(["init", "-q"], cwd=dest)
        _run_git(["add", "-A"], cwd=dest)
        _run_git(
            ["-c", "user.email=sandbox@local", "-c", "user.name=sandbox",
             "commit", "-q", "-m", "sandbox baseline"],
            cwd=dest,
        )
        return dest

    url = f"https://github.com/{repository}.git"
    subprocess.run(
        ["git", "clone", "--quiet", "--depth", "1", "--branch", ref, url, str(dest)],
        check=True,
        timeout=120,
    )
    return dest


def _find_command(manifest: dict, profile_name: str, command_group: str) -> tuple[str, dict]:
    profiles = manifest.get("profiles") or {}
    if profile_name not in profiles:
        raise SandboxError(f"profile_missing: '{profile_name}' not declared in manifest")
    profile_cfg = profiles[profile_name] or {}
    for entry in profile_cfg.get("commands") or []:
        if entry.get("name") == command_group:
            return entry["run"], profile_cfg
    raise SandboxError(
        f"command_group_missing: '{command_group}' not declared for profile '{profile_name}'"
    )


def _changed_files(workspace: Path) -> list[str]:
    try:
        result = _run_git(["status", "--porcelain"], cwd=workspace, timeout=10)
    except Exception:
        return []
    return [line[3:].strip() for line in result.stdout.splitlines() if line.strip()]


def _collect_artifacts(workspace: Path, patterns: list[str]) -> list[str]:
    found: list[str] = []
    for pattern in patterns:
        found.extend(str(p.relative_to(workspace)) for p in workspace.glob(pattern) if p.is_file())
    return found


def _audit(**fields: Any) -> None:
    """One JSON audit line per run, mirroring the gateway's mcp_gateway_audit
    pattern (docs/repo-sandbox-security.md 'Log policy')."""
    print(json.dumps({"event": "repo_sandbox_run_audit", **fields}), file=sys.stderr)


def _destroy_workspace(workdir: Path) -> None:
    """Best-effort but persistent workspace teardown.

    git creates read-only objects under .git/objects on Windows, which a
    plain shutil.rmtree refuses to delete (PermissionError). Clear the
    read-only bit and retry once per failing path instead of silently
    leaving the workspace behind with ignore_errors=True — a sandbox that
    fails to destroy its workspace is itself a policy violation (docs/
    repo-sandbox-security.md 'Filesystem policy').
    """

    def _on_rm_error(func, path, exc_info):  # noqa: ANN001
        try:
            os.chmod(path, stat.S_IWRITE)
            func(path)
        except OSError:
            pass

    shutil.rmtree(workdir, onerror=_on_rm_error)


def run_sandbox(
    *,
    repository: str,
    ref: str,
    profile: str,
    command_group: str,
    timeout_seconds: int = DEFAULT_TIMEOUT_SECONDS,
    actor: str | None = None,
) -> SandboxResult:
    started = time.monotonic()
    actor = actor or getpass.getuser()

    if profile not in ALLOWED_PROFILES_MVP:
        result = SandboxResult(
            ok=False, exit_code=None, logs_uri=None, artifacts=[], changed_files=[],
            duration_seconds=time.monotonic() - started,
            error=(
                f"profile_not_allowed: only {sorted(ALLOWED_PROFILES_MVP)} "
                f"supported in MVP, got '{profile}'"
            ),
        )
        _audit(repository=repository, ref=ref, profile=profile, command_group=command_group,
               actor=actor, **result.to_dict())
        return result

    workdir = Path(tempfile.mkdtemp(prefix="repo-sandbox-"))
    log_fd, log_path_str = tempfile.mkstemp(prefix="repo-sandbox-log-", suffix=".log")
    os.close(log_fd)
    log_path = Path(log_path_str)

    try:
        try:
            workspace = _resolve_workspace(repository, ref, workdir)
            manifest = _load_manifest(workspace)
            command, profile_cfg = _find_command(manifest, profile, command_group)
        except (SandboxError, subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            error = str(exc) if isinstance(exc, SandboxError) else f"checkout_failed: {exc}"
            result = SandboxResult(
                ok=False, exit_code=None, logs_uri=None, artifacts=[], changed_files=[],
                duration_seconds=time.monotonic() - started, error=error,
            )
            _audit(repository=repository, ref=ref, profile=profile, command_group=command_group,
                   actor=actor, **result.to_dict())
            return result

        manifest_timeout = profile_cfg.get("timeout_seconds")
        effective_timeout = (
            min(timeout_seconds, manifest_timeout) if manifest_timeout else timeout_seconds
        )

        exit_code: int | None
        error: str | None
        try:
            with log_path.open("w", encoding="utf-8") as log_file:
                proc = subprocess.run(
                    command,
                    shell=True,
                    cwd=workspace,
                    stdout=log_file,
                    stderr=subprocess.STDOUT,
                    timeout=effective_timeout,
                    # Deliberately not os.environ — no inherited secrets reach
                    # the sandboxed command (docs/repo-sandbox-security.md).
                    env={"PATH": os.environ.get("PATH", "")},
                )
            exit_code = proc.returncode
            error = None
        except subprocess.TimeoutExpired:
            exit_code = None
            error = f"timeout: exceeded {effective_timeout}s"

        changed = _changed_files(workspace)
        artifacts = _collect_artifacts(workspace, profile_cfg.get("output_files") or [])

        result = SandboxResult(
            ok=(exit_code == 0),
            exit_code=exit_code,
            logs_uri=f"file://{log_path}",
            artifacts=artifacts,
            changed_files=changed,
            duration_seconds=time.monotonic() - started,
            error=error,
        )
        _audit(repository=repository, ref=ref, profile=profile, command_group=command_group,
               actor=actor, **result.to_dict())
        return result
    finally:
        # Workspace is always destroyed, pass or fail or timeout — the log
        # file lives outside workdir so it survives this cleanup.
        _destroy_workspace(workdir)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True, help="owner/repo, or a local path for testing")
    parser.add_argument("--ref", default="main")
    parser.add_argument("--profile", default="safe-test")
    parser.add_argument("--command-group", required=True, dest="command_group")
    parser.add_argument("--timeout-seconds", type=int, default=DEFAULT_TIMEOUT_SECONDS, dest="timeout_seconds")
    args = parser.parse_args(argv)

    result = run_sandbox(
        repository=args.repository,
        ref=args.ref,
        profile=args.profile,
        command_group=args.command_group,
        timeout_seconds=args.timeout_seconds,
    )
    print(json.dumps(result.to_dict(), indent=2))
    return 0 if result.ok else 1


if __name__ == "__main__":
    sys.exit(main())
