#!/usr/bin/env bash
# load-env-safe.sh — Safe environment loader for Claude Factory
# Usage: . .claude/scripts/load-env-safe.sh
# Loads .claude/env.claude and .claude/env.claude.local, rebuilds DATABASE_URL

set -euo pipefail

# Track which files were loaded
_loaded_files=()

_source_env_file() {
  local env_file="$1"
  local had_xtrace=0
  local had_nounset=0

  [[ $- == *x* ]] && had_xtrace=1 && set +x
  [[ $- == *u* ]] && had_nounset=1 && set +u

  set -a
  # shellcheck disable=SC1090
  source "$env_file"
  set +a

  if [[ $had_nounset -eq 1 ]]; then
    set -u
  fi
  if [[ $had_xtrace -eq 1 ]]; then
    set -x
  fi
}

# Load .claude/env.claude if present
if [[ -f .claude/env.claude ]]; then
  _source_env_file .claude/env.claude
  _loaded_files+=(".claude/env.claude")
fi

# Load .claude/env.claude.local if present (overrides base)
if [[ -f .claude/env.claude.local ]]; then
  _source_env_file .claude/env.claude.local
  _loaded_files+=(".claude/env.claude.local")
fi

# Rebuild DATABASE_URL after local secrets are loaded
# This ensures ${POSTGRES_PASSWORD} is not empty
if [[ -n "${POSTGRES_USER:-}" ]] && [[ -n "${POSTGRES_PASSWORD:-}" ]] && \
   [[ -n "${POSTGRES_HOST:-}" ]] && [[ -n "${POSTGRES_PORT:-}" ]] && \
   [[ -n "${POSTGRES_DB:-}" ]]; then
  export DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
fi

# Print presence summary (no values)
echo "✓ Env loaded from: ${_loaded_files[*]:-none}"
echo "✓ DATABASE_URL: $([[ -n "${DATABASE_URL:-}" ]] && echo "set" || echo "not set")"
echo "✓ POSTGRES_PASSWORD: $([[ -n "${POSTGRES_PASSWORD:-}" ]] && echo "set" || echo "not set")"
