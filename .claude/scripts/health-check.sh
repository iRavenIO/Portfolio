#!/usr/bin/env bash
set -Eeuo pipefail

# Determine repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load shared libraries
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/env.sh"

# Load environment
_load_env_claude

# ╔═══════════════════════════════════════════════════════════════╗
# ║  🏥 Claude Factory — health-check.sh                          ║
# ║  Validate factory environment and dependencies                ║
# ╚═══════════════════════════════════════════════════════════════╝

say "╔═══════════════════════════════════════════════════════════════════════╗"
say "║  🏥 Claude Factory — Health Check                                    ║"
say "╚═══════════════════════════════════════════════════════════════════════╝"
say ""

EXIT_CODE=0
WARN_COUNT=0

# 1. Git
say "🔎 Checking git..."
if have git; then
  say "  ✅ git: $(git --version)"
else
  err "  ❌ git not found"
  EXIT_CODE=1
fi
say ""

# 2. Node.js and npm
say "🔎 Checking Node.js and npm..."
if have node; then
  say "  ✅ node: $(node --version)"
else
  err "  ❌ node not found"
  EXIT_CODE=1
fi

if have npm; then
  say "  ✅ npm: $(npm --version)"
else
  err "  ❌ npm not found"
  EXIT_CODE=1
fi
say ""

# 3. MCP dependencies
say "🔎 Checking MCP dependencies..."
if [[ -d ".claude/mcp/node_modules" ]]; then
  say "  ✅ MCP node_modules exists"
else
  warn "  ⚠️  MCP node_modules missing — run: cd .claude/mcp && npm install"
  EXIT_CODE=1
fi
say ""

# 4. ripgrep (rg)
say "🔎 Checking ripgrep..."
if have rg; then
  say "  ✅ rg: $(rg --version | head -n1)"
else
  warn "  ⚠️  rg (ripgrep) not found — install via: brew install ripgrep"
  EXIT_CODE=1
fi
say ""

# 5. Universal Ctags
say "🔎 Checking ctags..."
CTAGS_BIN="$(resolve_ctags 2>/dev/null || true)"
if [[ -n "$CTAGS_BIN" ]]; then
  CTAGS_VERSION=$($CTAGS_BIN --version 2>&1 | head -n1 || echo "unknown")
  if echo "$CTAGS_VERSION" | grep -qi "universal"; then
    say "  ✅ ctags (Universal): $CTAGS_VERSION"
  else
    warn "  ⚠️  ctags found but NOT Universal Ctags: $CTAGS_VERSION"
    warn "     Install Universal Ctags via: brew install universal-ctags"
    EXIT_CODE=1
  fi
else
  err "  ❌ ctags not found — install via: brew install universal-ctags"
  EXIT_CODE=1
fi
say ""

# 6. gemini (for research_search_web) [OPTIONAL]
say "🔎 Checking gemini (optional)..."
if have gemini; then
  # Try to run gemini -p to verify non-interactive execution works
  if gemini -p "hi" >/dev/null 2>&1; then
    say "  ✅ gemini -p command verified"
  else
    warn "  ⚠️  gemini found but failed to run — may require setup"
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
else
  warn "  ⚠️  gemini not found — Researcher agent web search will be unavailable"
  warn "     Install via: npm install -g @google/genai-for-devs"
  WARN_COUNT=$((WARN_COUNT + 1))
fi
say ""

# 7. macOS say command (for notify_say) [OPTIONAL]
say "🔎 Checking macOS say command (optional)..."
if [[ -x /usr/bin/say ]]; then
  say "  ✅ say (macOS voice)"
else
  warn "  ⚠️  say command not found — notification audio will not work"
  warn "     (This is expected on Linux; macOS-only feature)"
  WARN_COUNT=$((WARN_COUNT + 1))
fi
say ""

# 8. Tags file
say "🔎 Checking tags index..."
if [[ -f "tags" ]]; then
  TAG_COUNT=$(wc -l < tags | tr -d ' ')
  if [[ "$TAG_COUNT" -le 1 ]]; then
    warn "  ⚠️  tags file exists but appears empty ($TAG_COUNT lines) — re-run: ./install.sh"
    EXIT_CODE=1
  else
    say "  ✅ tags file exists ($TAG_COUNT lines)"
  fi
else
  warn "  ⚠️  tags file missing — run: ./install.sh"
  EXIT_CODE=1
fi
say ""

# 9. .claude/index-state.json
say "🔎 Checking index state..."
if [[ -f ".claude/index-state.json" ]]; then
  say "  ✅ .claude/index-state.json exists"
else
  warn "  ⚠️  .claude/index-state.json missing (will be created on first ctags run)"
fi
say ""

# 10. Policy files
say "🔎 Checking policy files..."
POLICY_FILES=(
  "docs/policy/orchestration.md"
  "docs/policy/build.md"
  "docs/policy/agents.md"
  "docs/policy/quota.md"
  "docs/policy/workflow.md"
  "docs/policy/spawn-templates.md"
  "docs/policy/critical-rules.md"
  "docs/policy/failure-recovery.md"
  "docs/policy/task-modes.md"
  "docs/policy/git-automation.md"
  "docs/policy/mcp-security.md"
  "docs/policy/observability.md"
)

MISSING_POLICY=0
for policy in "${POLICY_FILES[@]}"; do
  if [[ -f "$policy" ]]; then
    say "  ✅ $policy"
  else
    err "  ❌ $policy missing"
    MISSING_POLICY=1
  fi
done

if [[ "$MISSING_POLICY" -eq 1 ]]; then
  EXIT_CODE=1
fi
say ""

# 11. Agent files
say "🔎 Checking agent files..."
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
  if [[ -f "$agent" ]]; then
    say "  ✅ $agent"
  else
    err "  ❌ $agent missing"
    MISSING_AGENT=1
  fi
done

if [[ "$MISSING_AGENT" -eq 1 ]]; then
  EXIT_CODE=1
fi
say ""

# 12. MCP server files
say "🔎 Checking MCP server files..."
MCP_SERVERS=(
  ".claude/mcp/server.js"
  ".claude/mcp/server-ctags.js"
  ".claude/mcp/server-rg.js"
  ".claude/mcp/server-fs.js"
  ".claude/mcp/server-git.js"
  ".claude/mcp/server-query.js"
  ".claude/mcp/package.json"
)

MISSING_MCP=0
for mcp in "${MCP_SERVERS[@]}"; do
  if [[ -f "$mcp" ]]; then
    say "  ✅ $mcp"
  else
    err "  ❌ $mcp missing"
    MISSING_MCP=1
  fi
done

if [[ "$MISSING_MCP" -eq 1 ]]; then
  EXIT_CODE=1
fi
say ""

# 13. cf runner script
say "🔎 Checking cf runner script..."
if [[ -f "cf" ]]; then
  if [[ -x "cf" ]]; then
    say "  ✅ cf runner script exists and is executable"
  else
    warn "  ⚠️  cf exists but is not executable (run: chmod +x cf)"
    EXIT_CODE=1
  fi
else
  warn "  ⚠️  cf runner script missing (enhanced logging will be unavailable)"
  WARN_COUNT=$((WARN_COUNT + 1))
fi
say ""

# 14. SQLite (for cache system)
say "🔎 Checking SQLite..."
if have sqlite3; then
  SQLITE_VERSION=$(sqlite3 --version | awk '{print $1}')
  say "  ✅ sqlite3: $SQLITE_VERSION"
else
  warn "  ⚠️  sqlite3 not found — cache system will be unavailable"
  warn "     Install via: brew install sqlite3"
  WARN_COUNT=$((WARN_COUNT + 1))
fi
say ""

# 15. Redis (optional, for cache hot-path acceleration)
say "🔎 Checking Redis (optional)..."
if have redis-cli; then
  if redis-cli PING >/dev/null 2>&1; then
    say "  ✅ redis-cli: connected"
  else
    warn "  ⚠️  redis-cli found but Redis server not running"
    warn "     Cache will use SQLite only (performance degradation)"
    WARN_COUNT=$((WARN_COUNT + 1))
  fi
else
  warn "  ⚠️  redis-cli not found — cache will use SQLite only"
  warn "     Install via: brew install redis && brew services start redis"
  WARN_COUNT=$((WARN_COUNT + 1))
fi
say ""

# 16. Cache system integrity
say "🔎 Checking cache system..."
if [[ -d ".claude/cache" ]]; then
  say "  ✅ .claude/cache directory exists"

  if [[ -f ".claude/cache/cache.db" ]]; then
    # Test SQLite DB integrity
    if sqlite3 ".claude/cache/cache.db" "PRAGMA integrity_check;" | grep -q "ok"; then
      say "  ✅ Cache database is healthy"
    else
      warn "  ⚠️  Cache database is corrupted — will be regenerated"
      WARN_COUNT=$((WARN_COUNT + 1))
    fi
  else
    say "  ℹ️  Cache database not yet initialized (will be created on first use)"
  fi
else
  say "  ℹ️  Cache directory not yet created (will be initialized on first use)"
fi
say ""

# Summary
say "════════════════════════════════════════════════════════════════════════"
if [[ "$EXIT_CODE" -eq 0 && "$WARN_COUNT" -eq 0 ]]; then
  say "✅ All checks passed — factory is healthy!"
elif [[ "$EXIT_CODE" -eq 0 && "$WARN_COUNT" -gt 0 ]]; then
  warn "⚠️  All required checks passed, but $WARN_COUNT optional tool(s) missing"
  warn "   The factory will work, but some agent features may be unavailable."
  say "✅ Factory is operational (with warnings)."
else
  err "❌ Some required checks failed — see errors above"
fi
say "════════════════════════════════════════════════════════════════════════"

exit "$EXIT_CODE"
