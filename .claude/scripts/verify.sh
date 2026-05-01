#!/usr/bin/env bash
set -Eeuo pipefail

# ╔═══════════════════════════════════════════════════════════════╗
# ║  ✓ Claude Factory — verify.sh                                 ║
# ║  One-command verification with 4 modes                         ║
# ╚═══════════════════════════════════════════════════════════════╝
#
# Usage:
#   verify.sh [MODE]
#
# Modes:
#   quick (default)  — 7 critical checks, <3 seconds
#   full             — delegates to health-check.sh + validate-policies.sh
#   smoke            — 4 operational tests (MCP servers, ctags, rg, cache)
#   test             — delegates to test-install.sh (if exists)
#

# Resolve repo root
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd )"
cd "$REPO_ROOT"

# Load shared library
source "$SCRIPT_DIR/lib/common.sh"

usage() {
  cat <<EOF
Usage: verify.sh [MODE]

Modes:
  quick (default)  — 7 critical checks, <3 seconds
  full             — delegates to health-check.sh + validate-policies.sh
  smoke            — 4 operational tests (MCP servers, ctags, rg, cache)
  test             — delegates to test-install.sh (if exists)

Examples:
  verify.sh              # quick mode
  verify.sh full         # full health check
  verify.sh smoke        # operational smoke tests
  verify.sh test         # run test suite

Exit codes:
  0 — all checks passed
  1 — one or more checks failed
EOF
  exit 0
}

# Parse mode
MODE="${1:-quick}"

if [[ "$MODE" == "--help" || "$MODE" == "-h" ]]; then
  usage
fi

# ═════════════════════════════════════════════════════════════════
# MODE: full — delegate to health-check.sh + validate-policies.sh
# ═════════════════════════════════════════════════════════════════
if [[ "$MODE" == "full" ]]; then
  say "════════════════════════════════════════════════════════════════════════"
  say "Running full verification (health-check + validate-policies)..."
  say "════════════════════════════════════════════════════════════════════════"
  say ""

  EXIT_CODE=0

  # Run health-check.sh
  if [[ -f ".claude/scripts/health-check.sh" ]]; then
    if bash ".claude/scripts/health-check.sh"; then
      say ""
      say "PASS: health-check.sh completed successfully"
    else
      err "health-check.sh failed"
      EXIT_CODE=1
    fi
  else
    err ".claude/scripts/health-check.sh not found"
    EXIT_CODE=1
  fi

  say ""

  # Run validate-policies.sh
  if [[ -f ".claude/scripts/validate-policies.sh" ]]; then
    if bash ".claude/scripts/validate-policies.sh"; then
      say ""
      say "PASS: validate-policies.sh completed successfully"
    else
      err "validate-policies.sh failed"
      EXIT_CODE=1
    fi
  else
    err ".claude/scripts/validate-policies.sh not found"
    EXIT_CODE=1
  fi

  say ""
  say "════════════════════════════════════════════════════════════════════════"
  if [[ "$EXIT_CODE" -eq 0 ]]; then
    say "✅ Full verification PASSED"
  else
    say "❌ Full verification FAILED"
  fi
  say "════════════════════════════════════════════════════════════════════════"

  exit "$EXIT_CODE"
fi

# ═════════════════════════════════════════════════════════════════
# MODE: test — delegate to test-install.sh
# ═════════════════════════════════════════════════════════════════
if [[ "$MODE" == "test" ]]; then
  say "════════════════════════════════════════════════════════════════════════"
  say "Running test suite (test-install.sh)..."
  say "════════════════════════════════════════════════════════════════════════"
  say ""

  if [[ -f ".claude/scripts/test-install.sh" ]]; then
    if bash ".claude/scripts/test-install.sh"; then
      say ""
      say "════════════════════════════════════════════════════════════════════════"
      say "✅ Test suite PASSED"
      say "════════════════════════════════════════════════════════════════════════"
      exit 0
    else
      say ""
      say "════════════════════════════════════════════════════════════════════════"
      say "❌ Test suite FAILED"
      say "════════════════════════════════════════════════════════════════════════"
      exit 1
    fi
  else
    err ".claude/scripts/test-install.sh not found"
    say "   Remediation: test-install.sh is not yet implemented"
    exit 1
  fi
fi

# ═════════════════════════════════════════════════════════════════
# MODE: smoke — 4 operational tests
# ═════════════════════════════════════════════════════════════════
if [[ "$MODE" == "smoke" ]]; then
  say "════════════════════════════════════════════════════════════════════════"
  say "Running smoke tests (4 operational checks)..."
  say "════════════════════════════════════════════════════════════════════════"
  say ""

  EXIT_CODE=0

  # Test 1: Node can load MCP server module
  say "[1/4] Testing Node.js can load MCP server module..."
  if [[ -f ".claude/mcp/server.js" ]]; then
    if node -e "require('./.claude/mcp/server.js')" 2>/dev/null; then
      say "PASS: Node.js can load .claude/mcp/server.js"
    else
      err "Node.js failed to load .claude/mcp/server.js"
      say "   Remediation: check Node.js version and MCP dependencies (cd .claude/mcp && npm install)"
      EXIT_CODE=1
    fi
  else
    err ".claude/mcp/server.js not found"
    say "   Remediation: restore server.js from factory template"
    EXIT_CODE=1
  fi
  say ""

  # Test 2: ctags is available (Universal Ctags)
  say "[2/4] Testing ctags (Universal Ctags)..."
  if have ctags; then
    CTAGS_VERSION=$(ctags --version 2>&1 | head -n1 || echo "unknown")
    if echo "$CTAGS_VERSION" | grep -qi "universal"; then
      say "PASS: Universal Ctags available ($CTAGS_VERSION)"
    else
      err "ctags found but NOT Universal Ctags: $CTAGS_VERSION"
      say "   Remediation: install Universal Ctags via: brew install universal-ctags"
      EXIT_CODE=1
    fi
  else
    err "ctags not found"
    say "   Remediation: install Universal Ctags via: brew install universal-ctags"
    EXIT_CODE=1
  fi
  say ""

  # Test 3: ripgrep is available
  say "[3/4] Testing ripgrep (rg)..."
  if have rg; then
    RG_VERSION=$(rg --version | head -n1)
    say "PASS: ripgrep available ($RG_VERSION)"
  else
    err "ripgrep (rg) not found"
    say "   Remediation: install ripgrep via: brew install ripgrep"
    EXIT_CODE=1
  fi
  say ""

  # Test 4: SQLite cache DB is accessible (if exists)
  say "[4/4] Testing SQLite cache database..."
  if [[ -f ".claude/cache/cache.db" ]]; then
    if have sqlite3; then
      if sqlite3 ".claude/cache/cache.db" "PRAGMA integrity_check;" | grep -q "ok"; then
        say "PASS: Cache database is healthy and accessible"
      else
        err "Cache database exists but is corrupted"
        say "   Remediation: remove .claude/cache/cache.db (will be regenerated)"
        EXIT_CODE=1
      fi
    else
      err "sqlite3 command not found (cannot verify cache)"
      say "   Remediation: install sqlite3 via: brew install sqlite3"
      EXIT_CODE=1
    fi
  else
    say "PASS: Cache database not yet created (will be initialized on first use)"
  fi
  say ""

  say "════════════════════════════════════════════════════════════════════════"
  if [[ "$EXIT_CODE" -eq 0 ]]; then
    say "✅ Smoke tests PASSED"
  else
    say "❌ Smoke tests FAILED"
  fi
  say "════════════════════════════════════════════════════════════════════════"

  exit "$EXIT_CODE"
fi

# ═════════════════════════════════════════════════════════════════
# MODE: quick (default) — 7 critical checks
# ═════════════════════════════════════════════════════════════════
if [[ "$MODE" == "quick" ]]; then
  say "════════════════════════════════════════════════════════════════════════"
  say "Running quick verification (7 critical checks)..."
  say "════════════════════════════════════════════════════════════════════════"
  say ""

  EXIT_CODE=0

  # Check 1: Git repo detected
  say "[1/7] Checking git repository..."
  if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    say "PASS: Git repository detected"
  else
    err "Not a git repository"
    say "   Remediation: run 'git init' or clone from existing repo"
    EXIT_CODE=1
  fi
  say ""

  # Check 2: Node.js available
  say "[2/7] Checking Node.js..."
  if have node; then
    NODE_VERSION=$(node --version)
    say "PASS: Node.js available ($NODE_VERSION)"
  else
    err "Node.js not found"
    say "   Remediation: install Node.js via: brew install node (or nvm/volta)"
    EXIT_CODE=1
  fi
  say ""

  # Check 3: MCP dependencies installed
  say "[3/7] Checking MCP dependencies..."
  if [[ -d ".claude/mcp/node_modules" ]]; then
    say "PASS: MCP node_modules exists"
  else
    err "MCP node_modules missing"
    say "   Remediation: cd .claude/mcp && npm install"
    EXIT_CODE=1
  fi
  say ""

  # Check 4: All 6 MCP server files present
  say "[4/7] Checking MCP server files..."
  MCP_SERVERS=(
    ".claude/mcp/server.js"
    ".claude/mcp/server-ctags.js"
    ".claude/mcp/server-rg.js"
    ".claude/mcp/server-fs.js"
    ".claude/mcp/server-git.js"
    ".claude/mcp/server-query.js"
  )

  MISSING_MCP=0
  for mcp in "${MCP_SERVERS[@]}"; do
    if [[ ! -f "$mcp" ]]; then
      err "$mcp missing"
      MISSING_MCP=1
    fi
  done

  if [[ "$MISSING_MCP" -eq 0 ]]; then
    say "PASS: All 6 MCP server files present"
  else
    say "   Remediation: restore missing MCP server files from factory template"
    EXIT_CODE=1
  fi
  say ""

  # Check 5: All 8 agent files present
  say "[5/7] Checking agent files..."
  AGENT_FILES=(
    ".claude/agents/analyst.md"
    ".claude/agents/researcher.md"
    ".claude/agents/architect.md"
    ".claude/agents/developer.md"
    ".claude/agents/reviewer.md"
    ".claude/agents/tester.md"
    ".claude/agents/reporter.md"
    ".claude/agents/reader.md"
  )

  MISSING_AGENT=0
  for agent in "${AGENT_FILES[@]}"; do
    if [[ ! -f "$agent" ]]; then
      err "$agent missing"
      MISSING_AGENT=1
    fi
  done

  if [[ "$MISSING_AGENT" -eq 0 ]]; then
    say "PASS: All 8 agent files present"
  else
    say "   Remediation: restore missing agent files from factory template"
    EXIT_CODE=1
  fi
  say ""

  # Check 6: Policy directory exists with >=12 files
  say "[6/7] Checking policy files..."
  if [[ -d "docs/policy" ]]; then
    POLICY_COUNT=$(find "docs/policy" -type f -name "*.md" | wc -l | tr -d ' ')
    if [[ "$POLICY_COUNT" -ge 12 ]]; then
      say "PASS: Policy directory exists with $POLICY_COUNT files"
    else
      err "Policy directory has only $POLICY_COUNT files (expected >=12)"
      say "   Remediation: restore missing policy files from factory template"
      EXIT_CODE=1
    fi
  else
    err "docs/policy directory not found"
    say "   Remediation: restore docs/policy directory from factory template"
    EXIT_CODE=1
  fi
  say ""

  # Check 7: Tags file exists and is non-empty
  say "[7/7] Checking tags index..."
  if [[ -f "tags" ]]; then
    TAG_COUNT=$(wc -l < tags | tr -d ' ')
    if [[ "$TAG_COUNT" -gt 1 ]]; then
      say "PASS: Tags file exists and is non-empty ($TAG_COUNT lines)"
    else
      err "Tags file exists but appears empty ($TAG_COUNT lines)"
      say "   Remediation: run ./install.sh to regenerate tags"
      EXIT_CODE=1
    fi
  else
    err "Tags file missing"
    say "   Remediation: run ./install.sh to generate tags"
    EXIT_CODE=1
  fi
  say ""

  say "════════════════════════════════════════════════════════════════════════"
  if [[ "$EXIT_CODE" -eq 0 ]]; then
    say "✅ Quick verification PASSED — factory is ready"
  else
    say "❌ Quick verification FAILED — see errors above"
  fi
  say "════════════════════════════════════════════════════════════════════════"

  exit "$EXIT_CODE"
fi

# Unknown mode
err "Unknown mode: $MODE"
say "   Valid modes: quick, full, smoke, test"
say "   Run 'verify.sh --help' for usage"
exit 1
