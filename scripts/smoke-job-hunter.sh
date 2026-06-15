#!/bin/bash
set -euo pipefail

info()  { echo "[INFO]  $*"; }
error() { echo "[ERROR] $*" >&2; }

COMPOSE_PROFILE="job-hunter"

info "Checking Job Hunter Agent container status..."
CONTAINER="compose-job-hunter-scheduler-1"

# Check if container is running
if docker ps --format "{{.Names}}" | grep -q "$CONTAINER"; then
  info "OK: $CONTAINER is running"
else
  error "$CONTAINER is not running (try: docker compose --profile $COMPOSE_PROFILE up -d)"
  exit 1
fi

info "Smoke check passed."