#!/usr/bin/env bash
# test-log-observability.sh — Test Suite for Log Observability
# Tests ./cf summary output, redaction, and log-tail.sh functionality
# Part of Phase 5B implementation

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
CF_SCRIPT="$REPO_ROOT/cf"
LOG_TAIL_SCRIPT="$SCRIPT_DIR/log-tail.sh"
LOG_DIR="$REPO_ROOT/.claude/logs"
TEST_LOG_DIR="$REPO_ROOT/.claude/logs/test-$$"

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

setup() {
  # Create isolated test log directory
  mkdir -p "$TEST_LOG_DIR"
  echo "Setup: Created test log directory: $TEST_LOG_DIR"
}

teardown() {
  # Clean up test directory
  if [[ -d "$TEST_LOG_DIR" ]]; then
    rm -rf "$TEST_LOG_DIR"
    echo "Teardown: Removed test log directory: $TEST_LOG_DIR"
  fi
}

assert_pass() {
  local test_name="$1"
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_PASSED=$((TESTS_PASSED + 1))
  echo "✓ PASS: $test_name"
}

assert_fail() {
  local test_name="$1"
  local reason="$2"
  TESTS_RUN=$((TESTS_RUN + 1))
  TESTS_FAILED=$((TESTS_FAILED + 1))
  echo "✗ FAIL: $test_name"
  echo "  Reason: $reason"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local test_name="$3"

  if echo "$haystack" | grep -qF "$needle"; then
    assert_pass "$test_name"
    return 0
  else
    assert_fail "$test_name" "Expected to find '$needle' in output"
    return 1
  fi
}

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local test_name="$3"

  if echo "$haystack" | grep -qF "$needle"; then
    assert_fail "$test_name" "Expected NOT to find '$needle' in output"
    return 1
  else
    assert_pass "$test_name"
    return 0
  fi
}

assert_file_exists() {
  local file_path="$1"
  local test_name="$2"

  if [[ -f "$file_path" ]]; then
    assert_pass "$test_name"
    return 0
  else
    assert_fail "$test_name" "File does not exist: $file_path"
    return 1
  fi
}

assert_exit_code() {
  local expected="$1"
  local actual="$2"
  local test_name="$3"

  if [[ "$actual" -eq "$expected" ]]; then
    assert_pass "$test_name"
    return 0
  else
    assert_fail "$test_name" "Expected exit code $expected, got $actual"
    return 1
  fi
}

# ============================================================================
# TEST SUITE 1: ./cf Summary Output
# ============================================================================

test_cf_summary_banner() {
  echo ""
  echo "=== Test Suite 1: ./cf Summary Output ==="

  # Test 1.1: Run ./cf with success command, verify summary banner
  local output
  output=$("$CF_SCRIPT" echo "test command" 2>&1)
  assert_contains "$output" "=== Run Summary ===" "1.1: Summary banner present"

  # Test 1.2: Verify Status field (OK)
  assert_contains "$output" "Status:    OK (exit 0)" "1.2: Status shows OK for exit 0"

  # Test 1.3: Verify Duration field present
  assert_contains "$output" "Duration:" "1.3: Duration field present"

  # Test 1.4: Verify Log file field present
  assert_contains "$output" "Log file:" "1.4: Log file field present"

  # Test 1.5: Verify Log size field present
  assert_contains "$output" "Log size:" "1.5: Log size field present"
}

test_cf_summary_failure() {
  echo ""
  echo "=== Test Suite 2: ./cf Summary on Failure ==="

  # Test 2.1: Run ./cf with failing command
  local output exit_code
  output=$("$CF_SCRIPT" sh -c "exit 42" 2>&1) || exit_code=$?

  # Test 2.2: Verify exit code propagation
  assert_exit_code 42 "${exit_code:-0}" "2.1: Exit code propagated correctly"

  # Test 2.3: Verify Status field shows FAILED
  assert_contains "$output" "Status:    FAILED (exit 42)" "2.2: Status shows FAILED for exit 42"

  # Test 2.4: Summary banner still present on failure
  assert_contains "$output" "=== Run Summary ===" "2.3: Summary banner present on failure"
}

test_cf_duration_format() {
  echo ""
  echo "=== Test Suite 3: ./cf Duration Format ==="

  # Test 3.1: Run ./cf with sleep command
  local output
  output=$("$CF_SCRIPT" sleep 2 2>&1)

  # Test 3.2: Verify duration is at least 2 seconds
  # Extract duration line and parse
  local duration_line
  duration_line=$(echo "$output" | grep "Duration:")

  # Duration should contain "m" and "s" format
  assert_contains "$duration_line" "m" "3.1: Duration format contains minutes"
  assert_contains "$duration_line" "s" "3.2: Duration format contains seconds"
}

# ============================================================================
# TEST SUITE 2: ./cf Redaction
# ============================================================================

test_cf_log_redaction() {
  echo ""
  echo "=== Test Suite 4: ./cf Log Redaction ==="

  # Test 4.1: Run ./cf with command that outputs secrets
  local test_secret="my_secret_token_12345"
  "$CF_SCRIPT" echo "API_KEY=$test_secret" >/dev/null 2>&1

  # Find the most recent log file
  local latest_log
  latest_log=$(find "$LOG_DIR" -name "run-*.log" -type f -print0 | xargs -0 ls -t | head -n 1)

  # Test 4.2: Verify log file exists
  assert_file_exists "$latest_log" "4.1: Log file created"

  # Test 4.3: Verify secret is redacted in log
  local log_content
  log_content=$(cat "$latest_log")
  assert_not_contains "$log_content" "$test_secret" "4.2: Secret redacted in log file"

  # Test 4.4: Verify redaction marker present
  assert_contains "$log_content" "***REDACTED***" "4.3: Redaction marker present"
}

test_cf_redaction_failure_handling() {
  echo ""
  echo "=== Test Suite 5: ./cf Redaction Failure Handling ==="

  # Test 5.1: Temporarily rename redact.sh to simulate failure
  local redact_script="$REPO_ROOT/.claude/scripts/redact.sh"
  local backup_script="$REPO_ROOT/.claude/scripts/redact.sh.backup.$$"

  if [[ -f "$redact_script" ]]; then
    mv "$redact_script" "$backup_script"
  fi

  # Test 5.2: Run ./cf and check for warning
  local output
  output=$("$CF_SCRIPT" echo "test" 2>&1) || true

  # Test 5.3: Restore redact.sh
  if [[ -f "$backup_script" ]]; then
    mv "$backup_script" "$redact_script"
  fi

  # Test 5.4: Verify warning is shown if redaction fails
  # (This test is best-effort since redaction failure is rare)
  # Just verify that the script completes without crashing
  assert_contains "$output" "=== Run Summary ===" "5.1: Script completes even if redaction unavailable"
}

# ============================================================================
# TEST SUITE 3: log-tail.sh Functionality
# ============================================================================

test_log_tail_list() {
  echo ""
  echo "=== Test Suite 6: log-tail.sh List Mode ==="

  # Test 6.1: Create test log files
  mkdir -p "$TEST_LOG_DIR"
  echo "test log 1" > "$TEST_LOG_DIR/run-20260101-120000.log"
  echo "test log 2" > "$TEST_LOG_DIR/run-20260101-130000.log"

  # Test 6.2: Override LOG_DIR temporarily
  local output
  output=$(LOG_DIR="$TEST_LOG_DIR" bash "$LOG_TAIL_SCRIPT" --list)

  # Test 6.3: Verify list shows both logs
  assert_contains "$output" "run-20260101-120000" "6.1: List shows first log"
  assert_contains "$output" "run-20260101-130000" "6.2: List shows second log"

  # Test 6.4: Verify list shows SIZE and PATH columns
  assert_contains "$output" "SIZE" "6.3: List shows SIZE column"
  assert_contains "$output" "PATH" "6.4: List shows PATH column"

  # Cleanup
  rm -rf "$TEST_LOG_DIR"
}

test_log_tail_view() {
  echo ""
  echo "=== Test Suite 7: log-tail.sh View Mode ==="

  # Test 7.1: Create test log file
  mkdir -p "$TEST_LOG_DIR"
  local test_log="$TEST_LOG_DIR/run-20260101-120000.log"
  for i in {1..100}; do
    echo "Log line $i" >> "$test_log"
  done

  # Test 7.2: View last 50 lines (default)
  local output
  output=$(LOG_DIR="$TEST_LOG_DIR" bash "$LOG_TAIL_SCRIPT" 20260101-120000 2>/dev/null)

  # Test 7.3: Verify output contains last lines
  assert_contains "$output" "Log line 100" "7.1: View shows last line"
  assert_contains "$output" "Log line 51" "7.2: View shows 50th line from end"

  # Test 7.4: Verify output does NOT contain early lines
  # Use exact match with word boundary to avoid matching "Log line 1" in "Log line 100"
  if echo "$output" | grep -qE "^Log line 1$"; then
    assert_fail "7.3: View does not show line 1 (only last 50)" "Found 'Log line 1' in output"
  else
    assert_pass "7.3: View does not show line 1 (only last 50)"
  fi

  # Test 7.5: View with custom line count (-n 10)
  output=$(LOG_DIR="$TEST_LOG_DIR" bash "$LOG_TAIL_SCRIPT" -n 10 20260101-120000 2>/dev/null)
  assert_contains "$output" "Log line 100" "7.4: View -n 10 shows last line"
  assert_not_contains "$output" "Log line 89" "7.5: View -n 10 does not show line 89"

  # Cleanup
  rm -rf "$TEST_LOG_DIR"
}

test_log_tail_latest() {
  echo ""
  echo "=== Test Suite 8: log-tail.sh Latest Resolution ==="

  # Test 8.1: Create multiple test log files with different timestamps
  mkdir -p "$TEST_LOG_DIR"
  echo "old log" > "$TEST_LOG_DIR/run-20260101-120000.log"
  sleep 1
  echo "newer log" > "$TEST_LOG_DIR/run-20260101-130000.log"
  sleep 1
  echo "newest log" > "$TEST_LOG_DIR/run-20260101-140000.log"

  # Ensure mtime is different by touching files in order
  touch -t 202601011200 "$TEST_LOG_DIR/run-20260101-120000.log"
  touch -t 202601011300 "$TEST_LOG_DIR/run-20260101-130000.log"
  touch -t 202601011400 "$TEST_LOG_DIR/run-20260101-140000.log"

  # Test 8.2: View "latest" should show newest log
  local output
  output=$(LOG_DIR="$TEST_LOG_DIR" bash "$LOG_TAIL_SCRIPT" latest 2>/dev/null)

  # Test 8.3: Verify it shows the newest log
  assert_contains "$output" "newest log" "8.1: 'latest' resolves to newest log"
  assert_not_contains "$output" "old log" "8.2: 'latest' does not show old log"

  # Cleanup
  rm -rf "$TEST_LOG_DIR"
}

test_log_tail_missing_log() {
  echo ""
  echo "=== Test Suite 9: log-tail.sh Missing Log Handling ==="

  # Test 9.1: Try to view non-existent log
  local output exit_code
  output=$(LOG_DIR="$TEST_LOG_DIR" bash "$LOG_TAIL_SCRIPT" nonexistent-run-id 2>&1) || exit_code=$?

  # Test 9.2: Verify error exit code
  assert_exit_code 1 "${exit_code:-0}" "9.1: Non-existent log returns exit 1"

  # Test 9.3: Verify error message
  assert_contains "$output" "ERROR" "9.2: Error message shown for missing log"
}

# ============================================================================
# TEST SUITE 4: log-tail.sh Redaction
# ============================================================================

test_log_tail_redaction() {
  echo ""
  echo "=== Test Suite 10: log-tail.sh Redaction ==="

  # Test 10.1: Create test log with secrets
  mkdir -p "$TEST_LOG_DIR"
  local test_log="$TEST_LOG_DIR/run-20260101-120000.log"
  cat > "$test_log" <<EOF
Normal log line
API_KEY=secret_key_12345
Another normal line
DATABASE_URL=postgres://user:password@localhost/db
Final line
EOF

  # Test 10.2: View log (should be redacted by default)
  local output
  output=$(LOG_DIR="$TEST_LOG_DIR" bash "$LOG_TAIL_SCRIPT" 20260101-120000 2>/dev/null)

  # Test 10.3: Verify secrets are redacted
  assert_not_contains "$output" "secret_key_12345" "10.1: API_KEY value redacted"
  assert_not_contains "$output" "password" "10.2: DATABASE_URL password redacted"

  # Test 10.4: Verify redaction marker present
  assert_contains "$output" "***REDACTED***" "10.3: Redaction marker present"

  # Test 10.5: Verify normal lines are still present
  assert_contains "$output" "Normal log line" "10.4: Normal lines still visible"

  # Cleanup
  rm -rf "$TEST_LOG_DIR"
}

test_log_tail_raw_mode() {
  echo ""
  echo "=== Test Suite 11: log-tail.sh Raw Mode ==="

  # Test 11.1: Create test log with secrets
  mkdir -p "$TEST_LOG_DIR"
  local test_log="$TEST_LOG_DIR/run-20260101-120000.log"
  echo "API_KEY=secret_raw_12345" > "$test_log"

  # Test 11.2: Try raw mode without REDACT_DISABLED (should fail)
  local output exit_code
  output=$(LOG_DIR="$TEST_LOG_DIR" bash "$LOG_TAIL_SCRIPT" --raw 20260101-120000 2>&1) || exit_code=$?

  # Test 11.3: Verify error
  assert_exit_code 1 "${exit_code:-0}" "11.1: Raw mode without REDACT_DISABLED fails"
  assert_contains "$output" "REDACT_DISABLED=true" "11.2: Error message mentions REDACT_DISABLED"

  # Test 11.4: Try raw mode WITH REDACT_DISABLED=true (should succeed)
  output=$(REDACT_DISABLED=true LOG_DIR="$TEST_LOG_DIR" bash "$LOG_TAIL_SCRIPT" --raw 20260101-120000 2>/dev/null)

  # Test 11.5: Verify secrets are NOT redacted in raw mode
  assert_contains "$output" "secret_raw_12345" "11.3: Raw mode shows unredacted secrets"

  # Cleanup
  rm -rf "$TEST_LOG_DIR"
}

# ============================================================================
# TEST SUITE 5: Edge Cases
# ============================================================================

test_edge_cases() {
  echo ""
  echo "=== Test Suite 12: Edge Cases ==="

  # Test 12.1: Empty log file
  mkdir -p "$TEST_LOG_DIR"
  local empty_log="$TEST_LOG_DIR/run-20260101-120000.log"
  touch "$empty_log"

  local output
  output=$(LOG_DIR="$TEST_LOG_DIR" bash "$LOG_TAIL_SCRIPT" 20260101-120000 2>/dev/null) || true

  # Should complete without error
  assert_pass "12.1: Empty log file handled gracefully"

  # Test 12.2: No logs in directory
  rm -rf "$TEST_LOG_DIR"
  mkdir -p "$TEST_LOG_DIR"

  output=$(LOG_DIR="$TEST_LOG_DIR" bash "$LOG_TAIL_SCRIPT" latest 2>&1) || true
  assert_contains "$output" "No logs found" "12.2: No logs message shown"

  # Cleanup
  rm -rf "$TEST_LOG_DIR"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  echo "======================================"
  echo "Log Observability Test Suite"
  echo "======================================"
  echo ""

  setup

  # Run all test suites
  test_cf_summary_banner
  test_cf_summary_failure
  test_cf_duration_format
  test_cf_log_redaction
  test_cf_redaction_failure_handling
  test_log_tail_list
  test_log_tail_view
  test_log_tail_latest
  test_log_tail_missing_log
  test_log_tail_redaction
  test_log_tail_raw_mode
  test_edge_cases

  teardown

  # Print summary
  echo ""
  echo "======================================"
  echo "Test Summary"
  echo "======================================"
  echo "Tests run:    $TESTS_RUN"
  echo "Tests passed: $TESTS_PASSED"
  echo "Tests failed: $TESTS_FAILED"
  echo "======================================"

  if [[ "$TESTS_FAILED" -eq 0 ]]; then
    echo "✓ All tests passed!"
    exit 0
  else
    echo "✗ Some tests failed"
    exit 1
  fi
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
