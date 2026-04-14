# OPS TOOLS POLICY

## PURPOSE

This policy governs operational tooling for Kubernetes, Argo CD, Argo Workflows, PostgreSQL, and Supabase within the autonomous software factory. It defines permission tiers, safety controls, audit requirements, and usage patterns for infrastructure operations.

---

## ALLOWED TOOLS

The factory permits the following operational tools through wrapped shell scripts:

| Tool | Purpose | Wrapper Script |
|------|---------|----------------|
| `kubectl` / `k3s` | Kubernetes cluster operations | `.claude/scripts/ops/k8s.sh` |
| `argocd` | GitOps continuous deployment | `.claude/scripts/ops/argocd.sh` |
| `argo` | Workflow orchestration | `.claude/scripts/ops/argo-workflows.sh` |
| `psql` | PostgreSQL database operations | `.claude/scripts/ops/postgres.sh` |
| `supabase` | Supabase backend platform | `.claude/scripts/ops/supabase.sh` |

Direct invocation of these tools via Bash is **PROHIBITED**. Agents MUST use the wrapper scripts.

---

## PERMISSION TIERS

All operational actions are classified into four permission tiers:

### Tier 1: READ

**Scope:** Non-mutating, informational queries
**Examples:**
- `kubectl get`, `kubectl describe`, `kubectl logs`
- `argocd app get`, `argocd app list`
- `argo get`, `argo logs`
- `SELECT` queries on read-only database connections
- `supabase status`

**Controls:**
- No confirmation required
- No dry-run required
- Output may be cached (short TTL: 30-60 seconds)
- Audit logging required

### Tier 2: WRITE

**Scope:** Mutating operations that modify resources
**Examples:**
- `kubectl apply`, `kubectl patch`, `kubectl scale`
- `argocd app sync`
- `argo submit`
- `INSERT`, `UPDATE`, `DELETE` SQL statements
- `supabase db migrate`

**Controls:**
- `--dry-run` MANDATORY (default: TRUE)
- `--confirm` flag REQUIRED to execute (default: FALSE)
- Must log intent before execution
- Audit logging required with confirmation status
- No caching

### Tier 3: EXECUTE

**Scope:** Interactive or privileged execution contexts
**Examples:**
- `kubectl exec` (shell into pods)
- `kubectl port-forward`
- `psql` interactive sessions
- `argo submit --wait` (blocking workflow execution)
- `supabase link` (interactive authentication)

**Controls:**
- `--confirm` flag REQUIRED
- Interactive mode PROHIBITED unless explicitly approved by user
- Session/connection metadata logged
- No caching
- Output redaction MANDATORY

### Tier 4: INFRASTRUCTURE

**Scope:** Destructive or cluster-wide operations
**Examples:**
- `kubectl delete namespace`, `kubectl delete pvc`
- `argocd app delete`
- `argo delete`
- `DROP DATABASE`, `DROP TABLE`, `TRUNCATE`
- `supabase unlink`, `supabase db reset`

**Controls:**
- `--confirm` flag REQUIRED
- Additional `--force` flag REQUIRED for destructive ops
- Pre-execution snapshot/backup validation
- Human approval gate (block until user confirms)
- Audit logging with full command reconstruction
- No caching
- Output redaction MANDATORY

---

## SAFETY CONTROLS

### 1. Dry-Run Defaults

All **WRITE** and **INFRASTRUCTURE** tier operations default to dry-run mode:

```bash
# Default behavior (safe)
k8s.sh k8s_apply deployment.yaml
# Output: [DRY RUN] Would apply: deployment.yaml

# Actual execution requires confirmation
k8s.sh k8s_apply deployment.yaml --confirm
# Output: Applying deployment.yaml...
```

**Implementation:**
- Wrappers check for `--confirm` flag
- If absent, append `--dry-run=client` (kubectl) or equivalent for other tools
- Print `[DRY RUN]` prefix to all output
- Exit with code 0 (success simulation)

### 2. Confirmation Gates

Operations requiring `--confirm`:

| Tier | Require `--confirm` | Require `--force` |
|------|---------------------|-------------------|
| READ | No | No |
| WRITE | Yes | No |
| EXECUTE | Yes | No |
| INFRASTRUCTURE | Yes | Yes |

**Implementation:**
- Parse flags before execution
- Block if required flags are missing
- Log confirmation status to audit trail

### 3. Scoping

All operations MUST be scoped to prevent accidental broad-spectrum changes:

**Kubernetes:**
- Namespace REQUIRED for all kubectl commands (no cluster-wide defaults)
- Selector labels REQUIRED for bulk operations

**Argo CD:**
- Application name REQUIRED (no `--all` without `--confirm --force`)

**Argo Workflows:**
- Workflow name or label selector REQUIRED

**PostgreSQL:**
- Database name REQUIRED
- Schema REQUIRED for DDL operations
- Row limit REQUIRED for SELECT (default: 100)

**Supabase:**
- Project ref REQUIRED for all operations

### 4. Output Redaction

All operational output MUST pass through redaction before logging or returning to agents:

**Redaction Rules:**
- Secrets, tokens, passwords → `[REDACTED]`
- Environment variables containing `SECRET`, `PASSWORD`, `TOKEN`, `KEY` → `[REDACTED]`
- IP addresses → `[IP_REDACTED]`
- Connection strings → `[CONNECTION_REDACTED]`

**Implementation:**
- Source `.claude/scripts/redact.sh` at top of each wrapper
- Pipe all output through `redact_stream` function before returning

### 5. Audit Logging

Every operational invocation MUST write an audit entry:

**Audit Log Location:** `.claude/logs/ops-audit-$RUN_ID.log`

**Format:** JSON Lines (one JSON object per line)

**Required Fields:**
```json
{
  "timestamp": "2026-02-10T14:32:15Z",
  "run_id": "abc123",
  "tool": "kubectl",
  "function": "k8s_apply",
  "args": ["deployment.yaml", "--namespace=production"],
  "dry_run": true,
  "confirmed": false,
  "forced": false,
  "exit_code": 0,
  "duration_ms": 234,
  "user": "developer-agent",
  "scope": "production/deployment/webapp"
}
```

**Implementation:**
- Wrapper scripts append audit entry after command execution
- Use `date -u +"%Y-%m-%dT%H:%M:%SZ"` for timestamp
- Capture exit code and duration
- Redact sensitive args before logging

---

## WRAPPER SCRIPT SPECIFICATIONS

### Common Pattern

All wrapper scripts follow this structure:

```bash
#!/usr/bin/env bash
set -euo pipefail

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_ROOT="${CLAUDE_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
source "${CLAUDE_ROOT}/.claude/scripts/redact.sh"

# Parse global flags
DRY_RUN=true
CONFIRMED=false
FORCED=false
RUN_ID="${RUN_ID:-$(date +%s)-$$}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm) CONFIRMED=true; DRY_RUN=false; shift ;;
    --force) FORCED=true; shift ;;
    --) shift; break ;;
    *) break ;;
  esac
done

# Audit logging function
audit_log() {
  local tool=$1
  local func=$2
  local exit_code=$3
  local duration_ms=$4
  shift 4
  local args_json=$(printf '%s\n' "$@" | jq -R . | jq -s .)

  mkdir -p "${CLAUDE_ROOT}/.claude/logs"
  echo "{\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"run_id\":\"$RUN_ID\",\"tool\":\"$tool\",\"function\":\"$func\",\"args\":$args_json,\"dry_run\":$DRY_RUN,\"confirmed\":$CONFIRMED,\"forced\":$FORCED,\"exit_code\":$exit_code,\"duration_ms\":$duration_ms}" >> "${CLAUDE_ROOT}/.claude/logs/ops-audit-$RUN_ID.log"
}

# Function implementations...
```

### 1. k8s.sh

**Functions:**

```bash
k8s_get() {
  # Tier: READ
  # Usage: k8s_get <resource> <name> --namespace=<ns>
  # Example: k8s_get pod webapp-7d8f --namespace=production
}

k8s_list() {
  # Tier: READ
  # Usage: k8s_list <resource> --namespace=<ns> [--selector=<label>]
  # Example: k8s_list pods --namespace=production --selector=app=webapp
}

k8s_apply() {
  # Tier: WRITE
  # Usage: k8s_apply <file> [--confirm]
  # Example: k8s_apply deployment.yaml --confirm
  # Default: dry-run mode
}

k8s_delete() {
  # Tier: INFRASTRUCTURE
  # Usage: k8s_delete <resource> <name> --namespace=<ns> [--confirm] [--force]
  # Example: k8s_delete deployment webapp --namespace=production --confirm --force
  # Requires: --confirm --force
}
```

**Scoping Rules:**
- All functions require `--namespace` (no cluster-wide defaults)
- `k8s_delete` requires resource type + name (no bulk deletes without explicit selector)

### 2. argocd.sh

**Functions:**

```bash
argocd_app_get() {
  # Tier: READ
  # Usage: argocd_app_get <app-name>
  # Example: argocd_app_get webapp-production
}

argocd_app_sync() {
  # Tier: WRITE
  # Usage: argocd_app_sync <app-name> [--confirm]
  # Example: argocd_app_sync webapp-production --confirm
  # Default: dry-run mode (shows diff without syncing)
}

argocd_app_delete() {
  # Tier: INFRASTRUCTURE
  # Usage: argocd_app_delete <app-name> [--confirm] [--force]
  # Example: argocd_app_delete webapp-production --confirm --force
  # Requires: --confirm --force
}
```

### 3. argo-workflows.sh

**Functions:**

```bash
argo_get() {
  # Tier: READ
  # Usage: argo_get <workflow-name> [--namespace=<ns>]
  # Example: argo_get data-pipeline-x7k2 --namespace=workflows
}

argo_logs() {
  # Tier: READ
  # Usage: argo_logs <workflow-name> [--namespace=<ns>]
  # Example: argo_logs data-pipeline-x7k2 --namespace=workflows
  # Output: redacted logs
}

argo_submit() {
  # Tier: WRITE
  # Usage: argo_submit <workflow-file> [--confirm] [--namespace=<ns>]
  # Example: argo_submit pipeline.yaml --confirm --namespace=workflows
  # Default: dry-run mode (validates without submitting)
}

argo_delete() {
  # Tier: INFRASTRUCTURE
  # Usage: argo_delete <workflow-name> [--confirm] [--force] [--namespace=<ns>]
  # Example: argo_delete data-pipeline-x7k2 --confirm --force --namespace=workflows
  # Requires: --confirm --force
}
```

### 4. postgres.sh

**Functions:**

```bash
pg_query_readonly() {
  # Tier: READ
  # Usage: pg_query_readonly <query> --database=<db>
  # Example: pg_query_readonly "SELECT * FROM users LIMIT 10" --database=production
  # Enforces: read-only transaction, row limit (max 1000)
  # Connection: Uses read-replica if available
}

pg_query_write() {
  # Tier: WRITE (for DML) / INFRASTRUCTURE (for DDL)
  # Usage: pg_query_write <query> --database=<db> [--confirm]
  # Example: pg_query_write "UPDATE users SET active=true WHERE id=123" --database=production --confirm
  # Default: dry-run mode (EXPLAIN plan only)
  # DDL detection: DROP/TRUNCATE/ALTER requires --confirm --force
}

pg_exec_file() {
  # Tier: WRITE
  # Usage: pg_exec_file <sql-file> --database=<db> [--confirm]
  # Example: pg_exec_file migration.sql --database=production --confirm
  # Default: dry-run mode (validates syntax only)
}
```

**Safety:**
- Read-only queries use `SET TRANSACTION READ ONLY`
- Row limit enforced (default 100, max 1000)
- DDL operations require tier escalation
- Connection strings redacted in all output

### 5. supabase.sh

**Functions:**

```bash
supabase_status() {
  # Tier: READ
  # Usage: supabase_status
  # Example: supabase_status
  # Output: project ref, database status (redacted connection details)
}

supabase_link() {
  # Tier: EXECUTE
  # Usage: supabase_link <project-ref> [--confirm]
  # Example: supabase_link abc123def456 --confirm
  # Requires: --confirm (interactive authentication)
}

supabase_db_migrate() {
  # Tier: WRITE
  # Usage: supabase_db_migrate [--confirm]
  # Example: supabase_db_migrate --confirm
  # Default: dry-run mode (shows pending migrations)
  # Requires: --confirm to apply
}

supabase_db_reset() {
  # Tier: INFRASTRUCTURE
  # Usage: supabase_db_reset [--confirm] [--force]
  # Example: supabase_db_reset --confirm --force
  # Requires: --confirm --force
  # WARNING: Destructive operation, drops all data
}
```

---

## CACHING RULES

**READ-tier operations** may cache output to reduce redundant API calls:

**Cache Storage:** `.claude/cache/ops-cache.db` (SQLite)

**Cache Key:** `SHA256(tool + function + args)`

**TTL by Tool:**
- kubectl get/list: 30 seconds
- argocd app get: 60 seconds
- argo get/logs: 30 seconds
- psql SELECT: 60 seconds
- supabase status: 120 seconds

**Implementation:**
- Check cache before execution
- Return cached result if valid (within TTL)
- Invalidate cache on any WRITE/EXECUTE/INFRASTRUCTURE operation affecting same resource

**Cache Entry Format:**
```json
{
  "key": "sha256_hash",
  "tool": "kubectl",
  "function": "k8s_get",
  "args": ["pod", "webapp-7d8f", "--namespace=production"],
  "result": "[cached output]",
  "timestamp": "2026-02-10T14:32:15Z",
  "ttl": 30
}
```

**Rules:**
- Only READ-tier operations cache
- Cache MUST be cleared at start of each run (new RUN_ID)
- Cache MUST redact output before storing

---

## APPROVAL WORKFLOW USAGE EXAMPLES

### Example 1: Kubernetes Pod Scaling (WRITE Tier)

**Step 1: Create Plan**
```javascript
{
  "tool": "ops_plan_mutation",
  "arguments": {
    "tier": "WRITE",
    "operation": "kubectl_scale",
    "scope": {
      "namespace": "production",
      "resource": "deployment/api"
    },
    "params": {
      "replicas": 5,
      "current_replicas": 3
    },
    "dry_run_output": "deployment.apps/api scaled (dry run)"
  }
}

// Returns:
{
  "plan_id": "plan_1739212800_abc123",
  "plan_hash": "f3e8d9c7b6a5...",
  "version": 1,
  "tier": "WRITE",
  "operation": "kubectl_scale",
  "status": "pending_approval",
  "ttl_minutes": 30,
  "collision_warning": undefined,
  "next_step": "Call ops_approve with plan_id and plan_hash to approve this operation"
}
```

**Step 2: Review Plan (Optional)**
```javascript
{
  "tool": "ops_list_pending",
  "arguments": {}
}

// Returns list of pending plans with details
```

**Step 3: Approve Plan**
```javascript
{
  "tool": "ops_approve",
  "arguments": {
    "plan_id": "plan_1739212800_abc123",
    "plan_hash": "f3e8d9c7b6a5..."
  }
}

// Returns:
{
  "approved": true,
  "plan_id": "plan_1739212800_abc123",
  "tier": "WRITE",
  "operation": "kubectl_scale",
  "approved_at": "2026-02-10T19:30:00Z",
  "expires_at": "2026-02-10T20:00:00Z",
  "next_step": "Call ops_execute with plan_id to execute this operation"
}
```

**Step 4: Execute Plan**
```javascript
{
  "tool": "ops_execute",
  "arguments": {
    "plan_id": "plan_1739212800_abc123"
  }
}

// Returns execution result with redacted output
```

**Step 5: View Audit Log**
```javascript
{
  "tool": "ops_audit_log",
  "arguments": {
    "plan_id": "plan_1739212800_abc123"
  }
}

// Returns:
{
  "audit_log": true,
  "count": 4,
  "logs": [
    {
      "plan_id": "plan_1739212800_abc123",
      "action": "plan_created",
      "actor": "system",
      "timestamp": "2026-02-10T19:25:00Z",
      "details": { "tier": "WRITE", "operation": "kubectl_scale", "collision": false }
    },
    {
      "plan_id": "plan_1739212800_abc123",
      "action": "plan_approved",
      "actor": "system",
      "timestamp": "2026-02-10T19:30:00Z",
      "details": { "tier": "WRITE", "operation": "kubectl_scale", "hash_verified": true }
    },
    {
      "plan_id": "plan_1739212800_abc123",
      "action": "plan_executing",
      "actor": "system",
      "timestamp": "2026-02-10T19:31:00Z",
      "details": { "tier": "WRITE", "operation": "kubectl_scale" }
    },
    {
      "plan_id": "plan_1739212800_abc123",
      "action": "plan_executed",
      "actor": "system",
      "timestamp": "2026-02-10T19:31:05Z",
      "details": { "tier": "WRITE", "operation": "kubectl_scale", "success": true }
    }
  ]
}
```

### Example 2: Database Migration (INFRASTRUCTURE Tier)

**Step 1: Create Plan with Dry-Run**
```javascript
{
  "tool": "ops_plan_mutation",
  "arguments": {
    "tier": "INFRASTRUCTURE",
    "operation": "postgres_migrate",
    "scope": {
      "database": "production",
      "target": "schema_v2"
    },
    "params": {
      "migration_file": "migrations/002_add_users_table.sql",
      "rollback_plan": "migrations/002_rollback.sql"
    },
    "dry_run_output": "-- Dry run output:\n-- CREATE TABLE users...\n-- Migration affects 0 rows (dry run)"
  }
}

// Returns plan with collision warning if identical plan exists
```

**Step 2: Check for Collision**
If `collision_warning` is present in response:
```json
{
  "collision_warning": {
    "warning": "Identical plan(s) already exist",
    "existing_plans": [
      {
        "plan_id": "plan_1739212700_xyz789",
        "status": "executed",
        "created_at": "2026-02-10T18:00:00Z"
      }
    ]
  }
}
```

**Step 3: View Plan History**
```javascript
{
  "tool": "ops_plan_history",
  "arguments": {
    "plan_id": "plan_1739212800_def456",
    "show_diff": true
  }
}

// Returns version history with diffs between versions
```

### Example 3: Discovery + Mutation Workflow

**Step 1: Discover Current State**
```javascript
{
  "tool": "ops_discover_k8s",
  "arguments": {
    "namespace": "production",
    "resource_types": ["deployments", "pods"]
  }
}

// Analyze current state...
```

**Step 2: Plan Mutation Based on Discovery**
```javascript
{
  "tool": "ops_plan_mutation",
  "arguments": {
    "tier": "WRITE",
    "operation": "kubectl_apply",
    "scope": {
      "namespace": "production",
      "resource": "deployment/api"
    },
    "params": {
      "manifest_path": "/tmp/api-deployment-v2.yaml",
      "strategy": "rolling"
    },
    "dry_run_output": "... (kubectl apply output with --dry-run)"
  }
}
```

**Step 3: Approve and Execute**
Follow standard approval workflow...

### Example 4: Unified Discovery

**Discover All Infrastructure**
```javascript
{
  "tool": "ops_discover",
  "arguments": {
    "tools": ["k8s", "argocd", "postgres", "docker"],
    "parallel": true
  }
}

// Returns:
{
  "unified_discovery": true,
  "execution_mode": "parallel",
  "duration_ms": 1234,
  "tools_requested": 4,
  "tools_executed": 4,
  "summary": {
    "available": 4,
    "unavailable": 0,
    "disabled": 0,
    "errors": 0
  },
  "results": [
    {
      "tool": "k8s",
      "available": true,
      "summary": {
        "pod_count": 42,
        "namespaces": 8
      }
    },
    // ... other results
  ]
}
```

### Common Error Scenarios

**1. Plan Hash Mismatch (Tampering Detection)**
```json
{
  "error": "Plan hash mismatch - potential tampering detected",
  "plan_id": "plan_1739212800_abc123",
  "expected_hash": "f3e8d9c7b6a5...",
  "provided_hash": "a1b2c3d4e5f6..."
}
```
**Resolution:** Plan was modified after creation. Create new plan.

**2. Plan Expired**
```json
{
  "error": "Plan expired",
  "plan_id": "plan_1739212800_abc123",
  "age_seconds": 2400,
  "max_age_seconds": 1800,
  "suggestion": "Create a new plan with ops_plan_mutation"
}
```
**Resolution:** TTL exceeded (default 30 minutes). Create new plan.

**3. Invalid Plan ID Format**
```json
{
  "error": "Invalid plan_id format",
  "plan_id": "malicious_input"
}
```
**Resolution:** Plan ID must match format: `plan_{timestamp}_{random}`

**4. Plan Not Approved**
```json
{
  "error": "Plan not approved",
  "plan_id": "plan_1739212800_abc123",
  "current_status": "pending",
  "suggestion": "Call ops_approve first"
}
```
**Resolution:** Approve plan before attempting execution.

---

## SEQUENCE DIAGRAMS

### Approval Workflow State Machine

```
┌─────────┐
│ PENDING │  ←── ops_plan_mutation creates plan
└────┬────┘
     │
     │ ops_approve (with hash verification)
     ▼
┌──────────┐
│ APPROVED │
└────┬─────┘
     │
     │ ops_execute (with TTL check)
     ▼
┌───────────┐
│ EXECUTING │
└────┬──────┘
     │
     ├─── success ──→ ┌──────────┐
     │                │ EXECUTED │
     │                └──────────┘
     │
     └─── failure ──→ ┌────────┐
                      │ FAILED │
                      └────────┘
```

### Complete Approval Workflow Timeline

```
Time    Actor           Action                   Database State
──────  ──────────────  ───────────────────────  ──────────────────────
T+0s    Developer       ops_plan_mutation        approvals: status=pending
                                                 plan_history: version 1 saved
                                                 audit_log: plan_created

T+60s   Manager         ops_list_pending         (read-only query)

T+120s  Manager         ops_approve              approvals: status=approved
                                                 audit_log: plan_approved

T+180s  Developer       ops_execute              approvals: status=executing
                                                 audit_log: plan_executing

T+185s  System          (execution complete)     approvals: status=executed
                                                 audit_log: plan_executed
```

### Collision Detection Flow

```
ops_plan_mutation
    │
    ├─→ Generate plan_hash (SHA256)
    │
    ├─→ Check collision: SELECT * FROM approvals WHERE plan_hash = ?
    │
    ├─→ IF exists:
    │   │
    │   ├─→ Add collision_warning to output
    │   │   {
    │   │     "warning": "Identical plan(s) already exist",
    │   │     "existing_plans": [...]
    │   │   }
    │   │
    │   └─→ Continue (does not block creation)
    │
    └─→ Store new plan (status=pending)
```

---

## TROUBLESHOOTING GUIDE

### Problem: "Approval workflow is disabled in config"

**Cause:** Ops config file has `approval.enabled: false`

**Solution:**
```bash
# Check current config
cat .claude/config/ops.json

# Enable approval workflow
jq '.approval.enabled = true' .claude/config/ops.json > tmp.json && mv tmp.json .claude/config/ops.json

# Or create config if missing
cat > .claude/config/ops.json <<EOF
{
  "version": "1.0.0",
  "enabled": true,
  "approval": {
    "enabled": true,
    "ttl_minutes": 30,
    "require_hash_match": true,
    "max_pending": 100
  }
}
EOF
```

### Problem: "Approval store not initialized"

**Cause:** Database initialization failed or approvals.db is corrupted

**Solution:**
```bash
# Check if database exists
ls -lh .claude/cache/approvals.db

# Remove corrupted database (it will be recreated)
rm .claude/cache/approvals.db

# Restart MCP server
# Database will be recreated on next tool call
```

### Problem: Too many pending approvals

**Cause:** `max_pending` limit reached (default: 100)

**Solution:**
```bash
# View pending approvals
sqlite3 .claude/cache/approvals.db "SELECT plan_id, operation, created_at, status FROM approvals WHERE status='pending' ORDER BY created_at DESC LIMIT 10;"

# Clean up expired plans
sqlite3 .claude/cache/approvals.db "DELETE FROM approvals WHERE status='pending' AND created_at < $(date -u +%s) - 1800;"
```

### Problem: Plan hash keeps changing for identical operations

**Cause:** Plan includes timestamp field, causing hash variation

**Solution:** Ensure plan_details uses deterministic serialization. The `timestamp` field should be excluded from hash calculation, or use a fixed timestamp for dry-run operations.

### Problem: Cannot view audit logs

**Cause:** Audit log table not created (old database schema)

**Solution:**
```bash
# Check if audit_log table exists
sqlite3 .claude/cache/approvals.db ".schema audit_log"

# If missing, recreate database
rm .claude/cache/approvals.db
# Database will be recreated with new schema on next tool call
```

---

## MCP INTEGRATION

**Stage 1: Autodiscovery (IMPLEMENTED — Phase 5.1)**

The factory includes `factory-ops` MCP server (`.claude/mcp/server-ops.js`) providing four READ-tier discovery tools:

| MCP Tool | Permission Tier | Purpose | CLI Wrapped |
|----------|-----------------|---------|-------------|
| `ops_discover_k8s` | READ | Discover Kubernetes resources (namespaces, pods, services, deployments) | `kubectl` |
| `ops_discover_argocd` | READ | Discover Argo CD applications and sync status | `argocd` |
| `ops_discover_postgres` | READ | Discover PostgreSQL databases, schemas, tables | `psql` |
| `ops_discover_supabase` | READ | Discover Supabase project configuration | `supabase` |

**Stage 2: Extended Discovery (IMPLEMENTED — Phase 5.2)**

Five additional READ-tier discovery tools added to `factory-ops` MCP server:

| MCP Tool | Permission Tier | Purpose | CLI Wrapped |
|----------|-----------------|---------|-------------|
| `ops_discover_s3` | READ | Discover AWS S3 buckets and objects | `aws s3` |
| `ops_discover_github` | READ | Discover GitHub repos, workflows, releases, branches | `gh` |
| `ops_discover_docker` | READ | Discover Docker containers, images, networks, volumes | `docker` |
| `ops_discover_redis` | READ | Discover Redis server info, memory, keyspace stats | `redis-cli` |
| `ops_discover_argo_workflows` | READ | Discover Argo Workflows and their status | `argo` |

**Design:**
- **Graceful degradation:** Tools return `{ available: false }` if CLI not installed
- **Redaction:** All output redacted before returning (in-process Node.js regex, Phase 5.2 extensions)
- **Cache integration:** 30-120s TTL via cache.sh (future enhancement)
- **Timeout handling:** 5-15s per operation with proper error messages
- **Security:** Uses `execFile` (never `exec`), validates all inputs

**Phase 5.2 Secret Redaction Extensions:**
- S3 pre-signed URLs (X-Amz-Signature)
- AWS Account IDs in ARNs
- Docker registry auth tokens
- Redis AUTH passwords

**Stage 3: Approval-Gated Mutations + Unified Discovery (IMPLEMENTED — Phase 5.3 + P1)**

Sixteen tools total in `factory-ops` MCP server with approval workflow for mutations:

**Unified Discovery:**
| MCP Tool | Purpose |
|----------|---------|
| `ops_discover` | Aggregates all 9 discovery tools in parallel/sequential mode |

**Approval Workflow (WRITE/INFRASTRUCTURE tier):**
| MCP Tool | Permission Tier | Purpose |
|----------|-----------------|---------|
| `ops_plan_mutation` | WRITE/INFRASTRUCTURE | Create mutation plan with SHA256 hash |
| `ops_approve` | ADMIN | Approve plan with hash verification + TTL check |
| `ops_list_pending` | READ | List pending approval plans |
| `ops_execute` | WRITE/INFRASTRUCTURE | Execute approved plan (dispatch to CLI) |
| `ops_audit_log` | READ | View audit trail with filtering |
| `ops_plan_history` | READ | View plan versions and diffs |

**Approval Workflow Features:**
1. **Hash Verification:** SHA256 plan hashing prevents tampering
2. **TTL Enforcement:** Plans expire after configurable time (default 30 minutes)
3. **Collision Detection:** Warns when identical plans exist
4. **Version Tracking:** All plan modifications tracked with version numbers
5. **Audit Logging:** Comprehensive who/what/when logging for compliance
6. **Plan Diffs:** Visual comparison between plan versions
7. **Rollback History:** Complete version history for plan recovery

**Database Schema:**
- `approvals` table: Plan storage with status state machine
- `audit_log` table: Immutable audit trail (INSERT only)
- `plan_history` table: Version history for rollback support

**State Machine:**
```
PENDING → APPROVED → EXECUTING → EXECUTED
                              ↓
                           FAILED
```

**Security Model:**
- Plan IDs validated with regex: `/^plan_\d+_[a-z0-9]{8,16}$/`
- All SQL queries use parameterized bind parameters
- Hash verification prevents plan tampering
- TTL prevents stale plan execution
- Audit log cannot be deleted (compliance requirement)

**Stage 3: Approval Workflow & Unified Discovery (IMPLEMENTED — Phase 5.3)**

Five new MCP tools added to `factory-ops` MCP server for mutation approval and unified discovery:

| MCP Tool | Permission Tier | Purpose | Output |
|----------|-----------------|---------|--------|
| `ops_discover` | READ | Unified discovery aggregating all 9 tools | Combined infrastructure snapshot |
| `ops_plan_mutation` | WRITE | Create execution plan with hash | Plan ID, dry-run output |
| `ops_approve` | WRITE | Approve plan with hash verification | Approval confirmation |
| `ops_list_pending` | READ | List pending approval plans | Pending plans with TTL |
| `ops_execute` | WRITE/INFRASTRUCTURE | Execute approved plan | Execution result |

**Config System:**
- Per-project configuration: `.claude/config/ops.json`
- JSON Schema validation: `.claude/config/ops.schema.json`
- Hot-reload support via `watchFile`
- Optional config (defaults to enabled)

**Approval Workflow:**
- SQLite-backed approval store (`.claude/cache/approvals.db`)
- Plan hashing for tamper detection (SHA256)
- 30-minute TTL (configurable)
- Status tracking: pending → approved → executing → executed

**Unified Discovery:**
- Parallel execution with concurrency limiting
- Selective tool execution
- Combined result aggregation
- Summary statistics

**Stage 4: Shell Wrappers (FUTURE)**

Shell wrapper scripts (`.claude/scripts/ops/*.sh`) will provide WRITE/EXECUTE/INFRASTRUCTURE-tier operations:

| Wrapper Script | Permission Tiers | Operations |
|----------------|------------------|------------|
| `k8s.sh` | READ, WRITE, INFRASTRUCTURE | kubectl apply, delete, scale |
| `argocd.sh` | READ, WRITE, INFRASTRUCTURE | app sync, delete |
| `argo-workflows.sh` | READ, WRITE, INFRASTRUCTURE | workflow submit, delete |
| `postgres.sh` | READ, WRITE, INFRASTRUCTURE | DML/DDL queries, migrations |
| `supabase.sh` | READ, WRITE, INFRASTRUCTURE | migrations, resets |

**Integration Rules:**
- MCP tools (Stage 1) MUST enforce READ-tier only
- Shell wrappers (Stage 2) MUST enforce permission tiers via `--confirm` and `--force` flags
- All tools MUST audit log to `.claude/logs/ops-audit-$RUN_ID.log`
- All tools MUST redact output via `.claude/scripts/redact.sh`
- Prefer MCP tools when available (READ operations); fall back to wrappers for WRITE/EXECUTE/INFRASTRUCTURE

---

## AGENT USAGE PATTERNS

### Developer Agent

**Allowed:**
- READ-tier operations (status checks, logs)
- WRITE-tier operations in dry-run mode (to validate manifests)

**Prohibited:**
- EXECUTE-tier operations
- INFRASTRUCTURE-tier operations
- `--confirm` flag (Developer cannot execute mutating ops)

### Tester Agent

**Allowed:**
- READ-tier operations (verify deployments, check workflow status)
- WRITE-tier operations in dry-run mode (to test deployment validation)

**Prohibited:**
- `--confirm` flag
- EXECUTE/INFRASTRUCTURE operations

### Ops Agent (Future)

**Allowed:**
- All tiers with appropriate flags
- `--confirm` for WRITE/EXECUTE
- `--confirm --force` for INFRASTRUCTURE

**Requirements:**
- Must log justification for all INFRASTRUCTURE operations
- Must validate scope before execution
- Must verify dry-run output before confirming

---

## AUDIT TRAIL

All operational tooling generates audit logs for compliance and debugging:

**Log Aggregation:**
- Logs written to `.claude/logs/ops-audit-$RUN_ID.log` (per-run)
- Logs rotated daily (kept for 30 days)
- Critical operations (INFRASTRUCTURE tier) copied to permanent archive

**Query Interface:**
```bash
# Find all kubectl apply operations
jq 'select(.function == "k8s_apply")' .claude/logs/ops-audit-*.log

# Find all confirmed operations
jq 'select(.confirmed == true)' .claude/logs/ops-audit-*.log

# Find all failed operations
jq 'select(.exit_code != 0)' .claude/logs/ops-audit-*.log
```

**Retention:**
- Development: 7 days
- Staging: 30 days
- Production: 90 days (or per compliance requirements)

---

## ERROR HANDLING

**Exit Codes:**
- `0`: Success
- `1`: General error
- `2`: Missing required flag (e.g., `--confirm`)
- `3`: Scope validation failed (e.g., missing namespace)
- `4`: Dry-run validation failed
- `5`: External tool not found (kubectl, argocd, etc.)

**Error Output:**
All errors MUST:
1. Print to stderr (not stdout)
2. Include function name and failed operation
3. Redact sensitive details
4. Log to audit trail with full context

**Example:**
```bash
[ERROR] k8s_apply: Missing required flag --confirm for mutating operation
[ERROR] Attempted: kubectl apply -f deployment.yaml --namespace=production
[ERROR] Use: k8s.sh k8s_apply deployment.yaml --confirm
```

---

## SECURITY CHECKLIST

Before deploying operational tooling, verify:

- [ ] All wrapper scripts source `redact.sh`
- [ ] Audit logging enabled for all functions
- [ ] `--confirm` gates enforce correctly
- [ ] `--force` gates enforce for INFRASTRUCTURE tier
- [ ] Dry-run defaults work for all WRITE operations
- [ ] Namespace/scope validation prevents cluster-wide accidents
- [ ] Output redaction tested with real secrets
- [ ] Cache TTLs appropriate for data sensitivity
- [ ] Error messages don't leak credentials
- [ ] Scripts executable: `chmod +x .claude/scripts/ops/*.sh`

---

## FUTURE ENHANCEMENTS

1. **MCP Server for Ops Tools:** Wrap kubectl/argocd/argo/psql in a dedicated MCP server (`factory-ops`)
2. **Approval Workflow:** For INFRASTRUCTURE tier, require human approval via notification + confirmation token
3. **Rollback Support:** Automatic snapshot before destructive operations, with one-command rollback
4. **Cost Tracking:** Log resource costs for cloud operations (e.g., AWS EKS, RDS)
5. **Policy as Code:** Validate operations against OPA policies before execution

---

## SUMMARY

This policy establishes a four-tier permission model (READ, WRITE, EXECUTE, INFRASTRUCTURE) for operational tooling, enforced through shell script wrappers with mandatory dry-run defaults, confirmation gates, output redaction, and comprehensive audit logging. All agents using operational tools MUST adhere to these controls to ensure safe, traceable infrastructure operations.
