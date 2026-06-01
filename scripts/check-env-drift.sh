#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

python - <<'PY'
from __future__ import annotations

import re
import sys
from pathlib import Path

root = Path('.')
example_path = root / '.env.example'
compose_path = root / 'compose' / 'docker-compose.yml'
check_env_path = root / 'scripts' / 'check-env.sh'

errors: list[str] = []


def fail(message: str) -> None:
    errors.append(message)


def read(path: Path) -> str:
    if not path.exists():
        fail(f"missing required file: {path}")
        return ""
    return path.read_text(encoding='utf-8')

example = read(example_path)
compose = read(compose_path)
check_env = read(check_env_path)

example_keys = {
    match.group(1)
    for match in re.finditer(r"^([A-Za-z_][A-Za-z0-9_]*)=", example, re.MULTILINE)
}

compose_vars = {
    match.group(1)
    for match in re.finditer(r"\$\{([A-Za-z_][A-Za-z0-9_]*)(?::[-?][^}]*)?\}", compose)
}

required_block_match = re.search(r"required_keys=\(\s*(.*?)\s*\)", check_env, re.DOTALL)
if required_block_match:
    required_block = required_block_match.group(1)
    required_keys = {
        token
        for token in re.findall(r"\b[A-Z][A-Z0-9_]*\b", required_block)
    }
else:
    required_keys = set()
    fail("could not parse required_keys block from scripts/check-env.sh")

missing_from_example = sorted((compose_vars | required_keys) - example_keys)
if missing_from_example:
    fail(
        ".env.example is missing required key(s): "
        + ", ".join(missing_from_example)
    )

unused_required = sorted(required_keys - example_keys)
if unused_required:
    fail(
        "scripts/check-env.sh requires key(s) absent from .env.example: "
        + ", ".join(unused_required)
    )

print(f".env.example keys: {len(example_keys)}")
print(f"Compose interpolated vars: {len(compose_vars)}")
print(f"check-env required keys: {len(required_keys)}")

if compose_vars:
    print("Compose vars OK: " + ", ".join(sorted(compose_vars)))
if required_keys:
    print("Required keys OK: " + ", ".join(sorted(required_keys)))

if errors:
    for error in errors:
        print(f"ERROR: {error}", file=sys.stderr)
    sys.exit(1)

print("Environment drift check passed.")
PY
