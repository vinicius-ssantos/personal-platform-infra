#!/usr/bin/env bash
# Validate that Loki is reachable and has recent log streams from Alloy ingestion.

set -euo pipefail

NAMESPACE="${LOKI_NAMESPACE:-monitoring}"
LOKI_SERVICE="${LOKI_SERVICE:-loki}"
LOKI_PORT="${LOKI_PORT:-3100}"
LOCAL_PORT="${LOKI_LOCAL_PORT:-13100}"
QUERY_SELECTOR="${LOKI_QUERY_SELECTOR:-{namespace=~\"mcp|bff|vos|monitoring\"}}"
LIMIT="${LOKI_QUERY_LIMIT:-5}"
SINCE_SECONDS="${LOKI_SINCE_SECONDS:-3600}"

fail() {
  echo "✗ $*" >&2
  exit 1
}

warn() {
  echo "~ $*" >&2
}

ok() {
  echo "✓ $*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required"
}

cleanup() {
  if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
    kill "$PORT_FORWARD_PID" >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT

require_command kubectl
require_command curl

kubectl cluster-info --request-timeout=5s >/dev/null 2>&1 || fail "kubectl cannot reach a cluster"

kubectl get namespace "$NAMESPACE" >/dev/null 2>&1 || fail "namespace '$NAMESPACE' not found"
kubectl get svc "$LOKI_SERVICE" -n "$NAMESPACE" >/dev/null 2>&1 || fail "service '$NAMESPACE/$LOKI_SERVICE' not found"

if ! kubectl get pods -n "$NAMESPACE" -l app=loki --no-headers 2>/dev/null | grep -q "Running"; then
  fail "no running Loki pod found in namespace '$NAMESPACE'"
fi
ok "Loki pod is running"

if ! kubectl get pods -n "$NAMESPACE" -l app=alloy --no-headers 2>/dev/null | grep -q "Running"; then
  fail "no running Alloy pod found in namespace '$NAMESPACE'"
fi
ok "Alloy pod is running"

kubectl port-forward -n "$NAMESPACE" "svc/$LOKI_SERVICE" "$LOCAL_PORT:$LOKI_PORT" >/tmp/loki-port-forward.log 2>&1 &
PORT_FORWARD_PID=$!

for _ in $(seq 1 20); do
  if curl --silent --fail "http://127.0.0.1:${LOCAL_PORT}/ready" >/dev/null 2>&1; then
    ok "Loki ready endpoint is reachable"
    break
  fi
  sleep 1
done

curl --silent --fail "http://127.0.0.1:${LOCAL_PORT}/ready" >/dev/null 2>&1 || {
  cat /tmp/loki-port-forward.log >&2 || true
  fail "Loki ready endpoint did not become reachable through port-forward"
}

now_ns="$(date +%s%N)"
start_ns="$(( ( $(date +%s) - SINCE_SECONDS ) * 1000000000 ))"

query_url="http://127.0.0.1:${LOCAL_PORT}/loki/api/v1/query_range"
response="$(curl --silent --show-error --get "$query_url" \
  --data-urlencode "query=${QUERY_SELECTOR}" \
  --data-urlencode "start=${start_ns}" \
  --data-urlencode "end=${now_ns}" \
  --data-urlencode "limit=${LIMIT}" \
  --data-urlencode "direction=backward")"

status="$(printf '%s' "$response" | grep -o '"status":"[^"]*"' | head -n1 | cut -d'"' -f4 || true)"
[[ "$status" == "success" ]] || fail "Loki query did not return success: ${response}"

if printf '%s' "$response" | grep -q '"result":\[\]'; then
  warn "Loki is reachable but returned no streams for selector ${QUERY_SELECTOR} in the last ${SINCE_SECONDS}s"
  warn "Check Alloy RBAC/config, workload log volume, labels and whether workloads emitted logs recently."
  exit 1
fi

ok "Loki returned log streams for ${QUERY_SELECTOR}"
