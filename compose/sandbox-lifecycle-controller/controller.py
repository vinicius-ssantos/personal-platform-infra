"""Fixed-target local wake proxy for the optional code sandbox."""
from __future__ import annotations

import http.client
import json
import os
import socket
import threading
import time
from hmac import compare_digest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlencode

PROJECT = os.getenv("SANDBOX_COMPOSE_PROJECT", "compose")
TOKEN = os.environ["SANDBOX_API_KEY"]
IDLE_SECONDS = int(os.getenv("SANDBOX_IDLE_SECONDS", "900"))
TARGET_HOST = "mcp-code-sandbox"
TARGET_PORT = 8766


class UnixConnection(http.client.HTTPConnection):
    def connect(self) -> None:
        self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.sock.connect("/var/run/docker.sock")


def docker(method: str, path: str) -> tuple[int, bytes]:
    connection = UnixConnection("localhost")
    connection.request(method, path)
    response = connection.getresponse()
    payload = response.read()
    status = response.status
    connection.close()
    return status, payload


def container(service: str) -> str:
    labels = [f"com.docker.compose.project={PROJECT}", f"com.docker.compose.service={service}"]
    status, payload = docker("GET", "/containers/json?" + urlencode({"all": "1", "filters": json.dumps({"label": labels})}))
    containers = json.loads(payload) if status == 200 else []
    if len(containers) != 1:
        raise RuntimeError("sandbox_not_prepared")
    return containers[0]["Id"]


def docker_action(service: str, action: str) -> None:
    status, _ = docker("POST", f"/containers/{container(service)}/{action}")
    if status not in (204, 304):
        raise RuntimeError(f"docker_{action}_failed")


class Lifecycle:
    def __init__(self) -> None:
        self.lock = threading.Lock()
        self.active = 0
        self.last_activity = time.monotonic()

    def acquire(self) -> None:
        with self.lock:
            docker_action("docker-socket-proxy", "start")
            docker_action("mcp-code-sandbox", "start")
            for _ in range(30):
                try:
                    conn = http.client.HTTPConnection(TARGET_HOST, TARGET_PORT, timeout=1)
                    conn.request("GET", "/health")
                    if conn.getresponse().status == 200:
                        conn.close()
                        self.active += 1
                        self.last_activity = time.monotonic()
                        return
                    conn.close()
                except OSError:
                    pass
                time.sleep(1)
            raise RuntimeError("sandbox_readiness_timeout")

    def release(self) -> None:
        with self.lock:
            self.active -= 1
            self.last_activity = time.monotonic()

    def sleep_when_idle(self) -> None:
        while True:
            time.sleep(1)
            with self.lock:
                if self.active or time.monotonic() - self.last_activity < IDLE_SECONDS:
                    continue
                for service in ("mcp-code-sandbox", "docker-socket-proxy"):
                    try:
                        docker_action(service, "stop?t=10")
                    except RuntimeError:
                        pass
                self.last_activity = time.monotonic()


LIFECYCLE = Lifecycle()


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, _format: str, *_args: object) -> None: pass
    def _error(self, status: int, code: str) -> None:
        payload = json.dumps({"error": code}).encode()
        self.send_response(status); self.send_header("Content-Type", "application/json"); self.send_header("Content-Length", str(len(payload))); self.end_headers(); self.wfile.write(payload)
    def do_GET(self) -> None:
        if self.path == "/healthz":
            self.send_response(200); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"ok"); return
        self._proxy()
    def do_POST(self) -> None: self._proxy()
    def _proxy(self) -> None:
        if not compare_digest(self.headers.get("Authorization", ""), f"Bearer {TOKEN}"):
            self._error(401, "unauthorized"); return
        try:
            LIFECYCLE.acquire()
        except RuntimeError as error:
            self._error(503, str(error)); return
        try:
            body = self.rfile.read(int(self.headers.get("Content-Length", "0")))
            conn = http.client.HTTPConnection(TARGET_HOST, TARGET_PORT, timeout=90)
            headers = {key: value for key, value in self.headers.items() if key.lower() not in {"host", "connection"}}
            conn.request(self.command, self.path, body=body, headers=headers)
            response = conn.getresponse(); payload = response.read()
            self.send_response(response.status)
            for key, value in response.getheaders():
                if key.lower() not in {"connection", "transfer-encoding", "content-length"}: self.send_header(key, value)
            self.send_header("Content-Length", str(len(payload))); self.end_headers(); self.wfile.write(payload); conn.close()
        except OSError:
            self._error(502, "sandbox_proxy_failed")
        finally:
            LIFECYCLE.release()


if __name__ == "__main__":
    threading.Thread(target=LIFECYCLE.sleep_when_idle, daemon=True).start()
    ThreadingHTTPServer(("0.0.0.0", 8767), Handler).serve_forever()
