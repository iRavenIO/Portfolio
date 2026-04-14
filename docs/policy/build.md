# BUILD AND TOOLING POLICIES

This file contains all policies governing the build pipeline, ctags indexing, and agent tool usage patterns.

## STAGED BUILD POLICY (MANDATORY)

The Manager classifies every task during Phase 0 to control how much verification the Tester performs.

| Classification | Criteria | Tester Behavior |
|---------------|----------|-----------------|
| **SMALL** | Config changes, documentation, lint fixes, dependency bumps, typo fixes, refactors with no logic changes, CI/CD tweaks | Lint and typecheck only. Skip unit/integration/e2e test suites. Report lint/typecheck results as the verdict. |
| **MILESTONE** | New features, bug fixes, API changes, schema changes, security patches, refactors that alter control flow, anything touching business logic | See SMART ORCHESTRATION RULES for SMOKE vs FULL sub-classification within MILESTONE. |

**Classification rules:**
- The Manager MUST classify the task as `SMALL` or `MILESTONE` during Phase 0 (Task Detection), immediately after determining single vs. multi-task.
- For MILESTONE tasks, the Manager further classifies as `MILESTONE/SMOKE` or `MILESTONE/FULL` (see docs/policy/orchestration.md for Test Level System).
- **Default to `MILESTONE/FULL`** when the classification is ambiguous or the task touches code that could affect runtime behavior.
- For multi-task prompts, each task is classified independently in the Execution Plan.
- The full classification (e.g., `MILESTONE/FULL`) MUST be passed to the Tester in the Phase 4C prompt as `TASK CLASSIFICATION: <SMALL | MILESTONE/SMOKE | MILESTONE/FULL>`.
- The Tester MUST NOT override the Manager's classification. If the Tester believes the classification is wrong, it MUST output `NEEDS_MANAGER_ACTION: Classification may be incorrect — <reason>` and proceed with the given classification.

## FRESH TAGS INDEXING POLICY (MANDATORY)

The Manager MUST keep the ctags index fresh so agents always navigate up-to-date symbols. Use the MCP tool `code_index_ctags` with `{ "mode": "incremental" }`. The tool automatically escalates to a full rebuild when correctness requires it (missing tags, stale state, many deletes/renames, >24h since last full index, etc.). If MCP is unavailable, fall back to: `cd <repo_root> && git ls-files | ctags -L - -f tags --fields=+lnS --extras=+q` via Bash.

**When to index (the Manager calls this directly — NOT agents):**

| Trigger | When | Required? |
|---------|------|-----------|
| **Multi-task: batch start** | Once, immediately after the Execution Plan is produced (before Task 1 begins) | ALWAYS — use `mode="full"` (multi-task only) |
| **Pre-Phase-4** | Immediately before entering the Implementation Loop | ALWAYS |
| **Post-Developer** | After each Developer iteration exits, before spawning the Reviewer | ONLY IF the Developer's "Files Changed" section lists any created, modified, or deleted files. If zero files changed, SKIP this refresh (Smart Orchestration Rule). |
| **Multi-task: task start** | At the start of each task's Per-Task Pipeline (before Phase 1) | ALWAYS (multi-task only) |
| **Multi-task: task end** | After a task's Phase 5 completes, before moving to the next task | ALWAYS (multi-task only) |

**Rules:**
- The Manager calls `code_index_ctags` directly (it is NOT delegated to an agent).
- Always use `{ "mode": "incremental" }` — the tool decides internally whether a full rebuild is needed. Only pass `{ "mode": "full" }` if you explicitly want to force a complete rebuild (e.g., after install.sh, a major git operation like rebase/merge, or the "Multi-task: batch start" trigger).
- If the tool returns an error, log it and continue — do not block the pipeline on a ctags failure.
- The Developer's Implementation Report MUST include a "Files Changed" section listing created/modified/deleted files. The Manager uses this to decide whether a post-Developer re-index is needed.
- State is persisted in `.claude/index-state.json` — do not delete this file.
- **Ctags mode is configurable via environment variable** (see CTAGS MODE CONFIGURATION below).

## CTAGS MODE CONFIGURATION

The factory supports three ctags indexing modes controlled by the `CLAUDE_FACTORY_CTAGS_MODE` environment variable:

| Mode | Behavior |
|------|----------|
| `smart` (default) | Manager calls `code_index_ctags` only at the trigger points defined in the Fresh Tags Indexing Policy above. Balances freshness with performance. |
| `always` | Manager calls `code_index_ctags` before every agent spawn in the pipeline. Maximum symbol freshness at the cost of higher indexing overhead. Useful for rapidly changing codebases or when debugging symbol navigation issues. |
| `off` | Skip all `code_index_ctags` calls entirely. Use this mode for repositories where ctags is not useful (e.g., configuration-only repos, documentation-only projects) or when ctags is not installed. Agents may fall back to search-based discovery. |

**Usage:**
- Set the environment variable before starting the Claude Code session:
  ```bash
  export CLAUDE_FACTORY_CTAGS_MODE=smart   # default
  export CLAUDE_FACTORY_CTAGS_MODE=always  # maximum freshness
  export CLAUDE_FACTORY_CTAGS_MODE=off     # disable ctags
  ```
- If `CLAUDE_FACTORY_CTAGS_MODE` is not set, the factory defaults to `smart`.
- The Manager MUST check this environment variable before every ctags call and skip the call if mode is `off`.
- In `always` mode, the Manager calls `code_index_ctags` before spawning Analyst, Researcher, Architect, Developer, Reviewer, Tester, and Reporter (in addition to the standard trigger points).

## TOOL-FIRST POLICY (MANDATORY)

All agents MUST follow these rules to minimize token waste and context window consumption:

1. **Search before reading.** Before reading any file, use `code_search_rg` (or `code_index_ctags` for symbol navigation) to locate the specific lines, functions, or sections you need. Never open a file "to see what's in it" — know what you are looking for first.
2. **Prefer targeted tools.** Use `code_search_rg` for pattern/text discovery and `code_index_ctags` for symbol-level navigation. These return only relevant matches and cost a fraction of the tokens a full file read would consume.
3. **Never read an entire large file without justification.** If a file exceeds 500 lines, you MUST use line-range-limited reads (offset + limit parameters) targeting only the sections identified by a prior search. Reading the full file is permitted only when the task requires understanding the complete file (e.g., a full rewrite or comprehensive audit).
4. **Prefer line ranges in the Read tool.** When you must read a file, always provide `offset` and `limit` parameters to read only the relevant section. A search or ctags lookup should have already told you which lines to target.

## TOKEN USAGE POLICY (MANDATORY)

All agents MUST manage their context window as a finite, shared resource. Wasting tokens on unnecessary content degrades reasoning quality and increases cost across every tier.

1. **Prefer tool results over raw file content.** Use `code_search_rg` and `code_index_ctags` to extract only the lines, symbols, or patterns you need. Tool results are compact and targeted; raw file reads are expensive. This complements the TOOL-FIRST POLICY — that policy dictates *when* to use tools; this rule dictates *why*: every unnecessary token displaces useful reasoning context.
2. **Pass summaries, not raw outputs, between agents.** When the Manager forwards one agent's output to the next, it MUST pass a structured summary — not the agent's full verbose output. Strip debug logs, intermediate reasoning, and repeated context. Each agent should receive only the conclusions and data it needs to do its job.
3. **Keep context compressed at every stage.** Agents MUST write concise reports. Bullet points over paragraphs. Tables over prose. Code references (file:line) over inlined code blocks, unless the code itself is the deliverable. The goal is maximum information density per token.
4. **Delegate large reads to the Reader.** When an agent needs to consume more than 200 lines from a single file, or content from more than 3 files, the Manager SHOULD spawn the Reader (Tier 3 / Haiku) to extract and summarize the relevant content. This keeps Tier 1 and Tier 2 context windows focused on reasoning, not ingestion. See the READER DELEGATION PATTERN in docs/policy/agents.md for trigger rules and spawning instructions.
5. **Never load the entire repository into context.** No agent may read all files in the repo, concatenate file trees, or attempt to "understand the whole codebase" in a single context window. Discovery is always incremental: search, then read targeted sections, then search again if needed. The TOOL-FIRST POLICY and `code_search_rg` exist specifically to make this unnecessary.

---

This policy file is referenced by CLAUDE.md and enforced by the Manager. All agents must comply with these policies.
