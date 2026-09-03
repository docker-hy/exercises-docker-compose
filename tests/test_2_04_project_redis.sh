#!/usr/bin/env bash
# Verifies exercise 2.4: project/docker-compose.yaml configures a Redis
# container that the backend uses to cache the slow /ping?redis=true check.
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

cleanup() {
  (cd "$TARGET_DIR" && docker compose down >/dev/null 2>&1)
}
trap cleanup EXIT

[ -f "$COMPOSE_FILE" ] || fail "project/docker-compose.yaml not found"
pass "docker-compose.yaml exists"

grep -qi "redis" "$COMPOSE_FILE" || fail "docker-compose.yaml does not define a redis service"
pass "docker-compose.yaml defines a redis service"

grep -q "REDIS_HOST" "$COMPOSE_FILE" \
  || fail "docker-compose.yaml does not pass REDIS_HOST to the backend"
pass "docker-compose.yaml passes REDIS_HOST to the backend"

(cd "$TARGET_DIR" && docker compose up -d --build) || fail "docker compose up failed"
pass "docker compose up succeeded"

# This is what the "Exercise 2.4" button in the frontend checks: a GET to
# /api/ping?redis=true should be answered with "pong" once the backend has
# a working Redis connection.
redis_ok=false
for _ in $(seq 1 60); do
  response=$(curl -s --max-time 2 "$APP_URL/api/ping?redis=true" 2>/dev/null)
  if [ "$response" = "pong" ]; then
    redis_ok=true
    break
  fi
  sleep 2
done
$redis_ok || fail "GET /api/ping?redis=true did not return pong (got: '$response') -- check the backend's Redis connection"
pass "GET /api/ping?redis=true returned pong -- Redis is wired up"

(cd "$TARGET_DIR" && docker compose down) || fail "docker compose down failed"
pass "docker compose down succeeded"

echo "All tests passed"
