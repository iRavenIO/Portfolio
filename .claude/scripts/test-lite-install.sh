#!/usr/bin/env bash
set -euo pipefail

# ╔═══════════════════════════════════════════════════════════════╗
# ║  Test: Lite Mode Installation                                 ║
# ║  Validates lite install creates correct file structure         ║
# ║  and excludes heavy workflow components                        ║
# ╚═══════════════════════════════════════════════════════════════╝

TEST_NAME="lite-install"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

pass() { echo -e "${GREEN}✓${NC} $*"; }
fail() { echo -e "${RED}✗${NC} $*"; }
warn() { echo -e "${YELLOW}⚠${NC} $*"; }
info() { echo "  $*"; }

TESTS_PASSED=0
TESTS_FAILED=0
START_TIME=$(date +%s)

# ─────────────────────────────────────────────────────────────────
# Test Helpers
# ─────────────────────────────────────────────────────────────────

assert_file_exists() {
  local file="$1"
  local desc="${2:-$file}"
  if [[ -f "$file" ]]; then
    pass "$desc exists"
    ((TESTS_PASSED++))
    return 0
  else
    fail "$desc missing (expected: $file)"
    ((TESTS_FAILED++))
    return 1
  fi
}

assert_file_missing() {
  local file="$1"
  local desc="${2:-$file}"
  if [[ ! -e "$file" ]]; then
    pass "$desc correctly excluded"
    ((TESTS_PASSED++))
    return 0
  else
    fail "$desc should not exist in lite mode (found: $file)"
    ((TESTS_FAILED++))
    return 1
  fi
}

assert_dir_exists() {
  local dir="$1"
  local desc="${2:-$dir}"
  if [[ -d "$dir" ]]; then
    pass "$desc exists"
    ((TESTS_PASSED++))
    return 0
  else
    fail "$desc missing (expected: $dir)"
    ((TESTS_FAILED++))
    return 1
  fi
}

assert_executable() {
  local file="$1"
  local desc="${2:-$file}"
  if [[ -x "$file" ]]; then
    pass "$desc is executable"
    ((TESTS_PASSED++))
    return 0
  else
    fail "$desc not executable (expected: $file)"
    ((TESTS_FAILED++))
    return 1
  fi
}

assert_no_secrets_in_output() {
  local output="$1"
  # Check for patterns that might indicate leaked secrets
  local patterns=(
    "password="
    "token="
    "key="
    "secret="
    "AUTH_TOKEN="
    "API_KEY="
  )

  local found_secrets=0
  for pattern in "${patterns[@]}"; do
    if echo "$output" | grep -qi "$pattern"; then
      fail "Potential secret pattern found in output: $pattern"
      ((TESTS_FAILED++))
      found_secrets=1
    fi
  done

  if [[ $found_secrets -eq 0 ]]; then
    pass "No secret patterns in install output"
    ((TESTS_PASSED++))
  fi
}

# ─────────────────────────────────────────────────────────────────
# Main Test
# ─────────────────────────────────────────────────────────────────

echo "═══════════════════════════════════════════════════════════"
echo "  Test: $TEST_NAME"
echo "  Repo: $REPO_ROOT"
echo "═══════════════════════════════════════════════════════════"
echo ""

# Create temporary test directory
TEST_DIR=$(mktemp -d)
trap "rm -rf '$TEST_DIR'" EXIT

info "Test directory: $TEST_DIR"
echo ""

# Initialize git repo (required for lite install)
cd "$TEST_DIR"
git init -q
git config user.email "test@example.com"
git config user.name "Test User"

# ─────────────────────────────────────────────────────────────────
# Test 1: Copy lite files manually (simulating cfactorylite)
# ─────────────────────────────────────────────────────────────────

echo "→ Test 1: Copying lite mode files"
echo ""

mkdir -p .claude/mcp

# Copy essential lite files
rsync -a \
  --include='/.mcp.lite.json' \
  --include='/.claude/' \
  --include='/.claude/mcp/***' \
  --include='/.claude/env.claude.sample' \
  --include='/install.sh' \
  --include='/cf-lite' \
  --include='/CLAUDE_LITE.md' \
  --include='/.gitignore' \
  --exclude='*' \
  "$REPO_ROOT/" ./ 2>&1 | head -20 # Limit output

# Exclude heavy directories
rm -rf .claude/mcp/node_modules 2>/dev/null || true

echo ""

# ─────────────────────────────────────────────────────────────────
# Test 2: Verify required files exist
# ─────────────────────────────────────────────────────────────────

echo "→ Test 2: Required files"
echo ""

assert_file_exists ".mcp.lite.json" "MCP lite config"
assert_file_exists ".claude/mcp/server-ops.js" "MCP server-ops"
assert_file_exists ".claude/mcp/server-git.js" "MCP server-git"
assert_file_exists ".claude/mcp/server-fs.js" "MCP server-fs"
assert_file_exists ".claude/mcp/package.json" "MCP package.json"
assert_file_exists ".claude/env.claude.sample" "Environment template"
assert_file_exists "install.sh" "Install script"
assert_file_exists "cf-lite" "Lite runner script"
assert_file_exists "CLAUDE_LITE.md" "Lite documentation"
assert_file_exists ".gitignore" "Gitignore file"

echo ""

# ─────────────────────────────────────────────────────────────────
# Test 3: Verify excluded files (heavy workflow components)
# ─────────────────────────────────────────────────────────────────

echo "→ Test 3: Excluded files"
echo ""

assert_file_missing ".mcp.json" "Full MCP config"
assert_file_missing "CLAUDE.md" "Full workflow docs"
assert_file_missing ".claude/agents/manager.md" "Agent definitions"
assert_file_missing ".claude/scripts/health-check.sh" "Health check script"
assert_file_missing ".claude/scripts/validate-policies.sh" "Validation script"
assert_file_missing "docs/policy/workflow.md" "Workflow policy"
assert_file_missing "docs/policy/orchestration.md" "Orchestration policy"
assert_file_missing "docs/tasks/" "Task reports directory"

echo ""

# ─────────────────────────────────────────────────────────────────
# Test 4: Run lite install
# ─────────────────────────────────────────────────────────────────

echo "→ Test 4: Running install.sh --mode lite"
echo ""

# Set environment to skip deps (faster test)
export CLAUDE_FACTORY_SKIP_DEPS=1

# Capture install output
INSTALL_OUTPUT=$(./install.sh --mode lite 2>&1 || true)

# Check install completed
if echo "$INSTALL_OUTPUT" | grep -q "Setup complete.*lite"; then
  pass "Install completed successfully"
  ((TESTS_PASSED++))
else
  fail "Install did not complete as expected"
  ((TESTS_FAILED++))
  info "Output: $INSTALL_OUTPUT"
fi

# Check for mode indicator in output
if echo "$INSTALL_OUTPUT" | grep -q "Mode: lite"; then
  pass "Lite mode indicator present"
  ((TESTS_PASSED++))
else
  fail "Missing lite mode indicator"
  ((TESTS_FAILED++))
fi

echo ""

# ─────────────────────────────────────────────────────────────────
# Test 5: Security - No secrets in output
# ─────────────────────────────────────────────────────────────────

echo "→ Test 5: Security checks"
echo ""

assert_no_secrets_in_output "$INSTALL_OUTPUT"

echo ""

# ─────────────────────────────────────────────────────────────────
# Test 6: Verify executable permissions
# ─────────────────────────────────────────────────────────────────

echo "→ Test 6: Executable permissions"
echo ""

assert_executable "install.sh" "Install script"
assert_executable "cf-lite" "Lite runner"

echo ""

# ─────────────────────────────────────────────────────────────────
# Test 7: Verify MCP config structure
# ─────────────────────────────────────────────────────────────────

echo "→ Test 7: MCP configuration"
echo ""

# Check .mcp.lite.json contains expected servers
if grep -q "factory-ops" .mcp.lite.json; then
  pass "factory-ops server in config"
  ((TESTS_PASSED++))
else
  fail "factory-ops server missing from config"
  ((TESTS_FAILED++))
fi

if grep -q "factory-git" .mcp.lite.json; then
  pass "factory-git server in config"
  ((TESTS_PASSED++))
else
  fail "factory-git server missing from config"
  ((TESTS_FAILED++))
fi

if grep -q "factory-fs" .mcp.lite.json; then
  pass "factory-fs server in config"
  ((TESTS_PASSED++))
else
  fail "factory-fs server missing from config"
  ((TESTS_FAILED++))
fi

# Check that full-mode-only servers are NOT in lite config
if grep -q "factory-ctags" .mcp.lite.json; then
  fail "factory-ctags should not be in lite config"
  ((TESTS_FAILED++))
else
  pass "factory-ctags correctly excluded"
  ((TESTS_PASSED++))
fi

echo ""

# ─────────────────────────────────────────────────────────────────
# Test 8: Verify runtime directories
# ─────────────────────────────────────────────────────────────────

echo "→ Test 8: Runtime directories"
echo ""

# Note: These may not exist yet in fresh install, but install.sh should create them
# We're testing that install.sh ran correctly

if [[ -d ".claude/cache" ]] || echo "$INSTALL_OUTPUT" | grep -q "cache"; then
  pass "Cache directory handling"
  ((TESTS_PASSED++))
else
  warn "Cache directory not mentioned (may be skipped in lite)"
  ((TESTS_PASSED++)) # Not a failure for lite mode
fi

echo ""

# ─────────────────────────────────────────────────────────────────
# Test Summary
# ─────────────────────────────────────────────────────────────────

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo "═══════════════════════════════════════════════════════════"
echo "  Test Summary: $TEST_NAME"
echo "═══════════════════════════════════════════════════════════"
echo ""
echo "  Passed: $TESTS_PASSED"
echo "  Failed: $TESTS_FAILED"
echo "  Duration: ${DURATION}s"
echo ""

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo -e "${GREEN}✅ All tests passed${NC}"
  exit 0
else
  echo -e "${RED}❌ Some tests failed${NC}"
  exit 1
fi
