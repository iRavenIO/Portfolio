# AGENT ROUTING AND TOOLING POLICIES

This file contains all policies governing agent model routing, MCP tool scopes, and the Reader delegation pattern.

## MCP TOOLING POLICY (MANDATORY)

The Manager controls the lifecycle and MUST NOT allow agents to break sequencing.
Sequence: ANALYST → (RESEARCHER if needed) → ARCHITECT → DEV ↔ REVIEW ↔ TEST (loop) → REPORTER.
The Manager passes ONLY the needed outputs forward.
Agents MUST stay within their tool scopes below; if an agent needs something outside scope, they must output `NEEDS_MANAGER_ACTION: <what and why>` and stop.

### ANALYST
- ✅ `code_search_rg` (preferred) — discover files, patterns, code context
- ✅ `code_index_ctags` — ONLY if symbol-level navigation is required
- ❌ `research_search_web` — forbidden unless Manager explicitly requests it
- ❌ `notify_say` — forbidden
- ❌ `ops_discover_k8s`, `ops_discover_argocd`, `ops_discover_postgres`, `ops_discover_supabase` — forbidden

### RESEARCHER
- ✅ `research_search_web` — PRIMARY tool for all web research. Provide sources/links.
- ⚠️ `code_search_rg` — only to map research findings back to code areas
- ❌ `code_index_ctags` — forbidden unless mapping requires symbol navigation
- ❌ `notify_say` — forbidden
- ❌ `ops_discover_k8s`, `ops_discover_argocd`, `ops_discover_postgres`, `ops_discover_supabase` — forbidden

### ARCHITECT
- ✅ `code_search_rg` — confirm conventions, boundaries, interfaces, patterns
- ✅ `code_index_ctags` — trace definitions/references when planning changes
- ❌ `research_search_web` — forbidden unless Manager requests claim validation
- ❌ `notify_say` — forbidden
- ❌ `ops_discover_k8s`, `ops_discover_argocd`, `ops_discover_postgres`, `ops_discover_supabase` — forbidden

### DEVELOPER
- ✅ `code_search_rg` — find all touchpoints/usages before making changes
- ✅ `code_index_ctags` — jump to definitions, understand symbol relationships
- ❌ `research_search_web` — forbidden unless Manager explicitly routes a research task
- ❌ `notify_say` — forbidden
- ❌ `ops_discover_k8s`, `ops_discover_argocd`, `ops_discover_postgres`, `ops_discover_supabase` — forbidden

### REVIEWER
- ✅ `git_repo_diff` — FIRST tool call; get structured change list before reading files
- ✅ `code_search_rg` — audit patterns, risky usage, missed call sites
- ✅ `code_index_ctags` — trace symbol flows to verify design adherence
- ❌ `research_search_web` — forbidden (reviews are repo-bound)
- ❌ `notify_say` — forbidden
- ❌ `ops_discover_k8s`, `ops_discover_argocd`, `ops_discover_postgres`, `ops_discover_supabase` — forbidden

### TESTER
- ✅ `code_search_rg` — find existing tests, framework config, integration points
- ✅ `code_index_ctags` — identify what functions/modules should be tested
- ✅ `ops_discover_k8s` — verify Kubernetes deployments (READ-tier only)
- ✅ `ops_discover_argocd` — verify Argo CD application status (READ-tier only)
- ✅ `ops_discover_postgres` — verify database schema/tables (READ-tier only)
- ✅ `ops_discover_supabase` — verify Supabase configuration (READ-tier only)
- ❌ `research_search_web` — forbidden unless Manager requests it
- ❌ `notify_say` — forbidden

### REPORTER
- ✅ `notify_say` — MUST be the final action for the voice summary
- ✅ `git_status` — required for auto-commit protocol (verify working directory state)
- ✅ `git_diff_stat` — required for auto-commit protocol (verify staged changes)
- ⚠️ `code_search_rg` / `code_index_ctags` — only if needed to accurately list files/changes
- ❌ `research_search_web` — forbidden unless Manager requests late-stage validation
- ❌ `ops_discover_k8s`, `ops_discover_argocd`, `ops_discover_postgres`, `ops_discover_supabase` — forbidden

### READER
- ✅ `code_search_rg` (preferred) — locate relevant lines/sections before reading
- ⚠️ `code_index_ctags` — only when request requires symbol-level navigation
- ❌ `research_search_web` — forbidden
- ❌ `notify_say` — forbidden
- ❌ `git_repo_diff` — forbidden (use code_search_rg for diff-related context)
- ❌ `ops_discover_k8s`, `ops_discover_argocd`, `ops_discover_postgres`, `ops_discover_supabase` — forbidden

### Manager Enforcement Checklist (DO THIS EVERY TASK)

1. Before spawning each agent, include that agent's tool rules in the prompt.
2. Require each agent to state: `Tools I plan to use: ...` (one line) before any tool calls.
3. If an agent uses a forbidden tool or drifts scope — stop that agent, re-spawn with corrected prompt.
4. Prefer `code_search_rg` first; run `code_index_ctags` only when symbol navigation is truly needed.
5. Only RESEARCHER may use `research_search_web` by default.
6. Only REPORTER and the Manager may use `notify_say`. The Manager uses it for start notification (Phase 0) and task lifecycle hooks (onTaskStart/onTaskEnd in multi-task runs). The Reporter uses it as its final action for the voice summary.
7. If any agent outputs `NEEDS_MANAGER_ACTION`, handle the request before continuing.
8. Verify each agent spawn includes a Budget Block. If missing, re-spawn with corrected prompt.

## MULTI-MODEL ROUTING POLICY

The factory uses a three-tier model routing strategy that balances cognitive capability against cost. Every agent is assigned to exactly one tier based on the complexity of its work.

| Tier | Label | Model | Cognitive Profile | Assigned Agents |
|------|-------|-------|-------------------|-----------------|
| **Tier 1** | Strong | Opus | Deep reasoning, architectural planning, nuanced judgment, complex debugging | ARCHITECT, REVIEWER |
| **Tier 2** | Mid | Sonnet | Structured analysis, implementation, testing, research, reporting | ANALYST, RESEARCHER, DEVELOPER, TESTER, REPORTER |
| **Tier 3** | Cheap | Haiku | Fast extraction, summarization, file reading, diff analysis | READER |

**Routing Principles:**

1. **Match complexity to capability.** Tier 1 agents handle tasks requiring multi-step reasoning, design trade-offs, or quality judgments that directly affect correctness. Tier 2 agents handle well-scoped tasks with clear inputs and structured outputs. Tier 3 agents handle mechanical tasks (reading, extracting, summarizing) where speed and cost matter more than depth.
2. **Never over-provision.** If a task can be accomplished at a lower tier without quality loss, use the lower tier. The Reader exists specifically to offload mechanical file reading from Tier 1 and Tier 2 agents.
3. **The Manager runs on Tier 1 (Opus)** because it makes routing decisions, handles escalations, and orchestrates the full pipeline. It is not listed in the table because it is not spawned as a subagent.

## MODEL ASSIGNMENTS (MANDATORY)

When spawning agents with the Task tool, you MUST use these model assignments. See the MULTI-MODEL ROUTING POLICY above for the rationale behind each tier.

| Agent      | Tier   | Model    | Task Tool Parameter |
|------------|--------|----------|---------------------|
| ANALYST    | Tier 2 | Sonnet   | `model="sonnet"`    |
| RESEARCHER | Tier 2 | Sonnet   | `model="sonnet"`    |
| ARCHITECT  | Tier 1 | Opus     | `model="opus"`      |
| DEVELOPER  | Tier 2 | Sonnet   | `model="sonnet"`    |
| REVIEWER   | Tier 1 | Opus     | `model="opus"`      |
| TESTER     | Tier 2 | Sonnet   | `model="sonnet"`    |
| REPORTER   | Tier 2 | Sonnet   | `model="sonnet"`    |
| READER     | Tier 3 | Haiku    | `model="haiku"`     |

**Escalation override:** The baseline Developer assignment (Sonnet) is overridden by the Adaptive Model Escalation rules in `docs/policy/failure-recovery.md` when implementation quality demands it. Three escalation rules apply specifically to Developer spawns within the implementation loop: (1) Iteration Escalation (use Opus for iterations 3+), (2) Failure-Triggered Escalation (use Opus if 2+ Developer failures in current task), (3) Complexity-Triggered Escalation (use Opus for final iteration of HIGH complexity tasks). These escalation rules take precedence over quota-mode model assignments — correctness and implementation quality take priority over cost.

## READER DELEGATION PATTERN

The Reader is a **Tier 3 utility agent** — it is NOT part of the main pipeline sequence. The Manager spawns it on-demand to offload file reading from Tier 1 and Tier 2 agents, reducing token cost.

**When to spawn the Reader:**

| Trigger | Description |
|---------|-------------|
| **NEEDS_MANAGER_ACTION** | A pipeline agent requests file content via `NEEDS_MANAGER_ACTION: Need file content from <paths>`. The Manager spawns the Reader, collects its output, and re-spawns the requesting agent with the Reader's output injected. |
| **Proactive delegation** | Before spawning a Tier 1 agent (Architect/Reviewer), the Manager may pre-read large files via the Reader and pass the summaries as context, reducing the Tier 1 agent's token consumption. |
| **Bulk file reading** | When a task requires reading many files (e.g., codebase audit, multi-file refactor analysis), the Manager spawns the Reader to produce structured summaries instead of having the pipeline agent read each file individually. |

**How to spawn the Reader:**

```
Task tool call:
  description: "Read and summarize files"
  subagent_type: "general-purpose"
  model: "haiku"
  prompt: |
    <Read .claude/agents/reader.md for your full instructions>

    REQUEST TYPE: <FILE_CONTENT | EXTRACT_CONTEXT | DIFF_SUMMARY | BULK_SUMMARY | LINE_RANGE_SEARCH>

    FILES: <list of file paths to read>
    CONTEXT: <what the requesting agent needs this content for>
    SPECIFIC QUERY: <pattern, symbol, or line range to focus on — if applicable>

    MCP TOOL RULES (you MUST follow these):
    Allowed:
      ✅ `code_search_rg` (preferred) — locate lines/sections before reading
      ⚠️ `code_index_ctags` — only if request requires symbol navigation
    Forbidden:
      ❌ `research_search_web` ❌ `notify_say` ❌ `git_repo_diff`
    Before using any tool, state: "Tools I plan to use: ..."

    TOOL-FIRST POLICY: Always search (code_search_rg) before reading files.
    Use line-range reads (offset+limit) for files over 500 lines.
```

**Rules:**
- The Reader's output is passed to the requesting agent as additional context — it is NEVER a substitute for the agent's own analysis.
- The Reader MUST NOT be spawned inside the implementation loop for writing code — it is read-only.
- The Manager decides when Reader delegation saves tokens. If a file is small (< 200 lines) and only one file is needed, the pipeline agent should read it directly instead of incurring the overhead of spawning the Reader.

---

This policy file is referenced by CLAUDE.md and enforced by the Manager. All agents must comply with these tool scope restrictions and routing rules.
