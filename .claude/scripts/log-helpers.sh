# ============================================================
# Structured Logging Helper Library
#
# NOTE: This file is designed to be SOURCED, not executed.
# Do not run it directly. Use: source .claude/scripts/log-helpers.sh
#
# Sourced by run-with-logging.sh and multi-task orchestrators.
# Provides JSON-structured event logging with duration tracking.
#
# Usage:
#   source .claude/scripts/log-helpers.sh
#   log_init "$RUN_ID" "$LOG_FILE"
#   log_phase_start "phase1"
#   log_phase_end "phase1" "ok"
#   log_summary 1 1 0 "ok" "/path/to/report.md"
# ============================================================

# Guard against double-sourcing
[[ -n "${_LOG_HELPERS_LOADED:-}" ]] && return 0
_LOG_HELPERS_LOADED=1

# ============================================================
# Internal Helpers
# ============================================================

_log_iso_timestamp() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

_log_epoch_seconds() {
  date +%s
}

_log_escape_json() {
  local str="$1"
  # Remove carriage returns
  str="${str//$'\r'/}"
  # Escape backslashes
  str="${str//\\/\\\\}"
  # Escape double quotes
  str="${str//\"/\\\"}"
  # Escape newlines
  str="${str//$'\n'/\\n}"
  printf '%s' "$str"
}

_log_format_duration() {
  local total_seconds="$1"
  local minutes=$((total_seconds / 60))
  local seconds=$((total_seconds % 60))
  echo "${minutes}m ${seconds}s"
}

# ============================================================
# Public API
# ============================================================

log_init() {
  local run_id="$1"
  local log_file="$2"

  if [[ -z "$run_id" || -z "$log_file" ]]; then
    echo "ERROR: log_init requires run_id and log_file" >&2
    return 1
  fi

  export LOG_RUN_ID="$run_id"
  export LOG_FILE="$log_file"
  export _LOG_RUN_START_EPOCH
  _LOG_RUN_START_EPOCH="$(_log_epoch_seconds)"

  # Emit run_start event
  log_event "startup" "" "run_start" "ok" 0 "Run initialized: $run_id"
}

log_event() {
  local phase="$1"
  local task_id="$2"
  local event="$3"
  local status="$4"
  local duration_ms="$5"
  local message="$6"

  # Guard: ensure LOG_FILE is set
  if [[ -z "${LOG_FILE:-}" ]]; then
    echo "WARNING: log_event called but LOG_FILE not set. Did you call log_init?" >&2
    return 1
  fi

  local timestamp
  timestamp="$(_log_iso_timestamp)"
  local escaped_message
  escaped_message="$(_log_escape_json "$message")"

  # Build JSON line
  local json
  json=$(cat <<EOF
{"timestamp":"$timestamp","run_id":"${LOG_RUN_ID}","phase":"$phase","task_id":"$task_id","event":"$event","status":"$status","duration_ms":$duration_ms,"message":"$escaped_message"}
EOF
)

  echo "$json" >> "$LOG_FILE"
}

log_phase_start() {
  local phase="$1"
  local task_id="${2:-}"

  # Store start time in dynamic variable
  # CONSTRAINT: phase must contain only alphanumeric characters and underscores [a-zA-Z0-9_]
  # to ensure valid Bash variable names (e.g., _LOG_PHASE_START_phase1)
  printf -v "_LOG_PHASE_START_${phase}" '%s' "$SECONDS"

  log_event "$phase" "$task_id" "phase_start" "ok" 0 "Phase started: $phase"
}

log_phase_end() {
  local phase="$1"
  local status="$2"
  local task_id="${3:-}"
  local message="${4:-Phase completed: $phase}"

  # Retrieve start time from dynamic variable
  local _var="_LOG_PHASE_START_${phase}"
  local _start="${!_var:-$SECONDS}"
  local duration_sec=$((SECONDS - _start))
  local duration_ms=$((duration_sec * 1000))

  log_event "$phase" "$task_id" "phase_end" "$status" "$duration_ms" "$message"
}

log_task_start() {
  local task_id="$1"

  # Store start time in dynamic variable
  # CONSTRAINT: task_id must contain only alphanumeric characters and underscores [a-zA-Z0-9_]
  # to ensure valid Bash variable names (e.g., _LOG_TASK_START_1)
  printf -v "_LOG_TASK_START_${task_id}" '%s' "$SECONDS"

  log_event "task" "$task_id" "task_start" "ok" 0 "Task started: $task_id"
}

log_task_end() {
  local task_id="$1"
  local status="$2"

  # Retrieve start time from dynamic variable
  local _var="_LOG_TASK_START_${task_id}"
  local _start="${!_var:-$SECONDS}"
  local duration_sec=$((SECONDS - _start))
  local duration_ms=$((duration_sec * 1000))

  log_event "task" "$task_id" "task_end" "$status" "$duration_ms" "Task completed: $task_id"
}

log_error() {
  local phase="$1"
  local message="$2"
  local task_id="${3:-}"

  log_event "$phase" "$task_id" "error" "fail" 0 "$message"
}

log_info() {
  local phase="$1"
  local message="$2"
  local task_id="${3:-}"

  log_event "$phase" "$task_id" "info" "ok" 0 "$message"
}

log_summary() {
  local total_tasks="$1"
  local succeeded="$2"
  local failed="$3"
  local tags_status="$4"
  local report_path="$5"

  # Calculate total run duration
  local run_end_epoch
  run_end_epoch="$(_log_epoch_seconds)"
  local total_duration_sec=$((run_end_epoch - _LOG_RUN_START_EPOCH))
  local formatted_duration
  formatted_duration="$(_log_format_duration "$total_duration_sec")"

  # Write human-readable summary block
  cat >> "$LOG_FILE" <<EOF

========================================
RUN SUMMARY
========================================
Run ID:        $LOG_RUN_ID
Total Tasks:   $total_tasks
Succeeded:     $succeeded
Failed:        $failed
Tags Status:   $tags_status
Report:        $report_path
Duration:      $formatted_duration
========================================

EOF

  # Emit run_end JSON event
  log_event "summary" "" "run_end" "ok" $((total_duration_sec * 1000)) "Run completed: $succeeded succeeded, $failed failed"
}
