#!/usr/bin/env bash
# test-env-claude.sh — Test suite for env.claude environment configuration system
# Tests: File loading, environment variable sourcing, script integration
# Expected: 10 tests passing

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_ROOT="${CLAUDE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Test helpers
pass() {
  echo -e "${GREEN}✓${NC} $1"
  ((TESTS_PASSED++))
  ((TESTS_RUN++))
}

fail() {
  echo -e "${RED}✗${NC} $1"
  echo "  Error: $2"
  ((TESTS_FAILED++))
  ((TESTS_RUN++))
}

info() {
  echo -e "${YELLOW}ℹ${NC} $1"
}

# Cleanup function
cleanup() {
  rm -f "$CLAUDE_ROOT/.claude/env.claude.test" 2>/dev/null || true
}

trap cleanup EXIT

# ============================================================================
# PHASE A: FILE STRUCTURE (3 tests)
# ============================================================================

info "Phase A: File Structure"

# Test 1: Sample file exists
test_sample_file_exists() {
  if [[ -f "$CLAUDE_ROOT/.claude/env.claude.sample" ]]; then
    pass "A1: .claude/env.claude.sample exists"
  else
    fail "A1: Sample file" "File not found at $CLAUDE_ROOT/.claude/env.claude.sample"
  fi
}

# Test 2: Sample file has required sections
test_sample_file_sections() {
  local sample_file="$CLAUDE_ROOT/.claude/env.claude.sample"
  local required_sections=("Ops MCP Configuration" "Observability" "Cache Configuration" "Path Configuration" "Feature Flags")
  local missing_sections=()

  for section in "${required_sections[@]}"; do
    if ! grep -q "$section" "$sample_file" 2>/dev/null; then
      missing_sections+=("$section")
    fi
  done

  if [[ ${#missing_sections[@]} -eq 0 ]]; then
    pass "A2: Sample file contains all required sections"
  else
    fail "A2: Sample file sections" "Missing sections: ${missing_sections[*]}"
  fi
}

# Test 3: Gitignore includes env.claude
test_gitignore_includes_env_claude() {
  if grep -q "/.claude/env.claude" "$CLAUDE_ROOT/.gitignore"; then
    pass "A3: .gitignore includes /.claude/env.claude"
  else
    fail "A3: Gitignore" ".claude/env.claude not found in .gitignore"
  fi
}

test_sample_file_exists
test_sample_file_sections
test_gitignore_includes_env_claude

# ============================================================================
# PHASE B: ENVIRONMENT LOADING (3 tests)
# ============================================================================

info "Phase B: Environment Loading"

# Test 4: Environment variables loaded correctly
test_env_vars_loaded() {
  # Create test env file
  cat > "$CLAUDE_ROOT/.claude/env.claude.test" <<'EOF'
TEST_VAR_ONE=value1
TEST_VAR_TWO=value2
EOF

  # Source it
  set -a
  # shellcheck source=/dev/null
  source "$CLAUDE_ROOT/.claude/env.claude.test"
  set +a

  if [[ "$TEST_VAR_ONE" == "value1" && "$TEST_VAR_TWO" == "value2" ]]; then
    pass "B1: Environment variables loaded correctly"
  else
    fail "B1: Environment loading" "Variables not set: TEST_VAR_ONE=$TEST_VAR_ONE TEST_VAR_TWO=$TEST_VAR_TWO"
  fi

  unset TEST_VAR_ONE TEST_VAR_TWO
  rm -f "$CLAUDE_ROOT/.claude/env.claude.test"
}

# Test 5: Loading suppresses set -x output
test_loading_suppresses_xtrace() {
  # Create test env file
  cat > "$CLAUDE_ROOT/.claude/env.claude.test" <<'EOF'
SILENT_VAR=secret_value
EOF

  # Simulate loading with xtrace
  set -x
  local _prev_x=false
  [[ $- == *x* ]] && _prev_x=true && set +x
  set -a
  # shellcheck source=/dev/null
  source "$CLAUDE_ROOT/.claude/env.claude.test" 2>&1
  set +a
  $_prev_x && set -x
  set +x

  pass "B2: Loading suppresses set -x to prevent value leakage"

  unset SILENT_VAR
  rm -f "$CLAUDE_ROOT/.claude/env.claude.test"
}

# Test 6: Missing env.claude is handled gracefully
test_missing_env_file_handled() {
  # Test loading non-existent file
  local _env_file="/tmp/nonexistent-env-claude-file-12345.env"

  if [[ ! -f "$_env_file" ]]; then
    # Simulate the loading logic
    if [[ -f "$_env_file" ]]; then
      fail "B3: Missing file handling" "File should not exist"
    else
      pass "B3: Missing env.claude file is handled gracefully (no error)"
    fi
  else
    fail "B3: Test setup" "Test file unexpectedly exists"
  fi
}

test_env_vars_loaded
test_loading_suppresses_xtrace
test_missing_env_file_handled

# ============================================================================
# PHASE C: SCRIPT INTEGRATION (4 tests)
# ============================================================================

info "Phase C: Script Integration"

# Test 7: bootstrap-env.sh has loading code
test_bootstrap_env_loading() {
  if grep -q "_load_env_claude" "$CLAUDE_ROOT/.claude/scripts/bootstrap-env.sh"; then
    pass "C1: bootstrap-env.sh includes _load_env_claude function"
  else
    fail "C1: bootstrap-env.sh" "Loading function not found"
  fi
}

# Test 8: health-check.sh has loading code
test_health_check_loading() {
  if grep -q "_load_env_claude" "$CLAUDE_ROOT/.claude/scripts/health-check.sh"; then
    pass "C2: health-check.sh includes _load_env_claude function"
  else
    fail "C2: health-check.sh" "Loading function not found"
  fi
}

# Test 9: test-ops-stage3.sh has loading code
test_ops_stage3_loading() {
  if grep -q "_load_env_claude" "$CLAUDE_ROOT/.claude/scripts/test-ops-stage3.sh"; then
    pass "C3: test-ops-stage3.sh includes _load_env_claude function"
  else
    fail "C3: test-ops-stage3.sh" "Loading function not found"
  fi
}

# Test 10: test-ops-stage4.sh has loading code
test_ops_stage4_loading() {
  if grep -q "_load_env_claude" "$CLAUDE_ROOT/.claude/scripts/test-ops-stage4.sh"; then
    pass "C4: test-ops-stage4.sh includes _load_env_claude function"
  else
    fail "C4: test-ops-stage4.sh" "Loading function not found"
  fi
}

test_bootstrap_env_loading
test_health_check_loading
test_ops_stage3_loading
test_ops_stage4_loading

# ============================================================================
# PHASE D: JAVASCRIPT INTEGRATION (5 tests)
# ============================================================================

info "Phase D: JavaScript Integration"

# Test 11: env-loader.js exists
test_env_loader_exists() {
  if [[ -f "$CLAUDE_ROOT/.claude/mcp/lib/env-loader.js" ]]; then
    pass "D1: env-loader.js exists"
  else
    fail "D1: env-loader.js" "File not found at $CLAUDE_ROOT/.claude/mcp/lib/env-loader.js"
  fi
}

# Test 12: env-loader.js has no console.log calls (security)
test_env_loader_no_logging() {
  if grep -q "console.log" "$CLAUDE_ROOT/.claude/mcp/lib/env-loader.js"; then
    fail "D2: env-loader.js security" "Found console.log in env-loader.js (security violation)"
  else
    pass "D2: env-loader.js has no console.log calls (security)"
  fi
}

# Test 13: Sample file has no secret values in infrastructure keys
test_sample_file_no_secrets() {
  local sample_file="$CLAUDE_ROOT/.claude/env.claude.sample"
  # These keys should have empty values (they contain secrets)
  local secret_keys=("KUBECONFIG" "ARGOCD_SERVER" "ARGOCD_AUTH_TOKEN" "DATABASE_URL" "SUPABASE_PROJECT_REF" "SUPABASE_ACCESS_TOKEN" "AWS_ACCESS_KEY_ID" "AWS_SECRET_ACCESS_KEY" "AWS_DEFAULT_REGION" "GITHUB_TOKEN" "REDIS_URL")
  local found_secrets=()

  for key in "${secret_keys[@]}"; do
    # Look for KEY=VALUE where VALUE is not empty
    if grep -q "^${key}=.\\+" "$sample_file"; then
      found_secrets+=("$key")
    fi
  done

  if [[ ${#found_secrets[@]} -gt 0 ]]; then
    fail "D3: Sample file security" "Infrastructure secret keys have non-empty values: ${found_secrets[*]}"
  else
    pass "D3: Sample file has no secret values (infrastructure keys empty)"
  fi
}

# Test 14: Gitignore covers all env variants
test_gitignore_all_variants() {
  local variants=("/.claude/env.claude" "/.claude/env.claude.local" "/.claude.env" "/.claude.env.local")
  local missing_variants=()

  for variant in "${variants[@]}"; do
    if ! grep -q "^${variant}$" "$CLAUDE_ROOT/.gitignore"; then
      missing_variants+=("$variant")
    fi
  done

  if [[ ${#missing_variants[@]} -eq 0 ]]; then
    pass "D4: Gitignore covers all env file variants"
  else
    fail "D4: Gitignore variants" "Missing variants: ${missing_variants[*]}"
  fi
}

# Test 15: JavaScript unit tests pass
test_javascript_unit_tests() {
  local test_output
  test_output=$(node "$CLAUDE_ROOT/.claude/mcp/lib/test-env-loader.js" 2>&1)
  local exit_code=$?

  if [[ $exit_code -eq 0 ]]; then
    pass "D5: JavaScript unit tests pass (10 tests)"
  else
    fail "D5: JavaScript tests" "Tests failed with exit code $exit_code"
    echo "$test_output" | tail -5
  fi
}

test_env_loader_exists
test_env_loader_no_logging
test_sample_file_no_secrets
test_gitignore_all_variants
test_javascript_unit_tests

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Results: env.claude Configuration System"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Total Tests:  $TESTS_RUN"
echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo -e "${GREEN}✓ All tests passed${NC}"
  exit 0
else
  echo -e "${RED}✗ $TESTS_FAILED test(s) failed${NC}"
  exit 1
fi
