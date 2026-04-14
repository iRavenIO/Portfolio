# CRITICAL RULES POLICY

This document defines the mandatory enforcement rules for the Manager. All rules MUST be followed without exception.

---

## CRITICAL RULES

1. **EVERY prompt triggers this workflow.** No exceptions. No chatting.
2. **Always run Phase 0 (Task Detection) first.** Determine single vs. multi-task before spawning any agents.
3. **Always use the Task tool** to spawn agents. Never try to do an agent's job inline.
4. **Always pass the correct model parameter** as specified in the model assignment table. Respect the tier routing: Tier 1 (Opus) for planning/review, Tier 2 (Sonnet) for implementation/analysis, Tier 3 (Haiku) for file reading/extraction.
5. **Always read the agent's definition file** (from .claude/agents/) and include it in the prompt so the subagent has its full instructions.
6. **Pass all relevant context** from previous agents to the next one.
7. **The implementation loop MUST iterate** if the Reviewer or Tester finds issues. Maximum 5 iterations.
8. **The Reporter MUST use the MCP `notify_say` tool** (or `say` via Bash as fallback) to produce the voice summary.
9. **Use TaskCreate/TaskUpdate** to track progress through the phases so the user can see what's happening.
10. **For multi-task prompts:** Complete each task's full pipeline before starting the next. Always produce a Batch Completion Summary (Phase 6) at the end.
11. **Enforce MCP tool scopes.** Include role-specific tool rules in every agent prompt. If an agent uses a forbidden tool or drifts scope, stop it and re-spawn with a corrected prompt.
12. **Handle NEEDS_MANAGER_ACTION.** If any agent outputs this signal, address the request before continuing that agent's work.
13. **All reports go to `docs/tasks/reports/`.** Never write TASK_REPORT.md, TASK_REPORT_<i>.md, or BATCH_REPORT.md to the repository root. Always use `docs/tasks/reports/` (create the directory if it doesn't exist).
14. **Send progressive notifications.** Immediately after Phase 0 (Task Detection), call `notify_say` with a "Manager started" kickoff message. Then send phase completion notifications after Phases 1-4 complete (see Progressive Phase Notifications in workflow.md). Fallback: `say` via Bash.
15. **Send task lifecycle notifications (multi-task only).** At the start of each task, call `notify_say` with `"Starting task <i>/<N>: <title>"`. At the end of each task, call `notify_say` with `"Completed task <i>/<N> in <duration>"` (or `"Task <i>/<N> failed"` on failure). Record `task_start_time` at task start; compute duration as `Xm Ys` at task end. These are Manager-direct calls, not delegated to agents. Fallback: `say` via Bash.
16. **Keep tags fresh.** Always call `code_index_ctags { "mode": "incremental" }` before Phase 4, after each Developer iteration that changed files, and at the start/end of each task in multi-task runs. For multi-task prompts, call `code_index_ctags { "mode": "full" }` once at batch start (after the Execution Plan, before Task 1). The tool auto-escalates to full when correctness requires it. Fallback: `git ls-files | ctags -L - -f tags` via Bash. Never block the pipeline on a ctags failure.
17. **Classify tasks for staged builds.** During Phase 0, classify every task as `SMALL` or `MILESTONE` per the Staged Build Policy in docs/policy/build.md. Default to `MILESTONE` when unclear. Pass the classification to the Tester in the Phase 4C prompt. For multi-task prompts, classify each task independently in the Execution Plan.
18. **Enforce TOOL-FIRST policy.** All agents MUST search with `code_search_rg` before reading files and MUST use line-range reads (offset+limit) for files over 500 lines. The Manager includes the TOOL-FIRST POLICY reference in every agent prompt. See docs/policy/build.md for full rules.
19. **Consult runbooks during Phase 0.** After task classification, scan `.claude/runbooks/` for matching runbooks. If found, pass the runbook to the Analyst (as a reference) and to the Architect (as full supplementary context). Runbooks are advisory — the full pipeline still runs.
20. **Enforce TOKEN USAGE policy.** All agents MUST treat their context window as a finite resource. The Manager passes summaries (not raw outputs) between agents, delegates large reads to the Reader (Tier 3), and ensures no agent loads the entire repository. See docs/policy/build.md for full rules.
21. **Assemble Evidence Packs.** Before spawning the Reviewer or Tester, the Manager MUST assemble an Evidence Pack (see docs/policy/orchestration.md). Never pass raw Architect/Developer/Analyst outputs directly — always compress into the Evidence Pack format. This reduces Reviewer and Tester context window consumption.
22. **Verify deliverables before review.** After the Developer exits, the Manager MUST verify that all expected files from the Architect's design exist before spawning the Reviewer. If deliverables are missing, re-enter the loop with a gap list for the Developer. Do not waste a Tier 1 Reviewer cycle on incomplete implementations.
23. **Classify task complexity.** During Phase 0, classify every task as LOW, MEDIUM, or HIGH per the Task Complexity Classification in docs/policy/orchestration.md. Default to MEDIUM when unclear. Derive the Budget Block from the classification.
24. **Inject Budget Blocks.** Every agent spawn prompt MUST include the Budget Block. If an agent reports NEEDS_MANAGER_ACTION: Budget exceeded, the Manager MAY grant a one-level increase (e.g., small→medium) or re-scope the task.
25. **Maintain file read cache.** Track files read by each agent. Pass the FILES_ALREADY_READ list to subsequent agents. Agents MUST NOT re-read cached files unless git_repo_diff shows changes.
26. **Classify failures and apply recovery.** When an agent fails or validation/review gates fail, classify the failure type (TOOL_FAILURE, AGENT_RUNTIME_ERROR, PARTIAL_OUTPUT, VALIDATION_FAILURE, REVIEW_REJECTION) and execute recovery actions per the Manager Recovery Matrix in `docs/policy/failure-recovery.md`. Apply the three Developer escalation rules (iteration-based, failure-triggered, complexity-triggered) during the implementation loop.
27. **Execute auto-commit protocol.** The Reporter MUST follow the AUTO-COMMIT PROTOCOL steps in spawn-templates.md Phase 5. If all conditions are met, automatically commit implementation changes with proper commit message format (see docs/policy/git-automation.md). Honor the CLAUDE_FACTORY_AUTO_COMMIT environment variable for opt-out.
28. **Classify task mode.** During Phase 0, classify every task as MICRO-CHANGE, STANDARD, or VERIFICATION per docs/policy/task-modes.md. Apply mode-specific pipeline adjustments: MICRO-CHANGE skips Architect and uses reduced budgets; VERIFICATION skips implementation phases; STANDARD uses full pipeline.
29. **Inject token budgets.** The Manager MUST include token budget guidance in every agent spawn prompt as part of the Budget Block. Token budgets are derived from task complexity (LOW: 10K-30K, MEDIUM: 30K-80K, HIGH: 80K-150K input tokens). See docs/policy/token-budget.md for allocation rules and escalation protocol.
30. **Track execution timing.** The Manager MUST record phase start/end times (ISO 8601) and calculate durations for all phases and agents. Timing data is passed to the Reporter for inclusion in the EXECUTION METRICS section. See docs/policy/workflow.md for timing tracking requirements.
31. **Collect token usage metadata.** The Manager MUST capture input, output, and total token counts for every agent spawn and log them to the TOKEN LEDGER (agent, phase, model, iteration, tokens, timestamp). This data is passed to the Reporter for inclusion in the EXECUTION METRICS section. See docs/policy/observability.md for token ledger format.
32. **Cache-aware file reads.** Before reading any file, the Manager MUST check the Universal Context Cache (via `.claude/scripts/cache.sh`). Use cached content when available and unchanged. Inject CACHE CONTEXT blocks into agent spawn prompts listing pre-loaded policies, runbooks, and repository map. Agents MUST NOT re-read cached files unless git_repo_diff shows changes. See docs/policy/cache.md for cache lifecycle rules.
33. **Invalidate cache after edits.** After any Write or Edit operation, the Manager MUST invalidate affected cache entries by calling `cache_invalidate "file:<path>"`. Batch invalidations at task boundaries during multi-task runs. This prevents agents from reading stale cached content. See docs/policy/cache.md Rule 33 for invalidation protocol.

## CONTEXT PASSING PATTERN

Each agent receives:
- Its own instruction file content (read from .claude/agents/)
- Outputs from all previous agents that are relevant to its work
- The original user prompt (for reference)

This ensures each agent has full context without needing to re-discover information.

**Reader (utility agent):** The Reader does not follow the standard context chain. It receives only a specific read request (file paths, request type, and minimal context about what the requesting agent needs). Its output is injected into the requesting agent's prompt as supplementary context. The Reader never receives full pipeline outputs (Analyst report, Architect design, etc.) — it only needs to know what to read and why.

## ERROR HANDLING

The Manager MUST follow structured failure handling per `docs/policy/failure-recovery.md`:

- **Classify failures** into five types: TOOL_FAILURE, AGENT_RUNTIME_ERROR, PARTIAL_OUTPUT, VALIDATION_FAILURE, REVIEW_REJECTION
- **Execute recovery actions** per the Manager Recovery Matrix (Section 3):
  - TOOL_FAILURE / AGENT_RUNTIME_ERROR: retry once with same model, escalate model tier on second failure
  - PARTIAL_OUTPUT: re-spawn with clarification, escalate model tier on second partial output
  - VALIDATION_FAILURE / REVIEW_REJECTION: continue implementation loop, apply Developer escalation rules
- **Apply Developer escalation rules** during Phase 4 implementation loop:
  - Iteration Escalation: Use Opus for iterations 3+ (issues remaining after 2 iterations need stronger reasoning)
  - Failure-Triggered Escalation: Use Opus if Developer experienced 2+ failures in current task
  - Complexity-Triggered Escalation: Use Opus for final iteration of HIGH complexity tasks
- **Recovery limits:** Maximum 1 retry + 1 model escalation per agent spawn. If both fail, proceed with partial output and note failure.
- **Multi-task error handling:** If one task fails, still proceed to the next task. Record the failure in that task's report. The Batch Completion Summary (Phase 6) must note which tasks succeeded and which had issues.
- **Multi-task failure notification:** When a task fails in a multi-task run, the Manager MUST still call the onTaskEnd hook with the failure message (`"Task <i>/<N> failed"`) before proceeding to the next task. This ensures the user is always audibly notified of failures, even when the pipeline continues.
- Always produce a final report, even if partial.
