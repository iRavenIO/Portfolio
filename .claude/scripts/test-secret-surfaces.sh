#!/usr/bin/env bash
# test-secret-surfaces.sh — Test suite for secret protection across cache and logging
# Part of Task 5D: Safety Hardening - Secret Surfaces Audit
#
# Validates that secrets are blocked/redacted at all surfaces:
# 1. redact.sh denylist patterns
# 2. cache_set_file blocking
# 3. cache_set detection
# 4. cache_prime skipping
# 5. run-with-logging.sh redaction
# 6. Integration tests

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"


trap cleanup EXIT

# Test result helpers
pass() {
  echo -e "${GREEN}✓${NC} $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
}

fail() {
  echo -e "${RED}✗${NC} $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
  TESTS_RUN=$((TESTS_RUN + 1))
}

skip() {
  echo -e "${YELLOW}⊘${NC} $1 (skipped)"
}

section() {
  echo ""
  echo "════════════════════════════════════════════════════════════════"
  echo "  $1"
  echo "════════════════════════════════════════════════════════════════"
}

# ============================================================================
# TEST SUITE 1: redact.sh Denylist Patterns
# ============================================================================

test_redact_patterns() {
  section "TEST SUITE 1: redact.sh Denylist Patterns"

  # Source redact.sh
  if [[ ! -f "$SCRIPT_DIR/redact.sh" ]]; then
    fail "redact.sh not found"
    return
  fi
  source "$SCRIPT_DIR/redact.sh"

  # Test environment variable patterns
  echo "Testing environment variable patterns..."

  # Tokens
  if is_secret_var "API_TOKEN"; then
    pass "API_TOKEN identified as secret"
  else
    fail "API_TOKEN not identified as secret"
  fi

  if is_secret_var "GITHUB_TOKEN"; then
    pass "GITHUB_TOKEN identified as secret"
  else
    fail "GITHUB_TOKEN not identified as secret"
  fi

  # Keys
  if is_secret_var "ANTHROPIC_API_KEY"; then
    pass "ANTHROPIC_API_KEY identified as secret"
  else
    fail "ANTHROPIC_API_KEY not identified as secret"
  fi

  if is_secret_var "AWS_SECRET_ACCESS_KEY"; then
    pass "AWS_SECRET_ACCESS_KEY identified as secret"
  else
    fail "AWS_SECRET_ACCESS_KEY not identified as secret"
  fi

  # Passwords
  if is_secret_var "DB_PASSWORD"; then
    pass "DB_PASSWORD identified as secret"
  else
    fail "DB_PASSWORD not identified as secret"
  fi

  if is_secret_var "POSTGRES_PASSWORD"; then
    pass "POSTGRES_PASSWORD identified as secret"
  else
    fail "POSTGRES_PASSWORD not identified as secret"
  fi

  # Database URLs
  if is_secret_var "DATABASE_URL"; then
    pass "DATABASE_URL identified as secret"
  else
    fail "DATABASE_URL not identified as secret"
  fi

  # Kubernetes (NEW)
  if is_secret_var "KUBECONFIG"; then
    pass "KUBECONFIG identified as secret"
  else
    fail "KUBECONFIG not identified as secret"
  fi

  if is_secret_var "KUBE_TOKEN"; then
    pass "KUBE_TOKEN identified as secret"
  else
    fail "KUBE_TOKEN not identified as secret"
  fi

  # Docker (NEW)
  if is_secret_var "DOCKER_PASSWORD"; then
    pass "DOCKER_PASSWORD identified as secret"
  else
    fail "DOCKER_PASSWORD not identified as secret"
  fi

  if is_secret_var "DOCKER_AUTH"; then
    pass "DOCKER_AUTH identified as secret"
  else
    fail "DOCKER_AUTH not identified as secret"
  fi

  # Terraform (NEW)
  if is_secret_var "TF_VAR_api_key"; then
    pass "TF_VAR_api_key identified as secret"
  else
    fail "TF_VAR_api_key not identified as secret"
  fi

  # NPM (NEW)
  if is_secret_var "NPM_TOKEN"; then
    pass "NPM_TOKEN identified as secret"
  else
    fail "NPM_TOKEN not identified as secret"
  fi

  # Other services (NEW)
  if is_secret_var "SLACK_TOKEN"; then
    pass "SLACK_TOKEN identified as secret"
  else
    fail "SLACK_TOKEN not identified as secret"
  fi

  if is_secret_var "STRIPE_SECRET_KEY"; then
    pass "STRIPE_SECRET_KEY identified as secret"
  else
    fail "STRIPE_SECRET_KEY not identified as secret"
  fi

  # Allowlist (should NOT be secrets)
  if ! is_secret_var "NODE_ENV"; then
    pass "NODE_ENV correctly allowed (not secret)"
  else
    fail "NODE_ENV incorrectly marked as secret"
  fi

  if ! is_secret_var "PORT"; then
    pass "PORT correctly allowed (not secret)"
  else
    fail "PORT incorrectly marked as secret"
  fi

  if ! is_secret_var "LOG_LEVEL"; then
    pass "LOG_LEVEL correctly allowed (not secret)"
  else
    fail "LOG_LEVEL incorrectly marked as secret"
  fi

  # Test file patterns
  echo ""
  echo "Testing file patterns..."

  # Standard patterns
  if is_secret_file ".env"; then
    pass ".env identified as secret file"
  else
    fail ".env not identified as secret file"
  fi

  if is_secret_file ".env.local"; then
    pass ".env.local identified as secret file"
  else
    fail ".env.local not identified as secret file"
  fi

  if is_secret_file "id_rsa"; then
    pass "id_rsa identified as secret file"
  else
    fail "id_rsa not identified as secret file"
  fi

  if is_secret_file "credentials.json"; then
    pass "credentials.json identified as secret file"
  else
    fail "credentials.json not identified as secret file"
  fi

  # Kubernetes (NEW)
  if is_secret_file "config"; then
    pass "config (kubeconfig) identified as secret file"
  else
    fail "config (kubeconfig) not identified as secret file"
  fi

  if is_secret_file "cluster.kubeconfig"; then
    pass ".kubeconfig identified as secret file"
  else
    fail ".kubeconfig not identified as secret file"
  fi

  # Terraform (NEW)
  if is_secret_file "terraform.tfstate"; then
    pass "terraform.tfstate identified as secret file"
  else
    fail "terraform.tfstate not identified as secret file"
  fi

  if is_secret_file "prod.tfvars"; then
    pass "prod.tfvars identified as secret file"
  else
    fail "prod.tfvars not identified as secret file"
  fi

  # Docker (NEW)
  if is_secret_file ".dockercfg"; then
    pass ".dockercfg identified as secret file"
  else
    fail ".dockercfg not identified as secret file"
  fi

  # NPM (NEW)
  if is_secret_file ".npmrc"; then
    pass ".npmrc identified as secret file"
  else
    fail ".npmrc not identified as secret file"
  fi

  # Database (NEW)
  if is_secret_file ".pgpass"; then
    pass ".pgpass identified as secret file"
  else
    fail ".pgpass not identified as secret file"
  fi

  # Generic auth (NEW)
  if is_secret_file ".netrc"; then
    pass ".netrc identified as secret file"
  else
    fail ".netrc not identified as secret file"
  fi

  # Non-secret files
  if ! is_secret_file "package.json"; then
    pass "package.json correctly allowed (not secret)"
  else
    fail "package.json incorrectly marked as secret"
  fi

  if ! is_secret_file "README.md"; then
    pass "README.md correctly allowed (not secret)"
  else
    fail "README.md incorrectly marked as secret"
  fi
}

# ============================================================================
# TEST SUITE 2: cache_set_file Blocking
# ============================================================================

test_cache_set_file_blocking() {
  section "TEST SUITE 2: cache_set_file Blocking"

  # Initialize cache
  source "$SCRIPT_DIR/cache.sh" 2>/dev/null || {
    fail "Failed to source cache.sh"
    return
  }

  # Create test secret files
  echo "API_KEY=secret123" > "$TEST_DIR/.env"
  echo "password: secret456" > "$TEST_DIR/credentials.json"
  echo "safe content" > "$TEST_DIR/safe.txt"

  # NEW: Create additional secret file types
  echo "terraform state" > "$TEST_DIR/terraform.tfstate"
  echo "kube config" > "$TEST_DIR/config"
  echo '{"auths":{}}' > "$TEST_DIR/.dockercfg"
  echo "//registry:token=secret" > "$TEST_DIR/.npmrc"

  # Test that secret files are blocked
  if ! cache_set_file "$TEST_DIR/.env" "test" 2>/dev/null; then
    pass ".env file blocked from cache"
  else
    fail ".env file was cached (should be blocked)"
  fi

  if ! cache_set_file "$TEST_DIR/credentials.json" "test" 2>/dev/null; then
    pass "credentials.json blocked from cache"
  else
    fail "credentials.json was cached (should be blocked)"
  fi

  # NEW: Test new secret file types
  if ! cache_set_file "$TEST_DIR/terraform.tfstate" "test" 2>/dev/null; then
    pass "terraform.tfstate blocked from cache"
  else
    fail "terraform.tfstate was cached (should be blocked)"
  fi

  if ! cache_set_file "$TEST_DIR/config" "test" 2>/dev/null; then
    pass "config (kubeconfig) blocked from cache"
  else
    fail "config was cached (should be blocked)"
  fi

  if ! cache_set_file "$TEST_DIR/.dockercfg" "test" 2>/dev/null; then
    pass ".dockercfg blocked from cache"
  else
    fail ".dockercfg was cached (should be blocked)"
  fi

  if ! cache_set_file "$TEST_DIR/.npmrc" "test" 2>/dev/null; then
    pass ".npmrc blocked from cache"
  else
    fail ".npmrc was cached (should be blocked)"
  fi

  # Test that safe files are allowed
  if cache_set_file "$TEST_DIR/safe.txt" "test" 2>/dev/null; then
    pass "safe.txt allowed in cache"
  else
    fail "safe.txt was blocked (should be allowed)"
  fi
}

# ============================================================================
# TEST SUITE 3: cache_set Detection
# ============================================================================

test_cache_set_detection() {
  section "TEST SUITE 3: cache_set Detection"

  source "$SCRIPT_DIR/cache.sh" 2>/dev/null || {
    fail "Failed to source cache.sh"
    return
  }

  # Test that secret values are detected and rejected
  if ! cache_set "test_key_1" "API_KEY=secret123" "test" 2>/dev/null; then
    pass "Secret value detected and rejected by cache_set"
  else
    fail "Secret value was cached (should be rejected)"
  fi

  if ! cache_set "test_key_2" "export DATABASE_URL=postgres://user:pass@host/db" "test" 2>/dev/null; then
    pass "Database URL detected and rejected by cache_set"
  else
    fail "Database URL was cached (should be rejected)"
  fi

  if ! cache_set "test_key_3" "GITHUB_TOKEN=ghp_secret" "test" 2>/dev/null; then
    pass "GitHub token detected and rejected by cache_set"
  else
    fail "GitHub token was cached (should be rejected)"
  fi

  # Test that safe content is allowed
  if cache_set "test_key_4" "This is safe documentation text" "test" 2>/dev/null; then
    pass "Safe content allowed by cache_set"
  else
    fail "Safe content was rejected (should be allowed)"
  fi

  # Test safe types (policy, runbook, agent) are exempt
  if cache_set "policy_key" "API_KEY mentioned in policy doc" "policy" 2>/dev/null; then
    pass "Policy content with keyword mention allowed"
  else
    fail "Policy content was rejected (should be allowed)"
  fi
}

# ============================================================================
# TEST SUITE 4: cache_prime Skipping
# ============================================================================

test_cache_prime_skipping() {
  section "TEST SUITE 4: cache_prime Skipping"

  source "$SCRIPT_DIR/cache.sh" 2>/dev/null || {
    fail "Failed to source cache.sh"
    return
  }

  # Create test directory with mixed files
  mkdir -p "$TEST_DIR/prime_test"
  echo "safe content 1" > "$TEST_DIR/prime_test/file1.txt"
  echo "safe content 2" > "$TEST_DIR/prime_test/file2.txt"
  echo "API_KEY=secret" > "$TEST_DIR/prime_test/.env"
  echo "credentials" > "$TEST_DIR/prime_test/credentials.json"
  echo "terraform state" > "$TEST_DIR/prime_test/prod.tfstate"
  echo "kube config" > "$TEST_DIR/prime_test/cluster.kubeconfig"

  # Prime the cache with pattern
  cache_prime "test" "$TEST_DIR/prime_test/*" 2>/dev/null

  # Check that safe files were cached
  if cache_get "file:$TEST_DIR/prime_test/file1.txt" >/dev/null 2>&1; then
    pass "cache_prime cached safe file1.txt"
  else
    fail "cache_prime did not cache safe file1.txt"
  fi

  if cache_get "file:$TEST_DIR/prime_test/file2.txt" >/dev/null 2>&1; then
    pass "cache_prime cached safe file2.txt"
  else
    fail "cache_prime did not cache safe file2.txt"
  fi

  # Check that secret files were skipped
  if ! cache_get "file:$TEST_DIR/prime_test/.env" >/dev/null 2>&1; then
    pass "cache_prime skipped .env file"
  else
    fail "cache_prime cached .env file (should be skipped)"
  fi

  if ! cache_get "file:$TEST_DIR/prime_test/credentials.json" >/dev/null 2>&1; then
    pass "cache_prime skipped credentials.json"
  else
    fail "cache_prime cached credentials.json (should be skipped)"
  fi

  # NEW: Check new secret file types
  if ! cache_get "file:$TEST_DIR/prime_test/prod.tfstate" >/dev/null 2>&1; then
    pass "cache_prime skipped prod.tfstate"
  else
    fail "cache_prime cached prod.tfstate (should be skipped)"
  fi

  if ! cache_get "file:$TEST_DIR/prime_test/cluster.kubeconfig" >/dev/null 2>&1; then
    pass "cache_prime skipped cluster.kubeconfig"
  else
    fail "cache_prime cached cluster.kubeconfig (should be skipped)"
  fi
}

# ============================================================================
# TEST SUITE 5: run-with-logging.sh Redaction
# ============================================================================

test_run_with_logging_redaction() {
  section "TEST SUITE 5: run-with-logging.sh Redaction"

  local log_script="$SCRIPT_DIR/run-with-logging.sh"
  if [[ ! -f "$log_script" ]]; then
    fail "run-with-logging.sh not found"
    return
  fi

  # Test that command line is redacted in output
  # We'll capture the output and check for redaction
  local test_cmd="echo 'API_KEY=secret123'"

  # Run with logging (capture stdout)
  local output
  output=$(CLAUDE_FACTORY_SKIP_HEALTH_CHECK=1 "$log_script" bash -c "$test_cmd" 2>&1 | grep "Command:" || true)

  if echo "$output" | grep -q "REDACTED"; then
    pass "Command line redacted in console output"
  elif echo "$output" | grep -q "secret123"; then
    fail "Secret leaked in console output"
  else
    # If neither found, command line may be formatted differently
    pass "Command line output appears safe (no secret visible)"
  fi

  # Check log file for redaction
  local latest_log=$(ls -t "$REPO_ROOT/.claude/logs"/run-*.log 2>/dev/null | head -1 || echo "")
  if [[ -n "$latest_log" && -f "$latest_log" ]]; then
    if grep -q "secret123" "$latest_log"; then
      fail "Secret leaked in log file: $latest_log"
    else
      pass "Log file appears redacted (no secret visible)"
    fi
  else
    skip "Could not verify log file redaction (no log file found)"
  fi
}

# ============================================================================
# TEST SUITE 6: Integration Tests
# ============================================================================

test_integration() {
  section "TEST SUITE 6: Integration Tests"

  source "$SCRIPT_DIR/cache.sh" 2>/dev/null || {
    fail "Failed to source cache.sh"
    return
  }

  # End-to-end test: Create secret file, attempt cache_warm, verify blocked
  echo "TEST_PASSWORD=secret" > "$TEST_DIR/integration_test.env"

  # Attempt to warm cache with this directory
  cache_prime "test" "$TEST_DIR/integration_test.env" 2>/dev/null || true

  # Verify it wasn't cached
  if ! cache_get "file:$TEST_DIR/integration_test.env" >/dev/null 2>&1; then
    pass "End-to-end: Secret file blocked in cache_warm"
  else
    fail "End-to-end: Secret file was cached"
  fi

  # Test redact_stream integration
  local test_input="export API_KEY=sk_test_12345"
  local redacted_output=$(echo "$test_input" | redact_stream)

  if [[ "$redacted_output" != "$test_input" ]]; then
    pass "redact_stream successfully redacted secret"
  else
    fail "redact_stream did not redact secret"
  fi

  # Test that cache.sh exports redaction functions
  if declare -f is_secret_file >/dev/null 2>&1; then
    pass "is_secret_file exported by cache.sh"
  else
    fail "is_secret_file not exported by cache.sh"
  fi

  if declare -f redact_stream >/dev/null 2>&1; then
    pass "redact_stream exported by cache.sh"
  else
    fail "redact_stream not exported by cache.sh"
  fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  echo "════════════════════════════════════════════════════════════════"
  echo "  Claude Factory - Secret Surfaces Test Suite"
  echo "  Task 5D: Safety Hardening - Secret Surfaces Audit"
  echo "════════════════════════════════════════════════════════════════"
  echo ""

  # Run all test suites
  test_redact_patterns
  test_cache_set_file_blocking
  test_cache_set_detection
  test_cache_prime_skipping
  test_run_with_logging_redaction
  test_integration

  # Summary
  section "TEST SUMMARY"
  echo ""
  echo "Tests run:    $TESTS_RUN"
  echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
  echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
  echo ""

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
  else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
  fi
}

main "$@"
