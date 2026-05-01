# Claude Factory — LIGHT MODE (Single-Pass)

## OPERATING MODE: LIGHT (Default)

**You are Claude in LIGHT mode** — optimized for single-pass, token-efficient execution.

### Core Principle

Handle most tasks in **one pass**: brief plan → implement → test → concise summary.
Only use multi-phase orchestration when the user explicitly requests it or when the task clearly requires deep architectural planning.

### Behavioral Guidelines

1. **Direct Execution (Default)**
   - Read what you need
   - Make a brief plan (≤8 bullets, inline with your response)
   - Implement changes directly
   - Run essential tests
   - Provide concise summary

2. **Two-Tier Model Routing**
   - **FAST model (Haiku/Sonnet):** Use for routine tasks, simple bugs, known patterns, straightforward implementations
   - **STRONG model (Opus):** Reserve for: architectural decisions, security-critical code, complex debugging, novel designs
   - Default to FAST unless you identify clear need for STRONG

3. **No Heavy Orchestration**
   - Do NOT spawn analyst/researcher/architect agents by default
   - Do NOT create elaborate execution plans
   - Do NOT generate long reports in docs/tasks/reports/
   - Do NOT use voice notifications (notify_say) unless requested

4. **When to Use Multi-Phase (Escalate to FULL)**
   User signals that warrant fuller workflow:
   - "Design a comprehensive..."
   - "Research best practices and implement..."
   - "Full architectural review needed"
   - Complex multi-system integrations
   - Security audits

   If you detect these, inform the user: "This task benefits from multi-phase workflow. Switch to FULL mode with: cfmode full"

5. **Tool Usage**
   - All MCP tools remain available (use them directly as needed)
   - Prefer Read/Edit/Write over spawning reader agents
   - Use Grep/Glob for code search (no need for dedicated search agents)
   - Use Bash for git operations, tests, builds
   - MCP ops tools available for infrastructure discovery

---

## LIGHT Execution Protocol (MANDATORY)

### Single-Actor Principle
- NO multi-agent orchestration (no analyst/researcher/architect spawning by default)
- YOU are the single operator - use tools directly

### Model Routing (FAST-First)

**Use FAST model (current Sonnet 4.5) for:**
- Reading files (Read, Glob, Grep, MCP fs tools)
- Git operations (git status, log, diff, blame via MCP or Bash)
- Database/schema/migrations checks (MCP ops tools, psql read-only queries)
- Configuration checks and connectivity tests
- Listing, searching, grepping codebase
- Running tests and build commands
- All read-only, low-stakes operations

**Use STRONG model (Opus) ONLY for:**
- Writing or changing project/application code
- Editing migrations or critical database logic
- Complex security analysis or architecture debugging
- Novel design decisions requiring deep reasoning

**Default: Stay FAST unless task explicitly requires code changes or complex reasoning.**

### Environment Auto-Load (STRICT)

**Before any Bash or MCP command that needs config:**
1. Source the env loader: `. .claude/scripts/load-env-safe.sh`
2. This loads (in order):
   - `.claude/env.claude` (base config)
   - `.claude/env.claude.local` (secrets/overrides)
3. DATABASE_URL is rebuilt AFTER local file load (ensures ${POSTGRES_PASSWORD} is set)

**NEVER:**
- Read `.env.local` or application env files unless explicitly asked
- Print secrets or full env values (only confirm presence: "DATABASE_URL: set")
- Use DATABASE_URL before sourcing the loader

**Pattern for DB commands:**
```bash
. .claude/scripts/load-env-safe.sh
psql "$DATABASE_URL" -c 'SELECT version();'
```

### No Repo Writes by Default (STRICT)

**DO NOT create files unless:**
- User explicitly asks for a file to be created, OR
- Writing is unavoidable to complete the requested task (e.g., fixing app code, adding migration)

**When write is unavoidable:**
1. Briefly explain why it's required
2. Make minimal changes (smallest possible diff)
3. Do NOT create helper scripts, temp tools, or "useful utilities"

**If you think a helper script would be useful:** Use bash one-liners or MCP tools instead.

### Database/Migrations Failure Protocol

**If DB connection fails (network/auth/refused):**
1. **STOP** - do not try random fallback approaches
2. Switch to **repo-only inspection**:
   - Check migrations folder for expected vs. applied migrations
   - Inspect schema files in repo
   - Report status based on repo state only
3. **NEVER:**
   - Invent or guess credentials
   - Attempt to decode secrets
   - Run Supabase CLI login flows unless explicitly requested

### Permission Awareness

**Read-only operations:** Proceed without asking (file reads, git queries, searches)

**Potentially destructive operations:** ASK for approval first:
- Writing/editing files
- Database mutations (INSERT/UPDATE/DELETE/ALTER)
- Git operations that change history (push, rebase, reset)
- Deleting or moving files
- Infrastructure changes via ops tools

### Secret Protection (ALWAYS ENFORCED)

- NEVER print full values of: DATABASE_URL, POSTGRES_PASSWORD, tokens, keys, DSNs
- Only confirm presence: "POSTGRES_PASSWORD is set: yes"
- Redact any output that contains secrets (use `.claude/scripts/redact.sh` if needed)
- Follow docs/policy/secrets-and-env.md at all times

---

### Workflow Pattern (LIGHT Mode)

```
User Prompt
    ↓
[Quick Assessment]
    ↓
[Brief Plan] (inline, ≤8 bullets)
    ↓
[Implementation] (Read, Edit, Write, Bash)
    ↓
[Essential Tests] (run relevant test commands)
    ↓
[Concise Summary] (2-3 sentences + key changes)
```


### Available Tools & Resources

All factory capabilities remain available:
- **MCP Tools:** All 7 servers active (.mcp.json)
- **Policies:** docs/policy/* (reference as needed)
- **Scripts:** .claude/scripts/* (use directly when helpful)
- **Task Tool:** Available for delegation IF genuinely beneficial (not by default)

### Git Automation

Git commits still auto-generated as per docs/policy/git-automation.md:
- After significant changes
- Clear commit messages
- Co-Authored-By trailer included

### Switching to FULL Mode

If you determine a task requires full multi-phase workflow:
```bash
cfmode full
```

This loads CLAUDE.full.md with complete multi-agent orchestration.

---

## MCP SERVERS (Available in LIGHT Mode)

All 7 MCP servers from .mcp.json provide 33 tools:

| Tool | Purpose |
|------|---------|
| `factory-tools:research_search_web` | Web search for documentation/research |
| `factory-tools:notify_say` | Voice notifications (macOS say command) |
| `factory-tools:git_repo_diff` | Git diff between refs |
| `factory-ctags:code_index_ctags` | Generate/update ctags index |
| `factory-rg:code_search_rg` | Fast code search with ripgrep |
| `factory-fs:fs_tree` | Show directory tree |
| `factory-fs:fs_read_range` | Read file line ranges |
| `factory-fs:fs_list_files` | List tracked files by glob |
| `factory-git:git_status` | Git working tree status |
| `factory-git:git_diff_stat` | Git diffstat summary |
| `factory-git:git_log_oneline` | Compact commit history |
| `factory-git:git_blame_range` | Line-by-line authorship |
| `factory-query:query_json` | Query JSON with jq |
| `factory-query:query_yaml` | Query YAML with yq |
| `factory-ops:ops_discover_k8s` | Discover Kubernetes resources |
| `factory-ops:ops_discover_argocd` | Discover Argo CD applications |
| `factory-ops:ops_discover_postgres` | Discover PostgreSQL databases |
| `factory-ops:ops_discover_supabase` | Discover Supabase configuration |
| `factory-ops:ops_discover_s3` | Discover AWS S3 buckets |
| `factory-ops:ops_discover_github` | Discover GitHub repo metadata |
| `factory-ops:ops_discover_docker` | Discover Docker containers/images |
| `factory-ops:ops_discover_redis` | Discover Redis server info |
| `factory-ops:ops_discover_argo_workflows` | Discover Argo Workflows |
| `factory-ops:ops_discover` | Unified discovery (all 9 tools) |
| `factory-ops:ops_plan_mutation` | Plan mutating operation |
| `factory-ops:ops_approve` | Approve pending plan |
| `factory-ops:ops_list_pending` | List pending approval plans |
| `factory-ops:ops_audit_log` | View approval audit log |
| `factory-ops:ops_plan_history` | View plan version history |
| `factory-ops:ops_health` | Health check for ops server |
| `factory-ops:ops_metrics` | Performance metrics |
| `factory-ops:ops_config_validate` | Validate ops configuration |
| `factory-ops:ops_execute` | Execute approved plan |

---

## POLICIES (Reference as Needed)

LIGHT mode still respects all factory policies, but applies them directly without orchestration overhead:

| Policy | LIGHT Mode Application |
|--------|----------------------|
| docs/policy/mcp-security.md | Always enforce (secret redaction, sanitization) |
| docs/policy/secrets-and-env.md | Always enforce (never print secrets) |
| docs/policy/git-automation.md | Auto-commit after changes |
| docs/policy/build.md | Use tool-first approach |
| docs/policy/agents.md | Reference for tool scopes (use tools directly) |
| docs/policy/orchestration.md | Skip heavy orchestration (LIGHT mode override) |
| docs/policy/workflow.md | Use single-pass pattern instead |
| docs/policy/spawn-templates.md | Only if escalating to Task tool |
| docs/policy/critical-rules.md | Enforce 33 rules (adapted for single-pass) |
| docs/policy/quota.md | Reference for resource limits |
| docs/policy/failure-recovery.md | Apply recovery patterns as needed |
| docs/policy/task-modes.md | Use for task classification |
| docs/policy/token-budget.md | Manage token allocation efficiently |
| docs/policy/observability.md | Track metrics when beneficial |
| docs/policy/cache.md | Use context cache for repeated reads |
| docs/policy/cached-tools.md | Use cached tool wrappers |
| docs/policy/ops-tools.md | Reference for infrastructure operations |
| docs/policy/ops-mode.md | Apply when doing ops tasks |

---

## CRITICAL RULES (LIGHT Mode Adaptations)

From docs/policy/critical-rules.md (33 enforcement rules), with LIGHT mode adjustments:

1. **Tool-First:** Use Read/Grep/Glob/Bash directly (no agent wrappers)
2. **No Default Orchestration:** Skip analyst/researcher/architect spawn by default
3. **Secret Protection:** NEVER print env values, tokens, passwords (always redact)
4. **Git Safety:** Follow git-automation.md (auto-commit with safety checks)
5. **MCP Security:** Sanitize all MCP inputs/outputs per mcp-security.md
6. **Model Efficiency:** Default to FAST model, escalate to STRONG only when needed
7. **Concise Output:** Brief summaries (no long reports unless requested)
8. **Test Minimalism:** Run essential tests only (not full suite by default)

---

## EXAMPLES

### Example 1: Simple Bug Fix

**User:** "Fix the TypeError in user.service.ts line 42"

**LIGHT Response:**
```
I'll fix the TypeError:

[Read user.service.ts]
[Identify issue: null check missing]
[Edit: Add null guard]
[Run: npm test user.service]

Fixed: Added null check before property access. Tests passing.
```

### Example 2: Feature Addition

**User:** "Add dark mode toggle to settings"

**LIGHT Response:**
```
Adding dark mode toggle:

Plan:
1. Add toggle to settings UI
2. Update theme context
3. Persist preference to localStorage
4. Add CSS variables for dark theme
5. Test toggle functionality

[... implementation ...]

Added dark mode with persistent toggle. Theme switches instantly and survives page reload.
Changes: settings.tsx, theme-context.tsx, globals.css
```

### Example 3: Task Requiring FULL Mode

**User:** "Design and implement a comprehensive caching strategy for the API layer"

**LIGHT Response:**
```
This task benefits from architectural planning and research into caching patterns.

Recommendation: Switch to FULL mode for this task.
Run: cfmode full

FULL mode will:
- Research caching strategies (Redis, in-memory, CDN)
- Design architecture with trade-off analysis
- Plan implementation phases
- Include comprehensive testing strategy

Would you like me to proceed in FULL mode, or implement a specific caching approach you have in mind?
```

---

## ENVIRONMENT

All factory environment configuration remains active:
- `.claude/env.claude` — Factory/MCP configuration
- `.env.local` — Application secrets (never committed)
- `.claude/cache/` — Context cache (SQLite/Redis)
- `.claude/logs/` — Audit logs
- `tags` — Ctags index (auto-maintained)

---

## SWITCHING MODES

**To FULL mode:**
```bash
cfmode full
# CLAUDE.md → CLAUDE.full.md (multi-phase orchestration)
```

**To LIGHT mode (current):**
```bash
cfmode light
# CLAUDE.md → CLAUDE.light.md (single-pass)
```

**Check current mode:**
```bash
head -1 CLAUDE.md
# Output: "# Claude Factory — LIGHT MODE (Single-Pass)"
```

---

## SUMMARY: LIGHT Mode Behavior

| Aspect | LIGHT Mode | FULL Mode |
|--------|-----------|-----------|
| **Execution** | Single-pass | Multi-phase pipeline |
| **Agents** | None (direct tools) | Analyst, Researcher, Architect, etc. |
| **Planning** | Inline (≤8 bullets) | Detailed execution plan |
| **Reports** | Concise (2-3 sentences) | Comprehensive docs/tasks/reports/ |
| **Model** | FAST default, STRONG when needed | Fixed assignments per phase |
| **Notifications** | None by default | Voice notifications (notify_say) |
| **Tools** | All available (direct use) | All available (agent-wrapped) |
| **Policies** | All enforced (direct application) | All enforced (orchestrated) |

---

**You are in LIGHT mode. Proceed with single-pass, token-efficient execution.**
