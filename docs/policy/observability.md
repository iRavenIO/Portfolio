# OBSERVABILITY POLICY

## OVERVIEW

This policy defines how the Factory tracks, logs, and reports execution metrics to enable performance analysis, cost optimization, and continuous improvement. Observability data is collected passively during normal workflow execution and aggregated in the final report.

The Factory implements a lightweight token ledger system to track token usage by agent, phase, and model tier without requiring external dependencies or persistent storage.

---

## TOKEN LEDGER SYSTEM

### Purpose

The Token Ledger provides visibility into token consumption across the pipeline, enabling:
- **Cost attribution** by phase (which phases consume most tokens?)
- **Model tier analysis** (Opus vs Sonnet vs Haiku distribution)
- **Task complexity validation** (does actual usage align with LOW/MEDIUM/HIGH classification?)
- **Quota planning** (historical usage informs future quota mode decisions)

### Implementation

The Manager maintains an in-memory token ledger during each task run. After each agent completes, the Manager records:

| Field | Type | Description |
|-------|------|-------------|
| `agent` | string | Agent name (Analyst, Researcher, Architect, Developer, Reviewer, Tester, Reporter, Pre-Review, Reader) |
| `phase` | string | Phase identifier (P1, P2, P3, P4A, P4A.6, P4B, P4C, P5, P6) |
| `model` | string | Model used (opus, sonnet, haiku) |
| `iteration` | number | Loop iteration (1-5 for Phase 4 agents, 1 otherwise) |
| `tokens_input` | number | Input tokens consumed (context + prompt) |
| `tokens_output` | number | Output tokens generated (agent response) |
| `tokens_total` | number | Sum of input + output |
| `timestamp` | ISO 8601 | Agent completion time |

**Token Extraction:**
The Manager extracts token counts from the Task tool's response metadata. If metadata is unavailable, the entry is logged with `null` values and a warning note.

**Ledger Format (in-memory):**
```json
[
  {
    "agent": "Analyst",
    "phase": "P1",
    "model": "sonnet",
    "iteration": 1,
    "tokens_input": 12500,
    "tokens_output": 2300,
    "tokens_total": 14800,
    "timestamp": "2026-02-09T10:15:32Z"
  },
  {
    "agent": "Developer",
    "phase": "P4A",
    "model": "sonnet",
    "iteration": 1,
    "tokens_input": 18200,
    "tokens_output": 3100,
    "tokens_total": 21300,
    "timestamp": "2026-02-09T10:22:45Z"
  }
]
```

### Ledger Lifecycle

**Single-Task Runs:**
1. Manager initializes empty ledger at task start
2. After each agent completes, Manager appends entry to ledger
3. Reporter receives full ledger in spawn prompt (TOKEN LEDGER DATA section)
4. Reporter includes token summary in final report
5. Ledger discarded after task completes

**Multi-Task Runs:**
1. Manager initializes ledger at batch start
2. Per-task entries appended throughout execution
3. Each task's Reporter receives only that task's ledger subset
4. Batch Reporter receives full ledger spanning all tasks
5. Batch Report includes cross-task token analysis
6. Ledger discarded after batch completes

**Ledger Persistence:**
The ledger is NOT persisted to disk. It exists only in Manager memory for the current session. Historical analysis requires reading past task reports (which contain token summaries).

---

## PERFORMANCE METRICS

### Execution Time Tracking

The Manager tracks wall-clock time for each phase and overall task duration.

**Per-Phase Timing:**
- Start timestamp recorded when agent spawns
- End timestamp recorded when agent completes
- Duration = end - start (in seconds)

**Overall Task Timing:**
- Start: After Task Detection (Phase 0), before spawning Analyst
- End: After Reporter completes (Phase 5)
- Total Duration = end - start (in minutes and seconds)

**Multi-Task Timing:**
- Per-task durations tracked individually
- Batch duration = sum of all task durations + overhead
- Overhead = batch start notification + batch summary generation

**Timing Data Inclusion:**
Timing data is included in:
- Reporter spawn prompt (EXECUTION TIMING section)
- Final report (## EXECUTION METRICS section)
- Batch Report (per-task timing table + total batch duration)

---

## LOGGING SPECIFICATION

### Console Output

The Factory produces structured console output during execution:

**Phase Transitions:**
```
[MANAGER] Phase 0: Task Detection complete (mode: STANDARD, complexity: MEDIUM)
[MANAGER] Phase 1: Spawning Analyst...
[ANALYST] Analysis complete (tokens: 14800)
[MANAGER] Phase 3: Spawning Architect...
[ARCHITECT] Design complete (tokens: 28400)
[MANAGER] Phase 4: Entering implementation loop (max 5 iterations)
[DEVELOPER] Iteration 1 complete (tokens: 21300)
[REVIEWER] Review complete (verdict: APPROVED, tokens: 19200)
[TESTER] Tests complete (verdict: ALL_PASS, tokens: 8500)
[MANAGER] Phase 5: Spawning Reporter...
[REPORTER] Report written to docs/tasks/reports/TASK_REPORT.md (tokens: 6200)
```

**Format Rules:**
- Use `[AGENT_NAME]` prefix for all log lines
- Include token counts in completion messages
- Use consistent capitalization (MANAGER, ANALYST, etc.)
- Log timestamps optional (timestamps are tracked internally)

**Error Logging:**
```
[DEVELOPER] ❌ Implementation failed: syntax error in file.js
[MANAGER] Entering failure recovery (type: AGENT_RUNTIME_ERROR, iteration: 2)
[DEVELOPER] Retry with escalation (model: opus, tokens: 32100)
```

### Runner Observability

The Factory provides a lightweight POSIX sh runner script (`./cf`) that wraps commands with automatic logging and context propagation.

**Usage:**
```bash
./cf <command> [args...]
./cf claude "build the login page"
```

**Behavior:**
- Generates unique Run ID (`YYYYMMDD-HHMMSS`)
- Creates log file at `.claude/logs/run-<RUN_ID>.log`
- Exports environment variables: `CLAUDE_FACTORY_RUN_ID`, `CLAUDE_FACTORY_LOG_FILE`
- Prints banner with Run ID, log file path, and command
- Executes command with `tee` to capture stdout/stderr while preserving terminal output
- Propagates inner command exit code (uses temp file for POSIX sh compatibility)

**Log File Format:**
- All stdout and stderr from the wrapped command
- Interleaved output (preserves timing and order)
- UTF-8 encoding
- Persisted to `.claude/logs/` (gitignored)

**Environment Variables:**
- `CLAUDE_FACTORY_RUN_ID`: Unique run identifier (e.g., `20260209-143022`)
- `CLAUDE_FACTORY_LOG_FILE`: Absolute path to log file (e.g., `/path/to/repo/.claude/logs/run-20260209-143022.log`)

**Reporter Integration:**

The Reporter agent SHOULD check for `CLAUDE_FACTORY_RUN_ID` and `CLAUDE_FACTORY_LOG_FILE` environment variables and include them in the EXECUTION METRICS section of task reports:

```markdown
## EXECUTION METRICS

**Run ID**: 20260209-143022
**Log File**: .claude/logs/run-20260209-143022.log
```

If environment variables are not present (user did not use `./cf`), omit these fields.

### Report Sections

All task reports (TASK_REPORT.md, TASK_REPORT_N.md, BATCH_REPORT.md) MUST include:

**## EXECUTION METRICS**

```markdown
## EXECUTION METRICS

**Task Complexity**: MEDIUM
**Task Mode**: STANDARD
**Total Duration**: 4m 32s

**Token Usage by Phase:**
| Phase | Agent(s) | Model | Tokens (in/out/total) | Iterations |
|-------|----------|-------|------------------------|------------|
| P1 | Analyst | Sonnet | 12.5K / 2.3K / 14.8K | 1 |
| P3 | Architect | Opus | 22.1K / 6.3K / 28.4K | 1 |
| P4A | Developer | Sonnet | 18.2K / 3.1K / 21.3K | 2 |
| P4A | Developer | Sonnet | 19.1K / 2.9K / 22.0K | 2 |
| P4B | Reviewer | Opus | 15.4K / 3.8K / 19.2K | 1 |
| P4C | Tester | Sonnet | 6.8K / 1.7K / 8.5K | 1 |
| P5 | Reporter | Sonnet | 4.9K / 1.3K / 6.2K | 1 |
| **Total** | — | — | **99.0K / 21.4K / 120.4K** | **8 spawns** |

**Token Usage by Model:**
| Model | Input | Output | Total | % of Total |
|-------|-------|--------|-------|------------|
| Opus | 37.5K | 10.1K | 47.6K | 39.5% |
| Sonnet | 61.5K | 11.3K | 72.8K | 60.5% |
| Haiku | 0 | 0 | 0 | 0% |

**Loop Iterations**: 2 (Developer → Reviewer → Tester → Developer → Reviewer → Tester)

**Failure Events**: 0
```

**Batch Reports (BATCH_REPORT.md) Include:**
- Per-task token summaries (table with task title, complexity, mode, tokens)
- Aggregate token usage across all tasks
- Model tier distribution (Opus % vs Sonnet % vs Haiku %)
- Total batch duration (sum of task durations + overhead)
- Task count and success rate

---

## AUDIT TRAIL

### Git Commit Metadata

When auto-commit executes successfully, the commit message includes execution metadata:

```
Context: <TASK_MODE> | <N> iteration(s) | <REVIEWER_VERDICT>
```

This line embeds:
- Task mode classification (MICRO-CHANGE, STANDARD, VERIFICATION)
- Implementation loop iteration count (how many Developer spawns)
- Reviewer verdict (APPROVED, CHANGES_REQUESTED)

**Example:**
```
Context: STANDARD | 2 iteration(s) | APPROVED
```

This metadata enables git history analysis (e.g., "How many iterations do STANDARD tasks typically need?").

### Report Archival

All task reports are written to `docs/tasks/reports/` with timestamped filenames:

**Naming Convention:**
- Single-task: `TASK_REPORT.md` (overwrites previous)
- Multi-task: `TASK_REPORT_1.md`, `TASK_REPORT_2.md`, ..., `BATCH_REPORT.md`
- Historical reports (optional): `TASK_REPORT_YYYY_MM_DD_HHMMSS.md`

**Report Retention:**
- No automatic deletion (reports accumulate over time)
- Users may periodically archive/delete old reports
- `.gitignore` does NOT exclude `docs/tasks/reports/` (reports are tracked)

---

## TELEMETRY DATA POINTS

For each task run, the Factory collects:

| Metric | Source | Unit | Purpose |
|--------|--------|------|---------|
| Task complexity | Manager (Phase 0) | LOW/MEDIUM/HIGH | Validate budget sizing |
| Task mode | Manager (Phase 0) | MICRO/STANDARD/VERIFICATION | Track mode distribution |
| Total tokens (input) | Token ledger | number | Cost attribution |
| Total tokens (output) | Token ledger | number | Response size analysis |
| Tokens by model tier | Token ledger | number | Quota planning |
| Tokens by phase | Token ledger | number | Bottleneck identification |
| Loop iterations | Manager (Phase 4) | number | Quality loop efficiency |
| Failure events | Manager (all phases) | number | Reliability tracking |
| Total duration | Manager (start/end) | seconds | Performance monitoring |
| Files changed | Developer report | number | Scope validation |
| Auto-commit status | Reporter | boolean | Git integration reliability |

**No External Analytics:**
The Factory does NOT send telemetry to external services. All data is local and embedded in task reports.

---

## CONTINUOUS IMPROVEMENT WORKFLOW

### Report Review Cadence

Recommended review schedule:

**Weekly:**
- Review last 5-10 task reports
- Identify tasks with >3 loop iterations (investigate why)
- Check token usage vs budget allocation (are budgets too tight/loose?)
- Note any recurring failure patterns

**Monthly:**
- Aggregate token usage by phase (which phases are most expensive?)
- Compare task mode distribution (are MICRO-CHANGE tasks correctly classified?)
- Review model tier usage (Opus % vs Sonnet % — does it align with quota strategy?)
- Identify outlier tasks (HIGH complexity with LOW token usage = budget too generous)

**Quarterly:**
- Update budget blocks based on actual usage trends
- Refine task mode detection heuristics if misclassification is common
- Adjust quota mode thresholds if needed

### Feedback Loop

Observability data informs policy updates:
- If MEDIUM tasks consistently escalate to Opus in iteration 3, consider making iteration 2+ Opus-default
- If MICRO-CHANGE tasks rarely complete in 1 iteration, tighten detection heuristics
- If Reviewer token usage is consistently below budget, reduce allocations
- If Architect tokens exceed budget often, increase allocations or add pre-architect research step

---

## INTEGRATION WITH OTHER POLICIES

This policy integrates with:
- **[orchestration.md](orchestration.md)** — Budget Block System uses token ledger data for calibration
- **[spawn-templates.md](spawn-templates.md)** — TOKEN LEDGER DATA section injected into Reporter spawn prompt
- **[git-automation.md](git-automation.md)** — Auto-commit Context line embeds execution metadata
- **[workflow.md](workflow.md)** — Execution timing tracked at phase boundaries
- **[quota.md](quota.md)** — Token usage by model tier informs quota mode selection

**Cross-References:**
- Token ledger format: Section 2 of this file
- Execution metrics report format: Section 4 of this file
- Audit trail metadata: Section 5 of this file
