import importlib.util
from pathlib import Path

import pytest

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


def test_upstream_headers_preserves_host_and_removes_connection() -> None:
    headers = wake.upstream_headers({"Host": "gateway.example", "Connection": "keep-alive"})
    assert headers == {"Host": "gateway.example"}


@pytest.mark.parametrize(
    ("slot", "expected"),
    [
        ("blue", ("central-mcp-gateway-blue", 8041)),
        ("green", ("central-mcp-gateway-green", 8042)),
        ("legacy", ("central-mcp-gateway", 8040)),
    ],
)
def test_explicit_slot_is_honored(tmp_path, monkeypatch, slot, expected) -> None:
    monkeypatch.setattr(wake, "SLOT_STATE", tmp_path / "slot.json")
    wake.SLOT_STATE.write_text('{"slot":"' + slot + '"}', encoding="ascii")
    assert wake.active_slot() == expected


@pytest.mark.parametrize("content", [
    '{"slot":"external"}', '{"slot":null}', '{}', '[]', 'null',
    '{"slot":["legacy"]}', '{broken',
])
def test_missing_or_invalid_slot_denied(tmp_path, monkeypatch, content) -> None:
    monkeypatch.setattr(wake, "SLOT_STATE", tmp_path / "slot.json")
    wake.SLOT_STATE.write_text(content, encoding="ascii")
    with pytest.raises(wake.InvalidSlotState):
        wake.active_slot()


def test_missing_slot_state_denied(tmp_path, monkeypatch) -> None:
    monkeypatch.setattr(wake, "SLOT_STATE", tmp_path / "missing.json")
    with pytest.raises(wake.InvalidSlotState):
        wake.active_slot()
