#!/usr/bin/env bash
set -euo pipefail
# KEDA HTTP Add-on manages replica lifecycle for these deployments during normal
# operation. Use this script only for break-glass recovery (e.g. KEDA unavailable).
# Under normal operation, send an HTTP request through the interceptor proxy to
# wake the service — KEDA will scale it up automatically. See docs/lifecycle.md.

kubectl scale deploy/github-unified-mcp -n mcp --replicas=1
kubectl rollout status deploy/github-unified-mcp -n mcp --timeout=120s

kubectl scale deploy/github-unified-mcp-bff -n bff --replicas=1
kubectl rollout status deploy/github-unified-mcp-bff -n bff --timeout=120s
