#!/usr/bin/env bash
# Verifies exercise 2.6: project/docker-compose.yaml configures a Postgres
# database for the backend to save messages to.
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

grep -qi "postgres" "$COMPOSE_FILE" || fail "docker-compose.yaml does not define a postgres service"
pass "docker-compose.yaml defines a postgres service"

grep -q "POSTGRES_HOST" "$COMPOSE_FILE" \
  || fail "docker-compose.yaml does not pass POSTGRES_HOST to the backend"
pass "docker-compose.yaml passes POSTGRES_HOST to the backend"

(cd "$TARGET_DIR" && docker compose up -d --build) || fail "docker compose up failed"
pass "docker compose up succeeded"

# This is what the "Exercise 2.6" button in the frontend checks: a GET to
# /api/ping?postgres=true should be answered with "pong" once the backend
# has a working Postgres connection.
postgres_ok=false
for _ in $(seq 1 60); do
  response=$(curl -s --max-time 2 "$APP_URL/api/ping?postgres=true" 2>/dev/null)
  if [ "$response" = "pong" ]; then
    postgres_ok=true
    break
  fi
  sleep 2
done
$postgres_ok || fail "GET /api/ping?postgres=true did not return pong (got: '$response') -- check the backend's Postgres connection"
pass "GET /api/ping?postgres=true returned pong -- Postgres is wired up"

# The message form/list in the frontend relies on POST/GET /api/messages
# actually persisting to the database.
unique_body="test-message-$$-$RANDOM"
post_response=$(curl -s --max-time 5 -X POST "$APP_URL/api/messages" \
  -H "Content-Type: application/json" \
  -d "{\"body\": \"$unique_body\"}")
echo "$post_response" | grep -q "$unique_body" || fail "POST /api/messages did not echo back the saved message (got: '$post_response')"
pass "POST /api/messages saved a new message"

get_response=$(curl -s --max-time 5 "$APP_URL/api/messages")
echo "$get_response" | grep -q "$unique_body" \
  || fail "GET /api/messages did not include the message that was just saved (got: '$get_response')"
pass "GET /api/messages returns messages saved to Postgres"

(cd "$TARGET_DIR" && docker compose down) || fail "docker compose down failed"
pass "docker compose down succeeded"

echo "All tests passed"
