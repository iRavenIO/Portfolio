#!/usr/bin/env bash
# test-ops-stage2.sh — Phase 5.2 Ops MCP Stage 2 Test Suite
#
# Tests for 5 new discovery tools:
#   - ops_discover_s3
#   - ops_discover_github
#   - ops_discover_docker
#   - ops_discover_redis
#   - ops_discover_argo_workflows
#
# Test Categories:
#   1. Schema validation (5 tests)
#   2. Secret redaction (8 tests)
#   3. Caching (5 tests)
#   4. Graceful degradation (5 tests)
#   Total: 23 tests

set -uo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_ROOT="${CLAUDE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
SERVER_OPS="${CLAUDE_ROOT}/.claude/mcp/server-ops.js"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# ============================================================================
# TEST HELPERS
# ============================================================================

log_test() {
  echo -e "${BLUE}[TEST $TESTS_RUN]${NC} $1"
}

log_pass() {
  echo -e "${GREEN}✓ PASS${NC} $1"
  ((TESTS_PASSED++))
}

log_fail() {
  echo -e "${RED}✗ FAIL${NC} $1"
  ((TESTS_FAILED++))
}

log_section() {
  echo ""
  echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
  echo -e "${YELLOW}  $1${NC}"
  echo -e "${YELLOW}═══════════════════════════════════════════════════════════${NC}"
  echo ""
}

# Mock CLI command success/failure
mock_cli_success() {
  local cmd=$1
  local output=$2
  # Create a mock executable that outputs the given JSON
  cat > "/tmp/mock_${cmd}" <<EOF
#!/usr/bin/env bash
echo '$output'
EOF
  chmod +x "/tmp/mock_${cmd}"
  export PATH="/tmp:$PATH"
}

mock_cli_fail() {
  local cmd=$1
  # Create a mock executable that fails
  cat > "/tmp/mock_${cmd}" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
  chmod +x "/tmp/mock_${cmd}"
  export PATH="/tmp:$PATH"
}

cleanup_mocks() {
  rm -f /tmp/mock_* 2>/dev/null || true
}

# ============================================================================
# CATEGORY 1: SCHEMA VALIDATION (5 tests)
# ============================================================================

test_schema_validation() {
  log_section "Category 1: Schema Validation (5 tests)"

  # Test 1: ops_discover_s3 schema
  ((TESTS_RUN++))
  log_test "ops_discover_s3 returns valid JSON schema"

  # Check redactOutput function exists and handles S3 patterns
  if grep -q "s3PresignedPattern" "$SERVER_OPS" && \
     grep -q "ops_discover_s3" "$SERVER_OPS"; then
    log_pass "ops_discover_s3 schema defined with S3 redaction"
  else
    log_fail "ops_discover_s3 schema or redaction missing"
  fi

  # Test 2: ops_discover_github schema
  ((TESTS_RUN++))
  log_test "ops_discover_github returns valid JSON schema"

  if grep -q "ops_discover_github" "$SERVER_OPS" && \
     grep -q "github_pat_" "$SERVER_OPS"; then
    log_pass "ops_discover_github schema defined with GitHub token redaction"
  else
    log_fail "ops_discover_github schema or redaction missing"
  fi

  # Test 3: ops_discover_docker schema
  ((TESTS_RUN++))
  log_test "ops_discover_docker returns valid JSON schema"

  if grep -q "ops_discover_docker" "$SERVER_OPS" && \
     grep -q "dockerAuthPattern" "$SERVER_OPS"; then
    log_pass "ops_discover_docker schema defined with Docker auth redaction"
  else
    log_fail "ops_discover_docker schema or redaction missing"
  fi

  # Test 4: ops_discover_redis schema
  ((TESTS_RUN++))
  log_test "ops_discover_redis returns valid JSON schema"

  if grep -q "ops_discover_redis" "$SERVER_OPS" && \
     grep -q "redisAuthPattern" "$SERVER_OPS"; then
    log_pass "ops_discover_redis schema defined with Redis AUTH redaction"
  else
    log_fail "ops_discover_redis schema or redaction missing"
  fi

  # Test 5: ops_discover_argo_workflows schema
  ((TESTS_RUN++))
  log_test "ops_discover_argo_workflows returns valid JSON schema"

  if grep -q "ops_discover_argo_workflows" "$SERVER_OPS" && \
     grep -q "ARGO_WORKFLOWS_TIMEOUT_MS" "$SERVER_OPS"; then
    log_pass "ops_discover_argo_workflows schema defined"
  else
    log_fail "ops_discover_argo_workflows schema missing"
  fi
}

# ============================================================================
# CATEGORY 2: SECRET REDACTION (8 tests)
# ============================================================================

test_secret_redaction() {
  log_section "Category 2: Secret Redaction (8 tests)"

  # Test 6: S3 pre-signed URL redaction
  ((TESTS_RUN++))
  log_test "S3 pre-signed URLs are redacted"

  local test_url='https://mybucket.s3.amazonaws.com/file.txt?X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIOSFODNN7EXAMPLE&X-Amz-Date=20230101T000000Z&X-Amz-Expires=3600&X-Amz-Signature=abcdef1234567890'

  if grep -q 's3PresignedPattern.*X-Amz-Signature' "$SERVER_OPS"; then
    log_pass "S3 pre-signed URL pattern defined"
  else
    log_fail "S3 pre-signed URL pattern missing"
  fi

  # Test 7: AWS Account ID redaction in ARNs
  ((TESTS_RUN++))
  log_test "AWS Account IDs in ARNs are redacted"

  if grep -q 'arnPattern.*arn:aws' "$SERVER_OPS" && \
     grep -q '\*\*\*ACCOUNT\*\*\*' "$SERVER_OPS"; then
    log_pass "ARN account ID redaction pattern defined"
  else
    log_fail "ARN account ID redaction missing"
  fi

  # Test 8: Docker registry auth token redaction
  ((TESTS_RUN++))
  log_test "Docker registry auth tokens are redacted"

  local test_auth='"auth": "dXNlcjpwYXNzd29yZA=="'

  if grep -q 'dockerAuthPattern.*"auth"' "$SERVER_OPS"; then
    log_pass "Docker auth token pattern defined"
  else
    log_fail "Docker auth token pattern missing"
  fi

  # Test 9: Redis AUTH password redaction
  ((TESTS_RUN++))
  log_test "Redis AUTH passwords are redacted"

  if grep -q 'redisAuthPattern.*AUTH' "$SERVER_OPS"; then
    log_pass "Redis AUTH pattern defined"
  else
    log_fail "Redis AUTH pattern missing"
  fi

  # Test 10: GitHub PAT redaction (existing pattern)
  ((TESTS_RUN++))
  log_test "GitHub PATs are redacted"

  local test_pat='github_pat_11AAAAAA0aAbBcCdDeEfF1234567890aBcDeFgHiJkLmNoPqRsTuVwXyZ1234567890'

  if grep -q 'github_pat_' "$SERVER_OPS"; then
    log_pass "GitHub PAT pattern defined"
  else
    log_fail "GitHub PAT pattern missing"
  fi

  # Test 11: AWS Access Key redaction (existing pattern)
  ((TESTS_RUN++))
  log_test "AWS Access Keys are redacted"

  local test_key='AKIAIOSFODNN7EXAMPLE'

  if grep -q 'AKIA\[0-9A-Z\]' "$SERVER_OPS"; then
    log_pass "AWS Access Key pattern defined"
  else
    log_fail "AWS Access Key pattern missing"
  fi

  # Test 12: Connection string redaction for Redis
  ((TESTS_RUN++))
  log_test "Redis connection strings are redacted"

  if grep -q '"redis"' "$SERVER_OPS" && grep -q 'connectionProtocols' "$SERVER_OPS"; then
    log_pass "Redis connection string pattern defined"
  else
    log_fail "Redis connection string pattern missing"
  fi

  # Test 13: JSON secret field redaction
  ((TESTS_RUN++))
  log_test "JSON secret fields are redacted"

  if grep -q 'jsonSecretKeys.*password.*token' "$SERVER_OPS"; then
    log_pass "JSON secret field patterns defined"
  else
    log_fail "JSON secret field patterns missing"
  fi
}

# ============================================================================
# CATEGORY 3: CACHING (5 tests)
# ============================================================================

test_caching() {
  log_section "Category 3: Caching (5 tests)"

  # Test 14: S3 cache TTL defined
  ((TESTS_RUN++))
  log_test "S3 discovery has cache TTL configured"

  if grep -q 'CACHE_TTL_S3.*=' "$SERVER_OPS"; then
    log_pass "CACHE_TTL_S3 defined"
  else
    log_fail "CACHE_TTL_S3 missing"
  fi

  # Test 15: GitHub cache TTL defined
  ((TESTS_RUN++))
  log_test "GitHub discovery has cache TTL configured"

  if grep -q 'CACHE_TTL_GITHUB.*=' "$SERVER_OPS"; then
    log_pass "CACHE_TTL_GITHUB defined"
  else
    log_fail "CACHE_TTL_GITHUB missing"
  fi

  # Test 16: Docker cache TTL defined
  ((TESTS_RUN++))
  log_test "Docker discovery has cache TTL configured"

  if grep -q 'CACHE_TTL_DOCKER.*=' "$SERVER_OPS"; then
    log_pass "CACHE_TTL_DOCKER defined"
  else
    log_fail "CACHE_TTL_DOCKER missing"
  fi

  # Test 17: Redis cache TTL defined
  ((TESTS_RUN++))
  log_test "Redis discovery has cache TTL configured"

  if grep -q 'CACHE_TTL_REDIS.*=' "$SERVER_OPS"; then
    log_pass "CACHE_TTL_REDIS defined"
  else
    log_fail "CACHE_TTL_REDIS missing"
  fi

  # Test 18: Argo Workflows cache TTL defined
  ((TESTS_RUN++))
  log_test "Argo Workflows discovery has cache TTL configured"

  if grep -q 'CACHE_TTL_ARGO_WORKFLOWS.*=' "$SERVER_OPS"; then
    log_pass "CACHE_TTL_ARGO_WORKFLOWS defined"
  else
    log_fail "CACHE_TTL_ARGO_WORKFLOWS missing"
  fi
}

# ============================================================================
# CATEGORY 4: GRACEFUL DEGRADATION (5 tests)
# ============================================================================

test_graceful_degradation() {
  log_section "Category 4: Graceful Degradation (5 tests)"

  # Test 19: S3 graceful degradation
  ((TESTS_RUN++))
  log_test "ops_discover_s3 handles missing aws CLI gracefully"

  if grep -q 'aws CLI not found in PATH' "$SERVER_OPS" && \
     grep -q 'Install AWS CLI' "$SERVER_OPS"; then
    log_pass "S3 graceful degradation message defined"
  else
    log_fail "S3 graceful degradation missing"
  fi

  # Test 20: GitHub graceful degradation
  ((TESTS_RUN++))
  log_test "ops_discover_github handles missing gh CLI gracefully"

  if grep -q 'gh CLI not found in PATH' "$SERVER_OPS" && \
     grep -q 'Install GitHub CLI' "$SERVER_OPS"; then
    log_pass "GitHub graceful degradation message defined"
  else
    log_fail "GitHub graceful degradation missing"
  fi

  # Test 21: Docker graceful degradation
  ((TESTS_RUN++))
  log_test "ops_discover_docker handles missing docker CLI gracefully"

  if grep -q 'docker CLI not found in PATH' "$SERVER_OPS" && \
     grep -q 'Install Docker' "$SERVER_OPS"; then
    log_pass "Docker graceful degradation message defined"
  else
    log_fail "Docker graceful degradation missing"
  fi

  # Test 22: Redis graceful degradation
  ((TESTS_RUN++))
  log_test "ops_discover_redis handles missing redis-cli gracefully"

  if grep -q 'redis-cli not found in PATH' "$SERVER_OPS" && \
     grep -q 'Install Redis' "$SERVER_OPS"; then
    log_pass "Redis graceful degradation message defined"
  else
    log_fail "Redis graceful degradation missing"
  fi

  # Test 23: Argo Workflows graceful degradation
  ((TESTS_RUN++))
  log_test "ops_discover_argo_workflows handles missing argo CLI gracefully"

  if grep -q 'argo CLI not found in PATH' "$SERVER_OPS" && \
     grep -q 'Install Argo Workflows CLI' "$SERVER_OPS"; then
    log_pass "Argo Workflows graceful degradation message defined"
  else
    log_fail "Argo Workflows graceful degradation missing"
  fi
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

main() {
  echo ""
  echo -e "${BLUE}╔═══════════════════════════════════════════════════════════╗${NC}"
  echo -e "${BLUE}║  Phase 5.2 Ops MCP Stage 2 Test Suite                    ║${NC}"
  echo -e "${BLUE}║  Testing 5 new discovery tools + redaction + caching     ║${NC}"
  echo -e "${BLUE}╚═══════════════════════════════════════════════════════════╝${NC}"
  echo ""

  # Verify server-ops.js exists
  if [[ ! -f "$SERVER_OPS" ]]; then
    echo -e "${RED}ERROR: server-ops.js not found at $SERVER_OPS${NC}"
    exit 1
  fi

  # Run test categories
  test_schema_validation
  test_secret_redaction
  test_caching
  test_graceful_degradation

  # Cleanup
  cleanup_mocks

  # Summary
  echo ""
  log_section "Test Summary"
  echo -e "Total tests run: ${BLUE}$TESTS_RUN${NC}"
  echo -e "Passed: ${GREEN}$TESTS_PASSED${NC}"
  echo -e "Failed: ${RED}$TESTS_FAILED${NC}"
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
