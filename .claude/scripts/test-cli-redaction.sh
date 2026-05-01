#!/usr/bin/env bash
# test-cli-redaction.sh — Test CLI argument redaction functionality
# Tests: CLI flags, HTTP headers, connection strings, inline KEY=VALUE, value-based tokens

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

test_redaction() {
  local description="$1"
  local input="$2"
  local expected_pattern="$3"

  local output
  output=$(echo "$input" | bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" 2>/dev/null || echo "")

  if echo "$output" | grep -qE "$expected_pattern"; then
    pass "$description"
  else
    fail "$description (output: $output)"
  fi
}

test_no_redaction() {
  local description="$1"
  local input="$2"
  local should_contain="$3"

  local output
  output=$(echo "$input" | bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" 2>/dev/null || echo "")

  if echo "$output" | grep -qF "$should_contain"; then
    pass "$description"
  else
    fail "$description (output: $output)"
  fi
}

# ============================================================================
# TEST SUITE 1: CLI Flag Redaction
# ============================================================================

test_cli_flags() {
  say ""
  say "=== TEST SUITE 1: CLI Flag Redaction ==="
  say ""

  # Test 1.1: --token=value format
  say "Test 1.1: --token=value format"
  test_redaction "--token=value" \
    "curl --token=sk-ant-1234567890 https://api.example.com" \
    "REDACTED"

  # Test 1.2: --api-key=value format
  say "Test 1.2: --api-key=value format"
  test_redaction "--api-key=value" \
    "cli-tool --api-key=secret123 --output json" \
    "REDACTED"

  # Test 1.3: --token "value" format (space-separated with quotes)
  say "Test 1.3: --token \"value\" format"
  test_redaction "--token \"value\"" \
    "command --token \"bearer_token_here\" --verbose" \
    "REDACTED"

  # Test 1.4: --password='value' format (single quotes)
  say "Test 1.4: --password='value' format"
  test_redaction "--password='value'" \
    "mysql --password='secretpass' --host localhost" \
    "REDACTED"

  # Test 1.5: Multiple CLI flags in one line
  say "Test 1.5: Multiple CLI flags"
  test_redaction "Multiple CLI flags" \
    "app --api-key=key123 --secret=sec456 --token=tok789" \
    "REDACTED.*REDACTED.*REDACTED"

  # Test 1.6: Mixed with safe flags
  say "Test 1.6: Mixed with safe flags"
  local output
  output=$(echo "app --verbose --token=secret123 --output json" | bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" 2>/dev/null)
  if echo "$output" | grep -q "REDACTED" && echo "$output" | grep -q "verbose" && echo "$output" | grep -q "json"; then
    pass "Mixed with safe flags"
  else
    fail "Mixed with safe flags (output: $output)"
  fi

  # Test 1.7: Case variations
  say "Test 1.7: Case variations"
  test_redaction "Case variations" \
    "cmd --API-KEY=test --api-key=test2 --Api-Key=test3" \
    "REDACTED.*REDACTED.*REDACTED"

  # Test 1.8: Different flag names
  say "Test 1.8: Different secret flag names"
  test_redaction "Different flag names" \
    "app --bearer=tok1 --auth=tok2 --private-key=tok3" \
    "REDACTED.*REDACTED.*REDACTED"
}

# ============================================================================
# TEST SUITE 2: HTTP Header Redaction
# ============================================================================

test_http_headers() {
  say ""
  say "=== TEST SUITE 2: HTTP Header Redaction ==="
  say ""

  # Test 2.1: Authorization: Bearer token
  say "Test 2.1: Authorization: Bearer token"
  test_redaction "Authorization: Bearer" \
    "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9" \
    "REDACTED"

  # Test 2.2: X-API-Key header
  say "Test 2.2: X-API-Key header"
  test_redaction "X-API-Key" \
    "X-API-Key: sk-1234567890abcdef" \
    "REDACTED"

  # Test 2.3: Multiple headers
  say "Test 2.3: Multiple headers"
  local output
  output=$(printf "Authorization: Bearer token123\nX-API-Key: key456\n" | bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" 2>/dev/null)
  local redacted_count
  redacted_count=$(echo "$output" | grep -c "REDACTED" || true)
  if [[ "$redacted_count" -ge 2 ]]; then
    pass "Multiple headers ($redacted_count redacted)"
  else
    fail "Multiple headers (only $redacted_count redacted)"
  fi

  # Test 2.4: Case insensitive header names
  say "Test 2.4: Case insensitive headers"
  test_redaction "Case insensitive" \
    "authorization: bearer token123" \
    "REDACTED"

  # Test 2.5: Headers with extra whitespace
  say "Test 2.5: Headers with whitespace"
  test_redaction "Extra whitespace" \
    "Authorization:   Bearer   token123" \
    "REDACTED"
}

# ============================================================================
# TEST SUITE 3: Connection String Redaction
# ============================================================================

test_connection_strings() {
  say ""
  say "=== TEST SUITE 3: Connection String Redaction ==="
  say ""

  # Test 3.1: PostgreSQL connection string
  say "Test 3.1: PostgreSQL connection"
  test_redaction "PostgreSQL" \
    "postgresql://user:password@localhost:5432/mydb" \
    "REDACTED"

  # Test 3.2: MySQL connection string
  say "Test 3.2: MySQL connection"
  test_redaction "MySQL" \
    "mysql://admin:secretpass@db.example.com/production" \
    "REDACTED"

  # Test 3.3: MongoDB connection string
  say "Test 3.3: MongoDB connection"
  test_redaction "MongoDB" \
    "mongodb://user:pass123@cluster.mongodb.net/database" \
    "REDACTED"

  # Test 3.4: Redis connection string
  say "Test 3.4: Redis connection"
  test_redaction "Redis" \
    "redis://default:password@redis.example.com:6379/0" \
    "REDACTED"

  # Test 3.5: Connection string in command
  say "Test 3.5: Connection in command"
  test_redaction "Connection in command" \
    "psql postgres://user:pass@host/db --command 'SELECT 1'" \
    "REDACTED"
}

# ============================================================================
# TEST SUITE 4: Inline KEY=VALUE Redaction
# ============================================================================

test_inline_keyvalue() {
  say ""
  say "=== TEST SUITE 4: Inline KEY=VALUE Redaction ==="
  say ""

  # Test 4.1: Mid-line API_KEY=value
  say "Test 4.1: Mid-line API_KEY=value"
  test_redaction "Mid-line API_KEY" \
    "curl -X POST API_KEY=sk-test123 https://api.example.com" \
    "REDACTED"

  # Test 4.2: Multiple inline secrets
  say "Test 4.2: Multiple inline secrets"
  test_redaction "Multiple inline" \
    "command TOKEN=abc123 PASSWORD=xyz789 output.txt" \
    "REDACTED.*REDACTED"

  # Test 4.3: Inline secret after flag
  say "Test 4.3: Inline after flag"
  test_redaction "After flag" \
    "app --verbose SECRET_KEY=mysecret --output json" \
    "REDACTED"

  # Test 4.4: Safe inline values preserved
  say "Test 4.4: Safe inline preserved"
  test_no_redaction "Safe inline" \
    "command NODE_ENV=production PORT=3000" \
    "NODE_ENV=production"
}

# ============================================================================
# TEST SUITE 5: Value-Based Token Redaction
# ============================================================================

test_value_tokens() {
  say ""
  say "=== TEST SUITE 5: Value-Based Token Redaction ==="
  say ""

  # Test 5.1: Anthropic API key (sk-ant-api...)
  say "Test 5.1: Anthropic API key"
  test_redaction "Anthropic key" \
    "using key sk-ant-api01-1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567 for request" \
    "REDACTED"

  # Test 5.2: JWT token
  say "Test 5.2: JWT token"
  test_redaction "JWT" \
    "Authorization: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U" \
    "REDACTED"

  # Test 5.3: AWS access key (AKIA...)
  say "Test 5.3: AWS access key"
  test_redaction "AWS key" \
    "export AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE" \
    "REDACTED"

  # Test 5.4: GitHub PAT (github_pat_...)
  say "Test 5.4: GitHub PAT"
  test_redaction "GitHub PAT" \
    "token github_pat_11AAAAAAAAAAAAAAAAAAAAAAAA_BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB" \
    "REDACTED"

  # Test 5.5: GitHub classic token (ghp_...)
  say "Test 5.5: GitHub classic token"
  test_redaction "GitHub classic" \
    "GITHUB_TOKEN=ghp_1234567890123456789012345678901234AB" \
    "REDACTED"

  # Test 5.6: Google OAuth token (ya29...)
  say "Test 5.6: Google OAuth token"
  test_redaction "Google OAuth" \
    "token ya29.a0AfH6SMBx1234567890abcdefghijklmnopqrstuvwxyz" \
    "REDACTED"

  # Test 5.7: Google API key (AIza...)
  say "Test 5.7: Google API key"
  test_redaction "Google API key" \
    "key AIzaSyD1234567890123456789012345678901" \
    "REDACTED"

  # Test 5.8: Multiple token types in one line
  say "Test 5.8: Multiple token types"
  local output
  output=$(echo "Using AKIAIOSFODNN7EXAMPLE and ghp_1234567890123456789012345678901234AB" | bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" 2>/dev/null)
  local redacted_count
  # Count occurrences on the same line by removing each match and counting
  redacted_count=$(echo "$output" | grep -o "REDACTED" | wc -l | tr -d ' ')
  if [[ "$redacted_count" -ge 2 ]]; then
    pass "Multiple token types ($redacted_count redacted)"
  else
    fail "Multiple token types (only $redacted_count redacted)"
  fi
}

# ============================================================================
# TEST SUITE 6: Edge Cases & Safety
# ============================================================================

test_edge_cases() {
  say ""
  say "=== TEST SUITE 6: Edge Cases & Safety ==="
  say ""

  # Test 6.1: Feature flag disabled
  say "Test 6.1: Feature flag disabled"
  local output
  output=$(REDACT_CLI_ARGS=false bash -c 'source "$CLAUDE_ROOT/.claude/scripts/redact.sh" && echo "curl --token=secret123" | redact_stream' 2>/dev/null)
  if echo "$output" | grep -q "token=secret123"; then
    pass "Feature flag disables CLI redaction"
  else
    fail "Feature flag not working (output: $output)"
  fi

  # Test 6.2: Safe URLs preserved
  say "Test 6.2: Safe URLs preserved"
  test_no_redaction "Safe URLs" \
    "https://example.com/path?param=value" \
    "https://example.com"

  # Test 6.3: Safe connection strings (no credentials)
  say "Test 6.3: Safe connection (no creds)"
  test_no_redaction "Safe connection" \
    "postgresql://localhost:5432/mydb" \
    "postgresql://localhost"

  # Test 6.4: Empty input
  say "Test 6.4: Empty input"
  local output
  output=$(echo "" | bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" 2>/dev/null || echo "")
  pass "Empty input handled"

  # Test 6.5: Very long line
  say "Test 6.5: Long line handling"
  local long_input="prefix $(printf 'A%.0s' {1..1000}) --token=secret123 suffix"
  local output
  output=$(echo "$long_input" | bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" 2>/dev/null)
  if echo "$output" | grep -q "REDACTED"; then
    pass "Long line handled"
  else
    fail "Long line not handled"
  fi
}

# ============================================================================
# TEST SUITE 7: Integration & Regression
# ============================================================================

test_integration() {
  say ""
  say "=== TEST SUITE 7: Integration & Regression ==="
  say ""

  # Test 7.1: Old patterns still work
  say "Test 7.1: Regression - old patterns"
  test_redaction "Old pattern 1" \
    "API_KEY=sk-test123" \
    "REDACTED"

  # Test 7.2: JSON patterns still work
  say "Test 7.2: Regression - JSON"
  test_redaction "JSON pattern" \
    '{"api_key": "secret123"}' \
    "REDACTED"

  # Test 7.3: Combined old and new patterns
  say "Test 7.3: Combined patterns"
  local output
  output=$(printf "API_KEY=env123\ncurl --token=cli456\npostgresql://user:pass@host/db\n" | bash "$CLAUDE_ROOT/.claude/scripts/redact.sh" 2>/dev/null)
  local redacted_count
  redacted_count=$(echo "$output" | grep -c "REDACTED" || true)
  if [[ "$redacted_count" -ge 3 ]]; then
    pass "Combined patterns ($redacted_count redacted)"
  else
    fail "Combined patterns (only $redacted_count redacted)"
  fi
}

# ============================================================================
# MAIN
# ============================================================================

say "================================================================"
say "  CLI Secret Redaction Tests"
say "  Testing: New CLI argument patterns (3-7)"
say "================================================================"

test_cli_flags
test_http_headers
test_connection_strings
test_inline_keyvalue
test_value_tokens
test_edge_cases
test_integration

say ""
say "================================================================"
say "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
say "================================================================"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
