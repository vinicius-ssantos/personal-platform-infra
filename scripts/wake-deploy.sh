#!/usr/bin/env bash
set -euo pipefail

kubectl scale deploy/deploy-orchestrator-mcp -n mcp --replicas=1
kubectl rollout status deploy/deploy-orchestrator-mcp -n mcp
