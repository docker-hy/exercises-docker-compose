#!/usr/bin/env bash
# Verifies exercises 2.7 (reverse proxy) and 2.9 (fixup): Nginx sits in
# front of both the frontend and the backend, listening on host port 8000,
# and every button/request in the app works when routed through it.
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

grep -qi "nginx" "$COMPOSE_FILE" || fail "docker-compose.yaml does not define an nginx service"
pass "docker-compose.yaml defines an nginx service"

grep -qE '8000:80\b' "$COMPOSE_FILE" \
  || fail "docker-compose.yaml does not publish nginx's port 80 as host port 8000"
pass "docker-compose.yaml publishes nginx on host port 8000"

grep -q "/etc/nginx/nginx.conf" "$COMPOSE_FILE" \
  || fail "docker-compose.yaml does not bind mount a config file to /etc/nginx/nginx.conf"
pass "docker-compose.yaml bind mounts a config file to /etc/nginx/nginx.conf"

(cd "$TARGET_DIR" && docker compose up -d --build) || fail "docker compose up failed"
pass "docker compose up succeeded"

# The frontend must be reachable simply by going to http://localhost:8000.
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

# The direct request to the backend through the proxy must work.
ping_ok=false
for _ in $(seq 1 60); do
  response=$(curl -s --max-time 2 "$APP_URL/api/ping" 2>/dev/null)
  if [ "$response" = "pong" ]; then
    ping_ok=true
    break
  fi
  sleep 2
done
$ping_ok || fail "$APP_URL/api/ping did not return pong (got: '$response')"
pass "$APP_URL/api/ping returns pong through the Nginx proxy"

# Every exercise button in the app must keep working once all requests are
# routed through Nginx: backend (1.14), redis (2.4) and postgres (2.6).
redis_response=$(curl -s --max-time 5 "$APP_URL/api/ping?redis=true")
[ "$redis_response" = "pong" ] || fail "redis button broke behind the proxy (got: '$redis_response')"
pass "redis button (/api/ping?redis=true) works through the proxy"

postgres_response=$(curl -s --max-time 5 "$APP_URL/api/ping?postgres=true")
[ "$postgres_response" = "pong" ] || fail "postgres button broke behind the proxy (got: '$postgres_response')"
pass "postgres button (/api/ping?postgres=true) works through the proxy"

unique_body="nginx-test-$$-$RANDOM"
curl -s --max-time 5 -X POST "$APP_URL/api/messages" \
  -H "Content-Type: application/json" \
  -d "{\"body\": \"$unique_body\"}" >/dev/null
messages_response=$(curl -s --max-time 5 "$APP_URL/api/messages")
echo "$messages_response" | grep -q "$unique_body" \
  || fail "'Get all messages' broke behind the proxy (got: '$messages_response')"
pass "'Get all messages'/'Send message' work through the proxy"

(cd "$TARGET_DIR" && docker compose down) || fail "docker compose down failed"
pass "docker compose down succeeded"

echo "All tests passed"
