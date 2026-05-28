#!/usr/bin/env bash
set -euo pipefail

kubectl scale deploy/github-unified-mcp -n mcp --replicas=1
kubectl rollout status deploy/github-unified-mcp -n mcp

kubectl scale deploy/github-unified-mcp-bff -n bff --replicas=1 || true
