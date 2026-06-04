#!/usr/bin/env bash
# Decrypt the SOPS-managed VPS platform-secrets and apply them to the current
# kube-context. Run from a machine that has the age key AND a kubeconfig pointing
# at the VPS cluster (kustomize cannot decrypt SOPS, so this is a separate step).
#
# Usage:
#   just k8s-vps-secrets
#   # or directly:
#   SOPS_AGE_KEY_FILE=~/.age/personal-platform.txt scripts/apply-vps-secrets.sh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILE="${PLATFORM_SECRETS_FILE:-$ROOT_DIR/secrets/platform-secrets-vps.enc.yaml}"
export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.age/personal-platform.txt}"

for bin in sops kubectl; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERROR: $bin is required but not installed." >&2
    exit 1
  fi
done

if [[ ! -f "$FILE" ]]; then
  echo "ERROR: $FILE not found." >&2
  echo "       Create it from the template:" >&2
  echo "         cp secrets/platform-secrets-vps.enc.yaml.example secrets/platform-secrets-vps.enc.yaml" >&2
  echo "         # fill in real values, then: sops -e -i secrets/platform-secrets-vps.enc.yaml" >&2
  exit 1
fi

echo "Applying platform-secrets to context: $(kubectl config current-context)"
sops --decrypt "$FILE" | kubectl apply -f -
