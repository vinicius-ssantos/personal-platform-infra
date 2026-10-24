#!/usr/bin/env bash
# Isolated synthetic archive round-trip for CI. No Keycloak accounts or real data.
set -euo pipefail
umask 077

image='postgres:17-alpine@sha256:eee6c6e1b0894fa4fe0075eb054af9fd1cf39a35321c2d4110626cfe506411fb'
run_id="$(date +%s)-$RANDOM-$$"
source_container="vagadeck-ci-source-$run_id"
restore_container="vagadeck-ci-restore-$run_id"
scratch="$(mktemp -d)"
export POSTGRES_PASSWORD
POSTGRES_PASSWORD="$(openssl rand -hex 24)"

cleanup() {
  docker rm -f "$restore_container" >/dev/null 2>&1 || true
  docker rm -f "$source_container" >/dev/null 2>&1 || true
  rm -f -- "$scratch/synthetic.dump"
  rmdir -- "$scratch" 2>/dev/null || true
  unset POSTGRES_PASSWORD
}
trap cleanup EXIT

wait_for_postgres() {
  local container="$1"
  local attempt
  for attempt in $(seq 1 45); do
    if docker exec "$container" pg_isready -U keycloak -d keycloak >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo 'Synthetic PostgreSQL did not become ready' >&2
  return 1
}

assert_container_isolated() {
  local container="$1"
  local network ports
  network="$(docker inspect --format '{{.HostConfig.NetworkMode}}' "$container")"
  ports="$(docker inspect --format '{{json .HostConfig.PortBindings}}' "$container")"
  if [[ "$network" != 'none' || "$ports" != '{}' ]]; then
    echo 'Synthetic test container unexpectedly has network access or published ports' >&2
    return 1
  fi
}

docker run --detach --rm --network none --name "$source_container" \
  --env POSTGRES_PASSWORD --env POSTGRES_USER=keycloak --env POSTGRES_DB=keycloak \
  "$image" >/dev/null
wait_for_postgres "$source_container"
assert_container_isolated "$source_container"

# Deliberately synthetic schema, not a copied Keycloak database.
docker exec "$source_container" psql -X -v ON_ERROR_STOP=1 -U keycloak -d keycloak -c \
  "CREATE TABLE realm (id TEXT PRIMARY KEY, name TEXT NOT NULL);
   CREATE TABLE synthetic_config (id INTEGER PRIMARY KEY, value TEXT);
   INSERT INTO realm VALUES ('synthetic-a', 'test-realm-a'), ('synthetic-b', 'test-realm-b');
   INSERT INTO synthetic_config VALUES (1, 'no-identities'), (2, 'no-tokens');" >/dev/null

# Keep the binary archive off stdout: PowerShell redirection would corrupt it.
docker exec "$source_container" pg_dump --format=custom --no-owner --no-acl \
  -U keycloak -d keycloak --file /tmp/synthetic.dump
docker cp "$source_container:/tmp/synthetic.dump" "$scratch/synthetic.dump" >/dev/null
test "$(wc -c < "$scratch/synthetic.dump")" -gt 1024
sha256sum "$scratch/synthetic.dump" >/dev/null

docker run --detach --rm --network none --name "$restore_container" \
  --env POSTGRES_PASSWORD --env POSTGRES_USER=keycloak --env POSTGRES_DB=keycloak \
  "$image" >/dev/null
wait_for_postgres "$restore_container"
assert_container_isolated "$restore_container"

docker cp "$scratch/synthetic.dump" "$restore_container:/tmp/restore.dump" >/dev/null
docker exec "$restore_container" pg_restore --list /tmp/restore.dump >/dev/null
docker exec "$restore_container" pg_restore --exit-on-error --single-transaction \
  --no-owner --no-acl -U keycloak -d keycloak /tmp/restore.dump

query() {
  docker exec "$1" psql -X --quiet --tuples-only --no-align --set ON_ERROR_STOP=1 \
    -U keycloak -d keycloak -c "$2"
}

for sql in \
  'SELECT COUNT(*) FROM realm' \
  'SELECT COUNT(*) FROM synthetic_config' \
  "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='public' AND table_type='BASE TABLE'"
do
  source_count="$(query "$source_container" "$sql")"
  restored_count="$(query "$restore_container" "$sql")"
  if [[ "$source_count" != "$restored_count" || "$source_count" -lt 2 ]]; then
    echo 'Synthetic PostgreSQL backup/restore mismatch' >&2
    exit 1
  fi
done

echo 'SYNTHETIC_POSTGRES_DISPOSABLE_RESTORE_PASSED'
echo 'NOTE: This validates archive/restore mechanics only; live VagaDeck Keycloak restore is still pending.'
