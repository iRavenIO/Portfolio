# QUOTA-AWARE MODEL MIX POLICY

This policy defines quota-aware orchestration that adjusts model assignments based on API quota status, reducing reliance on high-tier models when quotas are constrained.

## 1. Overview

The Manager assesses API quota health before spawning agents and selects a **quota mode** (balanced, conserve_sonnet, or conserve_opus) that determines model assignments for the current task run.

**Relationship to existing policies:**
- This policy extends the model assignments defined in `docs/policy/agents.md`
- It coexists with the Task Complexity Classification and Budget Block System from `docs/policy/orchestration.md`
- The Manager combines quota mode, task complexity, and budget blocks to orchestrate agent spawns

**Backward compatibility:**
- Quota mode is optional — if no quota assessment is performed, the Manager defaults to `balanced` mode
- All spawn templates remain valid whether a QUOTA SNAPSHOT is provided or not
- Agents do not need to understand quota mode; they receive only their model assignment and budget

---

## 2. Quota Modes

The Manager selects one of three modes based on API quota health:

| Quota Mode | When to Use | Effect |
|------------|-------------|--------|
| **balanced** | Default — all quotas healthy | Standard model assignments (baseline from agents.md) |
| **conserve_sonnet** | All-models quota is low/critical, Sonnet-only quota is healthy | Shift LOW-complexity tasks to Haiku and MEDIUM/HIGH Analysts/Reporters to Opus (reduces Sonnet calls) |
| **conserve_opus** | Sonnet-only quota is healthy but Opus usage should be minimized | Shift Architect and Reviewer to Sonnet for LOW/MEDIUM tasks; enable Pre-Review Pass for MEDIUM tasks |

**Quota health levels:**
- **healthy**: >= 50% of quota remaining
- **low**: 20-49% remaining
- **critical**: < 20% remaining

---

## 3. Quota Snapshot Format

When the Manager performs a quota assessment, it includes a QUOTA SNAPSHOT in every agent spawn prompt (between BUDGET BLOCK and FILES ALREADY READ). The snapshot provides context but agents do NOT act on it — only the Manager uses it to derive model assignments.

### 3.1 Format

```
QUOTA SNAPSHOT (if provided):
  All-models remaining: <healthy | low | critical>
  Sonnet-only remaining: <healthy | low | critical>
  Policy mode: balanced | conserve_sonnet | conserve_opus
  Reason: <one-line justification>
```

**Example:**
```
QUOTA SNAPSHOT:
  All-models remaining: low
  Sonnet-only remaining: healthy
  Policy mode: conserve_sonnet
  Reason: All-models quota at 35%, conserving Sonnet to stretch capacity
```

If no quota assessment is performed, the QUOTA SNAPSHOT block is omitted entirely.

---

## 4. Quota-Aware Model Assignment Table

This table defines model assignments for every (Complexity × Quota Mode) combination. Cells marked with **(Δ)** differ from the `balanced` default.

### 4.1 Full Decision Table

| Complexity | Quota Mode       | Analyst    | Researcher | Architect  | Developer  | Reviewer   | Tester     | Reporter   | Reader     |
|------------|------------------|------------|------------|------------|------------|------------|------------|------------|------------|
| LOW        | balanced         | sonnet     | sonnet     | opus       | sonnet     | opus       | sonnet     | sonnet     | haiku      |
| LOW        | conserve_sonnet  | haiku  (Δ) | SKIP   (Δ) | opus       | sonnet     | opus       | haiku  (Δ) | haiku  (Δ) | haiku      |
| LOW        | conserve_opus    | sonnet     | sonnet     | sonnet (Δ) | sonnet     | sonnet (Δ) | sonnet     | sonnet     | haiku      |
| MEDIUM     | balanced         | sonnet     | sonnet     | opus       | sonnet     | opus       | sonnet     | sonnet     | haiku      |
| MEDIUM     | conserve_sonnet  | opus   (Δ) | sonnet     | opus       | sonnet     | opus       | sonnet     | opus   (Δ) | haiku      |
| MEDIUM     | conserve_opus    | sonnet     | sonnet     | opus       | sonnet     | sonnet (Δ) | sonnet     | sonnet     | haiku      |
| HIGH       | balanced         | sonnet     | sonnet     | opus       | sonnet     | opus       | sonnet     | sonnet     | haiku      |
| HIGH       | conserve_sonnet  | opus   (Δ) | sonnet     | opus       | sonnet     | opus       | sonnet     | opus   (Δ) | haiku      |
| HIGH       | conserve_opus    | sonnet     | sonnet     | opus       | sonnet     | opus       | sonnet     | sonnet     | haiku      |

**Rationale for deltas:**

**conserve_sonnet mode (reduce Sonnet calls):**
- LOW/Analyst → haiku: Simple analysis for trivial tasks
- LOW/Researcher → SKIP: Skip research phase for trivial tasks (Manager can inject skip decision)
- LOW/Tester → haiku: Lint-only verification doesn't need Sonnet
- LOW/Reporter → haiku: Documentation compilation for simple tasks
- MEDIUM+HIGH/Analyst → opus: Complex analysis needs stronger reasoning to reduce rework
- MEDIUM+HIGH/Reporter → opus: High-quality final reports reduce support burden

**conserve_opus mode (reduce Opus calls):**
- LOW/Architect → sonnet: Config changes and doc updates don't need Opus-level design
- LOW/Reviewer → sonnet: Low-risk changes can be reviewed by Sonnet
- MEDIUM/Reviewer → sonnet: Enable Pre-Review Pass (see Section 5) to offload Reviewer grunt work

### 4.2 Policy Mode Derivation Rules

The Manager determines the quota mode using this logic:

| All-models remaining | Sonnet-only remaining | Policy Mode       | Reason |
|----------------------|-----------------------|-------------------|--------|
| healthy              | healthy               | balanced          | Default — no constraints |
| healthy              | low                   | balanced          | Sonnet-only low but all-models healthy; no action needed |
| healthy              | critical              | balanced          | Sonnet-only critical but all-models healthy; no action needed |
| low                  | healthy               | conserve_sonnet   | All-models low, Sonnet-only healthy; reduce Sonnet to free all-models capacity |
| low                  | low                   | conserve_opus     | Both low; conserve Opus (rarer, more expensive) |
| low                  | critical              | conserve_opus     | Sonnet-only critical; must conserve Opus to avoid blocking work |
| critical             | healthy               | conserve_sonnet   | All-models critical; aggressively conserve Sonnet |
| critical             | low                   | conserve_opus     | Both constrained; prioritize Opus conservation |
| critical             | critical              | conserve_opus     | Emergency mode; conserve Opus (higher priority) |

**Manager responsibilities:**
1. **Assess quota health** (via API introspection, config, or heuristic)
2. **Derive policy mode** using the table above
3. **Inject QUOTA SNAPSHOT** into all agent prompts (between BUDGET BLOCK and FILES ALREADY READ)
4. **Select model** for each agent spawn using the Quota-Aware Model Assignment Table (Section 4.1)
5. **Conditional research skip**: If the policy mode is `conserve_sonnet` and complexity is `LOW`, the Manager MAY skip Phase 2 (Researcher) even if the Analyst flagged research as needed, and inject a note in the Architect's prompt: "Research phase skipped due to quota conservation."

### 4.3 Developer Model Rationale in conserve_sonnet Mode

In `conserve_sonnet` mode, the Developer remains assigned to Sonnet across all complexity levels. This is intentional for three reasons:

1. **Cost-quality balance:** Code generation at Sonnet tier provides sufficient quality for most implementation tasks. Promoting Developer to Opus would consume expensive Opus capacity for work that Sonnet handles well.
2. **Automatic escalation exists:** The Adaptive Model Escalation rules in `docs/policy/failure-recovery.md` automatically promote the Developer to Opus when implementation struggles (iteration 3+, 2+ failures, or HIGH complexity final iteration). This safety net means the Developer does not need a preemptive Opus assignment.
3. **Prevents Opus overuse:** The Developer is the most frequently spawned agent in the loop (up to 5 iterations). Assigning it to Opus in conserve_sonnet mode would undermine the goal of conserving expensive model capacity, since conserve_sonnet is already triggered by low all-models quota.

The Developer's Sonnet assignment in conserve_sonnet mode is NOT a hard constraint -- it is overridden by escalation rules when implementation quality demands it.

---

## 5. Pre-Review Pass Protocol

When **quota mode is conserve_opus** and **task complexity is MEDIUM**, the Manager enables a **Pre-Review Pass** — a lightweight Sonnet agent that runs between Developer and Reviewer to offload mechanical checks from the Tier 1 Reviewer.

### 5.1 Trigger Conditions

The Pre-Review Pass runs when ALL of these are true:
- Quota mode is `conserve_opus`
- Task complexity is `MEDIUM`
- The Developer has completed implementation (no missing deliverables)

**Trigger matrix:**

| Complexity | Quota Mode       | Pre-Review Pass |
|------------|------------------|-----------------|
| LOW        | balanced         | disabled        |
| LOW        | conserve_sonnet  | disabled        |
| LOW        | conserve_opus    | optional        |
| MEDIUM     | balanced         | disabled        |
| MEDIUM     | conserve_sonnet  | disabled        |
| MEDIUM     | conserve_opus    | MANDATORY       |
| HIGH       | balanced         | disabled        |
| HIGH       | conserve_sonnet  | disabled        |
| HIGH       | conserve_opus    | disabled        |

**Rationale:**
- LOW tasks are simple enough that a Pre-Review Pass adds overhead without benefit
- MEDIUM tasks have enough mechanical surface area (multi-file changes, cross-references) to justify a pre-filter
- HIGH tasks are complex enough that the Reviewer needs full context from the start — pre-filtering risks missing subtle issues

### 5.2 Pre-Review Pass Agent Specification

**Model:** Sonnet
**Name:** Pre-Review Agent
**Input:** Developer's Implementation Report + Architect's Technical Design Document + Evidence Pack (DIFF SUMMARY, CHANGED FILES, DELIVERABLES CHECKLIST)

**Responsibilities:**
1. **Diff Checklist**: Verify all files from the Architect's plan are present; flag missing or unexpected files
2. **Policy Violations**: Check for common issues (e.g., secrets in diffs, prohibited patterns, missing TOOL-FIRST adherence)
3. **Test Scope Recommendations**: Identify risky changes that need targeted tests
4. **Severity Triage**: Categorize findings as BLOCKER (must fix before Reviewer), WARNING (Reviewer should scrutinize), or INFO (low-priority note)
5. **Low-Risk Confirmation**: Identify files that match design exactly and are low-risk (Reviewer can skip deep read)

**Output Format:**
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

**PASS**: All mechanical checks passed; proceed to Reviewer with findings as context
**NEEDS_DEVELOPER_ACTION**: Critical issues found; re-spawn Developer with BLOCKER list

### 5.3 Reviewer Integration

When the Pre-Review Pass runs, the Manager includes its findings in the Reviewer's Evidence Pack under a new section:

```
PRE-REVIEW FINDINGS (if Pre-Review Pass ran):
<paste Pre-Review Agent's output>
```

The Reviewer uses these findings to:
- **Skip low-risk files** identified by the Pre-Review Agent
- **Prioritize flagged items** (especially BLOCKER and WARNING severity)
- **Focus test recommendations** on areas highlighted by Pre-Review Agent
- **Validate Pre-Review findings** (spot-check to ensure Pre-Review Agent didn't miss critical issues)

### 5.4 Tester Integration

When the Pre-Review Pass runs, the Manager includes test scope recommendations in the Tester's prompt as a new paragraph:

```
PRE-REVIEW TEST RECOMMENDATIONS (if available):
<paste test scope recommendations from Pre-Review Findings>

Use these recommendations to prioritize your test plan, but do NOT skip
testing areas that are not listed — the Pre-Review Agent provides guidance,
not a complete test specification.
```

---

## 6. Evidence Pack Extension

The Evidence Pack format in `docs/policy/orchestration.md` is extended to include Pre-Review Findings when applicable. The full format becomes:

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
- PRE-REVIEW FINDINGS section is ONLY included if the Pre-Review Pass ran
- If Pre-Review Pass did not run (disabled or not triggered), omit this section entirely
- The Reviewer and Tester prompts reference this section conditionally

---

## 7. Manager Workflow Integration

The Manager's Phase 4 (Implementation Loop) is extended as follows:

### Current Phase 4 (no quota awareness):
```
1. DEVELOPER → Implementation Report
2. [ctags refresh if files changed]
3. Pre-Review Deliverables Verification (Manager checks completeness)
4. Assemble Evidence Pack
5. REVIEWER → Code Review Report
6. TESTER → Test Report
```

### Extended Phase 4 (with quota awareness):
```
1. DEVELOPER → Implementation Report
2. [ctags refresh if files changed]
3. Pre-Review Deliverables Verification (Manager checks completeness)
4. [NEW] If Pre-Review Pass is MANDATORY or optional:
   a. Spawn Pre-Review Agent (Sonnet)
   b. If verdict = NEEDS_DEVELOPER_ACTION → loop back to step 1 with BLOCKER list
   c. If verdict = PASS → continue to step 5 with findings
5. Assemble Evidence Pack (includes PRE-REVIEW FINDINGS if step 4 ran)
6. REVIEWER → Code Review Report (with PRE-REVIEW FINDINGS context)
7. TESTER → Test Report (with PRE-REVIEW TEST RECOMMENDATIONS context)
```

**Manager decision logic for Pre-Review Pass:**
- If `quota_mode == "conserve_opus"` AND `complexity == "MEDIUM"` → Pre-Review Pass is MANDATORY
- If `quota_mode == "conserve_opus"` AND `complexity == "LOW"` → Pre-Review Pass is OPTIONAL (Manager MAY enable it if the change is high-risk)
- Otherwise → Pre-Review Pass is DISABLED

---

## 8. Spawn Template Changes

All agent spawn templates in `docs/policy/spawn-templates.md` are extended to include the QUOTA SNAPSHOT block (between BUDGET BLOCK and FILES ALREADY READ).

**Example (Phase 1: Analyst):**
```
BUDGET BLOCK:
  Complexity: <LOW|MEDIUM|HIGH>
  Tools: <tiny|small|medium|large>
  File Reads: <tiny|small|medium|large>
  Output Detail: <short|medium|detailed>

QUOTA SNAPSHOT (if provided):
  All-models remaining: <healthy | low | critical>
  Sonnet-only remaining: <healthy | low | critical>
  Policy mode: balanced | conserve_sonnet | conserve_opus
  Reason: <one-line justification>

FILES ALREADY READ (do NOT re-read these unless git_repo_diff shows changes):
<comma-separated list of file paths, or "None yet">
```

This block is injected into all 8 phase templates:
- Phase 1: Analyst
- Phase 2: Researcher
- Phase 3: Architect
- Phase 4A: Developer
- Phase 4B: Reviewer
- Phase 4C: Tester
- Phase 5: Reporter
- Phase 6: Batch Completion Summary (Reporter)

Additionally, two new subsections are added to spawn-templates.md:
1. **Phase 4A.6: Pre-Review Pass** (new agent template)
2. **Reviewer and Tester context extensions** (PRE-REVIEW FINDINGS and PRE-REVIEW TEST RECOMMENDATIONS paragraphs)

---

## 9. Policy File References

This policy is referenced in:
- `CLAUDE.md` — POLICIES table (new row for quota.md)
- `docs/policy/orchestration.md` — Evidence Pack extension (Section 6 above)
- `docs/policy/spawn-templates.md` — QUOTA SNAPSHOT injection, Pre-Review Pass template, Reviewer/Tester extensions
- `.claude/scripts/validate-policies.sh` — Validation checks for quota.md existence and structure
- `.claude/scripts/health-check.sh` — Policy file existence check

---

This policy is mandatory when the Manager performs quota assessment. If no quota assessment is performed (e.g., quota API unavailable), the Manager defaults to `balanced` mode and omits the QUOTA SNAPSHOT block from agent prompts.
