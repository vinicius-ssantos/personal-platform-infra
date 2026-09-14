"""Focused contract checks without a Docker daemon."""
import importlib.util
import json
import os
from pathlib import Path
from unittest.mock import patch
from urllib.parse import parse_qs, urlparse

os.environ["SANDBOX_API_KEY"] = "test-token"
MODULE = Path(__file__).with_name("controller.py")
SPEC = importlib.util.spec_from_file_location("controller", MODULE)
controller = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(controller)


def test_container_uses_fixed_compose_labels() -> None:
    with patch.object(controller, "docker", return_value=(200, b'[{"Id":"abc"}]')) as docker:
        assert controller.container("mcp-code-sandbox") == "abc"
    query = parse_qs(urlparse(docker.call_args.args[1]).query)
    labels = json.loads(query["filters"][0])["label"]
    assert labels == ["com.docker.compose.project=compose", "com.docker.compose.service=mcp-code-sandbox"]


def test_missing_prepared_container_is_not_retargeted() -> None:
    with patch.object(controller, "docker", return_value=(200, b"[]")):
        try:
            controller.container("mcp-code-sandbox")
        except RuntimeError as error:
            assert str(error) == "sandbox_not_prepared"
        else:
            raise AssertionError("a missing sandbox must fail closed")
