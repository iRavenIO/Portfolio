# WORKFLOW POLICY

This document defines the core workflow phases executed by the Manager for every user prompt.

---

## MANDATORY WORKFLOW

For EVERY user prompt, execute these phases IN ORDER:

### PHASE 0: TASK DETECTION

**Before spawning any agents**, analyze the user prompt to determine if it contains one task or multiple tasks.

**Heuristics for detecting multiple tasks:**

Look for any of these patterns:
- Sections named "Task A / Task B / Task C", "Phase 1 / Phase 2", "Step 1 / Step 2"
- Headers like "Execution Order", "Sub-tasks", "Roadmap"
- Numbered task lists with separate goals
- Multiple distinct objectives each with their own acceptance criteria or test cases
- Large prompts describing a batch of work or a roadmap

**If SINGLE task detected:** Classify the task as `SMALL` or `MILESTONE` (see Staged Build Policy in docs/policy/build.md). Then classify complexity as `LOW`, `MEDIUM`, or `HIGH` (see Task Complexity Classification in docs/policy/orchestration.md). Then classify task mode as `MICRO-CHANGE`, `STANDARD`, or `VERIFICATION` (see Task Mode Classification in docs/policy/task-modes.md). Derive the Budget Block from the complexity classification, with mode-specific overrides applied. Proceed to Runbook Lookup, then Start Notification, then Phase 1.

**If MULTIPLE tasks detected:** You MUST produce an Execution Plan before spawning any agents. Run Runbook Lookup for each task in the plan.

#### Task Mode Classification

After classifying task size and complexity, the Manager classifies the **task mode** to optimize pipeline execution:

**Modes:**
- **MICRO-CHANGE** - Minimal code changes requiring no design phase. Skip Architect. Reduced budgets. Max 2 loop iterations.
- **STANDARD** - Normal development work requiring full design and review. Full pipeline (current behavior).
- **VERIFICATION** - Read-only analysis tasks with no code changes. Skip Researcher, Architect, Developer. Read-only Analyst + Reporter.

**Detection heuristics** are defined in `docs/policy/task-modes.md`. The Manager applies these automatically during Phase 0.

**Pipeline adjustments per mode:**
- MICRO-CHANGE: Skip Phase 3 (Architect). Budget overrides: tiny/tiny/short. Max 2 loop iterations. Reviewer uses Sonnet tier. Tester runs lint-only.
- STANDARD: Full pipeline with standard budgets and model assignments.
- VERIFICATION: Skip Phases 2, 3, 4 (Researcher, Architect, Developer). No implementation loop. Read-only analysis.

See `docs/policy/task-modes.md` for full mode definitions and pipeline behavior matrix.

#### Runbook Lookup

After classifying the task, the Manager checks `.claude/runbooks/` for a matching runbook:

1. List files in `.claude/runbooks/*.md`
2. For each runbook, check if the title or "When to Use" criteria match the current task
3. If a match is found, record: `Applicable Runbook: .claude/runbooks/<name>.md`
4. If no match, proceed normally

The matched runbook (if any) is passed as context to the Analyst and Architect agents. See the RUNBOOK SYSTEM section in CLAUDE.md for full details.

#### Start Notification (immediately after Task Detection)

As the VERY FIRST action after Task Detection completes (whether single or multi-task), the Manager MUST send an audible kickoff notification using the MCP tool `notify_say`. If MCP is unavailable, fall back to: `say "..."` via Bash.

- **Single task:** `notify_say` → "Manager started. Beginning work on: <brief description>"
- **Multi-task:** `notify_say` → "Manager started. Beginning batch of <N> tasks. First: <brief description of task 1>"

This notification is sent by the Manager directly (not by an agent). It confirms the factory has taken control and the workflow is running.

#### Ops Context Detection

After Cache Bootstrap and before spawning the first agent (Analyst), the Manager MUST detect whether the task involves infrastructure operations:

**Detection Heuristics:**
- Scan user prompt for keywords: kubernetes, kubectl, k8s, argocd, argo, workflow, postgres, psql, supabase
- Check Analyst output (if available) for operational tooling references
- Look for .claude/scripts/ops/*.sh references in task description

**If ops context is detected:**
1. Classify operational scope (cluster, namespace, app name, database)
2. Include OPS CONTEXT block in all agent spawn prompts (see docs/policy/orchestration.md)
3. Remind agents of permission tier rules and dry-run defaults
4. Enable ops action logging in audit trail

See `docs/policy/orchestration.md` Section "Ops Tool Context Passing" for full rules.

#### Cache Bootstrap

Immediately after Run Preflight Bootstrap (before any agent spawning), the Manager MUST initialize the cache system to ensure all agents have access to pre-loaded context.

**Procedure:**
1. Source the cache library:
   ```bash
   source .claude/scripts/cache.sh
   ```
2. Initialize cache database (idempotent):
   ```bash
   cache_init
   ```
3. Prime cache with high-value context:
   ```bash
   cache_warm  # Pre-loads CLAUDE.md, policies, runbooks, repo map
   ```
4. The Manager MUST record cache operational state for inclusion in all agent spawn prompts (see CACHE PRECHECK BLOCK in spawn-templates.md)

**Cache Precheck Variables:**
- `run_id` — From `$CLAUDE_FACTORY_RUN_ID` (set by run-preflight.sh)
- `git_head` — From `git rev-parse --short HEAD`
- `cache_backend` — "sqlite+redis" if `redis-cli PING` succeeds, "sqlite" otherwise, "unavailable" if cache.sh fails to source
- `warm_stats` — Output of `cache_warm` (e.g., "12 files cached")
- `decision_memory` — Output of `decision_memory_stats()` (JSON string)

**Enforcement:**
- MANDATORY for all Manager runs (both single and multi-task)
- If cache bootstrap fails, log error and continue with `cache_backend = "unavailable"` (graceful degradation)
- Cache precheck variables are injected into ALL agent spawn prompts via the CACHE PRECHECK block (see spawn-templates.md)

#### Progressive Phase Notifications

After completing each major phase, the Manager sends progress notifications so the user receives audible status updates throughout the workflow. These notifications are sent by the Manager directly (not by an agent).

**Notification Schedule:**

| Event | Notification |
|-------|--------------|
| Phase 1 complete (Analyst) | `notify_say` → "Analysis complete." |
| Phase 2 complete (Researcher, if it ran) | `notify_say` → "Research complete." |
| Phase 3 complete (Architect) | `notify_say` → "Design complete." |
| Phase 4 complete (Implementation loop exits) | `notify_say` → "Implementation complete after <N> iterations." |
| Phase 5 complete (Reporter) | Reporter calls `notify_say` with task summary and commit status (after auto-commit, per spawn-templates.md) |

**Rules:**
- These are **Manager-initiated** calls (Phase 1-4). The Reporter handles its own notification per reporter.md.
- Send notifications **immediately after collecting agent output** for that phase.
- If MCP is unavailable, fall back to `say "..."` via Bash.
- For **multi-task runs**, send phase notifications for each task independently (e.g., "Analysis complete." is sent after each task's Analyst, not once at the end).
- **Failure handling:** If a phase fails and the Manager skips ahead or abandons a task, still send a notification: `"Phase <X> failed."` before moving on.

#### Execution Plan

When multiple tasks are detected, produce the plan internally:

```
## EXECUTION PLAN

Total tasks detected: <N>

Task 1: <short descriptive title> [SMALL|MILESTONE] [LOW|MEDIUM|HIGH] [MICRO-CHANGE|STANDARD|VERIFICATION]
Task 2: <short descriptive title> [SMALL|MILESTONE] [LOW|MEDIUM|HIGH] [MICRO-CHANGE|STANDARD|VERIFICATION]
Task 3: <short descriptive title> [SMALL|MILESTONE] [LOW|MEDIUM|HIGH] [MICRO-CHANGE|STANDARD|VERIFICATION]
...
```

Rules for the Execution Plan:
- Titles must be short and descriptive (one line each)
- Preserve the original order from the user prompt
- Do NOT start the agent pipeline yet — plan first
- Create a TaskCreate entry for each task so the user can see progress

After producing the Execution Plan (and before starting Task 1), the Manager MUST call `code_index_ctags` with `{ "mode": "full" }` to ensure the batch starts with a clean, complete symbol index. This is the only trigger that uses `mode="full"` by default.

Then execute the **Per-Task Pipeline** (Phases 1–5) sequentially for each task in order. Each task runs the FULL pipeline independently before moving to the next task. After ALL tasks complete, proceed to Phase 6 (Batch Completion Summary).

---

### PER-TASK PIPELINE (Phases 1–5)

For single-task prompts, run Phases 1–5 once.
For multi-task prompts, run Phases 1–5 once **per task**, in order.

**Failure Recovery:** During the implementation loop (Phase 4), if an agent fails, produces incomplete output, or validation/review gates fail, the Manager MUST consult `docs/policy/failure-recovery.md` for structured recovery actions and adaptive model escalation rules. The failure recovery policy defines five failure types, recovery matrices, and three Developer escalation rules (iteration-based, failure-triggered, complexity-triggered) that override baseline model assignments when implementation quality demands it.

Before starting each task in a multi-task run, update progress:
- Use `TaskUpdate` to mark the current task as `in_progress`
- The user should see: `Executing task <i>/<N>: <title>`
- **Call `code_index_ctags` with `{ "mode": "incremental" }` before Phase 1** (ensures fresh symbols for each task)
- **onTaskStart hook:** Call `notify_say` with: `"Starting task <i>/<N>: <title>"`. If MCP is unavailable, fall back to `say` via Bash. Record the current time as `task_start_time` (used for duration reporting in the onTaskEnd hook).
- After completing the task's Phase 5, **call `code_index_ctags` with `{ "mode": "incremental" }` again** (ensures the next task starts with an up-to-date index)
- **onTaskEnd hook:** Calculate `duration` as elapsed time since `task_start_time` (format: `Xm Ys`, e.g. `2m 34s`). Call `notify_say` with: `"Completed task <i>/<N> in <duration>"`. If the task failed (any unresolved issues, loop exhausted, or agent failure), use instead: `"Task <i>/<N> failed"`. If MCP is unavailable, fall back to `say` via Bash.
- Mark the task as `completed`

#### Token Budget Injection

Before spawning each agent in Phases 1-5, the Manager MUST:

1. **Compute estimated token budget** based on task complexity (LOW, MEDIUM, HIGH) using the guidance table in `docs/policy/token-budget.md`
2. **Include token budget guidance** in the agent's spawn prompt (as part of the Budget Block or as a separate note)
3. **Track token consumption** after the agent completes (collect input, output, total tokens from the agent's execution metadata)
4. **Log token usage** to the TOKEN LEDGER (see `docs/policy/observability.md`) for inclusion in the Reporter's EXECUTION METRICS section

Token budget injection format (added to Budget Block):

```
BUDGET BLOCK:
  Complexity: <LOW|MEDIUM|HIGH>
  Tools: <tiny|small|medium|large>
  File Reads: <tiny|small|medium|large>
  Output Detail: <short|medium|detailed>
  Token Budget: <10K-30K | 30K-80K | 80K-150K> (input guidance)
```

See `docs/policy/token-budget.md` for token budget allocation rules and escalation protocol.

#### Performance Timing

The Manager MUST track execution timing for each phase and agent spawn to enable performance analysis and optimization:

1. **Record phase start time** before spawning each agent (ISO 8601 timestamp)
2. **Record phase end time** after collecting agent output (ISO 8601 timestamp)
3. **Calculate phase duration** (format: `Xm Ys` for human readability, store as seconds for aggregation)
4. **Log phase timing** to the timing ledger for inclusion in the Reporter's EXECUTION METRICS section

Timing data collected:
- Task start time (Phase 0 complete)
- Per-phase timing (Analyst, Researcher if ran, Architect, Implementation Loop, Reporter)
- Per-iteration timing within the Implementation Loop (Developer, Reviewer, Tester)
- Task end time (Reporter complete)
- Total task duration (start to end)

For multi-task runs, also track:
- Batch start time (before Task 1 Phase 0)
- Per-task duration (sum of per-phase timings)
- Batch end time (after final Reporter/Batch Summary)
- Total batch duration (batch start to batch end)

See `docs/policy/observability.md` for timing data format and `docs/policy/token-budget.md` for performance targets.

---
