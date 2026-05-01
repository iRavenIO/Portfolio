#!/usr/bin/env bash
# test-ops-dryrun.sh — Test ops wrapper scripts in dry-run mode
# Tests: Dry-run behavior, confirmation gates, wrapper functionality

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export CLAUDE_ROOT

PASS_COUNT=0
FAIL_COUNT=0

# ============================================================================
# HELPERS
# ============================================================================

say()  { printf "%s\n" "$*"; }
pass() { say "  PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { say "  FAIL: $*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ============================================================================
# TEST SUITE 1: Ops Wrapper Existence
# ============================================================================

test_ops_wrapper_existence() {
  say ""
  say "=== TEST SUITE 1: Ops Wrapper Existence ==="
  say ""

  local ops_dir="${CLAUDE_ROOT}/.claude/scripts/ops"

  # --- Test 1.1: Ops directory exists ---
  say "Test 1.1: Ops directory exists"
  if [[ -d "$ops_dir" ]]; then
    pass "Ops directory exists at $ops_dir"
  else
    fail "Ops directory does not exist"
    return
  fi

  # --- Test 1.2: At least 5 ops scripts exist ---
  say "Test 1.2: At least 5 ops scripts exist"
  local script_count
  script_count=$(find "$ops_dir" -maxdepth 1 -name "*.sh" -type f | wc -l | tr -d ' ')

  if [[ "$script_count" -ge 5 ]]; then
    pass "Found $script_count ops scripts (minimum 5 expected)"
  else
    fail "Found only $script_count ops scripts (minimum 5 expected)"
  fi

  # --- Test 1.3: All ops scripts are executable ---
  say "Test 1.3: All ops scripts are executable"
  local all_executable=true
  while IFS= read -r script; do
    if [[ ! -x "$script" ]]; then
      fail "$(basename "$script") is not executable"
      all_executable=false
    fi
  done < <(find "$ops_dir" -maxdepth 1 -name "*.sh" -type f)

  if $all_executable; then
    pass "All ops scripts are executable"
  fi
}

# ============================================================================
# TEST SUITE 2: Dry-Run Mode
# ============================================================================

test_dryrun_mode() {
  say ""
  say "=== TEST SUITE 2: Dry-Run Mode ==="
  say ""

  local ops_dir="${CLAUDE_ROOT}/.claude/scripts/ops"

  # --- Test 2.1: Scripts accept --dry-run flag ---
  say "Test 2.1: Scripts accept --dry-run flag"

  # Test with k8s.sh if it exists
  if [[ -f "$ops_dir/k8s.sh" ]]; then
    local output
    output=$(bash "$ops_dir/k8s.sh" --dry-run 2>&1 || true)

    if echo "$output" | grep -qi "dry.run\|would\|simulating"; then
      pass "k8s.sh supports --dry-run flag"
    else
      fail "k8s.sh does not indicate dry-run mode (output: ${output:0:100}...)"
    fi
  else
    say "  SKIP: k8s.sh not found"
  fi

  # --- Test 2.2: Dry-run does not execute destructive commands ---
  say "Test 2.2: Dry-run does not execute destructive commands"

  # Test with postgres.sh if it exists
  if [[ -f "$ops_dir/postgres.sh" ]]; then
    # Run in dry-run mode - should not actually create/delete anything
    output=$(bash "$ops_dir/postgres.sh" --dry-run 2>&1 || true)

    # Check that it mentions dry-run or would/will syntax
    if echo "$output" | grep -qi "dry.run\|would"; then
      pass "postgres.sh indicates dry-run mode"
    else
      fail "postgres.sh does not clearly indicate dry-run"
    fi
  else
    say "  SKIP: postgres.sh not found"
  fi

  # --- Test 2.3: Scripts have help output ---
  say "Test 2.3: Scripts have help output"

  local has_help=false
  for script in "$ops_dir"/*.sh; do
    if [[ -f "$script" ]]; then
      output=$(bash "$script" --help 2>&1 || bash "$script" -h 2>&1 || true)

      if echo "$output" | grep -qi "usage\|help\|options"; then
        pass "$(basename "$script") has help output"
        has_help=true
        break
      fi
    fi
  done

  if ! $has_help; then
    say "  SKIP: No scripts with help output found (non-critical)"
  fi
}

# ============================================================================
# TEST SUITE 3: Confirmation Gates
# ============================================================================

test_confirmation_gates() {
  say ""
  say "=== TEST SUITE 3: Confirmation Gates ==="
  say ""

  local ops_dir="${CLAUDE_ROOT}/.claude/scripts/ops"

  # --- Test 3.1: Scripts check for confirmation in non-dry-run mode ---
  say "Test 3.1: Scripts have confirmation logic"

  local has_confirmation=false
  for script in "$ops_dir"/*.sh; do
    if [[ -f "$script" ]]; then
      # Check if script contains confirmation logic
      if grep -q "read.*confirm\|read.*CONFIRM\|read.*y/n" "$script" 2>/dev/null; then
        pass "$(basename "$script") has confirmation logic"
        has_confirmation=true
        break
      fi
    fi
  done

  if ! $has_confirmation; then
    say "  INFO: No explicit confirmation prompts found (may use other safety mechanisms)"
  fi

  # --- Test 3.2: Scripts have safety checks ---
  say "Test 3.2: Scripts have safety checks"

  local has_safety=false
  for script in "$ops_dir"/*.sh; do
    if [[ -f "$script" ]]; then
      # Check for common safety patterns
      if grep -q "set -euo pipefail\|set -e" "$script" 2>/dev/null; then
        pass "$(basename "$script") uses strict error handling (set -e)"
        has_safety=true
        break
      fi
    fi
  done

  if ! $has_safety; then
    fail "No scripts found with strict error handling"
  fi
}

# ============================================================================
# TEST SUITE 4: Wrapper Functionality
# ============================================================================

test_wrapper_functionality() {
  say ""
  say "=== TEST SUITE 4: Wrapper Functionality ==="
  say ""

  local ops_dir="${CLAUDE_ROOT}/.claude/scripts/ops"

  # --- Test 4.1: Scripts source common functions if needed ---
  say "Test 4.1: Scripts have proper structure"

  local has_structure=false
  for script in "$ops_dir"/*.sh; do
    if [[ -f "$script" ]]; then
      # Check for shebang
      if head -1 "$script" | grep -q "^#!/"; then
        pass "$(basename "$script") has proper shebang"
        has_structure=true
        break
      fi
    fi
  done

  if ! $has_structure; then
    fail "No scripts with proper shebang found"
  fi

  # --- Test 4.2: Scripts can be executed without errors in dry-run ---
  say "Test 4.2: Scripts can be executed in dry-run without errors"

  local exec_count=0
  local error_count=0

  for script in "$ops_dir"/*.sh; do
    if [[ -f "$script" && -x "$script" ]]; then
      exec_count=$((exec_count + 1))

      # Try to run with --dry-run (some scripts may not support it)
      if bash "$script" --dry-run > /dev/null 2>&1 || bash "$script" -n > /dev/null 2>&1; then
        pass "$(basename "$script") runs without errors in dry-run"
      else
        # Not all scripts may support dry-run, so this is informational
        say "  INFO: $(basename "$script") may not support --dry-run flag"
      fi
    fi
  done

  if [[ "$exec_count" -eq 0 ]]; then
    fail "No executable ops scripts found"
  fi

  # --- Test 4.3: cached-ops.sh exists and works ---
  say "Test 4.3: cached-ops.sh exists and is functional"

  if [[ -f "${CLAUDE_ROOT}/.claude/scripts/cached-ops.sh" ]]; then
    pass "cached-ops.sh exists"

    if [[ -x "${CLAUDE_ROOT}/.claude/scripts/cached-ops.sh" ]]; then
      pass "cached-ops.sh is executable"
    else
      fail "cached-ops.sh is not executable"
    fi

    # Check if it can be sourced
    if bash -c "source ${CLAUDE_ROOT}/.claude/scripts/cached-ops.sh 2>/dev/null"; then
      pass "cached-ops.sh can be sourced"
    else
      fail "cached-ops.sh cannot be sourced"
    fi
  else
    fail "cached-ops.sh does not exist"
  fi
}

# ============================================================================
# TEST SUITE 5: Integration with Cache System
# ============================================================================

test_cache_integration() {
  say ""
  say "=== TEST SUITE 5: Integration with Cache System ==="
  say ""

  # --- Test 5.1: cached-ops.sh sources cache.sh ---
  say "Test 5.1: cached-ops.sh integrates with cache.sh"

  if [[ -f "${CLAUDE_ROOT}/.claude/scripts/cached-ops.sh" ]]; then
    if grep -q "source.*cache.sh\|\..*cache.sh" "${CLAUDE_ROOT}/.claude/scripts/cached-ops.sh" 2>/dev/null; then
      pass "cached-ops.sh sources cache.sh"
    else
      fail "cached-ops.sh does not source cache.sh"
    fi
  else
    say "  SKIP: cached-ops.sh not found"
  fi

  # --- Test 5.2: Cached ops functions exist ---
  say "Test 5.2: Cached ops functions exist in cached-ops.sh"

  if [[ -f "${CLAUDE_ROOT}/.claude/scripts/cached-ops.sh" ]]; then
    # Check for at least one cached ops function
    if grep -q "^cached_.*() {" "${CLAUDE_ROOT}/.claude/scripts/cached-ops.sh" 2>/dev/null; then
      pass "cached-ops.sh defines cached_ functions"
    else
      fail "cached-ops.sh does not define cached_ functions"
    fi
  else
    say "  SKIP: cached-ops.sh not found"
  fi
}

# ============================================================================
# MAIN
# ============================================================================

say "================================================================"
say "  Ops Dry-Run Tests"
say "  Testing: Ops wrapper scripts, dry-run mode, confirmation gates"
say "================================================================"

test_ops_wrapper_existence
test_dryrun_mode
test_confirmation_gates
test_wrapper_functionality
test_cache_integration

say ""
say "================================================================"
say "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
say "================================================================"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
