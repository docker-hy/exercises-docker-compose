#!/usr/bin/env bash
# Verifies exercise 2.3: project/docker-compose.yaml brings up the example
# frontend and backend together, and the frontend can reach the backend
# through it (the same connection the "Exercise 1.14" button in the app
# tests).
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

grep -q "backend" "$COMPOSE_FILE" || fail "docker-compose.yaml does not define a backend service"
pass "docker-compose.yaml defines a backend service"

grep -q "frontend" "$COMPOSE_FILE" || fail "docker-compose.yaml does not define a frontend service"
pass "docker-compose.yaml defines a frontend service"

(cd "$TARGET_DIR" && docker compose up -d --build) || fail "docker compose up failed"
pass "docker compose up succeeded"

# Wait for the whole stack (frontend/backend, and whatever sits in front of
# them) to start serving requests.
frontend_ok=false
for _ in $(seq 1 60); do
  if curl -s --max-time 2 "$APP_URL" 2>/dev/null | grep -qi "html"; then
    frontend_ok=true
    break
  fi
  sleep 2
done
$frontend_ok || fail "frontend was not reachable at $APP_URL"
pass "frontend is reachable at $APP_URL"

# This is exactly what the "Exercise 1.14" button in the frontend checks:
# a GET to /api/ping should be answered by the backend with "pong".
backend_ok=false
for _ in $(seq 1 60); do
  response=$(curl -s --max-time 2 "$APP_URL/api/ping" 2>/dev/null)
  if [ "$response" = "pong" ]; then
    backend_ok=true
    break
  fi
  sleep 2
done
$backend_ok || fail "frontend could not reach backend through /api/ping (got: '$response')"
pass "frontend can reach the backend through /api/ping"

(cd "$TARGET_DIR" && docker compose down) || fail "docker compose down failed"
pass "docker compose down succeeded"

echo "All tests passed"
