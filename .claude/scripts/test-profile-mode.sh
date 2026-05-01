#!/usr/bin/env bash
set -euo pipefail

# ╔═══════════════════════════════════════════════════════════════╗
# ║  Test: Behavioral Profile Modes (LIGHT / FULL)                ║
# ║  Validates profile files and mode switching                    ║
# ╚═══════════════════════════════════════════════════════════════╝

TEST_NAME="profile-mode"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m'

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
    fail "$desc missing"
    ((TESTS_FAILED++))
    return 1
  fi
}

assert_contains() {
  local file="$1"
  local pattern="$2"
  local desc="${3:-$file contains $pattern}"
  if grep -q "$pattern" "$file"; then
    pass "$desc"
    ((TESTS_PASSED++))
    return 0
  else
    fail "$desc (pattern not found: $pattern)"
    ((TESTS_FAILED++))
    return 1
  fi
}

assert_header_matches() {
  local file="$1"
  local pattern="$2"
  local desc="${3:-$file header matches $pattern}"
  local header=$(head -1 "$file")
  if echo "$header" | grep -q "$pattern"; then
    pass "$desc"
    ((TESTS_PASSED++))
    return 0
  else
    fail "$desc (header: $header)"
    ((TESTS_FAILED++))
    return 1
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

cd "$REPO_ROOT"

# ─────────────────────────────────────────────────────────────────
# Test 1: Profile files exist
# ─────────────────────────────────────────────────────────────────

echo "→ Test 1: Profile files exist"
echo ""

assert_file_exists "CLAUDE.md" "Main profile (CLAUDE.md)"
assert_file_exists "CLAUDE.light.md" "LIGHT profile"
assert_file_exists "CLAUDE.full.md" "FULL profile"
assert_file_exists "AGENTS.md" "Main OpenCode profile (AGENTS.md)"
assert_file_exists "AGENTS.light.md" "OpenCode LIGHT profile"
assert_file_exists "AGENTS.full.md" "OpenCode FULL profile"
assert_file_exists "opencode.json" "Active OpenCode config"
assert_file_exists ".opencode/router.md" "OpenCode router"
assert_file_exists ".opencode/modes/plan.md" "OpenCode plan mode"
assert_file_exists ".opencode/project.template.yml" "OpenCode project template"

echo ""

# ─────────────────────────────────────────────────────────────────
# Test 2: Profile markers present
# ─────────────────────────────────────────────────────────────────

echo "→ Test 2: Profile markers"
echo ""

assert_contains "CLAUDE.light.md" "LIGHT MODE" "LIGHT profile has marker"
assert_contains "CLAUDE.full.md" "MULTI-AGENT\|AUTONOMOUS" "FULL profile has marker"
assert_contains "AGENTS.light.md" "LIGHT MODE" "OpenCode LIGHT profile has marker"
assert_contains "AGENTS.full.md" "FULL MODE" "OpenCode FULL profile has marker"

echo ""

# ─────────────────────────────────────────────────────────────────
# Test 3: Default mode is LIGHT
# ─────────────────────────────────────────────────────────────────

echo "→ Test 3: Default mode is LIGHT"
echo ""

assert_header_matches "CLAUDE.md" "LIGHT MODE" "CLAUDE.md defaults to LIGHT mode"
assert_header_matches "AGENTS.md" "LIGHT MODE" "AGENTS.md defaults to LIGHT mode"

echo ""

# ─────────────────────────────────────────────────────────────────
# Test 4: Profile switching (simulated)
# ─────────────────────────────────────────────────────────────────

echo "→ Test 4: Profile switching simulation"
echo ""

# Create temp test repo
TEST_DIR=$(mktemp -d)
trap "rm -rf '$TEST_DIR'" EXIT

cp CLAUDE.light.md "$TEST_DIR/"
cp CLAUDE.full.md "$TEST_DIR/"
cp AGENTS.light.md "$TEST_DIR/"
cp AGENTS.full.md "$TEST_DIR/"
cd "$TEST_DIR"

# Simulate switching to LIGHT
cp CLAUDE.light.md CLAUDE.md
if head -1 CLAUDE.md | grep -q "LIGHT MODE"; then
  pass "Switch to LIGHT mode works"
  ((TESTS_PASSED++))
else
  fail "Switch to LIGHT mode failed"
  ((TESTS_FAILED++))
fi

cp AGENTS.light.md AGENTS.md
if head -1 AGENTS.md | grep -q "LIGHT MODE"; then
  pass "OpenCode switch to LIGHT mode works"
  ((TESTS_PASSED++))
else
  fail "OpenCode switch to LIGHT mode failed"
  ((TESTS_FAILED++))
fi

# Simulate switching to FULL
cp CLAUDE.full.md CLAUDE.md
if head -1 CLAUDE.md | grep -q "MULTI-AGENT\|AUTONOMOUS"; then
  pass "Switch to FULL mode works"
  ((TESTS_PASSED++))
else
  fail "Switch to FULL mode failed"
  ((TESTS_FAILED++))
fi

cp AGENTS.full.md AGENTS.md
if head -1 AGENTS.md | grep -q "FULL MODE"; then
  pass "OpenCode switch to FULL mode works"
  ((TESTS_PASSED++))
else
  fail "OpenCode switch to FULL mode failed"
  ((TESTS_FAILED++))
fi

# Return to repo root
cd "$REPO_ROOT"

echo ""

# ─────────────────────────────────────────────────────────────────
# Test 5: LIGHT mode behavioral characteristics
# ─────────────────────────────────────────────────────────────────

echo "→ Test 5: LIGHT mode characteristics"
echo ""

assert_contains "CLAUDE.light.md" "single-pass\|Single-pass" "LIGHT mode mentions single-pass"
assert_contains "CLAUDE.light.md" "token-efficient\|Token-efficient" "LIGHT mode mentions token efficiency"
assert_contains "CLAUDE.light.md" "brief plan\|Brief plan" "LIGHT mode mentions brief planning"

echo ""

# ─────────────────────────────────────────────────────────────────
# Test 6: FULL mode behavioral characteristics
# ─────────────────────────────────────────────────────────────────

echo "→ Test 6: FULL mode characteristics"
echo ""

assert_contains "CLAUDE.full.md" "multi-phase\|Multi-phase\|MANAGER" "FULL mode mentions multi-phase"
assert_contains "CLAUDE.full.md" "agent\|Agent" "FULL mode mentions agents"
assert_contains "CLAUDE.full.md" "Analyst\|Researcher\|Architect" "FULL mode has agent pipeline"

echo ""

# ─────────────────────────────────────────────────────────────────
# Test 7: Zsh helper includes cfmode
# ─────────────────────────────────────────────────────────────────

echo "→ Test 7: Zsh helper includes cfmode"
echo ""

if [[ -f ".zsh/claude-factory-helpers.zsh" ]]; then
  assert_contains ".zsh/claude-factory-helpers.zsh" "cfmode" "Zsh helpers include cfmode function"
  assert_contains ".zsh/claude-factory-helpers.zsh" "cfmode light" "cfmode supports light mode"
  assert_contains ".zsh/claude-factory-helpers.zsh" "cfmode full" "cfmode supports full mode"
else
  warn "Zsh helpers not found (optional)"
  ((TESTS_PASSED++)) # Not a failure
fi

echo ""

# ─────────────────────────────────────────────────────────────────
# Test 8: Documentation updated
# ─────────────────────────────────────────────────────────────────

echo "→ Test 8: Documentation"
echo ""

if [[ -f "docs/INSTALL.md" ]]; then
  assert_contains "docs/INSTALL.md" "LIGHT\|Behavioral.*Mode" "INSTALL.md documents modes"
else
  warn "INSTALL.md not found"
  ((TESTS_PASSED++)) # Not a failure
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
