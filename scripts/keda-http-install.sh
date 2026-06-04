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

# Apply InterceptorRoutes with real hostnames.
# InterceptorRoute hosts use __VPS_DOMAIN__ tokens that must be substituted
# before applying — otherwise the interceptor never matches production traffic
# and scale-from-zero silently does nothing for requests with real Host headers.
# Render __VPS_DOMAIN__ tokens in InterceptorRoute hosts before applying.
# Default to example.com for local/k3d testing so that smoke-keda-http.sh
# Host headers (e.g. mcp-github.example.com) match the installed routes.
# For VPS production: export VPS_DOMAIN=your.domain before running this script,
# or set it via: VPS_DOMAIN=your.domain just keda-http-install
_DOMAIN="${VPS_DOMAIN:-example.com}"
if [[ "$_DOMAIN" == "example.com" ]]; then
  echo "VPS_DOMAIN not set — using example.com (local/k3d testing mode)."
else
  echo "Rendering KEDA routes with VPS_DOMAIN=${_DOMAIN} ..."
fi

if ! command -v kustomize >/dev/null 2>&1; then
  echo "ERROR: kustomize is required to render KEDA routes." >&2
  exit 1
fi

kustomize build k8s/addons/keda-http/pilot \
  | sed "s/__VPS_DOMAIN__/${_DOMAIN}/g" \
  | kubectl apply -f -

echo "KEDA HTTP Add-on installed."
