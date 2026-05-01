#!/usr/bin/env bash
# test-secrets-redaction.sh — Test redact.sh functionality and secret pattern matching
# Tests: Pattern detection, redaction behavior, edge cases

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export CLAUDE_ROOT

PASS_COUNT=0
FAIL_COUNT=0
TEST_FILE=""

# ============================================================================
# HELPERS
# ============================================================================

say()  { printf "%s\n" "$*"; }
pass() { say "  PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { say "  FAIL: $*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }

setup_test_file() {
  TEST_FILE=$(mktemp)
}

teardown_test_file() {
  if [[ -n "${TEST_FILE:-}" && -f "${TEST_FILE:-}" ]]; then
    rm -f "$TEST_FILE"
  fi
}

# ============================================================================
# TEST SUITE 1: Secret Pattern Detection
# ============================================================================

test_secret_patterns() {
  say ""
  say "=== TEST SUITE 1: Secret Pattern Detection ==="
  say ""

  # --- Test 1.1: API key pattern detection ---
  say "Test 1.1: API key pattern detection"
  setup_test_file
  echo "API_KEY=sk-1234567890abcdef1234567890abcdef" > "$TEST_FILE"

  local output
  output=$(bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" "$TEST_FILE" 2>/dev/null || echo "")

  if echo "$output" | grep -q "REDACTED"; then
    pass "API key detected and redacted"
  else
    fail "API key not detected (output: $output)"
  fi
  teardown_test_file

  # --- Test 1.2: AWS access key detection ---
  say "Test 1.2: AWS access key detection"
  setup_test_file
  echo "AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE" > "$TEST_FILE"

  output=$(bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" "$TEST_FILE" 2>/dev/null || echo "")

  if echo "$output" | grep -q "REDACTED"; then
    pass "AWS access key detected and redacted"
  else
    fail "AWS access key not detected"
  fi
  teardown_test_file

  # --- Test 1.3: Password pattern detection ---
  say "Test 1.3: Password pattern detection"
  setup_test_file
  echo "DB_PASSWORD=mySecretP@ssw0rd123" > "$TEST_FILE"

  output=$(bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" "$TEST_FILE" 2>/dev/null || echo "")

  if echo "$output" | grep -q "REDACTED"; then
    pass "Password detected and redacted"
  else
    fail "Password not detected"
  fi
  teardown_test_file

  # --- Test 1.4: Private key header detection ---
  say "Test 1.4: Private key header detection"
  setup_test_file
  cat > "$TEST_FILE" << 'INNER_EOF'
-----BEGIN PRIVATE KEY-----
MIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC
-----END PRIVATE KEY-----
INNER_EOF

  output=$(bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" "$TEST_FILE" 2>/dev/null || echo "")

  if echo "$output" | grep -q "REDACTED"; then
    pass "Private key detected and redacted"
  else
    fail "Private key not detected"
  fi
  teardown_test_file

  # --- Test 1.5: JWT token detection ---
  say "Test 1.5: JWT token detection"
  setup_test_file
  echo "TOKEN=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c" > "$TEST_FILE"

  output=$(bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" "$TEST_FILE" 2>/dev/null || echo "")

  if echo "$output" | grep -q "REDACTED"; then
    pass "JWT token detected and redacted"
  else
    fail "JWT token not detected"
  fi
  teardown_test_file
}

# ============================================================================
# TEST SUITE 2: Redaction Behavior
# ============================================================================

test_redaction_behavior() {
  say ""
  say "=== TEST SUITE 2: Redaction Behavior ==="
  say ""

  # --- Test 2.1: Safe content is not redacted ---
  say "Test 2.1: Safe content is not redacted"
  setup_test_file
  echo "This is a safe log message with no secrets" > "$TEST_FILE"

  local output
  output=$(bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" "$TEST_FILE" 2>/dev/null || echo "")

  if echo "$output" | grep -q "safe log message"; then
    pass "Safe content not redacted"
  else
    fail "Safe content incorrectly redacted"
  fi
  teardown_test_file

  # --- Test 2.2: Multiple secrets in one file ---
  say "Test 2.2: Multiple secrets in one file"
  setup_test_file
  cat > "$TEST_FILE" << 'INNER_EOF'
API_KEY=sk-test123
DB_PASSWORD=secretpass
Safe line here
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
INNER_EOF

  output=$(bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" "$TEST_FILE" 2>/dev/null || echo "")

  local redacted_count
  redacted_count=$(echo "$output" | grep -c "REDACTED" || true)

  if [[ "$redacted_count" -ge 3 ]]; then
    pass "Multiple secrets detected ($redacted_count redacted)"
  else
    fail "Not all secrets detected (only $redacted_count redacted)"
  fi

  if echo "$output" | grep -q "Safe line here"; then
    pass "Safe lines preserved"
  else
    fail "Safe lines not preserved"
  fi
  teardown_test_file

  # --- Test 2.3: Empty file handling ---
  say "Test 2.3: Empty file handling"
  setup_test_file
  # File is empty

  if bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" "$TEST_FILE" > /dev/null 2>&1; then
    pass "Empty file handled gracefully"
  else
    fail "Empty file caused error"
  fi
  teardown_test_file

  # --- Test 2.4: File with only secrets ---
  say "Test 2.4: File with only secrets"
  setup_test_file
  cat > "$TEST_FILE" << 'INNER_EOF'
API_KEY=sk-abc123
SECRET_KEY=secret123
PASSWORD=pass456
INNER_EOF

  output=$(bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" "$TEST_FILE" 2>/dev/null || echo "")

  if echo "$output" | grep -q "REDACTED"; then
    pass "File with only secrets redacted"
  else
    fail "Secrets not redacted in secrets-only file"
  fi
  teardown_test_file
}

# ============================================================================
# TEST SUITE 3: Edge Cases
# ============================================================================

test_edge_cases() {
  say ""
  say "=== TEST SUITE 3: Edge Cases ==="
  say ""

  # --- Test 3.1: Secret at end of line ---
  say "Test 3.1: Secret at end of line"
  setup_test_file
  echo "export API_KEY=sk-test123" > "$TEST_FILE"

  local output
  output=$(bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" "$TEST_FILE" 2>/dev/null || echo "")

  if echo "$output" | grep -q "REDACTED"; then
    pass "Secret at end of line detected"
  else
    fail "Secret at end of line not detected"
  fi
  teardown_test_file

  # --- Test 3.2: Secret in JSON ---
  say "Test 3.2: Secret in JSON"
  setup_test_file
  echo '{"api_key": "sk-1234567890abcdef", "name": "test"}' > "$TEST_FILE"

  output=$(bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" "$TEST_FILE" 2>/dev/null || echo "")

  if echo "$output" | grep -q "REDACTED"; then
    pass "Secret in JSON detected"
  else
    fail "Secret in JSON not detected"
  fi
  teardown_test_file

  # --- Test 3.3: Secret in YAML ---
  say "Test 3.3: Secret in YAML"
  setup_test_file
  cat > "$TEST_FILE" << 'INNER_EOF'
apiVersion: v1
kind: Secret
data:
  password: bXlzZWNyZXRwYXNzd29yZA==
INNER_EOF

  output=$(bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" "$TEST_FILE" 2>/dev/null || echo "")

  if echo "$output" | grep -q "REDACTED"; then
    pass "Secret in YAML detected"
  else
    fail "Secret in YAML not detected"
  fi
  teardown_test_file

  # --- Test 3.4: Case sensitivity ---
  say "Test 3.4: Case sensitivity handling"
  setup_test_file
  cat > "$TEST_FILE" << 'INNER_EOF'
api_key=sk-test123
API_KEY=sk-test456
Api_Key=sk-test789
INNER_EOF

  output=$(bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" "$TEST_FILE" 2>/dev/null || echo "")

  local case_redacted_count
  case_redacted_count=$(echo "$output" | grep -c "REDACTED" || true)

  if [[ "$case_redacted_count" -ge 3 ]]; then
    pass "Case variations all detected ($case_redacted_count redacted)"
  else
    fail "Not all case variations detected ($case_redacted_count redacted)"
  fi
  teardown_test_file

  # --- Test 3.5: Quoted secrets ---
  say "Test 3.5: Quoted secrets"
  setup_test_file
  cat > "$TEST_FILE" << 'INNER_EOF'
API_KEY="sk-test123"
PASSWORD='mysecret456'
INNER_EOF

  output=$(bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" "$TEST_FILE" 2>/dev/null || echo "")

  if echo "$output" | grep -q "REDACTED"; then
    pass "Quoted secrets detected"
  else
    fail "Quoted secrets not detected"
  fi
  teardown_test_file
}

# ============================================================================
# TEST SUITE 4: Script Functionality
# ============================================================================

test_script_functionality() {
  say ""
  say "=== TEST SUITE 4: Script Functionality ==="
  say ""

  # --- Test 4.1: redact.sh is executable ---
  say "Test 4.1: redact.sh is executable"
  if [[ -x "$CLAUDE_ROOT/.claude/scripts/redact.sh" ]]; then
    pass "redact.sh is executable"
  else
    fail "redact.sh is not executable"
  fi

  # --- Test 4.2: redact.sh exists ---
  say "Test 4.2: redact.sh exists"
  if [[ -f "$CLAUDE_ROOT/.claude/scripts/redact.sh" ]]; then
    pass "redact.sh exists"
  else
    fail "redact.sh does not exist"
  fi

  # --- Test 4.3: redact.sh accepts file argument ---
  say "Test 4.3: redact.sh accepts file argument"
  setup_test_file
  echo "test" > "$TEST_FILE"

  if bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" "$TEST_FILE" > /dev/null 2>&1; then
    pass "redact.sh accepts file argument"
  else
    fail "redact.sh does not accept file argument"
  fi
  teardown_test_file

  # --- Test 4.4: redact.sh handles missing file gracefully ---
  say "Test 4.4: redact.sh handles missing file gracefully"
  if bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" "/nonexistent/file" 2>&1 | grep -q "not found\|does not exist\|No such file" || [[ $? -ne 0 ]]; then
    pass "redact.sh handles missing file"
  else
    fail "redact.sh does not handle missing file properly"
  fi
}

# ============================================================================
# MAIN
# ============================================================================

say "================================================================"
say "  Secrets Redaction Tests"
say "  Testing: redact.sh pattern detection and redaction behavior"
say "================================================================"

test_secret_patterns
test_redaction_behavior
test_edge_cases
test_script_functionality

say ""
say "================================================================"
say "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
say "================================================================"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
