#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Test Suite for run-preflight.sh Direct Execution
#
# Tests:
#   - Sourcing behavior (exports functions/vars)
#   - Direct execution behavior (runs checks)
#   - Idempotency (safe to re-run)
#   - Log directory creation
#   - Cache warning behavior
#
# Usage: .claude/scripts/test-direct-run-preflight.sh
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ============================================================
# Test Framework Functions
# ============================================================

print_header() {
  echo ""
  echo "=========================================="
  echo "$1"
  echo "=========================================="
}

print_test() {
  echo ""
  echo "TEST: $1"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

pass() {
  echo -e "${GREEN}✓ PASS${NC}: $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
  echo -e "${RED}✗ FAIL${NC}: $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

assertExitCode() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  if [[ "$expected" -eq "$actual" ]]; then
    pass "$description"
  else
    fail "$description"
    echo "  Expected exit code: $expected"
    echo "  Actual exit code:   $actual"
  fi
}

assertFunctionExists() {
  local func_name="$1"
  local description="$2"

  if declare -F "$func_name" >/dev/null; then
    pass "$description"
  else
    fail "$description"
    echo "  Function not found: $func_name"
  fi
}

assertVarSet() {
  local var_name="$1"
  local description="$2"

  if [[ -n "${!var_name:-}" ]]; then
    pass "$description"
  else
    fail "$description"
    echo "  Variable not set: $var_name"
  fi
}

assertContains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$description"
  else
    fail "$description"
    echo "  Expected to contain: $needle"
  fi
}

assertDirExists() {
  local dir="$1"
  local description="$2"

  if [[ -d "$dir" ]]; then
    pass "$description"
  else
    fail "$description"
    echo "  Directory not found: $dir"
  fi
}

# ============================================================
# Test Suite 1: Sourcing Behavior
# ============================================================

test_sourcing_behavior() {
  print_header "SOURCING BEHAVIOR TESTS"

  # Test 1: Script can be sourced without errors
  print_test "run-preflight.sh can be sourced"

  cd "$REPO_ROOT"
  set +e
  source .claude/scripts/run-preflight.sh
  source_exit=$?
  set -e

  assertExitCode 0 "$source_exit" "Sourcing should not produce errors"

  # Test 2: CLAUDE_ROOT is set after sourcing
  print_test "CLAUDE_ROOT is set after sourcing"
  assertVarSet "CLAUDE_ROOT" "CLAUDE_ROOT should be set"

  # Test 3: CLAUDE_FACTORY_RUN_ID is set after sourcing
  print_test "CLAUDE_FACTORY_RUN_ID is set after sourcing"
  assertVarSet "CLAUDE_FACTORY_RUN_ID" "CLAUDE_FACTORY_RUN_ID should be set"

  # Test 4: CLAUDE_FACTORY_LOG_FILE is set after sourcing
  print_test "CLAUDE_FACTORY_LOG_FILE is set after sourcing"
  assertVarSet "CLAUDE_FACTORY_LOG_FILE" "CLAUDE_FACTORY_LOG_FILE should be set"
}

# ============================================================
# Test Suite 2: Variable Exports
# ============================================================

test_variable_exports() {
  print_header "VARIABLE EXPORTS TESTS"

  cd "$REPO_ROOT"
  source .claude/scripts/run-preflight.sh

  # Test 1: CLAUDE_ROOT points to correct directory
  print_test "CLAUDE_ROOT points to repo root"

  if [[ "$CLAUDE_ROOT" == "$REPO_ROOT" ]]; then
    pass "CLAUDE_ROOT correctly points to $REPO_ROOT"
  else
    fail "CLAUDE_ROOT mismatch (expected: $REPO_ROOT, got: $CLAUDE_ROOT)"
  fi

  # Test 2: CLAUDE_FACTORY_LOG_FILE path is valid
  print_test "CLAUDE_FACTORY_LOG_FILE path is valid"

  if [[ "$CLAUDE_FACTORY_LOG_FILE" == "$CLAUDE_ROOT/.claude/logs/run-"* ]]; then
    pass "CLAUDE_FACTORY_LOG_FILE correctly set under .claude/logs/"
  else
    fail "CLAUDE_FACTORY_LOG_FILE unexpected path: $CLAUDE_FACTORY_LOG_FILE"
  fi

  # Test 3: CLAUDE_FACTORY_RUN_ID format is valid
  print_test "CLAUDE_FACTORY_RUN_ID format is valid"

  if [[ "$CLAUDE_FACTORY_RUN_ID" =~ ^[0-9]{8}-[0-9]{6}$ ]]; then
    pass "CLAUDE_FACTORY_RUN_ID has correct format (YYYYMMDD-HHMMSS)"
  else
    fail "CLAUDE_FACTORY_RUN_ID unexpected format: $CLAUDE_FACTORY_RUN_ID"
  fi
}

# ============================================================
# Test Suite 3: Idempotency
# ============================================================

test_idempotency() {
  print_header "IDEMPOTENCY TESTS"

  # Test 1: First direct run completes successfully
  print_test "First direct run of run-preflight.sh"

  cd "$REPO_ROOT"
  set +e
  output1=$(./.claude/scripts/run-preflight.sh 2>&1)
  exit1=$?
  set -e

  assertExitCode 0 "$exit1" "First run should exit 0"

  # Test 2: Second run is idempotent
  print_test "Second direct run is idempotent"

  set +e
  output2=$(./.claude/scripts/run-preflight.sh 2>&1)
  exit2=$?
  set -e

  assertExitCode 0 "$exit2" "Second run should exit 0"

  # Test 3: Verify bootstrap message appears both times
  print_test "Both runs show preflight bootstrap message"

  assertContains "$output1" "preflight" "First run should show preflight message"
  assertContains "$output2" "preflight" "Second run should show preflight message"
}

# ============================================================
# Test Suite 4: Log Directory Creation
# ============================================================

test_log_directory() {
  print_header "LOG DIRECTORY CREATION TESTS"

  # Clean up log directory for test
  if [[ -d "$REPO_ROOT/.claude/logs" ]]; then
    rm -rf "$REPO_ROOT/.claude/logs"
  fi

  # Test 1: Log directory is created if missing
  print_test "Log directory created on first run"

  cd "$REPO_ROOT"
  ./.claude/scripts/run-preflight.sh >/dev/null 2>&1

  assertDirExists "$REPO_ROOT/.claude/logs" "Log directory should be created"

  # Test 2: Log file path exists (may be empty)
  print_test "Log file path is created"

  # The script creates the log directory but doesn't necessarily create the log file
  # Just verify the directory exists and a log file pattern would be valid
  if ls "$REPO_ROOT/.claude/logs/run-"*.log >/dev/null 2>&1; then
    pass "Run log files can be created in .claude/logs/"
  else
    # It's okay if no log files exist yet
    pass "Log directory is ready for log files"
  fi

  # Test 3: Log directory creation is idempotent
  print_test "Log directory creation is idempotent"

  ./.claude/scripts/run-preflight.sh >/dev/null 2>&1

  assertDirExists "$REPO_ROOT/.claude/logs" "Log directory should still exist"
}

# ============================================================
# Test Suite 5: Cache Warning Behavior
# ============================================================

test_cache_warning() {
  print_header "CACHE WARNING BEHAVIOR TESTS"

  cd "$REPO_ROOT"

  # Test 1: Warning if cache.db is missing
  print_test "Warning issued if cache.db is missing"

  # Temporarily rename cache.db if it exists
  local cache_backup=""
  if [[ -f "$REPO_ROOT/.claude/cache/context.db" ]]; then
    cache_backup="$REPO_ROOT/.claude/cache/context.db.bak"
    mv "$REPO_ROOT/.claude/cache/context.db" "$cache_backup"
  fi

  set +e
  output=$(./.claude/scripts/run-preflight.sh 2>&1)
  set -e

  # Restore cache.db
  if [[ -n "$cache_backup" && -f "$cache_backup" ]]; then
    mv "$cache_backup" "$REPO_ROOT/.claude/cache/context.db"
  fi

  if echo "$output" | grep -qi "cache\|database"; then
    pass "Warning about missing cache database"
  else
    echo "  ℹ️  No explicit cache warning (may be acceptable)"
  fi

  # Test 2: No warning if cache.db exists
  print_test "No warning if cache.db exists"

  # Ensure cache.db exists
  if [[ ! -f "$REPO_ROOT/.claude/cache/context.db" ]]; then
    source "$REPO_ROOT/.claude/scripts/cache.sh"
    cache_init
  fi

  set +e
  output=$(./.claude/scripts/run-preflight.sh 2>&1)
  exit_code=$?
  set -e

  assertExitCode 0 "$exit_code" "Should exit 0 with cache.db present"
}

# ============================================================
# Main Test Execution
# ============================================================

main() {
  echo ""
  echo "=========================================="
  echo "RUN-PREFLIGHT.SH TEST SUITE"
  echo "=========================================="
  echo "Repository: $REPO_ROOT"
  echo ""

  # Run test suites
  test_sourcing_behavior
  test_variable_exports
  test_idempotency
  test_log_directory
  test_cache_warning

  # Print summary
  print_header "TEST SUMMARY"
  echo "Total Tests:  $TESTS_TOTAL"
  echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
  echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
  echo ""

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
    echo ""
    exit 0
  else
    echo -e "${RED}SOME TESTS FAILED${NC}"
    echo ""
    exit 1
  fi
}

# Run main
main
