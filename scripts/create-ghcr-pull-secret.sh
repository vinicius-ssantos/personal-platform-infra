#!/usr/bin/env bash
set -euo pipefail

SECRET_NAME="${GHCR_PULL_SECRET_NAME:-ghcr-pull-secret}"
NAMESPACES="${GHCR_PULL_SECRET_NAMESPACES:-mcp bff vos}"
DOCKER_SERVER="${GHCR_DOCKER_SERVER:-ghcr.io}"
DOCKER_EMAIL="${GHCR_DOCKER_EMAIL:-unused@example.local}"

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is required to create GHCR pull secrets." >&2
  exit 1
fi

if ! kubectl cluster-info >/dev/null 2>&1; then
  echo "ERROR: kubectl cannot reach a cluster. Check KUBECONFIG/current context." >&2
  exit 1
fi

if [[ -z "${GHCR_USERNAME:-}" ]]; then
  echo "ERROR: GHCR_USERNAME is required." >&2
  exit 1
fi

if [[ -z "${GHCR_TOKEN:-}" ]]; then
  echo "ERROR: GHCR_TOKEN is required. Use a token with read:packages for private GHCR images." >&2
  exit 1
fi

for namespace in ${NAMESPACES}; do
  echo "Creating/updating ${SECRET_NAME} in namespace ${namespace}..."

  kubectl get namespace "${namespace}" >/dev/null 2>&1 || kubectl create namespace "${namespace}"

  kubectl create secret docker-registry "${SECRET_NAME}" \
    --docker-server="${DOCKER_SERVER}" \
    --docker-username="${GHCR_USERNAME}" \
    --docker-password="${GHCR_TOKEN}" \
    --docker-email="${DOCKER_EMAIL}" \
    --namespace="${namespace}" \
    --dry-run=client \
    -o yaml | kubectl apply -f - >/dev/null

  kubectl get secret "${SECRET_NAME}" -n "${namespace}" >/dev/null
  echo "OK ${namespace}/${SECRET_NAME}"
done
