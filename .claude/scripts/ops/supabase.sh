#!/usr/bin/env bash
set -euo pipefail

# Supabase Operations Wrapper
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

# Check if supabase is available
if ! command -v supabase &> /dev/null; then
  echo "[ERROR] supabase CLI not found. Please install supabase CLI." >&2
  exit 5
fi

# supabase_status: Get project status (READ tier)
supabase_status() {
  local cmd="supabase status"
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "supabase" "supabase_status" 0
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "supabase" "supabase_status" 1
    return 1
  fi
}

# supabase_projects: List projects (READ tier)
supabase_projects() {
  local cmd="supabase projects list"
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "supabase" "supabase_projects" 0
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "supabase" "supabase_projects" 1
    return 1
  fi
}

# supabase_link: Link to a remote project (EXECUTE tier)
supabase_link() {
  local project_ref=$1

  if [[ -z "$project_ref" ]]; then
    echo "[ERROR] supabase_link: Project reference is required" >&2
    audit_log "supabase" "supabase_link" 1
    exit 1
  fi

  if [[ "$CONFIRMED" == "false" ]]; then
    echo "[ERROR] supabase_link: EXECUTE tier operation requires --confirm" >&2
    echo "[ERROR] Use: supabase.sh supabase_link $project_ref --confirm" >&2
    audit_log "supabase" "supabase_link" 2 "$project_ref"
    exit 2
  fi

  echo "[INFO] Linking to Supabase project: $project_ref"
  echo "[INFO] This may require interactive authentication..."
  local cmd="supabase link --project-ref $project_ref"
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "supabase" "supabase_link" 0 "$project_ref"
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "supabase" "supabase_link" 1 "$project_ref"
    return 1
  fi
}

# supabase_db_diff: Show pending database migrations (READ tier)
supabase_db_diff() {
  local cmd="supabase db diff"
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "supabase" "supabase_db_diff" 0
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "supabase" "supabase_db_diff" 1
    return 1
  fi
}

# supabase_db_migrate: Apply database migrations (WRITE tier)
supabase_db_migrate() {
  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] Would apply pending database migrations"
    echo "[DRY RUN] Showing diff..."
    supabase_db_diff
    audit_log "supabase" "supabase_db_migrate" 0 "[dry-run]"
    return 0
  fi

  if [[ "$CONFIRMED" == "false" ]]; then
    echo "[ERROR] supabase_db_migrate: Missing required flag --confirm for mutating operation" >&2
    echo "[ERROR] Use: supabase.sh supabase_db_migrate --confirm" >&2
    audit_log "supabase" "supabase_db_migrate" 2
    exit 2
  fi

  local cmd="supabase db push"
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "supabase" "supabase_db_migrate" 0
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "supabase" "supabase_db_migrate" 1
    return 1
  fi
}

# supabase_db_reset: Reset local database (INFRASTRUCTURE tier)
supabase_db_reset() {
  if [[ "$CONFIRMED" == "false" || "$FORCED" == "false" ]]; then
    echo "[ERROR] supabase_db_reset: INFRASTRUCTURE tier operation requires --confirm --force" >&2
    echo "[ERROR] Use: supabase.sh supabase_db_reset --confirm --force" >&2
    echo "[WARNING] This will DROP ALL DATA in the local database" >&2
    audit_log "supabase" "supabase_db_reset" 2
    exit 2
  fi

  echo "[WARNING] Resetting local Supabase database - ALL DATA WILL BE LOST"
  local cmd="supabase db reset"
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "supabase" "supabase_db_reset" 0
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "supabase" "supabase_db_reset" 1
    return 1
  fi
}

# supabase_functions_deploy: Deploy edge functions (WRITE tier)
supabase_functions_deploy() {
  local function_name=$1

  if [[ -z "$function_name" ]]; then
    echo "[ERROR] supabase_functions_deploy: Function name is required" >&2
    audit_log "supabase" "supabase_functions_deploy" 1
    exit 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] Would deploy function: $function_name"
    audit_log "supabase" "supabase_functions_deploy" 0 "$function_name" "[dry-run]"
    return 0
  fi

  if [[ "$CONFIRMED" == "false" ]]; then
    echo "[ERROR] supabase_functions_deploy: Missing required flag --confirm for mutating operation" >&2
    echo "[ERROR] Use: supabase.sh supabase_functions_deploy $function_name --confirm" >&2
    audit_log "supabase" "supabase_functions_deploy" 2 "$function_name"
    exit 2
  fi

  local cmd="supabase functions deploy $function_name"
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "supabase" "supabase_functions_deploy" 0 "$function_name"
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "supabase" "supabase_functions_deploy" 1 "$function_name"
    return 1
  fi
}

# supabase_unlink: Unlink from remote project (INFRASTRUCTURE tier)
supabase_unlink() {
  if [[ "$CONFIRMED" == "false" || "$FORCED" == "false" ]]; then
    echo "[ERROR] supabase_unlink: INFRASTRUCTURE tier operation requires --confirm --force" >&2
    echo "[ERROR] Use: supabase.sh supabase_unlink --confirm --force" >&2
    audit_log "supabase" "supabase_unlink" 2
    exit 2
  fi

  echo "[WARNING] Unlinking from Supabase project"
  local cmd="supabase unlink"
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "supabase" "supabase_unlink" 0
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "supabase" "supabase_unlink" 1
    return 1
  fi
}

# Main dispatcher
FUNCTION="${ARGS[0]:-}"
if [[ -z "$FUNCTION" ]]; then
  echo "Usage: supabase.sh <function> [args...]" >&2
  echo "Functions: supabase_status, supabase_projects, supabase_link, supabase_db_diff," >&2
  echo "           supabase_db_migrate, supabase_db_reset, supabase_functions_deploy, supabase_unlink" >&2
  exit 1
fi

case "$FUNCTION" in
  supabase_status)
    supabase_status
    ;;
  supabase_projects)
    supabase_projects
    ;;
  supabase_link)
    supabase_link "${ARGS[@]:1}"
    ;;
  supabase_db_diff)
    supabase_db_diff
    ;;
  supabase_db_migrate)
    supabase_db_migrate
    ;;
  supabase_db_reset)
    supabase_db_reset
    ;;
  supabase_functions_deploy)
    supabase_functions_deploy "${ARGS[@]:1}"
    ;;
  supabase_unlink)
    supabase_unlink
    ;;
  *)
    echo "[ERROR] Unknown function: $FUNCTION" >&2
    exit 1
    ;;
esac
