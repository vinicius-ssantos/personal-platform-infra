#!/usr/bin/env bash
set -euo pipefail
# KEDA HTTP Add-on manages replica lifecycle for these deployments during normal
# operation. Use this script only for break-glass recovery. See docs/lifecycle.md.

kubectl scale deploy/vos-studio-mcp -n vos --replicas=1
kubectl rollout status deploy/vos-studio-mcp -n vos --timeout=120s

kubectl scale deploy/vos-studio-bff -n bff --replicas=1
kubectl rollout status deploy/vos-studio-bff -n bff --timeout=120s
