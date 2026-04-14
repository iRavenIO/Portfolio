# FAILURE RECOVERY & ADAPTIVE ESCALATION POLICY

This policy defines structured failure handling and model escalation for the Manager.

---

## 1. Overview

The Claude Factory's implementation loop (Phase 4) operates through iterative refinement: Developer → Reviewer → Tester → Developer → ... until acceptance criteria are met or maximum iterations are reached. During this loop, various failure modes can occur: tools may crash, agents may produce incomplete output, validation may fail, or code review may request changes.

This policy provides a structured framework for the Manager to detect, classify, and recover from failures. It defines:

1. **Failure Type Taxonomy** — Five distinct failure categories with clear detection criteria
2. **Manager Recovery Matrix** — Deterministic recovery actions for each failure type
3. **Adaptive Model Escalation** — Three escalation rules that automatically upgrade Developer spawns to more capable models when implementation quality demands it

This policy integrates with and extends:
- `docs/policy/orchestration.md` — Smart Orchestration Rules (Evidence Pack, Budget Blocks)
- `docs/policy/agents.md` — Multi-Model Routing and baseline model assignments
- `docs/policy/quota.md` — Quota-aware model mix and Pre-Review Pass Protocol
- `docs/policy/critical-rules.md` — Enforcement rules and error handling
- `docs/policy/workflow.md` — Phase definitions and execution plan

The Manager MUST consult this policy whenever an agent fails, produces incomplete output, or a validation/review gate fails during the implementation loop.

---

## 2. Failure Type Taxonomy

The Manager classifies failures into five types based on detection criteria:

| Failure Type | Detection Criteria | Examples |
|--------------|-------------------|----------|
| **TOOL_FAILURE** | MCP tool crash, command exits non-zero, missing/empty tool output | `code_search_rg` timeout, `ctags` process crash, `git` command fails, network error during MCP call |
| **AGENT_RUNTIME_ERROR** | Subagent exception, Task tool returns error, unexpected system error, agent produces no output | Background agent crash, model API error, context window exceeded, Task tool exception |
| **PARTIAL_OUTPUT** | Agent completes but deliverables incomplete, missing required sections, missing files | Developer report lacks "Files Changed" section, Analyst missing acceptance criteria, Architect design incomplete |
| **VALIDATION_FAILURE** | `health-check.sh` fails, `validate-policies.sh` fails, tests fail, lint errors | Tester returns FAILURES_FOUND, policy validation check fails, unit tests fail |
| **REVIEW_REJECTION** | Reviewer verdict = CHANGES_REQUESTED | Code review identifies issues requiring Developer rework |

**Classification rules:**

- If multiple failure types apply, classify as the most severe: TOOL_FAILURE > AGENT_RUNTIME_ERROR > PARTIAL_OUTPUT > VALIDATION_FAILURE > REVIEW_REJECTION
- If the failure does not match any defined type, treat it as AGENT_RUNTIME_ERROR
- Log the failure type and recovery action taken for observability

---

## 3. Manager Recovery Matrix

For each failure type, the Manager executes the prescribed recovery action:

| Failure Type | Recovery Action | Escalation |
|--------------|-----------------|------------|
| **TOOL_FAILURE** | 1. Log failure with tool name and error<br>2. Retry same agent ONCE with same model<br>3. If retry fails → escalate model tier (Haiku→Sonnet→Opus)<br>4. If Opus fails → log and proceed with partial output | Model tier escalation on second failure |
| **AGENT_RUNTIME_ERROR** | 1. Log failure with agent type and error<br>2. Retry same agent ONCE with same model and additional context<br>3. If retry fails → escalate model tier<br>4. If Opus fails → proceed to next phase with failure note | Model tier escalation on second failure |
| **PARTIAL_OUTPUT** | 1. Re-spawn same agent with clarification prompt identifying missing deliverables<br>2. Do NOT escalate model yet<br>3. If re-spawn also produces partial output → escalate model tier | Model tier escalation only after second partial output |
| **VALIDATION_FAILURE** | 1. Continue implementation loop<br>2. Send Developer to fix issues with specific failure details<br>3. Apply Iteration Escalation Ladder (see Section 4) | Via Iteration Escalation Ladder |
| **REVIEW_REJECTION** | 1. Continue implementation loop<br>2. Pass reviewer feedback to Developer<br>3. Apply Iteration Escalation Ladder (see Section 4) | Via Iteration Escalation Ladder |

### 3.1 Model Tier Escalation Ladder

When recovery requires model escalation, the Manager uses this progression:

```
Haiku → Sonnet → Opus
```

**Escalation rules:**
- Escalation is one step at a time (never skip Sonnet to go directly to Opus from Haiku)
- If the agent was already on Opus and fails again, log the failure and proceed to the next phase with a failure note
- Escalation applies only to the current agent spawn, not globally; subsequent spawns of the same agent type revert to default unless escalation conditions persist

### 3.2 Recovery Attempt Limits

To prevent infinite recovery loops:

- **Maximum 1 retry** per failure type per agent spawn
- **Maximum 1 model escalation** per agent spawn
- If both retry and escalation fail, proceed with partial output and note the failure in the final report
- These limits apply per-agent, per-spawn — the failure counter resets when spawning a different agent type

---

## 4. Adaptive Model Escalation

The following three escalation rules apply specifically to **Developer** spawns within the implementation loop (Phase 4). They override the baseline Developer model assignment from `docs/policy/agents.md`.

### 4.1 Developer Iteration Escalation Ladder

The Developer's model is determined by the current iteration count:

| Iteration | Developer Model | Rationale |
|-----------|-----------------|-----------|
| 1 | Sonnet | Initial implementation with baseline model |
| 2 | Sonnet | First round of fixes with baseline model |
| 3 | Opus | Issues remaining after 2 iterations likely require stronger reasoning |
| 4 | Opus | Continue with Opus for complex fixes |
| 5 | Opus | Final iteration uses strongest model |

**Rationale:** The first two iterations handle the initial implementation and one round of fixes. If the implementation still needs work after two iterations, the remaining issues are likely complex enough to warrant Opus-level reasoning. This provides a graduated escalation that conserves Opus quota for genuinely difficult problems.

### 4.2 Failure-Triggered Escalation

If the Developer agent experiences **two or more failures** (TOOL_FAILURE or AGENT_RUNTIME_ERROR) within the same task run, the **next Developer spawn uses Opus** regardless of iteration number.

**Scope:** "Same task run" means within a single task's Phase 4 loop. The failure counter resets at task boundaries in multi-task runs.

**Rationale:** Repeated Developer failures signal environmental issues, complex implementation challenges, or inadequate model capacity. Escalating to Opus increases the likelihood of successful implementation on the next attempt.

### 4.3 Complexity-Triggered Escalation

For tasks classified as **HIGH complexity** (per `docs/policy/orchestration.md` Task Complexity Classification), the **final iteration** of the implementation loop uses **Opus** for the Developer.

**Final iteration definition:** The last iteration before the loop exits, whether that's iteration 5 (maximum) or an earlier iteration if all acceptance criteria are met.

**Rationale:** HIGH complexity tasks have intricate requirements, multiple file changes, or significant architectural impact. Using Opus for the final implementation attempt ensures the highest-quality code for the most challenging tasks.

### 4.4 Escalation Rule Composition

When multiple escalation rules apply simultaneously, the **highest-tier model wins**:

| Rule | Trigger | Model |
|------|---------|-------|
| Baseline (agents.md) | Default | Sonnet |
| Iteration Escalation | iteration >= 3 | Opus |
| Failure-Triggered | 2+ Developer failures | Opus |
| Complexity-Triggered | HIGH + final iteration | Opus |

**Examples:**

- Iteration 2, HIGH complexity, 0 failures → **Sonnet** (complexity-triggered only applies at final iteration, not iteration 2)
- Iteration 3, MEDIUM complexity, 0 failures → **Opus** (iteration escalation triggers)
- Iteration 1, LOW complexity, 2 failures → **Opus** (failure-triggered escalation overrides baseline)
- Iteration 5, HIGH complexity, 0 failures → **Opus** (both iteration and complexity-triggered apply; Opus wins)

### 4.5 Interaction with Quota Modes

Escalation rules from this policy **take precedence over quota-mode model assignments** for the Developer. This means:

- In `conserve_sonnet` mode, if escalation triggers Opus for the Developer, the Manager MUST use Opus
- In `conserve_opus` mode, if escalation triggers Opus for the Developer, the Manager MUST use Opus (no change from baseline)
- In `balanced` mode, escalation rules apply normally

**Rationale:** Quota conservation cannot override safety escalation — correctness and implementation quality take priority over cost. The escalation system is designed to use Opus sparingly and only when necessary, so allowing escalation in conserve modes does not undermine the conservation goal.

---

## 5. Manager Implementation

The Manager tracks these state variables during each task's Phase 4:

```python
developer_iteration = 0           # current iteration count (1-based)
developer_failure_count = 0       # TOOL_FAILURE + AGENT_RUNTIME_ERROR count for Developer in current task
task_complexity = LOW|MEDIUM|HIGH # from Analyst's classification
max_iterations = 5                # from workflow.md
```

Before each Developer spawn, the Manager computes the model using this algorithm:

```python
model = "sonnet"   # baseline from agents.md

# Apply escalation rules (highest tier wins)
if developer_iteration >= 3:
    model = "opus"   # iteration escalation

if developer_failure_count >= 2:
    model = "opus"   # failure-triggered escalation

if task_complexity == "HIGH" and developer_iteration == max_iterations:
    model = "opus"   # complexity-triggered escalation

# model is now "sonnet" or "opus"
```

After the Developer completes (or fails), the Manager updates state:

```python
developer_iteration += 1

if developer_failed:
    developer_failure_count += 1
```

The Manager resets `developer_iteration` and `developer_failure_count` to 0 at the start of each new task in multi-task runs.

---

## 6. Policy File References

This policy is referenced in:

- `CLAUDE.md` — POLICIES table (row for failure-recovery.md)
- `docs/policy/orchestration.md` — "Failure Recovery Cross-Reference" section
- `docs/policy/workflow.md` — "Failure Recovery" paragraph in Per-Task Pipeline
- `docs/policy/critical-rules.md` — Rule 26 (failure classification) + updated Error Handling section
- `docs/policy/agents.md` — "Escalation override" note under MODEL ASSIGNMENTS
- `.claude/scripts/validate-policies.sh` — Checks 15, 16, 17 for existence and content
- `.claude/scripts/health-check.sh` — Policy file existence check in POLICY_FILES array
