#!/usr/bin/env bash
set -euo pipefail

kubectl scale deploy/vos-studio-mcp -n vos --replicas=1
kubectl rollout status deploy/vos-studio-mcp -n vos

kubectl scale deploy/vos-studio-bff -n bff --replicas=1
kubectl rollout status deploy/vos-studio-bff -n bff
