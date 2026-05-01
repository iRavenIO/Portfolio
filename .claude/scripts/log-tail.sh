#!/usr/bin/env bash
# log-tail.sh — Claude Factory Log Viewer
# Provides secure, redacted viewing of Claude Factory run logs
# Part of Log Observability implementation (docs/policy/observability.md)

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="${LOG_DIR:-$REPO_ROOT/.claude/logs}"
REDACT_SCRIPT="$SCRIPT_DIR/redact.sh"

# ============================================================================
# REDACTION ENFORCEMENT
# ============================================================================

# Mandatory: source redact.sh unless REDACT_DISABLED=true
if [[ "${REDACT_DISABLED:-false}" != "true" ]]; then
  if [[ ! -f "$REDACT_SCRIPT" ]]; then
    echo "ERROR: Redaction library not found: $REDACT_SCRIPT" >&2
    echo "Cannot proceed without redaction capability. Aborting." >&2
    exit 1
  fi
  # shellcheck source=.claude/scripts/redact.sh
  source "$REDACT_SCRIPT"
fi

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS] [RUN_ID]

Claude Factory log viewer with mandatory secret redaction.

OPTIONS:
  -l, --list             List all available logs (sorted by modification time)
  -n, --lines NUM        Number of lines to display (default: 50)
  -f, --follow           Follow log in real-time (like tail -f)
  -r, --raw              Display raw log without redaction (requires REDACT_DISABLED=true)
  -h, --help             Show this help message

ARGUMENTS:
  RUN_ID                 Run ID or "latest" (default: latest)

EXAMPLES:
  $(basename "$0")                        # View latest log (50 lines, redacted)
  $(basename "$0") 20260210-153022        # View specific run log
  $(basename "$0") -n 100 latest          # View latest log (100 lines)
  $(basename "$0") -f latest              # Follow latest log in real-time
  $(basename "$0") -l                     # List all available logs
  REDACT_DISABLED=true $(basename "$0") -r latest   # View raw (no redaction)

NOTES:
  - All logs are redacted by default to protect secrets
  - Raw mode (-r) requires explicit REDACT_DISABLED=true environment variable
  - Follow mode (-f) uses redacted streaming

EOF
  exit 0
}

err() {
  echo "ERROR: $*" >&2
  exit 1
}

# Find all run logs, sorted by modification time (newest first)
find_logs() {
  if [[ ! -d "$LOG_DIR" ]]; then
    return 1
  fi

  # Find all run-*.log files, sort by mtime (newest first)
  find "$LOG_DIR" -name "run-*.log" -type f -print0 2>/dev/null | \
    xargs -0 ls -t 2>/dev/null || true
}

# Extract run ID from log file path
extract_run_id() {
  local log_path="$1"
  basename "$log_path" | sed 's/^run-\(.*\)\.log$/\1/'
}

# Get log file path from run ID
get_log_path() {
  local run_id="$1"

  # Handle "latest" keyword
  if [[ "$run_id" == "latest" ]]; then
    local latest
    latest=$(find_logs | head -n 1)
    if [[ -z "$latest" ]]; then
      err "No logs found in $LOG_DIR"
    fi
    echo "$latest"
    return 0
  fi

  # Check if exact run ID exists
  local log_path="$LOG_DIR/run-${run_id}.log"
  if [[ -f "$log_path" ]]; then
    echo "$log_path"
    return 0
  fi

  err "Log not found: $run_id"
}

# Format file size (human-readable)
format_size() {
  local bytes="$1"
  if [[ "$bytes" -lt 1024 ]]; then
    echo "${bytes}B"
  elif [[ "$bytes" -lt 1048576 ]]; then
    echo "$((bytes / 1024))K"
  else
    echo "$((bytes / 1048576))M"
  fi
}

# ============================================================================
# MODES
# ============================================================================

mode_list() {
  # List all available logs
  local logs
  logs=$(find_logs)

  if [[ -z "$logs" ]]; then
    echo "No logs found in $LOG_DIR"
    return 0
  fi

  echo "Available logs (newest first):"
  echo ""
  printf "%-20s  %10s  %s\n" "RUN_ID" "SIZE" "PATH"
  printf "%-20s  %10s  %s\n" "--------------------" "----------" "----"

  while IFS= read -r log_path; do
    local run_id
    run_id=$(extract_run_id "$log_path")
    local size
    size=$(stat -f %z "$log_path" 2>/dev/null || stat -c %s "$log_path" 2>/dev/null || echo "0")
    local size_human
    size_human=$(format_size "$size")

    printf "%-20s  %10s  %s\n" "$run_id" "$size_human" "$log_path"
  done <<< "$logs"
}

mode_view() {
  # View log (tail -n NUM, redacted)
  local run_id="$1"
  local num_lines="$2"

  local log_path
  log_path=$(get_log_path "$run_id")

  if [[ ! -f "$log_path" ]]; then
    err "Log file not found: $log_path"
  fi

  # Display log with redaction
  tail -n "$num_lines" "$log_path" | redact_stream
}

mode_follow() {
  # Follow log in real-time (tail -f, redacted)
  local run_id="$1"

  local log_path
  log_path=$(get_log_path "$run_id")

  if [[ ! -f "$log_path" ]]; then
    err "Log file not found: $log_path"
  fi

  echo "Following log: $log_path (Ctrl+C to stop)"
  echo ""

  # Follow with redaction
  tail -f "$log_path" | redact_stream
}

mode_raw() {
  # View raw log without redaction (requires REDACT_DISABLED=true)
  local run_id="$1"
  local num_lines="$2"

  if [[ "${REDACT_DISABLED:-false}" != "true" ]]; then
    err "Raw mode requires REDACT_DISABLED=true environment variable"
  fi

  local log_path
  log_path=$(get_log_path "$run_id")

  if [[ ! -f "$log_path" ]]; then
    err "Log file not found: $log_path"
  fi

  # Display raw log (no redaction)
  tail -n "$num_lines" "$log_path"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  local mode="view"
  local run_id="latest"
  local num_lines=50

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -l|--list)
        mode="list"
        shift
        ;;
      -n|--lines)
        num_lines="$2"
        shift 2
        ;;
      -f|--follow)
        mode="follow"
        shift
        ;;
      -r|--raw)
        mode="raw"
        shift
        ;;
      -h|--help)
        usage
        ;;
      -*)
        err "Unknown option: $1"
        ;;
      *)
        run_id="$1"
        shift
        ;;
    esac
  done

  # Validate num_lines is a number
  if ! [[ "$num_lines" =~ ^[0-9]+$ ]]; then
    err "Invalid number of lines: $num_lines"
  fi

  # Execute mode
  case "$mode" in
    list)
      mode_list
      ;;
    view)
      mode_view "$run_id" "$num_lines"
      ;;
    follow)
      mode_follow "$run_id"
      ;;
    raw)
      mode_raw "$run_id" "$num_lines"
      ;;
    *)
      err "Unknown mode: $mode"
      ;;
  esac
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
