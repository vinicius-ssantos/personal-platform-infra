"""Regression tests for the loopback Gateway wake proxy's idle lifecycle.

All subprocess calls and time sources are mocked. No Docker operations occur.
"""
from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock, patch


_SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "mcp-wake-proxy.py"
_SPEC = importlib.util.spec_from_file_location("gateway_wake_proxy_tested", _SCRIPT)
assert _SPEC is not None and _SPEC.loader is not None
wake = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(wake)


class _StopTestLoop(Exception):
    """Break the indefinite idle loop without modifying production code."""


class GatewayWakeProxyIdleTests(unittest.TestCase):
    def setUp(self) -> None:
        self.lifecycle = wake.Lifecycle()
        self.lifecycle.last_service = wake.SLOTS["blue"][0]
        self.lifecycle.last = 100.0

    def _one_idle_tick(self, now: float):
        with (
            patch.object(wake.time, "monotonic", return_value=now),
            patch.object(wake.time, "sleep", side_effect=[None, _StopTestLoop()]),
            patch.object(wake.subprocess, "run") as run,
        ):
            with self.assertRaises(_StopTestLoop):
                self.lifecycle.idle_loop()
            return run

    def test_default_idle_interval_is_fifteen_minutes(self) -> None:
        self.assertEqual(wake.IDLE_SECONDS, 900)

    def test_does_not_stop_selected_slot_before_idle_timeout(self) -> None:
        run = self._one_idle_tick(now=100.0 + wake.IDLE_SECONDS - 1.0)
        run.assert_not_called()

    def test_does_not_stop_during_an_active_request(self) -> None:
        self.lifecycle.active = 1
        run = self._one_idle_tick(now=100.0 + wake.IDLE_SECONDS + 100.0)
        run.assert_not_called()

    def test_after_idle_timeout_stops_last_used_slot_not_standby(self) -> None:
        now = 100.0 + wake.IDLE_SECONDS + 1.0
        run = self._one_idle_tick(now=now)
        run.assert_called_once()
        args, kwargs = run.call_args
        cmd = args[0]
        self.assertEqual(
            cmd[cmd.index("stop"):],
            ["stop", wake.SLOTS["blue"][0], *wake.CORE_SERVICES],
        )
        self.assertNotIn(wake.SLOTS["green"][0], cmd)
        self.assertEqual(kwargs["cwd"], wake.ROOT)
        self.assertEqual(kwargs["stdout"], wake.subprocess.DEVNULL)
        self.assertEqual(kwargs["stderr"], wake.subprocess.DEVNULL)
        self.assertEqual(self.lifecycle.last, now)

    def test_wake_and_release_hold_the_idle_gate_during_request(self) -> None:
        with (
            patch.object(wake.time, "monotonic", return_value=1200.0),
            patch.object(wake.subprocess, "run") as run,
        ):
            self.lifecycle.wake(wake.SLOTS["blue"][0])
            run.assert_called_once()
            cmd = run.call_args.args[0]
            self.assertEqual(
                cmd[cmd.index("up"):],
                ["up", "-d", "--wait", wake.SLOTS["blue"][0], *wake.CORE_SERVICES],
            )
            self.assertEqual(self.lifecycle.active, 1)
            self.assertEqual(self.lifecycle.last_service, wake.SLOTS["blue"][0])
            self.lifecycle.release()
            self.assertEqual(self.lifecycle.active, 0)
            self.assertEqual(self.lifecycle.last, 1200.0)


class GatewayWakeProxyRouteSafetyTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.state = Path(self.temp.name) / "slot.json"
        slot_patch = patch.object(wake, "SLOT_STATE", self.state)
        slot_patch.start()
        self.addCleanup(slot_patch.stop)

    def test_explicit_blue_green_and_legacy_are_supported(self) -> None:
        for slot in ("blue", "green", "legacy"):
            with self.subTest(slot=slot):
                self.state.write_text('{"slot":"' + slot + '"}', encoding="ascii")
                self.assertEqual(wake.active_slot(), wake.SLOTS[slot])

    def test_missing_state_is_denied(self) -> None:
        with self.assertRaises(wake.InvalidSlotState):
            wake.active_slot()

    def test_malformed_or_unknown_state_is_denied(self) -> None:
        for payload in (
            '{"slot":"unexpected"}', '{"slot":null}', "null", "[]", "{}",
            '{"slot":["legacy"]}', "{broken",
        ):
            with self.subTest(payload=payload):
                self.state.write_text(payload, encoding="ascii")
                with self.assertRaises(wake.InvalidSlotState):
                    wake.active_slot()

    def test_invalid_state_returns_generic_503_without_docker_or_secrets(self) -> None:
        self.state.write_text('{"slot":"private-route-name"}', encoding="ascii")
        send_error = Mock()
        request = SimpleNamespace(command="POST", path="/mcp", send_error=send_error)
        with patch.object(wake.LIFECYCLE, "wake") as docker_wake:
            wake.Handler.proxy(request)
        docker_wake.assert_not_called()
        send_error.assert_called_once_with(503, "mcp route unavailable")
        self.assertNotIn("private-route-name", str(send_error.call_args))
        self.assertNotIn(str(self.state), str(send_error.call_args))


if __name__ == "__main__":
    unittest.main()
