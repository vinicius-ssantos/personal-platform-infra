"""Loopback-only wake proxy for the public MCP and OAuth routes."""
from __future__ import annotations

import http.client
import json
import os
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPOSE = ROOT / "compose" / "docker-compose.yml"
ENV_FILE = ROOT / ".env"
PORT = int(os.getenv("MCP_WAKE_PROXY_PORT", "8788"))
IDLE_SECONDS = int(os.getenv("MCP_WAKE_PROXY_IDLE_SECONDS", "900"))
SLOT_STATE = Path(os.getenv("MCP_WAKE_PROXY_SLOT_STATE", Path(os.getenv("LOCALAPPDATA", str(ROOT))) / "personal-platform" / "gateway-slot.json"))
SLOTS = {"legacy": ("central-mcp-gateway", 8040), "blue": ("central-mcp-gateway-blue", 8041), "green": ("central-mcp-gateway-green", 8042)}
CORE_SERVICES = ("github-unified-mcp", "repo-research-sidecar")
PROFILES = ("gateway", "github", "repo-research")


def allowed(method: str, path: str) -> bool:
    return (method == "POST" and path == "/mcp") or (method in {"GET", "POST"} and (path.startswith("/.well-known/") or path.startswith("/oauth/")))


def active_slot() -> tuple[str, int]:
    try:
        slot = json.loads(SLOT_STATE.read_text(encoding="ascii")).get("slot")
    except (OSError, ValueError, AttributeError):
        slot = "legacy"
    return SLOTS.get(slot, SLOTS["legacy"])


class Lifecycle:
    def __init__(self) -> None:
        self.lock = threading.Lock(); self.active = 0; self.last = time.monotonic(); self.last_service = SLOTS["legacy"][0]
    def wake(self, service: str) -> None:
        with self.lock:
            command = ["docker", "compose", "-f", str(COMPOSE), "--env-file", str(ENV_FILE)]
            for profile in PROFILES: command += ["--profile", profile]
            subprocess.run(command + ["up", "-d", "--wait", service, *CORE_SERVICES], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True, timeout=90)
            self.last_service = service; self.active += 1; self.last = time.monotonic()
    def release(self) -> None:
        with self.lock: self.active -= 1; self.last = time.monotonic()
    def idle_loop(self) -> None:
        while True:
            time.sleep(1)
            with self.lock:
                if self.active or time.monotonic() - self.last < IDLE_SECONDS: continue
                subprocess.run(["docker", "compose", "-f", str(COMPOSE), "--env-file", str(ENV_FILE), "stop", self.last_service, *CORE_SERVICES], cwd=ROOT, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=30)
                self.last = time.monotonic()


LIFECYCLE = Lifecycle()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, _format: str, *_args: object) -> None: pass
    def do_GET(self) -> None: self.proxy()
    def do_POST(self) -> None: self.proxy()
    def proxy(self) -> None:
        if not allowed(self.command, self.path): self.send_error(404); return
        service, port = active_slot()
        try: LIFECYCLE.wake(service)
        except (subprocess.SubprocessError, OSError): self.send_error(503, "mcp core unavailable"); return
        try:
            body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            connection = http.client.HTTPConnection("127.0.0.1", port, timeout=90)
            headers = {k: v for k, v in self.headers.items() if k.lower() not in {"host", "connection"}}
            connection.request(self.command, self.path, body=body, headers=headers)
            response = connection.getresponse()
            self.send_response(response.status)
            for key, value in response.getheaders():
                if key.lower() not in {"connection", "transfer-encoding", "content-length"}: self.send_header(key, value)
            # Closing this backend hop gives Caddy an unambiguous end-of-stream
            # while allowing long MCP responses to flow without buffering.
            self.send_header("Connection", "close"); self.end_headers()
            while chunk := response.read(65536):
                self.wfile.write(chunk); self.wfile.flush()
            self.close_connection = True
        except OSError: self.send_error(502, "mcp core proxy failed")
        finally: LIFECYCLE.release()


if __name__ == "__main__":
    threading.Thread(target=LIFECYCLE.idle_loop, daemon=True).start()
    ThreadingHTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
