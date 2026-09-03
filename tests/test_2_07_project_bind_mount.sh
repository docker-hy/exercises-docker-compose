#!/usr/bin/env bash
# Verifies exercise 2.7: the Postgres database is backed by a manually
# configured bind mount (e.g. ./database) instead of the image's default
# anonymous volume, and that data actually persists there across restarts.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="$REPO_ROOT/project"
COMPOSE_FILE="$TARGET_DIR/docker-compose.yaml"
APP_URL="http://localhost:8000"

fail() {
  echo "FAIL: $1"
  exit 1
}

pass() {
  echo "PASS: $1"
}

# Postgres initializes its data directory as its own container user
# (uid 70, mode 0700), so on native Linux (unlike Docker Desktop's mac
# volume translation) the host user running this script has no permission
# to read or remove it directly. Route those operations through a
# throwaway root container instead.
clean_host_dir() {
  docker run --rm -v "$TARGET_DIR:/target" alpine rm -rf "/target/${host_dir#./}" >/dev/null 2>&1
}

host_dir_has_file() {
  docker run --rm -v "$TARGET_DIR:/target" alpine test -f "/target/${host_dir#./}/$1"
}

cleanup() {
  (cd "$TARGET_DIR" && docker compose down >/dev/null 2>&1)
  [ -n "${host_dir:-}" ] && clean_host_dir
}
trap cleanup EXIT

[ -f "$COMPOSE_FILE" ] || fail "project/docker-compose.yaml not found"
pass "docker-compose.yaml exists"

# A bind mount for postgres data maps a host path (./database or similar)
# to /var/lib/postgresql/data, as opposed to a named/anonymous volume.
grep -q "/var/lib/postgresql/data" "$COMPOSE_FILE" \
  || fail "docker-compose.yaml does not mount anything to /var/lib/postgresql/data"
pass "docker-compose.yaml mounts something to /var/lib/postgresql/data"

grep -E "^\s*-\s*\./[A-Za-z0-9_.-]*:/var/lib/postgresql/data" "$COMPOSE_FILE" >/dev/null \
  || fail "the mount for /var/lib/postgresql/data does not look like a bind mount to a relative host path (./...)"
pass "the mount for /var/lib/postgresql/data is a bind mount to a relative host path"

host_dir=$(grep -oE "\./[A-Za-z0-9_.-]*:/var/lib/postgresql/data" "$COMPOSE_FILE" | head -n1 | cut -d: -f1)
[ -n "$host_dir" ] || fail "could not determine the bind mount's host directory from docker-compose.yaml"
pass "bind mount host directory is $host_dir"

# There should be no top-level named volume declared for this data, since
# the exercise explicitly asks for a bind mount instead.
if grep -qE "^volumes:" "$COMPOSE_FILE"; then
  fail "docker-compose.yaml declares a top-level 'volumes:' section -- exercise 2.7 asks for a bind mount, not a named volume"
fi
pass "docker-compose.yaml does not declare a named volume for the database"

# Start from a clean slate: don't assume anything about whether the bind
# mount directory already exists on the host, or what's in it left over
# from a previous run -- otherwise a stale PG_VERSION file could make the
# persistence check below pass without the mount actually working.
clean_host_dir

(cd "$TARGET_DIR" && docker compose up -d --build) || fail "docker compose up failed"
pass "docker compose up succeeded"

postgres_ok=false
for _ in $(seq 1 60); do
  response=$(curl -s --max-time 2 "$APP_URL/api/ping?postgres=true" 2>/dev/null)
  if [ "$response" = "pong" ]; then
    postgres_ok=true
    break
  fi
  sleep 2
done
$postgres_ok || fail "backend never reported a working Postgres connection"
pass "backend has a working Postgres connection"

data_appeared=false
for _ in $(seq 1 15); do
  if host_dir_has_file PG_VERSION; then
    data_appeared=true
    break
  fi
  sleep 1
done
$data_appeared || fail "no Postgres data files appeared on the host at $TARGET_DIR/${host_dir#./} -- is the bind mount actually working?"
pass "Postgres data files are visible on the host filesystem at $TARGET_DIR/${host_dir#./}"

unique_body="bind-mount-test-$$-$RANDOM"
curl -s --max-time 5 -X POST "$APP_URL/api/messages" \
  -H "Content-Type: application/json" \
  -d "{\"body\": \"$unique_body\"}" >/dev/null
pass "saved a message before restarting the stack"

(cd "$TARGET_DIR" && docker compose down) || fail "docker compose down failed"
pass "docker compose down succeeded"

(cd "$TARGET_DIR" && docker compose up -d) || fail "docker compose up (restart) failed"
pass "docker compose up (restart) succeeded"

persisted=false
for _ in $(seq 1 60); do
  get_response=$(curl -s --max-time 2 "$APP_URL/api/messages" 2>/dev/null)
  if echo "$get_response" | grep -q "$unique_body"; then
    persisted=true
    break
  fi
  sleep 2
done
$persisted || fail "the message saved before the restart is gone -- data is not persisted on the bind mount"
pass "the message saved before the restart is still there -- data persists on the bind mount"

(cd "$TARGET_DIR" && docker compose down) || fail "docker compose down failed"
pass "docker compose down succeeded"

echo "All tests passed"
