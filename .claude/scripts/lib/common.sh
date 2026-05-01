#!/usr/bin/env bash
# common.sh — Common utility functions for factory scripts
# Provides: say, warn, err, have functions and color codes
# Usage: source "${BASH_SOURCE[0]%/*}/lib/common.sh"

# Double-source guard
if [[ "${__COMMON_SH_LOADED:-}" == "true" ]]; then
  return 0
fi
readonly __COMMON_SH_LOADED=true

# ============================================================
# Output Functions
# ============================================================

say()  { printf "%s\n" "$*"; }
warn() { printf "⚠️  %s\n" "$*" >&2; }
err()  { printf "❌ %s\n" "$*" >&2; }

# ============================================================
# Utility Functions
# ============================================================

have() { command -v "$1" >/dev/null 2>&1; }

resolve_ctags() {
  if [[ -n "${CLAUDE_FACTORY_CTAGS_BIN:-}" ]] && [[ -x "${CLAUDE_FACTORY_CTAGS_BIN}" ]]; then
    printf '%s\n' "$CLAUDE_FACTORY_CTAGS_BIN"
    return 0
  fi

  if [[ -x "/opt/homebrew/opt/universal-ctags/bin/ctags" ]]; then
    printf '%s\n' "/opt/homebrew/opt/universal-ctags/bin/ctags"
    return 0
  fi

  if [[ -x "/usr/local/opt/universal-ctags/bin/ctags" ]]; then
    printf '%s\n' "/usr/local/opt/universal-ctags/bin/ctags"
    return 0
  fi

  if have brew; then
    local brew_ctags
    brew_ctags="$(brew --prefix universal-ctags 2>/dev/null)/bin/ctags"
    if [[ -x "$brew_ctags" ]]; then
      printf '%s\n' "$brew_ctags"
      return 0
    fi
  fi

  if have ctags; then
    command -v ctags
    return 0
  fi

  return 1
}

# ============================================================
# Color Codes
# ============================================================

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly MAGENTA='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color
