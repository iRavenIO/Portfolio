#!/usr/bin/env bash
set -Eeuo pipefail

# ╔═══════════════════════════════════════════════════════════════╗
# ║  🔍 Claude Factory — run-with-logging.sh                      ║
# ║  Observability-enhanced execution wrapper                     ║
# ╚═══════════════════════════════════════════════════════════════╝
#
# Runs a command while capturing stdout and stderr to a timestamped
# log file under .claude/logs/. Supports enhanced observability
# features like pre-flight checks, health validation, and execution
# metrics reporting.
#
# Usage:
#   .claude/scripts/run-with-logging.sh <command> [args...]
#
# Example:
#   .claude/scripts/run-with-logging.sh claude "build the login page"
#
# Options (via environment variables):
#   CLAUDE_FACTORY_SKIP_HEALTH_CHECK=1  Skip pre-flight health check
#   CLAUDE_FACTORY_LOG_METRICS=1        Enable detailed metrics logging
#
# Output is preserved on the terminal via tee.
# Log files: .claude/logs/run-YYYYMMDD-HHMMSS.log
#
# See docs/policy/observability.md for full details.
#
# ⚠️  DEPRECATION NOTICE:
# This script is being replaced by ./cf (a simpler POSIX sh runner).
# run-with-logging.sh will remain available for advanced use cases
# (health checks, metrics logging) but ./cf is now the recommended
# default for standard factory runs.
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$REPO_ROOT/.claude/logs"

# Configuration
SKIP_HEALTH_CHECK="${CLAUDE_FACTORY_SKIP_HEALTH_CHECK:-0}"
LOG_METRICS="${CLAUDE_FACTORY_LOG_METRICS:-0}"

# Source redaction library (with fallback stub)
if [[ -f "$SCRIPT_DIR/redact.sh" ]]; then
  source "$SCRIPT_DIR/redact.sh"
else
  # Fallback stub if redact.sh is unavailable
  redact_stream() { cat; }
fi

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Generate run ID from current timestamp
RUN_ID="$(date +%Y%m%d-%H%M%S)"
LOG_FILE="$LOG_DIR/run-${RUN_ID}.log"

# Validate that a command was provided
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 <command> [args...]"
  echo "Example: $0 claude \"build the login page\""
  echo ""
  echo "Options (environment variables):"
  echo "  CLAUDE_FACTORY_SKIP_HEALTH_CHECK=1  Skip pre-flight checks"
  echo "  CLAUDE_FACTORY_LOG_METRICS=1        Enable detailed metrics"
  echo ""
  exit 1
fi

# Source logging helpers (if available)
if [[ -f "$SCRIPT_DIR/log-helpers.sh" ]]; then
  source "$SCRIPT_DIR/log-helpers.sh"
  LOG_HELPERS_AVAILABLE=1
else
  LOG_HELPERS_AVAILABLE=0
fi

# Initialize logging system
if [[ $LOG_HELPERS_AVAILABLE -eq 1 ]]; then
  log_init "$RUN_ID" "$LOG_FILE"
fi

echo "╔═══════════════════════════════════════════════════════════════════════╗"
echo "║  🔍 Claude Factory — Observability-Enhanced Execution                ║"
echo "╚═══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Run ID:       $RUN_ID"
echo "Log file:     $LOG_FILE"
echo "Command:      $(echo "$*" | redact_stream)"
echo "Timestamp:    $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "Metrics:      $(if [[ $LOG_METRICS -eq 1 ]]; then echo "ENABLED"; else echo "DISABLED"; fi)"
echo ""

# Environment variable report
if [[ $LOG_METRICS -eq 1 ]]; then
  echo "Environment Variables:"
  echo "  CLAUDE_FACTORY_AUTO_COMMIT=${CLAUDE_FACTORY_AUTO_COMMIT:-1}"
  echo "  CLAUDE_FACTORY_SKIP_CONFIRMATION=${CLAUDE_FACTORY_SKIP_CONFIRMATION:-0}"
  echo "  CLAUDE_FACTORY_CTAGS_MODE=${CLAUDE_FACTORY_CTAGS_MODE:-smart}"
  echo "  CLAUDE_FACTORY_SKIP_HEALTH_CHECK=$SKIP_HEALTH_CHECK"
  echo ""
fi

# Pre-flight health check
if [[ $SKIP_HEALTH_CHECK -eq 0 ]]; then
  if [[ -x "$REPO_ROOT/.claude/scripts/health-check.sh" ]]; then
    echo "🔎 Running pre-flight health check..."
    if "$REPO_ROOT/.claude/scripts/health-check.sh"; then
      echo "  ✅ Health check passed"
    else
      echo "  ⚠️  Health check reported issues — continuing anyway"
    fi
    echo ""
  fi
fi

# Log command info
if [[ $LOG_HELPERS_AVAILABLE -eq 1 ]]; then
  log_info "startup" "Command: $(echo "$*" | redact_stream)"
fi

# Set up exit trap for summary logging
_run_start_time=$(date +%s)
_run_exit_code=0
_run_cleanup() {
  _run_exit_code=${_run_exit_code:-$?}
  local _run_end_time=$(date +%s)
  local _run_duration=$((_run_end_time - _run_start_time))
  local _run_duration_min=$((_run_duration / 60))
  local _run_duration_sec=$((_run_duration % 60))

  echo ""
  echo "════════════════════════════════════════════════════════════════════════"
  if [[ "$_run_exit_code" -eq 0 ]]; then
    echo "✅ Execution complete"
  else
    echo "❌ Execution failed with exit code $_run_exit_code"
  fi
  echo "Duration: ${_run_duration_min}m ${_run_duration_sec}s"
  echo "════════════════════════════════════════════════════════════════════════"

  # Log summary if helpers available
  if [[ $LOG_HELPERS_AVAILABLE -eq 1 ]]; then
    local _status="ok"
    [[ "$_run_exit_code" -ne 0 ]] && _status="fail"
    local _succeeded=0 _failed=0
    if [[ "$_status" == "ok" ]]; then _succeeded=1; else _failed=1; fi
    log_summary "1" "$_succeeded" "$_failed" "unknown" ""
  fi

  # Report location hint
  if [[ -d "$REPO_ROOT/docs/tasks/reports" ]]; then
    local _latest_report=$(ls -t "$REPO_ROOT/docs/tasks/reports"/*.md 2>/dev/null | head -1 || true)
    if [[ -n "$_latest_report" ]]; then
      echo ""
      echo "📄 Latest report: $_latest_report"
    fi
  fi
}
trap _run_cleanup EXIT

echo "════════════════════════════════════════════════════════════════════════"
echo "🚀 Starting execution..."
echo "════════════════════════════════════════════════════════════════════════"
echo ""

# Execute the command, piping both stdout and stderr through redaction and tee
exec > >(redact_stream | tee -a "$LOG_FILE") 2>&1

# Run the provided command with all arguments
"$@" && _run_exit_code=0 || _run_exit_code=$?

# Exit with the captured exit code
exit $_run_exit_code
