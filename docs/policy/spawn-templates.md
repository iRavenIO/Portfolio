# SPAWN TEMPLATES POLICY

This document contains the standardized spawn prompt templates for all agent phases. The Manager MUST use these templates when spawning agents.

---

## PHASE 1: ANALYSIS

Spawn the **Analyst** agent to understand and decompose the task.

```
Task tool call:
  description: "Analyze task requirements"
  subagent_type: "general-purpose"
  model: "sonnet"
  prompt: |
    <Read .claude/agents/analyst.md for your full instructions>

    USER TASK: <paste the user's prompt here>

    APPLICABLE RUNBOOK (if any):
    <paste runbook path and title, or "No matching runbook found">

    MCP TOOL RULES (you MUST follow these):
    Allowed:
      ✅ `code_search_rg` (preferred) — discover files, APIs, patterns, code context
      ✅ `code_index_ctags` — ONLY if symbol-level navigation is required
    Forbidden:
      ❌ `research_search_web` — do NOT use unless Manager told you to
      ❌ `notify_say`
    Before using any tool, state: "Tools I plan to use: ..."
    If you need something outside your scope, output:
      NEEDS_MANAGER_ACTION: <what is needed and why>
    and stop. If MCP is unavailable, fall back to Bash equivalents.

    BUDGET BLOCK:
      Complexity: <LOW|MEDIUM|HIGH>
      Tools: <tiny|small|medium|large>
      File Reads: <tiny|small|medium|large>
      Output Detail: <short|medium|detailed>
      Token Budget: <10K-30K | 30K-80K | 80K-150K>
    You MUST stay within these budget limits. If you need to exceed them,
    output: NEEDS_MANAGER_ACTION: Budget exceeded — <what and why>

    QUOTA SNAPSHOT (if provided):
      All-models remaining: <healthy | low | critical>
      Sonnet-only remaining: <healthy | low | critical>
      Policy mode: balanced | conserve_sonnet | conserve_opus
      Reason: <one-line justification>

    CACHE PRECHECK (operational — do NOT act on this, for Reporter metrics only):
      Run ID: <run_id>
      Git HEAD: <short_sha>
      Cache Backend: <sqlite | sqlite+redis | unavailable>
      Warm Stats: <N> files cached
      Decision Memory: <stats_json>

    CACHE CONTEXT (pre-loaded stable context — do NOT re-read unless changed):
    <Manager will inject cached policies, runbooks, and repo map here>
    Example format:
    - CLAUDE.md (cached, read 3x, last 2m ago)
    - docs/policy/orchestration.md (cached, read 5x, last 1m ago)
    - .claude/runbooks/add-mcp-server.md (cached, read 1x, last 10m ago)
    - Repository map (547 files, generated 3m ago)

    FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
    <comma-separated list of file paths, or "None yet">

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

    Examine the repository structure and existing code.
    Produce a complete Task Analysis Report following the format
    specified in your agent instructions.

    TOOL-FIRST POLICY: Always search (code_search_rg) before reading files.
    Use line-range reads (offset+limit) for files over 500 lines.
    See docs/policy/build.md for full rules.
```

Collect the Analyst's output. Check the "Research Needed" section.

<!-- MANAGER: After collecting Analyst output, call notify_say("Analysis complete.") -->

---

## PHASE 2: RESEARCH (Conditional)

**Spawn the Researcher ONLY IF** the Analyst flagged `Research Needed: YES`.

```
Task tool call:
  description: "Research technical options"
  subagent_type: "general-purpose"
  model: "sonnet"
  prompt: |
    <Read .claude/agents/researcher.md for your full instructions>

    RESEARCH QUESTIONS FROM ANALYST:
    <paste the research questions here>

    MCP TOOL RULES (you MUST follow these):
    Allowed:
      ✅ `research_search_web` — PRIMARY tool for all web research.
         Provide sources/links in your report.
      ⚠️ `code_search_rg` — only to map research findings back to code areas
    Forbidden:
      ❌ `code_index_ctags` — unless mapping requires symbol navigation
      ❌ `notify_say`
    Before using any tool, state: "Tools I plan to use: ..."
    If you need something outside your scope, output:
      NEEDS_MANAGER_ACTION: <what is needed and why>
    and stop. If MCP is unavailable, fall back to: gemini -p "query" via Bash.

    BUDGET BLOCK:
      Complexity: <LOW|MEDIUM|HIGH>
      Tools: <tiny|small|medium|large>
      File Reads: <tiny|small|medium|large>
      Output Detail: <short|medium|detailed>
      Token Budget: <10K-30K | 30K-80K | 80K-150K>
    You MUST stay within these budget limits. If you need to exceed them,
    output: NEEDS_MANAGER_ACTION: Budget exceeded — <what and why>

    QUOTA SNAPSHOT (if provided):
      All-models remaining: <healthy | low | critical>
      Sonnet-only remaining: <healthy | low | critical>
      Policy mode: balanced | conserve_sonnet | conserve_opus
      Reason: <one-line justification>

    CACHE PRECHECK (operational — do NOT act on this, for Reporter metrics only):
      Run ID: <run_id>
      Git HEAD: <short_sha>
      Cache Backend: <sqlite | sqlite+redis | unavailable>
      Warm Stats: <N> files cached
      Decision Memory: <stats_json>

    CACHE CONTEXT (pre-loaded stable context — do NOT re-read unless changed):
    <Manager will inject cached policies and repo map here>

    FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
    <comma-separated list of file paths>

    Produce a complete Research Report following the format
    specified in your agent instructions.

    TOOL-FIRST POLICY: Always search (code_search_rg) before reading files.
    Use line-range reads (offset+limit) for files over 500 lines.
    See docs/policy/build.md for full rules.
```

If research was not needed, skip directly to Phase 3.

<!-- MANAGER: If Researcher ran, call notify_say("Research complete.") -->

---

## PHASE 3: ARCHITECTURE

Spawn the **Architect** agent to design the solution.

```
Task tool call:
  description: "Design technical architecture"
  subagent_type: "general-purpose"
  model: "opus"
  prompt: |
    <Read .claude/agents/architect.md for your full instructions>

    TASK ANALYSIS REPORT:
    <paste Analyst's output>

    RESEARCH REPORT (if available):
    <paste Researcher's output or "No research was conducted">

    APPLICABLE RUNBOOK (if any):
    <paste full runbook content or "No matching runbook found">

    MCP TOOL RULES (you MUST follow these):
    Allowed:
      ✅ `code_search_rg` — confirm conventions, boundaries, interfaces, patterns
      ✅ `code_index_ctags` — trace definitions/references when planning changes
    Forbidden:
      ❌ `research_search_web` — unless Manager requests claim validation
      ❌ `notify_say`
    Before using any tool, state: "Tools I plan to use: ..."
    If you need something outside your scope, output:
      NEEDS_MANAGER_ACTION: <what is needed and why>
    and stop. If MCP is unavailable, fall back to Bash equivalents.

    BUDGET BLOCK:
      Complexity: <LOW|MEDIUM|HIGH>
      Tools: <tiny|small|medium|large>
      File Reads: <tiny|small|medium|large>
      Output Detail: <short|medium|detailed>
      Token Budget: <10K-30K | 30K-80K | 80K-150K>
    You MUST stay within these budget limits. If you need to exceed them,
    output: NEEDS_MANAGER_ACTION: Budget exceeded — <what and why>

    QUOTA SNAPSHOT (if provided):
      All-models remaining: <healthy | low | critical>
      Sonnet-only remaining: <healthy | low | critical>
      Policy mode: balanced | conserve_sonnet | conserve_opus
      Reason: <one-line justification>

    CACHE PRECHECK (operational — do NOT act on this, for Reporter metrics only):
      Run ID: <run_id>
      Git HEAD: <short_sha>
      Cache Backend: <sqlite | sqlite+redis | unavailable>
      Warm Stats: <N> files cached
      Decision Memory: <stats_json>

    CACHE CONTEXT (pre-loaded stable context — do NOT re-read unless changed):
    <Manager will inject cached policies, runbooks, and repo map here>

    FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
    <comma-separated list of file paths>

    Examine the codebase thoroughly and produce a complete
    Technical Design Document following the format specified
    in your agent instructions.

    TOOL-FIRST POLICY: Always search (code_search_rg) before reading files.
    Use line-range reads (offset+limit) for files over 500 lines.
    See docs/policy/build.md for full rules.
```

<!-- MANAGER: After collecting Architect output, call notify_say("Design complete.") -->

---

## MICRO-CHANGE MODE SPAWN VARIANTS

When task mode is classified as MICRO-CHANGE, skip Phase 3 (Architect) and use these modified spawn prompts for Phases 4-6. All other phases (Analyst, Researcher if needed, Reporter) use their standard prompts.

### DEVELOPER (MICRO-CHANGE)

```
Task tool call:
  description: "Implement micro-change"
  subagent_type: "general-purpose"
  model: "sonnet"
  prompt: |
    <Read .claude/agents/developer.md for your full instructions>

    TASK MODE: MICRO-CHANGE (no Architect design — implement directly)

    USER TASK: <paste the user's prompt here>

    ANALYST REPORT (summary):
    <paste only the "Changes Required" section from Analyst output>

    REVIEWER FEEDBACK (if any):
    <paste reviewer issues or "First implementation — no feedback yet">

    TESTER FEEDBACK (if any):
    <paste tester failures or "No test feedback yet">

    MCP TOOL RULES (you MUST follow these):
    Allowed:
      ✅ `code_search_rg` — find all touchpoints/usages before changes
      ✅ `code_index_ctags` — jump to definitions, understand symbols
    Forbidden:
      ❌ `research_search_web` ❌ `notify_say`
    Before using any tool, state: "Tools I plan to use: ..."
    If you need something outside your scope, output:
      NEEDS_MANAGER_ACTION: <what is needed and why>
    and stop. If MCP is unavailable, fall back to Bash equivalents.

    BUDGET BLOCK (MICRO-CHANGE overrides):
      Complexity: LOW (overridden to tiny budget)
      Tools: tiny (max 3 tool calls)
      File Reads: tiny (max 2 files)
      Output Detail: short
      Token Budget: 10K-30K
    You MUST stay within these budget limits. If you discover complexity
    requiring more resources, output:
      ESCALATION REQUIRED: Task is more complex than MICRO-CHANGE — needs full pipeline

    CACHE PRECHECK (operational — do NOT act on this, for Reporter metrics only):
      Run ID: <run_id>
      Git HEAD: <short_sha>
      Cache Backend: <sqlite | sqlite+redis | unavailable>
      Warm Stats: <N> files cached
      Decision Memory: <stats_json>

    FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
    <comma-separated list of file paths>

    Implement the minimal change required. No scope creep. Produce an
    Implementation Report with a "Files Changed" section.

    TOOL-FIRST POLICY: Always search (code_search_rg) before reading files.
    Use line-range reads (offset+limit) for files over 500 lines.
    See docs/policy/build.md for full rules.
```

### REVIEWER (MICRO-CHANGE)

```
Task tool call:
  description: "Review micro-change"
  subagent_type: "general-purpose"
  model: "sonnet"
  prompt: |
    <Read .claude/agents/reviewer.md for your full instructions>

    TASK MODE: MICRO-CHANGE (lightweight review — focus on correctness)

    EVIDENCE PACK:
    <paste the Evidence Pack assembled by the Manager>

    MCP TOOL RULES (you MUST follow these):
    Allowed:
      ✅ `git_repo_diff` — only if DIFF SUMMARY is empty or you need different base/head
      ✅ `code_search_rg` — audit patterns, check for missed call sites
    Forbidden:
      ❌ `code_index_ctags` — not needed for micro-changes
      ❌ `research_search_web` ❌ `notify_say`
    Before using any tool, state: "Tools I plan to use: ..."
    If MCP is unavailable, fall back to Bash equivalents.

    BUDGET BLOCK (MICRO-CHANGE overrides):
      Complexity: LOW (overridden to tiny budget)
      Tools: tiny (max 3 tool calls)
      File Reads: tiny (max 2 files)
      Output Detail: short
      Token Budget: 10K-30K
    You MUST stay within these budget limits. If you discover issues
    requiring deeper analysis, output:
      ESCALATION REQUIRED: Review found design issues — needs Architect

    CACHE PRECHECK (operational — do NOT act on this, for Reporter metrics only):
      Run ID: <run_id>
      Git HEAD: <short_sha>
      Cache Backend: <sqlite | sqlite+redis | unavailable>
      Warm Stats: <N> files cached
      Decision Memory: <stats_json>

    FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
    <comma-separated list of file paths>

    Review the change for correctness. Check:
    1. Does it match the requested change?
    2. Are there syntax errors or obvious bugs?
    3. Does it break existing patterns?

    Produce a short Code Review Report with APPROVED or CHANGES_REQUESTED verdict.

    TOOL-FIRST POLICY: Always search (code_search_rg) before reading files.
    Use line-range reads (offset+limit) for files over 500 lines.
    See docs/policy/build.md for full rules.
```

### TESTER (MICRO-CHANGE)

```
Task tool call:
  description: "Test micro-change"
  subagent_type: "general-purpose"
  model: "sonnet"
  prompt: |
    <Read .claude/agents/tester.md for your full instructions>

    TASK MODE: MICRO-CHANGE (lint-only verification)

    EVIDENCE PACK:
    <paste the Evidence Pack assembled by the Manager>

    MCP TOOL RULES (you MUST follow these):
    Allowed:
      ✅ `code_search_rg` — find lint config and test framework setup
    Forbidden:
      ❌ `code_index_ctags` ❌ `research_search_web` ❌ `notify_say`
    Before using any tool, state: "Tools I plan to use: ..."
    If MCP is unavailable, fall back to Bash equivalents.

    BUDGET BLOCK (MICRO-CHANGE overrides):
      Complexity: LOW (overridden to short budget)
      Tools: tiny (max 2 tool calls)
      File Reads: tiny (max 1 file)
      Output Detail: short
      Token Budget: 10K-30K
    You MUST stay within these budget limits.

    CACHE PRECHECK (operational — do NOT act on this, for Reporter metrics only):
      Run ID: <run_id>
      Git HEAD: <short_sha>
      Cache Backend: <sqlite | sqlite+redis | unavailable>
      Warm Stats: <N> files cached
      Decision Memory: <stats_json>

    FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
    <comma-separated list of file paths>

    YOUR TASK:
    Run lint/typecheck ONLY. Do NOT run unit, integration, or e2e tests for
    MICRO-CHANGE tasks. Verify syntax correctness and static analysis passes.

    Produce a short Test Report with ALL_PASS or FAILURES_FOUND verdict.

    TOOL-FIRST POLICY: Always search (code_search_rg) before reading files.
    See docs/policy/build.md for full rules.
```

**Loop Iteration Limit for MICRO-CHANGE:** Maximum 2 iterations (instead of 5 for STANDARD).

---

## PHASE 4: IMPLEMENTATION LOOP

This is the core build-review-test cycle. It loops until quality gates pass.

**Maximum iterations: 5**

**PRE-LOOP: REFRESH TAGS INDEX**

Before entering the loop, the Manager MUST call `code_index_ctags` with `{ "mode": "incremental" }` to ensure all agents in the loop work with an up-to-date symbol index. The tool will auto-escalate to a full rebuild if needed. If MCP is unavailable, fall back to Bash: `cd <repo_root> && git ls-files | ctags -L - -f tags --fields=+lnS --extras=+q`. If the call fails, log the error and continue.

```
── MANAGER calls code_index_ctags { "mode": "incremental" } ──

iteration = 0
reviewer_issues = null
tester_failures = null

LOOP:
  iteration += 1
  if iteration > 5: break with partial report

  ── STEP 4A: DEVELOPER ──

  Task tool call:
    description: "Implement solution"
    subagent_type: "general-purpose"
    model: "sonnet"
    prompt: |
      <Read .claude/agents/developer.md for your full instructions>

      TECHNICAL DESIGN:
      <paste Architect's output>

      REVIEWER FEEDBACK (if any):
      <paste reviewer issues or "First implementation — no feedback yet">

      TESTER FEEDBACK (if any):
      <paste tester failures or "No test feedback yet">

      MCP TOOL RULES (you MUST follow these):
      Allowed:
        ✅ `code_search_rg` — find all touchpoints/usages before changes
        ✅ `code_index_ctags` — jump to definitions, understand symbols
      Forbidden:
        ❌ `research_search_web` ❌ `notify_say`
      Before using any tool, state: "Tools I plan to use: ..."
      If you need something outside your scope, output:
        NEEDS_MANAGER_ACTION: <what is needed and why>
      and stop. If MCP is unavailable, fall back to Bash equivalents.

      BUDGET BLOCK:
        Complexity: <LOW|MEDIUM|HIGH>
        Tools: <tiny|small|medium|large>
        File Reads: <tiny|small|medium|large>
        Output Detail: <short|medium|detailed>
        Token Budget: <10K-30K | 30K-80K | 80K-150K>
      You MUST stay within these budget limits. If you need to exceed them,
      output: NEEDS_MANAGER_ACTION: Budget exceeded — <what and why>

      QUOTA SNAPSHOT (if provided):
        All-models remaining: <healthy | low | critical>
        Sonnet-only remaining: <healthy | low | critical>
        Policy mode: balanced | conserve_sonnet | conserve_opus
        Reason: <one-line justification>

      CACHE PRECHECK (operational — do NOT act on this, for Reporter metrics only):
        Run ID: <run_id>
        Git HEAD: <short_sha>
        Cache Backend: <sqlite | sqlite+redis | unavailable>
        Warm Stats: <N> files cached
        Decision Memory: <stats_json>

      CACHE CONTEXT (pre-loaded stable context — do NOT re-read unless changed):
      <Manager will inject cached policies, runbooks, and repo map here>
      Example format:
      - CLAUDE.md (cached, read 3x, last 2m ago)
      - docs/policy/orchestration.md (cached, read 5x, last 1m ago)
      - .claude/runbooks/add-mcp-server.md (cached, read 1x, last 10m ago)
      - Repository map (547 files, generated 3m ago)

      FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
      <comma-separated list of file paths>

      CACHED TOOL POLICY:
        Prefer cached wrappers for repeated operations:
        - cached_rg <pattern> [path] — instead of raw rg for second+ searches
        - cached_git_diff [base] [head] — instead of raw git diff for Evidence Pack
        - cached_file_list [pattern] — instead of raw git ls-files for scope checks
        CACHED TOOL SAFETY — Files to ignore (do NOT cache results from these):
        .env, .env.*, credentials.json, *.pem, *.key, *.p12, *.pfx
        secrets/, .secrets/, config/secrets.*
        Use tight file scopes: always provide a path argument to cached_rg.
        See docs/policy/cached-tools.md for full rules.

      Implement the solution following the Architect's plan exactly.
      If feedback was provided, fix the specific issues identified.
      No scope creep. Produce an Implementation Report.
      Your report MUST include a "Files Changed" section listing every
      file you created, modified, or deleted.

      OPS SAFETY (if using operational wrappers):
      If you invoke any .claude/scripts/ops/*.sh wrapper:
      - NEVER use --confirm or --force flags (Developer cannot execute mutating ops)
      - All WRITE/EXECUTE/INFRASTRUCTURE operations run in dry-run mode ONLY
      - Include a "CONFIRMATION" section in your output listing exact commands that
        would need confirmation for actual execution (for Tester verification)
      - Log all dry-run outputs for review
      See docs/policy/ops-tools.md for permission tier rules.

      TOOL-FIRST POLICY: Always search (code_search_rg) before reading files.
      Use line-range reads (offset+limit) for files over 500 lines.
      See docs/policy/build.md for full rules.

  ── POST-DEVELOPER: CONDITIONAL TAGS REFRESH ──

  If the Developer's Implementation Report lists ANY created, modified,
  or deleted files, the Manager MUST call code_index_ctags { "mode": "incremental" }
  before spawning the Reviewer. This ensures the Reviewer and Tester
  navigate symbols that reflect the Developer's latest changes.
  If no files were changed, skip this step.

  ── STEP 4A.5: PRE-REVIEW DELIVERABLES VERIFICATION ──

  The Manager (not an agent) verifies the Developer's output before spawning the Reviewer:
  1. Parse the "Files Changed" section from the Developer's Implementation Report
  2. Compare against the Architect's file structure plan (Section 2.3)
  3. If any expected files are MISSING → re-enter the loop (back to Developer with gap list)
  4. If unexpected files appear → note them for the Reviewer but do not block
  5. Assemble the Evidence Pack (see docs/policy/orchestration.md)
  6. If all deliverables verified → proceed to Step 4A.6 or Step 4B

  ── STEP 4A.6: PRE-REVIEW PASS (Conditional) ──

  **Trigger conditions:** See docs/policy/quota.md Section 5.1 for full trigger matrix.
  - MANDATORY when quota_mode == "conserve_opus" AND complexity == "MEDIUM"
  - OPTIONAL when quota_mode == "conserve_opus" AND complexity == "LOW"
  - DISABLED otherwise

  If Pre-Review Pass is enabled, spawn the Pre-Review Agent:

  Task tool call:
    description: "Pre-review mechanical checks"
    subagent_type: "general-purpose"
    model: "sonnet"
    prompt: |
      You are the Pre-Review Agent. Your role is to offload mechanical checks
      from the Tier 1 Reviewer, allowing the Reviewer to focus on design
      adherence and subtle issues.

      DEVELOPER'S IMPLEMENTATION REPORT:
      <paste Developer's output>

      ARCHITECT'S TECHNICAL DESIGN DOCUMENT:
      <paste Architect's output>

      EVIDENCE PACK:
      <paste Evidence Pack (DIFF SUMMARY, CHANGED FILES, DELIVERABLES CHECKLIST)>

      MCP TOOL RULES (you MUST follow these):
      Allowed:
        ✅ `code_search_rg` — audit patterns, check for prohibited usage
        ✅ `fs_read_range` — read specific line ranges for verification
      Forbidden:
        ❌ `code_index_ctags` — not needed for mechanical checks
        ❌ `research_search_web` ❌ `notify_say`
      Before using any tool, state: "Tools I plan to use: ..."

      BUDGET BLOCK:
        Complexity: <LOW|MEDIUM|HIGH>
        Tools: small
        File Reads: medium
        Output Detail: medium
        Token Budget: <10K-30K | 30K-80K | 80K-150K>
      You MUST stay within these budget limits.

      QUOTA SNAPSHOT (if provided):
        All-models remaining: <healthy | low | critical>
        Sonnet-only remaining: <healthy | low | critical>
        Policy mode: balanced | conserve_sonnet | conserve_opus
        Reason: <one-line justification>

      CACHE PRECHECK (operational — do NOT act on this, for Reporter metrics only):
        Run ID: <run_id>
        Git HEAD: <short_sha>
        Cache Backend: <sqlite | sqlite+redis | unavailable>
        Warm Stats: <N> files cached
        Decision Memory: <stats_json>

      FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
      <comma-separated list of file paths>

      YOUR TASK:
      1. **Diff Checklist**: Verify all files from the Architect's plan are present;
         flag missing or unexpected files
      2. **Policy Violations**: Check for common issues (secrets in diffs, prohibited
         patterns, missing TOOL-FIRST adherence)
      3. **Test Scope Recommendations**: Identify risky changes that need targeted tests
      4. **Severity Triage**: Categorize findings as BLOCKER (must fix before Reviewer),
         WARNING (Reviewer should scrutinize), or INFO (low-priority note)
      5. **Low-Risk Confirmation**: Identify files that match design exactly and are
         low-risk (Reviewer can skip deep read)

      OUTPUT FORMAT (you MUST use this exact format):
      ```
      PRE-REVIEW FINDINGS:

      1. Diff Checklist:
         - Files modified: <list>
         - Files expected but missing: <list or "None">
         - Unexpected files: <list or "None">

      2. Policy Violations: <list or "None">
         - <violation description> [severity: BLOCKER | WARNING | INFO]

      3. Test Scope Recommendations: <list>
         - <file or module>: <recommended test focus>

      4. Flagged Items for Reviewer: <list with severity>
         - <file>:<line>: <issue description> [severity: BLOCKER | WARNING | INFO]

      5. Low-Risk Files Confirmed: <list>
         - <file>: <reason it matches design>

      VERDICT: PASS | NEEDS_DEVELOPER_ACTION
      <If NEEDS_DEVELOPER_ACTION, list BLOCKER items that must be fixed before proceeding to Reviewer>
      ```

      TOOL-FIRST POLICY: Always search (code_search_rg) before reading files.
      Use line-range reads (offset+limit) for files over 500 lines.
      See docs/policy/build.md for full rules.

  If Pre-Review Agent returns NEEDS_DEVELOPER_ACTION → loop back to Step 4A with BLOCKER list
  If Pre-Review Agent returns PASS → include PRE-REVIEW FINDINGS in Evidence Pack and proceed to Step 4B

  ── STEP 4B: REVIEWER ──

  Task tool call:
    description: "Review implementation"
    subagent_type: "general-purpose"
    model: "opus"
    prompt: |
      <Read .claude/agents/reviewer.md for your full instructions>

      EVIDENCE PACK:
      <paste the Evidence Pack assembled by the Manager>

      PRE-REVIEW VERIFICATION: The Manager has verified all expected
      deliverables exist. You may trust the Evidence Pack's DELIVERABLES
      CHECKLIST.

      DIFF SUMMARY USAGE: You have been provided an Evidence Pack. Use
      the DIFF SUMMARY as your starting point instead of calling
      git_repo_diff independently. Only call git_repo_diff if the DIFF
      SUMMARY is empty or you need a different base/head range.

      MCP TOOL RULES (you MUST follow these):
      Allowed:
        ✅ `git_repo_diff` — only if DIFF SUMMARY is empty or you need different base/head
        ✅ `code_search_rg` — audit patterns, risky usage, missed call sites
        ✅ `code_index_ctags` — trace symbol flows, verify design adherence
      Forbidden:
        ❌ `research_search_web` ❌ `notify_say`
      Before using any tool, state: "Tools I plan to use: ..."
      If you need something outside your scope, output:
        NEEDS_MANAGER_ACTION: <what is needed and why>
      and stop. If MCP is unavailable, fall back to Bash equivalents.

      BUDGET BLOCK:
        Complexity: <LOW|MEDIUM|HIGH>
        Tools: <tiny|small|medium|large>
        File Reads: <tiny|small|medium|large>
        Output Detail: <short|medium|detailed>
        Token Budget: <10K-30K | 30K-80K | 80K-150K>
      You MUST stay within these budget limits. If you need to exceed them,
      output: NEEDS_MANAGER_ACTION: Budget exceeded — <what and why>

      QUOTA SNAPSHOT (if provided):
        All-models remaining: <healthy | low | critical>
        Sonnet-only remaining: <healthy | low | critical>
        Policy mode: balanced | conserve_sonnet | conserve_opus
        Reason: <one-line justification>

      CACHE PRECHECK (operational — do NOT act on this, for Reporter metrics only):
        Run ID: <run_id>
        Git HEAD: <short_sha>
        Cache Backend: <sqlite | sqlite+redis | unavailable>
        Warm Stats: <N> files cached
        Decision Memory: <stats_json>

      FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
      <comma-separated list of file paths>

      PRE-REVIEW CONTEXT (if Pre-Review Pass ran):
      The Pre-Review Agent has already performed mechanical checks. Review the
      PRE-REVIEW FINDINGS section in the Evidence Pack:
      - Skip deep reads of Low-Risk Files Confirmed (spot-check only)
      - Prioritize Flagged Items (especially BLOCKER and WARNING severity)
      - Validate Pre-Review findings (spot-check to ensure nothing critical was missed)
      - Focus your review on design adherence, subtle logic issues, and
        architectural concerns that require Tier 1 reasoning

      CACHED TOOL POLICY:
        Prefer cached wrappers for repeated operations:
        - cached_rg <pattern> [path] — instead of raw rg for second+ searches
        - cached_git_diff [base] [head] — instead of raw git diff for Evidence Pack
        - cached_file_list [pattern] — instead of raw git ls-files for scope checks
        CACHED TOOL SAFETY — Files to ignore (do NOT cache results from these):
        .env, .env.*, credentials.json, *.pem, *.key, *.p12, *.pfx
        secrets/, .secrets/, config/secrets.*
        Use tight file scopes: always provide a path argument to cached_rg.
        See docs/policy/cached-tools.md for full rules.

      DIFF-FIRST REVIEW PROCESS:
      1. Use the DIFF SUMMARY from the Evidence Pack as your change list.
         Only call `git_repo_diff` if the DIFF SUMMARY is missing.
      2. Triage each file as RISKY or LOW-RISK (see your agent instructions).
      3. Deep-read only RISKY files. Spot-check LOW-RISK files with `code_search_rg`.
      4. Run cross-cutting pattern audits across all changed files.
      5. Produce a Code Review Report with Diff Overview table and
         a clear APPROVED or CHANGES_REQUESTED verdict.

      OPS ACTION SAFETY REVIEW (if Developer used ops wrappers):
      If the Developer's Implementation Report includes operational wrapper invocations:
      1. Verify NO --confirm or --force flags were used by Developer
      2. Check that all WRITE/INFRASTRUCTURE operations are dry-run ONLY
      3. Verify the "CONFIRMATION" section lists exact commands for execution
      4. Confirm scope is correct (namespace, app name, database, etc.)
      5. Check for secrets exposure in command output (see secrets-and-env.md)
      6. Flag any ops actions that require human review before confirmation
      See docs/policy/ops-tools.md for safety controls.

      TOOL-FIRST POLICY: Always search (code_search_rg) before reading files.
      Use line-range reads (offset+limit) for files over 500 lines.
      See docs/policy/build.md for full rules.

  if reviewer verdict == CHANGES_REQUESTED:
    continue LOOP (back to Developer with feedback)

  ── STEP 4C: TESTER ──

  Task tool call:
    description: "Test implementation"
    subagent_type: "general-purpose"
    model: "sonnet"
    prompt: |
      <Read .claude/agents/tester.md for your full instructions>

      EVIDENCE PACK:
      <paste the Evidence Pack assembled by the Manager>

      TASK CLASSIFICATION: <SMALL | MILESTONE/SMOKE | MILESTONE/FULL>
      - If SMALL: run lint and typecheck ONLY. Skip unit/integration/e2e tests.
        Report lint/typecheck pass/fail as your verdict.
      - If MILESTONE/SMOKE: run lint, typecheck, and targeted unit tests for
        changed functions only. Skip integration and e2e tests.
      - If MILESTONE/FULL: run the full test suite (unit, integration, e2e
        as applicable). Standard testing behavior.

      MCP TOOL RULES (you MUST follow these):
      Allowed:
        ✅ `code_search_rg` — find existing tests, framework config, integration points
        ✅ `code_index_ctags` — identify what functions/modules to test
      Forbidden:
        ❌ `research_search_web` ❌ `notify_say`
      Before using any tool, state: "Tools I plan to use: ..."
      If you need something outside your scope, output:
        NEEDS_MANAGER_ACTION: <what is needed and why>
      and stop. If MCP is unavailable, fall back to Bash equivalents.

      BUDGET BLOCK:
        Complexity: <LOW|MEDIUM|HIGH>
        Tools: <tiny|small|medium|large>
        File Reads: <tiny|small|medium|large>
        Output Detail: <short|medium|detailed>
        Token Budget: <10K-30K | 30K-80K | 80K-150K>
      You MUST stay within these budget limits. If you need to exceed them,
      output: NEEDS_MANAGER_ACTION: Budget exceeded — <what and why>

      QUOTA SNAPSHOT (if provided):
        All-models remaining: <healthy | low | critical>
        Sonnet-only remaining: <healthy | low | critical>
        Policy mode: balanced | conserve_sonnet | conserve_opus
        Reason: <one-line justification>

      CACHE PRECHECK (operational — do NOT act on this, for Reporter metrics only):
        Run ID: <run_id>
        Git HEAD: <short_sha>
        Cache Backend: <sqlite | sqlite+redis | unavailable>
        Warm Stats: <N> files cached
        Decision Memory: <stats_json>

      FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
      <comma-separated list of file paths>

      PRE-REVIEW TEST RECOMMENDATIONS (if available):
      <paste test scope recommendations from Pre-Review Findings>

      Use these recommendations to prioritize your test plan, but do NOT skip
      testing areas that are not listed — the Pre-Review Agent provides guidance,
      not a complete test specification.

      CACHED TOOL POLICY:
        Prefer cached wrappers for repeated operations:
        - cached_rg <pattern> [path] — instead of raw rg for second+ searches
        - cached_file_list [pattern] — instead of raw git ls-files for scope checks
        CACHED TOOL SAFETY — Files to ignore (do NOT cache results from these):
        .env, .env.*, credentials.json, *.pem, *.key, *.p12, *.pfx
        secrets/, .secrets/, config/secrets.*
        Use tight file scopes: always provide a path argument to cached_rg.
        See docs/policy/cached-tools.md for full rules.

      Follow the TASK CLASSIFICATION above to determine your verification scope.
      Use the Evidence Pack's CHANGED FILES list to scope your testing.
      Produce a Test Report with a clear ALL_PASS or FAILURES_FOUND verdict.

      OPS ACTION VERIFICATION (if Developer used ops wrappers):
      If the Developer's report includes operational wrapper invocations:
      - Verify dry-run outputs are syntactically valid
      - Check that CONFIRMATION section commands match actual operations intended
      - DO NOT execute ops commands with --confirm (Tester cannot mutate infrastructure)
      - Test validation scripts/health checks if applicable
      See docs/policy/ops-tools.md for testing patterns.

      TOOL-FIRST POLICY: Always search (code_search_rg) before reading files.
      Use line-range reads (offset+limit) for files over 500 lines.
      See docs/policy/build.md for full rules.

  if tester verdict == FAILURES_FOUND:
    continue LOOP (back to Developer with test failures)

  BREAK — all quality gates passed

<!-- MANAGER: After loop exits, call notify_say("Implementation complete after N iterations.") -->
```

---

## PHASE 5: FINAL REPORT

After the loop exits successfully, spawn the **Reporter**.

```
Task tool call:
  description: "Generate final report"
  subagent_type: "general-purpose"
  model: "sonnet"
  prompt: |
    <Read .claude/agents/reporter.md for your full instructions>

    MCP TOOL RULES (you MUST follow these):
    Allowed:
      ✅ `notify_say` — MUST be your final action (voice summary, 2-4 sentences)
      ⚠️ `code_search_rg` / `code_index_ctags` — only if needed to list files/changes
    Forbidden:
      ❌ `research_search_web`
    Before using any tool, state: "Tools I plan to use: ..."
    If MCP is unavailable, fall back to the `say` command via Bash.

    BUDGET BLOCK:
      Complexity: <LOW|MEDIUM|HIGH>
      Tools: <tiny|small|medium|large>
      File Reads: <tiny|small|medium|large>
      Output Detail: <short|medium|detailed>
      Token Budget: <10K-30K | 30K-80K | 80K-150K>
    You MUST stay within these budget limits. If you need to exceed them,
    output: NEEDS_MANAGER_ACTION: Budget exceeded — <what and why>

    QUOTA SNAPSHOT (if provided):
      All-models remaining: <healthy | low | critical>
      Sonnet-only remaining: <healthy | low | critical>
      Policy mode: balanced | conserve_sonnet | conserve_opus
      Reason: <one-line justification>

    CACHE PRECHECK (operational — do NOT act on this, for Reporter metrics only):
      Run ID: <run_id>
      Git HEAD: <short_sha>
      Cache Backend: <sqlite | sqlite+redis | unavailable>
      Warm Stats: <N> files cached
      Decision Memory: <stats_json>

    CACHE CONTEXT (pre-loaded stable context — do NOT re-read unless changed):
    <Manager will inject cached policies and repo map here>

    FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
    <comma-separated list of file paths>

    DECISION MEMORY CONTEXT (observability):
    <Manager will inject decision_memory_summary() output here if available>
    The Manager generates this by calling: decision_memory_summary 10
    Example format:
    Based on 42 previous runs:
    - Architect skip rate: 23.8%
    - Avg loops (MICRO-CHANGE): 1.0 | (STANDARD): 1.8 | (VERIFICATION): 1.0
    - Token trend: decreasing (-12%)
    - Mode breakdown: MICRO-CHANGE:12 STANDARD:28 VERIFICATION:2

    If available, include this context in your final report's DECISION MEMORY SUMMARY section.
    Also include any recommendations from decision_memory_predict() if the Manager provided them.

    TOKEN LEDGER DATA (observability):
    <paste JSON array of token usage entries for all agents spawned in this task>
    Each entry format:
    {
      "agent": "Analyst|Researcher|Architect|Developer|Reviewer|Tester|Reporter|Pre-Review|Reader",
      "phase": "P1|P2|P3|P4A|P4A.6|P4B|P4C|P5",
      "model": "opus|sonnet|haiku",
      "iteration": <number>,
      "tokens_input": <number>,
      "tokens_output": <number>,
      "tokens_total": <number>,
      "timestamp": "<ISO 8601>"
    }
    If token metadata is unavailable, note: "Token data unavailable — metadata not captured"

    EXECUTION TIMING (observability):
    Task start: <ISO 8601 timestamp>
    Task end: <ISO 8601 timestamp>
    Total duration: <X>m <Y>s
    Per-phase timing:
    - Phase 1 (Analyst): <duration>
    - Phase 2 (Researcher): <duration> [if ran]
    - Phase 3 (Architect): <duration>
    - Phase 4 (Implementation Loop): <duration> (<N> iterations)
    - Phase 5 (Reporter): <duration>

    RUNNER CONTEXT (always available via run-preflight.sh):
    If environment variables CLAUDE_FACTORY_RUN_ID and CLAUDE_FACTORY_LOG_FILE are present, include them in the EXECUTION METRICS section of your report:
    - Run ID: <value of CLAUDE_FACTORY_RUN_ID>
    - Log File: <relative path from repo root>
    If these environment variables are not present, omit these fields.

    Compile the final report from all phase outputs:

    ANALYST OUTPUT:
    <paste>

    RESEARCHER OUTPUT (if any):
    <paste or "No research conducted">

    ARCHITECT OUTPUT:
    <paste>

    DEVELOPER OUTPUT:
    <paste final implementation report>

    REVIEWER OUTPUT:
    <paste final review — should be APPROVED>

    TESTER OUTPUT:
    <paste final test report — should be ALL_PASS>

    LOOP ITERATIONS: <number>

    TOOL-FIRST POLICY: Always search (code_search_rg) before reading files.
    Use line-range reads (offset+limit) for files over 500 lines.
    See docs/policy/build.md for full rules.

    Write the report to docs/tasks/reports/TASK_REPORT.md (create the directory if needed).

    Your report MUST include an EXECUTION METRICS section following the format
    specified in docs/policy/observability.md. Use the TOKEN LEDGER DATA and
    EXECUTION TIMING context provided above to populate token usage tables,
    model tier distribution, and timing information.

    OPS ACTIONS SUMMARY (if operational wrappers were used):
    If any agent (Developer, Tester) invoked .claude/scripts/ops/*.sh wrappers,
    include an "Ops Actions Summary" section in your report:
      Tool: <kubectl|argocd|argo|psql|supabase>
      Function: <function name from wrapper>
      Dry-Run: <true|false>
      Confirmed: <true|false> (should always be false for Developer/Tester)
      Outcome: <success|failure|validation-only>
      Audit Log: <path to ops-audit-<run_id>.log>
      Commands Requiring Confirmation: <list exact commands from CONFIRMATION section>
    This summary provides a clear audit trail of all infrastructure interactions.
    See docs/policy/ops-tools.md for audit log format.

    AUTO-COMMIT PROTOCOL:
    After writing the report, follow these steps to automatically commit the
    implementation changes (if conditions are met):

    1. Check environment variable: If CLAUDE_FACTORY_AUTO_COMMIT == "0" or "false", set commit_note = "Auto-commit disabled by environment variable" and skip to step 10
    2. Verify all quality gates passed: Reviewer == APPROVED AND Tester == ALL_PASS
       - If not, set commit_note = "Auto-commit skipped: quality gates not passed" and skip to step 10
    3. Verify files were modified: Developer's Implementation Report lists at least one file
       - If not, set commit_note = "Auto-commit skipped: no files modified" and skip to step 10
    4. Run `git status --porcelain` to check working directory state
    5. Verify only expected files changed (match Developer's Implementation Report list)
       - If extra files detected, set commit_note = "Auto-commit skipped: unexpected changes detected" and skip to step 10
    6. Check for submodule paths: run `git config --file .gitmodules --get-regexp path`
       - If any changed file is in a submodule, set commit_note = "Auto-commit skipped: submodule changes detected" and skip to step 10
    7. Check for secret patterns: verify changed files do NOT include .env, credentials.json, *.pem, *.key
       - If secrets detected, set commit_note = "Auto-commit skipped: potential credentials detected" and skip to step 10
    8. If all checks pass:
       a. Run `git add <list of changed files>` (add specific files, not `git add .`)
       b. Run `git diff --cached --name-only` to verify staging
       c. Generate commit message per docs/policy/git-automation.md format (include Context line)
       d. Run `git commit -m "$(cat <<'EOF'\n<message>\nEOF\n)"` with Co-Authored-By footer
       e. If commit succeeds:
          - Extract short hash: run `git rev-parse --short HEAD`
          - Extract type and brief summary from commit message first line
          - Set commit_note = "Committed: <short_hash> — <type>: <brief summary>"
       f. If commit fails (pre-commit hook):
          - Set commit_note = "Auto-commit failed: pre-commit hook error"
    9. If step 8 was executed but staging failed before commit:
       - Set commit_note = "Auto-commit failed: staging error"
    10. VOICE NOTIFICATION:
        Use `notify_say` to speak a summary aloud (2-4 sentences).
        Message format: "<task summary>. <commit_note>."
        Example: "Implementation complete. Added task mode classification policy. Committed: a1b2c3d — feat: Add task mode classification for cost optimization."
        Example: "Implementation complete. Fixed authentication bug. Auto-commit skipped: submodule changes detected."
        If MCP is unavailable, fall back to the `say` command via Bash.

    See docs/policy/git-automation.md for full rules and safety requirements.
```

For multi-task runs: name each per-task report `docs/tasks/reports/TASK_REPORT_<i>.md` (e.g., `docs/tasks/reports/TASK_REPORT_1.md`, `docs/tasks/reports/TASK_REPORT_2.md`).

---

## PHASE 6: BATCH COMPLETION SUMMARY (Multi-Task Only)

**Skip this phase for single-task prompts.** It only runs when Phase 0 detected multiple tasks.

After ALL tasks have completed their individual pipelines (Phases 1–5), spawn the **Reporter** one final time to produce a combined batch summary.

```
Task tool call:
  description: "Generate batch completion summary"
  subagent_type: "general-purpose"
  model: "sonnet"
  prompt: |
    <Read .claude/agents/reporter.md for your full instructions>

    MCP TOOL RULES (you MUST follow these):
    Allowed:
      ✅ `notify_say` — MUST be your final action (voice batch summary)
      ⚠️ `code_search_rg` — only if needed to verify file lists
    Forbidden:
      ❌ `research_search_web` ❌ `code_index_ctags`
    Before using any tool, state: "Tools I plan to use: ..."
    If MCP is unavailable, fall back to the `say` command via Bash.

    BUDGET BLOCK:
      Complexity: <LOW|MEDIUM|HIGH>
      Tools: <tiny|small|medium|large>
      File Reads: <tiny|small|medium|large>
      Output Detail: <short|medium|detailed>
      Token Budget: <10K-30K | 30K-80K | 80K-150K>
    You MUST stay within these budget limits. If you need to exceed them,
    output: NEEDS_MANAGER_ACTION: Budget exceeded — <what and why>

    QUOTA SNAPSHOT (if provided):
      All-models remaining: <healthy | low | critical>
      Sonnet-only remaining: <healthy | low | critical>
      Policy mode: balanced | conserve_sonnet | conserve_opus
      Reason: <one-line justification>

    CACHE PRECHECK (operational — do NOT act on this, for Reporter metrics only):
      Run ID: <run_id>
      Git HEAD: <short_sha>
      Cache Backend: <sqlite | sqlite+redis | unavailable>
      Warm Stats: <N> files cached
      Decision Memory: <stats_json>

    CACHE CONTEXT (pre-loaded stable context — do NOT re-read unless changed):
    <Manager will inject cached policies and repo map here>

    FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
    <comma-separated list of file paths>

    TOKEN LEDGER DATA (observability — full batch):
    <paste JSON array of all token usage entries across all tasks in this batch>
    This includes entries from Task 1, Task 2, ..., Task N.
    Use this data to produce aggregate token usage metrics in the batch report.

    EXECUTION TIMING (observability — full batch):
    Batch start: <ISO 8601 timestamp>
    Batch end: <ISO 8601 timestamp>
    Total batch duration: <X>m <Y>s
    Per-task timing:
    - Task 1: <duration>
    - Task 2: <duration>
    - ...
    - Task N: <duration>

    You are producing a BATCH COMPLETION SUMMARY.
    This is a combined summary across multiple tasks that were
    executed sequentially. Each task already has its own detailed
    report (docs/tasks/reports/TASK_REPORT_1.md, TASK_REPORT_2.md, etc.).

    EXECUTION PLAN:
    <paste the execution plan with all task titles>

    TOTAL TASKS: <N>
    TASKS COMPLETED SUCCESSFULLY: <count>
    TASKS WITH ISSUES: <count, if any>

    PER-TASK SUMMARIES:
    <For each task, paste a 2-3 line summary of what was accomplished
     and whether all quality gates passed>

    Write the batch summary to docs/tasks/reports/BATCH_REPORT.md (create the directory if needed).
    Include:
    - Total tasks completed
    - High-level summary of what was accomplished overall
    - Confirmation of build/test status across all tasks
    - Any unresolved issues
    - EXECUTION METRICS section (aggregate token usage, model tier distribution,
      per-task timing table, total batch duration) following the format in
      docs/policy/observability.md

    TOOL-FIRST POLICY: Always search (code_search_rg) before reading files.
    Use line-range reads (offset+limit) for files over 500 lines.
    See docs/policy/build.md for full rules.

    Then use `notify_say` to speak a final batch summary aloud.
    Example: "Batch complete. <N> tasks finished successfully. <brief overview>."
```
