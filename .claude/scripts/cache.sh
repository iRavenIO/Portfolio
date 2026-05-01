#!/usr/bin/env bash
# cache.sh — Universal Context Cache library
# Provides SQLite-backed caching with optional Redis hot-path acceleration

set -euo pipefail

# ============================================================================
# REDACTION INTEGRATION
# ============================================================================

# Source redaction library (with fallback stubs if unavailable)
SCRIPT_DIR_CACHE="${SCRIPT_DIR_CACHE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
if [[ -f "$SCRIPT_DIR_CACHE/redact.sh" ]]; then
  source "$SCRIPT_DIR_CACHE/redact.sh"
else
  # Fallback stubs if redact.sh is unavailable
  is_secret_file() { return 1; }
  redact_stream() { cat; }
fi

# ============================================================================
# CONFIGURATION
# ============================================================================

# Detect CLAUDE_ROOT (with fallback for sourced vs executed context)
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  CLAUDE_ROOT="${CLAUDE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
else
  CLAUDE_ROOT="${CLAUDE_ROOT:-$(pwd)}"
fi
CACHE_DIR="${CLAUDE_ROOT}/.claude/cache"
CACHE_DB="${CACHE_DIR}/cache.db"
CACHE_REPO_MAP="${CACHE_DIR}/repo-map.txt"
CACHE_TTL_SECONDS=300              # Redis TTL: 5 minutes
CACHE_REPO_MAP_TTL=600             # Repo map refresh: 10 minutes
CACHE_MAX_FILE_SIZE=1048576        # Skip caching files >1MB
CACHE_EVICTION_THRESHOLD=1000      # Evict oldest entries if >1000 cached
REDIS_PREFIX="factory:"            # Redis key prefix

# Detect Redis availability
REDIS_AVAILABLE=false
if command -v redis-cli >/dev/null 2>&1 && redis-cli PING >/dev/null 2>&1; then
  REDIS_AVAILABLE=true
fi

# ============================================================================
# LOGGING
# ============================================================================

LOG_FILE="${CLAUDE_ROOT}/.claude/logs/factory.log"

log_cache() {
  local event="$1"
  shift
  local msg="$*"
  local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  mkdir -p "$(dirname "$LOG_FILE")"
  echo "{\"timestamp\":\"$timestamp\",\"event\":\"cache_$event\",\"message\":\"$msg\"}" >> "$LOG_FILE"
}

# ============================================================================
# SQLITE OPERATIONS
# ============================================================================

cache_init() {
  # Initialize cache directory and SQLite database
  mkdir -p "$CACHE_DIR"
  chmod 700 "$CACHE_DIR"

  if [[ ! -f "$CACHE_DB" ]]; then
    sqlite3 "$CACHE_DB" <<'EOF'
CREATE TABLE IF NOT EXISTS cache_entries (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  key          TEXT NOT NULL UNIQUE,
  value        TEXT NOT NULL,
  type         TEXT NOT NULL,
  created_at   INTEGER NOT NULL,
  last_read    INTEGER NOT NULL,
  read_count   INTEGER DEFAULT 0,
  file_mtime   INTEGER,
  file_hash    TEXT,
  metadata     TEXT
);
CREATE INDEX IF NOT EXISTS idx_key ON cache_entries(key);
CREATE INDEX IF NOT EXISTS idx_type ON cache_entries(type);
CREATE INDEX IF NOT EXISTS idx_last_read ON cache_entries(last_read);
PRAGMA journal_mode=WAL;
EOF
    chmod 600 "$CACHE_DB"
    log_cache "init" "Database initialized at $CACHE_DB"
  fi
}

cache_set() {
  # Store entry in cache
  # Usage: cache_set <key> <value> <type> [filepath] [metadata]
  local key="$1"
  local value="$2"
  local type="$3"
  local filepath="${4:-}"
  local metadata="${5:-}"

  # Validate content (skip for known safe types)
  local is_safe_type=false
  case "$type" in
    policy|runbook|agent|repo_map) is_safe_type=true ;;
  esac

  if [[ "$is_safe_type" == "false" ]]; then
    # For other types, use redact_stream to detect secrets
    local redacted_value=$(echo "$value" | redact_stream)
    if [[ "$redacted_value" != "$value" ]]; then
      log_cache "error" "Rejected cache_set for $key: potential secret detected"
      return 1
    fi
  fi

  local now=$(date +%s)
  local file_mtime=""
  local file_hash=""

  if [[ -n "$filepath" && -f "$filepath" ]]; then
    file_mtime=$(stat -f %m "$filepath" 2>/dev/null || stat -c %Y "$filepath" 2>/dev/null || echo "")
    file_hash=$(shasum -a 256 "$filepath" | awk '{print $1}')
  fi

  # Escape special characters for SQLite
  # First escape backslashes, then single quotes
  local escaped_key="${key//\\/\\\\}"
  escaped_key="${escaped_key//\'/''}"

  local escaped_type="${type//\\/\\\\}"
  escaped_type="${escaped_type//\'/''}"

  local escaped_value="${value//\\/\\\\}"
  escaped_value="${escaped_value//\'/''}"

  local escaped_metadata="${metadata//\\/\\\\}"
  escaped_metadata="${escaped_metadata//\'/''}"

  local escaped_file_hash="${file_hash//\\/\\\\}"
  escaped_file_hash="${escaped_file_hash//\'/''}"

  # Construct SQL with proper NULL handling
  local sql_file_mtime="${file_mtime:-NULL}"
  local sql_file_hash="NULL"
  if [[ -n "$escaped_file_hash" ]]; then
    sql_file_hash="'$escaped_file_hash'"
  fi
  local sql_metadata="NULL"
  if [[ -n "$escaped_metadata" ]]; then
    sql_metadata="'$escaped_metadata'"
  fi

  sqlite3 "$CACHE_DB" <<EOF
INSERT INTO cache_entries (key, value, type, created_at, last_read, read_count, file_mtime, file_hash, metadata)
VALUES ('$escaped_key', '$escaped_value', '$escaped_type', $now, $now, 0, $sql_file_mtime, $sql_file_hash, $sql_metadata)
ON CONFLICT(key) DO UPDATE SET
  value = excluded.value,
  file_mtime = excluded.file_mtime,
  file_hash = excluded.file_hash,
  created_at = $now,
  last_read = $now,
  read_count = 0;
EOF

  # Also write to Redis if available
  if [[ "$REDIS_AVAILABLE" == "true" ]]; then
    redis-cli SETEX "${REDIS_PREFIX}${key}" "$CACHE_TTL_SECONDS" "$value" >/dev/null 2>&1 || true
  fi

  log_cache "set" "key=$key type=$type size=${#value}"
}

cache_get() {
  # Retrieve entry from cache (updates last_read and read_count)
  # Usage: cache_get <key>
  local key="$1"

  # Try Redis first
  if [[ "$REDIS_AVAILABLE" == "true" ]]; then
    local redis_value=$(redis-cli GET "${REDIS_PREFIX}${key}" 2>/dev/null || echo "")
    if [[ -n "$redis_value" ]]; then
      log_cache "hit" "key=$key source=redis"
      echo "$redis_value"
      return 0
    fi
  fi

  # Redis miss or unavailable — query SQLite
  local escaped_key="${key//\'/''}"
  local value=$(sqlite3 "$CACHE_DB" "SELECT value FROM cache_entries WHERE key='$escaped_key';")

  if [[ -n "$value" ]]; then
    # Update last_read and read_count
    local now=$(date +%s)
    sqlite3 "$CACHE_DB" "UPDATE cache_entries SET last_read=$now, read_count=read_count+1 WHERE key='$escaped_key';"

    # Write to Redis for next time
    if [[ "$REDIS_AVAILABLE" == "true" ]]; then
      redis-cli SETEX "${REDIS_PREFIX}${key}" "$CACHE_TTL_SECONDS" "$value" >/dev/null 2>&1 || true
    fi

    log_cache "hit" "key=$key source=sqlite"
    echo "$value"
    return 0
  else
    log_cache "miss" "key=$key"
    return 1
  fi
}

cache_invalidate() {
  # Delete single cache entry
  # Usage: cache_invalidate <key>
  local key="$1"
  local escaped_key="${key//\'/''}"

  sqlite3 "$CACHE_DB" "DELETE FROM cache_entries WHERE key='$escaped_key';"

  if [[ "$REDIS_AVAILABLE" == "true" ]]; then
    redis-cli DEL "${REDIS_PREFIX}${key}" >/dev/null 2>&1 || true
  fi

  log_cache "invalidate" "key=$key"
}

cache_invalidate_type() {
  # Delete all entries of a specific type
  # Usage: cache_invalidate_type <type>
  local type="$1"
  local escaped_type="${type//\'/''}"

  # Get all keys of this type before deleting
  local keys=$(sqlite3 "$CACHE_DB" "SELECT key FROM cache_entries WHERE type='$escaped_type';")
  local count=$(echo "$keys" | wc -l | tr -d ' ')

  # Delete from SQLite
  sqlite3 "$CACHE_DB" "DELETE FROM cache_entries WHERE type='$escaped_type';"

  # Also delete from Redis if available
  if [[ "$REDIS_AVAILABLE" == "true" && -n "$keys" ]]; then
    while IFS= read -r key; do
      [[ -n "$key" ]] && redis-cli DEL "${REDIS_PREFIX}${key}" >/dev/null 2>&1 || true
    done <<< "$keys"
  fi

  log_cache "invalidate_type" "type=$type count=$count"
}

cache_flush() {
  # Clear entire cache
  sqlite3 "$CACHE_DB" "DELETE FROM cache_entries;"

  if [[ "$REDIS_AVAILABLE" == "true" ]]; then
    # Delete only factory-prefixed keys, not entire Redis database
    redis-cli --scan --pattern "${REDIS_PREFIX}*" | xargs -r redis-cli DEL >/dev/null 2>&1 || true
  fi

  log_cache "flush" "Entire cache cleared"
}

cache_prime() {
  # Bulk populate cache with files matching pattern
  # Usage: cache_prime <type> <pattern>
  local type="$1"
  local pattern="$2"

  local files
  if [[ "$pattern" == *"*"* ]]; then
    # Glob pattern - prepend CLAUDE_ROOT if relative
    local search_pattern="$pattern"
    if [[ "$pattern" != /* ]]; then
      # Relative pattern — prepend CLAUDE_ROOT
      search_pattern="${CLAUDE_ROOT}/${pattern}"
    fi
    files=$(find "$CLAUDE_ROOT" -path "$search_pattern" -type f 2>/dev/null || true)
  else
    # Comma-separated list
    files="${pattern//,/ }"
  fi

  local count=0
  for file in $files; do
    if [[ ! -f "$file" ]]; then
      continue
    fi

    # Skip secret files
    if is_secret_file "$file"; then
      log_cache "skip" "file=$file reason=secret_file"
      continue
    fi

    # Skip large files
    local size=$(stat -f %z "$file" 2>/dev/null || stat -c %s "$file" 2>/dev/null || echo "0")
    if [[ "$size" -gt "$CACHE_MAX_FILE_SIZE" ]]; then
      log_cache "skip" "file=$file reason=too_large size=$size"
      continue
    fi

    # Check if already cached with same hash
    local file_hash=$(shasum -a 256 "$file" | awk '{print $1}')
    local escaped_file_key="file:${file//\'/''}"
    local cached_hash=$(sqlite3 "$CACHE_DB" "SELECT file_hash FROM cache_entries WHERE key='$escaped_file_key';")

    if [[ "$cached_hash" == "$file_hash" ]]; then
      log_cache "skip" "file=$file reason=unchanged hash=$file_hash"
      continue
    fi

    # Cache miss or stale — read and store
    local content=$(cat "$file")
    cache_set "file:$file" "$content" "$type" "$file"
    count=$((count + 1))
  done

  log_cache "prime" "type=$type files_cached=$count"
}

# ============================================================================
# REPOSITORY MAP
# ============================================================================

build_repo_map() {
  # Generate repository structure tree
  # Returns: text tree (also cached as repo_map key)

  # Check if cached and fresh
  if [[ -f "$CACHE_REPO_MAP" ]]; then
    local age=$(($(date +%s) - $(stat -f %m "$CACHE_REPO_MAP" 2>/dev/null || stat -c %Y "$CACHE_REPO_MAP" 2>/dev/null || echo "0")))
    if [[ "$age" -lt "$CACHE_REPO_MAP_TTL" ]]; then
      cat "$CACHE_REPO_MAP"
      return 0
    fi
  fi

  # Generate fresh map
  local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S")
  local total_files=$(find "$CLAUDE_ROOT" -type f 2>/dev/null | wc -l | tr -d ' ')
  local tracked_files=0
  local is_git_repo="no"

  if git -C "$CLAUDE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    is_git_repo="yes"
    tracked_files=$(git -C "$CLAUDE_ROOT" ls-files | wc -l | tr -d ' ')
  fi

  local output=""
  output+="REPOSITORY MAP (generated $timestamp)\n"
  output+="Total files: $total_files | Tracked files: $tracked_files | Git repo: $is_git_repo\n\n"

  # Generate tree (depth 3)
  if command -v tree >/dev/null 2>&1; then
    output+=$(tree -L 3 -I 'node_modules|.git|*.pyc|__pycache__|.next|dist|build' "$CLAUDE_ROOT" 2>/dev/null || echo "Tree unavailable")
  else
    output+=$(ls -R "$CLAUDE_ROOT" | head -100)
  fi

  output+="\n\nKey directories:\n"
  output+="  Policies:  docs/policy/*.md ($(ls "$CLAUDE_ROOT"/docs/policy/*.md 2>/dev/null | wc -l | tr -d ' ') files)\n"
  output+="  Runbooks:  .claude/runbooks/*.md ($(ls "$CLAUDE_ROOT"/.claude/runbooks/*.md 2>/dev/null | wc -l | tr -d ' ') files)\n"
  output+="  Agents:    .claude/agents/*.md ($(ls "$CLAUDE_ROOT"/.claude/agents/*.md 2>/dev/null | wc -l | tr -d ' ') files)\n"
  output+="  Scripts:   .claude/scripts/*.sh ($(ls "$CLAUDE_ROOT"/.claude/scripts/*.sh 2>/dev/null | wc -l | tr -d ' ') files)\n"

  # Write to cache file
  echo -e "$output" > "$CACHE_REPO_MAP"

  # Also store in SQLite
  cache_set "repo_map" "$output" "repo_map"

  log_cache "repo_map_generated" "files=$total_files"
  echo -e "$output"
}

# ============================================================================
# STATISTICS
# ============================================================================

cache_stats() {
  # Compute cache performance metrics
  # Returns: JSON object

  local total=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM cache_entries;")
  local by_type=$(sqlite3 "$CACHE_DB" "SELECT type, COUNT(*) FROM cache_entries GROUP BY type;" | awk '{printf "%s:%s ", $1, $2}')
  local total_reads=$(sqlite3 "$CACHE_DB" "SELECT SUM(read_count) FROM cache_entries;")
  local avg_reads=$(sqlite3 "$CACHE_DB" "SELECT AVG(read_count) FROM cache_entries;")
  local most_read=$(sqlite3 "$CACHE_DB" "SELECT key, read_count FROM cache_entries ORDER BY read_count DESC LIMIT 3;" | awk '{printf "%s(%s) ", $1, $2}')

  echo "{\"total_entries\":$total,\"by_type\":\"$by_type\",\"total_reads\":${total_reads:-0},\"avg_reads\":${avg_reads:-0},\"most_read\":\"$most_read\"}"
}

cache_evict_stale() {
  # Evict least-used entries if cache exceeds threshold
  local count=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM cache_entries;")

  if [[ "$count" -gt "$CACHE_EVICTION_THRESHOLD" ]]; then
    local keep_count=$((CACHE_EVICTION_THRESHOLD * 80 / 100))
    local now=$(date +%s)

    # Compute score = read_count / (1 + age_in_days)
    # Keep top 80% (frequent + recent), delete bottom 20% (stale + infrequent)
    sqlite3 "$CACHE_DB" <<EOF
DELETE FROM cache_entries
WHERE id NOT IN (
  SELECT id FROM cache_entries
  ORDER BY (read_count / (1.0 + ($now - last_read) / 86400.0)) DESC
  LIMIT $keep_count
);
EOF

    log_cache "eviction" "threshold=$CACHE_EVICTION_THRESHOLD kept=$keep_count"
  fi
}

# ============================================================================
# LOCKING MECHANISM
# ============================================================================

LOCK_DIR="${CACHE_DIR}/.lock"
LOCK_TIMEOUT=30  # Maximum lock age in seconds

cache_lock() {
  # Acquire exclusive lock using atomic mkdir
  # Usage: cache_lock
  # Returns: 0 on success, 1 on failure

  local attempt=0
  local max_attempts=10

  while [[ $attempt -lt $max_attempts ]]; do
    # Try to acquire lock
    if mkdir "$LOCK_DIR" 2>/dev/null; then
      # Lock acquired
      echo $$ > "$LOCK_DIR/pid"

      # Register cleanup trap
      trap 'cache_unlock' EXIT INT TERM
      log_cache "lock" "acquired"
      return 0
    fi

    # Lock exists - check if stale
    if [[ -f "$LOCK_DIR/pid" ]]; then
      local lock_age=$(($(date +%s) - $(stat -f %m "$LOCK_DIR" 2>/dev/null || stat -c %Y "$LOCK_DIR" 2>/dev/null || echo "0")))
      if [[ "$lock_age" -gt "$LOCK_TIMEOUT" ]]; then
        # Stale lock - remove it
        rm -rf "$LOCK_DIR"
        log_cache "lock_stale_removed" "Removed stale lock (age: ${lock_age}s)"
        continue
      fi
    fi

    # Wait and retry
    sleep 0.1
    attempt=$((attempt + 1))
  done

  log_cache "lock_timeout" "Failed to acquire lock after $max_attempts attempts"
  return 1
}

cache_unlock() {
  # Release lock
  # Usage: cache_unlock

  if [[ -d "$LOCK_DIR" ]]; then
    rm -rf "$LOCK_DIR"
  fi
}

# ============================================================================
# CACHE WARMING AND GARBAGE COLLECTION
# ============================================================================

cache_warm() {
  # Pre-populate cache with high-value files
  # Usage: cache_warm
  # Returns: count of files cached

  log_cache "warm_start" "Starting cache warm"

  local count=0

  # Warm policies
  if [[ -d "$CLAUDE_ROOT/docs/policy" ]]; then
    for policy in "$CLAUDE_ROOT"/docs/policy/*.md; do
      [[ -f "$policy" ]] || continue
      cache_set_file "$policy" "policy" && count=$((count + 1))
    done
  fi

  # Warm runbooks
  if [[ -d "$CLAUDE_ROOT/.claude/runbooks" ]]; then
    for runbook in "$CLAUDE_ROOT"/.claude/runbooks/*.md; do
      [[ -f "$runbook" ]] || continue
      cache_set_file "$runbook" "runbook" && count=$((count + 1))
    done
  fi

  # Warm core files
  [[ -f "$CLAUDE_ROOT/CLAUDE.md" ]] && cache_set_file "$CLAUDE_ROOT/CLAUDE.md" "core" && count=$((count + 1))
  [[ -f "$CLAUDE_ROOT/.mcp.json" ]] && cache_set_file "$CLAUDE_ROOT/.mcp.json" "core" && count=$((count + 1))

  # Generate and cache repo map
  local repo_map=$(build_repo_map)
  cache_set "repo_map" "$repo_map" "repo_map" && count=$((count + 1))

  log_cache "warm_complete" "Warmed $count files"
  echo "$count"
}

cache_gc() {
  # Garbage collection - remove stale entries
  # Usage: cache_gc [max_age_seconds]
  # Returns: count of entries removed

  log_cache "gc_start" "Starting garbage collection"

  local now=$(date +%s)
  local max_age="${1:-86400}"  # Default: 24 hours
  local count_before=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM cache_entries;")

  # Delete entries not read in last max_age seconds
  # Use: last_read < (now - max_age) for correct comparison
  sqlite3 "$CACHE_DB" "DELETE FROM cache_entries WHERE last_read < ($now - $max_age);"

  local count_after=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM cache_entries;")
  local removed=$((count_before - count_after))

  # Run VACUUM to reclaim space
  sqlite3 "$CACHE_DB" "VACUUM;"

  log_cache "gc_complete" "Removed $removed stale entries (max_age=${max_age}s)"
  echo "$removed"
}

# ============================================================================
# DECISION MEMORY
# ============================================================================

decision_memory_record() {
  # Record Manager decision metrics for analysis
  # Usage: decision_memory_record <run_id> <task_mode> <tokens_estimated> <tokens_actual> <architect_skipped> <loops> <duration_seconds>
  local run_id="$1"
  local task_mode="$2"
  local tokens_estimated="$3"
  local tokens_actual="$4"
  local architect_skipped="$5"
  local loops="$6"
  local duration_seconds="$7"

  # Ensure decision_memory table exists
  sqlite3 "$CACHE_DB" <<'EOF'
CREATE TABLE IF NOT EXISTS decision_memory (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id              TEXT NOT NULL,
  task_mode           TEXT NOT NULL,
  tokens_estimated    INTEGER,
  tokens_actual       INTEGER,
  architect_skipped   INTEGER DEFAULT 0,
  loops               INTEGER DEFAULT 0,
  duration_seconds    INTEGER,
  created_at          INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_decision_run_id ON decision_memory(run_id);
CREATE INDEX IF NOT EXISTS idx_decision_task_mode ON decision_memory(task_mode);
EOF

  local now=$(date +%s)
  local escaped_run_id="${run_id//\'/''}"
  local escaped_task_mode="${task_mode//\'/''}"

  sqlite3 "$CACHE_DB" <<EOF
INSERT INTO decision_memory (run_id, task_mode, tokens_estimated, tokens_actual, architect_skipped, loops, duration_seconds, created_at)
VALUES ('$escaped_run_id', '$escaped_task_mode', $tokens_estimated, $tokens_actual, $architect_skipped, $loops, $duration_seconds, $now);
EOF

  log_cache "decision_memory_record" "run_id=$run_id task_mode=$task_mode tokens=$tokens_actual loops=$loops"
}

decision_memory_stats() {
  # Compute decision memory statistics
  # Usage: decision_memory_stats
  # Returns: JSON object with aggregated metrics

  # Check if table exists
  if ! sqlite3 "$CACHE_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='decision_memory';" | grep -q "decision_memory"; then
    echo '{"error": "decision_memory table does not exist"}'
    return 1
  fi

  local total_runs=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM decision_memory;")
  local avg_tokens=$(sqlite3 "$CACHE_DB" "SELECT AVG(tokens_actual) FROM decision_memory WHERE tokens_actual IS NOT NULL;")
  local avg_loops=$(sqlite3 "$CACHE_DB" "SELECT AVG(loops) FROM decision_memory WHERE loops IS NOT NULL;")
  local avg_duration=$(sqlite3 "$CACHE_DB" "SELECT AVG(duration_seconds) FROM decision_memory WHERE duration_seconds IS NOT NULL;")
  local architect_skip_rate=$(sqlite3 "$CACHE_DB" "SELECT CAST(SUM(architect_skipped) AS FLOAT) / COUNT(*) * 100 FROM decision_memory;")

  # Mode breakdown
  local mode_breakdown=$(sqlite3 "$CACHE_DB" "SELECT task_mode, COUNT(*) FROM decision_memory GROUP BY task_mode;" | awk '{printf "%s:%s ", $1, $2}')

  echo "{\"total_runs\":$total_runs,\"avg_tokens\":${avg_tokens:-0},\"avg_loops\":${avg_loops:-0},\"avg_duration\":${avg_duration:-0},\"architect_skip_rate\":${architect_skip_rate:-0},\"mode_breakdown\":\"$mode_breakdown\"}"
}

decision_memory_summary() {
  # Generate a formatted Decision Memory Summary for the Reporter
  # Usage: decision_memory_summary [N]
  # N = number of recent runs to analyze (default: 10)
  # Returns: Formatted markdown text suitable for report inclusion

  local n="${1:-10}"

  # Check if table exists
  if ! sqlite3 "$CACHE_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='decision_memory';" 2>/dev/null | grep -q "decision_memory"; then
    echo "Decision Memory: No data available (table not initialized)"
    return 1
  fi

  local total_runs
  total_runs=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM decision_memory;" 2>/dev/null || echo "0")

  if [[ "$total_runs" -eq 0 ]]; then
    echo "Decision Memory: No historical data recorded yet"
    return 0
  fi

  # Compute stats from last N runs
  local recent_n=$((total_runs < n ? total_runs : n))

  local architect_skip_rate
  architect_skip_rate=$(sqlite3 "$CACHE_DB" "SELECT printf('%.1f', CAST(SUM(architect_skipped) AS FLOAT) / COUNT(*) * 100) FROM (SELECT architect_skipped FROM decision_memory ORDER BY created_at DESC LIMIT $recent_n);" 2>/dev/null || echo "0.0")

  local avg_loops_micro
  avg_loops_micro=$(sqlite3 "$CACHE_DB" "SELECT printf('%.1f', AVG(loops)) FROM (SELECT loops FROM decision_memory WHERE task_mode='MICRO-CHANGE' ORDER BY created_at DESC LIMIT $recent_n);" 2>/dev/null || echo "N/A")

  local avg_loops_standard
  avg_loops_standard=$(sqlite3 "$CACHE_DB" "SELECT printf('%.1f', AVG(loops)) FROM (SELECT loops FROM decision_memory WHERE task_mode='STANDARD' ORDER BY created_at DESC LIMIT $recent_n);" 2>/dev/null || echo "N/A")

  local avg_loops_verification
  avg_loops_verification=$(sqlite3 "$CACHE_DB" "SELECT printf('%.1f', AVG(loops)) FROM (SELECT loops FROM decision_memory WHERE task_mode='VERIFICATION' ORDER BY created_at DESC LIMIT $recent_n);" 2>/dev/null || echo "N/A")

  # Token trend: compare first half vs second half of recent runs
  local half_n=$((recent_n / 2))
  if [[ "$half_n" -lt 1 ]]; then half_n=1; fi

  local older_avg_tokens
  older_avg_tokens=$(sqlite3 "$CACHE_DB" "SELECT CAST(AVG(tokens_actual) AS INTEGER) FROM (SELECT tokens_actual FROM decision_memory WHERE tokens_actual IS NOT NULL ORDER BY created_at DESC LIMIT $recent_n OFFSET $half_n);" 2>/dev/null || echo "0")

  local newer_avg_tokens
  newer_avg_tokens=$(sqlite3 "$CACHE_DB" "SELECT CAST(AVG(tokens_actual) AS INTEGER) FROM (SELECT tokens_actual FROM decision_memory WHERE tokens_actual IS NOT NULL ORDER BY created_at DESC LIMIT $half_n);" 2>/dev/null || echo "0")

  local token_trend="stable"
  if [[ "$older_avg_tokens" -gt 0 && "$newer_avg_tokens" -gt 0 ]]; then
    local pct_change=$(( (newer_avg_tokens - older_avg_tokens) * 100 / older_avg_tokens ))
    if [[ "$pct_change" -gt 10 ]]; then
      token_trend="increasing (+${pct_change}%)"
    elif [[ "$pct_change" -lt -10 ]]; then
      token_trend="decreasing (${pct_change}%)"
    fi
  fi

  # Mode breakdown for last N runs
  local mode_breakdown
  mode_breakdown=$(sqlite3 "$CACHE_DB" "SELECT task_mode || ':' || COUNT(*) FROM (SELECT task_mode FROM decision_memory ORDER BY created_at DESC LIMIT $recent_n) GROUP BY task_mode;" 2>/dev/null | tr '\n' ' ')

  # Overall averages
  local avg_tokens
  avg_tokens=$(sqlite3 "$CACHE_DB" "SELECT CAST(AVG(tokens_actual) AS INTEGER) FROM (SELECT tokens_actual FROM decision_memory WHERE tokens_actual IS NOT NULL ORDER BY created_at DESC LIMIT $recent_n);" 2>/dev/null || echo "0")

  local avg_duration
  avg_duration=$(sqlite3 "$CACHE_DB" "SELECT CAST(AVG(duration_seconds) AS INTEGER) FROM (SELECT duration_seconds FROM decision_memory WHERE duration_seconds IS NOT NULL ORDER BY created_at DESC LIMIT $recent_n);" 2>/dev/null || echo "0")

  # Format output
  cat <<SUMMARY
## Decision Memory Summary (last $recent_n of $total_runs runs)

| Metric | Value |
|--------|-------|
| Architect skip rate | ${architect_skip_rate}% |
| Avg loops (MICRO-CHANGE) | ${avg_loops_micro} |
| Avg loops (STANDARD) | ${avg_loops_standard} |
| Avg loops (VERIFICATION) | ${avg_loops_verification} |
| Avg tokens (recent) | ${avg_tokens} |
| Token trend | ${token_trend} |
| Avg duration | ${avg_duration}s |
| Mode breakdown | ${mode_breakdown} |
SUMMARY
}

decision_memory_predict() {
  # Use historical decision memory to predict task mode characteristics
  # Usage: decision_memory_predict <task_mode>
  # Returns: JSON with predicted loops, tokens, and architect_skip recommendation
  #
  # The Manager calls this during Phase 0 to inform budget allocation

  local task_mode="$1"

  # Check if table exists and has data
  if ! sqlite3 "$CACHE_DB" "SELECT name FROM sqlite_master WHERE type='table' AND name='decision_memory';" 2>/dev/null | grep -q "decision_memory"; then
    echo '{"prediction":"unavailable","reason":"no_data"}'
    return 0
  fi

  local mode_count
  mode_count=$(sqlite3 "$CACHE_DB" "SELECT COUNT(*) FROM decision_memory WHERE task_mode='$task_mode';" 2>/dev/null || echo "0")

  if [[ "$mode_count" -lt 3 ]]; then
    echo "{\"prediction\":\"insufficient_data\",\"mode\":\"$task_mode\",\"samples\":$mode_count}"
    return 0
  fi

  # Compute predictions from historical data for this mode
  local predicted_loops
  predicted_loops=$(sqlite3 "$CACHE_DB" "SELECT printf('%.1f', AVG(loops)) FROM decision_memory WHERE task_mode='$task_mode';" 2>/dev/null || echo "0")

  local predicted_tokens
  predicted_tokens=$(sqlite3 "$CACHE_DB" "SELECT CAST(AVG(tokens_actual) AS INTEGER) FROM decision_memory WHERE task_mode='$task_mode' AND tokens_actual IS NOT NULL;" 2>/dev/null || echo "0")

  local skip_rate
  skip_rate=$(sqlite3 "$CACHE_DB" "SELECT printf('%.1f', CAST(SUM(architect_skipped) AS FLOAT) / COUNT(*) * 100) FROM decision_memory WHERE task_mode='$task_mode';" 2>/dev/null || echo "0")

  local avg_duration
  avg_duration=$(sqlite3 "$CACHE_DB" "SELECT CAST(AVG(duration_seconds) AS INTEGER) FROM decision_memory WHERE task_mode='$task_mode' AND duration_seconds IS NOT NULL;" 2>/dev/null || echo "0")

  # Recommend architect skip if: skip_rate > 30% AND skipped tasks have fewer loops
  local recommend_skip="false"
  local skip_float=${skip_rate%.*}
  if [[ "${skip_float:-0}" -gt 30 ]]; then
    local skipped_avg_loops
    skipped_avg_loops=$(sqlite3 "$CACHE_DB" "SELECT AVG(loops) FROM decision_memory WHERE task_mode='$task_mode' AND architect_skipped=1;" 2>/dev/null || echo "999")
    local nonskipped_avg_loops
    nonskipped_avg_loops=$(sqlite3 "$CACHE_DB" "SELECT AVG(loops) FROM decision_memory WHERE task_mode='$task_mode' AND architect_skipped=0;" 2>/dev/null || echo "0")

    # Compare as integers (multiply by 10 for precision)
    local skip_x10=$(echo "$skipped_avg_loops" | awk '{printf "%d", $1 * 10}')
    local nonskip_x10=$(echo "$nonskipped_avg_loops" | awk '{printf "%d", $1 * 10}')
    if [[ "$skip_x10" -le "$nonskip_x10" ]]; then
      recommend_skip="true"
    fi
  fi

  # Token budget recommendation: use 120% of historical average as budget
  local recommended_budget
  if [[ "$predicted_tokens" -gt 0 ]]; then
    recommended_budget=$((predicted_tokens * 120 / 100))
  else
    recommended_budget=0
  fi

  echo "{\"prediction\":\"available\",\"mode\":\"$task_mode\",\"samples\":$mode_count,\"predicted_loops\":$predicted_loops,\"predicted_tokens\":$predicted_tokens,\"architect_skip_rate\":$skip_rate,\"recommend_architect_skip\":$recommend_skip,\"avg_duration\":$avg_duration,\"recommended_token_budget\":$recommended_budget}"
}

# ============================================================================
# TOOL OUTPUT CACHING
# ============================================================================

_tool_cache_key() {
  # Generate cache key for tool output
  # Usage: _tool_cache_key <tool_name> <args...>
  local tool="$1"
  shift
  local args="$*"
  local git_head=$(git -C "$CLAUDE_ROOT" rev-parse HEAD 2>/dev/null || echo "no-git")

  # Hash args + git_head to create stable key
  local fingerprint=$(echo "${tool}:${args}:${git_head}" | shasum -a 256 | awk '{print $1}')
  echo "tool:${tool}:${fingerprint}"
}

cached_rg() {
  # Cached ripgrep wrapper
  # Usage: cached_rg <pattern> [path]
  local pattern="$1"
  local path="${2:-$CLAUDE_ROOT}"

  local key=$(_tool_cache_key "rg" "$pattern" "$path")

  # Try cache first
  local cached=$(cache_get "$key" 2>/dev/null || echo "")
  if [[ -n "$cached" ]]; then
    echo "$cached"
    return 0
  fi

  # Cache miss - run rg
  if command -v rg >/dev/null 2>&1; then
    local output=$(rg "$pattern" "$path" 2>/dev/null || echo "")
    cache_set "$key" "$output" "tool_output"
    echo "$output"
  else
    echo ""
    return 1
  fi
}

cached_git_diff() {
  # Cached git diff wrapper
  # Usage: cached_git_diff [base] [head]
  local base="${1:-HEAD~1}"
  local head="${2:-HEAD}"

  local key=$(_tool_cache_key "git_diff" "$base" "$head")

  # Try cache first
  local cached=$(cache_get "$key" 2>/dev/null || echo "")
  if [[ -n "$cached" ]]; then
    echo "$cached"
    return 0
  fi

  # Cache miss - run git diff
  if git -C "$CLAUDE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local output=$(git -C "$CLAUDE_ROOT" diff --name-status "$base" "$head" 2>/dev/null || echo "")
    cache_set "$key" "$output" "tool_output"
    echo "$output"
  else
    echo ""
    return 1
  fi
}

cached_file_list() {
  # Cached file list wrapper
  # Usage: cached_file_list [pattern]
  local pattern="${1:-*}"

  local key=$(_tool_cache_key "file_list" "$pattern")

  # Try cache first
  local cached=$(cache_get "$key" 2>/dev/null || echo "")
  if [[ -n "$cached" ]]; then
    echo "$cached"
    return 0
  fi

  # Cache miss - run find/ls
  if git -C "$CLAUDE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local output=$(git -C "$CLAUDE_ROOT" ls-files "$pattern" 2>/dev/null || echo "")
    cache_set "$key" "$output" "tool_output"
    echo "$output"
  else
    local output=$(find "$CLAUDE_ROOT" -name "$pattern" -type f 2>/dev/null || echo "")
    cache_set "$key" "$output" "tool_output"
    echo "$output"
  fi
}

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

cache_get_file() {
  # Convenience wrapper for file reads
  # Usage: cache_get_file <filepath>
  local filepath=$(realpath "$1")
  local key="file:$filepath"

  cache_get "$key"
}

cache_set_file() {
  # Convenience wrapper for file caching
  # Usage: cache_set_file <filepath> <type>
  local filepath=$(realpath "$1")
  local type="${2:-file}"
  local key="file:$filepath"

  if [[ ! -f "$filepath" ]]; then
    log_cache "error" "File not found: $filepath"
    return 1
  fi

  # Block secret files from being cached
  if is_secret_file "$filepath"; then
    log_cache "blocked" "Secret file rejected: $filepath"
    return 1
  fi

  local content=$(cat "$filepath")
  cache_set "$key" "$content" "$type" "$filepath"
}

cache_invalidate_file() {
  # Convenience wrapper for file invalidation
  # Usage: cache_invalidate_file <filepath>
  local filepath=$(realpath "$1")
  local key="file:$filepath"

  cache_invalidate "$key"
}

# ============================================================================
# EXPORTS
# ============================================================================

# Export all functions before initialization so they're available in subshells
export -f log_cache
export -f _tool_cache_key
export -f cache_init
export -f cache_set
export -f cache_get
export -f cache_invalidate
export -f cache_invalidate_type
export -f cache_flush
export -f cache_prime
export -f build_repo_map
export -f cache_stats
export -f cache_evict_stale
export -f cache_get_file
export -f cache_set_file
export -f cache_invalidate_file
export -f cache_lock
export -f cache_unlock
export -f cache_warm
export -f cache_gc
export -f decision_memory_record
export -f decision_memory_stats
export -f decision_memory_summary
export -f decision_memory_predict
export -f cached_rg
export -f cached_git_diff
export -f cached_file_list

# Export redaction functions (if available)
if declare -f is_secret_file >/dev/null 2>&1; then
  export -f is_secret_file
fi
if declare -f redact_stream >/dev/null 2>&1; then
  export -f redact_stream
fi

# ============================================================================
# INITIALIZATION
# ============================================================================

# Auto-init cache on source
cache_init
