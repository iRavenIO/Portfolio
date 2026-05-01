#!/usr/bin/env bash
set -euo pipefail

# Argo CD Operations Wrapper
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

# Check if argocd is available
if ! command -v argocd &> /dev/null; then
  echo "[ERROR] argocd not found. Please install argocd CLI." >&2
  exit 5
fi

# argocd_app_get: Get Argo CD application details (READ tier)
argocd_app_get() {
  local app_name=$1

  if [[ -z "$app_name" ]]; then
    echo "[ERROR] argocd_app_get: Application name is required" >&2
    audit_log "argocd" "argocd_app_get" 1
    exit 1
  fi

  local cmd="argocd app get $app_name -o yaml"
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "argocd" "argocd_app_get" 0 "$app_name"
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "argocd" "argocd_app_get" 1 "$app_name"
    return 1
  fi
}

# argocd_app_list: List Argo CD applications (READ tier)
argocd_app_list() {
  local selector=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --selector=*)
        selector="${1#*=}"
        shift
        ;;
      *)
        echo "[ERROR] argocd_app_list: Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  local cmd="argocd app list"
  [[ -n "$selector" ]] && cmd="$cmd --selector=$selector"

  local output
  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "argocd" "argocd_app_list" 0 ${selector:+"--selector=$selector"}
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "argocd" "argocd_app_list" 1 ${selector:+"--selector=$selector"}
    return 1
  fi
}

# argocd_app_sync: Sync an Argo CD application (WRITE tier)
argocd_app_sync() {
  local app_name=$1

  if [[ -z "$app_name" ]]; then
    echo "[ERROR] argocd_app_sync: Application name is required" >&2
    audit_log "argocd" "argocd_app_sync" 1
    exit 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] Would sync application: $app_name"
    echo "[DRY RUN] Fetching diff..."
    local diff_cmd="argocd app diff $app_name"
    local output
    if output=$(eval "$diff_cmd" 2>&1); then
      echo "$output" | redact_stream
      audit_log "argocd" "argocd_app_sync" 0 "$app_name" "[dry-run]"
      return 0
    else
      echo "$output" | redact_stream >&2
      audit_log "argocd" "argocd_app_sync" 1 "$app_name" "[dry-run]"
      return 1
    fi
  fi

  if [[ "$CONFIRMED" == "false" ]]; then
    echo "[ERROR] argocd_app_sync: Missing required flag --confirm for mutating operation" >&2
    echo "[ERROR] Use: argocd.sh argocd_app_sync $app_name --confirm" >&2
    audit_log "argocd" "argocd_app_sync" 2 "$app_name"
    exit 2
  fi

  local cmd="argocd app sync $app_name"
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "argocd" "argocd_app_sync" 0 "$app_name"
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "argocd" "argocd_app_sync" 1 "$app_name"
    return 1
  fi
}

# argocd_app_delete: Delete an Argo CD application (INFRASTRUCTURE tier)
argocd_app_delete() {
  local app_name=$1

  if [[ -z "$app_name" ]]; then
    echo "[ERROR] argocd_app_delete: Application name is required" >&2
    audit_log "argocd" "argocd_app_delete" 1
    exit 1
  fi

  if [[ "$CONFIRMED" == "false" || "$FORCED" == "false" ]]; then
    echo "[ERROR] argocd_app_delete: INFRASTRUCTURE tier operation requires --confirm --force" >&2
    echo "[ERROR] Use: argocd.sh argocd_app_delete $app_name --confirm --force" >&2
    audit_log "argocd" "argocd_app_delete" 2 "$app_name"
    exit 2
  fi

  echo "[WARNING] Deleting Argo CD application: $app_name"
  local cmd="argocd app delete $app_name --yes"

  local output
  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "argocd" "argocd_app_delete" 0 "$app_name"
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "argocd" "argocd_app_delete" 1 "$app_name"
    return 1
  fi
}

# Main dispatcher
FUNCTION="${ARGS[0]:-}"
if [[ -z "$FUNCTION" ]]; then
  echo "Usage: argocd.sh <function> [args...]" >&2
  echo "Functions: argocd_app_get, argocd_app_list, argocd_app_sync, argocd_app_delete" >&2
  exit 1
fi

case "$FUNCTION" in
  argocd_app_get)
    argocd_app_get "${ARGS[@]:1}"
    ;;
  argocd_app_list)
    argocd_app_list "${ARGS[@]:1}"
    ;;
  argocd_app_sync)
    argocd_app_sync "${ARGS[@]:1}"
    ;;
  argocd_app_delete)
    argocd_app_delete "${ARGS[@]:1}"
    ;;
  *)
    echo "[ERROR] Unknown function: $FUNCTION" >&2
    exit 1
    ;;
esac
