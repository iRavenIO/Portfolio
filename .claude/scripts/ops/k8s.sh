#!/usr/bin/env bash
set -euo pipefail

# Kubernetes Operations Wrapper
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

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
  echo "[ERROR] kubectl not found. Please install kubectl." >&2
  exit 5
fi

# k8s_get: Get a specific Kubernetes resource (READ tier)
k8s_get() {
  local resource=$1
  local name=$2
  local namespace=""

  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace=*)
        namespace="${1#*=}"
        shift
        ;;
      *)
        echo "[ERROR] k8s_get: Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  if [[ -z "$namespace" ]]; then
    echo "[ERROR] k8s_get: --namespace is required" >&2
    audit_log "kubectl" "k8s_get" 3 "$resource" "$name"
    exit 3
  fi

  local cmd="kubectl get $resource $name --namespace=$namespace -o yaml"
  local output

  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "kubectl" "k8s_get" 0 "$resource" "$name" "--namespace=$namespace"
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "kubectl" "k8s_get" 1 "$resource" "$name" "--namespace=$namespace"
    return 1
  fi
}

# k8s_list: List Kubernetes resources (READ tier)
k8s_list() {
  local resource=$1
  local namespace=""
  local selector=""

  shift
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
        echo "[ERROR] k8s_list: Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  if [[ -z "$namespace" ]]; then
    echo "[ERROR] k8s_list: --namespace is required" >&2
    audit_log "kubectl" "k8s_list" 3 "$resource"
    exit 3
  fi

  local cmd="kubectl get $resource --namespace=$namespace"
  [[ -n "$selector" ]] && cmd="$cmd --selector=$selector"

  local output
  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "kubectl" "k8s_list" 0 "$resource" "--namespace=$namespace" ${selector:+"--selector=$selector"}
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "kubectl" "k8s_list" 1 "$resource" "--namespace=$namespace" ${selector:+"--selector=$selector"}
    return 1
  fi
}

# k8s_apply: Apply a Kubernetes manifest (WRITE tier)
k8s_apply() {
  local file=$1
  local namespace=""

  shift
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace=*)
        namespace="${1#*=}"
        shift
        ;;
      *)
        echo "[ERROR] k8s_apply: Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  if [[ ! -f "$file" ]]; then
    echo "[ERROR] k8s_apply: File not found: $file" >&2
    audit_log "kubectl" "k8s_apply" 1 "$file"
    exit 1
  fi

  local cmd="kubectl apply -f $file"
  [[ -n "$namespace" ]] && cmd="$cmd --namespace=$namespace"

  if [[ "$DRY_RUN" == "true" ]]; then
    cmd="$cmd --dry-run=client"
    echo "[DRY RUN] Would apply: $file"
    if [[ -n "$namespace" ]]; then
      echo "[DRY RUN] Namespace: $namespace"
    fi
  fi

  if [[ "$DRY_RUN" == "false" && "$CONFIRMED" == "false" ]]; then
    echo "[ERROR] k8s_apply: Missing required flag --confirm for mutating operation" >&2
    echo "[ERROR] Use: k8s.sh k8s_apply $file --confirm" >&2
    audit_log "kubectl" "k8s_apply" 2 "$file" ${namespace:+"--namespace=$namespace"}
    exit 2
  fi

  local output
  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "kubectl" "k8s_apply" 0 "$file" ${namespace:+"--namespace=$namespace"}
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "kubectl" "k8s_apply" 1 "$file" ${namespace:+"--namespace=$namespace"}
    return 1
  fi
}

# k8s_delete: Delete a Kubernetes resource (INFRASTRUCTURE tier)
k8s_delete() {
  local resource=$1
  local name=$2
  local namespace=""

  shift 2
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace=*)
        namespace="${1#*=}"
        shift
        ;;
      *)
        echo "[ERROR] k8s_delete: Unknown argument: $1" >&2
        exit 1
        ;;
    esac
  done

  if [[ -z "$namespace" ]]; then
    echo "[ERROR] k8s_delete: --namespace is required" >&2
    audit_log "kubectl" "k8s_delete" 3 "$resource" "$name"
    exit 3
  fi

  if [[ "$CONFIRMED" == "false" || "$FORCED" == "false" ]]; then
    echo "[ERROR] k8s_delete: INFRASTRUCTURE tier operation requires --confirm --force" >&2
    echo "[ERROR] Use: k8s.sh k8s_delete $resource $name --namespace=$namespace --confirm --force" >&2
    audit_log "kubectl" "k8s_delete" 2 "$resource" "$name" "--namespace=$namespace"
    exit 2
  fi

  echo "[WARNING] Deleting $resource/$name in namespace $namespace..."
  local cmd="kubectl delete $resource $name --namespace=$namespace"

  local output
  if output=$(eval "$cmd" 2>&1); then
    echo "$output" | redact_stream
    audit_log "kubectl" "k8s_delete" 0 "$resource" "$name" "--namespace=$namespace"
    return 0
  else
    echo "$output" | redact_stream >&2
    audit_log "kubectl" "k8s_delete" 1 "$resource" "$name" "--namespace=$namespace"
    return 1
  fi
}

# Main dispatcher
FUNCTION="${ARGS[0]:-}"
if [[ -z "$FUNCTION" ]]; then
  echo "Usage: k8s.sh <function> [args...]" >&2
  echo "Functions: k8s_get, k8s_list, k8s_apply, k8s_delete" >&2
  exit 1
fi

case "$FUNCTION" in
  k8s_get)
    k8s_get "${ARGS[@]:1}"
    ;;
  k8s_list)
    k8s_list "${ARGS[@]:1}"
    ;;
  k8s_apply)
    k8s_apply "${ARGS[@]:1}"
    ;;
  k8s_delete)
    k8s_delete "${ARGS[@]:1}"
    ;;
  *)
    echo "[ERROR] Unknown function: $FUNCTION" >&2
    exit 1
    ;;
esac
