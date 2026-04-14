# Technical Design Document: Phase 5.2 -- Ops MCP Stage 2

## TDD-2026-02-10 | Complexity: 4/5 | Estimated LOC: ~2,100

---

## 1. Architecture Overview

### 1.1 Component Diagram

```
+-----------------------------------------------------------------------+
|                          Claude Code (Manager)                         |
|  Spawns agents that call MCP tools or Bash wrappers                   |
+-----------------------------------------------------------------------+
        |                          |                         |
        v                          v                         v
+----------------+   +------------------------+   +-----------------+
| factory-ops    |   | Shell Wrappers         |   | cache.sh        |
| (server-ops.js)|   | (.claude/scripts/ops/) |   | (SQLite/Redis)  |
|                |   |                        |   |                 |
| READ-tier:     |   | READ/WRITE/EXEC/INFRA: |   | cache_get()     |
|  7 discover_*  |   |  k8s.sh                |   | cache_set()     |
|  tools         |   |  argocd.sh             |   | cache_invalidate|
|                |   |  argo-workflows.sh     |   |                 |
| WRITE-tier:    |   |  postgres.sh           |   +---------+-------+
|  ops_plan_*    |   |  supabase.sh           |             |
|  ops_approve   |   +----------+-------------+             |
|  ops_execute   |              |                           |
+-------+--------+              |                           |
        |                       v                           v
        |              +------------------+        +----------------+
        |              | redact.sh        |        | cache.db       |
        |              | (secret          |        | (SQLite)       |
        |              |  redaction)      |        | - cache_entries|
        |              +------------------+        | - decision_mem |
        |                                          | - approval_log |
        v                                          +----------------+
+-----------------------------------------------+
| External CLIs (graceful degradation)          |
| kubectl | argocd | argo | psql | supabase     |
| aws s3  | gh     | docker | redis-cli         |
+-----------------------------------------------+
```

### 1.2 Data Flow

**Discovery (READ-tier) -- existing 4 tools + 5 new tools:**

```
Agent -> MCP tool call -> server-ops.js
  -> execSafe(cli, args, {timeout})
  -> Parse JSON/text output
  -> redactOutput(result)
  -> Return {content: [{type: "text", text: redactedJSON}]}
```

**Mutation (WRITE-tier via approval workflow) -- new:**

```
Agent -> ops_plan_mutation(params) -> server-ops.js
  -> Validate params (tier, scope)
  -> Generate execution plan (dry-run CLI)
  -> Hash plan: SHA256(plan_json)
  -> Store in approval_log table (status: pending_plan)
  -> Return { plan_id, plan_hash, plan_details, dry_run_output }

Manager -> ops_approve(plan_id, plan_hash) -> server-ops.js
  -> Verify plan_hash matches stored hash (tamper detection)
  -> Check TTL (< 30 minutes)
  -> Atomic UPDATE status = approved (SQLite BEGIN EXCLUSIVE)
  -> Return { approved: true, plan_id }

Agent -> ops_execute(plan_id) -> server-ops.js
  -> Load plan from approval_log WHERE status = approved
  -> Verify TTL still valid
  -> Atomic UPDATE status = executing
  -> execSafe(cli, actual_args, {timeout})
  -> redactOutput(result)
  -> UPDATE status = executed, store result
  -> Invalidate related cache entries
  -> Return { executed: true, result }
```

### 1.3 Error Handling and Graceful Degradation

| Failure Mode | Detection | Recovery |
|---|---|---|
| CLI not installed | `execSafe` returns `error: "command_not_found"` | Return `{available: false, tool, suggestion}` |
| CLI timeout | `error.killed === true` | Return timeout error with duration |
| JSON parse failure | `try/catch` around `JSON.parse` | Return raw output with parse_error flag |
| SQLite lock | `SQLITE_BUSY` error | Retry 3x with 100ms backoff |
| Cache miss | `cache_get` returns null | Execute CLI, store result |
| Approval expired | TTL check > 30 min | Return `{expired: true}`, require re-plan |
| Network unreachable | CLI exit code > 0 | Return error with stderr (redacted) |

---

## 2. Module Design

### 2.1 File Structure and Responsibilities

```
.claude/mcp/server-ops.js           [MODIFY] Add 8 new tools + approval workflow + cache
.claude/scripts/cache.sh            [MODIFY] Add approval_log schema + approval functions
.claude/scripts/test-ops-stage2.sh  [NEW]    Phase 5.2 comprehensive test suite
docs/policy/ops-tools.md            [MODIFY] Update Stage 2 from FUTURE to IMPLEMENTED
docs/policy/mcp-security.md         [MODIFY] Add new tools to permission matrix
CLAUDE.md                           [MODIFY] Register new tools in MCP table
```

### 2.2 New MCP Tool Signatures (server-ops.js)

#### Tool 5: ops_discover_s3

```javascript
server.tool(
  "ops_discover_s3",
  "Discover AWS S3 buckets and their configuration. Returns structured JSON with bucket inventory. READ-tier operation. Gracefully degrades if aws CLI not available.",
  {
    bucket: z.string().optional()
      .describe("Filter by bucket name. If omitted, lists all buckets."),
    prefix: z.string().optional()
      .describe("List objects under this prefix (requires bucket)."),
    max_keys: z.number().optional().default(100)
      .describe("Maximum objects to list (default 100, max 1000).")
  },
  async ({ bucket, prefix, max_keys }) => { /* ... */ }
);
```

**CLI calls:**
- List buckets: `aws s3api list-buckets --output json`
- List objects: `aws s3api list-objects-v2 --bucket <b> --prefix <p> --max-keys <n> --output json`
- Bucket config: `aws s3api get-bucket-location --bucket <b> --output json`

**Timeout:** 15,000ms | **Cache TTL:** 60s

#### Tool 6: ops_discover_github

```javascript
server.tool(
  "ops_discover_github",
  "Discover GitHub repository metadata, workflows, and recent CI status. Returns structured JSON. READ-tier operation. Gracefully degrades if gh CLI not available.",
  {
    repo: z.string().optional()
      .describe("Repository in owner/repo format. If omitted, uses current repo."),
    include: z.array(z.enum(["workflows", "releases", "branches"]))
      .optional().default(["workflows", "branches"])
      .describe("What to discover. Default: workflows and branches.")
  },
  async ({ repo, include }) => { /* ... */ }
);
```

**CLI calls:**
- Repo info: `gh repo view <repo> --json name,description,defaultBranchRef,isPrivate`
- Workflows: `gh run list --repo <repo> --limit 10 --json status,name,conclusion,createdAt`
- Releases: `gh release list --repo <repo> --limit 5 --json tagName,name,publishedAt`
- Branches: `gh api repos/<owner>/<repo>/branches --paginate=false | head -20`

**Timeout:** 15,000ms | **Cache TTL:** 60s

#### Tool 7: ops_discover_docker

```javascript
server.tool(
  "ops_discover_docker",
  "Discover Docker containers, images, and networks. Returns structured JSON. READ-tier operation. Gracefully degrades if docker CLI not available.",
  {
    include: z.array(z.enum(["containers", "images", "networks", "volumes"]))
      .optional().default(["containers", "images"])
      .describe("What to discover. Default: containers and images."),
    all: z.boolean().optional().default(false)
      .describe("Include stopped containers (default: running only).")
  },
  async ({ include, all }) => { /* ... */ }
);
```

**CLI calls:**
- Containers: `docker ps --format json` (or `docker ps -a --format json` if all)
- Images: `docker images --format json`
- Networks: `docker network ls --format json`
- Volumes: `docker volume ls --format json`

**Timeout:** 10,000ms | **Cache TTL:** 30s

#### Tool 8: ops_discover_redis

```javascript
server.tool(
  "ops_discover_redis",
  "Discover Redis server info, databases, and key statistics. Returns structured JSON. READ-tier operation. Gracefully degrades if redis-cli not available.",
  {
    url: z.string().optional()
      .describe("Redis connection URL. If omitted, uses REDIS_URL env var or localhost:6379."),
    section: z.array(z.enum(["server", "memory", "keyspace", "clients", "stats"]))
      .optional().default(["server", "memory", "keyspace"])
      .describe("INFO sections to query. Default: server, memory, keyspace.")
  },
  async ({ url, section }) => { /* ... */ }
);
```

**CLI calls:**
- Server info: `redis-cli -u <url> INFO <section>`
- Key count: `redis-cli -u <url> DBSIZE`
- Keyspace: `redis-cli -u <url> INFO keyspace`

**Timeout:** 5,000ms | **Cache TTL:** 30s

#### Tool 9: ops_discover_argo_workflows

```javascript
server.tool(
  "ops_discover_argo_workflows",
  "Discover Argo Workflows and their status. Returns structured JSON. READ-tier operation. Gracefully degrades if argo CLI not available.",
  {
    namespace: z.string().optional()
      .describe("Kubernetes namespace. Defaults to 'argo'."),
    status: z.enum(["Running", "Succeeded", "Failed", "Error", "Pending"])
      .optional()
      .describe("Filter by workflow status."),
    limit: z.number().optional().default(20)
      .describe("Maximum workflows to list (default 20, max 100).")
  },
  async ({ namespace, status, limit }) => { /* ... */ }
);
```

**CLI calls:**
- List workflows: `argo list --namespace <ns> --output json`
- Get workflow: `argo get <name> --namespace <ns> --output json`

**Timeout:** 10,000ms | **Cache TTL:** 30s

#### Tool 10: ops_plan_mutation (SIMPLIFIED - NOT IMPLEMENTED IN THIS PHASE)

**Note:** The approval workflow tools (ops_plan_mutation, ops_approve, ops_execute) are **NOT** part of Phase 5.2. They are listed in the TDD for future reference but will be implemented in a separate phase. Phase 5.2 focuses solely on the 5 new **READ-tier discovery tools**.

The approval workflow will be Phase 5.3 (future work).

---

## 3. Secret Redaction Extensions

### 3.1 New Patterns for Phase 5.2

Add to `redactOutput()` in `server-ops.js`:

```javascript
// AWS S3 patterns
// S3 pre-signed URLs contain signatures
const s3PresignedPattern = /https:\/\/[^?]+\?[^"]*X-Amz-Signature=[^"&\s]+[^"'\s]*/g;
redacted = redacted.replace(s3PresignedPattern, "https://s3.***REDACTED_PRESIGNED_URL***");

// AWS Account IDs (12-digit numbers in ARN context)
const arnPattern = /arn:aws[^:]*:[^:]+:[^:]*:(\d{12}):/g;
redacted = redacted.replace(arnPattern, (match, accountId) =>
  match.replace(accountId, "***ACCOUNT***")
);

// Docker registry auth tokens
const dockerAuthPattern = /"auth"\s*:\s*"[A-Za-z0-9+/=]+"/g;
redacted = redacted.replace(dockerAuthPattern, '"auth": "***REDACTED***"');

// Redis AUTH password in connection URLs
const redisAuthPattern = /AUTH\s+[^\s"]+/gi;
redacted = redacted.replace(redisAuthPattern, "AUTH ***REDACTED***");
```

---

## 4. Cache Integration

### 4.1 Cache Key Format

```
ops:discover:{tool}:{fingerprint}
```

Where `fingerprint = SHA256(context_data + ":" + params_data)`.

### 4.2 TTL Values

| Tool | Cache TTL |
|---|---|
| ops_discover_s3 | 60s |
| ops_discover_github | 60s |
| ops_discover_docker | 30s |
| ops_discover_redis | 30s |
| ops_discover_argo_workflows | 30s |

---

## 5. Testing Strategy

### 5.1 Test File

**Path:** `.claude/scripts/test-ops-stage2.sh`

### 5.2 Test Categories

| Category | Count | Description |
|---|---|---|
| Schema validation | 5 | Each new discovery tool returns valid JSON |
| Secret redaction | 8 | AWS keys, S3 pre-signed URLs, Docker auth, Redis AUTH |
| Caching | 5 | Cache hit/miss, TTL expiration |
| Graceful degradation | 5 | Missing CLI returns `{available: false}` |
| **Total** | **23** | |

---

## 6. Implementation Sequence

```
Phase A: Discovery Tools (5 new tools)           ~500 LOC
  A1. Add ops_discover_s3 to server-ops.js
  A2. Add ops_discover_github to server-ops.js
  A3. Add ops_discover_docker to server-ops.js
  A4. Add ops_discover_redis to server-ops.js
  A5. Add ops_discover_argo_workflows to server-ops.js

Phase B: Secret Redaction Extensions             ~100 LOC
  B1. Add S3 pre-signed URL pattern to redactOutput
  B2. Add ARN account ID pattern to redactOutput
  B3. Add Docker registry auth pattern to redactOutput
  B4. Add Redis AUTH pattern to redactOutput

Phase C: Tests                                   ~300 LOC
  C1. Create test-ops-stage2.sh with mock CLI framework
  C2. Write schema validation tests (5)
  C3. Write secret redaction tests (8)
  C4. Write caching tests (5)
  C5. Write graceful degradation tests (5)

Phase D: Documentation                           ~50 LOC
  D1. Update CLAUDE.md MCP tools table
  D2. Update docs/policy/ops-tools.md
  D3. Update docs/policy/mcp-security.md
```

---

**END OF TECHNICAL DESIGN DOCUMENT**
