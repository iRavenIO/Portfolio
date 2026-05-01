#!/usr/bin/env bash
# test-notifications.sh
# Test suite for notify-helpers.sh notification library

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_FAILED=0
TEST_PASSED=0

# Test assertion helpers
assert_success() {
  local msg="$1"
  TEST_PASSED=$((TEST_PASSED + 1))
  printf "[PASS] %s\n" "$msg"
}

assert_failure() {
  local msg="$1"
  TEST_FAILED=$((TEST_FAILED + 1))
  printf "[FAIL] %s\n" "$msg" >&2
}

# Stub 'say' command to capture calls via temp files
SAY_LOG="/tmp/test-notifications-say.log"
SAY_COUNT_FILE="/tmp/test-notifications-say-count"

say() {
  echo "$*" >> "$SAY_LOG"
  local count=0
  if [[ -f "$SAY_COUNT_FILE" ]]; then
    count=$(<"$SAY_COUNT_FILE")
  fi
  echo $((count + 1)) > "$SAY_COUNT_FILE"
  return 0
}

reset_say_stub() {
  rm -f "$SAY_LOG" "$SAY_COUNT_FILE"
  touch "$SAY_LOG"
  echo "0" > "$SAY_COUNT_FILE"
}

get_say_count() {
  if [[ -f "$SAY_COUNT_FILE" ]]; then
    cat "$SAY_COUNT_FILE"
  else
    echo "0"
  fi
}

get_say_last_msg() {
  if [[ -f "$SAY_LOG" ]]; then
    tail -n 1 "$SAY_LOG"
  else
    echo ""
  fi
}

# Initialize
reset_say_stub

# -----------------------------
# Test 1: Source notify-helpers.sh without errors
# -----------------------------
unset _NOTIFY_HELPERS_LOADED
if source "${SCRIPT_DIR}/notify-helpers.sh" 2>/dev/null; then
  assert_success "T1: notify-helpers.sh sources without errors"
else
  assert_failure "T1: notify-helpers.sh failed to source"
fi

# -----------------------------
# Test 2: Double-source guard prevents re-initialization
# -----------------------------
_NOTIFY_HELPERS_LOADED=""
source "${SCRIPT_DIR}/notify-helpers.sh" 2>/dev/null
marker1="${_NOTIFY_HELPERS_LOADED}"
source "${SCRIPT_DIR}/notify-helpers.sh" 2>/dev/null
marker2="${_NOTIFY_HELPERS_LOADED}"
if [[ "$marker1" == "$marker2" ]]; then
  assert_success "T2: Double-source guard works (marker unchanged)"
else
  assert_failure "T2: Double-source guard failed"
fi

# -----------------------------
# Test 3: CLAUDE_FACTORY_NOTIFY=0 disables notifications
# -----------------------------
unset _NOTIFY_HELPERS_LOADED
export CLAUDE_FACTORY_NOTIFY=0
source "${SCRIPT_DIR}/notify-helpers.sh"
reset_say_stub

notify_task_start 1 3 "Test task"
sleep 0.1  # Allow background 'say' to write
count=$(get_say_count)
if [[ "$count" -eq 0 ]]; then
  assert_success "T3: CLAUDE_FACTORY_NOTIFY=0 blocks notify_task_start"
else
  assert_failure "T3: CLAUDE_FACTORY_NOTIFY=0 did not block (called $count times)"
fi

# -----------------------------
# Test 4: CLAUDE_FACTORY_NOTIFY=1 enables notifications
# -----------------------------
unset _NOTIFY_HELPERS_LOADED
export CLAUDE_FACTORY_NOTIFY=1
source "${SCRIPT_DIR}/notify-helpers.sh"
reset_say_stub

notify_task_start 2 5 "Feature implementation"
sleep 0.1
count=$(get_say_count)
msg=$(get_say_last_msg)
if [[ "$count" -eq 1 ]] && [[ "$msg" == "Starting task 2 of 5: Feature implementation" ]]; then
  assert_success "T4: CLAUDE_FACTORY_NOTIFY=1 triggers notify_task_start with correct message"
else
  assert_failure "T4: CLAUDE_FACTORY_NOTIFY=1 did not trigger correctly (count=$count, msg=\"$msg\")"
fi

# -----------------------------
# Test 5: notify_task_end with "failed" status
# -----------------------------
reset_say_stub
notify_task_end 3 5 "1m 20s" "failed"
if [[ "$SAY_CALL_COUNT" -eq 1 ]] && [[ "$SAY_LAST_MSG" == "Task 3 of 5 failed" ]]; then
  assert_success "T5: notify_task_end with status=failed produces correct message"
else
  assert_failure "T5: notify_task_end failed status incorrect (msg=\"$SAY_LAST_MSG\")"
fi

# -----------------------------
# Test 6: notify_task_end with default (success) status
# -----------------------------
reset_say_stub
notify_task_end 4 5 "2m 10s"
if [[ "$SAY_CALL_COUNT" -eq 1 ]] && [[ "$SAY_LAST_MSG" == "Completed task 4 of 5 in 2m 10s" ]]; then
  assert_success "T6: notify_task_end default status produces success message"
else
  assert_failure "T6: notify_task_end default status incorrect (msg=\"$SAY_LAST_MSG\")"
fi

# -----------------------------
# Test 7: Syntax check install.sh
# -----------------------------
if bash -n "${SCRIPT_DIR}/../../install.sh" 2>/dev/null; then
  assert_success "T7: install.sh passes bash syntax check"
else
  assert_failure "T7: install.sh has syntax errors"
fi

# -----------------------------
# Summary
# -----------------------------
printf "\n========================================\n"
printf "TEST SUMMARY\n"
printf "========================================\n"
printf "PASSED: %d\n" "$TEST_PASSED"
printf "FAILED: %d\n" "$TEST_FAILED"
printf "========================================\n"

if [[ "$TEST_FAILED" -gt 0 ]]; then
  exit 1
else
  printf "\nALL TESTS PASSED ✓\n"
  exit 0
fi
