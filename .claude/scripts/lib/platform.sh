#!/usr/bin/env bash
# platform.sh — Platform detection and compatibility
# Provides: is_macos, is_linux, platform_stat, platform_* wrappers
# Usage: source "${BASH_SOURCE[0]%/*}/lib/platform.sh"

# Double-source guard
if [[ "${__PLATFORM_SH_LOADED:-}" == "true" ]]; then
  return 0
fi
readonly __PLATFORM_SH_LOADED=true

# ============================================================
# Platform Detection
# ============================================================

is_macos() {
  [[ "$(uname)" == "Darwin" ]]
}

is_linux() {
  [[ "$(uname)" == "Linux" ]]
}

# ============================================================
# Platform-Specific Wrappers
# ============================================================

# Get file modification time (Unix timestamp)
platform_stat() {
  local file="$1"
  if is_macos; then
    stat -f "%m" "$file" 2>/dev/null
  else
    stat -c "%Y" "$file" 2>/dev/null
  fi
}

# Get file size in bytes
platform_stat_size() {
  local file="$1"
  if is_macos; then
    stat -f "%z" "$file" 2>/dev/null
  else
    stat -c "%s" "$file" 2>/dev/null
  fi
}

# Get platform name
platform_name() {
  if is_macos; then
    echo "macOS"
  elif is_linux; then
    echo "Linux"
  else
    echo "Unknown"
  fi
}
