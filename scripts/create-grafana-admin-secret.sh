#!/usr/bin/env bash
# Create or update the Grafana admin Secret without committing credentials.

set -euo pipefail

NAMESPACE="${GRAFANA_NAMESPACE:-monitoring}"
SECRET_NAME="${GRAFANA_ADMIN_SECRET_NAME:-grafana-admin}"
ADMIN_USER="${GRAFANA_ADMIN_USER:-admin}"
ADMIN_PASSWORD="${GRAFANA_ADMIN_PASSWORD:-}"
TARGET_ENV="${TARGET_ENV:-local}"

if [[ -z "$ADMIN_PASSWORD" ]]; then
  cat >&2 <<'EOF'
error: GRAFANA_ADMIN_PASSWORD is required.

Example for local/k3d:
  GRAFANA_ADMIN_PASSWORD='change-me-local-only' just grafana-secret

For VPS, provide the value from the encrypted secrets flow and use TARGET_ENV=vps.
EOF
  exit 2
fi

if [[ "$TARGET_ENV" != "local" && "$ADMIN_PASSWORD" == "admin" ]]; then
  echo "error: refusing default Grafana password outside local mode" >&2
  exit 2
fi

kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic "$SECRET_NAME" \
  --namespace "$NAMESPACE" \
  --from-literal=admin-user="$ADMIN_USER" \
  --from-literal=admin-password="$ADMIN_PASSWORD" \
  --dry-run=client \
  -o yaml | kubectl apply -f -

echo "Grafana admin Secret '${NAMESPACE}/${SECRET_NAME}' applied."
