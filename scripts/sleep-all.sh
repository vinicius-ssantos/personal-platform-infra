#!/usr/bin/env bash
set -euo pipefail

kubectl scale deploy/github-unified-mcp -n mcp --replicas=0 || true
kubectl scale deploy/deploy-orchestrator-mcp -n mcp --replicas=0 || true
kubectl scale deploy/mcp-social -n mcp --replicas=0 || true
kubectl scale deploy/github-unified-mcp-bff -n bff --replicas=0 || true
kubectl scale deploy/vos-studio-mcp -n vos --replicas=0 || true
kubectl scale deploy/vos-studio-bff -n bff --replicas=0 || true
