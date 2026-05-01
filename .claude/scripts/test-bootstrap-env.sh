#!/usr/bin/env bash
# test-bootstrap-env.sh — E2E Tests for bootstrap-env.sh
# Tests: Project detection, .env.local generation, idempotency, redaction
# Expected: 12 E2E tests passing in <10s

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_ROOT="${CLAUDE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
HARNESS_DIR="$SCRIPT_DIR/test-harness"
BOOTSTRAP_SCRIPT="$SCRIPT_DIR/bootstrap-env.sh"

# Load shared libraries
source "$SCRIPT_DIR/lib/test-framework.sh"

# Setup: Create temporary test fixture
TEST_ROOT=$(mktemp -d /tmp/test-bootstrap-XXXXXX)
trap 'rm -rf "$TEST_ROOT"' EXIT

setup_fixtures() {
  info "Setting up test fixtures in: $TEST_ROOT"

  # Create fake Next.js project
  mkdir -p "$TEST_ROOT/apps/web"
  cat > "$TEST_ROOT/apps/web/package.json" <<'EOF'
{
  "name": "web",
  "version": "1.0.0",
  "dependencies": {
    "next": "^14.0.0",
    "react": "^18.0.0"
  }
}
EOF

  # Create fake Supabase project
  mkdir -p "$TEST_ROOT/supabase/migrations"
  cat > "$TEST_ROOT/supabase/config.toml" <<'EOF'
[api]
port = 54321
enabled = true
EOF

  # Create fake Docker project
  mkdir -p "$TEST_ROOT/services/api"
  cat > "$TEST_ROOT/services/api/docker-compose.yml" <<'EOF'
version: '3.8'
services:
  api:
    image: node:20
    ports:
      - "3000:3000"
EOF

  # Create fake k8s project
  mkdir -p "$TEST_ROOT/infra/charts"
  cat > "$TEST_ROOT/infra/values.yaml" <<'EOF'
replicaCount: 3
image:
  repository: myapp
  tag: latest
EOF

  # Create nested project (should not exceed max depth)
  mkdir -p "$TEST_ROOT/apps/web/node_modules/some-package"
  cat > "$TEST_ROOT/apps/web/node_modules/some-package/package.json" <<'EOF'
{
  "name": "some-package",
  "version": "1.0.0"
}
EOF
}

# ============================================================================
# PHASE A: SCRIPT VALIDATION (3 tests)
# ============================================================================

info "Phase A: Script Validation"

# Test 1: Script is executable
test_script_executable() {
  if [[ -x "$BOOTSTRAP_SCRIPT" ]]; then
    pass "A1: bootstrap-env.sh is executable"
  else
    fail "A1: bootstrap-env.sh executable" "Script not executable"
  fi
}

# Test 2: Script has help flag
test_help_flag() {
  if "$BOOTSTRAP_SCRIPT" --help 2>&1 | grep -q "Usage:"; then
    pass "A2: --help flag works"
  else
    fail "A2: --help flag" "Help output not found"
  fi
}

# Test 3: Script has redaction function
test_redaction_function() {
  if grep -q "redact_output" "$BOOTSTRAP_SCRIPT"; then
    pass "A3: redact_output function exists"
  else
    fail "A3: redact_output function" "Function not found"
  fi
}

test_script_executable
test_help_flag
test_redaction_function

# ============================================================================
# PHASE B: PROJECT DETECTION (4 tests)
# ============================================================================

info "Phase B: Project Detection"

setup_fixtures

# Test 4: Detects Next.js project
test_detect_nextjs() {
  local output
  output=$("$BOOTSTRAP_SCRIPT" --dry-run --project "$TEST_ROOT/apps/web" 2>&1 | grep -c "nextjs" || true)

  if [[ $output -gt 0 ]]; then
    pass "B1: Detects Next.js project"
  else
    fail "B1: Next.js detection" "Expected 'nextjs' in output"
  fi
}

# Test 5: Detects Supabase project
test_detect_supabase() {
  local output
  output=$("$BOOTSTRAP_SCRIPT" --dry-run --project "$TEST_ROOT" 2>&1 | grep -c "supabase" || true)

  if [[ $output -gt 0 ]]; then
    pass "B2: Detects Supabase project"
  else
    fail "B2: Supabase detection" "Expected 'supabase' in output"
  fi
}

# Test 6: Detects Docker project
test_detect_docker() {
  local output
  output=$("$BOOTSTRAP_SCRIPT" --dry-run --project "$TEST_ROOT" 2>&1 | grep -c "docker" || true)

  if [[ $output -gt 0 ]]; then
    pass "B3: Detects Docker project"
  else
    fail "B3: Docker detection" "Expected 'docker' in output"
  fi
}

# Test 7: Detects K8s project
test_detect_k8s() {
  local output
  output=$("$BOOTSTRAP_SCRIPT" --dry-run --project "$TEST_ROOT" 2>&1 | grep -c "k8s" || true)

  if [[ $output -gt 0 ]]; then
    pass "B4: Detects K8s project"
  else
    fail "B4: K8s detection" "Expected 'k8s' in output"
  fi
}

test_detect_nextjs
test_detect_supabase
test_detect_docker
test_detect_k8s

# ============================================================================
# PHASE C: FILE GENERATION (3 tests)
# ============================================================================

info "Phase C: File Generation"

# Test 8: Creates .env.local with empty values
test_creates_env_file() {
  "$BOOTSTRAP_SCRIPT" --project "$TEST_ROOT/apps/web" >/dev/null 2>&1

  if [[ -f "$TEST_ROOT/apps/web/.env.local" ]]; then
    # Check that file has keys but empty values
    if grep -q "DATABASE_URL=" "$TEST_ROOT/apps/web/.env.local" && ! grep -q "DATABASE_URL=.\\+" "$TEST_ROOT/apps/web/.env.local"; then
      pass "C1: Creates .env.local with empty values"
    else
      fail "C1: .env.local generation" "File has non-empty values"
    fi
  else
    fail "C1: .env.local generation" ".env.local not created"
  fi
}

# Test 9: Idempotency (no changes on re-run)
test_idempotency() {
  # First run
  "$BOOTSTRAP_SCRIPT" --project "$TEST_ROOT/apps/web" >/dev/null 2>&1
  local size1
  size1=$(stat -f%z "$TEST_ROOT/apps/web/.env.local" 2>/dev/null || stat -c%s "$TEST_ROOT/apps/web/.env.local" 2>/dev/null)

  # Second run (should skip)
  local output
  output=$("$BOOTSTRAP_SCRIPT" --project "$TEST_ROOT/apps/web" 2>&1 | grep -c "already exists" || true)

  if [[ $output -gt 0 ]]; then
    pass "C2: Idempotent (skips existing .env.local)"
  else
    fail "C2: Idempotency" "Expected 'already exists' message"
  fi
}

# Test 10: Force flag overwrites
test_force_overwrite() {
  # Create initial file
  "$BOOTSTRAP_SCRIPT" --project "$TEST_ROOT/apps/web" >/dev/null 2>&1
  sleep 1

  # Overwrite with --force
  "$BOOTSTRAP_SCRIPT" --project "$TEST_ROOT/apps/web" --force >/dev/null 2>&1

  if [[ -f "$TEST_ROOT/apps/web/.env.local" ]]; then
    pass "C3: --force overwrites existing .env.local"
  else
    fail "C3: Force overwrite" ".env.local not found after --force"
  fi
}

test_creates_env_file
test_idempotency
test_force_overwrite

# ============================================================================
# PHASE D: SECURITY & REDACTION (2 tests)
# ============================================================================

info "Phase D: Security & Redaction"

# Test 11: Output does not contain secrets
test_output_no_secrets() {
  # Add a fake secret to env
  export DATABASE_URL="postgres://user:SuperSecret123@db.example.com:5432/prod"

  # Run bootstrap and capture output
  local output
  output=$("$BOOTSTRAP_SCRIPT" --project "$TEST_ROOT/apps/web" --force 2>&1 || true)

  # Check output does NOT contain the secret
  if echo "$output" | grep -q "SuperSecret123"; then
    fail "D1: Output redaction" "Secret leaked in output: SuperSecret123"
  else
    pass "D1: Output does not contain secrets"
  fi

  unset DATABASE_URL
}

# Test 12: .env.local has correct permissions
test_file_permissions() {
  "$BOOTSTRAP_SCRIPT" --project "$TEST_ROOT/apps/web" --force >/dev/null 2>&1

  # Check permissions (should be 600 = -rw-------)
  local perms
  perms=$(stat -f%Lp "$TEST_ROOT/apps/web/.env.local" 2>/dev/null || stat -c%a "$TEST_ROOT/apps/web/.env.local" 2>/dev/null)

  if [[ "$perms" == "600" ]]; then
    pass "D2: .env.local has restrictive permissions (600)"
  else
    fail "D2: File permissions" "Expected 600, got $perms"
  fi
}

test_output_no_secrets
test_file_permissions

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Results: bootstrap-env.sh E2E Tests"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Total Tests:  $TESTS_RUN"
echo -e "Passed:       ${GREEN}${TESTS_PASSED}${NC}"
echo -e "Failed:       ${RED}${TESTS_FAILED}${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo -e "${GREEN}✓ All tests passed${NC}"
  exit 0
else
  echo -e "${RED}✗ Some tests failed${NC}"
  exit 1
fi
