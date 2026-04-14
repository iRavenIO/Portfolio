# SMART ORCHESTRATION RULES (MANDATORY)

The Manager uses six interlocking mechanisms to reduce token consumption without altering the agent pipeline sequence:

## Run Preflight Bootstrap

Before any Phase 0 task detection, the Manager MUST source `.claude/scripts/run-preflight.sh` to ensure Run ID and log file environment variables are available for all downstream operations.

**Procedure:**
1. At the start of Phase 0, before task detection, execute:
   ```bash
   source .claude/scripts/run-preflight.sh
   ```
2. This script:
   - Checks if `CLAUDE_FACTORY_RUN_ID` is already set (from `./cf`)
   - If not, generates a new Run ID using `date +%Y%m%d-%H%M%S`
   - Creates `.claude/logs/` directory if missing
   - Exports `CLAUDE_FACTORY_RUN_ID` and `CLAUDE_FACTORY_LOG_FILE`
   - Warns if cache DB is missing
   - Prints confirmation to stderr
3. The script uses a double-source guard (`_RUN_PREFLIGHT_LOADED`) to safely run multiple times

**Enforcement:**
- MANDATORY for all Manager runs, whether invoked via `./cf` or direct `claude` command
- If script sourcing fails, log the error but continue (graceful degradation)
- All agents receive Run ID via spawn prompt context if available

## Evidence Pack

Before spawning the Reviewer or Tester, the Manager assembles a standardized context bundle that eliminates redundant repository searches. The Evidence Pack contains:

```
EVIDENCE PACK:

DIFF SUMMARY:
| File | Status | Lines Changed |
|------|--------|---------------|
| <path> | A/M/D/R | +N / -N |

CHANGED FILES: <comma-separated list of paths>

DELIVERABLES CHECKLIST:
- [x] <file/feature from Architect's plan> — verified present
- [x] <file/feature> — verified present
- [ ] <file/feature> — MISSING (if any)

ACCEPTANCE CRITERIA:
- <criterion 1 from Analyst>
- <criterion 2>

RELEVANT DESIGN CONTEXT:
<2-5 bullet points summarizing the Architect's key design decisions
 relevant to review/testing — NOT the full design doc>

PRE-REVIEW FINDINGS (if Pre-Review Pass ran):
1. Diff Checklist:
   - Files modified: [list]
   - Files expected but missing: [list or "None"]
   - Unexpected files: [list or "None"]
2. Policy Violations: [list or "None"]
3. Test Scope Recommendations: [list]
4. Flagged Items for Reviewer: [list with severity]
5. Low-Risk Files Confirmed: [list]
```

**Assembly rules:**
- The Manager extracts DIFF SUMMARY by calling `git_repo_diff` (or falls back to Developer's "Files Changed" section)
- DELIVERABLES CHECKLIST is built from the Architect's file structure plan (Section 2.3)
- ACCEPTANCE CRITERIA comes from the Analyst's report
- RELEVANT DESIGN CONTEXT is a compressed summary of the Architect's design (NOT a raw paste)
- PRE-REVIEW FINDINGS is ONLY included if the Pre-Review Pass ran (see `docs/policy/quota.md` Section 5); if not, omit this section entirely
- The Evidence Pack replaces ad-hoc context sections in Reviewer and Tester prompts

**Cached Assembly Optimization:**

When the Evidence Pack is assembled during the first iteration of the implementation loop, the Manager SHOULD cache it for reuse in subsequent loop iterations (if the Developer needs to fix issues and re-submit). The DIFF SUMMARY and CHANGED FILES sections MUST be regenerated on each iteration (files may change), but DELIVERABLES CHECKLIST, ACCEPTANCE CRITERIA, and RELEVANT DESIGN CONTEXT remain stable across iterations and can be reused from cache.

**Cache Integration:**
- After assembling the Evidence Pack for the first time, store stable sections (DELIVERABLES CHECKLIST, ACCEPTANCE CRITERIA, RELEVANT DESIGN CONTEXT) in cache with key `evidence_pack:<run_id>`
- On subsequent iterations (iteration > 1), retrieve cached sections and only regenerate DIFF SUMMARY and CHANGED FILES
- This reduces token consumption in the implementation loop without altering the Evidence Pack's completeness

## Pre-Review Deliverables Verification

After the Developer exits and before spawning the Reviewer, the Manager verifies implementation completeness:

1. Parse the "Files Changed" section from the Developer's Implementation Report
2. Compare against the Architect's file structure plan
3. If any expected files are MISSING → re-spawn the Developer with a specific gap list (do NOT proceed to Reviewer)
4. If unexpected files appear → note them in the Evidence Pack for the Reviewer but do not block
5. Only proceed to the Reviewer when all expected deliverables are present

This is a Manager-direct action, not delegated to an agent. It prevents wasted Tier 1 review cycles on incomplete implementations.

## In-Run File Read Cache

The Manager maintains a logical cache of files already read or searched during the current task run:

- When passing context to the next agent, the Manager includes relevant file content summaries from prior agents instead of requiring re-reads
- Agents MUST NOT re-read files that were already read by a prior agent in the same run UNLESS `git_repo_diff` shows those files changed since the last read
- Bootstrap context (agent .md files, CLAUDE.md) is loaded once per run and never re-loaded
- The cache resets at task boundaries in multi-task runs
- This reduces redundant file I/O and token consumption across agents

**FILES_ALREADY_READ prompt injection format:**

The Manager tracks all files read by agents during the current task run. Before spawning each agent, the Manager includes:

```
FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
path/to/file1.md, path/to/file2.js, path/to/file3.ts
```

If no files have been read yet in the current run, the Manager should inject:

```
FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
None yet
```

## Test Level System

Within the existing STAGED BUILD POLICY, MILESTONE tasks are further sub-classified to control test scope:

| Test Level | Criteria | Tester Behavior |
|------------|----------|-----------------|
| **SMOKE** | Low-complexity MILESTONE changes: adding a new utility function, simple API endpoint, straightforward bug fix with clear scope | Lint + typecheck + targeted unit tests for changed functions only. Skip integration and e2e. |
| **FULL** | High-complexity MILESTONE changes: architectural changes, security patches, multi-component features, schema changes | Complete test suite (unit + integration + e2e as applicable). |

**Classification rules:**
- The Manager classifies during Phase 0 as `SMALL`, `MILESTONE/SMOKE`, or `MILESTONE/FULL`
- Default to `MILESTONE/FULL` when ambiguous
- The classification is passed to the Tester in the Phase 4C prompt as `TASK CLASSIFICATION: <SMALL | MILESTONE/SMOKE | MILESTONE/FULL>`
- This coexists with the existing STAGED BUILD POLICY — `SMALL` still means lint+typecheck only

## Smart ctags Refresh

An optimization to the FRESH TAGS INDEXING POLICY:

- If the Developer's Implementation Report "Files Changed" section lists zero files (no creates, modifies, or deletes), skip the post-Developer ctags refresh
- This is safe because no symbols changed, so the existing index is still current
- The Manager verifies this via pre-review deliverables verification (if that check finds no discrepancies, it confirms zero changes)
- See the amended FRESH TAGS INDEXING POLICY table for full details

## TASK COMPLEXITY CLASSIFICATION (MANDATORY)

During Phase 0, after classifying the task as SMALL or MILESTONE per the Staged Build Policy, the Manager MUST classify the task's complexity to derive the Budget Block for all agents.

### Complexity Levels

| Level | Criteria | Examples |
|-------|----------|----------|
| **LOW** | Config changes, documentation updates, typo fixes, single-file edits, lint fixes, dependency bumps, simple renames | Update .gitignore, fix typos in README, bump package version, add config flag |
| **MEDIUM** | Multi-file features, bug fixes, refactors with logic changes, API additions, straightforward implementations | Add new API endpoint, fix bug across 2-3 files, refactor function with tests, add new utility module |
| **HIGH** | Architectural changes, security patches, schema migrations, cross-cutting concerns, major refactors, anything touching core system behavior | Database schema change, authentication overhaul, pipeline restructure, security vulnerability fix, multi-agent coordination change |

**Classification rules:**
- The Manager MUST classify every task during Phase 0, after Staged Build classification and before Runbook Lookup
- Default to **MEDIUM** when complexity is ambiguous or the scope is unclear
- Complexity classification is orthogonal to Staged Build classification (SMALL vs MILESTONE)
  - Example: A typo fix in documentation is `SMALL` build + `LOW` complexity
  - Example: A security patch is `MILESTONE` build + `HIGH` complexity
- For multi-task prompts, each task is classified independently in the Execution Plan
- The complexity drives the Budget Block (see next section)

## BUDGET BLOCK SYSTEM (MANDATORY)

The Budget Block is a standardized resource constraint template that the Manager injects into every agent spawn prompt. It governs three dimensions of agent resource consumption: tool usage, file reads, and output verbosity.

### Budget Block Template

```
BUDGET BLOCK:
  Complexity: LOW | MEDIUM | HIGH
  Tools: tiny | small | medium | large
  File Reads: tiny | small | medium | large
  Output Detail: short | medium | detailed
```

### Complexity-to-Budget Default Mapping

| Complexity | Tools | File Reads | Output Detail |
|------------|-------|------------|---------------|
| **LOW** | tiny | tiny | short |
| **MEDIUM** | small | medium | medium |
| **HIGH** | medium | large | detailed |

**Manager override authority:**
- The Manager MAY override the default budget based on agent role
  - Example: Reviewer always gets at least `medium` tools budget (needs code_search_rg + code_index_ctags + git_repo_diff)
  - Example: Reader always gets at least `small` file_reads budget (reading is its purpose)
- Overrides should be rare and justified by the agent's core responsibilities

### Budget Numeric Guidance

Agents use this table to interpret budget labels:

| Label | Tool Calls | File Reads | Output Detail |
|-------|-----------|------------|---------------|
| **tiny** | 1-3 | 0-1 files | Bullet points only; minimal prose; code references (file:line) instead of inlined blocks |
| **small** | 4-8 | 2-4 files | Structured sections with bullet points; brief code snippets where necessary |
| **medium** | 9-15 | 5-10 files | Comprehensive sections with tables, lists, code references; moderate detail |
| **large** | 16+ | 11+ files | Full detailed report with all supporting evidence; inlined code blocks when they are the deliverable |

**Interpretation rules:**
- These are **guidance ranges**, not hard limits
- Agents should plan their work to stay within budget
- If an agent determines the budget is genuinely insufficient to complete its task correctly, it MUST escalate (see below)
- "Tool calls" includes all MCP tool invocations and Bash commands that perform discovery (searches, diffs, status checks)
- "File reads" means full or partial file reads via the Read tool (does NOT count search results or tool outputs that incidentally show file snippets)

### Budget Enforcement

**Agent responsibilities:**
1. **Pre-flight check:** Before starting work, review the Budget Block and plan tool usage and file reads accordingly
2. **Self-monitoring:** Track tool calls and file reads during execution
3. **Escalation:** If the budget is insufficient, output:
   ```
   NEEDS_MANAGER_ACTION: Budget exceeded — <specific reason and what additional budget is needed>
   ```
   Then stop. Do NOT silently exceed limits.

**Manager responsibilities:**
1. **Injection:** Include the Budget Block in every agent spawn prompt (after MCP TOOL RULES, before task instructions)
2. **Escalation handling:** When an agent reports budget exceeded:
   - Review the reason and current progress
   - MAY grant a one-level increase (tiny→small, small→medium, medium→large)
   - MAY re-scope the task to fit within budget
   - MUST NOT grant unlimited budget or skip enforcement
3. **Verification:** After each agent completes, check that output respects the `Output Detail` budget

### Budget Block Injection Example

```
MCP TOOL RULES (you MUST follow these):
Allowed:
  ✅ `code_search_rg` — discover files, patterns, code context
  ✅ `code_index_ctags` — ONLY if symbol-level navigation is required
Forbidden:
  ❌ `research_search_web` ❌ `notify_say`
Before using any tool, state: "Tools I plan to use: ..."

BUDGET BLOCK:
  Complexity: MEDIUM
  Tools: small
  File Reads: medium
  Output Detail: medium
You MUST stay within these budget limits. If you need to exceed them,
output: NEEDS_MANAGER_ACTION: Budget exceeded — <what and why>

FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
CLAUDE.md, .claude/agents/analyst.md

<Task-specific instructions follow...>
```

### Budget Escalation Protocol

When an agent outputs `NEEDS_MANAGER_ACTION: Budget exceeded — <reason>`:

1. **Manager reviews reason:** Is the request legitimate? Does the task genuinely require more resources?
2. **Manager decides:**
   - **Grant one-level increase** (e.g., small→medium for tools) and re-spawn the agent with adjusted Budget Block
   - **Re-scope task** (narrow the agent's objective to fit within budget) and re-spawn with clarified instructions
   - **Deny** (if the request is due to inefficient approach) and re-spawn with guidance on how to stay within budget
3. **One escalation per agent per iteration:** An agent may escalate once. If it escalates again after a grant, the Manager should re-scope or re-assign.

---

## OPS TOOL CONTEXT PASSING

When the Manager detects a task involving infrastructure operations (Kubernetes, Argo CD, Argo Workflows, PostgreSQL, Supabase), it MUST include an OPS CONTEXT block in agent spawn prompts to provide operational parameters and safety reminders.

### Detection Criteria

The Manager classifies a task as requiring ops context if the task description or Analyst output mentions:
- Kubernetes, kubectl, k8s, pods, deployments, namespaces, services
- Argo CD, ArgoCD, GitOps, application sync
- Argo Workflows, workflows, pipeline execution
- PostgreSQL, psql, database queries, schema changes
- Supabase, backend operations, migrations

### OPS CONTEXT Block Format

The Manager injects this block into Analyst, Developer, Reviewer, Tester, and Reporter prompts when ops context is needed:

```
OPS CONTEXT (if task involves infrastructure operations):
If the task involves Kubernetes, Argo CD, Argo Workflows, PostgreSQL, or Supabase,
the Manager will include this context block:
  Cluster: <k8s cluster name/context>
  Namespace: <default namespace for this task>
  App Names: <relevant Argo CD apps>
  Database: <database name if applicable>
  Dry-Run Default: TRUE (all WRITE/INFRASTRUCTURE operations default to dry-run)
  Permission Tiers: READ (no confirmation) | WRITE (--confirm) | EXECUTE (--confirm) | INFRASTRUCTURE (--confirm --force)
  See docs/policy/ops-tools.md and docs/policy/secrets-and-env.md for full rules.
```

### Context Sources

The Manager derives ops context from:
1. **User prompt** — If the user specifies cluster/namespace/app/database, use those values
2. **Repository defaults** — Check for `.claude/config/ops-defaults.yaml` (if it exists)
3. **Task classification** — Default to conservative scopes (e.g., namespace=default, dry-run=true)

**Fallback behavior:**
- If cluster/namespace/app/database are not specified, omit those fields from the OPS CONTEXT block
- Always include Dry-Run Default and Permission Tiers reminders

### Safety Reminders per Agent

**Developer:**
- MUST NOT use --confirm or --force flags
- All WRITE/EXECUTE/INFRASTRUCTURE operations run in dry-run mode ONLY
- MUST include "CONFIRMATION" section listing exact commands for execution

**Reviewer:**
- MUST verify Developer did not use --confirm or --force
- MUST check scope correctness (namespace, app name, database)
- MUST flag ops actions requiring human review

**Tester:**
- MUST verify dry-run outputs are valid
- MUST NOT execute ops commands with --confirm
- Test validation scripts/health checks only

**Reporter:**
- MUST include "Ops Actions Summary" when ops wrappers were used
- MUST list exact commands requiring confirmation
- MUST reference audit log path

### Cross-References

- Permission tier definitions: `docs/policy/ops-tools.md`
- Dry-run defaults: `docs/policy/ops-tools.md` Section "Safety Controls"
- Audit logging: `docs/policy/ops-tools.md` Section "Audit Logging"
- Secret redaction: `docs/policy/secrets-and-env.md`

---

## FAILURE RECOVERY CROSS-REFERENCE

When agents fail, produce incomplete output, or validation/review gates fail during the implementation loop, the Manager MUST consult `docs/policy/failure-recovery.md` for structured recovery actions. That policy defines:

- **Failure Type Taxonomy** — Five failure categories (TOOL_FAILURE, AGENT_RUNTIME_ERROR, PARTIAL_OUTPUT, VALIDATION_FAILURE, REVIEW_REJECTION) with detection criteria
- **Manager Recovery Matrix** — Deterministic recovery actions for each failure type
- **Adaptive Model Escalation** — Three escalation rules that automatically upgrade Developer spawns based on iteration count, failure history, or task complexity

The failure recovery policy integrates tightly with the orchestration rules in this document — Evidence Pack assembly, deliverables verification, and budget enforcement remain active during recovery attempts.

---

## ARCHITECT CONFIRMATION GATE

For certain high-risk tasks, the Manager pauses after the Architect phase and requires explicit confirmation before proceeding to implementation. This gate prevents wasted implementation cycles when design clarity is uncertain.

### Trigger Conditions

The Architect Confirmation Gate activates when **ALL** of these conditions are met:

1. **Task mode:** STANDARD (not MICRO-CHANGE or VERIFICATION)
2. **Complexity:** HIGH
3. **Ambiguity markers:** The Architect's Technical Design Document contains any of these phrases:
   - "This is one possible approach"
   - "Alternative considered"
   - "Trade-off"
   - "Unclear from requirements"
   - "Assumption:"
   - "May require"
   - "Should be confirmed"

### Gate Behavior

When triggered:

1. **Manager detects ambiguity markers** by scanning the Architect's output for the phrases above
2. **Manager outputs confirmation request:**
   ```
   ARCHITECT CONFIRMATION GATE TRIGGERED

   The Architect has flagged design ambiguity or trade-offs requiring confirmation:

   <paste relevant sections from Technical Design Document>

   Do you approve this design approach?
   - Reply "yes" or "approved" to proceed with implementation
   - Reply with changes/clarifications to re-run Architect with updated requirements
   - Reply "cancel" to abort this task
   ```
3. **Manager waits for user response** (blocks pipeline progression)
4. **Manager processes response:**
   - "yes" / "approved" → proceed to Phase 4 (Implementation Loop)
   - Changes/clarifications → re-spawn Architect with user feedback appended to prompt
   - "cancel" → skip to Phase 5 (Reporter) with "Task cancelled by user" status

### Integration with Multi-Task Runs

In multi-task runs, the gate applies per-task:
- If Task 2 triggers the gate, the pipeline pauses after Task 2's Architect phase
- The user confirms or rejects before Task 2's implementation begins
- Other tasks are not affected

### Bypass

The gate can be bypassed by setting environment variable:
```
CLAUDE_FACTORY_SKIP_CONFIRMATION=1
```

When bypassed, the Manager logs: "Architect Confirmation Gate would have triggered but is bypassed by environment variable."

---

## OPS MODE GATE

For certain low-risk operational tasks, the Manager may bypass the Architect phase entirely and proceed directly from Analyst to implementation. This gate accelerates simple operations that have well-established patterns and do not require design exploration.

### Trigger Conditions

The Ops Mode Gate activates when **ALL** of these conditions are met:

1. **Task mode:** MICRO-CHANGE or VERIFICATION
2. **Complexity:** LOW
3. **Scope:** The task involves one of these patterns:
   - Config file updates (package.json, .gitignore, tsconfig.json, etc.)
   - Documentation fixes (typos, formatting, link updates)
   - Dependency version bumps (no breaking changes)
   - Environment variable additions
   - Lint rule changes
   - Simple renames or moves with no logic changes

### Gate Behavior

When triggered:

1. **Manager detects ops pattern** by analyzing task description and Analyst output
2. **Manager skips Phase 3 (Architect)** and proceeds directly to Phase 4 (Implementation Loop)
3. **Manager injects simplified context into Developer prompt:**
   ```
   OPS MODE ACTIVE: This task has been classified as a low-risk operational change.
   No architectural design is required. Proceed with implementation based on:
   - Analyst's Task Analysis Report
   - Standard patterns for this operation type
   ```
4. **Developer receives:**
   - Analyst's report (including acceptance criteria)
   - Simplified Budget Block (always LOW complexity defaults)
   - Instructions to implement directly without waiting for Architect output

### Integration with Multi-Task Runs

In multi-task runs, the gate applies per-task:
- Some tasks may use Ops Mode while others follow the full pipeline
- The Manager decides independently for each task during Phase 0
- Ops Mode tasks report "ARCHITECT: SKIPPED (Ops Mode)" in the Execution Plan

### Bypass

The gate can be bypassed by setting environment variable:
```
CLAUDE_FACTORY_FORCE_ARCHITECT=1
```

When bypassed, the Manager logs: "Ops Mode Gate would have triggered but is bypassed by environment variable."

### Safety Rules

**The Manager MUST NOT activate Ops Mode if:**
- The Analyst flags any design ambiguity or risk
- The task involves schema changes, API contracts, or authentication logic
- The task touches multiple subsystems or has unclear boundaries
- User explicitly requests design review

---

## TOKEN BUDGET CROSS-REFERENCE

The Budget Block System in this document defines *what budgets to enforce* (tools, file reads, output detail). The Token Budget System in `docs/policy/token-budget.md` defines *how token consumption maps to these budgets* and provides token allocation guidance for each complexity level.

**Integration:**
- The Manager derives Budget Blocks from task complexity classification (LOW, MEDIUM, HIGH)
- Each Budget Block label (tiny, small, medium, large) corresponds to token consumption guidance in `docs/policy/token-budget.md`
- Agents receive both the Budget Block (resource constraints) and estimated token budgets (context window guidance)

See `docs/policy/token-budget.md` for:
- Token budget numeric guidance (estimated input/output token ranges per complexity)
- Performance optimization rules (parallel tool calls, lazy loading, Evidence Pack reuse)
- Budget escalation protocol (how agents request more budget and how the Manager responds)

---

## PERFORMANCE OPTIMIZATION INTEGRATION

The orchestration rules in this document (Evidence Pack, File Read Cache, Smart ctags Refresh) are *implemented* by the Manager during task execution. The performance optimization rules in `docs/policy/token-budget.md` are *followed* by agents during their work.

**Manager responsibilities:**
- Assemble Evidence Packs to compress context (reduce Reviewer/Tester token consumption)
- Track file read cache and inject FILES_ALREADY_READ lists (prevent redundant reads)
- Skip ctags refresh when Developer's "Files Changed" section lists zero files (reduce overhead)
- Apply Test Level System to scope testing appropriately (SMOKE vs FULL)

**Agent responsibilities:**
- Follow TOOL-FIRST policy (search before read, use line-range reads for large files)
- Use parallel tool calls when possible (reduce latency)
- Apply lazy loading (progressive information discovery)
- Respect Budget Block limits and escalate when necessary

See `docs/policy/token-budget.md` for full performance optimization rules.

---

## OBSERVABILITY INTEGRATION

The Budget Block System and Smart Orchestration Rules are monitored by the observability framework defined in `docs/policy/observability.md`.

**Metrics tracked:**
- Token consumption per agent (input, output, total) — compared against Budget Block allocation
- Tool call counts per agent — validated against Budget Block's "Tools" dimension
- File read counts per agent — validated against Budget Block's "File Reads" dimension
- Loop iteration counts — compared against efficiency targets (≤2 iterations for 90% of tasks)
- Phase timing — measured for latency optimization

**Continuous improvement:**
- The Reporter includes EXECUTION METRICS section in every task report (using TOKEN LEDGER DATA and EXECUTION TIMING context)
- Budget escalation events are logged (when agents request budget increases)
- Budget violations are tracked (when agents silently exceed limits without escalating)
- Performance targets from `docs/policy/token-budget.md` are used as benchmarks for trend analysis

See `docs/policy/observability.md` for full logging specification and report format.

---

## AUTO-INVALIDATION HOOKS (MANDATORY)

The Manager MUST call cache invalidation hooks after any file-modifying operation to keep the cache consistent. The hooks are defined in `.claude/scripts/cache-hooks.sh`.

### Hook Functions

| Function | When to Call | What It Invalidates |
|----------|-------------|---------------------|
| `cache_invalidate_for_write <file_path>` | After any Write/Edit/Bash that modifies a file | File cache entry, typed policy/runbook key, repo_map (if structural), overlapping tool caches |
| `cache_invalidate_for_policy_change` | After any policy file (docs/policy/*.md) or CLAUDE.md is modified | All policy, runbook, and spawn caches; CLAUDE.md cache; repo_map |
| `cache_invalidate_for_git_head_change` | After git checkout, pull, rebase, merge, or when HEAD changes between tasks | All tool output, file, policy, runbook, core, and spawn caches; repo_map. Preserves decision_memory |

### Manager Integration Points

**After Developer Phase (Step 4A):**
```bash
source .claude/scripts/cache-hooks.sh
# For each file the Developer created/modified/deleted:
cache_invalidate_for_write "<file_path>"
```

**At Task Boundaries (Multi-Task):**
```bash
source .claude/scripts/cache-hooks.sh
cache_check_head_changed  # Auto-detects HEAD change and invalidates if needed
```

**After Policy Edits:**
```bash
source .claude/scripts/cache-hooks.sh
cache_invalidate_for_policy_change
```

**Batch Invalidation (Multiple Files):**
```bash
source .claude/scripts/cache-hooks.sh
cache_invalidate_batch "file1.md" "file2.ts" "file3.sh"
```

### Safety Rules

1. **Never delete non-factory Redis keys** — All Redis operations use the `factory:` prefix
2. **Decision memory is preserved** — `cache_invalidate_for_git_head_change` clears file/tool caches but preserves the `decision_memory` table
3. **Structural files trigger repo_map rebuild** — Changes to package.json, tsconfig.json, Dockerfile, .mcp.json, etc. invalidate the cached repo map
4. **Policy changes cascade** — A single policy file edit invalidates all spawn prompt caches (which embed policy context)

### Deterministic Behavior

Given the same file path input, the hooks produce identical invalidation patterns:
- Policy file edit -> invalidates: `file:<path>`, `policy:<name>`, all `spawn:*` keys, `repo_map`
- Source file edit -> invalidates: `file:<path>`, overlapping `tool:*` keys
- Structural file edit -> invalidates: `file:<path>`, `repo_map`, overlapping `tool:*` keys
- Git HEAD change -> invalidates: all `file:*`, `tool:*`, `policy:*`, `runbook:*`, `core:*`, `spawn:*`, `repo_map`

### Decision Memory Integration

The Manager SHOULD use `decision_memory_stats()` output to adjust orchestration decisions:
- **Task mode prediction:** If historical data shows MICRO-CHANGE tasks averaging <1.2 loops, maintain aggressive MICRO-CHANGE classification
- **Architect skip recommendation:** If architect_skip_rate > 30% and skipped tasks average fewer loops than non-skipped, recommend skipping for similar tasks
- **Token budget adjustment:** If avg_tokens consistently < 70% of budget, recommend lowering budget for that complexity level

---

This policy file is referenced by CLAUDE.md and enforced by the Manager. All agents receive Budget Blocks in their spawn prompts.
