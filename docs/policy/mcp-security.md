# MCP SECURITY POLICY

## APPROVAL-GATED MUTATIONS (Phase 5.3)

The factory implements a three-stage approval workflow for mutating operations (WRITE/INFRASTRUCTURE tier):

### Workflow Stages

1. **Plan**: Agent creates execution plan via `ops_plan_mutation`
   - Returns `plan_id` and `plan_hash` (SHA256 of plan details)
   - Stores plan in SQLite approval database
   - Status: `pending`

2. **Approve**: Manager approves via `ops_approve`
   - Verifies `plan_hash` matches (tamper protection)
   - Checks TTL (default: 30 minutes, configurable)
   - Updates status to `approved`

3. **Execute**: Agent executes via `ops_execute`
   - Loads approved plan from database
   - Re-validates TTL
   - Executes operation (future: dispatches to CLI)
   - Stores result, updates status to `executed`

### Security Controls

- **Hash Verification**: SHA256 hash prevents plan tampering between approval and execution
- **TTL Enforcement**: Approvals expire after 30 minutes (configurable in `.claude/config/ops.json`)
- **Status Tracking**: Atomic SQLite updates prevent race conditions
- **Redaction**: All outputs pass through `redactOutput()` before returning
- **Audit Trail**: All operations logged to approval database with timestamps

### Database Schema

```sql
CREATE TABLE approvals (
  id INTEGER PRIMARY KEY,
  plan_id TEXT UNIQUE,
  plan_hash TEXT,
  plan_details TEXT,
  tier TEXT,  -- WRITE or INFRASTRUCTURE
  status TEXT DEFAULT 'pending',
  created_at INTEGER,
  approved_at INTEGER,
  executed_at INTEGER,
  result TEXT
);
```

---

## PURPOSE

This policy governs the use of MCP (Model Context Protocol) tools within the Claude Factory. It defines:
- Which agents can use which MCP tools
- What operations require elevated permissions
- How to prevent security violations
- Audit requirements for sensitive operations

This policy complements existing security controls in `critical-rules.md` and `agents.md`.

---

## PERMISSION TIERS

MCP tools are classified into four permission tiers based on their potential impact:

### Tier 1: READ (Low Risk)
**Operations:** Read-only access to code, git history, file metadata
**Risk:** Information disclosure only
**Audit:** Optional

**Tools:**
- `code_search_rg` (factory-rg)
- `fs_tree` (factory-fs)
- `fs_read_range` (factory-fs)
- `fs_list_files` (factory-fs)
- `git_status` (factory-git)
- `git_diff_stat` (factory-git)
- `git_log_oneline` (factory-git)
- `git_blame_range` (factory-git)
- `query_json` (factory-query)
- `query_yaml` (factory-query)
- `ops_discover_k8s` (factory-ops)
- `ops_discover_argocd` (factory-ops)
- `ops_discover_postgres` (factory-ops)
- `ops_discover_supabase` (factory-ops)
- `ops_discover_s3` (factory-ops, Phase 5.2)
- `ops_discover_github` (factory-ops, Phase 5.2)
- `ops_discover_docker` (factory-ops, Phase 5.2)
- `ops_discover_redis` (factory-ops, Phase 5.2)
- `ops_discover_argo_workflows` (factory-ops, Phase 5.2)

### Tier 2: WRITE (Medium Risk)
**Operations:** Create/modify files, change working tree state
**Risk:** Code modification, data loss
**Audit:** Recommended

**Tools:**
- Currently no WRITE-tier MCP tools exist
- File writes use Claude Code's Write/Edit tools (not MCP)
- Git commits use Bash `git commit` (not MCP)

### Tier 3: EXECUTE (High Risk)
**Operations:** Run external commands, trigger computation
**Risk:** Resource consumption, side effects
**Audit:** Required

**Tools:**
- `code_index_ctags` (factory-ctags) — spawns ctags process
- `research_search_web` (factory-tools) — calls external gemini CLI API

### Tier 4: INFRASTRUCTURE (Critical Risk)
**Operations:** System notifications, inter-agent communication
**Risk:** User notification spam, pipeline disruption
**Audit:** Required

**Tools:**
- `notify_say` (factory-tools) — triggers macOS voice notification
- `git_repo_diff` (factory-tools) — used by Manager for batch orchestration

---

## AGENT PERMISSION MATRIX

| Agent       | READ | WRITE | EXECUTE | INFRASTRUCTURE | Notes |
|-------------|------|-------|---------|----------------|-------|
| Manager     | ✓    | —     | ✓       | ✓              | Full access to orchestration tools |
| Analyst     | ✓    | —     | ✓*      | —              | Read-only analysis (✓* = `code_index_ctags` only) |
| Researcher  | ✓    | —     | ✓       | —              | Can call `research_search_web` |
| Architect   | ✓    | —     | ✓*      | —              | Read-only design review (✓* = `code_index_ctags` only) |
| Developer   | ✓    | —     | ✓       | —              | Can call `code_index_ctags` (incremental) |
| Reviewer    | ✓    | —     | —       | ✓*             | Read-only code review (✓* = `git_repo_diff` only) |
| Tester      | ✓    | —     | ✓*      | —              | Read-only test validation (✓* = `code_index_ctags` only) |
| Reporter    | ✓    | —     | —       | ✓              | Can call `notify_say` for final report (also `git_status`, `git_diff_stat` for auto-commit) |
| Reader      | ✓    | —     | —       | —              | Read-only utility agent |

**Permission Enforcement:**

The Manager MUST enforce these permissions by:
1. **Injecting permission rules** into agent spawn prompts (e.g., "You have READ permissions only. Do NOT call code_index_ctags or research_search_web.")
2. **Reviewing agent outputs** for unauthorized tool calls (e.g., if Analyst calls `code_index_ctags`, the Manager rejects the result and re-spawns with stronger constraints)
3. **Logging violations** in the final report when detected

---

## TOOL-SPECIFIC SECURITY CONTROLS

### code_index_ctags (EXECUTE Tier)

**Allowed Agents:** Manager, Analyst*, Architect*, Developer, Tester*
**Security Constraints:**
- Manager: Can call with `mode: "full"` or `mode: "incremental"`
- Analyst*, Architect*, Tester*: Can ONLY call with `mode: "incremental"` (restricted access for analysis/design/testing tasks)
- Developer: Can ONLY call with `mode: "incremental"`
- Developer MUST NOT call before implementation starts (Architect confirmation gate ensures ctags runs before Dev loop)
- Manager MUST run full index at batch start (multi-task only)

**Enforcement:**
```
Developer spawn prompt MUST include:
"You may call code_index_ctags ONLY with mode: 'incremental' and ONLY after you have modified files. Never call with mode: 'full'."
```

**Audit Log Entry:**
```
Agent: Developer
Tool: code_index_ctags
Mode: incremental
Timestamp: 2026-02-09T14:32:15Z
Files indexed: 3 changed files
```

### research_search_web (EXECUTE Tier)

**Allowed Agents:** Researcher
**Security Constraints:**
- ONLY Researcher can call this tool
- Manager decides whether to spawn Researcher (based on task complexity)
- Queries MUST be logged (for audit and cost tracking)

**Enforcement:**
```
Non-Researcher spawn prompts MUST include:
"You do NOT have access to research_search_web. Do not attempt external research."
```

**Audit Log Entry:**
```
Agent: Researcher
Tool: research_search_web
Query: "Rust async runtime comparison tokio vs async-std 2026"
Timestamp: 2026-02-09T14:28:42Z
Results: 8 sources
```

### notify_say (INFRASTRUCTURE Tier)

**Allowed Agents:** Manager, Reporter
**Security Constraints:**
- Manager: Can notify at workflow start, task start/end (multi-task only)
- Reporter: Can notify ONCE at final report completion
- Messages MUST be concise (max ~100 words)
- MUST NOT spam user with intermediate notifications

**Enforcement:**
```
Reporter spawn prompt MUST include:
"You may call notify_say EXACTLY ONCE to deliver the final summary. Keep it under 100 words."
```

**Audit Log Entry:**
```
Agent: Reporter
Tool: notify_say
Message: "Task complete. Implemented MCP security policy with 4 permission tiers..."
Timestamp: 2026-02-09T14:45:03Z
```

### git_repo_diff (INFRASTRUCTURE Tier)

**Allowed Agents:** Manager, Reviewer*
**Security Constraints:**
- Manager: Can call for multi-task orchestration (detect which files changed between tasks)
- Reviewer*: Can call to get structured file change list for code review (restricted access)
- MUST NOT be called by Developer/Tester (they use `git status` or Read tools)

**Enforcement:**
```
Non-Manager spawn prompts MUST NOT mention git_repo_diff.
```

**Audit Log Entry:**
```
Agent: Manager
Tool: git_repo_diff
Base: task-1-end-commit
Head: HEAD
Files changed: 4 (2 modified, 2 added)
Timestamp: 2026-02-09T14:50:12Z
```

---

## AUDIT LOGGING SPECIFICATION

### When to Log

- **EXECUTE Tier:** Log every call (ctags, research_search_web)
- **INFRASTRUCTURE Tier:** Log every call (notify_say, git_repo_diff)
- **READ Tier:** Logging optional (useful for debugging, not security-critical)
- **WRITE Tier:** N/A (no MCP write tools exist)

### Log Format

```
# MCP Audit Log — [YYYY-MM-DD]

[HH:MM:SS] Agent: <agent-name>
           Tool: <mcp-tool-name>
           Params: <key params, e.g., mode, query>
           Result: <success|failure>
           Notes: <optional context>
```

### Log Location

**Current Implementation:** Audit logs are embedded in task reports (`docs/tasks/reports/*.md`) under "MCP Tool Usage" sections.

**Future Implementation (Ops Mode):**
- Structured logs in `docs/audit/mcp-logs-YYYY-MM.jsonl`
- Queryable via `query_json` MCP tool
- Automatic log rotation (monthly)

---

## SECRET HANDLING

### Secrets in MCP Tool Calls

**Rule:** MCP tools MUST NOT accept or log secrets (API keys, tokens, passwords).

**Enforcement:**
1. **No secret parameters:** MCP tool schemas do not include secret fields
2. **Env var usage:** External tools (gemini CLI, ctags) read secrets from environment, not CLI args
3. **Log sanitization:** If a tool accepts free-form text (e.g., `research_search_web` query), the Manager MUST NOT pass secrets

**Example Violation:**
```
# BAD — Do not do this
research_search_web({
  "query": "API key: sk-1234567890abcdef..."
})
```

**Correct Approach:**
```
# GOOD — Secrets stay in environment
research_search_web({
  "query": "How to use OpenAI API for embeddings"
})
# The tool reads OPENAI_API_KEY from env, never logs it
```

### Secrets in File Operations

**Rule:** Agents MUST NOT write secrets to files tracked by git.

**Enforcement (existing controls in critical-rules.md):**
- Rule 18: Do not commit `.env`, `credentials.json`, etc.
- Pre-commit hooks (if configured) to block secret commits
- Reviewer MUST check for secrets in `Code Review Report`

**Cross-Reference (git-automation.md):**
- Commit Condition #6: Do not commit files that likely contain secrets (`.env`, `credentials.json`, etc.)
- Safety Rule #7: Warn user if they specifically request to commit secret-containing files

**MCP-Specific Addition:**
- `fs_list_files` and `fs_tree` MUST respect `.gitignore` (they already do)
- `fs_read_range` CAN read `.env` files (for debugging), but Agents MUST NOT log their contents in reports

---

## MANAGER ENFORCEMENT MECHANISMS

The Manager is responsible for enforcing this policy. Mechanisms:

### 1. Spawn Prompt Injection

**What:** The Manager injects permission rules into every agent spawn prompt.

**How:**
- READ-only agents: "You have READ permissions. MCP tools available: code_search_rg, fs_tree, ..."
- EXECUTE agents: "You have READ + EXECUTE permissions. You may call code_index_ctags with mode: incremental."
- INFRASTRUCTURE agents: "You may call notify_say ONCE at completion."

**Example (Developer spawn):**
```
You are the DEVELOPER agent.

**MCP Tools Available to You:**
- code_search_rg (factory-rg): Fast regex code search
- code_index_ctags (factory-ctags): Generate/update ctags index

**SECURITY CONSTRAINTS:**
- You may call code_index_ctags ONLY with mode: 'incremental'
- You may ONLY call it AFTER modifying files
- You do NOT have access to research_search_web or notify_say
```

### 2. Output Validation

**What:** After an agent completes, the Manager scans the output for policy violations.

**Violations to Detect:**
- Unauthorized tool calls (e.g., Analyst called `code_index_ctags`)
- Incorrect parameters (e.g., Developer called `code_index_ctags` with `mode: "full"`)
- Excessive `notify_say` calls (e.g., Reporter called it 3 times)

**Response:**
- **Soft violations (first offense):** Manager logs warning, re-spawns agent with stronger constraints
- **Hard violations (repeated or critical):** Manager aborts pipeline, reports failure to user

### 3. Audit Logging

**What:** Manager maintains an audit log of all EXECUTE and INFRASTRUCTURE tool calls.

**Format:** See "Audit Logging Specification" above.

**Location:** Embedded in task reports (current), separate log file (future Ops Mode).

### 4. Pre-Flight Checks

**What:** Before spawning an agent, Manager verifies:
- MCP servers are running (`.mcp.json` servers are active)
- Required tools are available (e.g., `ctags`, `rg`, `jq`, `yq` installed)
- No quota exhaustion (if Opus quota is low, defer Reviewer spawn)

**How:** Manager can call `mcp__factory-tools__health_check` (if such a tool existed), or run `.claude/scripts/health-check.sh` via Bash.

---

## FUTURE: OPS MODE ENHANCEMENTS

When the factory adds an **Ops Mode** (deployment, monitoring, infrastructure tasks), this policy will be extended to cover:

### New Permission Tier: DEPLOY (Critical+ Risk)

**Operations:** Deploy to production, modify infrastructure, manage secrets
**Risk:** Service outages, data loss, security breaches
**Audit:** Mandatory, with approval gates

**Future Tools:**
- `deploy_service` (factory-deploy) — Deploy to k8s/cloud
- `rotate_secret` (factory-secrets) — Update secrets in vault
- `rollback_deployment` (factory-deploy) — Revert to previous version

**Agent:** Ops Agent (Opus model, strict permissions, human-in-the-loop approval required)

### Approval Gates

**Rule:** DEPLOY-tier operations require explicit user confirmation before execution.

**Workflow:**
1. Ops Agent produces deployment plan
2. Manager presents plan to user: "Ready to deploy X to production. Confirm? (y/n)"
3. User confirms → Manager spawns Ops Agent with execute=true flag
4. User rejects → Manager aborts, logs rejection

### Audit Integration

**Rule:** All DEPLOY operations are logged to external audit system (e.g., Splunk, Datadog).

**Format:**
```json
{
  "timestamp": "2026-02-09T15:00:00Z",
  "agent": "OpsAgent",
  "tool": "deploy_service",
  "action": "deploy",
  "target": "production",
  "service": "api-gateway",
  "version": "v2.3.1",
  "approved_by": "user@example.com",
  "result": "success"
}
```

---

## INTEGRATION WITH EXISTING POLICIES

This policy builds on and references:

| Policy File | Relationship |
|-------------|--------------|
| `agents.md` | Defines which agents have MCP tool access (this policy refines it with tiers) |
| `critical-rules.md` | Rule 6 (MCP tool scopes) — this policy is the detailed specification |
| `orchestration.md` | Budget Block System — EXECUTE tools consume budget, this policy ensures they're used correctly |
| `build.md` | Fresh Tags Indexing — this policy defines who can call `code_index_ctags` and when |
| `git-automation.md` | Auto-commit protocol — this policy ensures git operations stay secure (no secret commits) |

**Precedence:** If this policy conflicts with another, **this policy takes precedence** for MCP tool usage. For non-MCP operations (e.g., file edits via Write tool), other policies apply.

---

## VALIDATION CHECKLIST

Use this checklist to verify MCP security policy compliance:

### Manager Pre-Flight
- [ ] All 6 MCP servers are running (`.mcp.json` active)
- [ ] Required CLI tools installed (`ctags`, `rg`, `jq`, `yq`, `gemini`, `say`)
- [ ] No quota exhaustion (Opus requests available for Reviewer)

### Agent Spawn
- [ ] Spawn prompt includes permission tier (READ, EXECUTE, INFRASTRUCTURE)
- [ ] Spawn prompt lists allowed MCP tools explicitly
- [ ] Spawn prompt forbids unauthorized tools (e.g., "You do NOT have access to notify_say")

### Agent Execution
- [ ] Agent only calls tools listed in spawn prompt
- [ ] Agent uses correct parameters (e.g., Developer uses `mode: incremental` for ctags)
- [ ] Agent does not attempt to bypass restrictions (e.g., using Bash instead of MCP)

### Manager Post-Execution
- [ ] Manager reviews agent output for unauthorized tool calls
- [ ] Manager logs all EXECUTE and INFRASTRUCTURE tool calls
- [ ] Manager does not propagate secrets to next agent

### Reporter Final Report
- [ ] Report includes "MCP Tool Usage" section (if tools were called)
- [ ] Report notes any security violations encountered
- [ ] Reporter calls `notify_say` exactly once (not zero, not multiple)

### Multi-Task Batch
- [ ] Manager calls `code_index_ctags` with `mode: full` at batch start (once)
- [ ] Manager calls `code_index_ctags` with `mode: incremental` at task boundaries
- [ ] Manager calls `notify_say` at task start/end (if configured)
- [ ] Manager calls `notify_say` once at batch completion

---

## REVISION HISTORY

| Version | Date       | Changes |
|---------|------------|---------|
| 1.0     | 2026-02-09 | Initial policy (4 tiers, 9 agents, 14 tools) |

**Next Review:** 2026-03-09 (or when Ops Mode is implemented)

---

**END OF POLICY**
