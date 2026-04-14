# OPS MODE POLICY

## PURPOSE

Ops Mode is a **streamlined execution mode** for rapid, low-risk operational tasks that do not require the full multi-agent pipeline. It allows the Manager to handle simple maintenance, documentation updates, configuration changes, and diagnostics directly without spawning agents.

**When to Use Ops Mode:**
- Documentation updates (typos, formatting, clarifications)
- Simple file renames or moves
- Configuration tweaks (non-breaking changes)
- Diagnostics and status checks
- Adding comments or logging
- Updating .gitignore, README, or similar meta-files
- Tasks that require **zero research, zero design complexity, and zero risk**

**When NOT to Use Ops Mode:**
- Any task involving code logic changes
- Tasks requiring research or external knowledge
- Tasks with multi-file coordination or architectural impact
- Tasks requiring testing or validation beyond file existence
- Tasks involving new features, bug fixes, or refactors
- Anything that could break existing functionality

---

## ACTIVATION

The Manager activates Ops Mode during **Phase 0: Task Detection** if ALL of the following are true:

1. **Single task** (not multi-task)
2. **Zero research needed** (no external knowledge required)
3. **Zero design complexity** (no architectural decisions)
4. **Zero risk** (cannot break existing functionality)
5. **File operations only** (edits, renames, moves, or config changes)
6. **No testing required** (beyond file existence or syntax check)

**Activation Decision:**

During Task Detection, the Manager evaluates the prompt and asks:
- Is this a documentation update, typo fix, or meta-file change?
- Can I complete this in under 5 steps with no spawned agents?
- Is there zero chance this breaks existing code?

If YES to all three, activate Ops Mode.

**Explicit Override:**

The user can force Ops Mode with: `"[OPS MODE]"` prefix in the prompt.
The user can block Ops Mode with: `"[FULL PIPELINE]"` prefix in the prompt.

---

## OPS MODE WORKFLOW

```
Phase 0: Task Detection
├─ Manager evaluates task
├─ Ops Mode criteria met? YES
├─ notify_say "Ops Mode activated for: <task>"
│
Phase 1: Direct Execution (Manager)
├─ Perform file operations (Read, Edit, Write, Bash)
├─ Verify changes (Read, git_status)
├─ Auto-commit (if auto-commit enabled and changes exist)
│
Phase 2: Completion Report
├─ Manager outputs brief summary
└─ notify_say "Ops Mode complete: <summary>"
```

**No agents are spawned.** The Manager handles everything directly.

---

## EXECUTION RULES

1. **Speed First:** Ops Mode prioritizes speed. Minimize tool calls. Batch reads where possible.
2. **No Over-Engineering:** Do not create elaborate solutions. Make the minimal change requested.
3. **Verify, Don't Test:** Check that files exist and syntax is valid. Do not run test suites.
4. **Auto-Commit Eligible:** Ops Mode tasks are eligible for auto-commit if enabled (see [docs/policy/git-automation.md](docs/policy/git-automation.md)).
5. **Single Iteration:** Ops Mode does not loop. If the task cannot be completed in one pass, escalate to full pipeline.

---

## FAILURE HANDLING

If the Manager encounters ANY of the following during Ops Mode execution:
- Unexpected file contents (logic that would be affected)
- Missing dependencies or imports that require research
- Syntax errors that cannot be trivially fixed
- Any indication the change is riskier than initially assessed

**Immediate Escalation:**
1. Abort Ops Mode
2. notify_say "Ops Mode aborted. Escalating to full pipeline."
3. Re-run Phase 0 with Ops Mode disabled
4. Proceed with standard multi-agent pipeline

---

## COMPLETION REPORT FORMAT

```
# OPS MODE COMPLETION REPORT

## Task
[One-line description]

## Changes Made
- [File path]: [Change description]
- [File path]: [Change description]

## Verification
[Confirm files exist, syntax valid, git status clean]

## Auto-Commit
[Yes/No] — [Commit hash if yes]

## Duration
[Start time → End time] ([X]m [Y]s)
```

**Voice Notification:**

The Manager MUST call `notify_say` with:
- Start: `"Ops Mode activated for: <task>"`
- End: `"Ops Mode complete: <summary>"`

---

## EXAMPLES

### Valid Ops Mode Tasks

✅ "Fix typo in CLAUDE.md: change 'hueristic' to 'heuristic'"
✅ "Add .DS_Store to .gitignore"
✅ "Rename docs/old-guide.md to docs/archive/old-guide.md"
✅ "Update README.md: add link to new policy file"
✅ "Add comment to install.sh explaining ctags step"

### Invalid Ops Mode Tasks (Require Full Pipeline)

❌ "Fix bug in server.js where API calls fail"
❌ "Add new MCP tool for database queries"
❌ "Refactor Analyst agent to use new evidence format"
❌ "Research best practices for error handling and update agents"
❌ "Add unit tests for factory-tools server"

---

## BUDGET IMPACT

Ops Mode conserves token budget by eliminating agent spawns. A typical Ops Mode task uses:
- Manager: 5K–15K tokens (single turn)
- Total: 5K–15K tokens

Compare to standard single-task pipeline:
- Manager: 10K–20K
- Analyst: 15K–30K
- Architect: 30K–50K
- Developer: 20K–40K
- Reviewer: 20K–40K
- Tester: 10K–20K
- Reporter: 10K–20K
- Total: 115K–220K tokens

**Ops Mode saves ~100K–200K tokens per eligible task.**

---

## INTEGRATION WITH AUTO-COMMIT

Ops Mode tasks are **ideal candidates for auto-commit** because:
- They are low-risk by definition
- They produce single, atomic changes
- They require no review or testing loop

If auto-commit is enabled (see [docs/policy/git-automation.md](docs/policy/git-automation.md)), the Manager MUST auto-commit Ops Mode changes unless:
- The user explicitly disabled auto-commit for this session
- The changes involve sensitive files (.env, credentials, etc.)

**Auto-Commit Message Format for Ops Mode:**

```
ops: <brief description>

[Optional details if needed]

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

Example:
```
ops: fix typo in CLAUDE.md (hueristic → heuristic)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

---

## POLICY REFERENCES

- **Task Detection:** [docs/policy/workflow.md](docs/policy/workflow.md)
- **Auto-Commit Protocol:** [docs/policy/git-automation.md](docs/policy/git-automation.md)
- **Failure Recovery:** [docs/policy/failure-recovery.md](docs/policy/failure-recovery.md)
- **Critical Rules:** [docs/policy/critical-rules.md](docs/policy/critical-rules.md)

---

**END OF OPS MODE POLICY**
