#!/usr/bin/env bash
set -euo pipefail
# KEDA HTTP Add-on manages replica lifecycle for this deployment during normal
# operation. Use this script only for break-glass recovery. See docs/lifecycle.md.

kubectl scale deploy/deploy-orchestrator-mcp -n mcp --replicas=1
kubectl rollout status deploy/deploy-orchestrator-mcp -n mcp --timeout=120s
