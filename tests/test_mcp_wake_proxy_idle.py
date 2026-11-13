"""Regression tests for the loopback Gateway wake proxy's idle lifecycle.

All subprocess calls and time sources are mocked. No Docker operations occur.
"""
from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path
from unittest.mock import patch


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


if __name__ == "__main__":
    unittest.main()
