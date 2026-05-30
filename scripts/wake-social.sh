#!/usr/bin/env bash
set -euo pipefail

kubectl scale deploy/mcp-social -n mcp --replicas=1
kubectl rollout status deploy/mcp-social -n mcp
