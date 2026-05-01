#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# Test Suite for install.sh
#
# Tests:
#   - Idempotency of install.sh (safe to re-run)
#   - Cache subsystem initialization
#   - Dependency verification
#   - Validation script execution
#
# Usage: .claude/scripts/test-install.sh
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

# ============================================================
# Install Script Tests
# ============================================================

test_install_idempotency() {
  print_header "INSTALL IDEMPOTENCY TESTS"

  # Test 1: First run completes successfully
  print_test "First install.sh run completes successfully"

  cd "$REPO_ROOT"
  set +e
  output=$(./install.sh 2>&1)
  first_exit=$?
  set -e

  assertExitCode 0 "$first_exit" "First install.sh run should exit 0"

  # Test 2: Second run is idempotent (safe to re-run)
  print_test "Second install.sh run is idempotent"

  set +e
  output=$(./install.sh 2>&1)
  second_exit=$?
  set -e

  assertExitCode 0 "$second_exit" "Second install.sh run should exit 0"
  assertContains "$output" "Setup complete" "Should complete successfully"

  # Test 3: Cache directory exists after install
  print_test "Cache directory created by install.sh"

  assertDirExists "$REPO_ROOT/.claude/cache" "Cache directory should exist"
  assertFileExists "$REPO_ROOT/.claude/cache/cache.db" "Cache database should exist"

  # Test 4: decision_memory table exists
  print_test "decision_memory table created by install.sh"

  if sqlite3 "$REPO_ROOT/.claude/cache/cache.db" "SELECT name FROM sqlite_master WHERE type='table' AND name='decision_memory';" | grep -q "decision_memory"; then
    pass "decision_memory table exists"
  else
    fail "decision_memory table should exist"
  fi

  # Test 5: Scripts are executable
  print_test "Scripts made executable by install.sh"

  local scripts=(
    ".claude/scripts/health-check.sh"
    ".claude/scripts/validate-policies.sh"
    ".claude/scripts/cache.sh"
    ".claude/scripts/test-cache.sh"
  )

  for script in "${scripts[@]}"; do
    if [[ -x "$REPO_ROOT/$script" ]]; then
      pass "$script is executable"
    else
      fail "$script should be executable"
    fi
  done
}

test_cache_subsystem_initialization() {
  print_header "CACHE SUBSYSTEM INITIALIZATION TESTS"

  # Test 1: cache.sh can be sourced
  print_test "cache.sh can be sourced successfully"

  set +e
  source "$REPO_ROOT/.claude/scripts/cache.sh"
  source_exit=$?
  set -e

  assertExitCode 0 "$source_exit" "cache.sh should source without errors"

  # Test 2: cache functions are exported
  print_test "Cache functions are exported and callable"

  local funcs=(
    "cache_init"
    "cache_set"
    "cache_get"
    "cache_lock"
    "cache_unlock"
    "cache_warm"
    "cache_gc"
    "decision_memory_record"
    "decision_memory_stats"
  )

  for func in "${funcs[@]}"; do
    if declare -F "$func" >/dev/null; then
      pass "$func is exported"
    else
      fail "$func should be exported"
    fi
  done

  # Test 3: cache_warm runs successfully
  print_test "cache_warm runs and populates cache"

  set +e
  count=$(cache_warm 2>/dev/null)
  warm_exit=$?
  set -e

  assertExitCode 0 "$warm_exit" "cache_warm should exit 0"

  if [[ "$count" -gt 0 ]]; then
    pass "cache_warm populated $count entries"
  else
    fail "cache_warm should populate at least 1 entry"
  fi

  # Test 4: decision_memory_record works
  print_test "decision_memory_record stores data"

  # Get initial count
  initial_count=$(sqlite3 "$REPO_ROOT/.claude/cache/cache.db" "SELECT COUNT(*) FROM decision_memory WHERE run_id='test-install-run';")

  decision_memory_record "test-install-run" "STANDARD" 50000 48200 0 2 156

  record_count=$(sqlite3 "$REPO_ROOT/.claude/cache/cache.db" "SELECT COUNT(*) FROM decision_memory WHERE run_id='test-install-run';")

  if [[ "$record_count" -gt "$initial_count" ]]; then
    pass "decision_memory_record stored record (count: $record_count)"
  else
    fail "decision_memory_record should store new record"
  fi

  # Cleanup test record
  sqlite3 "$REPO_ROOT/.claude/cache/cache.db" "DELETE FROM decision_memory WHERE run_id='test-install-run';"
}

test_validation_scripts() {
  print_header "VALIDATION SCRIPT TESTS"

  # Test 1: health-check.sh passes
  print_test "health-check.sh passes after install"

  cd "$REPO_ROOT"
  set +e
  output=$(./.claude/scripts/health-check.sh 2>&1)
  health_exit=$?
  set -e

  assertExitCode 0 "$health_exit" "health-check.sh should exit 0"
  assertContains "$output" "Checking cache system" "Should check cache system"

  # Test 2: validate-policies.sh passes
  print_test "validate-policies.sh passes after install"

  set +e
  output=$(./.claude/scripts/validate-policies.sh 2>&1)
  validate_exit=$?
  set -e

  assertExitCode 0 "$validate_exit" "validate-policies.sh should exit 0"
  assertContains "$output" "All policy validations passed" "Should pass all validations"
}

test_dependency_verification() {
  print_header "DEPENDENCY VERIFICATION TESTS"

  # Test 1: Required commands exist
  print_test "Required dependencies are available"

  local required_cmds=("git" "node" "npm" "sqlite3")
  local optional_cmds=("rg" "ctags" "redis-cli")

  for cmd in "${required_cmds[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      pass "$cmd is available"
    else
      fail "$cmd should be available (required)"
    fi
  done

  for cmd in "${optional_cmds[@]}"; do
    if command -v "$cmd" >/dev/null 2>&1; then
      pass "$cmd is available (optional)"
    else
      echo "  ℹ️  $cmd not available (optional)"
    fi
  done

  # Test 2: MCP dependencies installed
  print_test "MCP dependencies installed"

  if [[ -d "$REPO_ROOT/.claude/mcp/node_modules" ]]; then
    pass "MCP node_modules directory exists"
  else
    fail "MCP node_modules should exist after install"
  fi
}

test_gitignore_content() {
  print_header ".GITIGNORE CONTENT VALIDATION"

  # Test 1: .gitignore file exists
  print_test ".gitignore file exists at repo root"

  if [[ -f "$REPO_ROOT/.gitignore" ]]; then
    pass ".gitignore exists"
  else
    fail ".gitignore should exist at repo root"
    return
  fi

  # Test 2: All required patterns are present
  print_test ".gitignore contains required cache patterns"

  local required_patterns=(
    ".claude/cache/"
    ".claude/logs/"
    ".claude/memory/"
    "node_modules"
    "tags"
    ".claude/index-state.json"
  )

  for pattern in "${required_patterns[@]}"; do
    if grep -qF "$pattern" "$REPO_ROOT/.gitignore"; then
      pass "Pattern '$pattern' found in .gitignore"
    else
      fail "Pattern '$pattern' missing from .gitignore"
    fi
  done
}

test_fresh_repo_tags_fallback() {
  print_header "FRESH REPO TAGS FALLBACK TESTS"

  # Test 1: Create a temporary fresh git repo
  print_test "Tags generated in fresh repo with zero tracked files"

  local TMPDIR_FR
  TMPDIR_FR="$(mktemp -d)"
  trap "rm -rf '$TMPDIR_FR'" RETURN

  # Initialize a fresh git repo with zero tracked files
  git init "$TMPDIR_FR/fresh" >/dev/null 2>&1

  # Copy minimal factory structure (matching bootstrap runbook)
  cp "$REPO_ROOT/CLAUDE.md" "$TMPDIR_FR/fresh/"
  cp "$REPO_ROOT/.gitignore" "$TMPDIR_FR/fresh/" 2>/dev/null || true
  cp "$REPO_ROOT/install.sh" "$TMPDIR_FR/fresh/"
  cp -R "$REPO_ROOT/.claude" "$TMPDIR_FR/fresh/"
  cp -R "$REPO_ROOT/docs" "$TMPDIR_FR/fresh/"
  cp "$REPO_ROOT/.mcp.json" "$TMPDIR_FR/fresh/"
  cp "$REPO_ROOT/cf" "$TMPDIR_FR/fresh/" 2>/dev/null || true

  # Run install.sh in the fresh repo
  cd "$TMPDIR_FR/fresh"
  chmod +x install.sh
  set +e
  output=$(./install.sh 2>&1)
  install_exit=$?
  set -e

  assertExitCode 0 "$install_exit" "install.sh should exit 0 in fresh repo"

  # Tags file should exist and have content
  if [[ -f "$TMPDIR_FR/fresh/tags" ]]; then
    local tag_lines
    tag_lines=$(wc -l < "$TMPDIR_FR/fresh/tags" | tr -d ' ')
    if [[ "$tag_lines" -gt 1 ]]; then
      pass "Tags file generated with $tag_lines lines in fresh repo"
    else
      fail "Tags file exists but is empty ($tag_lines lines)"
    fi
  else
    fail "Tags file should exist after install in fresh repo"
  fi

  # Verify fallback warning was emitted
  assertContains "$output" "falling back to filesystem scan" "Should emit fallback warning"

  cd "$REPO_ROOT"
  rm -rf "$TMPDIR_FR"
}

test_cf_runner() {
  print_header "CF RUNNER TESTS"

  # Test 1: cf file exists
  print_test "cf runner script exists at repo root"
  assertFileExists "$REPO_ROOT/cf" "cf runner should exist"

  # Test 2: cf is executable
  print_test "cf runner script is executable"
  if [[ -x "$REPO_ROOT/cf" ]]; then
    pass "cf is executable"
  else
    fail "cf should be executable after install"
  fi

  # Test 3: cf shows usage when run without args
  print_test "cf shows usage when run without arguments"
  set +e
  output=$("$REPO_ROOT/cf" 2>&1)
  cf_exit=$?
  set -e

  assertExitCode 1 "$cf_exit" "cf should exit 1 with no arguments"
  assertContains "$output" "Usage:" "cf should print usage"
}

test_gemini_health_check() {
  print_header "GEMINI HEALTH CHECK TESTS"

  # Test 1: health-check.sh detects gemini correctly
  print_test "health-check.sh validates gemini command"

  cd "$REPO_ROOT"
  set +e
  output=$(./.claude/scripts/health-check.sh 2>&1)
  health_exit=$?
  set -e

  # Should check for gemini (not gemini-dash-p)
  assertContains "$output" "Checking gemini" "Should check for gemini command"

  # Should NOT mention gemini-dash-p
  if [[ "$output" == *"gemini-dash-p"* ]]; then
    fail "Should NOT reference gemini-dash-p in output"
  else
    pass "Does not reference deprecated gemini-dash-p"
  fi

  # If gemini is installed, should verify it
  if command -v gemini >/dev/null 2>&1; then
    assertContains "$output" "gemini command verified" "Should verify gemini when installed"
  fi
}

# ============================================================
# Main Test Execution
# ============================================================

main() {
  echo ""
  echo "=========================================="
  echo "INSTALL SCRIPT TEST SUITE"
  echo "=========================================="
  echo "Repository: $REPO_ROOT"
  echo ""

  # Run test suites
  test_install_idempotency
  test_cache_subsystem_initialization
  test_validation_scripts
  test_dependency_verification
  test_gitignore_content
  test_fresh_repo_tags_fallback
  test_cf_runner
  test_gemini_health_check

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
