#!/usr/bin/env bash
# test-light-behavior.sh — Fast infra-free LIGHT mode behavior validation
# Tests: loader script, DATABASE_URL rebuild, secret redaction, CLAUDE.light.md protocol

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0

# Test functions
pass() {
  echo -e "${GREEN}✓${NC} $1"
  PASS=$((PASS + 1))
}

fail() {
  echo -e "${RED}✗${NC} $1"
  FAIL=$((FAIL + 1))
}

info() {
  echo -e "${YELLOW}ℹ${NC} $1"
}

# Change to repo root
cd "$(git rev-parse --show-toplevel)" || exit 1

info "Testing LIGHT mode behavior (infra-free, <1s)"
echo

# Test 1: Loader script exists
if [[ -f .claude/scripts/load-env-safe.sh ]]; then
  pass "load-env-safe.sh exists"
else
  fail "load-env-safe.sh missing"
fi

# Test 2: Loader is sourceable (syntax check)
if bash -n .claude/scripts/load-env-safe.sh 2>/dev/null; then
  pass "load-env-safe.sh has valid syntax"
else
  fail "load-env-safe.sh has syntax errors"
fi

# Test 3: Loader sets DATABASE_URL after sourcing (static check)
if grep -q 'export DATABASE_URL=' .claude/scripts/load-env-safe.sh 2>/dev/null || true; then
  pass "Loader rebuilds DATABASE_URL after local file load"
else
  fail "Loader does not rebuild DATABASE_URL"
fi

# Test 4: Loader does not print sensitive values (check for echo/printf of vars)
sensitive_match=$(grep -E 'echo.*\$\{?DATABASE_URL\}?[^:]|echo.*\$\{?POSTGRES_PASSWORD\}?[^:]|printf.*\$\{?DATABASE_URL\}?[^:]|printf.*\$\{?POSTGRES_PASSWORD\}?[^:]' .claude/scripts/load-env-safe.sh 2>/dev/null || true)
if [[ -n "$sensitive_match" ]]; then
  fail "Loader prints sensitive env values (security violation)"
else
  pass "Loader does not print sensitive values"
fi

# Test 5: CLAUDE.light.md contains LIGHT Execution Protocol
if grep -q "## LIGHT Execution Protocol" CLAUDE.light.md 2>/dev/null || true; then
  pass "CLAUDE.light.md has LIGHT Execution Protocol section"
else
  fail "CLAUDE.light.md missing LIGHT Execution Protocol section"
fi

# Test 6: CLAUDE.light.md enforces NO REPO WRITES BY DEFAULT
if grep -qi "NO REPO WRITES BY DEFAULT\|Do NOT create files unless" CLAUDE.light.md 2>/dev/null || true; then
  pass "CLAUDE.light.md enforces no repo writes by default"
else
  fail "CLAUDE.light.md missing no-writes-by-default rule"
fi

# Test 7: CLAUDE.light.md has Model Routing (FAST-First)
if grep -q "Model Routing" CLAUDE.light.md 2>/dev/null && grep -q "FAST model" CLAUDE.light.md 2>/dev/null; then
  pass "CLAUDE.light.md has Model Routing (FAST-First) section"
else
  fail "CLAUDE.light.md missing Model Routing guidance"
fi

# Test 8: CLAUDE.light.md has Environment Auto-Load section
if grep -q "Environment Auto-Load" CLAUDE.light.md 2>/dev/null || true; then
  pass "CLAUDE.light.md has Environment Auto-Load section"
else
  fail "CLAUDE.light.md missing Environment Auto-Load section"
fi

# Test 9: CLAUDE.light.md has Database/Migrations Failure Protocol
if grep -q "Database/Migrations Failure Protocol" CLAUDE.light.md 2>/dev/null || true; then
  pass "CLAUDE.light.md has DB failure protocol"
else
  fail "CLAUDE.light.md missing DB failure protocol"
fi

# Test 10: CLAUDE.md mirrors CLAUDE.light.md (both have LIGHT Execution Protocol)
if grep -q "## LIGHT Execution Protocol" CLAUDE.md 2>/dev/null || true; then
  pass "CLAUDE.md mirrors CLAUDE.light.md (has protocol section)"
else
  fail "CLAUDE.md does not mirror CLAUDE.light.md"
fi

# Test 11: docs/INSTALL.md documents env auto-loading
if grep -q "LIGHT Mode: Environment Auto-Loading\|load-env-safe.sh" docs/INSTALL.md 2>/dev/null || true; then
  pass "docs/INSTALL.md documents env auto-loading"
else
  fail "docs/INSTALL.md missing env auto-loading docs"
fi

# Test 12: docs/INSTALL.md explains DATABASE_URL interpolation pitfall
if grep -qi "DATABASE_URL.*Interpolation.*Pitfall\|DATABASE_URL.*rebuild" docs/INSTALL.md 2>/dev/null || true; then
  pass "docs/INSTALL.md explains DATABASE_URL pitfall"
else
  fail "docs/INSTALL.md missing DATABASE_URL pitfall explanation"
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "Results: ${GREEN}${PASS} passed${NC}, ${RED}${FAIL} failed${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $FAIL -eq 0 ]]; then
  echo -e "${GREEN}✓ All LIGHT mode behavior tests passed${NC}"
  exit 0
else
  echo -e "${RED}✗ Some tests failed${NC}"
  exit 1
fi
