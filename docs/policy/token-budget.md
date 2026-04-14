# TOKEN & PERFORMANCE OPTIMIZATION ENGINE

This policy defines budget governance mechanisms that complement the observability framework in `docs/policy/observability.md`. While observability.md defines *what to measure* (token ledger, timing, metrics), this document defines *how to control* resource consumption through proactive budget enforcement.

---

## TOKEN BUDGET SYSTEM

The Token Budget System governs how much context each agent can consume during its execution. It is a core component of the Budget Block System defined in `docs/policy/orchestration.md`.

### Token Budget Allocation

Each agent is allocated a token budget based on:
1. Task complexity classification (LOW, MEDIUM, HIGH)
2. Agent role (some roles need more context)
3. Task mode (MICRO-CHANGE, STANDARD, VERIFICATION)

The Manager derives these budgets from the Budget Block's `Tools`, `File Reads`, and `Output Detail` dimensions.

### Token Budget Numeric Guidance

| Complexity | Estimated Token Budget (input) | Estimated Output Budget |
|------------|--------------------------------|-------------------------|
| **LOW** | 10K-30K tokens | 2K-5K tokens |
| **MEDIUM** | 30K-80K tokens | 5K-15K tokens |
| **HIGH** | 80K-150K tokens | 15K-40K tokens |

**Interpretation:**
- Input budget includes: agent instructions, prior agent outputs, code snippets, Evidence Pack, context files
- Output budget includes: agent's written report, code examples, tables, recommendations
- These are *guidance ranges*, not hard limits — the actual context window depends on the model (Opus: 200K, Sonnet: 200K, Haiku: 200K)
- Agents should aim to stay within their estimated budget by following the TOOL-FIRST policy, using line-range reads, and avoiding full-repository scans

### Token Budget Enforcement

**Agent responsibilities:**
1. **Pre-flight planning:** Before starting work, estimate how many files need to be read and how much output to produce
2. **Incremental loading:** Read files progressively (start with searches, then line-range reads, then full reads only when necessary)
3. **Output compression:** Use summaries and references instead of inlining large code blocks
4. **Escalation:** If the budget is insufficient, output `NEEDS_MANAGER_ACTION: Token budget exceeded — <reason>`

**Manager responsibilities:**
1. **Budget injection:** Include estimated token budget guidance in the Budget Block for each agent spawn
2. **Context trimming:** Pass summaries of prior agent outputs instead of raw full reports when possible
3. **Escalation handling:** When an agent reports token budget exceeded, review the reason and decide:
   - Grant a one-level increase (e.g., MEDIUM → HIGH complexity budget)
   - Re-scope the task to fit within budget
   - Split the task into smaller sub-tasks

---

## PERFORMANCE OPTIMIZATION RULES

These rules complement the Smart Orchestration Rules in `docs/policy/orchestration.md` to reduce latency and improve throughput.

### 1. Parallel Tool Calls

When multiple independent tool calls can run concurrently, agents MUST use parallel invocation:

```
# Good (parallel)
Read file1.ts AND Read file2.ts AND code_search_rg "pattern"

# Bad (sequential)
Read file1.ts
Read file2.ts
code_search_rg "pattern"
```

**When to parallelize:**
- Reading multiple files that don't depend on each other
- Running multiple search queries with different patterns
- Checking multiple git refs or branches

**When NOT to parallelize:**
- One tool call depends on the output of another (e.g., read file found by search)
- Order matters (e.g., git operations that modify state)

### 2. Lazy Loading

Agents MUST follow a progressive information discovery pattern:

1. **Search first** — Use `code_search_rg` to find files and patterns
2. **Line-range reads** — Read only relevant sections (offset+limit)
3. **Full reads last** — Only read entire files when the above steps are insufficient

This is codified in the TOOL-FIRST policy (see `docs/policy/build.md`).

### 3. Evidence Pack Reuse

The Manager assembles Evidence Packs (see `docs/policy/orchestration.md`) to reduce redundant context passing:

- **Before:** Reviewer reads Analyst report (5K tokens) + Architect report (10K tokens) + Developer report (8K tokens) = 23K tokens of repeated context
- **After:** Reviewer reads Evidence Pack (3K tokens) = compressed, structured context

The Evidence Pack includes:
- DIFF SUMMARY (compact table)
- CHANGED FILES (comma-separated list)
- DELIVERABLES CHECKLIST (bulleted list)
- ACCEPTANCE CRITERIA (from Analyst)
- RELEVANT DESIGN CONTEXT (2-5 bullet points from Architect)
- PRE-REVIEW FINDINGS (if Pre-Review Pass ran)

### 4. File Read Cache

The Manager tracks files already read during the current task run and passes this list to subsequent agents:

```
FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
CLAUDE.md, .claude/agents/analyst.md, docs/policy/build.md
```

Agents MUST NOT re-read these files unless:
- They need a different section (use line-range read with offset+limit)
- `git_repo_diff` shows the file changed since the last read

### 5. ctags Indexing Strategy

ctags indexing is governed by the FRESH TAGS INDEXING POLICY in `docs/policy/build.md`:

- Use `{ "mode": "incremental" }` by default (fast, diffs only)
- The MCP tool auto-escalates to full rebuild when correctness requires it (missing tags, stale state, many deletes/renames, 24h staleness)
- Skip post-Developer ctags refresh if the Developer's "Files Changed" section lists zero files

---

## PERFORMANCE METRICS & TARGETS

Performance targets for the factory:

| Metric | Target | Measurement |
|--------|--------|-------------|
| **Task Latency (SMALL)** | < 2 minutes | Task start to Reporter complete |
| **Task Latency (MILESTONE/LOW)** | < 5 minutes | Task start to Reporter complete |
| **Task Latency (MILESTONE/MEDIUM)** | < 10 minutes | Task start to Reporter complete |
| **Task Latency (MILESTONE/HIGH)** | < 20 minutes | Task start to Reporter complete |
| **Token Efficiency** | < 100K tokens per SMALL task | Sum of input + output tokens across all agents |
| **Loop Iterations** | ≤ 2 for 90% of tasks | Developer → Reviewer → Tester loop count |
| **Pre-Review Pass Rate** | ≥ 70% | Percentage of Pre-Review Pass runs that return PASS verdict |

These targets are *aspirational* and depend on task complexity, codebase size, and model availability. The Manager does NOT enforce these as hard limits, but the observability data (see `docs/policy/observability.md`) allows tracking trends over time.

---

## BUDGET ESCALATION PROTOCOL

When an agent outputs `NEEDS_MANAGER_ACTION: Budget exceeded — <reason>` or `NEEDS_MANAGER_ACTION: Token budget exceeded — <reason>`:

1. **Manager reviews reason:** Is the request legitimate? Does the task genuinely require more resources?
2. **Manager decides:**
   - **Grant one-level increase** (e.g., MEDIUM → HIGH complexity budget) and re-spawn the agent with adjusted Budget Block
   - **Re-scope task** (narrow the agent's objective to fit within budget) and re-spawn with clarified instructions
   - **Deny** (if the request is due to inefficient approach) and re-spawn with guidance on how to stay within budget
3. **One escalation per agent per iteration:** An agent may escalate once. If it escalates again after a grant, the Manager should re-scope or re-assign.

This protocol is also referenced in `docs/policy/orchestration.md` for the Budget Block System.

---

## CROSS-REFERENCES

This policy integrates with:

- **docs/policy/orchestration.md** — Budget Block System, Evidence Pack, File Read Cache, Smart ctags Refresh
- **docs/policy/build.md** — TOOL-FIRST policy, FRESH TAGS INDEXING POLICY, TOKEN USAGE POLICY
- **docs/policy/observability.md** — Token ledger, performance metrics, timing data, continuous improvement
- **docs/policy/workflow.md** — Phase definitions, lifecycle hooks, progressive notifications
- **docs/policy/spawn-templates.md** — Budget Block injection in all agent prompts

The Token Budget System is enforced by the Manager during agent spawning and monitored by the observability framework during execution.
