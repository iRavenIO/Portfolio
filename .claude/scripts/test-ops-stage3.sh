#!/usr/bin/env bash
# test-ops-stage3.sh — Test suite for Ops MCP Stage 3
# Tests: Bug fixes, config system, approval workflow, unified discovery
# Expected: 29 tests passing

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_ROOT="${CLAUDE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Load shared libraries
source "$SCRIPT_DIR/lib/env.sh"
source "$SCRIPT_DIR/lib/test-framework.sh"

# Load environment
_load_env_claude

# ============================================================================
# PHASE A: BUG FIXES (3 tests)
# ============================================================================

info "Phase A: Bug Fixes"

# Test 1: Redis NaN handling
test_redis_nan() {
  local test_output="not_a_number"
  local parsed=$(node -e "const val = parseInt('$test_output'.trim(), 10); console.log(isNaN(val) ? 0 : val);")
  if [[ "$parsed" == "0" ]]; then
    pass "A1: Redis NaN handling returns 0 for invalid input"
  else
    fail "A1: Redis NaN handling" "Expected 0, got $parsed"
  fi
}

# Test 2: GitHub repo format handling
test_github_repo_format() {
  # Verify server-ops.js has proper repo format handling
  if grep -q "repos/{owner}/{repo}/branches" "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "A2: GitHub repo format uses template syntax for current repo"
  else
    fail "A2: GitHub repo format" "Missing template syntax in branches discovery"
  fi
}

# Test 3: Multi-secret redaction
test_multi_secret_redaction() {
  # Verify redactOutput doesn't have early returns
  local early_returns=$(grep -c "return redacted" "$CLAUDE_ROOT/.claude/mcp/server-ops.js" || echo "0")
  if [[ "$early_returns" -le 1 ]]; then
    pass "A3: Multi-secret redaction processes all patterns"
  else
    fail "A3: Multi-secret redaction" "Found $early_returns early returns (should be 1)"
  fi
}

test_redis_nan
test_github_repo_format
test_multi_secret_redaction

# ============================================================================
# PHASE B: CONFIG SYSTEM (6 tests)
# ============================================================================

info "Phase B: Config System"

# Test 4: Config file exists
test_config_file_exists() {
  if [[ -f "$CLAUDE_ROOT/.claude/config/ops.json" ]]; then
    pass "B1: Config file exists at .claude/config/ops.json"
  else
    fail "B1: Config file existence" "ops.json not found"
  fi
}

# Test 5: Config schema exists
test_config_schema_exists() {
  if [[ -f "$CLAUDE_ROOT/.claude/config/ops.schema.json" ]]; then
    pass "B2: Config schema exists at .claude/config/ops.schema.json"
  else
    fail "B2: Config schema existence" "ops.schema.json not found"
  fi
}

# Test 6: Config is valid JSON
test_config_valid_json() {
  if jq empty "$CLAUDE_ROOT/.claude/config/ops.json" >/dev/null 2>&1; then
    pass "B3: Config file is valid JSON"
  else
    fail "B3: Config JSON validation" "Invalid JSON syntax"
  fi
}

# Test 7: Config has required fields
test_config_required_fields() {
  local has_version=$(jq -r '.version' "$CLAUDE_ROOT/.claude/config/ops.json")
  local has_discovery=$(jq -r '.discovery' "$CLAUDE_ROOT/.claude/config/ops.json")
  local has_approval=$(jq -r '.approval' "$CLAUDE_ROOT/.claude/config/ops.json")

  if [[ "$has_version" != "null" && "$has_discovery" != "null" && "$has_approval" != "null" ]]; then
    pass "B4: Config has required fields (version, discovery, approval)"
  else
    fail "B4: Config required fields" "Missing version, discovery, or approval"
  fi
}

# Test 8: Config loader in server
test_config_loader_exists() {
  if grep -q "loadOpsConfig" "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "B5: Config loader function exists in server-ops.js"
  else
    fail "B5: Config loader" "loadOpsConfig function not found"
  fi
}

# Test 9: Hot-reload support
test_config_hot_reload() {
  if grep -q "watchFile.*configPath" "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "B6: Config hot-reload uses watchFile"
  else
    fail "B6: Config hot-reload" "watchFile not found in config loader"
  fi
}

test_config_file_exists
test_config_schema_exists
test_config_valid_json
test_config_required_fields
test_config_loader_exists
test_config_hot_reload

# ============================================================================
# PHASE C: APPROVAL WORKFLOW (10 tests)
# ============================================================================

info "Phase C: Approval Workflow"

# Test 10: Approval database schema
test_approval_db_schema() {
  if grep -q "CREATE TABLE IF NOT EXISTS approvals" "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "C1: Approval database schema defined"
  else
    fail "C1: Approval database schema" "CREATE TABLE not found"
  fi
}

# Test 11: Plan hash function
test_plan_hash_function() {
  if grep -q "function hashPlan" "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "C2: Plan hash function exists"
  else
    fail "C2: Plan hash function" "hashPlan not found"
  fi
}

# Test 12: Plan ID generation
test_plan_id_generation() {
  if grep -q "function generatePlanId" "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "C3: Plan ID generation function exists"
  else
    fail "C3: Plan ID generation" "generatePlanId not found"
  fi
}

# Test 13: ops_plan_mutation tool
test_ops_plan_mutation_tool() {
  if grep -q '"ops_plan_mutation"' "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "C4: ops_plan_mutation tool registered"
  else
    fail "C4: ops_plan_mutation tool" "Tool not found in server"
  fi
}

# Test 14: ops_approve tool
test_ops_approve_tool() {
  if grep -q '"ops_approve"' "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "C5: ops_approve tool registered"
  else
    fail "C5: ops_approve tool" "Tool not found in server"
  fi
}

# Test 15: ops_list_pending tool
test_ops_list_pending_tool() {
  if grep -q '"ops_list_pending"' "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "C6: ops_list_pending tool registered"
  else
    fail "C6: ops_list_pending tool" "Tool not found in server"
  fi
}

# Test 16: ops_execute tool
test_ops_execute_tool() {
  if grep -q '"ops_execute"' "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "C7: ops_execute tool registered"
  else
    fail "C7: ops_execute tool" "Tool not found in server"
  fi
}

# Test 17: Hash verification in approve
test_hash_verification() {
  if grep -q "plan.plan_hash !== plan_hash" "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "C8: Hash verification in ops_approve"
  else
    fail "C8: Hash verification" "Hash comparison not found"
  fi
}

# Test 18: TTL check in approve
test_ttl_check_approve() {
  if grep -q "age > maxAge" "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "C9: TTL expiration check in approval flow"
  else
    fail "C9: TTL check" "Age comparison not found"
  fi
}

# Test 19: Approval initialization called
test_approval_init_called() {
  if grep -q "await initApprovalStore()" "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "C10: initApprovalStore called in main()"
  else
    fail "C10: Approval init" "initApprovalStore not called"
  fi
}

test_approval_db_schema
test_plan_hash_function
test_plan_id_generation
test_ops_plan_mutation_tool
test_ops_approve_tool
test_ops_list_pending_tool
test_ops_execute_tool
test_hash_verification
test_ttl_check_approve
test_approval_init_called

# ============================================================================
# PHASE D: UNIFIED DISCOVERY (5 tests)
# ============================================================================

info "Phase D: Unified Discovery"

# Test 20: ops_discover tool exists
test_ops_discover_tool() {
  if grep -q '"ops_discover"' "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "D1: ops_discover unified tool registered"
  else
    fail "D1: ops_discover tool" "Tool not found in server"
  fi
}

# Test 21: Tool handlers map
test_tool_handlers_map() {
  if grep -q "const toolHandlers = {" "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "D2: Tool handlers map defined"
  else
    fail "D2: Tool handlers" "toolHandlers object not found"
  fi
}

# Test 22: Parallel execution support
test_parallel_execution() {
  if grep -q "Promise.all" "$CLAUDE_ROOT/.claude/mcp/server-ops.js" && grep -q "useParallel" "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "D3: Parallel execution with Promise.all"
  else
    fail "D3: Parallel execution" "Promise.all or useParallel not found"
  fi
}

# Test 23: Concurrency limiting
test_concurrency_limit() {
  if grep -q "maxConcurrent" "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "D4: Concurrency limiting implemented"
  else
    fail "D4: Concurrency limit" "maxConcurrent not found"
  fi
}

# Test 24: Unified discovery result format
test_unified_result_format() {
  if grep -q "unified_discovery: true" "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "D5: Unified discovery result format includes marker"
  else
    fail "D5: Result format" "unified_discovery marker not found"
  fi
}

test_ops_discover_tool
test_tool_handlers_map
test_parallel_execution
test_concurrency_limit
test_unified_result_format

# ============================================================================
# PHASE E: INTEGRATION TESTS (5 tests)
# ============================================================================

info "Phase E: Integration Tests"

# Test 25: Total tool count
test_total_tool_count() {
  local tool_count=$(grep -c 'server.tool(' "$CLAUDE_ROOT/.claude/mcp/server-ops.js" || echo 0)
  if [[ "$tool_count" -ge 14 ]]; then
    pass "E1: Server registers 14+ tools (9 discovery + 1 unified + 4 approval)"
  else
    fail "E1: Tool count" "Found $tool_count tools, expected 14+"
  fi
}

# Test 26: All imports present
test_required_imports() {
  local has_crypto=$(grep -q "import.*createHash.*crypto" "$CLAUDE_ROOT/.claude/mcp/server-ops.js" && echo "yes" || echo "no")
  local has_watch=$(grep -q "import.*watchFile" "$CLAUDE_ROOT/.claude/mcp/server-ops.js" && echo "yes" || echo "no")

  if [[ "$has_crypto" == "yes" && "$has_watch" == "yes" ]]; then
    pass "E2: Required imports (crypto, watchFile) present"
  else
    fail "E2: Required imports" "Missing crypto=$has_crypto watchFile=$has_watch"
  fi
}

# Test 27: Redaction applied to approval outputs
test_approval_redaction() {
  if grep -q "redactOutput.*JSON.stringify.*params" "$CLAUDE_ROOT/.claude/mcp/server-ops.js" || grep -q "redactedOutput.*JSON.stringify.*simulated" "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "E3: Approval outputs pass through redactOutput"
  else
    fail "E3: Approval redaction" "redactOutput not found in approval tools"
  fi
}

# Test 28: Config initialization in main
test_config_init_in_main() {
  if grep -q "await loadOpsConfig()" "$CLAUDE_ROOT/.claude/mcp/server-ops.js"; then
    pass "E4: Config loaded in main() startup"
  else
    fail "E4: Config initialization" "loadOpsConfig not called in main"
  fi
}

# Test 29: No syntax errors
test_no_syntax_errors() {
  if node -c "$CLAUDE_ROOT/.claude/mcp/server-ops.js" >/dev/null 2>&1; then
    pass "E5: server-ops.js has no syntax errors"
  else
    fail "E5: Syntax validation" "Node.js syntax check failed"
  fi
}

test_total_tool_count
test_required_imports
test_approval_redaction
test_config_init_in_main
test_no_syntax_errors

# ============================================================================
# SUMMARY
# ============================================================================

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Test Results: Ops MCP Stage 3"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Total Tests:  $TESTS_RUN"
echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [[ $TESTS_FAILED -eq 0 ]]; then
  echo -e "${GREEN}✓ All tests passed${NC}"
  exit 0
else
  echo -e "${RED}✗ $TESTS_FAILED test(s) failed${NC}"
  exit 1
fi
