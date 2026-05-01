#!/usr/bin/env bash
set -Eeuo pipefail

# Load shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"

# ╔═══════════════════════════════════════════════════════════════╗
# ║  📋 Claude Factory — validate-policies.sh                     ║
# ║  Check policy file integrity and cross-references             ║
# ╚═══════════════════════════════════════════════════════════════╝

say "╔═══════════════════════════════════════════════════════════════════════╗"
say "║  📋 Claude Factory — Policy Validation                               ║"
say "╚═══════════════════════════════════════════════════════════════════════╝"
say ""

EXIT_CODE=0

# 1. Check policy files exist
say "🔎 Checking policy file existence..."
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
  "docs/policy/token-budget.md"
  "docs/policy/observability.md"
  "docs/policy/cache.md"
  "docs/policy/cached-tools.md"
  "docs/policy/secrets-and-env.md"
  "docs/policy/ops-tools.md"
  "docs/policy/ops-mode.md"
)

for policy in "${POLICY_FILES[@]}"; do
  if [[ -f "$policy" ]]; then
    say "  ✅ $policy"
  else
    err "  ❌ $policy missing"
    EXIT_CODE=1
  fi
done
say ""

# 2. Check CLAUDE.md references to policy files
say "🔎 Checking CLAUDE.md policy references..."
EXPECTED_REFS=(
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
  "docs/policy/token-budget.md"
  "docs/policy/observability.md"
  "docs/policy/cache.md"
  "docs/policy/cached-tools.md"
  "docs/policy/secrets-and-env.md"
  "docs/policy/ops-tools.md"
  "docs/policy/ops-mode.md"
)

for ref in "${EXPECTED_REFS[@]}"; do
  if grep -q "$ref" CLAUDE.md; then
    say "  ✅ CLAUDE.md → $ref"
  else
    err "  ❌ CLAUDE.md missing reference to $ref"
    EXIT_CODE=1
  fi
done
say ""

# 3. Check spawn-templates.md for required sections
say "🔎 Validating spawn-templates.md structure..."
REQUIRED_PHASES=(
  "PHASE 1: ANALYSIS"
  "PHASE 2: RESEARCH"
  "PHASE 3: ARCHITECTURE"
  "PHASE 4: IMPLEMENTATION LOOP"
  "PHASE 5: FINAL REPORT"
  "PHASE 6: BATCH COMPLETION SUMMARY"
)

for phase in "${REQUIRED_PHASES[@]}"; do
  if grep -q "$phase" docs/policy/spawn-templates.md; then
    say "  ✅ $phase"
  else
    err "  ❌ spawn-templates.md missing: $phase"
    EXIT_CODE=1
  fi
done
say ""

# 4. Check spawn-templates.md for fixed TOOL-FIRST references
say "🔎 Checking TOOL-FIRST policy references in spawn-templates.md..."
OLD_REF_COUNT=$(grep -c "See the TOOL-FIRST POLICY section in CLAUDE.md for full rules" docs/policy/spawn-templates.md || true)
NEW_REF_COUNT=$(grep -c "See docs/policy/build.md for full rules" docs/policy/spawn-templates.md || true)

if [[ "$OLD_REF_COUNT" -gt 0 ]]; then
  err "  ❌ Found $OLD_REF_COUNT old TOOL-FIRST references (should point to docs/policy/build.md)"
  EXIT_CODE=1
else
  say "  ✅ No old TOOL-FIRST references found"
fi

if [[ "$NEW_REF_COUNT" -ge 6 ]]; then
  say "  ✅ Found $NEW_REF_COUNT correct TOOL-FIRST references (minimum 6 expected)"
else
  warn "  ⚠️  Found only $NEW_REF_COUNT TOOL-FIRST references (minimum 6 expected)"
  EXIT_CODE=1
fi
say ""

# 5. Check critical-rules.md for fixed policy file references
say "🔎 Checking policy file references in critical-rules.md..."
if grep -q "docs/policy/build.md" docs/policy/critical-rules.md; then
  say "  ✅ critical-rules.md → docs/policy/build.md"
else
  err "  ❌ critical-rules.md missing reference to docs/policy/build.md"
  EXIT_CODE=1
fi

if grep -q "docs/policy/orchestration.md" docs/policy/critical-rules.md; then
  say "  ✅ critical-rules.md → docs/policy/orchestration.md"
else
  err "  ❌ critical-rules.md missing reference to docs/policy/orchestration.md"
  EXIT_CODE=1
fi
say ""

# 6. Check for CLAUDE.md size reduction
say "🔎 Checking CLAUDE.md file size..."
CLAUDE_LINES=$(wc -l < CLAUDE.md | tr -d ' ')
if [[ "$CLAUDE_LINES" -le 300 ]]; then
  say "  ✅ CLAUDE.md is $CLAUDE_LINES lines (target: ≤300)"
else
  warn "  ⚠️  CLAUDE.md is $CLAUDE_LINES lines (target: ≤300)"
fi
say ""

# 7. Check for orphaned TOOL-FIRST POLICY section in CLAUDE.md
say "🔎 Checking CLAUDE.md for orphaned TOOL-FIRST POLICY section..."
if grep -q "## TOOL-FIRST POLICY" CLAUDE.md; then
  err "  ❌ CLAUDE.md still contains TOOL-FIRST POLICY section (should be moved to docs/policy/build.md)"
  EXIT_CODE=1
else
  say "  ✅ No orphaned TOOL-FIRST POLICY section in CLAUDE.md"
fi
say ""

# 8. Check for orphaned TOKEN USAGE POLICY section in CLAUDE.md
say "🔎 Checking CLAUDE.md for orphaned TOKEN USAGE POLICY section..."
if grep -q "## TOKEN USAGE POLICY" CLAUDE.md; then
  err "  ❌ CLAUDE.md still contains TOKEN USAGE POLICY section (should be moved to docs/policy/build.md)"
  EXIT_CODE=1
else
  say "  ✅ No orphaned TOKEN USAGE POLICY section in CLAUDE.md"
fi
say ""

# 9. Check quota.md exists
say "🔎 Checking quota.md existence..."
if [[ -f "docs/policy/quota.md" ]]; then
  say "  ✅ docs/policy/quota.md exists"
else
  err "  ❌ docs/policy/quota.md missing"
  EXIT_CODE=1
fi
say ""

# 10. Check spawn-templates.md for QUOTA SNAPSHOT references (should be ≥8)
say "🔎 Checking QUOTA SNAPSHOT references in spawn-templates.md..."
QUOTA_SNAPSHOT_COUNT=$(grep -c "QUOTA SNAPSHOT (if provided):" docs/policy/spawn-templates.md || true)
if [[ "$QUOTA_SNAPSHOT_COUNT" -ge 8 ]]; then
  say "  ✅ Found $QUOTA_SNAPSHOT_COUNT QUOTA SNAPSHOT references (minimum 8 expected)"
else
  err "  ❌ Found only $QUOTA_SNAPSHOT_COUNT QUOTA SNAPSHOT references (minimum 8 expected)"
  EXIT_CODE=1
fi
say ""

# 11. Check spawn-templates.md for Pre-Review Pass template
say "🔎 Checking Pre-Review Pass template in spawn-templates.md..."
if grep -q "STEP 4A.6: PRE-REVIEW PASS" docs/policy/spawn-templates.md; then
  say "  ✅ spawn-templates.md contains Pre-Review Pass template (Step 4A.6)"
else
  err "  ❌ spawn-templates.md missing Pre-Review Pass template (Step 4A.6)"
  EXIT_CODE=1
fi
say ""

# 12. Check quota.md for decision table (should have ≥9 rows)
say "🔎 Checking quota.md decision table structure..."
DECISION_TABLE_ROWS=$(grep -c "| LOW\|| MEDIUM\|| HIGH" docs/policy/quota.md || true)
if [[ "$DECISION_TABLE_ROWS" -ge 9 ]]; then
  say "  ✅ Decision table has $DECISION_TABLE_ROWS complexity rows (minimum 9 expected)"
else
  err "  ❌ Decision table has only $DECISION_TABLE_ROWS complexity rows (minimum 9 expected)"
  EXIT_CODE=1
fi
say ""

# 13. Check orchestration.md for PRE-REVIEW FINDINGS
say "🔎 Checking orchestration.md for PRE-REVIEW FINDINGS extension..."
if grep -q "PRE-REVIEW FINDINGS (if Pre-Review Pass ran):" docs/policy/orchestration.md; then
  say "  ✅ orchestration.md contains PRE-REVIEW FINDINGS section"
else
  err "  ❌ orchestration.md missing PRE-REVIEW FINDINGS section"
  EXIT_CODE=1
fi
say ""

# 14. Check spawn-templates.md for Reviewer PRE-REVIEW CONTEXT
say "🔎 Checking spawn-templates.md for Reviewer PRE-REVIEW CONTEXT..."
if grep -q "PRE-REVIEW CONTEXT (if Pre-Review Pass ran):" docs/policy/spawn-templates.md; then
  say "  ✅ spawn-templates.md contains PRE-REVIEW CONTEXT paragraph for Reviewer"
else
  err "  ❌ spawn-templates.md missing PRE-REVIEW CONTEXT paragraph for Reviewer"
  EXIT_CODE=1
fi
say ""

# 15. Check failure-recovery.md exists
say "🔎 Checking failure-recovery.md existence..."
if [[ -f "docs/policy/failure-recovery.md" ]]; then
  say "  ✅ docs/policy/failure-recovery.md exists"
else
  err "  ❌ docs/policy/failure-recovery.md missing"
  EXIT_CODE=1
fi
say ""

# 16. Check failure-recovery.md for Failure Type Taxonomy (5 types)
say "🔎 Checking failure-recovery.md for Failure Type Taxonomy..."
FAILURE_TYPES=(
  "TOOL_FAILURE"
  "AGENT_RUNTIME_ERROR"
  "PARTIAL_OUTPUT"
  "VALIDATION_FAILURE"
  "REVIEW_REJECTION"
)
MISSING_TYPES=0
for ftype in "${FAILURE_TYPES[@]}"; do
  if grep -q "$ftype" docs/policy/failure-recovery.md; then
    say "  ✅ $ftype"
  else
    err "  ❌ $ftype missing"
    MISSING_TYPES=1
  fi
done
if [[ "$MISSING_TYPES" -eq 1 ]]; then
  EXIT_CODE=1
fi
say ""

# 17. Check failure-recovery.md for Developer escalation rules (3 rules)
say "🔎 Checking failure-recovery.md for Developer escalation rules..."
ESCALATION_RULES=(
  "Developer Iteration Escalation Ladder"
  "Failure-Triggered Escalation"
  "Complexity-Triggered Escalation"
)
MISSING_RULES=0
for rule in "${ESCALATION_RULES[@]}"; do
  if grep -q "$rule" docs/policy/failure-recovery.md; then
    say "  ✅ $rule"
  else
    err "  ❌ $rule missing"
    MISSING_RULES=1
  fi
done
if [[ "$MISSING_RULES" -eq 1 ]]; then
  EXIT_CODE=1
fi
say ""

# 18. Check task-modes.md exists and has mode definitions
say "🔎 Checking task-modes.md for mode definitions..."
if [[ -f "docs/policy/task-modes.md" ]]; then
  say "  ✅ docs/policy/task-modes.md exists"
  MODES=("MICRO-CHANGE" "STANDARD" "VERIFICATION")
  MISSING_MODES=0
  for mode in "${MODES[@]}"; do
    if grep -q "$mode" docs/policy/task-modes.md; then
      say "  ✅ $mode mode defined"
    else
      err "  ❌ $mode mode missing"
      MISSING_MODES=1
    fi
  done
  if [[ "$MISSING_MODES" -eq 1 ]]; then
    EXIT_CODE=1
  fi
else
  err "  ❌ docs/policy/task-modes.md missing"
  EXIT_CODE=1
fi
say ""

# 19. Check workflow.md references task-modes.md
say "🔎 Checking workflow.md for task mode classification section..."
if grep -q "Task Mode Classification" docs/policy/workflow.md; then
  say "  ✅ workflow.md contains Task Mode Classification section"
else
  err "  ❌ workflow.md missing Task Mode Classification section"
  EXIT_CODE=1
fi
if grep -q "docs/policy/task-modes.md" docs/policy/workflow.md; then
  say "  ✅ workflow.md references docs/policy/task-modes.md"
else
  err "  ❌ workflow.md missing reference to docs/policy/task-modes.md"
  EXIT_CODE=1
fi
say ""

# 20. Check spawn-templates.md for MICRO-CHANGE spawn variants
say "🔎 Checking spawn-templates.md for MICRO-CHANGE spawn variants..."
if grep -q "MICRO-CHANGE MODE SPAWN VARIANTS" docs/policy/spawn-templates.md; then
  say "  ✅ spawn-templates.md contains MICRO-CHANGE MODE SPAWN VARIANTS section"
  MICRO_CHANGE_AGENTS=("DEVELOPER (MICRO-CHANGE)" "REVIEWER (MICRO-CHANGE)" "TESTER (MICRO-CHANGE)")
  MISSING_VARIANTS=0
  for agent in "${MICRO_CHANGE_AGENTS[@]}"; do
    if grep -q "$agent" docs/policy/spawn-templates.md; then
      say "  ✅ $agent variant defined"
    else
      err "  ❌ $agent variant missing"
      MISSING_VARIANTS=1
    fi
  done
  if [[ "$MISSING_VARIANTS" -eq 1 ]]; then
    EXIT_CODE=1
  fi
else
  err "  ❌ spawn-templates.md missing MICRO-CHANGE MODE SPAWN VARIANTS section"
  EXIT_CODE=1
fi
say ""

# 21. Check git-automation.md exists and has commit conditions
say "🔎 Checking git-automation.md for commit conditions..."
if [[ -f "docs/policy/git-automation.md" ]]; then
  say "  ✅ docs/policy/git-automation.md exists"
  if grep -q "COMMIT CONDITIONS" docs/policy/git-automation.md; then
    say "  ✅ git-automation.md contains COMMIT CONDITIONS section"
  else
    err "  ❌ git-automation.md missing COMMIT CONDITIONS section"
    EXIT_CODE=1
  fi
  if grep -q "Co-Authored-By: Claude Sonnet 4.5" docs/policy/git-automation.md; then
    say "  ✅ git-automation.md specifies Co-Authored-By footer"
  else
    err "  ❌ git-automation.md missing Co-Authored-By footer requirement"
    EXIT_CODE=1
  fi
else
  err "  ❌ docs/policy/git-automation.md missing"
  EXIT_CODE=1
fi
say ""

# 22. Check spawn-templates.md for AUTO-COMMIT PROTOCOL
say "🔎 Checking spawn-templates.md for AUTO-COMMIT PROTOCOL..."
if grep -q "AUTO-COMMIT PROTOCOL:" docs/policy/spawn-templates.md; then
  say "  ✅ spawn-templates.md contains AUTO-COMMIT PROTOCOL section"
else
  err "  ❌ spawn-templates.md missing AUTO-COMMIT PROTOCOL section"
  EXIT_CODE=1
fi
say ""

# 23. Check critical-rules.md for Rules 27 and 28
say "🔎 Checking critical-rules.md for Rules 27 and 28..."
if grep -q "27\. \*\*Execute auto-commit protocol\.\*\*" docs/policy/critical-rules.md; then
  say "  ✅ critical-rules.md contains Rule 27 (auto-commit protocol)"
else
  err "  ❌ critical-rules.md missing Rule 27 (auto-commit protocol)"
  EXIT_CODE=1
fi
if grep -q "28\. \*\*Classify task mode\.\*\*" docs/policy/critical-rules.md; then
  say "  ✅ critical-rules.md contains Rule 28 (task mode classification)"
else
  err "  ❌ critical-rules.md missing Rule 28 (task mode classification)"
  EXIT_CODE=1
fi
say ""

# 24. Check workflow.md for Progressive Phase Notifications
say "🔎 Checking workflow.md for Progressive Phase Notifications..."
if grep -q "Progressive Phase Notifications" docs/policy/workflow.md; then
  say "  ✅ workflow.md contains Progressive Phase Notifications section"
else
  err "  ❌ workflow.md missing Progressive Phase Notifications section"
  EXIT_CODE=1
fi
say ""

# 25. Check orchestration.md for Architect Confirmation Gate
say "🔎 Checking orchestration.md for Architect Confirmation Gate..."
if grep -q "ARCHITECT CONFIRMATION GATE" docs/policy/orchestration.md; then
  say "  ✅ orchestration.md contains ARCHITECT CONFIRMATION GATE section"
else
  err "  ❌ orchestration.md missing ARCHITECT CONFIRMATION GATE section"
  EXIT_CODE=1
fi
say ""

# 26. Check mcp-security.md structure
say "🔎 Checking mcp-security.md structure..."
if [[ -f "docs/policy/mcp-security.md" ]]; then
  say "  ✅ docs/policy/mcp-security.md exists"
  MCP_SECURITY_SECTIONS=(
    "PERMISSION TIERS"
    "AGENT PERMISSION MATRIX"
    "AUDIT LOGGING SPECIFICATION"
  )
  MISSING_SECTIONS=0
  for section in "${MCP_SECURITY_SECTIONS[@]}"; do
    if grep -q "$section" docs/policy/mcp-security.md; then
      say "  ✅ $section section found"
    else
      err "  ❌ $section section missing"
      MISSING_SECTIONS=1
    fi
  done
  if [[ "$MISSING_SECTIONS" -eq 1 ]]; then
    EXIT_CODE=1
  fi
else
  err "  ❌ docs/policy/mcp-security.md missing"
  EXIT_CODE=1
fi
say ""

# 27. Check observability.md structure
say "🔎 Checking observability.md structure..."
if [[ -f "docs/policy/observability.md" ]]; then
  say "  ✅ docs/policy/observability.md exists"
  OBSERVABILITY_SECTIONS=(
    "TOKEN LEDGER SYSTEM"
    "PERFORMANCE METRICS"
    "LOGGING SPECIFICATION"
  )
  MISSING_OBS_SECTIONS=0
  for section in "${OBSERVABILITY_SECTIONS[@]}"; do
    if grep -q "$section" docs/policy/observability.md; then
      say "  ✅ $section section found"
    else
      err "  ❌ $section section missing"
      MISSING_OBS_SECTIONS=1
    fi
  done
  if [[ "$MISSING_OBS_SECTIONS" -eq 1 ]]; then
    EXIT_CODE=1
  fi
else
  err "  ❌ docs/policy/observability.md missing"
  EXIT_CODE=1
fi
say ""

# 28. Check spawn-templates.md for TOKEN LEDGER DATA references
say "🔎 Checking spawn-templates.md for TOKEN LEDGER DATA..."
TOKEN_LEDGER_COUNT=$(grep -c "TOKEN LEDGER DATA" docs/policy/spawn-templates.md || true)
if [[ "$TOKEN_LEDGER_COUNT" -ge 2 ]]; then
  say "  ✅ Found $TOKEN_LEDGER_COUNT TOKEN LEDGER DATA references (minimum 2 expected)"
else
  err "  ❌ Found only $TOKEN_LEDGER_COUNT TOKEN LEDGER DATA references (minimum 2 expected)"
  EXIT_CODE=1
fi
say ""

# 29. Check spawn-templates.md for EXECUTION TIMING references
say "🔎 Checking spawn-templates.md for EXECUTION TIMING..."
EXECUTION_TIMING_COUNT=$(grep -c "EXECUTION TIMING" docs/policy/spawn-templates.md || true)
if [[ "$EXECUTION_TIMING_COUNT" -ge 2 ]]; then
  say "  ✅ Found $EXECUTION_TIMING_COUNT EXECUTION TIMING references (minimum 2 expected)"
else
  err "  ❌ Found only $EXECUTION_TIMING_COUNT EXECUTION TIMING references (minimum 2 expected)"
  EXIT_CODE=1
fi
say ""

# 30. Check observability.md for report format specification
say "🔎 Checking observability.md for EXECUTION METRICS report format..."
if grep -q "## EXECUTION METRICS" docs/policy/observability.md; then
  say "  ✅ observability.md contains EXECUTION METRICS report format"
else
  err "  ❌ observability.md missing EXECUTION METRICS report format"
  EXIT_CODE=1
fi
say ""

# 31. Check cf runner script exists and is executable
say "🔎 Checking cf runner script..."
if [[ -f "cf" ]]; then
  say "  ✅ cf runner script exists"
  if [[ -x "cf" ]]; then
    say "  ✅ cf is executable"
  else
    err "  ❌ cf is not executable (run: chmod +x cf)"
    EXIT_CODE=1
  fi
else
  err "  ❌ cf runner script missing"
  EXIT_CODE=1
fi
say ""

# 32. Check observability.md for Runner Observability section
say "🔎 Checking observability.md for Runner Observability section..."
if grep -q "### Runner Observability" docs/policy/observability.md; then
  say "  ✅ observability.md contains Runner Observability section"
  if grep -q "CLAUDE_FACTORY_RUN_ID" docs/policy/observability.md; then
    say "  ✅ Runner Observability documents CLAUDE_FACTORY_RUN_ID"
  else
    err "  ❌ Runner Observability missing CLAUDE_FACTORY_RUN_ID documentation"
    EXIT_CODE=1
  fi
  if grep -q "CLAUDE_FACTORY_LOG_FILE" docs/policy/observability.md; then
    say "  ✅ Runner Observability documents CLAUDE_FACTORY_LOG_FILE"
  else
    err "  ❌ Runner Observability missing CLAUDE_FACTORY_LOG_FILE documentation"
    EXIT_CODE=1
  fi
else
  err "  ❌ observability.md missing Runner Observability section"
  EXIT_CODE=1
fi
say ""

# 33. Check token-budget.md existence
say "🔎 Checking token-budget.md existence..."
if [[ -f "docs/policy/token-budget.md" ]]; then
  say "  ✅ docs/policy/token-budget.md exists"
else
  err "  ❌ docs/policy/token-budget.md missing"
  EXIT_CODE=1
fi
say ""

# 34. Check orchestration.md for token budget cross-reference
say "🔎 Checking orchestration.md for token budget cross-reference..."
if grep -q "TOKEN BUDGET CROSS-REFERENCE" docs/policy/orchestration.md; then
  say "  ✅ orchestration.md contains TOKEN BUDGET CROSS-REFERENCE section"
  if grep -q "docs/policy/token-budget.md" docs/policy/orchestration.md; then
    say "  ✅ orchestration.md references docs/policy/token-budget.md"
  else
    err "  ❌ orchestration.md missing reference to docs/policy/token-budget.md"
    EXIT_CODE=1
  fi
else
  err "  ❌ orchestration.md missing TOKEN BUDGET CROSS-REFERENCE section"
  EXIT_CODE=1
fi
say ""

# 35. Check spawn-templates.md for Token Budget line in Budget Blocks
say "🔎 Checking spawn-templates.md for Token Budget line in Budget Blocks..."
TOKEN_BUDGET_TEMPLATE_COUNT=$(grep -c "Token Budget: <10K-30K | 30K-80K | 80K-150K>" docs/policy/spawn-templates.md || true)
TOKEN_BUDGET_FIXED_COUNT=$(grep -c "Token Budget: 10K-30K" docs/policy/spawn-templates.md || true)
TOKEN_BUDGET_TOTAL=$((TOKEN_BUDGET_TEMPLATE_COUNT + TOKEN_BUDGET_FIXED_COUNT))
if [[ "$TOKEN_BUDGET_TOTAL" -ge 12 ]]; then
  say "  ✅ Found $TOKEN_BUDGET_TOTAL Token Budget lines ($TOKEN_BUDGET_TEMPLATE_COUNT template + $TOKEN_BUDGET_FIXED_COUNT fixed; minimum 12 expected)"
else
  err "  ❌ Found only $TOKEN_BUDGET_TOTAL Token Budget lines ($TOKEN_BUDGET_TEMPLATE_COUNT template + $TOKEN_BUDGET_FIXED_COUNT fixed; minimum 12 expected)"
  EXIT_CODE=1
fi
say ""

# 36. Check critical-rules.md for Rules 29-31
say "🔎 Checking critical-rules.md for Rules 29-31..."
if grep -q "29\. \*\*Inject token budgets\.\*\*" docs/policy/critical-rules.md; then
  say "  ✅ critical-rules.md contains Rule 29 (inject token budgets)"
else
  err "  ❌ critical-rules.md missing Rule 29 (inject token budgets)"
  EXIT_CODE=1
fi
if grep -q "30\. \*\*Track execution timing\.\*\*" docs/policy/critical-rules.md; then
  say "  ✅ critical-rules.md contains Rule 30 (track execution timing)"
else
  err "  ❌ critical-rules.md missing Rule 30 (track execution timing)"
  EXIT_CODE=1
fi
if grep -q "31\. \*\*Collect token usage metadata\.\*\*" docs/policy/critical-rules.md; then
  say "  ✅ critical-rules.md contains Rule 31 (collect token usage metadata)"
else
  err "  ❌ critical-rules.md missing Rule 31 (collect token usage metadata)"
  EXIT_CODE=1
fi
say ""

# 37. Check cache.md structure
say "🔎 Checking cache.md structure..."
if [[ -f "docs/policy/cache.md" ]]; then
  say "  ✅ docs/policy/cache.md exists"
  CACHE_SECTIONS=(
    "CACHE ARCHITECTURE"
    "CACHE LIFECYCLE"
    "CACHE USAGE RULES"
    "REPOSITORY MAP"
  )
  MISSING_CACHE_SECTIONS=0
  for section in "${CACHE_SECTIONS[@]}"; do
    if grep -q "$section" docs/policy/cache.md; then
      say "  ✅ $section section found"
    else
      err "  ❌ $section section missing"
      MISSING_CACHE_SECTIONS=1
    fi
  done
  if [[ "$MISSING_CACHE_SECTIONS" -eq 1 ]]; then
    EXIT_CODE=1
  fi
else
  err "  ❌ docs/policy/cache.md missing"
  EXIT_CODE=1
fi
say ""

# 38. Check spawn-templates.md for CACHE CONTEXT references
say "🔎 Checking spawn-templates.md for CACHE CONTEXT references..."
CACHE_CONTEXT_COUNT=$(grep -c "CACHE CONTEXT (pre-loaded stable context — do NOT re-read unless changed):" docs/policy/spawn-templates.md || true)
if [[ "$CACHE_CONTEXT_COUNT" -ge 6 ]]; then
  say "  ✅ Found $CACHE_CONTEXT_COUNT CACHE CONTEXT references (minimum 6 expected)"
else
  err "  ❌ Found only $CACHE_CONTEXT_COUNT CACHE CONTEXT references (minimum 6 expected)"
  EXIT_CODE=1
fi
say ""

# 39. Check cache.sh for Phase 3.4 hardening functions
say "🔎 Checking cache.sh for Phase 3.4 hardening functions..."
CACHE_SH_FILE=".claude/scripts/cache.sh"
if [[ -f "$CACHE_SH_FILE" ]]; then
  HARDENING_FUNCS=("cache_lock" "cache_unlock" "cache_warm" "cache_gc" "decision_memory_record" "decision_memory_stats")
  MISSING_FUNCS=0
  for func in "${HARDENING_FUNCS[@]}"; do
    if grep -q "$func()" "$CACHE_SH_FILE"; then
      say "  ✅ $func function found"
    else
      err "  ❌ $func function missing"
      MISSING_FUNCS=1
    fi
  done
  if [[ "$MISSING_FUNCS" -eq 1 ]]; then
    EXIT_CODE=1
  fi
else
  err "  ❌ cache.sh missing"
  EXIT_CODE=1
fi
say ""

# 40. Check install.sh for cache subsystem initialization
say "🔎 Checking install.sh for cache subsystem initialization..."
if grep -q "Cache subsystem initialization" install.sh; then
  say "  ✅ install.sh contains cache subsystem initialization section"
  if grep -q "decision_memory" install.sh; then
    say "  ✅ install.sh creates decision_memory table"
  else
    err "  ❌ install.sh missing decision_memory table creation"
    EXIT_CODE=1
  fi
else
  err "  ❌ install.sh missing cache subsystem initialization section"
  EXIT_CODE=1
fi
say ""

# 41. Check cache.md for Decision Memory section
say "🔎 Checking cache.md for Decision Memory documentation..."
if grep -q "## DECISION MEMORY" docs/policy/cache.md; then
  say "  ✅ cache.md contains DECISION MEMORY section"
  if grep -q "decision_memory_record" docs/policy/cache.md; then
    say "  ✅ cache.md documents decision_memory_record function"
  else
    err "  ❌ cache.md missing decision_memory_record documentation"
    EXIT_CODE=1
  fi
  if grep -q "decision_memory_stats" docs/policy/cache.md; then
    say "  ✅ cache.md documents decision_memory_stats function"
  else
    err "  ❌ cache.md missing decision_memory_stats documentation"
    EXIT_CODE=1
  fi
else
  err "  ❌ cache.md missing DECISION MEMORY section"
  EXIT_CODE=1
fi
say ""

# 42. Check spawn-templates.md for DECISION MEMORY CONTEXT
say "🔎 Checking spawn-templates.md for DECISION MEMORY CONTEXT..."
if grep -q "DECISION MEMORY CONTEXT" docs/policy/spawn-templates.md; then
  say "  ✅ spawn-templates.md contains DECISION MEMORY CONTEXT reference"
else
  err "  ❌ spawn-templates.md missing DECISION MEMORY CONTEXT reference"
  EXIT_CODE=1
fi
say ""

# 43. Check cache-hooks.sh exists with required functions
say "🔎 Checking cache-hooks.sh for auto-invalidation hooks..."
CACHE_HOOKS_FILE=".claude/scripts/cache-hooks.sh"
if [[ -f "$CACHE_HOOKS_FILE" ]]; then
  say "  ✅ $CACHE_HOOKS_FILE exists"
  HOOK_FUNCS=("cache_invalidate_for_write" "cache_invalidate_for_policy_change" "cache_invalidate_for_git_head_change")
  MISSING_HOOKS=0
  for func in "${HOOK_FUNCS[@]}"; do
    if grep -q "${func}()" "$CACHE_HOOKS_FILE"; then
      say "  ✅ $func function found"
    else
      err "  ❌ $func function missing"
      MISSING_HOOKS=1
    fi
  done
  if [[ "$MISSING_HOOKS" -eq 1 ]]; then
    EXIT_CODE=1
  fi
else
  err "  ❌ $CACHE_HOOKS_FILE missing"
  EXIT_CODE=1
fi
say ""

# 44. Check cached-tools.md exists
say "🔎 Checking cached-tools.md existence..."
if [[ -f "docs/policy/cached-tools.md" ]]; then
  say "  ✅ docs/policy/cached-tools.md exists"
  CACHED_TOOL_SECTIONS=("CACHED TOOL WRAPPERS" "SAFETY CONSTRAINTS" "TTL DEFAULTS")
  MISSING_CT_SECTIONS=0
  for section in "${CACHED_TOOL_SECTIONS[@]}"; do
    if grep -q "$section" docs/policy/cached-tools.md; then
      say "  ✅ $section section found"
    else
      err "  ❌ $section section missing"
      MISSING_CT_SECTIONS=1
    fi
  done
  if [[ "$MISSING_CT_SECTIONS" -eq 1 ]]; then
    EXIT_CODE=1
  fi
else
  err "  ❌ docs/policy/cached-tools.md missing"
  EXIT_CODE=1
fi
say ""

# 45. Check CLAUDE.md references cached-tools.md
say "🔎 Checking CLAUDE.md for cached-tools.md reference..."
if grep -q "docs/policy/cached-tools.md" CLAUDE.md; then
  say "  ✅ CLAUDE.md references docs/policy/cached-tools.md"
else
  err "  ❌ CLAUDE.md missing reference to docs/policy/cached-tools.md"
  EXIT_CODE=1
fi
say ""

# 46. Check spawn-templates.md for CACHED TOOL POLICY references
say "🔎 Checking spawn-templates.md for CACHED TOOL POLICY..."
CACHED_TOOL_POLICY_COUNT=$(grep -c "CACHED TOOL POLICY:" docs/policy/spawn-templates.md || true)
if [[ "$CACHED_TOOL_POLICY_COUNT" -ge 3 ]]; then
  say "  ✅ Found $CACHED_TOOL_POLICY_COUNT CACHED TOOL POLICY references (minimum 3 expected: Developer, Reviewer, Tester)"
else
  err "  ❌ Found only $CACHED_TOOL_POLICY_COUNT CACHED TOOL POLICY references (minimum 3 expected)"
  EXIT_CODE=1
fi
say ""

# 47. Check orchestration.md for AUTO-INVALIDATION HOOKS section
say "🔎 Checking orchestration.md for AUTO-INVALIDATION HOOKS..."
if grep -q "AUTO-INVALIDATION HOOKS" docs/policy/orchestration.md; then
  say "  ✅ orchestration.md contains AUTO-INVALIDATION HOOKS section"
else
  err "  ❌ orchestration.md missing AUTO-INVALIDATION HOOKS section"
  EXIT_CODE=1
fi
say ""

# 48. Check cache.sh for decision_memory_summary and decision_memory_predict functions
say "🔎 Checking cache.sh for decision memory analytics functions..."
if grep -q "decision_memory_summary()" "$CACHE_SH_FILE"; then
  say "  ✅ decision_memory_summary function found"
else
  err "  ❌ decision_memory_summary function missing"
  EXIT_CODE=1
fi
if grep -q "decision_memory_predict()" "$CACHE_SH_FILE"; then
  say "  ✅ decision_memory_predict function found"
else
  err "  ❌ decision_memory_predict function missing"
  EXIT_CODE=1
fi
say ""

# 49. Check cache.md for Manager Prediction Integration
say "🔎 Checking cache.md for Manager Prediction Integration..."
if grep -q "Manager Prediction Integration" docs/policy/cache.md; then
  say "  ✅ cache.md contains Manager Prediction Integration section"
else
  err "  ❌ cache.md missing Manager Prediction Integration section"
  EXIT_CODE=1
fi
say ""

# 50. Check orchestration.md for Decision Memory Integration
say "🔎 Checking orchestration.md for Decision Memory Integration..."
if grep -q "Decision Memory Integration" docs/policy/orchestration.md; then
  say "  ✅ orchestration.md contains Decision Memory Integration section"
else
  err "  ❌ orchestration.md missing Decision Memory Integration section"
  EXIT_CODE=1
fi
say ""

# 51. Check secrets-and-env.md exists
say "🔎 Checking secrets-and-env.md existence..."
if [[ -f "docs/policy/secrets-and-env.md" ]]; then
  say "  ✅ docs/policy/secrets-and-env.md exists"
else
  err "  ❌ docs/policy/secrets-and-env.md missing"
  EXIT_CODE=1
fi
say ""

# 52. Check CLAUDE.md references secrets-and-env.md
say "🔎 Checking CLAUDE.md for secrets-and-env.md reference..."
if grep -q "docs/policy/secrets-and-env.md" CLAUDE.md; then
  say "  ✅ CLAUDE.md references docs/policy/secrets-and-env.md"
else
  err "  ❌ CLAUDE.md missing reference to docs/policy/secrets-and-env.md"
  EXIT_CODE=1
fi
say ""

# 53. Check ops-tools.md exists
say "🔎 Checking ops-tools.md existence..."
if [[ -f "docs/policy/ops-tools.md" ]]; then
  say "  ✅ docs/policy/ops-tools.md exists"
else
  err "  ❌ docs/policy/ops-tools.md missing"
  EXIT_CODE=1
fi
say ""

# 54. Check CLAUDE.md references ops-tools.md
say "🔎 Checking CLAUDE.md for ops-tools.md reference..."
if grep -q "docs/policy/ops-tools.md" CLAUDE.md; then
  say "  ✅ CLAUDE.md references docs/policy/ops-tools.md"
else
  err "  ❌ CLAUDE.md missing reference to docs/policy/ops-tools.md"
  EXIT_CODE=1
fi
say ""

# 55. Check redact.sh exists and is executable
say "🔎 Checking redact.sh script..."
if [[ -f ".claude/scripts/redact.sh" ]]; then
  say "  ✅ .claude/scripts/redact.sh exists"
  if [[ -x ".claude/scripts/redact.sh" ]]; then
    say "  ✅ redact.sh is executable"
  else
    err "  ❌ redact.sh is not executable (run: chmod +x .claude/scripts/redact.sh)"
    EXIT_CODE=1
  fi
else
  err "  ❌ .claude/scripts/redact.sh missing"
  EXIT_CODE=1
fi
say ""

# 56. Check ops wrapper scripts exist (at least 5)
say "🔎 Checking ops wrapper scripts..."
OPS_DIR=".claude/scripts/ops"
if [[ -d "$OPS_DIR" ]]; then
  say "  ✅ .claude/scripts/ops/ directory exists"
  OPS_SCRIPT_COUNT=$(find "$OPS_DIR" -maxdepth 1 -name "*.sh" -type f | wc -l | tr -d ' ')
  if [[ "$OPS_SCRIPT_COUNT" -ge 5 ]]; then
    say "  ✅ Found $OPS_SCRIPT_COUNT ops wrapper scripts (minimum 5 expected)"
  else
    err "  ❌ Found only $OPS_SCRIPT_COUNT ops wrapper scripts (minimum 5 expected)"
    EXIT_CODE=1
  fi
else
  err "  ❌ .claude/scripts/ops/ directory missing"
  EXIT_CODE=1
fi
say ""

# 57. Check .gitignore includes cache, logs, and memory directories
say "🔎 Checking .gitignore for cache/logs/memory directories..."
# Accept multiple forms: /.claude/cache/ , /.claude/cache , .claude/cache/ , .claude/cache
GITIGNORE_DIRS=("cache" "logs" "memory")
MISSING_GITIGNORE=0
for dir in "${GITIGNORE_DIRS[@]}"; do
  if grep -qE "^/?\.claude/${dir}/?\s*$" .gitignore 2>/dev/null; then
    say "  ✅ .gitignore includes .claude/${dir}"
  else
    err "  ❌ .gitignore missing .claude/${dir} (expected pattern: /.claude/${dir}/)"
    MISSING_GITIGNORE=1
  fi
done
if [[ "$MISSING_GITIGNORE" -eq 1 ]]; then
  EXIT_CODE=1
fi
say ""

# 58. Check cached-ops.sh exists and is executable
say "🔎 Checking cached-ops.sh script..."
if [[ -f ".claude/scripts/cached-ops.sh" ]]; then
  say "  ✅ .claude/scripts/cached-ops.sh exists"
  if [[ -x ".claude/scripts/cached-ops.sh" ]]; then
    say "  ✅ cached-ops.sh is executable"
  else
    err "  ❌ cached-ops.sh is not executable (run: chmod +x .claude/scripts/cached-ops.sh)"
    EXIT_CODE=1
  fi
else
  err "  ❌ .claude/scripts/cached-ops.sh missing"
  EXIT_CODE=1
fi
say ""

# 59. Check .gitignore does NOT exclude docs/ or policy files
say "🔎 Checking .gitignore does not exclude docs/ or policy files..."
MUST_NOT_IGNORE_PATTERNS=("docs/" "docs/policy/" "*.md")
INCORRECTLY_IGNORED=0
for pattern in "${MUST_NOT_IGNORE_PATTERNS[@]}"; do
  # Use fixed-string grep; filter out comments first
  if grep -v '^#' .gitignore 2>/dev/null | grep -qF "${pattern}"; then
    err "  ❌ .gitignore contains '${pattern}' — policy docs and markdown files must be tracked"
    INCORRECTLY_IGNORED=1
  else
    say "  ✅ .gitignore does not exclude ${pattern}"
  fi
done
if [[ "$INCORRECTLY_IGNORED" -eq 1 ]]; then
  EXIT_CODE=1
fi
say ""

# 60. Check .gitignore includes tags file
say "🔎 Checking .gitignore for tags file..."
if grep -qE "^/?tags\s*$" .gitignore 2>/dev/null; then
  say "  ✅ .gitignore includes tags"
else
  err "  ❌ .gitignore missing tags entry — ctags index must not be committed"
  EXIT_CODE=1
fi
say ""

# 61. Check rule count consistency (CLAUDE.md vs critical-rules.md)
say "🔎 Checking rule count consistency..."
RULE_COUNT=$(grep -cE '^\d+\. \*\*' docs/policy/critical-rules.md || true)
CLAIMED_COUNT=$(grep -oE '\d+ enforcement rules' CLAUDE.md | head -1 | grep -oE '\d+' || true)
if [[ -n "$RULE_COUNT" ]] && [[ -n "$CLAIMED_COUNT" ]] && [[ "$RULE_COUNT" == "$CLAIMED_COUNT" ]]; then
  say "  ✅ Rule count matches: $RULE_COUNT rules in critical-rules.md, CLAUDE.md claims $CLAIMED_COUNT"
else
  err "  ❌ Rule count mismatch: critical-rules.md has $RULE_COUNT rules, CLAUDE.md claims $CLAIMED_COUNT"
  EXIT_CODE=1
fi
say ""

# 62. Check tool count consistency (CLAUDE.md vs actual MCP servers)
say "🔎 Checking MCP tool count consistency..."
TOOL_COUNT=$(grep -c 'server\.tool(' .claude/mcp/server*.js 2>/dev/null | awk -F: '{s+=$2} END {print s}' || true)
TABLE_TOOL_COUNT=$(grep -cE '^\| `factory-' CLAUDE.md || true)
if [[ -n "$TOOL_COUNT" ]] && [[ -n "$TABLE_TOOL_COUNT" ]] && [[ "$TOOL_COUNT" == "$TABLE_TOOL_COUNT" ]]; then
  say "  ✅ Tool count matches: $TOOL_COUNT tools registered, CLAUDE.md table has $TABLE_TOOL_COUNT rows"
else
  err "  ❌ Tool count mismatch: $TOOL_COUNT tools registered, CLAUDE.md table has $TABLE_TOOL_COUNT rows"
  EXIT_CODE=1
fi
say ""

# 63. Check MCP server count consistency (.mcp.json vs CLAUDE.md)
say "🔎 Checking MCP server count consistency..."
MCP_JSON_COUNT=$(grep -c '"factory-' .mcp.json || true)
CLAIMED_SERVER_COUNT=$(grep -oE 'seven local MCP servers|7 servers' CLAUDE.md | head -1 | grep -oE '\d+' || echo "7")
if [[ -n "$MCP_JSON_COUNT" ]] && [[ "$MCP_JSON_COUNT" == "$CLAIMED_SERVER_COUNT" ]]; then
  say "  ✅ Server count matches: .mcp.json has $MCP_JSON_COUNT servers, CLAUDE.md claims $CLAIMED_SERVER_COUNT"
else
  err "  ❌ Server count mismatch: .mcp.json has $MCP_JSON_COUNT servers, CLAUDE.md claims $CLAIMED_SERVER_COUNT"
  EXIT_CODE=1
fi
say ""

# 64. Check VERSION file exists and has valid format
say "🔎 Checking VERSION file..."
if [[ -f "VERSION" ]]; then
  VERSION_CONTENT=$(cat VERSION)
  if [[ "$VERSION_CONTENT" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    say "  ✅ VERSION file valid: $VERSION_CONTENT"
  else
    err "  ❌ VERSION file has invalid format: $VERSION_CONTENT (expected semver format)"
    EXIT_CODE=1
  fi
else
  err "  ❌ VERSION file missing"
  EXIT_CODE=1
fi
say ""

# 65. Check policy file presence (all referenced files exist)
say "🔎 Checking all policy files are tracked..."
ACTUAL_POLICY_COUNT=$(find docs/policy -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
EXPECTED_POLICY_COUNT=${#POLICY_FILES[@]}
if [[ "$ACTUAL_POLICY_COUNT" == "$EXPECTED_POLICY_COUNT" ]]; then
  say "  ✅ Policy file count matches: $ACTUAL_POLICY_COUNT files in docs/policy, $EXPECTED_POLICY_COUNT expected"
else
  warn "  ⚠️  Policy file count mismatch: $ACTUAL_POLICY_COUNT files in docs/policy, $EXPECTED_POLICY_COUNT expected in POLICY_FILES array"
fi
say ""

# Summary
say "════════════════════════════════════════════════════════════════════════"
if [[ "$EXIT_CODE" -eq 0 ]]; then
  say "✅ All policy validations passed!"
else
  err "❌ Some validations failed — see warnings above"
fi
say "════════════════════════════════════════════════════════════════════════"

exit "$EXIT_CODE"
