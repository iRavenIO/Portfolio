#!/usr/bin/env bash
set -euo pipefail

# Argo Workflows Operations Wrapper
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

# Check if argo is available
if ! command -v argo &> /dev/null; then
  echo "[ERROR] argo not found. Please install argo workflows CLI." >&2
  exit 5
fi

# argo_get: Get workflow details (READ tier)
argo_get() {
  local workflow_name=$1
  local namespace="argo"

  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace=*)
        namespace="${1#*=}"
        shift
        ;;
      *)
        echo "[ERROR] argo_get: Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  if [[ -z "$workflow_name" ]]; then
    echo "[ERROR] argo_get: Workflow name is required" >&2
    audit_log "argo" "argo_get" 1
    exit 1
  fi

  local cmd="argo get $workflow_name --namespace=$namespace -o yaml"
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "argo" "argo_get" 0 "$workflow_name" "--namespace=$namespace"
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "argo" "argo_get" 1 "$workflow_name" "--namespace=$namespace"
    return 1
  fi
}

# argo_list: List workflows (READ tier)
argo_list() {
  local namespace="argo"
  local selector=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace=*)
        namespace="${1#*=}"
        shift
        ;;
      --selector=*)
        selector="${1#*=}"
        shift
        ;;
      *)
        echo "[ERROR] argo_list: Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  local cmd="argo list --namespace=$namespace"
  [[ -n "$selector" ]] && cmd="$cmd --selector=$selector"

  local output
  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "argo" "argo_list" 0 "--namespace=$namespace" ${selector:+"--selector=$selector"}
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "argo" "argo_list" 1 "--namespace=$namespace" ${selector:+"--selector=$selector"}
    return 1
  fi
}

# argo_logs: Get workflow logs (READ tier)
argo_logs() {
  local workflow_name=$1
  local namespace="argo"

  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace=*)
        namespace="${1#*=}"
        shift
        ;;
      *)
        echo "[ERROR] argo_logs: Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  if [[ -z "$workflow_name" ]]; then
    echo "[ERROR] argo_logs: Workflow name is required" >&2
    audit_log "argo" "argo_logs" 1
    exit 1
  fi

  local cmd="argo logs $workflow_name --namespace=$namespace"
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "argo" "argo_logs" 0 "$workflow_name" "--namespace=$namespace"
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "argo" "argo_logs" 1 "$workflow_name" "--namespace=$namespace"
    return 1
  fi
}

# argo_submit: Submit a workflow (WRITE tier)
argo_submit() {
  local workflow_file=$1
  local namespace="argo"

  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace=*)
        namespace="${1#*=}"
        shift
        ;;
      *)
        echo "[ERROR] argo_submit: Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  if [[ ! -f "$workflow_file" ]]; then
    echo "[ERROR] argo_submit: File not found: $workflow_file" >&2
    audit_log "argo" "argo_submit" 1 "$workflow_file"
    exit 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[DRY RUN] Would submit workflow: $workflow_file"
    echo "[DRY RUN] Validating..."
    local cmd="argo lint $workflow_file --namespace=$namespace"
    local output
    if output=$(eval "$cmd" 2>&1); then
      echo "$output" | redact_stream
      audit_log "argo" "argo_submit" 0 "$workflow_file" "--namespace=$namespace" "[dry-run]"
      return 0
    else
      echo "$output" | redact_stream >&2
      audit_log "argo" "argo_submit" 4 "$workflow_file" "--namespace=$namespace" "[dry-run]"
      return 1
    fi
  fi

  if [[ "$CONFIRMED" == "false" ]]; then
    echo "[ERROR] argo_submit: Missing required flag --confirm for mutating operation" >&2
    echo "[ERROR] Use: argo-workflows.sh argo_submit $workflow_file --confirm" >&2
    audit_log "argo" "argo_submit" 2 "$workflow_file" "--namespace=$namespace"
    exit 2
  fi

  local cmd="argo submit $workflow_file --namespace=$namespace"
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "argo" "argo_submit" 0 "$workflow_file" "--namespace=$namespace"
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "argo" "argo_submit" 1 "$workflow_file" "--namespace=$namespace"
    return 1
  fi
}

# argo_delete: Delete a workflow (INFRASTRUCTURE tier)
argo_delete() {
  local workflow_name=$1
  local namespace="argo"

  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace=*)
        namespace="${1#*=}"
        shift
        ;;
      *)
        echo "[ERROR] argo_delete: Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  if [[ -z "$workflow_name" ]]; then
    echo "[ERROR] argo_delete: Workflow name is required" >&2
    audit_log "argo" "argo_delete" 1
    exit 1
  fi

  if [[ "$CONFIRMED" == "false" || "$FORCED" == "false" ]]; then
    echo "[ERROR] argo_delete: INFRASTRUCTURE tier operation requires --confirm --force" >&2
    echo "[ERROR] Use: argo-workflows.sh argo_delete $workflow_name --confirm --force" >&2
    audit_log "argo" "argo_delete" 2 "$workflow_name" "--namespace=$namespace"
    exit 2
  fi

  echo "[WARNING] Deleting workflow: $workflow_name"
  local cmd="argo delete $workflow_name --namespace=$namespace"

  local output
  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "argo" "argo_delete" 0 "$workflow_name" "--namespace=$namespace"
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "argo" "argo_delete" 1 "$workflow_name" "--namespace=$namespace"
    return 1
  fi
}

# Main dispatcher
FUNCTION="${ARGS[0]:-}"
if [[ -z "$FUNCTION" ]]; then
  echo "Usage: argo-workflows.sh <function> [args...]" >&2
  echo "Functions: argo_get, argo_list, argo_logs, argo_submit, argo_delete" >&2
  exit 1
fi

case "$FUNCTION" in
  argo_get)
    argo_get "${ARGS[@]:1}"
    ;;
  argo_list)
    argo_list "${ARGS[@]:1}"
    ;;
  argo_logs)
    argo_logs "${ARGS[@]:1}"
    ;;
  argo_submit)
    argo_submit "${ARGS[@]:1}"
    ;;
  argo_delete)
    argo_delete "${ARGS[@]:1}"
    ;;
  *)
    echo "[ERROR] Unknown function: $FUNCTION" >&2
    exit 1
    ;;
esac
