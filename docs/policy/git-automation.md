# GIT AUTOMATION POLICY

## OVERVIEW

The Factory automatically commits implementation changes after successful completion of the implementation loop (Phase 4) when certain conditions are met. This policy defines when auto-commits occur, commit message format, safety rules, and opt-out mechanisms.

Auto-commits reduce manual overhead and ensure the repository reflects completed work. The Reporter agent executes the auto-commit protocol as part of its final actions.

---

## COMMIT CONDITIONS

The Reporter MUST create a git commit when ALL of these conditions are met:

| # | Condition | Check |
|---|-----------|-------|
| 1 | **All quality gates passed** | Reviewer verdict == APPROVED AND Tester verdict == ALL_PASS |
| 2 | **Files were modified** | Developer's Implementation Report lists at least one created/modified/deleted file |
| 3 | **Working directory is clean** | `git status --porcelain` shows ONLY the files listed in the Developer's Implementation Report (no unexpected changes) |
| 4 | **Not a submodule change** | None of the changed files are in a submodule path (see Submodule Handling below) |
| 5 | **Auto-commit enabled** | Environment variable `CLAUDE_FACTORY_AUTO_COMMIT` is not set to `0` or `false` (default: enabled) |
| 6 | **No untracked secrets** | Changed files do NOT include `.env`, `credentials.json`, `*.pem`, `*.key`, or other secret patterns |

If ANY condition fails, the Reporter MUST skip the auto-commit and note the reason in the final report.

---

## COMMIT MESSAGE FORMAT

Auto-commit messages follow this template:

```
<type>: <brief summary>

<optional detailed description>

Context: <TASK_MODE> | <N> iteration(s) | <REVIEWER_VERDICT>

Files changed:
- <path> (created|modified|deleted)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

**Message Generation Rules:**

1. **Language** - Commit messages MUST be written in English. All sections (summary, description, context, file list) use English only.

2. **Type** - One of: `feat`, `fix`, `refactor`, `docs`, `test`, `chore`, `perf`, `style`
   - Derived from task analysis and changes made
   - Default to `feat` for new functionality, `fix` for bug fixes, `refactor` for restructuring, `docs` for documentation-only, `test` for test additions, `chore` for tooling/config

3. **Brief Summary** - 50-72 characters, imperative mood
   - Example: "Add task mode classification policy"
   - Example: "Fix memory leak in cache invalidation"
   - Example: "Refactor spawn prompt templates for modularity"

3. **Detailed Description** - Optional, 1-3 sentences explaining WHY (not WHAT)
   - Example: "This enables cost optimization by skipping unnecessary pipeline phases for simple changes."
   - Omit if the brief summary is self-explanatory

4. **Context** - MANDATORY metadata line with task mode, iteration count, and reviewer verdict
   - Format: `Context: <TASK_MODE> | <N> iteration(s) | <REVIEWER_VERDICT>`
   - Example: `Context: STANDARD | 2 iteration(s) | APPROVED`
   - Example: `Context: MICRO-CHANGE | 1 iteration(s) | APPROVED`
   - This line provides execution context for the commit (task classification, development iterations, review outcome)

5. **Files Changed** - Bulleted list of files created/modified/deleted
   - Example:
     ```
     Files changed:
     - docs/policy/task-modes.md (created)
     - docs/policy/workflow.md (modified)
     - .claude/scripts/validate-policies.sh (modified)
     ```

6. **Co-Authored-By Footer** - MANDATORY
   - Always include: `Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>`
   - This footer MUST appear at the end of every auto-commit message

**Example:**

```
feat: Add task mode classification for cost optimization

Enables the Factory to classify tasks as MICRO-CHANGE, STANDARD, or
VERIFICATION. This reduces costs by skipping unnecessary phases and
using smaller budget allocations for simple changes.

Context: STANDARD | 2 iteration(s) | APPROVED

Files changed:
- docs/policy/task-modes.md (created)
- docs/policy/workflow.md (modified)
- docs/policy/spawn-templates.md (modified)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>
```

---

## SUBMODULE HANDLING

### Overview

Submodules are git repositories embedded within a parent repository. They have separate commit histories and require distinct workflows. The Factory MUST NOT auto-commit changes to submodule paths to prevent accidental coupling of parent and submodule commit histories.

### Detection Protocol

The Reporter MUST execute the following checks before attempting an auto-commit:

**Step 1: Check for .gitmodules file**
```bash
if [[ -f .gitmodules ]]; then
  # Submodules may exist — proceed to Step 2
else
  # No submodules — skip submodule checks
fi
```

**Step 2: List all submodule paths**
```bash
git config --file .gitmodules --get-regexp path | awk '{print $2}'
```

Example output:
```
vendor/lib-a
vendor/lib-b
third-party/sdk
```

**Step 3: Check changed files against submodule paths**

For each file in the Developer's Implementation Report:
- Extract the file's directory path
- Check if it starts with any submodule path
- If match found → block auto-commit

**Example:**
```bash
# Changed file: vendor/lib-a/src/module.js
# Submodule paths: vendor/lib-a, vendor/lib-b
# Match: vendor/lib-a/src/module.js starts with vendor/lib-a
# Result: BLOCK auto-commit
```

### Blocking Behavior

When submodule changes are detected:
1. The Reporter MUST NOT run `git add` or `git commit`
2. Set `commit_note = "Auto-commit skipped: submodule changes detected"`
3. Log the blocked attempt in the final report
4. Continue with voice notification (report includes commit_note)

**No Escalation:**
Do NOT ask the user to confirm or provide guidance. Submodule changes are ALWAYS blocked from auto-commit. The user can manually commit submodule changes if needed.

### Rationale

**Why block submodule commits:**
- Submodules track specific commit SHAs — committing a submodule path in the parent repo changes the tracked SHA
- This can create unintended dependencies between parent and submodule versions
- Submodule workflows typically involve: (1) commit inside submodule, (2) commit in parent to update SHA reference
- Auto-committing both in one operation risks:
  - Bundling unrelated changes
  - Breaking submodule independence
  - Creating circular dependency issues

**Why not support submodule-aware commits:**
- Detecting "safe" submodule commits (e.g., only updating the SHA reference) is complex
- Risk of incorrect automation outweighs convenience benefit
- Manual submodule workflows are well-established and safer

### Edge Cases

**Nested Submodules:**
If a submodule contains its own submodules (nested submodules), the Factory only checks the first-level submodule paths listed in `.gitmodules`. Nested submodules within a first-level submodule are implicitly blocked (since any change to the first-level path triggers blocking).

**Submodule Removal:**
If a submodule is removed from `.gitmodules`, the Reporter will NOT block commits to the former submodule path (since `git config --file .gitmodules` will not list it). This is correct behavior — the path is no longer a submodule.

**Submodule Addition:**
If a new submodule is added during the task (Developer creates `.gitmodules` or adds new entries), the Reporter's detection will catch it and block the commit.

### Testing Submodule Detection

To verify submodule detection works:

```bash
# Add a test submodule
git submodule add https://github.com/example/lib vendor/test-lib

# Modify a file inside the submodule
echo "test" > vendor/test-lib/README.md

# Run the Factory on a task that touches the submodule
# Expected: Auto-commit should be blocked with "submodule changes detected"

# Clean up
git submodule deinit vendor/test-lib
git rm vendor/test-lib
rm -rf .git/modules/vendor/test-lib
```

---

## SAFETY RULES

The Reporter MUST follow these safety rules when executing auto-commits:

1. **No force operations** - Never use `--amend`, `--force`, or destructive flags
2. **No hook skipping** - Never use `--no-verify` or `--no-gpg-sign` (hooks must run)
3. **Verify staging** - After `git add`, run `git diff --cached --name-only` to confirm only expected files are staged
4. **Atomic operation** - If staging fails, abort and log the error (do not proceed to commit)
5. **Pre-commit hook failure** - If the commit fails due to pre-commit hooks, log the failure in the report but do NOT retry (the user must fix hook issues manually)
6. **Concurrent changes** - If `git status` shows files changed beyond the Implementation Report list, block the auto-commit and log: "Auto-commit blocked: unexpected changes detected"
7. **No credentials in diffs** - If `git diff --cached` contains patterns like `password`, `secret`, `api_key`, `token` (case-insensitive), block the commit and log: "Auto-commit blocked: potential credentials detected"

---

## ENVIRONMENT VARIABLE

Auto-commit can be disabled by setting:

```bash
export CLAUDE_FACTORY_AUTO_COMMIT=0
# or
export CLAUDE_FACTORY_AUTO_COMMIT=false
```

When disabled:
- The Reporter skips the auto-commit protocol entirely
- The final report notes: "Auto-commit skipped (disabled by environment variable)"

Default behavior: **Auto-commit is ENABLED** unless explicitly disabled.

---

## POLICY FILE REFERENCES

This policy integrates with:
- **[spawn-templates.md](spawn-templates.md)** - Reporter spawn prompt includes AUTO-COMMIT PROTOCOL steps
- **[critical-rules.md](critical-rules.md)** - Rule 27 mandates auto-commit protocol execution
- **[agents.md](agents.md)** - Reporter tool scope includes `git_status`, `git_diff_stat`
- **[workflow.md](workflow.md)** - Auto-commit happens in Phase 5 (Final Report), after Reporter writes the task report

**Cross-references:**
- AUTO-COMMIT PROTOCOL steps: see spawn-templates.md "PHASE 5: FINAL REPORT"
- Git tool scoping: see agents.md "Reporter" row in MCP Tool Scopes table
- Commit guidelines: see critical-rules.md Git Safety Protocol
