# TASK MODE CLASSIFICATION

## OVERVIEW

The Factory classifies each task into one of three modes to optimize resource usage and execution time. Mode detection occurs during Phase 0 (Task Detection) and determines which agents run, their budget allocations, and loop iteration limits.

This policy enables:
- **Cost efficiency** - Skip unnecessary agents for simple changes
- **Faster turnaround** - Reduced budgets and iterations for micro-changes
- **Appropriate rigor** - Full pipeline for complex work, lightweight for simple work

Mode classification is **automatic** based on detection heuristics. The Manager performs mode classification immediately after task complexity classification.

---

## MODE DEFINITIONS

| Mode | Description | Use Cases | Pipeline Changes |
|------|-------------|-----------|------------------|
| **MICRO-CHANGE** | Minimal code changes requiring no design phase. Single file edits, simple fixes, documentation updates. | Bug fixes, typos, parameter tweaks, comment updates, formatting changes | Skip Architect. Reduced budgets (tiny/tiny/short). Max 2 loop iterations. |
| **STANDARD** | Normal development work requiring full design and review. Multi-file changes, new features, refactoring. | Feature development, refactoring, new components, integration work | Full pipeline (current behavior). Standard budgets. Max 3 loop iterations. |
| **VERIFICATION** | Read-only analysis tasks with no code changes. Audits, investigations, explanations. | Code audits, bug investigations, documentation requests, "explain how X works" | Skip Researcher, Architect, Developer. Read-only Analyst + Reporter. No loop. |

---

## DETECTION HEURISTICS

The Manager applies this algorithm during Phase 0:

```
INPUT: user_prompt, file_count_estimate, complexity_level

# Step 1: Check for verification keywords
IF user_prompt contains ["explain", "how does", "audit", "investigate", "document how", "show me how"]
   AND NOT contains ["fix", "add", "implement", "update", "change"]
   THEN mode = VERIFICATION
   RETURN mode

# Step 2: Check for micro-change indicators
micro_keywords = ["typo", "fix typo", "rename variable", "update comment", "bump version", "fix lint", "format code"]
simple_edits = ["change X to Y", "update X", "fix X in Y"]

IF complexity_level == LOW
   AND (user_prompt contains any(micro_keywords) OR matches any(simple_edits))
   AND file_count_estimate <= 2
   THEN mode = MICRO-CHANGE
   RETURN mode

# Step 3: Default to STANDARD
mode = STANDARD
RETURN mode
```

**Edge Cases:**
- If uncertain, default to STANDARD (safer over-provisioning)
- Multi-task prompts: classify each task independently
- If a task seems MICRO-CHANGE but mentions "refactor" or "redesign", escalate to STANDARD

---

## PIPELINE BEHAVIOR MATRIX

| Phase | MICRO-CHANGE | STANDARD | VERIFICATION |
|-------|--------------|----------|--------------|
| **Phase 1: Analyst** | ✅ Runs (tiny budget) | ✅ Runs (standard budget) | ✅ Runs (short budget) |
| **Phase 2: Researcher** | ❌ Skip | ✅ Conditional (standard budget) | ❌ Skip |
| **Phase 3: Architect** | ❌ Skip | ✅ Runs (opus, generous budget) | ❌ Skip |
| **Phase 4: Developer** | ✅ Runs (tiny budget) | ✅ Runs (standard budget) | ❌ Skip |
| **Phase 5: Reviewer** | ✅ Runs (sonnet, tiny budget) | ✅ Runs (opus, standard budget) | ❌ Skip |
| **Phase 6: Tester** | ✅ Runs (short budget, lint-only) | ✅ Runs (standard budget) | ❌ Skip |
| **Phase 7: Reporter** | ✅ Runs (short budget) | ✅ Runs (standard budget) | ✅ Runs (short budget) |
| **Loop Iterations** | Max 2 | Max 3 | N/A (no loop) |
| **ctags (incremental)** | ✅ Pre-loop + in-loop | ✅ Pre-loop + in-loop | ❌ Skip |

**Budget Overrides for MICRO-CHANGE:**
- Analyst: `tiny` (50K tokens)
- Developer: `tiny` (50K tokens)
- Reviewer: `tiny` (50K tokens), **downgraded to Sonnet tier**
- Tester: `short` (100K tokens)
- Reporter: `short` (100K tokens)

**Verification Mode Behavior:**
- Analyst produces read-only analysis (no design, no implementation)
- Reporter summarizes findings with file references
- No ctags indexing
- No implementation loop

---

## ESCALATION PATH

A MICRO-CHANGE task may escalate to STANDARD if:

1. **Developer discovers complexity** - Implementation reveals multi-file dependencies or design gaps
2. **Reviewer flags design issues** - Code review identifies architectural problems
3. **Tester finds failures** - Tests reveal broader issues requiring redesign

**Escalation Protocol:**
1. Agent reports escalation need in their output: `ESCALATION REQUIRED: <reason>`
2. Manager detects escalation marker
3. Manager re-runs from Phase 3 (Architect) with STANDARD budgets
4. Loop counter resets to 0

Escalation is **rare** but ensures safety. The Manager logs escalations for future heuristic tuning.

---

## POLICY FILE REFERENCES

This policy integrates with:
- **[workflow.md](workflow.md)** - Task mode affects execution plan format and phase sequencing
- **[spawn-templates.md](spawn-templates.md)** - Contains MICRO-CHANGE spawn variants for Developer, Reviewer, Tester
- **[orchestration.md](orchestration.md)** - Budget blocks reference task mode for budget allocation
- **[critical-rules.md](critical-rules.md)** - Rule 28 mandates task mode classification in Phase 0

**Cross-references:**
- MICRO-CHANGE spawn prompts: see spawn-templates.md "MICRO-CHANGE MODE SPAWN VARIANTS"
- Budget allocation rules: see orchestration.md "Budget Block System"
- Detection timing: see workflow.md "Phase 0: Task Detection"
