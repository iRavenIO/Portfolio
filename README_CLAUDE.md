# Technical Reference — Autonomous Multi-Agent Software Factory

This document contains the full architecture, agent pipeline, MCP integration details, and troubleshooting guide.

For a quick overview and usage instructions, see [README.md](README.md).

## Architecture

```
CLAUDE.md                        ← Global brain / Manager orchestrator
.mcp.json                        ← Project-scoped MCP config (6 servers)
install.sh                       ← Setup script (tools + deps + ctags)
.claude/
├── mcp/
│   ├── server.js                ← MCP: factory-tools (3 tools)
│   ├── server-ctags.js          ← MCP: factory-ctags (1 tool)
│   ├── server-rg.js             ← MCP: factory-rg (1 tool)
│   ├── server-fs.js             ← MCP: factory-fs (3 tools)
│   ├── server-git.js            ← MCP: factory-git (4 tools)
│   ├── server-query.js          ← MCP: factory-query (2 tools)
│   ├── package.json             ← Shared dependencies
│   └── node_modules/            ← Installed via install.sh or npm install
├── agents/
│   ├── manager.md               ← Orchestration rules (Opus) — reference only
│   ├── analyst.md               ← Task decomposition (Sonnet)
│   ├── researcher.md            ← Web research via MCP (Sonnet)
│   ├── architect.md             ← Technical design (Opus)
│   ├── developer.md             ← Implementation (Sonnet)
│   ├── reviewer.md              ← Code review quality gate (Opus)
│   ├── tester.md                ← Test writing & execution (Sonnet)
│   ├── reporter.md              ← Final report + voice via MCP (Sonnet)
│   └── reader.md                ← File reading utility (Haiku)
└── runbooks/
    └── add-mcp-server.md        ← Runbook: adding a new MCP server
docs/
└── policy/
    ├── orchestration.md         ← Smart orchestration + task complexity + budget blocks
    ├── build.md                 ← Staged build + fresh tags + ctags mode + tool-first + token usage
    └── agents.md                ← MCP tooling + model routing + reader delegation
```

## How It Works

1. User sends any prompt to Claude Code CLI in this repository
2. Claude Code reads `.mcp.json` and starts the six MCP servers automatically
3. `CLAUDE.md` instructs Claude to act as the MANAGER agent
4. The MANAGER detects single vs. multi-task prompts (Phase 0)
5. The MANAGER classifies task complexity (LOW/MEDIUM/HIGH) and derives Budget Blocks for all agents
6. The MANAGER sends a "Manager started" audible notification via `notify_say`
7. The MANAGER spawns specialized agents via the Task tool, injecting Budget Blocks and file read cache into each prompt
8. Agents use MCP tools instead of raw shell commands and self-enforce budget limits
9. Each agent uses its assigned model (Opus for critical thinking, Sonnet for execution, Haiku for file reading)
10. Outputs flow from one agent to the next
11. The MANAGER keeps the ctags index fresh by calling `code_index_ctags` in incremental mode before the implementation loop, after each Developer iteration that changes files, and at each task boundary in multi-task runs (auto-escalates to full when needed)
12. A quality loop (Developer → Reviewer → Tester) iterates until all gates pass
13. A final report is written to `docs/tasks/reports/` and a voice summary is spoken aloud via MCP

## Agent Pipeline

### Single-Task Prompt

```
USER PROMPT
    │
    ▼
[TASK DETECTION + notify_say "Manager started. Beginning work on: ..."]
    │
    ▼
┌─────────┐
│ ANALYST  │  Understands the task, produces requirements
└────┬────┘
     │
     ▼
┌──────────┐
│RESEARCHER│  Web search via MCP tool research_search_web
└────┬────┘
     │
     ▼
┌──────────┐
│ARCHITECT │  Designs the solution, creates implementation plan
└────┬────┘
     │
     ▼
[code_index_ctags incremental — pre-loop]
     │
     ▼
┌──────────────────────────────────────────────┐
│          QUALITY LOOP (max 5x)                │
│                                               │
│  DEVELOPER → [ctags incremental if changed]   │
│           → REVIEWER → TESTER                 │
│                ▲              │               │
│                └── if fail ───┘               │
└──────────────┬────────────────────────────────┘
               │
               ▼
         ┌──────────┐
         │ REPORTER │  Report → docs/tasks/reports/TASK_REPORT.md + notify_say
         └──────────┘
```

### Multi-Task Prompt

When the Manager detects multiple tasks in a single prompt, it produces an Execution Plan and runs the full pipeline per task sequentially. The Manager calls `code_index_ctags` at the start and end of each task to keep symbols fresh across task boundaries. After all tasks complete, a Batch Completion Summary is produced.

Per-task reports are written to `docs/tasks/reports/TASK_REPORT_1.md`, `TASK_REPORT_2.md`, etc. The batch summary is written to `docs/tasks/reports/BATCH_REPORT.md`.

## MCP Servers and Tools

The project runs six MCP servers, all registered in `.mcp.json` and started automatically by Claude Code.

### factory-tools (server.js)

The original server providing agent workflow tools and git utilities.

| Tool                  | Wraps           | Description                       |
|-----------------------|-----------------|-----------------------------------|
| `research_search_web` | `gemini -p`     | Web search with 500-char limit    |
| `notify_say`          | macOS `say`     | Voice output with 1000-char limit |
| `git_repo_diff`       | `git diff`      | Structured file change list (JSON)|

All three tools use `execFile` (no shell) to prevent injection attacks. `research_search_web` and `notify_say` include input length validation; `git_repo_diff` validates inputs via zod schema.

### factory-ctags (server-ctags.js)

Code indexing server for generating ctags files with real incremental support.

| Tool               | Wraps   | Description                                       |
|--------------------|---------|---------------------------------------------------|
| `code_index_ctags` | `ctags` | Generate or incrementally update a tags index      |

**Input schema:**

| Parameter | Type                       | Required | Default         | Description                               |
|-----------|----------------------------|----------|-----------------|-------------------------------------------|
| `mode`    | `"full"` \| `"incremental"` | No       | `"full"`        | `incremental` updates only changed files; auto-escalates to full when needed |
| `output`  | string                     | No       | `<repo>/tags`   | Output path for the tags file             |

**Incremental mode behavior:**
1. Reads persistent state from `.claude/index-state.json`
2. Runs `git diff --name-status <last_sha>..HEAD` to find changed files
3. Parses A/M/R/D statuses into `changed_files` and `risky_changes` (D+R count)
4. If no changes since last index → returns immediately ("skipping")
5. Runs `ctags --append` on only the changed files (fast)
6. Updates the state file with new HEAD sha, timestamp, and mode

**Auto-escalation to full rebuild** occurs when any of these are true:
- Tags file does not exist
- State file is missing or `last_indexed_sha` is missing
- `last_indexed_sha` is not an ancestor of HEAD (e.g., after rebase or force-push)
- More than 24 hours since the last full index (staleness guard)
- Changed files > 1,500 (large batch change)
- Any deletes or renames detected (append cannot remove stale symbols)
- git diff fails for any reason
- `ctags --append` fails for any reason

**Full mode behavior:**
- Uses `git ls-files` to get all tracked files
- git ls-files lists tracked files; .gitignore affects which files become tracked
- Runs `ctags -L <tmpfile> -f <output>` to rebuild the entire index
- Updates state file with `last_full_indexed_at` timestamp

**State file** (`.claude/index-state.json`, gitignored):
```json
{
  "last_indexed_sha": "abc123...",
  "last_indexed_at": 1738800000000,
  "last_mode": "incremental",
  "last_file_count": 42,
  "last_full_indexed_at": 1738750000000
}
```

**Common properties:**
- Timeout: 3 minutes (ctags), 30 seconds (git operations)
- maxBuffer: 10 MB
- If `ctags` or `git` is missing, returns error suggesting `./install.sh`

**Example calls:**
```json
{ "mode": "incremental" }
{ "mode": "full" }
```

### factory-rg (server-rg.js)

Fast code search server using ripgrep.

| Tool             | Wraps          | Description                          |
|------------------|----------------|--------------------------------------|
| `code_search_rg` | `rg` (ripgrep) | Regex search across repository files |

**Input schema:**

| Parameter     | Type                  | Required | Default      | Description                          |
|---------------|-----------------------|----------|--------------|--------------------------------------|
| `pattern`     | string                | Yes      | —            | Regex pattern to search for          |
| `path`        | string                | No       | repo root    | Directory or file to search within   |
| `glob`        | string \| string[]    | No       | —            | Glob filter(s), e.g. `"*.js"`       |
| `max_results` | number (1–1000)       | No       | 200          | Max matching lines to return         |

**Behavior:**
- Runs `rg` with `--line-number --no-heading --color never`
- Respects `.gitignore` by default (ripgrep built-in)
- Truncates output beyond `max_results` with a note
- Timeout: 1 minute, maxBuffer: 5 MB
- If `rg` is missing, suggests running `./install.sh`

**Example calls:**
```json
{ "pattern": "TODO|FIXME" }
{ "pattern": "import.*express", "glob": "*.js", "max_results": 50 }
{ "pattern": "class\\s+\\w+", "path": "src/", "glob": ["*.ts", "*.tsx"] }
```

## Fresh Tags Indexing Policy

The Manager keeps the ctags index (`tags` file at repo root) fresh throughout every run by calling `code_index_ctags` with `{ "mode": "incremental" }` at key points. The tool auto-escalates to a full rebuild when correctness requires it (see thresholds above).

| Trigger | When | Condition |
|---------|------|-----------|
| Multi-task: batch start | After Execution Plan, before Task 1 | Always (multi-task only) — uses `mode="full"` |
| Pre-loop | Before entering the Phase 4 implementation loop | Always |
| Post-Developer | After each Developer iteration, before the Reviewer | Only if files were changed |
| Multi-task: task start | Before Phase 1 of each task | Always (multi-task only) |
| Multi-task: task end | After Phase 5, before the next task | Always (multi-task only) |

**Why incremental by default:** In large repos (~36k files), a full ctags rebuild takes significant time. Incremental mode uses `git diff` to identify only changed files and runs `ctags --append`, completing in seconds rather than minutes. The auto-escalation thresholds ensure correctness is never sacrificed:

- **24h staleness** — guarantees at least one full rebuild per day to clear accumulated stale symbols
- **1,500 file threshold** — at this scale, a full rebuild is more reliable than append
- **Any delete/rename** — append cannot remove stale symbols from deleted/renamed files, so a full rebuild is triggered immediately (no threshold)

**State file:** `.claude/index-state.json` (gitignored) tracks the last indexed commit SHA, timestamps, and mode. Created automatically by `install.sh` or by the tool's first run. Do not delete this file — if missing, the next incremental call will fall back to a full rebuild.

If the MCP tool is unavailable, the Manager falls back to: `git ls-files | ctags -L - -f tags --fields=+lnS --extras=+q` via Bash. A ctags failure is logged but never blocks the pipeline.

## Git-Aware Incremental Indexing

The ctags incremental indexing in `server-ctags.js` uses git history to determine which files need re-indexing. This section documents the safety mechanisms built into the incremental pipeline.

### Ancestry Verification

Before computing a diff, the tool verifies that the last indexed SHA is an ancestor of the current HEAD using `git merge-base --is-ancestor`. This correctly detects rebases and force-pushes: after such operations, the old SHA is no longer an ancestor of the new HEAD, so the tool falls back to a full rebuild rather than computing a diff against a diverged history.

### Diff Failure Handling

If `git diff --name-status <last_sha>..HEAD` fails for any reason (even with a valid ancestor SHA), the tool immediately falls back to a full rebuild. There is no intermediate fallback (e.g., diffing against HEAD~1), because narrowing the diff range silently risks missing changed files.

### Delete/Rename Policy

Any file deletion or rename detected in the diff triggers an immediate full rebuild. The `ctags --append` mode cannot remove stale symbol entries from deleted or renamed files, so a full rebuild is the only way to ensure the index does not contain phantom symbols. There is no threshold — even a single delete or rename triggers a full rebuild.

### Unchanged Thresholds

The `MAX_CHANGED_FILES` threshold (1,500) remains in place. If the diff contains more than 1,500 changed files, a full rebuild is more reliable and often faster than appending tags for each file individually.

## Model Assignments

| Agent      | Model        | Reasoning                          |
|------------|--------------|-------------------------------------|
| Manager    | Claude Opus  | Complex orchestration decisions    |
| Analyst    | Claude Sonnet| Structured analysis                |
| Researcher | Claude Sonnet| Web search and comparison          |
| Architect  | Claude Opus  | Deep technical design              |
| Developer  | Claude Sonnet| Code implementation                |
| Reviewer   | Claude Opus  | Critical quality assessment        |
| Tester     | Claude Sonnet| Test writing and execution         |
| Reporter   | Claude Sonnet| Documentation and reporting        |

## Setup

### Quick Setup (recommended)

```bash
chmod +x install.sh && ./install.sh
```

The script:
1. Verifies macOS and Homebrew
2. Checks for `node`, `npm`, `git` (errors if missing)
3. Installs `rg` (ripgrep) and `ctags` (Universal Ctags) via Homebrew if missing
4. Runs `npm install` in `.claude/mcp/`
5. Generates an initial `tags` file at the repo root

### Manual Setup

```bash
# Install tools
brew install ripgrep universal-ctags

# Install MCP dependencies
cd .claude/mcp && npm install

# Generate initial ctags
cd /path/to/repo && git ls-files | ctags -L - -f tags --fields=+lnS --extras=+q
```

### Prerequisites

- macOS (for `say` command and Homebrew)
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code)
- Access to Claude Opus and Claude Sonnet models
- Node.js >= 18
- `gemini` CLI in PATH (for Researcher web searches)

### How MCP Servers Start

Claude Code reads `.mcp.json` from the repository root when you open the project:

```json
{
  "mcpServers": {
    "factory-tools": {
      "command": "node",
      "args": [".claude/mcp/server.js"]
    },
    "factory-ctags": {
      "command": "node",
      "args": [".claude/mcp/server-ctags.js"]
    },
    "factory-rg": {
      "command": "node",
      "args": [".claude/mcp/server-rg.js"]
    }
  }
}
```

No manual server start is needed. Claude Code manages the server lifecycle.

### Verify MCP Tools Are Available

After opening this project in Claude Code, run:

```
/mcp
```

You should see three servers listed:
- `factory-tools` — `research_search_web`, `notify_say`, `git_repo_diff`
- `factory-ctags` — `code_index_ctags`
- `factory-rg` — `code_search_rg`

## Troubleshooting

For comprehensive troubleshooting guidance covering installation failures, MCP server issues, cache/database problems, tags indexing, git operations, and configuration errors, see:

**[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)**

Quick fixes for common issues:

### MCP server not connecting
1. Run `./install.sh` to ensure everything is installed
2. Check Node.js is available: `node --version` (need v18+)
3. Verify `.mcp.json` exists at the repo root with all three servers
4. Restart Claude Code to re-read MCP config

### research_search_web returns "command not found"
Ensure `gemini` CLI is installed and in your PATH:
```bash
which gemini
# Install if missing:
npm install -g @google/genai-for-devs
```

### code_index_ctags returns "ctags not found"
```bash
./install.sh  # installs universal-ctags via Homebrew
# or manually:
brew install universal-ctags
```

### code_search_rg returns "rg not found"
```bash
./install.sh  # installs ripgrep via Homebrew
# or manually:
brew install ripgrep
```

### notify_say returns "command not found"
The `say` command is macOS-only. On other platforms, the tool will return an error and the Reporter will note it in the report.

### Agents falling back to Bash
If MCP tools are unavailable, agents will automatically fall back to running tools directly via the Bash tool. The workflow still works — MCP just provides safer, validated execution.

---

## Changelog

### Phase 2.5: Stabilization & Adaptive Escalation

**Goal:** Introduce formal failure recovery and adaptive model escalation to improve implementation loop reliability.

**Changes:**
- **New policy file**: Created `docs/policy/failure-recovery.md` (~250 lines) defining structured failure handling and adaptive model escalation for the implementation loop
- **Failure Type Taxonomy**: Five distinct failure categories (TOOL_FAILURE, AGENT_RUNTIME_ERROR, PARTIAL_OUTPUT, VALIDATION_FAILURE, REVIEW_REJECTION) with clear detection criteria
- **Manager Recovery Matrix**: Deterministic recovery actions for each failure type (retry with escalation, re-spawn with clarification, continue loop with feedback)
- **Adaptive Model Escalation**: Three escalation rules for Developer spawns during Phase 4:
  - **Iteration Escalation Ladder**: Use Opus for iterations 3+ (issues remaining after 2 iterations need stronger reasoning)
  - **Failure-Triggered Escalation**: Use Opus if Developer experienced 2+ failures in current task
  - **Complexity-Triggered Escalation**: Use Opus for final iteration of HIGH complexity tasks
- **Escalation precedence over quota modes**: Escalation rules override conserve_sonnet/conserve_opus model assignments for Developer — correctness takes priority over cost
- **Pre-Review tool scope fix**: Corrected Pre-Review Agent MCP tool scope in `spawn-templates.md` (removed `code_index_ctags`, added `fs_read_range`)
- **Developer conserve_sonnet clarification**: Added Section 4.3 to `quota.md` explaining why Developer remains Sonnet in conserve_sonnet mode (cost-quality balance, automatic escalation exists, prevents Opus overuse)
- **Cross-references added**: Updated `orchestration.md`, `workflow.md`, `critical-rules.md`, `agents.md`, and `CLAUDE.md` with failure recovery policy references
- **Verification scripts extended**: Updated `.claude/scripts/validate-policies.sh` with 3 new checks for failure-recovery.md (existence, 5 failure types, 3 escalation rules); updated `.claude/scripts/health-check.sh` to include failure-recovery.md in policy file checks

**How escalation works:**
- The Manager tracks `developer_iteration` and `developer_failure_count` during each task's Phase 4 loop
- Before each Developer spawn, the Manager computes the model: baseline = Sonnet, then apply escalation rules (highest tier wins)
- State variables reset at task boundaries in multi-task runs
- Escalation applies only to Developer in Phase 4 — other agents use baseline model assignments unless they individually fail and trigger recovery escalation

**Files created:**
- `docs/policy/failure-recovery.md`

**Files modified:**
- `docs/policy/spawn-templates.md` (Pre-Review tool scope fix)
- `docs/policy/quota.md` (Section 4.3: Developer conserve_sonnet rationale)
- `docs/policy/orchestration.md` (Failure Recovery Cross-Reference section)
- `docs/policy/workflow.md` (Failure Recovery paragraph in Per-Task Pipeline)
- `docs/policy/critical-rules.md` (Rule 26 + updated Error Handling section)
- `docs/policy/agents.md` (Escalation override note after MODEL ASSIGNMENTS table)
- `CLAUDE.md` (POLICIES table + architecture tree)
- `README_CLAUDE.md` (this changelog)
- `.claude/scripts/validate-policies.sh` (3 new validation checks)
- `.claude/scripts/health-check.sh` (failure-recovery.md added to policy file list)

**Verification:**
```bash
.claude/scripts/health-check.sh        # Should include failure-recovery.md in policy checks
.claude/scripts/validate-policies.sh   # Should validate failure-recovery.md structure (5 types, 3 rules)
grep -c "failure-recovery.md" CLAUDE.md  # Should show 2 occurrences (POLICIES table + tree)
grep "Escalation override" docs/policy/agents.md  # Should find escalation note after MODEL ASSIGNMENTS
```

---

### Phase 2.6: Scaling & Cost Optimization

**Goal:** Transform the Factory into a scalable, cost-efficient workflow by implementing task mode classification, progressive notifications, micro-change pipeline optimization, architect confirmation gates, automatic git commits, and enhanced validation scripts.

**Changes:**
- **Task Mode Classification**: Created `docs/policy/task-modes.md` (~120 lines) defining three task modes (MICRO-CHANGE, STANDARD, VERIFICATION) with detection heuristics and pipeline behavior matrix. MICRO-CHANGE tasks skip Architect phase and use reduced budgets (tiny/tiny/short) with max 2 loop iterations. VERIFICATION tasks skip implementation phases entirely for read-only analysis.
- **Progressive Phase Notifications**: Enhanced `docs/policy/workflow.md` with Progressive Phase Notifications section defining notification schedule for Phases 1-4. Updated `docs/policy/spawn-templates.md` with HTML comment reminders after each phase. Updated critical-rules.md Rule 14 to reference progressive notifications.
- **Micro-Change Pipeline**: Updated `docs/policy/workflow.md` with Task Mode Classification section and modified Execution Plan format to include mode classification. Added MICRO-CHANGE MODE SPAWN VARIANTS section to `docs/policy/spawn-templates.md` with specialized spawn prompts for Developer, Reviewer, and Tester agents using reduced budgets and lightweight verification.
- **Architect Confirmation Gate**: Added ARCHITECT CONFIRMATION GATE section to `docs/policy/orchestration.md` defining trigger conditions (STANDARD mode + HIGH complexity + ambiguity markers), gate behavior with user confirmation protocol, and bypass mechanism via CLAUDE_FACTORY_SKIP_CONFIRMATION environment variable.
- **Automatic Git Commit**: Created `docs/policy/git-automation.md` (~100 lines) defining 6 commit conditions, commit message format with Co-Authored-By footer, submodule handling rules, and 7 safety rules. Added AUTO-COMMIT PROTOCOL to Reporter spawn prompt in `docs/policy/spawn-templates.md`. Added Rules 27-28 to `docs/policy/critical-rules.md`. Updated `docs/policy/agents.md` to add git_status and git_diff_stat to Reporter tool scope.
- **Validation Scripts**: Enhanced `.claude/scripts/validate-policies.sh` with 8 new validation checks (18-25) for task-modes.md, git-automation.md, MICRO-CHANGE variants, AUTO-COMMIT PROTOCOL, progressive notifications, and Architect Confirmation Gate. Updated both validation scripts to include new policy files in POLICY_FILES arrays.
- **Documentation**: Updated CLAUDE.md POLICIES table with new policy files, architecture tree with task-modes.md and git-automation.md entries, and rule count from 25 to 28. Added Phase 2.6 changelog to README_CLAUDE.md.

**Environment Variables:**

| Variable | Default | Purpose |
|----------|---------|---------|
| `CLAUDE_FACTORY_AUTO_COMMIT` | `1` (enabled) | Set to `0` or `false` to disable automatic git commits after successful implementation |
| `CLAUDE_FACTORY_SKIP_CONFIRMATION` | `0` (disabled) | Set to `1` to bypass Architect Confirmation Gate for HIGH complexity tasks |

**Files created:**
- `docs/policy/task-modes.md`
- `docs/policy/git-automation.md`

**Files modified:**
- `docs/policy/workflow.md` (Progressive Phase Notifications + Task Mode Classification + Execution Plan format)
- `docs/policy/spawn-templates.md` (Progressive notification comments + MICRO-CHANGE variants + AUTO-COMMIT PROTOCOL)
- `docs/policy/critical-rules.md` (Rule 14 update + Rules 27-28)
- `docs/policy/orchestration.md` (Architect Confirmation Gate section)
- `docs/policy/agents.md` (Reporter tool scope: git_status, git_diff_stat)
- `CLAUDE.md` (POLICIES table + architecture tree + rule count 25→28)
- `README_CLAUDE.md` (this changelog)
- `.claude/scripts/validate-policies.sh` (8 new validation checks + 2 policy files in arrays)
- `.claude/scripts/health-check.sh` (2 policy files added to POLICY_FILES array)

**Verification:**
```bash
.claude/scripts/health-check.sh        # Should include task-modes.md and git-automation.md in policy checks
.claude/scripts/validate-policies.sh   # Should run 25 validation checks (17 original + 8 new)
grep -c "task-modes.md" CLAUDE.md      # Should show 2 occurrences (POLICIES table + tree)
grep -c "git-automation.md" CLAUDE.md  # Should show 2 occurrences (POLICIES table + tree)
grep "28 critical rules" CLAUDE.md     # Should find updated rule count
grep "MICRO-CHANGE MODE SPAWN VARIANTS" docs/policy/spawn-templates.md  # Should find new section
grep "AUTO-COMMIT PROTOCOL:" docs/policy/spawn-templates.md  # Should find auto-commit steps
grep "Progressive Phase Notifications" docs/policy/workflow.md  # Should find new section
grep "ARCHITECT CONFIRMATION GATE" docs/policy/orchestration.md  # Should find new section
```

---

### Phase 3: Observability & Token Governance

**Goal:** Add comprehensive observability, token tracking, and enhanced submodule safety to enable cost analysis and continuous improvement.

**Changes:**
- **Observability Policy**: Created `docs/policy/observability.md` (~250 lines) defining Token Ledger System, Performance Metrics, Logging Specification, Audit Trail, and Telemetry Data Points. Token ledger tracks input/output/total tokens per agent spawn with phase, model, and iteration metadata.
- **Token Ledger Integration**: Updated `docs/policy/spawn-templates.md` to inject TOKEN LEDGER DATA and EXECUTION TIMING sections into Reporter spawn prompts (both single-task and batch). Reporter now produces EXECUTION METRICS section in all task reports with token usage by phase, model tier distribution, and loop iteration counts.
- **Enhanced Logging Script**: Updated `.claude/scripts/run-with-logging.sh` to include pre-flight health checks, environment variable reporting, execution timing, and report location hints. Added CLAUDE_FACTORY_SKIP_HEALTH_CHECK and CLAUDE_FACTORY_LOG_METRICS environment variables.
- **Submodule Safety Enhancement**: Expanded `docs/policy/git-automation.md` SUBMODULE HANDLING section with detailed detection protocol (3-step check), blocking behavior rules, rationale explanation, edge case handling (nested submodules, removal, addition), and testing procedure.
- **Validation Script Updates**: Added 4 new validation checks (27-30) to `.claude/scripts/validate-policies.sh` for observability.md existence, section structure (TOKEN LEDGER SYSTEM, PERFORMANCE METRICS, LOGGING SPECIFICATION), TOKEN LEDGER DATA references in spawn-templates.md (≥2), EXECUTION TIMING references (≥2), and EXECUTION METRICS report format specification.

**How Token Ledger Works:**
- Manager maintains in-memory JSON array of token usage entries during task execution
- After each agent completes, Manager extracts token counts from Task tool response metadata and appends entry with agent, phase, model, iteration, tokens_input, tokens_output, tokens_total, timestamp
- Reporter receives full ledger in spawn prompt and produces token usage tables in final report
- Ledger is discarded after task completes (not persisted to disk — historical analysis uses task reports)

**Observability Data Points:**
| Metric | Source | Purpose |
|--------|--------|---------|
| Total tokens (input/output) | Token ledger | Cost attribution |
| Tokens by model tier | Token ledger | Quota planning |
| Tokens by phase | Token ledger | Bottleneck identification |
| Loop iterations | Manager (Phase 4) | Quality loop efficiency |
| Failure events | Manager (all phases) | Reliability tracking |
| Total duration | Manager (start/end) | Performance monitoring |

**Submodule Safety Improvements:**
- 3-step detection protocol (check .gitmodules → list paths → match changed files)
- Blocking behavior clearly defined (no escalation, no user prompt)
- Edge case handling documented (nested submodules, removal, addition)
- Testing procedure provided for verification

**Files created:**
- `docs/policy/observability.md`

**Files modified:**
- `docs/policy/spawn-templates.md` (TOKEN LEDGER DATA + EXECUTION TIMING sections for Reporter and Batch Reporter)
- `.claude/scripts/run-with-logging.sh` (enhanced observability features)
- `docs/policy/git-automation.md` (expanded SUBMODULE HANDLING section)
- `.claude/scripts/validate-policies.sh` (4 new validation checks + observability.md in POLICY_FILES array)
- `README_CLAUDE.md` (this changelog)

**Verification:**
```bash
.claude/scripts/health-check.sh                        # Should include observability.md in policy checks
.claude/scripts/validate-policies.sh                   # Should run 30 validation checks (26 original + 4 new)
grep -c "observability.md" CLAUDE.md                   # Should show 2 occurrences (POLICIES table + tree)
grep "TOKEN LEDGER DATA" docs/policy/spawn-templates.md # Should find injected sections in Reporter + Batch Reporter
grep "SUBMODULE HANDLING" docs/policy/git-automation.md # Should find expanded section with 3-step protocol
```

---

### Phase 3.1: Always-On Logging & Run UX

**Goal:** Provide a lightweight, always-on runner script for transparent logging and improved run UX.

**Changes:**
- **cf runner script**: Created `./cf` POSIX sh wrapper (62 lines) that provides automatic logging, run ID generation, environment variable export, and exit code propagation with zero configuration
- **Log directory**: Added `/.claude/logs/` to `.gitignore` for automatic log file exclusion
- **Runner Observability**: Added "Runner Observability" subsection to `docs/policy/observability.md` documenting `./cf` usage, environment variables (`CLAUDE_FACTORY_RUN_ID`, `CLAUDE_FACTORY_LOG_FILE`), and Reporter integration pattern
- **Reporter Context Injection**: Added RUNNER CONTEXT paragraph to Reporter spawn prompt in `docs/policy/spawn-templates.md` instructing Reporter to include Run ID and Log File in EXECUTION METRICS when environment variables are present
- **Validation Script Updates**: Added 2 new validation checks (31-32) to `.claude/scripts/validate-policies.sh` for cf script existence/executability and Runner Observability section presence
- **Health Check Updates**: Added check 13 to `.claude/scripts/health-check.sh` for cf script validation (warns if missing, errors if not executable)
- **Deprecation Notice**: Added deprecation comment to `.claude/scripts/run-with-logging.sh` noting `./cf` is now the recommended default runner

**Usage:**
```bash
./cf claude "build the login page"
# Output: Banner with Run ID, log file path, command
# Log file: .claude/logs/run-20260209-143022.log
# Environment: CLAUDE_FACTORY_RUN_ID=20260209-143022
```

**Design Principles:**
- **POSIX sh** for maximum portability (no bash-isms, no zsh extensions)
- **Zero dependencies** (no npm, no external tools beyond sh and standard Unix utilities)
- **Exit code propagation** (uses temp file strategy for PIPESTATUS-free compatibility)
- **Minimal overhead** (< 1ms startup time, tee has negligible performance impact)
- **Non-intrusive** (users can still run `claude` directly; `./cf` is optional but recommended)

**Files created:**
- `cf` (62 lines, POSIX sh runner script)

**Files modified:**
- `.gitignore` (added `/.claude/logs/`)
- `docs/policy/observability.md` (added Runner Observability subsection after line 148)
- `docs/policy/spawn-templates.md` (added RUNNER CONTEXT paragraph after line 744)
- `.claude/scripts/validate-policies.sh` (added checks 31-32 before Summary)
- `.claude/scripts/health-check.sh` (added check 13 before Summary)
- `.claude/scripts/run-with-logging.sh` (added deprecation notice after line 28)
- `README_CLAUDE.md` (this changelog)

**Verification:**
```bash
./cf --help                                  # Should show usage message
ls -lh .claude/logs/                         # Should be empty initially (logs created on first run)
.claude/scripts/health-check.sh              # Check 13 should pass
.claude/scripts/validate-policies.sh         # Checks 31-32 should pass
grep "Runner Observability" docs/policy/observability.md  # Should find new subsection
grep "RUNNER CONTEXT" docs/policy/spawn-templates.md      # Should find Reporter injection
```

---

### Phase 2.4: Quota-Aware Model Mix

**Goal:** Add quota-aware orchestration that adjusts model assignments based on API quota status, reducing reliance on high-tier models when quotas are constrained.

**Changes:**
- **New policy file**: Created `docs/policy/quota.md` (~200 lines) defining three quota modes (balanced, conserve_sonnet, conserve_opus) with a 9-row decision table mapping (Complexity × Mode) to model assignments
- **Quota Snapshot format**: Standardized optional context block injected into all agent spawn prompts (between BUDGET BLOCK and FILES ALREADY READ)
- **Pre-Review Pass protocol**: New lightweight Sonnet agent (Step 4A.6) that runs between Developer and Reviewer when quota_mode=conserve_opus and complexity=MEDIUM, offloading mechanical checks from Tier 1 Reviewer
- **Evidence Pack extension**: Added PRE-REVIEW FINDINGS section to Evidence Pack format in `docs/policy/orchestration.md` (included conditionally when Pre-Review Pass runs)
- **Spawn template updates**: Injected QUOTA SNAPSHOT block into all 8 phase templates in `docs/policy/spawn-templates.md`; added Pre-Review Pass template (Step 4A.6) and PRE-REVIEW CONTEXT/TEST RECOMMENDATIONS paragraphs for Reviewer and Tester
- **Policy references updated**: Added quota.md to CLAUDE.md POLICIES table and system architecture tree
- **Verification scripts extended**: Updated `.claude/scripts/validate-policies.sh` with 6 new checks for quota.md existence, QUOTA SNAPSHOT reference count (≥8), decision table structure (≥9 rows), PRE-REVIEW FINDINGS, and Pre-Review Pass template; updated `.claude/scripts/health-check.sh` to include quota.md in policy file checks

**How to choose a quota mode:**
- **balanced** (default): Use when all quotas are healthy (≥50% remaining)
- **conserve_sonnet**: Use when all-models quota is low/critical (<50%) but Sonnet-only quota is healthy; shifts LOW-complexity tasks to Haiku and MEDIUM/HIGH Analysts/Reporters to Opus
- **conserve_opus**: Use when Opus usage should be minimized (e.g., Sonnet-only quota healthy but approaching limits); shifts Architect and Reviewer to Sonnet for LOW/MEDIUM tasks and enables Pre-Review Pass for MEDIUM tasks

**Files created:**
- `docs/policy/quota.md`

**Files modified:**
- `docs/policy/orchestration.md` (Evidence Pack extension with PRE-REVIEW FINDINGS section)
- `docs/policy/spawn-templates.md` (QUOTA SNAPSHOT in all 8 templates + Pre-Review Pass template + Reviewer/Tester context extensions)
- `CLAUDE.md` (POLICIES table + architecture tree)
- `README_CLAUDE.md` (this changelog)
- `.claude/scripts/validate-policies.sh` (6 new validation checks)
- `.claude/scripts/health-check.sh` (quota.md added to policy file list)

**Verification:**
```bash
.claude/scripts/health-check.sh        # Should include quota.md in policy checks
.claude/scripts/validate-policies.sh   # Should validate quota.md structure
grep -c "QUOTA SNAPSHOT" docs/policy/spawn-templates.md  # Should show ≥8 occurrences
grep "PRE-REVIEW PASS" docs/policy/spawn-templates.md    # Should find Step 4A.6 template
```

---

### Phase 2.3: CLAUDE.md Optimization & Self-Verification

**Goal:** Reduce CLAUDE.md size by ~75% and add self-verification scripts.

**Changes:**
- **CLAUDE.md modular refactor**: Extracted ~550 lines (Phase 0, Phases 1-6 spawn prompts, and Critical Rules sections) into 3 new policy files in `docs/policy/`:
  - `workflow.md` (Phase 0: Task Detection, Execution Plan, Per-Task Pipeline)
  - `spawn-templates.md` (Phases 1-6 agent spawn prompts with MCP Tool Rules and Budget Blocks)
  - `critical-rules.md` (25 critical rules, context passing pattern, error handling)
- CLAUDE.md is now a thin entry file (~210 lines, down from 801 lines) with link blocks pointing to policy files
- **Verification scripts**: Added `.claude/scripts/health-check.sh` and `.claude/scripts/validate-policies.sh`
- **install.sh integration**: Both verification scripts run automatically at the end of `install.sh`
- **Fixed cross-references**: Updated 8 TOOL-FIRST policy references in `spawn-templates.md` to point to `docs/policy/build.md` (instead of "CLAUDE.md")
- **Fixed policy references**: Updated 2 policy file references in `critical-rules.md` to point to `docs/policy/build.md` and `docs/policy/orchestration.md`
- **README updates**: Added Configuration section to README.md with environment variables table and verification script usage

**Files created:**
- `docs/policy/workflow.md`
- `docs/policy/spawn-templates.md`
- `docs/policy/critical-rules.md`
- `.claude/scripts/health-check.sh`
- `.claude/scripts/validate-policies.sh`

**Files modified:**
- `CLAUDE.md` (801 → 210 lines, ~74% reduction)
- `install.sh` (integrated verification scripts)
- `README.md` (added Configuration section)
- `README_CLAUDE.md` (this changelog)

**Verification:**
```bash
.claude/scripts/health-check.sh        # All checks should pass
.claude/scripts/validate-policies.sh   # All validations should pass
wc -l CLAUDE.md                        # Should show ~210 lines
```

---

### Phase 2.2: Dynamic Budgets & Token Governance

Introduced task complexity classification and budget governance layer to reduce token waste:
- **Task Complexity Classification**: All tasks are classified as LOW, MEDIUM, or HIGH complexity during Phase 0
- **Budget Block System**: Manager derives and injects Budget Blocks (tools, file_reads, output_detail) into every agent prompt
- **Budget Enforcement**: Agents self-monitor and escalate via NEEDS_MANAGER_ACTION when budget is insufficient
- **File Read Cache Formalization**: FILES_ALREADY_READ list injected into every agent prompt to prevent redundant reads
- **CLAUDE.md Modular Refactor**: Extracted ~600 lines into three policy files (docs/policy/orchestration.md, build.md, agents.md)
- **Configurable ctags Mode**: Added CLAUDE_FACTORY_CTAGS_MODE environment variable (smart | always | off)

Files modified:
- Created: docs/policy/orchestration.md, docs/policy/build.md, docs/policy/agents.md
- Modified: CLAUDE.md (slim index ~450 lines), all 8 agent files (budget enforcement rules), README_CLAUDE.md

### Phase 2.1: Smart Orchestration (Token Reduction)

Added smart orchestration rules to reduce token consumption:
- **Evidence Pack**: Standardized context bundle for Reviewer/Tester (eliminates redundant repo searches)
- **Pre-review deliverables verification**: Manager validates implementation completeness before spawning Reviewer
- **In-run file read cache**: Policy to prevent duplicate file reads within a task run
- **Test level system**: SMOKE vs FULL sub-classification for MILESTONE tasks
- **Smart ctags refresh**: Skip post-Developer ctags when no files changed

Files modified: CLAUDE.md, .claude/agents/reviewer.md, .claude/agents/tester.md, README_CLAUDE.md
