#!/usr/bin/env bash
# test-framework.sh — Test framework for factory test scripts
# Provides: pass, fail, assert functions, test counters, test summary
# Usage: source "${BASH_SOURCE[0]%/*}/lib/test-framework.sh"

# Double-source guard
if [[ "${__TEST_FRAMEWORK_SH_LOADED:-}" == "true" ]]; then
  return 0
fi
readonly __TEST_FRAMEWORK_SH_LOADED=true

# Source common utilities
LIB_DIR="${BASH_SOURCE[0]%/*}"
source "$LIB_DIR/common.sh"

# ============================================================
# Test Counters
# ============================================================

TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_RUN=0
PASS_COUNT=0
FAIL_COUNT=0

# ============================================================
# Test Output Functions
# ============================================================

pass() {
  echo -e "${GREEN}✓ PASS${NC}: $1"
  ((TESTS_PASSED++))
  ((PASS_COUNT++))
  ((TESTS_RUN++))
}

fail() {
  local message="$1"
  local detail="${2:-}"
  echo -e "${RED}✗ FAIL${NC}: $message" >&2
  if [[ -n "$detail" ]]; then
    echo "  Error: $detail" >&2
  fi
  ((TESTS_FAILED++))
  ((FAIL_COUNT++))
  ((TESTS_RUN++))
}

info() {
  echo -e "${YELLOW}ℹ${NC} $1"
}

print_header() {
  echo ""
  echo "=========================================="
  echo "$1"
  echo "=========================================="
}

print_test() {
  echo ""
  echo "TEST: $1"
  ((TESTS_TOTAL++))
}

# ============================================================
# Assertion Functions
# ============================================================

assertEqual() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  if [[ "$expected" == "$actual" ]]; then
    pass "$description"
  else
    fail "$description"
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
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
    echo "  Actual: $haystack"
  fi
}

assertNotContains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$description"
  else
    fail "$description"
    echo "  Expected NOT to contain: $needle"
    echo "  Actual: $haystack"
  fi
}

assertFileExists() {
  local file="$1"
  local description="$2"

  if [[ -f "$file" ]]; then
    pass "$description"
  else
    fail "$description"
    echo "  File not found: $file"
  fi
}

assertFileNotExists() {
  local file="$1"
  local description="$2"

  if [[ ! -f "$file" ]]; then
    pass "$description"
  else
    fail "$description"
    echo "  File should not exist: $file"
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

assertNotEmpty() {
  local value="$1"
  local description="$2"

  if [[ -n "$value" ]]; then
    pass "$description"
  else
    fail "$description"
    echo "  Value was empty"
  fi
}

assertEmpty() {
  local value="$1"
  local description="$2"

  if [[ -z "$value" ]]; then
    pass "$description"
  else
    fail "$description"
    echo "  Expected empty, got: $value"
  fi
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

assert_success() {
  local exit_code=$?
  local description="$1"

  if [[ $exit_code -eq 0 ]]; then
    pass "$description"
  else
    fail "$description" "Command exited with code $exit_code"
  fi
}

assert_failure() {
  local exit_code=$?
  local description="$1"

  if [[ $exit_code -ne 0 ]]; then
    pass "$description"
  else
    fail "$description" "Command succeeded but should have failed"
  fi
}

assert_pass() {
  local description="$1"
  pass "$description"
}

assert_fail() {
  local description="$1"
  local detail="${2:-}"
  fail "$description" "$detail"
}

# ============================================================
# Test Summary
# ============================================================

test_summary() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "Test Summary"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local total=$((TESTS_PASSED + TESTS_FAILED))
  if [[ $total -eq 0 ]]; then
    total=$((PASS_COUNT + FAIL_COUNT))
  fi
  if [[ $TESTS_RUN -gt 0 ]]; then
    total=$TESTS_RUN
  fi
  if [[ $TESTS_TOTAL -gt 0 && $total -eq 0 ]]; then
    total=$TESTS_TOTAL
  fi

  echo "Total Tests:  $total"
  echo -e "Passed:       ${GREEN}${TESTS_PASSED}${NC} (PASS_COUNT: ${PASS_COUNT})"
  echo -e "Failed:       ${RED}${TESTS_FAILED}${NC} (FAIL_COUNT: ${FAIL_COUNT})"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  if [[ $TESTS_FAILED -eq 0 && $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed${NC}"
    echo ""
    return 0
  else
    echo -e "${RED}✗ Some tests failed${NC}"
    echo ""
    return 1
  fi
}
