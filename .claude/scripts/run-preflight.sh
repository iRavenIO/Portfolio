#!/usr/bin/env bash
# run-preflight.sh — Direct Run Bootstrap
#
# Ensures CLAUDE_FACTORY_RUN_ID and CLAUDE_FACTORY_LOG_FILE are always
# available, whether the user ran ./cf or invoked claude directly.
#
# NOTE: This file is designed to be SOURCED, not executed.
#   source .claude/scripts/run-preflight.sh

# ── Double-source guard ──────────────────────────────────────────
[[ -n "${_RUN_PREFLIGHT_LOADED:-}" ]] && return 0
_RUN_PREFLIGHT_LOADED=1

# ── Derive CLAUDE_ROOT ───────────────────────────────────────────
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  CLAUDE_ROOT="${CLAUDE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
else
  CLAUDE_ROOT="${CLAUDE_ROOT:-$(pwd)}"
fi

# ── Skip if already bootstrapped (./cf was used) ─────────────────
if [[ -n "${CLAUDE_FACTORY_RUN_ID:-}" ]]; then
  return 0
fi

# ── Generate Run ID ──────────────────────────────────────────────
CLAUDE_FACTORY_RUN_ID="$(date +%Y%m%d-%H%M%S)"
CLAUDE_FACTORY_LOG_FILE="${CLAUDE_ROOT}/.claude/logs/run-${CLAUDE_FACTORY_RUN_ID}.log"

# ── Ensure log directory ─────────────────────────────────────────
mkdir -p "${CLAUDE_ROOT}/.claude/logs"

# ── Export for downstream consumers ──────────────────────────────
export CLAUDE_FACTORY_RUN_ID
export CLAUDE_FACTORY_LOG_FILE

# ── Install bootstrap check ──────────────────────────────────────
if [[ ! -f "${CLAUDE_ROOT}/.claude/cache/cache.db" ]]; then
  printf '[preflight] Warning: Cache DB not found. Run ./install.sh to bootstrap.\n' >&2
fi

# ── Confirmation ─────────────────────────────────────────────────
printf '[preflight] Run ID: %s\n' "$CLAUDE_FACTORY_RUN_ID" >&2
printf '[preflight] Log: %s\n' "$CLAUDE_FACTORY_LOG_FILE" >&2
