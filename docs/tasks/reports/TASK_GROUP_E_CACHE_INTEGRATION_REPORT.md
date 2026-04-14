# Task Group E: Cache Integration for Ops — Implementation Report

**Developer Agent**
**Date:** 2026-02-10
**Status:** ✅ COMPLETED

---

## Summary

Implemented cached wrappers for 5 safe READ operations from Task Group D ops tools. All wrappers cache only READ-tier outputs, include context-aware fingerprinting, apply redaction before storage, and support configurable TTL (60-300s range, default 120s).

---

## Implementation Details

### File Created

**Location:** `.claude/scripts/cached-ops.sh` (executable)

**Architecture:**
- Extends existing `cache.sh` infrastructure
- Sources both `cache.sh` and `redact.sh` for dependency
- ZSH and Bash compatible

### Key Format

All cached keys follow this pattern:
```
ops:<tool>:<function>:<context_hash>:<params_hash>
```

**Fingerprinting includes:**
- Current context (kubectl context, argocd context, database host, project directory)
- Function parameters (resource name, namespace, app name, etc.)
- Git HEAD (invalidates cache on code changes)

---

## Implemented Wrappers

### 1. `cached_k8s_get`

**Usage:**
```bash
cached_k8s_get <resource> <name> --namespace=<ns> [--ttl=<seconds>]
```

**Example:**
```bash
source .claude/scripts/cached-ops.sh
cached_k8s_get deployment my-app --namespace=production --ttl=60
```

**Context:** Includes current kubectl cluster context
**Cache Key:** `ops:k8s:get:<cluster_context>:<resource:name:namespace>`
**Underlying Tool:** `.claude/scripts/ops/k8s.sh k8s_get`

---

### 2. `cached_argocd_app_get`

**Usage:**
```bash
cached_argocd_app_get <app_name> [--ttl=<seconds>]
```

**Example:**
```bash
cached_argocd_app_get my-application --ttl=90
```

**Context:** Includes current argocd context
**Cache Key:** `ops:argocd:app_get:<argocd_context>:<app_name>`
**Underlying Tool:** `.claude/scripts/ops/argocd.sh argocd_app_get`

---

### 3. `cached_argo_get`

**Usage:**
```bash
cached_argo_get <workflow_name> [--namespace=<ns>] [--ttl=<seconds>]
```

**Example:**
```bash
cached_argo_get data-processing-workflow --namespace=argo --ttl=120
```

**Context:** Includes current kubectl cluster context (argo uses kubectl)
**Cache Key:** `ops:argo:get:<cluster_context>:<workflow:namespace>`
**Underlying Tool:** `.claude/scripts/ops/argo-workflows.sh argo_get`

---

### 4. `cached_pg_schema`

**Usage:**
```bash
cached_pg_schema --database=<db> [--schema=<schema>] [--ttl=<seconds>]
```

**Example:**
```bash
cached_pg_schema --database=mydb --schema=public --ttl=300
```

**Context:** Includes PostgreSQL host (from `$PGHOST` or defaults to localhost)
**Cache Key:** `ops:postgres:schema:<db_host>:<database:schema>`
**Underlying Tool:** `.claude/scripts/ops/postgres.sh pg_query_readonly`
**Query:** Introspects `information_schema.columns` for table and column metadata

---

### 5. `cached_supabase_status`

**Usage:**
```bash
cached_supabase_status [--ttl=<seconds>]
```

**Example:**
```bash
cached_supabase_status --ttl=180
```

**Context:** Includes current working directory (supabase status is project-specific)
**Cache Key:** `ops:supabase:status:<project_dir>`
**Underlying Tool:** `.claude/scripts/ops/supabase.sh supabase_status`

---

## Cache Invalidation Helper

### `invalidate_ops_cache`

**Usage:**
```bash
# Invalidate all ops cache entries
invalidate_ops_cache

# Invalidate specific tool cache entries
invalidate_ops_cache k8s
invalidate_ops_cache argocd
```

**Description:** Deletes all `ops_output` type cache entries, or filters by tool name.

---

## Configuration

### Environment Variable

**`CACHED_OPS_TTL`** (default: 120 seconds)

```bash
# Set custom default TTL
export CACHED_OPS_TTL=180
source .claude/scripts/cached-ops.sh
```

### Per-Call TTL Override

All wrappers accept an optional `--ttl=<seconds>` parameter to override the default:

```bash
cached_k8s_get pod my-pod --namespace=default --ttl=60
```

**TTL Range:** 60-300 seconds (as specified in requirements)

---

## Security Rules

### 1. READ-Only Caching

All wrappers cache **only READ-tier outputs**. No WRITE/EXECUTE/INFRASTRUCTURE operations are cached.

### 2. Redaction Before Storage

All tool outputs are piped through `redact_stream` before caching:

```bash
local redacted=$(echo "$output" | redact_stream)
cache_set "$key" "$redacted" "ops_output"
```

This ensures secrets and sensitive environment variables are never stored in the cache.

### 3. Context Invalidation

Cache keys include git HEAD in the fingerprint. When the repository changes, all cached ops outputs are automatically invalidated.

### 4. TTL Enforcement

The `_ops_cache_get_with_ttl` helper checks TTL on every cache read:
- If age > TTL: invalidate entry and return cache miss
- If age ≤ TTL: return cached value

---

## Usage Examples

### Example 1: Kubernetes Resource Status

```bash
#!/usr/bin/env bash
source .claude/scripts/cached-ops.sh

# First call: cache miss, executes kubectl
cached_k8s_get deployment api-server --namespace=production --ttl=120

# Second call within 120s: cache hit
cached_k8s_get deployment api-server --namespace=production --ttl=120
```

### Example 2: Database Schema Introspection

```bash
#!/usr/bin/env bash
source .claude/scripts/cached-ops.sh

# Export database host (optional, defaults to localhost)
export PGHOST=db.example.com

# Introspect schema (first call: cache miss)
cached_pg_schema --database=app_db --schema=public --ttl=300

# Subsequent calls within 300s: cache hit
cached_pg_schema --database=app_db --schema=public
```

### Example 3: Cache Invalidation Workflow

```bash
#!/usr/bin/env bash
source .claude/scripts/cached-ops.sh

# Populate cache
cached_k8s_get pod web-1 --namespace=default
cached_argocd_app_get my-app

# Invalidate all ops cache entries
invalidate_ops_cache

# Next calls will be cache misses
cached_k8s_get pod web-1 --namespace=default
```

---

## Testing

### Manual Test

```bash
# Load library
source .claude/scripts/cached-ops.sh

# Show usage (verify script loaded)
bash .claude/scripts/cached-ops.sh
```

**Expected Output:**
```
Usage: source cached-ops.sh

Available functions:
  cached_k8s_get <resource> <name> --namespace=<ns> [--ttl=<seconds>]
  cached_argocd_app_get <app_name> [--ttl=<seconds>]
  cached_argo_get <workflow_name> [--namespace=<ns>] [--ttl=<seconds>]
  cached_pg_schema --database=<db> [--schema=<schema>] [--ttl=<seconds>]
  cached_supabase_status [--ttl=<seconds>]
  invalidate_ops_cache [tool]

Configuration:
  CACHED_OPS_TTL=120 (default: 120 seconds)
```

---

## Design Decisions

### Why Extend cache.sh Instead of Creating New File?

**Decision:** Create new `.claude/scripts/cached-ops.sh` that sources `cache.sh`

**Rationale:**
- `cache.sh` is a general-purpose caching library
- Ops-specific wrappers have unique context requirements (kubectl context, argocd context, etc.)
- Separation of concerns: `cache.sh` = storage engine, `cached-ops.sh` = domain-specific wrappers
- Easier to maintain and extend ops-specific logic

### Why Include Git HEAD in Fingerprint?

**Rationale:**
- Ops tools may change behavior when scripts are updated
- Git HEAD changes trigger automatic cache invalidation
- Prevents stale data from persisting across code changes

### Why TTL Defaults to 120s?

**Rationale:**
- Balance between performance (reduce API calls) and freshness (detect infrastructure changes quickly)
- Production systems typically update every 1-5 minutes
- 120s TTL allows 2-3 cached reads before refresh
- Configurable via `CACHED_OPS_TTL` for different environments

---

## Files Modified

- **Created:** `.claude/scripts/cached-ops.sh` (executable, 390 lines)

---

## Token Usage

- **Estimated:** ~4K tokens
- **Actual:** ~4K tokens (within budget)

---

## Completion Checklist

- [x] Implement 5 cached wrapper functions
- [x] Cache only READ outputs (no WRITE/EXECUTE/INFRASTRUCTURE)
- [x] Fingerprint includes context (cluster/namespace/app/db + query + git_head)
- [x] Redact before storing (pipe through `redact_stream`)
- [x] Short TTL: 60-300s configurable (default 120s)
- [x] Invalidate on context changes (git HEAD in fingerprint)
- [x] Make file executable
- [x] Write implementation report with usage examples
- [x] Test script loading

---

## Next Steps

**For Task Group F (Orchestration + Template Updates):**
- Update spawn templates to use cached ops wrappers where applicable
- Add guidance for agents on when to use cached vs. direct ops calls

**For Task Group G (Validation + Tests Expansion):**
- Add integration tests for cached ops wrappers
- Validate TTL enforcement
- Test cache invalidation scenarios

---

**END OF REPORT**
