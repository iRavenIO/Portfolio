#!/usr/bin/env bash
# cache-hooks.sh — Auto-Invalidation Hooks for Universal Context Cache
# Provides deterministic invalidation functions triggered by file writes,
# policy changes, and git HEAD changes.

set -euo pipefail

# ============================================================================
# CONFIGURATION
# ============================================================================

if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  CLAUDE_ROOT="${CLAUDE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
else
  CLAUDE_ROOT="${CLAUDE_ROOT:-$(pwd)}"
fi

# Source the base cache library (provides cache_invalidate, cache_invalidate_type, etc.)
# Guard against double-sourcing
if [[ -z "${_CACHE_HOOKS_LOADED:-}" ]]; then
  _CACHE_HOOKS_LOADED=1

  # Source cache.sh if not already loaded
  if ! declare -f cache_invalidate >/dev/null 2>&1; then
    source "${CLAUDE_ROOT}/.claude/scripts/cache.sh"
  fi
fi

CACHE_DIR="${CLAUDE_ROOT}/.claude/cache"
CACHE_DB="${CACHE_DIR}/cache.db"
LOG_FILE="${CLAUDE_ROOT}/.claude/logs/factory.log"
REDIS_PREFIX="factory:"

# Detect Redis availability
REDIS_AVAILABLE=false
if command -v redis-cli >/dev/null 2>&1 && redis-cli PING >/dev/null 2>&1; then
  REDIS_AVAILABLE=true
fi

# ============================================================================
# LOGGING
# ============================================================================

_log_hook() {
  local event="$1"
  shift
  local msg="$*"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "{\"timestamp\":\"$timestamp\",\"event\":\"hook_$event\",\"message\":\"$msg\"}" >> "$LOG_FILE"
}

# ============================================================================
# STRUCTURAL FILE PATTERNS
# ============================================================================

# Files that, when changed, require repo_map invalidation
STRUCTURAL_PATTERNS=(
  "package.json"
  "package-lock.json"
  "tsconfig.json"
  ".mcp.json"
  "Makefile"
  "Dockerfile"
  "docker-compose.yml"
  "docker-compose.yaml"
  ".gitignore"
  "install.sh"
)

# Policy file directory
POLICY_DIR="docs/policy"
AGENT_DIR=".claude/agents"
RUNBOOK_DIR=".claude/runbooks"
SCRIPTS_DIR=".claude/scripts"

# ============================================================================
# HOOK 1: cache_invalidate_for_write
# ============================================================================

cache_invalidate_for_write() {
  # Invalidate cache entries affected by a file write/edit.
  # Usage: cache_invalidate_for_write <file_path>
  #
  # Behavior:
  #   1. Invalidate the file's direct cache entry (file:<path>)
  #   2. If the file is a policy, invalidate the policy:<name> typed key
  #   3. If the file is a structural file, invalidate repo_map
  #   4. Invalidate any tool output caches whose path scope overlaps the file
  #
  # Safety: Never deletes non-factory Redis keys (all keys use REDIS_PREFIX)

  local file_path="$1"

  # Normalize to absolute path if relative
  if [[ "$file_path" != /* ]]; then
    file_path="${CLAUDE_ROOT}/${file_path}"
  fi

  # Resolve to canonical path (handle symlinks, ../)
  if [[ -e "$file_path" ]]; then
    file_path=$(cd "$(dirname "$file_path")" && pwd)/$(basename "$file_path")
  fi

  _log_hook "write_invalidate" "file=$file_path"

  # 1. Invalidate direct file cache entry
  local file_key="file:${file_path}"
  cache_invalidate "$file_key" 2>/dev/null || true

  # 2. Check if it's a policy file and invalidate typed key
  local rel_path="${file_path#$CLAUDE_ROOT/}"
  if [[ "$rel_path" == ${POLICY_DIR}/*.md ]]; then
    local policy_name
    policy_name=$(basename "$rel_path" .md)
    cache_invalidate "policy:${policy_name}" 2>/dev/null || true
    _log_hook "write_invalidate" "policy_key=policy:${policy_name}"
  fi

  # 3. Check if it's a runbook and invalidate typed key
  if [[ "$rel_path" == ${RUNBOOK_DIR}/*.md ]]; then
    local runbook_name
    runbook_name=$(basename "$rel_path" .md)
    cache_invalidate "runbook:${runbook_name}" 2>/dev/null || true
    _log_hook "write_invalidate" "runbook_key=runbook:${runbook_name}"
  fi

  # 4. Check if it's CLAUDE.md (core config)
  if [[ "$rel_path" == "CLAUDE.md" ]]; then
    cache_invalidate "file:${CLAUDE_ROOT}/CLAUDE.md" 2>/dev/null || true
    _log_hook "write_invalidate" "core_file=CLAUDE.md"
  fi

  # 5. Check if structural file changed -> invalidate repo_map
  local basename_file
  basename_file=$(basename "$rel_path")
  for pattern in "${STRUCTURAL_PATTERNS[@]}"; do
    if [[ "$basename_file" == "$pattern" ]]; then
      cache_invalidate "repo_map" 2>/dev/null || true
      # Also remove the cached repo-map.txt file
      rm -f "${CACHE_DIR}/repo-map.txt" 2>/dev/null || true
      _log_hook "write_invalidate" "repo_map invalidated due to structural file: $basename_file"
      break
    fi
  done

  # 6. Invalidate overlapping tool output caches
  # Tool caches are keyed as tool:<name>:<fingerprint>
  # We invalidate all tool caches that might reference the changed file's directory
  _invalidate_overlapping_tool_caches "$file_path"
}

# ============================================================================
# HOOK 2: cache_invalidate_for_policy_change
# ============================================================================

cache_invalidate_for_policy_change() {
  # Invalidate all caches affected by a policy file change.
  # Usage: cache_invalidate_for_policy_change
  #
  # This is a broader invalidation that clears:
  #   1. All policy-typed cache entries
  #   2. All runbook-typed cache entries (may reference policies)
  #   3. All spawn-typed cache entries (contain injected policy context)
  #   4. The repo_map (policy count may have changed)
  #   5. All file:* entries under docs/policy/
  #
  # Use this when:
  #   - A policy file is created, modified, or deleted
  #   - CLAUDE.md is modified (it references policies)
  #   - A runbook references policy rules that changed

  _log_hook "policy_invalidate" "Invalidating all policy-related caches"

  # 1. Invalidate all policy-typed entries
  cache_invalidate_type "policy" 2>/dev/null || true

  # 2. Invalidate all runbook-typed entries (may embed policy references)
  cache_invalidate_type "runbook" 2>/dev/null || true

  # 3. Invalidate all spawn-typed entries (contain injected policy context)
  if [[ -f "$CACHE_DB" ]]; then
    local spawn_keys
    spawn_keys=$(sqlite3 "$CACHE_DB" "SELECT key FROM cache_entries WHERE key LIKE 'spawn:%';" 2>/dev/null || echo "")
    if [[ -n "$spawn_keys" ]]; then
      while IFS= read -r key; do
        [[ -n "$key" ]] && cache_invalidate "$key" 2>/dev/null || true
      done <<< "$spawn_keys"
    fi
  fi

  # 4. Invalidate file:* entries under docs/policy/
  if [[ -f "$CACHE_DB" ]]; then
    local policy_file_keys
    policy_file_keys=$(sqlite3 "$CACHE_DB" "SELECT key FROM cache_entries WHERE key LIKE 'file:%${POLICY_DIR}%';" 2>/dev/null || echo "")
    if [[ -n "$policy_file_keys" ]]; then
      while IFS= read -r key; do
        [[ -n "$key" ]] && cache_invalidate "$key" 2>/dev/null || true
      done <<< "$policy_file_keys"
    fi
  fi

  # 5. Invalidate CLAUDE.md cache (it references all policies)
  cache_invalidate "file:${CLAUDE_ROOT}/CLAUDE.md" 2>/dev/null || true

  # 6. Invalidate repo_map (policy file count may have changed)
  cache_invalidate "repo_map" 2>/dev/null || true
  rm -f "${CACHE_DIR}/repo-map.txt" 2>/dev/null || true

  _log_hook "policy_invalidate" "Complete — cleared policy, runbook, spawn, and related file caches"
}

# ============================================================================
# HOOK 3: cache_invalidate_for_git_head_change
# ============================================================================

cache_invalidate_for_git_head_change() {
  # Invalidate caches affected by a git HEAD change (checkout, pull, rebase, merge).
  # Usage: cache_invalidate_for_git_head_change
  #
  # This is the most aggressive invalidation:
  #   1. All tool output caches (keyed by git HEAD fingerprint, now stale)
  #   2. All file:* caches (files may have changed)
  #   3. Repo map (file structure may have changed)
  #   4. Preserves: decision_memory (session-spanning, not git-dependent)
  #
  # Use this when:
  #   - git checkout, git pull, git rebase, git merge complete
  #   - Manager detects HEAD changed between task boundaries
  #
  # Safety: Never deletes non-factory Redis keys

  _log_hook "git_head_invalidate" "Git HEAD changed — invalidating stale caches"

  # 1. Invalidate all tool output caches (fingerprinted with old HEAD)
  cache_invalidate_type "tool_output" 2>/dev/null || true

  # 2. Invalidate all file caches
  cache_invalidate_type "file" 2>/dev/null || true

  # 3. Invalidate all policy caches
  cache_invalidate_type "policy" 2>/dev/null || true

  # 4. Invalidate all runbook caches
  cache_invalidate_type "runbook" 2>/dev/null || true

  # 5. Invalidate all core caches
  cache_invalidate_type "core" 2>/dev/null || true

  # 6. Invalidate all spawn caches
  if [[ -f "$CACHE_DB" ]]; then
    local spawn_keys
    spawn_keys=$(sqlite3 "$CACHE_DB" "SELECT key FROM cache_entries WHERE key LIKE 'spawn:%';" 2>/dev/null || echo "")
    if [[ -n "$spawn_keys" ]]; then
      while IFS= read -r key; do
        [[ -n "$key" ]] && cache_invalidate "$key" 2>/dev/null || true
      done <<< "$spawn_keys"
    fi
  fi

  # 7. Invalidate repo map
  cache_invalidate "repo_map" 2>/dev/null || true
  rm -f "${CACHE_DIR}/repo-map.txt" 2>/dev/null || true

  # 8. Clean Redis tool keys (only factory-prefixed)
  if [[ "$REDIS_AVAILABLE" == "true" ]]; then
    redis-cli --scan --pattern "${REDIS_PREFIX}tool:*" | xargs -r redis-cli DEL >/dev/null 2>&1 || true
  fi

  _log_hook "git_head_invalidate" "Complete — all file/tool/policy caches cleared, decision_memory preserved"
}

# ============================================================================
# INTERNAL HELPERS
# ============================================================================

_invalidate_overlapping_tool_caches() {
  # Invalidate tool output caches that may reference the changed file
  # Tool caches use fingerprints that include file paths
  local changed_file="$1"
  local changed_dir
  changed_dir=$(dirname "$changed_file")

  if [[ ! -f "$CACHE_DB" ]]; then
    return 0
  fi

  # Get all tool cache keys
  local tool_keys
  tool_keys=$(sqlite3 "$CACHE_DB" "SELECT key FROM cache_entries WHERE type='tool_output';" 2>/dev/null || echo "")

  if [[ -z "$tool_keys" ]]; then
    return 0
  fi

  # Invalidate all tool caches (conservative approach: tool fingerprints include
  # git HEAD and args, and we cannot reverse the hash to check path overlap,
  # so we invalidate all tool outputs for the current session)
  local invalidated=0
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    cache_invalidate "$key" 2>/dev/null || true
    invalidated=$((invalidated + 1))
  done <<< "$tool_keys"

  if [[ "$invalidated" -gt 0 ]]; then
    _log_hook "tool_cache_invalidate" "Invalidated $invalidated tool output caches due to file change: $changed_file"
  fi
}

# ============================================================================
# CONVENIENCE: Batch invalidation for multiple files
# ============================================================================

cache_invalidate_batch() {
  # Invalidate caches for a list of changed files
  # Usage: cache_invalidate_batch <file1> <file2> ...
  # Or pipe: echo "file1\nfile2" | cache_invalidate_batch

  local policy_changed=false
  local files=()

  if [[ $# -gt 0 ]]; then
    files=("$@")
  else
    # Read from stdin
    while IFS= read -r file; do
      [[ -n "$file" ]] && files+=("$file")
    done
  fi

  for file in "${files[@]}"; do
    cache_invalidate_for_write "$file"

    # Track if any policy file changed
    local rel_path="${file#$CLAUDE_ROOT/}"
    if [[ "$rel_path" == ${POLICY_DIR}/*.md ]] || [[ "$rel_path" == "CLAUDE.md" ]]; then
      policy_changed=true
    fi
  done

  # If any policy changed, run the broader policy invalidation
  if [[ "$policy_changed" == "true" ]]; then
    cache_invalidate_for_policy_change
  fi

  _log_hook "batch_invalidate" "Processed ${#files[@]} files, policy_changed=$policy_changed"
}

# ============================================================================
# GIT HEAD CHANGE DETECTION
# ============================================================================

_get_current_head() {
  git -C "$CLAUDE_ROOT" rev-parse HEAD 2>/dev/null || echo "unknown"
}

cache_check_head_changed() {
  # Check if git HEAD changed since last recorded value
  # Usage: cache_check_head_changed
  # Returns: 0 if changed (and triggers invalidation), 1 if unchanged

  local current_head
  current_head=$(_get_current_head)

  local stored_head=""
  if [[ -f "$CACHE_DB" ]]; then
    stored_head=$(sqlite3 "$CACHE_DB" "SELECT value FROM cache_entries WHERE key='_git_head';" 2>/dev/null || echo "")
  fi

  if [[ "$current_head" != "$stored_head" && -n "$stored_head" ]]; then
    _log_hook "head_change_detected" "old=$stored_head new=$current_head"
    cache_invalidate_for_git_head_change
    # Update stored HEAD
    cache_set "_git_head" "$current_head" "internal" 2>/dev/null || true
    return 0
  elif [[ -z "$stored_head" ]]; then
    # First run — store HEAD without invalidating
    cache_set "_git_head" "$current_head" "internal" 2>/dev/null || true
    return 1
  fi

  return 1
}

# ============================================================================
# EXPORTS
# ============================================================================

export -f cache_invalidate_for_write
export -f cache_invalidate_for_policy_change
export -f cache_invalidate_for_git_head_change
export -f cache_invalidate_batch
export -f cache_check_head_changed
export -f _invalidate_overlapping_tool_caches
export -f _log_hook
export -f _get_current_head
