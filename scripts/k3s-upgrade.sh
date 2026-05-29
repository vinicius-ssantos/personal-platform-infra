#!/usr/bin/env bash
# Upgrades k3s to the latest stable release on a single-node cluster.
# Run on the VPS as root (or via sudo).
set -euo pipefail

NODE_NAME="${K3S_NODE_NAME:-$(kubectl get nodes -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || hostname)}"

echo "=== Scaling down all workloads ==="
for ns in mcp bff vos; do
  kubectl get deployments -n "$ns" --no-headers -o custom-columns="NAME:.metadata.name" 2>/dev/null \
    | xargs -r -I{} kubectl scale deployment/{} -n "$ns" --replicas=0
done

echo "=== Draining node: $NODE_NAME ==="
kubectl drain "$NODE_NAME" --ignore-daemonsets --delete-emptydir-data --timeout=60s || true

echo "=== Installing latest k3s ==="
curl -sfL https://get.k3s.io | sh -

echo "=== Waiting for node to be Ready ==="
kubectl wait node "$NODE_NAME" --for=condition=Ready --timeout=120s

echo "=== Uncordoning node ==="
kubectl uncordon "$NODE_NAME"

echo ""
echo "k3s upgrade complete. Use 'just wake-github' or 'kubectl apply -k k8s/overlays/vps' to restore workloads."
