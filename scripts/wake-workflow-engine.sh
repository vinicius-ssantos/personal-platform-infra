#!/usr/bin/env bash
set -euo pipefail

kubectl scale deploy/workflow-engine -n mcp --replicas=1
kubectl rollout status deploy/workflow-engine -n mcp --timeout=120s
