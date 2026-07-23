#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PROJECT_NAME="hookrail-redis"
COMPOSE_FILE="$ROOT_DIR/infra/redis/compose.yml"

cleanup() {
  # stop + remove containers; keep named volumes by default
  docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" down --remove-orphans >/dev/null 2>&1 || true
}

trap cleanup INT TERM EXIT

docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" up -d --remove-orphans

# wait until Redis is responding
docker compose -p "$PROJECT_NAME" -f "$COMPOSE_FILE" exec -T redis \
  bash -lc 'until redis-cli ping >/dev/null 2>&1; do sleep 0.2; done'

# wait until the SRH HTTP shim is reachable (it only accepts POST, so we send PING)
until curl -fsS -X POST \
  -H "Authorization: Bearer example_token" \
  -H "Content-Type: application/json" \
  -d '["PING"]' \
  http://localhost:8079/ >/dev/null 2>&1; do
  sleep 0.2
done

echo "Redis is up on localhost:6379 with an HTTP REST shim on http://localhost:8079 (token: example_token). Press Ctrl+C to stop."
while :; do sleep 1; done
