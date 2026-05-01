#!/bin/sh
set -eu

export ADMIN_API_HOST="${ADMIN_API_HOST:-127.0.0.1}"
export ADMIN_API_PORT="${ADMIN_API_PORT:-8791}"

node /app/services/admin-api/src/server.js &
ADMIN_PID="$!"

cleanup() {
  kill "$ADMIN_PID" 2>/dev/null || true
}
trap cleanup INT TERM EXIT

nginx -g 'daemon off;'
