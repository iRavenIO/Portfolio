#!/usr/bin/env bash
set -euo pipefail

# PostgreSQL Operations Wrapper
# Enforces permission tiers, dry-run defaults, confirmation gates, and audit logging

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAUDE_ROOT="${CLAUDE_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"
source "${CLAUDE_ROOT}/.claude/scripts/redact.sh"

# Global state
DRY_RUN=true
CONFIRMED=false
FORCED=false
RUN_ID="${RUN_ID:-$(date +%s)-$$}"
START_TIME=$(date +%s%3N)

# Parse global flags
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --confirm)
      CONFIRMED=true
      DRY_RUN=false
      shift
      ;;
    --force)
      FORCED=true
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      ARGS+=("$1")
      shift
      ;;
  esac
done

# Audit logging function
audit_log() {
  local tool=$1
  local func=$2
  local exit_code=$3
  shift 3

  local end_time=$(date +%s%3N)
  local duration=$((end_time - START_TIME))
  local args_json=$(printf '%s\n' "$@" | jq -R . | jq -s .)

  mkdir -p "${CLAUDE_ROOT}/.claude/logs"
  echo "{\"timestamp\":\"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\",\"run_id\":\"$RUN_ID\",\"tool\":\"$tool\",\"function\":\"$func\",\"args\":$args_json,\"dry_run\":$DRY_RUN,\"confirmed\":$CONFIRMED,\"forced\":$FORCED,\"exit_code\":$exit_code,\"duration_ms\":$duration}" >> "${CLAUDE_ROOT}/.claude/logs/ops-audit-$RUN_ID.log"
}

# Check if psql is available
if ! command -v psql &> /dev/null; then
  echo "[ERROR] psql not found. Please install PostgreSQL client." >&2
  exit 5
fi

# Detect DDL operations (require tier escalation)
is_ddl() {
  local query=$1
  local upper_query=$(echo "$query" | tr '[:lower:]' '[:upper:]')

  if [[ "$upper_query" =~ (DROP|TRUNCATE|ALTER[[:space:]]+TABLE|ALTER[[:space:]]+DATABASE|CREATE[[:space:]]+DATABASE|DROP[[:space:]]+DATABASE) ]]; then
    return 0
  fi
  return 1
}

# pg_query_readonly: Execute a read-only query (READ tier)
pg_query_readonly() {
  local query=$1
  local database=""
  local limit=100

  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --database=*)
        database="${1#*=}"
        shift
        ;;
      --limit=*)
        limit="${1#*=}"
        if [[ $limit -gt 1000 ]]; then
          echo "[ERROR] pg_query_readonly: Row limit cannot exceed 1000" >&2
          exit 1
        fi
        shift
        ;;
      *)
        echo "[ERROR] pg_query_readonly: Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  if [[ -z "$database" ]]; then
    echo "[ERROR] pg_query_readonly: --database is required" >&2
    audit_log "psql" "pg_query_readonly" 3 "[query]"
    exit 3
  fi

  # Enforce read-only transaction and row limit
  local wrapped_query="BEGIN TRANSACTION READ ONLY; SET statement_timeout = '30s'; $query LIMIT $limit; COMMIT;"

  local cmd="psql -d $database -c \"$wrapped_query\""
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "psql" "pg_query_readonly" 0 "[query-redacted]" "--database=$database" "--limit=$limit"
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "psql" "pg_query_readonly" 1 "[query-redacted]" "--database=$database" "--limit=$limit"
    return 1
  fi
}

# pg_query_write: Execute a write query (WRITE/INFRASTRUCTURE tier)
pg_query_write() {
  local query=$1
  local database=""

  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --database=*)
        database="${1#*=}"
        shift
        ;;
      *)
        echo "[ERROR] pg_query_write: Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  if [[ -z "$database" ]]; then
    echo "[ERROR] pg_query_write: --database is required" >&2
    audit_log "psql" "pg_query_write" 3 "[query]"
    exit 3
  fi

  # Check if this is DDL (requires INFRASTRUCTURE tier)
  if is_ddl "$query"; then
    if [[ "$CONFIRMED" == "false" || "$FORCED" == "false" ]]; then
      echo "[ERROR] pg_query_write: DDL operation requires INFRASTRUCTURE tier (--confirm --force)" >&2
      echo "[ERROR] Detected destructive operation in query" >&2
      audit_log "psql" "pg_query_write" 2 "[ddl-query-redacted]" "--database=$database"
      exit 2
    fi
    echo "[WARNING] Executing DDL operation on database: $database"
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] Would execute query on database: $database"
    echo "[DRY RUN] Generating EXPLAIN plan..."
    local explain_query="EXPLAIN $query"
    local cmd="psql -d $database -c \"$explain_query\""
    local output
    if output=$(eval "$cmd" 2>&1); then
      echo "$output" | redact_stream
      audit_log "psql" "pg_query_write" 0 "[query-redacted]" "--database=$database" "[dry-run]"
      return 0
    else
      echo "$output" | redact_stream >&2
      audit_log "psql" "pg_query_write" 4 "[query-redacted]" "--database=$database" "[dry-run]"
      return 1
    fi
  fi

  if [[ "$CONFIRMED" == "false" ]]; then
    echo "[ERROR] pg_query_write: Missing required flag --confirm for mutating operation" >&2
    echo "[ERROR] Use: postgres.sh pg_query_write \"<query>\" --database=$database --confirm" >&2
    audit_log "psql" "pg_query_write" 2 "[query-redacted]" "--database=$database"
    exit 2
  fi

  local cmd="psql -d $database -c \"$query\""
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "psql" "pg_query_write" 0 "[query-redacted]" "--database=$database"
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "psql" "pg_query_write" 1 "[query-redacted]" "--database=$database"
    return 1
  fi
}

# pg_exec_file: Execute SQL file (WRITE tier)
pg_exec_file() {
  local sql_file=$1
  local database=""

  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --database=*)
        database="${1#*=}"
        shift
        ;;
      *)
        echo "[ERROR] pg_exec_file: Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  if [[ ! -f "$sql_file" ]]; then
    echo "[ERROR] pg_exec_file: File not found: $sql_file" >&2
    audit_log "psql" "pg_exec_file" 1 "$sql_file"
    exit 1
  fi

  if [[ -z "$database" ]]; then
    echo "[ERROR] pg_exec_file: --database is required" >&2
    audit_log "psql" "pg_exec_file" 3 "$sql_file"
    exit 3
  fi

  # Check if file contains DDL
  if grep -qiE "(DROP|TRUNCATE|ALTER TABLE|ALTER DATABASE|CREATE DATABASE|DROP DATABASE)" "$sql_file"; then
    if [[ "$CONFIRMED" == "false" || "$FORCED" == "false" ]]; then
      echo "[ERROR] pg_exec_file: File contains DDL, requires INFRASTRUCTURE tier (--confirm --force)" >&2
      audit_log "psql" "pg_exec_file" 2 "$sql_file" "--database=$database"
      exit 2
    fi
    echo "[WARNING] File contains DDL operations"
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] Would execute SQL file: $sql_file"
    echo "[DRY RUN] Validating syntax..."
    # Syntax validation only
    local cmd="psql -d $database --dry-run -f $sql_file"
    local output
    if output=$(eval "$cmd" 2>&1); then
      echo "[DRY RUN] Syntax validation passed"
      audit_log "psql" "pg_exec_file" 0 "$sql_file" "--database=$database" "[dry-run]"
      return 0
    else
      echo "$output" | redact_stream >&2
      audit_log "psql" "pg_exec_file" 4 "$sql_file" "--database=$database" "[dry-run]"
      return 1
    fi
  fi

  if [[ "$CONFIRMED" == "false" ]]; then
    echo "[ERROR] pg_exec_file: Missing required flag --confirm for mutating operation" >&2
    echo "[ERROR] Use: postgres.sh pg_exec_file $sql_file --database=$database --confirm" >&2
    audit_log "psql" "pg_exec_file" 2 "$sql_file" "--database=$database"
    exit 2
  fi

  local cmd="psql -d $database -f $sql_file"
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "psql" "pg_exec_file" 0 "$sql_file" "--database=$database"
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "psql" "pg_exec_file" 1 "$sql_file" "--database=$database"
    return 1
  fi
}

# Main dispatcher
FUNCTION="${ARGS[0]:-}"
if [[ -z "$FUNCTION" ]]; then
  echo "Usage: postgres.sh <function> [args...]" >&2
  echo "Functions: pg_query_readonly, pg_query_write, pg_exec_file" >&2
  exit 1
fi

case "$FUNCTION" in
  pg_query_readonly)
    pg_query_readonly "${ARGS[@]:1}"
    ;;
  pg_query_write)
    pg_query_write "${ARGS[@]:1}"
    ;;
  pg_exec_file)
    pg_exec_file "${ARGS[@]:1}"
    ;;
  *)
    echo "[ERROR] Unknown function: $FUNCTION" >&2
    exit 1
    ;;
esac
