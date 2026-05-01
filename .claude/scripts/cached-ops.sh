#!/usr/bin/env bash
# cached-ops.sh — Cached wrappers for safe READ operations from ops tools
# Part of Task Group E: Cache Integration for Ops
# Caches READ-tier outputs only (no WRITE/EXECUTE/INFRASTRUCTURE)

set -euo pipefail

# Detect CLAUDE_ROOT
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${(%):-%x}")" && pwd)"
else
  SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
CLAUDE_ROOT="${CLAUDE_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"

# Source dependencies
source "${CLAUDE_ROOT}/.claude/scripts/cache.sh"
source "${CLAUDE_ROOT}/.claude/scripts/redact.sh"

# Configuration
CACHED_OPS_TTL="${CACHED_OPS_TTL:-120}"  # Default 120s (configurable)

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

_ops_cache_key() {
  # Generate cache key for ops tool output
  # Usage: _ops_cache_key <tool> <function> <context> <params>
  local tool="$1"
  local function="$2"
  local context="$3"
  local params="$4"

  # Include git HEAD in fingerprint for cache invalidation on code changes
  local git_head=$(git -C "$CLAUDE_ROOT" rev-parse HEAD 2>/dev/null || echo "no-git")

  # Hash context + params + git_head to create stable key
  local fingerprint=$(echo "${context}:${params}:${git_head}" | shasum -a 256 | awk '{print $1}')
  echo "ops:${tool}:${function}:${fingerprint}"
}

_ops_cache_get_with_ttl() {
  # Get cached value if it exists and is within TTL
  # Usage: _ops_cache_get_with_ttl <key> <ttl_seconds>
  local key="$1"
  local ttl="${2:-$CACHED_OPS_TTL}"

  # Check if key exists in cache
  local escaped_key="${key//\'/''}"
  local last_read=$(sqlite3 "$CACHE_DB" "SELECT last_read FROM cache_entries WHERE key='$escaped_key';" 2>/dev/null || echo "")

  if [[ -z "$last_read" ]]; then
    return 1  # Cache miss
  fi

  # Check TTL
  local now=$(date +%s)
  local age=$((now - last_read))

  if [[ "$age" -gt "$ttl" ]]; then
    # Expired - invalidate and return miss
    cache_invalidate "$key"
    return 1
  fi

  # Within TTL - return cached value
  cache_get "$key"
  return 0
}

# ============================================================================
# CACHED OPS WRAPPERS
# ============================================================================

# cached_k8s_get: Cached wrapper for kubectl get (READ tier)
# Usage: cached_k8s_get <resource> <name> --namespace=<ns> [--ttl=<seconds>]
cached_k8s_get() {
  local resource="$1"
  local name="$2"
  local namespace=""
  local ttl="$CACHED_OPS_TTL"

  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace=*)
        namespace="${1#*=}"
        shift
        ;;
      --ttl=*)
        ttl="${1#*=}"
        shift
        ;;
      *)
        echo "[ERROR] cached_k8s_get: Unknown argument: $1" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$namespace" ]]; then
    echo "[ERROR] cached_k8s_get: --namespace is required" >&2
    return 1
  fi

  # Get current kubectl context for cache key
  local context=$(kubectl config current-context 2>/dev/null || echo "default")
  local params="resource=${resource}:name=${name}:namespace=${namespace}"
  local key=$(_ops_cache_key "k8s" "get" "cluster=${context}" "$params")

  # Try cache first
  if _ops_cache_get_with_ttl "$key" "$ttl" 2>/dev/null; then
    return 0
  fi

  # Cache miss - execute k8s_get and cache result
  local output
  if output=$(bash "$SCRIPT_DIR/ops/k8s.sh" k8s_get "$resource" "$name" --namespace="$namespace" 2>&1); then
    # Redact before caching
    local redacted=$(echo "$output" | redact_stream)
    cache_set "$key" "$redacted" "ops_output"
    echo "$redacted"
    return 0
  else
    echo "$output" >&2
    return 1
  fi
}

# cached_argocd_app_get: Cached wrapper for argocd app get (READ tier)
# Usage: cached_argocd_app_get <app_name> [--ttl=<seconds>]
cached_argocd_app_get() {
  local app_name="$1"
  local ttl="$CACHED_OPS_TTL"

  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ttl=*)
        ttl="${1#*=}"
        shift
        ;;
      *)
        echo "[ERROR] cached_argocd_app_get: Unknown argument: $1" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$app_name" ]]; then
    echo "[ERROR] cached_argocd_app_get: Application name is required" >&2
    return 1
  fi

  # Get current argocd context
  local context=$(argocd context 2>/dev/null | grep 'CURRENT' | awk '{print $2}' || echo "default")
  local params="app=${app_name}"
  local key=$(_ops_cache_key "argocd" "app_get" "context=${context}" "$params")

  # Try cache first
  if _ops_cache_get_with_ttl "$key" "$ttl" 2>/dev/null; then
    return 0
  fi

  # Cache miss - execute argocd_app_get and cache result
  local output
  if output=$(bash "$SCRIPT_DIR/ops/argocd.sh" argocd_app_get "$app_name" 2>&1); then
    # Redact before caching
    local redacted=$(echo "$output" | redact_stream)
    cache_set "$key" "$redacted" "ops_output"
    echo "$redacted"
    return 0
  else
    echo "$output" >&2
    return 1
  fi
}

# cached_argo_get: Cached wrapper for argo get workflow (READ tier)
# Usage: cached_argo_get <workflow_name> [--namespace=<ns>] [--ttl=<seconds>]
cached_argo_get() {
  local workflow_name="$1"
  local namespace="argo"
  local ttl="$CACHED_OPS_TTL"

  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace=*)
        namespace="${1#*=}"
        shift
        ;;
      --ttl=*)
        ttl="${1#*=}"
        shift
        ;;
      *)
        echo "[ERROR] cached_argo_get: Unknown argument: $1" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$workflow_name" ]]; then
    echo "[ERROR] cached_argo_get: Workflow name is required" >&2
    return 1
  fi

  # Get current kubectl context (argo uses kubectl context)
  local context=$(kubectl config current-context 2>/dev/null || echo "default")
  local params="workflow=${workflow_name}:namespace=${namespace}"
  local key=$(_ops_cache_key "argo" "get" "cluster=${context}" "$params")

  # Try cache first
  if _ops_cache_get_with_ttl "$key" "$ttl" 2>/dev/null; then
    return 0
  fi

  # Cache miss - execute argo_get and cache result
  local output
  if output=$(bash "$SCRIPT_DIR/ops/argo-workflows.sh" argo_get "$workflow_name" --namespace="$namespace" 2>&1); then
    # Redact before caching
    local redacted=$(echo "$output" | redact_stream)
    cache_set "$key" "$redacted" "ops_output"
    echo "$redacted"
    return 0
  else
    echo "$output" >&2
    return 1
  fi
}

# cached_pg_schema: Cached wrapper for PostgreSQL schema introspection (READ tier)
# Usage: cached_pg_schema --database=<db> [--schema=<schema>] [--ttl=<seconds>]
cached_pg_schema() {
  local database=""
  local schema="public"
  local ttl="$CACHED_OPS_TTL"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --database=*)
        database="${1#*=}"
        shift
        ;;
      --schema=*)
        schema="${1#*=}"
        shift
        ;;
      --ttl=*)
        ttl="${1#*=}"
        shift
        ;;
      *)
        echo "[ERROR] cached_pg_schema: Unknown argument: $1" >&2
        return 1
        ;;
    esac
  done

  if [[ -z "$database" ]]; then
    echo "[ERROR] cached_pg_schema: --database is required" >&2
    return 1
  fi

  # Get database host for context
  local db_host="${PGHOST:-localhost}"
  local params="database=${database}:schema=${schema}"
  local key=$(_ops_cache_key "postgres" "schema" "host=${db_host}" "$params")

  # Try cache first
  if _ops_cache_get_with_ttl "$key" "$ttl" 2>/dev/null; then
    return 0
  fi

  # Cache miss - execute schema introspection query
  # Query: list all tables with column info in specified schema
  local query="SELECT table_schema, table_name, column_name, data_type, is_nullable FROM information_schema.columns WHERE table_schema = '$schema' ORDER BY table_name, ordinal_position;"

  local output
  if output=$(bash "$SCRIPT_DIR/ops/postgres.sh" pg_query_readonly "$query" --database="$database" --limit=1000 2>&1); then
    # Redact before caching
    local redacted=$(echo "$output" | redact_stream)
    cache_set "$key" "$redacted" "ops_output"
    echo "$redacted"
    return 0
  else
    echo "$output" >&2
    return 1
  fi
}

# cached_supabase_status: Cached wrapper for supabase status (READ tier)
# Usage: cached_supabase_status [--ttl=<seconds>]
cached_supabase_status() {
  local ttl="$CACHED_OPS_TTL"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ttl=*)
        ttl="${1#*=}"
        shift
        ;;
      *)
        echo "[ERROR] cached_supabase_status: Unknown argument: $1" >&2
        return 1
        ;;
    esac
  done

  # Get current working directory as context (supabase status is project-specific)
  local project_dir=$(pwd)
  local params="cwd=${project_dir}"
  local key=$(_ops_cache_key "supabase" "status" "$params" "")

  # Try cache first
  if _ops_cache_get_with_ttl "$key" "$ttl" 2>/dev/null; then
    return 0
  fi

  # Cache miss - execute supabase_status and cache result
  local output
  if output=$(bash "$SCRIPT_DIR/ops/supabase.sh" supabase_status 2>&1); then
    # Redact before caching
    local redacted=$(echo "$output" | redact_stream)
    cache_set "$key" "$redacted" "ops_output"
    echo "$redacted"
    return 0
  else
    echo "$output" >&2
    return 1
  fi
}

# ============================================================================
# CACHE INVALIDATION HELPERS
# ============================================================================

# invalidate_ops_cache: Invalidate all ops cache entries
# Usage: invalidate_ops_cache [tool]
invalidate_ops_cache() {
  local tool="${1:-}"

  if [[ -z "$tool" ]]; then
    # Invalidate all ops cache entries
    cache_invalidate_type "ops_output"
    echo "Invalidated all ops cache entries"
  else
    # Invalidate specific tool cache entries
    # Get all keys matching pattern
    local keys=$(sqlite3 "$CACHE_DB" "SELECT key FROM cache_entries WHERE type='ops_output' AND key LIKE 'ops:${tool}:%';" 2>/dev/null || echo "")

    if [[ -n "$keys" ]]; then
      while IFS= read -r key; do
        [[ -n "$key" ]] && cache_invalidate "$key"
      done <<< "$keys"
      echo "Invalidated cache entries for tool: $tool"
    else
      echo "No cache entries found for tool: $tool"
    fi
  fi
}

# ============================================================================
# EXPORTS
# ============================================================================

export -f _ops_cache_key
export -f _ops_cache_get_with_ttl
export -f cached_k8s_get
export -f cached_argocd_app_get
export -f cached_argo_get
export -f cached_pg_schema
export -f cached_supabase_status
export -f invalidate_ops_cache

# If script is executed directly, show usage
if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "Usage: source cached-ops.sh"
  echo ""
  echo "Available functions:"
  echo "  cached_k8s_get <resource> <name> --namespace=<ns> [--ttl=<seconds>]"
  echo "  cached_argocd_app_get <app_name> [--ttl=<seconds>]"
  echo "  cached_argo_get <workflow_name> [--namespace=<ns>] [--ttl=<seconds>]"
  echo "  cached_pg_schema --database=<db> [--schema=<schema>] [--ttl=<seconds>]"
  echo "  cached_supabase_status [--ttl=<seconds>]"
  echo "  invalidate_ops_cache [tool]"
  echo ""
  echo "Configuration:"
  echo "  CACHED_OPS_TTL=${CACHED_OPS_TTL} (default: 120 seconds)"
fi
