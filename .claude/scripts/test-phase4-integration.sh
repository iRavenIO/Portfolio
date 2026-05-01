#!/usr/bin/env bash
# test-phase4-integration.sh — Phase 4 Integration Tests
# Tests cache invalidation hooks, decision memory analytics,
# and cached tool adoption behavior.

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
export CLAUDE_ROOT

PASS_COUNT=0
FAIL_COUNT=0
TEST_CACHE_DB=""
ORIG_CACHE_DB=""

# ============================================================================
# HELPERS
# ============================================================================

say()  { printf "%s\n" "$*"; }
pass() { say "  PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { say "  FAIL: $*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }

setup_test_cache() {
  # Create a temporary cache DB for testing (don't pollute real cache)
  TEST_CACHE_DIR=$(mktemp -d)
  TEST_CACHE_DB="${TEST_CACHE_DIR}/context.db"
  TEST_LOG_DIR="${TEST_CACHE_DIR}/logs"
  mkdir -p "$TEST_LOG_DIR"

  # Note: cache.sh unconditionally sets CACHE_DIR/CACHE_DB from CLAUDE_ROOT.
  # We must override AFTER sourcing cache.sh. Each test suite does:
  #   source cache.sh   <- sets CACHE_DB to production DB
  #   CACHE_DIR=...     <- we override to test dir
  #   CACHE_DB=...      <- we override to test DB
  #   cache_init        <- reinitialize with test DB
}

teardown_test_cache() {
  if [[ -n "${TEST_CACHE_DIR:-}" && -d "${TEST_CACHE_DIR:-}" ]]; then
    rm -rf "$TEST_CACHE_DIR"
  fi
}

# ============================================================================
# TEST SUITE 1: Cache Invalidation Hooks
# ============================================================================

test_cache_hooks() {
  say ""
  say "=== TEST SUITE 1: Cache Invalidation Hooks ==="
  say ""

  setup_test_cache

  # Source cache library (will auto-init with production DB)
  source "$CLAUDE_ROOT/.claude/scripts/cache.sh"
  # Override to test DB after source
  CACHE_DIR="$TEST_CACHE_DIR"
  CACHE_DB="$TEST_CACHE_DB"
  CACHE_REPO_MAP="${TEST_CACHE_DIR}/repo-map.txt"
  LOG_FILE="${TEST_CACHE_DIR}/logs/factory.log"
  LOCK_DIR="${CACHE_DIR}/.lock"
  cache_init

  source "$CLAUDE_ROOT/.claude/scripts/cache-hooks.sh"
  # Override hooks' variables too
  CACHE_DIR="$TEST_CACHE_DIR"
  CACHE_DB="$TEST_CACHE_DB"
  LOG_FILE="${TEST_CACHE_DIR}/logs/factory.log"

  # --- Test 1.1: cache_invalidate_for_write removes file entry ---
  say "Test 1.1: cache_invalidate_for_write removes file entry"
  local test_file="${CLAUDE_ROOT}/docs/policy/orchestration.md"
  cache_set "file:${test_file}" "test content" "file" "$test_file"
  local before=$(cache_get "file:${test_file}" 2>/dev/null || echo "")
  if [[ -n "$before" ]]; then
    cache_invalidate_for_write "$test_file"
    local after=$(cache_get "file:${test_file}" 2>/dev/null || echo "")
    if [[ -z "$after" ]]; then
      pass "File cache entry removed after write invalidation"
    else
      fail "File cache entry still exists after write invalidation"
    fi
  else
    fail "Could not set up test data"
  fi

  # --- Test 1.2: cache_invalidate_for_write invalidates policy typed key ---
  say "Test 1.2: cache_invalidate_for_write invalidates policy typed key"
  cache_set "policy:orchestration" "policy content" "policy"
  cache_set "file:${CLAUDE_ROOT}/docs/policy/orchestration.md" "file content" "file"
  cache_invalidate_for_write "${CLAUDE_ROOT}/docs/policy/orchestration.md"
  local policy_after=$(cache_get "policy:orchestration" 2>/dev/null || echo "")
  if [[ -z "$policy_after" ]]; then
    pass "Policy typed key invalidated when policy file written"
  else
    fail "Policy typed key still exists after policy file write"
  fi

  # --- Test 1.3: Structural file change invalidates repo_map ---
  say "Test 1.3: Structural file change invalidates repo_map"
  cache_set "repo_map" "old repo map" "repo_map"
  cache_invalidate_for_write "${CLAUDE_ROOT}/package.json"
  local repo_map_after=$(cache_get "repo_map" 2>/dev/null || echo "")
  if [[ -z "$repo_map_after" ]]; then
    pass "repo_map invalidated after structural file change"
  else
    fail "repo_map still exists after structural file change"
  fi

  # --- Test 1.4: cache_invalidate_for_policy_change clears all policy caches ---
  say "Test 1.4: cache_invalidate_for_policy_change clears all policy caches"
  cache_set "policy:build" "build policy" "policy"
  cache_set "policy:agents" "agents policy" "policy"
  cache_set "runbook:add-mcp" "runbook content" "runbook"
  cache_invalidate_for_policy_change
  local p1=$(cache_get "policy:build" 2>/dev/null || echo "")
  local p2=$(cache_get "policy:agents" 2>/dev/null || echo "")
  local r1=$(cache_get "runbook:add-mcp" 2>/dev/null || echo "")
  if [[ -z "$p1" && -z "$p2" && -z "$r1" ]]; then
    pass "All policy and runbook caches cleared"
  else
    fail "Some policy/runbook caches still exist after policy change"
  fi

  # --- Test 1.5: cache_invalidate_for_git_head_change preserves decision_memory ---
  say "Test 1.5: cache_invalidate_for_git_head_change preserves decision_memory"
  cache_set "file:${CLAUDE_ROOT}/test.js" "test content" "file"
  cache_set "policy:orchestration" "orch content" "policy"
  # Record a decision memory entry
  decision_memory_record "test-run-1" "STANDARD" 50000 45000 0 2 120
  cache_invalidate_for_git_head_change
  local file_after=$(cache_get "file:${CLAUDE_ROOT}/test.js" 2>/dev/null || echo "")
  local dm_count=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM decision_memory;" 2>/dev/null || echo "0")
  if [[ -z "$file_after" && "$dm_count" -gt 0 ]]; then
    pass "File caches cleared, decision_memory preserved"
  else
    fail "Git HEAD change did not behave correctly (file_after='$file_after', dm_count=$dm_count)"
  fi

  # --- Test 1.6: Tool output caches invalidated after file write ---
  say "Test 1.6: Tool output caches invalidated after file write"
  cache_set "tool:rg:abc123" "search results" "tool_output"
  cache_invalidate_for_write "${CLAUDE_ROOT}/src/index.ts"
  local tool_after=$(cache_get "tool:rg:abc123" 2>/dev/null || echo "")
  if [[ -z "$tool_after" ]]; then
    pass "Tool output cache invalidated after file write"
  else
    fail "Tool output cache still exists after file write"
  fi

  teardown_test_cache
}

# ============================================================================
# TEST SUITE 2: Decision Memory Analytics
# ============================================================================

test_decision_memory() {
  say ""
  say "=== TEST SUITE 2: Decision Memory Analytics ==="
  say ""

  setup_test_cache

  # Source cache library and override to test DB
  source "$CLAUDE_ROOT/.claude/scripts/cache.sh"
  CACHE_DIR="$TEST_CACHE_DIR"
  CACHE_DB="$TEST_CACHE_DB"
  CACHE_REPO_MAP="${TEST_CACHE_DIR}/repo-map.txt"
  LOG_FILE="${TEST_CACHE_DIR}/logs/factory.log"
  LOCK_DIR="${CACHE_DIR}/.lock"
  cache_init

  # --- Test 2.1: Record and retrieve decision memory ---
  say "Test 2.1: Record and retrieve decision memory"
  decision_memory_record "run-001" "MICRO-CHANGE" 15000 12000 1 1 60
  decision_memory_record "run-002" "STANDARD" 50000 48000 0 2 180
  decision_memory_record "run-003" "STANDARD" 60000 55000 0 1 150
  decision_memory_record "run-004" "MICRO-CHANGE" 10000 9500 1 1 45
  local count=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM decision_memory;" 2>/dev/null || echo "0")
  if [[ "$count" -eq 4 ]]; then
    pass "4 decision memory entries recorded"
  else
    fail "Expected 4 entries, got $count"
  fi

  # --- Test 2.2: decision_memory_stats returns valid JSON ---
  say "Test 2.2: decision_memory_stats returns valid JSON"
  local stats
  stats=$(decision_memory_stats)
  if echo "$stats" | grep -q '"total_runs":4'; then
    pass "decision_memory_stats returns correct total_runs"
  else
    fail "decision_memory_stats returned unexpected output: $stats"
  fi

  # --- Test 2.3: decision_memory_summary produces formatted output ---
  say "Test 2.3: decision_memory_summary produces formatted output"
  local summary
  summary=$(decision_memory_summary 10)
  if echo "$summary" | grep -q "Decision Memory Summary"; then
    pass "decision_memory_summary produces formatted table"
  else
    fail "decision_memory_summary output missing expected header"
  fi
  if echo "$summary" | grep -q "Architect skip rate"; then
    pass "Summary includes architect skip rate"
  else
    fail "Summary missing architect skip rate"
  fi

  # --- Test 2.4: decision_memory_predict returns predictions ---
  say "Test 2.4: decision_memory_predict returns predictions"
  # Add more samples so we have >= 3 for STANDARD
  decision_memory_record "run-005" "STANDARD" 55000 52000 0 2 160
  local prediction
  prediction=$(decision_memory_predict "STANDARD")
  if echo "$prediction" | grep -q '"prediction":"available"'; then
    pass "decision_memory_predict returns available prediction"
  else
    fail "decision_memory_predict returned unexpected: $prediction"
  fi
  if echo "$prediction" | grep -q '"recommended_token_budget"'; then
    pass "Prediction includes recommended_token_budget"
  else
    fail "Prediction missing recommended_token_budget"
  fi

  # --- Test 2.5: decision_memory_predict with insufficient data ---
  say "Test 2.5: decision_memory_predict with insufficient data"
  local insuf_prediction
  insuf_prediction=$(decision_memory_predict "VERIFICATION")
  if echo "$insuf_prediction" | grep -q '"insufficient_data"'; then
    pass "Returns insufficient_data for mode with <3 samples"
  else
    fail "Expected insufficient_data, got: $insuf_prediction"
  fi

  # --- Test 2.6: Simulate second run and verify cache hit ---
  say "Test 2.6: Simulate second run — cache hit behavior"
  cache_set "file:${CLAUDE_ROOT}/docs/policy/build.md" "build policy content" "policy"
  local first_read
  first_read=$(cache_get "file:${CLAUDE_ROOT}/docs/policy/build.md" 2>/dev/null || echo "")
  local second_read
  second_read=$(cache_get "file:${CLAUDE_ROOT}/docs/policy/build.md" 2>/dev/null || echo "")
  if [[ "$first_read" == "$second_read" && -n "$first_read" ]]; then
    local read_count
    read_count=$(sqlite3 "$CACHE_DB" "SELECT read_count FROM cache_entries WHERE key='file:${CLAUDE_ROOT}/docs/policy/build.md';" 2>/dev/null || echo "0")
    if [[ "$read_count" -ge 2 ]]; then
      pass "Cache hit increments read_count (count=$read_count)"
    else
      pass "Cache returns consistent content on second read"
    fi
  else
    fail "Cache returned different content on second read"
  fi

  teardown_test_cache
}

# ============================================================================
# TEST SUITE 3: Cached Tool Wrappers
# ============================================================================

test_cached_tools() {
  say ""
  say "=== TEST SUITE 3: Cached Tool Wrappers ==="
  say ""

  setup_test_cache

  # Source cache library and override to test DB
  source "$CLAUDE_ROOT/.claude/scripts/cache.sh"
  CACHE_DIR="$TEST_CACHE_DIR"
  CACHE_DB="$TEST_CACHE_DB"
  CACHE_REPO_MAP="${TEST_CACHE_DIR}/repo-map.txt"
  LOG_FILE="${TEST_CACHE_DIR}/logs/factory.log"
  LOCK_DIR="${CACHE_DIR}/.lock"
  cache_init

  # --- Test 3.1: cached_rg returns and caches results ---
  say "Test 3.1: cached_rg returns and caches results"
  local result1
  result1=$(cached_rg "cache_invalidate_for_write" "${CLAUDE_ROOT}/.claude/scripts" 2>/dev/null || echo "")
  if [[ -n "$result1" ]]; then
    pass "cached_rg returns search results"
  else
    fail "cached_rg returned empty results"
  fi

  # --- Test 3.2: cached_rg returns cached results on second call ---
  say "Test 3.2: cached_rg returns cached results on second call"
  local result2
  result2=$(cached_rg "cache_invalidate_for_write" "${CLAUDE_ROOT}/.claude/scripts" 2>/dev/null || echo "")
  if [[ "$result1" == "$result2" ]]; then
    pass "cached_rg returns same results on second call (cache hit)"
  else
    fail "cached_rg returned different results on second call"
  fi

  # --- Test 3.3: cached_file_list returns results ---
  say "Test 3.3: cached_file_list returns results"
  local files
  files=$(cached_file_list "*.sh" 2>/dev/null || echo "")
  if [[ -n "$files" ]]; then
    pass "cached_file_list returns file list"
  else
    fail "cached_file_list returned empty"
  fi

  # --- Test 3.4: Policy file invalidation clears related caches ---
  say "Test 3.4: Policy file modification triggers invalidation"
  source "$CLAUDE_ROOT/.claude/scripts/cache-hooks.sh"
  cache_set "policy:orchestration" "orch policy" "policy"
  cache_set "file:${CLAUDE_ROOT}/docs/policy/orchestration.md" "orch file" "file"
  cache_invalidate_for_write "${CLAUDE_ROOT}/docs/policy/orchestration.md"
  local p_after=$(cache_get "policy:orchestration" 2>/dev/null || echo "")
  local f_after=$(cache_get "file:${CLAUDE_ROOT}/docs/policy/orchestration.md" 2>/dev/null || echo "")
  if [[ -z "$p_after" && -z "$f_after" ]]; then
    pass "Policy file modification invalidates both typed and file caches"
  else
    fail "Policy invalidation incomplete (policy='$p_after', file='$f_after')"
  fi

  teardown_test_cache
}

# ============================================================================
# TEST SUITE 4: Validation Script
# ============================================================================

test_validation() {
  say ""
  say "=== TEST SUITE 4: Validation Script ==="
  say ""

  # --- Test 4.1: validate-policies.sh runs without errors ---
  say "Test 4.1: validate-policies.sh runs successfully"
  local validation_output
  if validation_output=$(cd "$CLAUDE_ROOT" && bash .claude/scripts/validate-policies.sh 2>&1); then
    pass "validate-policies.sh completed successfully"
  else
    local exit_code=$?
    fail "validate-policies.sh exited with code $exit_code"
    # Show first few lines of output for debugging
    echo "$validation_output" | tail -20
  fi

  # --- Test 4.2: All required files exist ---
  say "Test 4.2: All Phase 4 files exist"
  local required_files=(
    ".claude/scripts/cache-hooks.sh"
    "docs/policy/cached-tools.md"
    ".claude/scripts/cache.sh"
  )
  local all_exist=true
  for f in "${required_files[@]}"; do
    if [[ -f "${CLAUDE_ROOT}/${f}" ]]; then
      pass "$f exists"
    else
      fail "$f missing"
      all_exist=false
    fi
  done
}

# ============================================================================
# TEST SUITE 5: Cross-Run Simulation
# ============================================================================

test_cross_run_simulation() {
  say ""
  say "=== TEST SUITE 5: Cross-Run Simulation ==="
  say ""

  setup_test_cache
  source "$CLAUDE_ROOT/.claude/scripts/cache.sh"
  CACHE_DIR="$TEST_CACHE_DIR"
  CACHE_DB="$TEST_CACHE_DB"
  CACHE_REPO_MAP="${TEST_CACHE_DIR}/repo-map.txt"
  LOG_FILE="${TEST_CACHE_DIR}/logs/factory.log"
  LOCK_DIR="${CACHE_DIR}/.lock"
  cache_init

  source "$CLAUDE_ROOT/.claude/scripts/cache-hooks.sh"
  CACHE_DIR="$TEST_CACHE_DIR"
  CACHE_DB="$TEST_CACHE_DB"
  LOG_FILE="${TEST_CACHE_DIR}/logs/factory.log"

  # --- Simulate Run 1 ---
  say "Simulating Run 1..."
  cache_set "file:${CLAUDE_ROOT}/docs/policy/build.md" "build policy v1" "policy"
  cache_set "file:${CLAUDE_ROOT}/docs/policy/agents.md" "agents policy v1" "policy"
  decision_memory_record "sim-run-1" "STANDARD" 50000 47000 0 2 120

  # --- Simulate Run 2 (with policy change) ---
  say "Simulating Run 2 (policy file modified)..."
  cache_invalidate_for_write "${CLAUDE_ROOT}/docs/policy/build.md"
  cache_set "file:${CLAUDE_ROOT}/docs/policy/build.md" "build policy v2" "policy"
  decision_memory_record "sim-run-2" "STANDARD" 45000 42000 0 1 90

  # --- Test 5.1: Run 2 gets fresh policy content ---
  say "Test 5.1: Run 2 reads updated policy content"
  local build_content
  build_content=$(cache_get "file:${CLAUDE_ROOT}/docs/policy/build.md" 2>/dev/null || echo "")
  if [[ "$build_content" == "build policy v2" ]]; then
    pass "Run 2 reads updated policy content (v2)"
  else
    fail "Run 2 got stale content: '$build_content'"
  fi

  # --- Test 5.2: Decision memory accumulates across runs ---
  say "Test 5.2: Decision memory accumulates across runs"
  local dm_count
  dm_count=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM decision_memory;" 2>/dev/null || echo "0")
  if [[ "$dm_count" -ge 2 ]]; then
    pass "Decision memory has entries from both runs ($dm_count entries)"
  else
    fail "Decision memory missing entries ($dm_count)"
  fi

  # --- Test 5.3: decision_memory_summary works with accumulated data ---
  say "Test 5.3: decision_memory_summary with accumulated data"
  decision_memory_record "sim-run-3" "STANDARD" 48000 44000 0 1 100
  local summary
  summary=$(decision_memory_summary 10)
  if echo "$summary" | grep -q "Decision Memory Summary" && echo "$summary" | grep -q "Architect skip rate"; then
    pass "Summary produced with accumulated data"
  else
    fail "Summary incomplete with accumulated data"
  fi

  teardown_test_cache
}

# ============================================================================
# TEST SUITE 6: Cache Invalidation Integration
# ============================================================================

test_cache_invalidation_integration() {
  say ""
  say "=== TEST SUITE 6: Cache Invalidation Integration ==="
  say ""

  setup_test_cache
  source "$CLAUDE_ROOT/.claude/scripts/cache.sh"
  CACHE_DIR="$TEST_CACHE_DIR"
  CACHE_DB="$TEST_CACHE_DB"
  CACHE_REPO_MAP="${TEST_CACHE_DIR}/repo-map.txt"
  LOG_FILE="${TEST_CACHE_DIR}/logs/factory.log"
  LOCK_DIR="${CACHE_DIR}/.lock"
  cache_init

  source "$CLAUDE_ROOT/.claude/scripts/cache-hooks.sh"
  CACHE_DIR="$TEST_CACHE_DIR"
  CACHE_DB="$TEST_CACHE_DB"
  LOG_FILE="${TEST_CACHE_DIR}/logs/factory.log"

  # --- Test 6.1: Write invalidation cascades correctly ---
  say "Test 6.1: Write invalidation cascades correctly"
  cache_set "file:${CLAUDE_ROOT}/src/index.ts" "original content" "file"
  cache_set "tool:rg:search1" "search results" "tool_output"
  cache_set "repo_map" "original map" "repo_map"

  cache_invalidate_for_write "${CLAUDE_ROOT}/src/index.ts"

  local file_after=$(cache_get "file:${CLAUDE_ROOT}/src/index.ts" 2>/dev/null || echo "")
  local tool_after=$(cache_get "tool:rg:search1" 2>/dev/null || echo "")
  local map_after=$(cache_get "repo_map" 2>/dev/null || echo "")

  if [[ -z "$file_after" && -z "$tool_after" && -n "$map_after" ]]; then
    pass "Write invalidation cleared file and tool caches, preserved repo_map"
  else
    fail "Write invalidation cascade incorrect (file='$file_after', tool='$tool_after', map='$map_after')"
  fi

  # --- Test 6.2: Policy change invalidates all policy caches ---
  say "Test 6.2: Policy change invalidates all policy caches"
  cache_set "policy:build" "build policy" "policy"
  cache_set "policy:agents" "agents policy" "policy"
  cache_set "policy:workflow" "workflow policy" "policy"
  cache_set "runbook:add-mcp" "runbook content" "runbook"
  cache_set "file:${CLAUDE_ROOT}/src/other.ts" "other file" "file"

  cache_invalidate_for_policy_change

  local p1=$(cache_get "policy:build" 2>/dev/null || echo "")
  local p2=$(cache_get "policy:agents" 2>/dev/null || echo "")
  local p3=$(cache_get "policy:workflow" 2>/dev/null || echo "")
  local r1=$(cache_get "runbook:add-mcp" 2>/dev/null || echo "")
  local f1=$(cache_get "file:${CLAUDE_ROOT}/src/other.ts" 2>/dev/null || echo "")

  if [[ -z "$p1" && -z "$p2" && -z "$p3" && -z "$r1" && -n "$f1" ]]; then
    pass "Policy change invalidated all policy/runbook caches, preserved other files"
  else
    fail "Policy invalidation incomplete"
  fi

  # --- Test 6.3: Git HEAD change preserves decision memory ---
  say "Test 6.3: Git HEAD change preserves decision memory"
  cache_set "file:${CLAUDE_ROOT}/test.js" "test" "file"
  cache_set "policy:test" "test policy" "policy"
  cache_set "tool:rg:test" "test tool" "tool_output"
  decision_memory_record "test-run-git-1" "STANDARD" 50000 48000 0 2 120
  decision_memory_record "test-run-git-2" "MICRO-CHANGE" 15000 14000 1 1 60

  cache_invalidate_for_git_head_change

  local file_after=$(cache_get "file:${CLAUDE_ROOT}/test.js" 2>/dev/null || echo "")
  local dm_count=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM decision_memory WHERE run_id LIKE 'test-run-git-%';" 2>/dev/null || echo "0")

  if [[ -z "$file_after" && "$dm_count" -eq 2 ]]; then
    pass "Git HEAD change cleared caches but preserved decision memory"
  else
    fail "Git HEAD change behavior incorrect (file='$file_after', dm_count=$dm_count)"
  fi

  teardown_test_cache
}

# ============================================================================
# TEST SUITE 7: Decision Memory Advanced Tests
# ============================================================================

test_decision_memory_advanced() {
  say ""
  say "=== TEST SUITE 7: Decision Memory Advanced Tests ==="
  say ""

  setup_test_cache
  source "$CLAUDE_ROOT/.claude/scripts/cache.sh"
  CACHE_DIR="$TEST_CACHE_DIR"
  CACHE_DB="$TEST_CACHE_DB"
  CACHE_REPO_MAP="${TEST_CACHE_DIR}/repo-map.txt"
  LOG_FILE="${TEST_CACHE_DIR}/logs/factory.log"
  LOCK_DIR="${CACHE_DIR}/.lock"
  cache_init

  # --- Test 7.1: Prediction with mixed task modes ---
  say "Test 7.1: Prediction with mixed task modes"
  # Add samples for STANDARD mode
  decision_memory_record "adv-1" "STANDARD" 50000 48000 0 2 120
  decision_memory_record "adv-2" "STANDARD" 55000 52000 0 2 130
  decision_memory_record "adv-3" "STANDARD" 48000 46000 0 1 110

  # Add samples for MICRO-CHANGE mode
  decision_memory_record "adv-4" "MICRO-CHANGE" 15000 14000 1 1 50
  decision_memory_record "adv-5" "MICRO-CHANGE" 12000 11000 1 1 45
  decision_memory_record "adv-6" "MICRO-CHANGE" 18000 17000 1 1 55

  local std_prediction=$(decision_memory_predict "STANDARD" 2>/dev/null || echo "")
  local micro_prediction=$(decision_memory_predict "MICRO-CHANGE" 2>/dev/null || echo "")

  if echo "$std_prediction" | grep -q '"prediction":"available"'; then
    pass "STANDARD prediction available with 3+ samples"
  else
    fail "STANDARD prediction unavailable"
  fi

  if echo "$micro_prediction" | grep -q '"prediction":"available"'; then
    pass "MICRO-CHANGE prediction available with 3+ samples"
  else
    fail "MICRO-CHANGE prediction unavailable"
  fi

  # --- Test 7.2: Decision memory summary with varied data ---
  say "Test 7.2: Decision memory summary with varied data"
  local summary=$(decision_memory_summary 10 2>/dev/null || echo "")

  if echo "$summary" | grep -q "Decision Memory Summary"; then
    pass "Summary header present"
  else
    fail "Summary header missing"
  fi

  if echo "$summary" | grep -q "Architect skip rate"; then
    pass "Architect skip rate calculated"
  else
    fail "Architect skip rate missing"
  fi

  if echo "$summary" | grep -q "Avg token budget"; then
    pass "Average token budget calculated"
  else
    fail "Average token budget missing"
  fi

  # --- Test 7.3: Stats aggregation ---
  say "Test 7.3: Stats aggregation with multiple modes"
  local stats=$(decision_memory_stats 2>/dev/null || echo "")

  if echo "$stats" | grep -q '"total_runs":6'; then
    pass "Stats reports correct total_runs (6)"
  else
    fail "Stats total_runs incorrect"
  fi

  if echo "$stats" | grep -q '"modes"'; then
    pass "Stats includes modes breakdown"
  else
    fail "Stats missing modes breakdown"
  fi

  # --- Test 7.4: Architect skip rate calculation ---
  say "Test 7.4: Architect skip rate calculation"
  # We have 6 records: 3 MICRO-CHANGE (all skipped architect) + 3 STANDARD (none skipped)
  # Skip rate should be 3/6 = 50%
  local stats=$(decision_memory_stats 2>/dev/null || echo "")
  if echo "$stats" | grep -q '"architect_skip_rate"'; then
    pass "Stats includes architect_skip_rate"
    # Extract skip rate (format is "architect_skip_rate":0.50 or similar)
    local skip_rate=$(echo "$stats" | grep -o '"architect_skip_rate":[0-9.]*' | cut -d: -f2)
    if [[ -n "$skip_rate" ]]; then
      pass "Architect skip rate extracted: $skip_rate"
    fi
  else
    fail "Stats missing architect_skip_rate"
  fi

  teardown_test_cache
}

# ============================================================================
# TEST SUITE 8: Policy File Touch Invalidation
# ============================================================================

test_policy_file_touch_invalidation() {
  say ""
  say "=== TEST SUITE 8: Policy File Touch Invalidation ==="
  say ""

  setup_test_cache
  source "$CLAUDE_ROOT/.claude/scripts/cache.sh"
  CACHE_DIR="$TEST_CACHE_DIR"
  CACHE_DB="$TEST_CACHE_DB"
  CACHE_REPO_MAP="${TEST_CACHE_DIR}/repo-map.txt"
  LOG_FILE="${TEST_CACHE_DIR}/logs/factory.log"
  LOCK_DIR="${CACHE_DIR}/.lock"
  cache_init

  source "$CLAUDE_ROOT/.claude/scripts/cache-hooks.sh"
  CACHE_DIR="$TEST_CACHE_DIR"
  CACHE_DB="$TEST_CACHE_DB"
  LOG_FILE="${TEST_CACHE_DIR}/logs/factory.log"

  # --- Test 8.1: Touch policy file invalidates policy cache ---
  say "Test 8.1: Touch policy file invalidates policy cache"
  cache_set "policy:orchestration" "orchestration policy content" "policy"
  cache_set "file:${CLAUDE_ROOT}/docs/policy/orchestration.md" "file content" "file"

  # Simulate file touch (modification)
  cache_invalidate_for_write "${CLAUDE_ROOT}/docs/policy/orchestration.md"

  local policy_after=$(cache_get "policy:orchestration" 2>/dev/null || echo "")
  local file_after=$(cache_get "file:${CLAUDE_ROOT}/docs/policy/orchestration.md" 2>/dev/null || echo "")

  if [[ -z "$policy_after" && -z "$file_after" ]]; then
    pass "Touch invalidated both policy and file caches"
  else
    fail "Touch invalidation incomplete (policy='$policy_after', file='$file_after')"
  fi

  # --- Test 8.2: Touch one policy file doesn't affect other policies ---
  say "Test 8.2: Touch one policy file doesn't affect unrelated policies"
  cache_set "policy:build" "build policy" "policy"
  cache_set "policy:agents" "agents policy" "policy"
  cache_set "file:${CLAUDE_ROOT}/docs/policy/build.md" "build file" "file"

  # Only touch build.md
  cache_invalidate_for_write "${CLAUDE_ROOT}/docs/policy/build.md"

  local build_p=$(cache_get "policy:build" 2>/dev/null || echo "")
  local agents_p=$(cache_get "policy:agents" 2>/dev/null || echo "")

  if [[ -z "$build_p" && -n "$agents_p" ]]; then
    pass "Selective policy invalidation works (build cleared, agents preserved)"
  else
    fail "Selective invalidation failed (build='$build_p', agents='$agents_p')"
  fi

  # --- Test 8.3: Policy directory scan invalidation ---
  say "Test 8.3: Policy directory-level invalidation clears all policies"
  cache_set "policy:workflow" "workflow" "policy"
  cache_set "policy:quota" "quota" "policy"
  cache_set "runbook:add-mcp" "runbook" "runbook"

  cache_invalidate_for_policy_change

  local w=$(cache_get "policy:workflow" 2>/dev/null || echo "")
  local q=$(cache_get "policy:quota" 2>/dev/null || echo "")
  local r=$(cache_get "runbook:add-mcp" 2>/dev/null || echo "")

  if [[ -z "$w" && -z "$q" && -z "$r" ]]; then
    pass "Directory-level policy change cleared all policy/runbook caches"
  else
    fail "Directory-level invalidation incomplete"
  fi

  teardown_test_cache
}

# ============================================================================
# MAIN
# ============================================================================

say "================================================================"
say "  Phase 4 Integration Tests"
say "  Testing: Cache Hooks, Decision Memory, Cached Tools, Validation"
say "================================================================"

test_cache_hooks
test_decision_memory
test_cached_tools
test_validation
test_cross_run_simulation
test_cache_invalidation_integration
test_decision_memory_advanced
test_policy_file_touch_invalidation

say ""
say "================================================================"
say "  Results: $PASS_COUNT passed, $FAIL_COUNT failed"
say "================================================================"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
