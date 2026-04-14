#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

export BACKEND_LOCAL_SHARED_SECRET="${BACKEND_LOCAL_SHARED_SECRET:-dev-secret}"
export LOCAL_TOOLS_ENABLED="${LOCAL_TOOLS_ENABLED:-true}"
export ASSISTANT_API_HOST="${ASSISTANT_API_HOST:-127.0.0.1}"
export ASSISTANT_API_PORT="${ASSISTANT_API_PORT:-8787}"
export LOCAL_AGENT_HOST="${LOCAL_AGENT_HOST:-127.0.0.1}"
export LOCAL_AGENT_PORT="${LOCAL_AGENT_PORT:-7443}"

echo "[assistant:stack] starting local-agent on ${LOCAL_AGENT_HOST}:${LOCAL_AGENT_PORT}"
node "${ROOT_DIR}/services/local-agent/src/server.js" &
LOCAL_PID=$!

cleanup() {
  if kill -0 "$LOCAL_PID" >/dev/null 2>&1; then
    kill "$LOCAL_PID" >/dev/null 2>&1 || true
  fi
}

trap cleanup EXIT INT TERM

echo "[assistant:stack] starting assistant-api on ${ASSISTANT_API_HOST}:${ASSISTANT_API_PORT}"
node "${ROOT_DIR}/services/assistant-api/src/server.js"
