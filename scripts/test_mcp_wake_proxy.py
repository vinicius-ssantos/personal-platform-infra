import importlib.util
from pathlib import Path

spec = importlib.util.spec_from_file_location("wake", Path(__file__).with_name("mcp-wake-proxy.py"))
wake = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(wake)


def test_public_route_allowlist_is_fail_closed() -> None:
    assert wake.allowed("POST", "/mcp")
    assert wake.allowed("GET", "/oauth/authorize")
    assert not wake.allowed("GET", "/mcp")
    assert not wake.allowed("POST", "/gateway/admin")
    assert not wake.allowed("POST", "/runner-autoscaler/webhook")
