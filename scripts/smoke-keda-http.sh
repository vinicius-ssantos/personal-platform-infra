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

# Poll until the port-forward is accepting connections before sending HTTP requests.
until (: < /dev/tcp/127.0.0.1/18090) 2>/dev/null; do sleep 1; done

check_wake() {
  local host="$1" path="$2" deploy="$3" ns="$4"
  echo "  Waking $deploy via Host: $host ..."
  curl -fsS --retry 20 --retry-delay 2 --retry-connrefused --retry-all-errors \
    -H "Host: $host" \
    "http://127.0.0.1:18090${path}" >/dev/null
  kubectl rollout status "deploy/$deploy" -n "$ns" --timeout="$TIMEOUT"
  echo "  OK: $deploy"
}

# Single source of truth: host:path:deploy:namespace
# Hosts match the Cloudflare DNS subdomains configured in terraform/cloudflare.
SERVICES=(
  "mcp-github.example.com:/healthz:github-unified-mcp:mcp"
  "github-bff.example.com:/healthz:github-unified-mcp-bff:bff"
  "deploy-mcp.example.com:/healthz:deploy-orchestrator-mcp:mcp"
  "social-mcp.example.com:/health:mcp-social:mcp"
  "vos-mcp.example.com:/health:vos-studio-mcp:vos"
  "vos-bff.example.com:/healthz:vos-studio-bff:bff"
  "mcp-gateway.example.com:/healthz:central-mcp-gateway:mcp"
)

echo "KEDA HTTP smoke: waking all ${#SERVICES[@]} services via interceptor proxy..."

for _svc in "${SERVICES[@]}"; do
  IFS=: read -r _host _path _deploy _ns <<< "$_svc"
  check_wake "$_host" "$_path" "$_deploy" "$_ns"
done

echo ""
echo "KEDA HTTP smoke passed: all ${#SERVICES[@]} services woke and are healthy."
