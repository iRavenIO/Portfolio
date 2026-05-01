# notify-helpers.sh
#
# Reusable notification functions for the Claude Software Factory pipeline.
# Provides task lifecycle voice notifications via macOS 'say' command.
#
# Usage:
#   source .claude/scripts/notify-helpers.sh
#   notify_task_start 1 3 "Implement feature X"
#   notify_task_end 1 3 "2m 15s"
#
# Environment Variables:
#   CLAUDE_FACTORY_NOTIFY=1    Enable voice notifications (default)
#   CLAUDE_FACTORY_NOTIFY=0    Disable all voice notifications
#
# Notes:
#   - This file is meant to be sourced, not executed directly (no shebang).
#   - Double-source protection prevents duplicate initialization.
#   - If 'say' is not available, a warning is printed once and notifications are silently disabled.

# -----------------------------
# Double-source guard
# -----------------------------
[[ -n "${_NOTIFY_HELPERS_LOADED:-}" ]] && return 0
_NOTIFY_HELPERS_LOADED=1

# -----------------------------
# Configuration
# -----------------------------
: "${CLAUDE_FACTORY_NOTIFY:=1}"

# -----------------------------
# Internal: speak text via macOS say
# -----------------------------
_notify_speak() {
  if [[ "$CLAUDE_FACTORY_NOTIFY" == "0" ]]; then return 0; fi
  local msg="$1"
  if command -v say &>/dev/null; then
    say "$msg" &
  elif [[ -z "${_NOTIFY_WARNED:-}" ]]; then
    _NOTIFY_WARNED=1
    printf '[notify] Warning: say command not available; notifications disabled.\n' >&2
  fi
}

# -----------------------------
# Public API
# -----------------------------

# notify_task_start <index> <total> <title>
#
# Announces the start of a task in a multi-task batch.
#
# Arguments:
#   $1 - Task index (1-based)
#   $2 - Total number of tasks
#   $3 - Task title
#
# Example:
#   notify_task_start 2 5 "Refactor authentication module"
#   => "Starting task 2 of 5: Refactor authentication module"
notify_task_start() {
  local idx="$1" total="$2" title="$3"
  _notify_speak "Starting task ${idx} of ${total}: ${title}"
}

# notify_task_end <index> <total> <duration> [status]
#
# Announces the completion or failure of a task.
#
# Arguments:
#   $1 - Task index (1-based)
#   $2 - Total number of tasks
#   $3 - Duration string (e.g., "2m 15s")
#   $4 - Status: "ok" (default) or "failed"
#
# Examples:
#   notify_task_end 2 5 "1m 30s"
#   => "Completed task 2 of 5 in 1m 30s"
#
#   notify_task_end 3 5 "0m 45s" "failed"
#   => "Task 3 of 5 failed"
notify_task_end() {
  local idx="$1" total="$2" duration="$3" status="${4:-ok}"
  if [[ "$status" == "failed" ]]; then
    _notify_speak "Task ${idx} of ${total} failed"
  else
    _notify_speak "Completed task ${idx} of ${total} in ${duration}"
  fi
}
