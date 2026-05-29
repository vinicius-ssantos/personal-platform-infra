#!/usr/bin/env bash
set -euo pipefail

if ! command -v helm >/dev/null 2>&1; then
  echo "ERROR: helm is required to install KEDA HTTP Add-on." >&2
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "ERROR: kubectl is required." >&2
  exit 1
fi

helm repo add kedacore https://kedacore.github.io/charts
helm repo update

helm upgrade --install keda kedacore/keda \
  --namespace keda \
  --create-namespace

kubectl rollout status deploy/keda-operator -n keda --timeout=180s

helm upgrade --install http-add-on kedacore/keda-add-ons-http \
  --namespace keda

kubectl rollout status deploy/keda-add-ons-http-operator -n keda --timeout=180s
kubectl rollout status deploy/keda-add-ons-http-interceptor -n keda --timeout=180s
kubectl rollout status deploy/keda-add-ons-http-scaler -n keda --timeout=180s

kubectl apply -k k8s/addons/keda-http/pilot

echo "KEDA HTTP Add-on pilot installed."
