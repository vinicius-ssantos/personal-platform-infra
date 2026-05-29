#!/usr/bin/env bash
set -euo pipefail

TIMEOUT="${KEDA_HTTP_SMOKE_TIMEOUT:-180s}"
PIDS=()

cleanup() {
  for pid in "${PIDS[@]:-}"; do
    kill "$pid" 2>/dev/null || true
  done
}
trap cleanup EXIT

kubectl rollout status deploy/keda-add-ons-http-interceptor -n keda --timeout="$TIMEOUT"

kubectl port-forward -n keda svc/keda-add-ons-http-interceptor-proxy 18090:8080 >/dev/null 2>&1 &
PIDS+=($!)
sleep 3

curl -fsS --retry 20 --retry-delay 2 --retry-connrefused --retry-all-errors \
  -H "Host: mcp-github.example.com" \
  http://127.0.0.1:18090/healthz >/dev/null

kubectl rollout status deploy/github-unified-mcp -n mcp --timeout="$TIMEOUT"

curl -fsS --retry 20 --retry-delay 2 --retry-connrefused --retry-all-errors \
  -H "Host: github-bff.example.com" \
  http://127.0.0.1:18090/healthz >/dev/null

kubectl rollout status deploy/github-unified-mcp-bff -n bff --timeout="$TIMEOUT"

echo "KEDA HTTP pilot smoke passed."
