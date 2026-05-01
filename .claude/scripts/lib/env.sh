#!/usr/bin/env bash
# env.sh — Environment detection and loading
# Provides: detect_claude_root, _load_env_claude
# Usage: source "${BASH_SOURCE[0]%/*}/lib/env.sh"

# Double-source guard
if [[ "${__ENV_SH_LOADED:-}" == "true" ]]; then
  return 0
fi
readonly __ENV_SH_LOADED=true

# ============================================================
# CLAUDE_ROOT Detection
# ============================================================

detect_claude_root() {
  local dir="$PWD"
  while [[ "$dir" != "/" ]]; do
    if [[ -d "$dir/.claude" ]]; then
      echo "$dir"
      return 0
    fi
    dir="$(dirname "$dir")"
  done
  # Fallback to current directory
  echo "$PWD"
}

# ============================================================
# env.claude Loading
# ============================================================

# Load factory environment configuration from .claude/env.claude
# Preserves existing shell debugging state (set -x)
# Sets allexport mode temporarily to export all variables
_load_env_claude() {
  # Use CLAUDE_ROOT if set, otherwise detect it
  local root="${CLAUDE_ROOT:-$(detect_claude_root)}"
  local _env_file="${root}/.claude/env.claude"
  local _env_local_file="${root}/.claude/env.claude.local"
  local _prev_x=false
  local _prev_u=false

  [[ $- == *x* ]] && _prev_x=true && set +x
  [[ $- == *u* ]] && _prev_u=true && set +u

  if [[ -f "$_env_file" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$_env_file"
    set +a
  fi

  if [[ -f "$_env_local_file" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$_env_local_file"
    set +a
  fi

  if [[ -n "${POSTGRES_USER:-}" ]] && [[ -n "${POSTGRES_PASSWORD:-}" ]] && \
     [[ -n "${POSTGRES_HOST:-}" ]] && [[ -n "${POSTGRES_PORT:-}" ]] && \
     [[ -n "${POSTGRES_DB:-}" ]]; then
    export DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
  fi

  if $_prev_u; then
    set -u
  fi
  if $_prev_x; then
    set -x
  fi
}

# ============================================================
# Auto-initialization
# ============================================================

# If CLAUDE_ROOT is not set, detect it
if [[ -z "${CLAUDE_ROOT:-}" ]]; then
  CLAUDE_ROOT=$(detect_claude_root)
  export CLAUDE_ROOT
fi
