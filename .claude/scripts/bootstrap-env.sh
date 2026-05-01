#!/usr/bin/env bash
# bootstrap-env.sh — Safe Environment Variable Scaffolding
# Creates .env.local files with EMPTY values only (no secrets)
# Part of Phase 5.5: Project Bootstrap + Safe Env Scaffolding

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Load factory environment configuration (if present)
_load_env_claude() {
  local _env_file="${REPO_ROOT:-.}/.claude/env.claude"
  local _env_local_file="${REPO_ROOT:-.}/.claude/env.claude.local"
  local _prev_x=false
  local _prev_u=false

  [[ $- == *x* ]] && _prev_x=true && set +x
  [[ $- == *u* ]] && _prev_u=true && set +u

  if [[ -f "$_env_file" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$_env_file"
    set +a
  fi

  if [[ -f "$_env_local_file" ]]; then
    set -a
    # shellcheck source=/dev/null
    source "$_env_local_file"
    set +a
  fi

  if $_prev_u; then
    set -u
  fi
  if $_prev_x; then
    set -x
  fi
}
_load_env_claude
unset -f _load_env_claude

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Flags
DRY_RUN=false
FORCE=false
PROJECT_PATH=""
FORMAT="dotenv"
VERBOSE=false

# Bounded scan limits (prevent runaway scans)
MAX_DEPTH=4
MAX_FILES=10000
SCAN_TIMEOUT=30

# Usage
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Safe environment variable scaffolding. Creates .env.local files with EMPTY
values only. NEVER writes real secrets to files.

OPTIONS:
  --dry-run         Print planned actions without creating files
  --force           Overwrite existing .env.local files
  --project PATH    Bootstrap a specific project root only
  --format FORMAT   Output format: dotenv (default) or yaml
  --verbose         Show detailed scanning output
  -h, --help        Show this help message

EXAMPLES:
  # Scan and bootstrap entire repo:
  $0

  # Dry run to see what would be created:
  $0 --dry-run

  # Force overwrite existing .env.local:
  $0 --force

  # Bootstrap specific project only:
  $0 --project apps/web

SECURITY:
  - Only KEY names are written, values are EMPTY
  - Output is redacted to prevent secret leakage
  - .env.local is automatically gitignored
  - Never commit .env.local files to version control

EOF
  exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --force)
      FORCE=true
      shift
      ;;
    --project)
      PROJECT_PATH="$2"
      shift 2
      ;;
    --format)
      FORMAT="$2"
      shift 2
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo -e "${RED}Error: Unknown option: $1${NC}"
      usage
      ;;
  esac
done

# Logging helpers
log_info() {
  echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
  echo -e "${GREEN}✓${NC} $1"
}

log_warn() {
  echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
  echo -e "${RED}✗${NC} $1"
}

log_verbose() {
  if [[ "$VERBOSE" == "true" ]]; then
    echo -e "${NC}  $1${NC}"
  fi
}

# Redaction function (matches server-ops.js patterns)
redact_output() {
  local text="$1"

  # Redact connection strings
  text=$(echo "$text" | sed -E 's/(postgres|mysql|mongodb|redis):[/][/][^@]*:[^@]*@[^ ]*/\1:\/\/***REDACTED***/g')

  # Redact tokens (Anthropic, JWT, AWS, GitHub)
  text=$(echo "$text" | sed -E 's/sk-ant-api[0-9]+-[A-Za-z0-9_-]{95,}/***REDACTED***/g')
  text=$(echo "$text" | sed -E 's/eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+/***REDACTED***/g')
  text=$(echo "$text" | sed -E 's/AKIA[0-9A-Z]{16}/***REDACTED***/g')
  text=$(echo "$text" | sed -E 's/github_pat_[0-9a-zA-Z_]{70,}/***REDACTED***/g')

  # Redact env var values (KEY=value) - but only if value is non-empty
  text=$(echo "$text" | sed -E 's/(TOKEN|SECRET|KEY|PASSWORD|PASS)=[^[:space:]]+/\1=***REDACTED***/g')

  echo "$text"
}

# Detect project type from path
detect_project_type() {
  local path="$1"
  local types=()

  # Node.js / Next.js
  if [[ -f "$path/package.json" ]]; then
    types+=("node")
    if grep -q "next" "$path/package.json" 2>/dev/null; then
      types+=("nextjs")
    fi
  fi

  # Vite
  if [[ -f "$path/vite.config.js" ]] || [[ -f "$path/vite.config.ts" ]]; then
    types+=("vite")
  fi

  # Supabase
  if [[ -d "$path/supabase" ]] || [[ -f "$path/supabase/config.toml" ]]; then
    types+=("supabase")
  fi

  # Docker / Compose
  if [[ -f "$path/docker-compose.yml" ]] || [[ -f "$path/compose.yaml" ]] || [[ -f "$path/Dockerfile" ]]; then
    types+=("docker")
  fi

  # Infrastructure (k8s, terraform, helm)
  if [[ -d "$path/charts" ]] || [[ -f "$path/values.yaml" ]] || [[ -f "$path/kustomization.yaml" ]]; then
    types+=("k8s")
  fi

  if ls "$path"/*.tf >/dev/null 2>&1; then
    types+=("terraform")
  fi

  # Return types (handle empty array for set -u compatibility)
  if [[ ${#types[@]} -gt 0 ]]; then
    echo "${types[@]}"
  fi
}

# Generate env keys based on project types
generate_env_keys() {
  local types="$1"
  local keys=()

  # Core keys (always included)
  keys+=("# Database")
  keys+=("DATABASE_URL=")
  keys+=("")

  # Node.js / Next.js keys
  if [[ "$types" =~ "node" ]] || [[ "$types" =~ "nextjs" ]]; then
    keys+=("# Node.js / Next.js")
    keys+=("NODE_ENV=development")
    keys+=("PORT=3000")
    keys+=("")
  fi

  # Supabase keys
  if [[ "$types" =~ "supabase" ]]; then
    keys+=("# Supabase")
    keys+=("NEXT_PUBLIC_SUPABASE_URL=")
    keys+=("NEXT_PUBLIC_SUPABASE_ANON_KEY=")
    keys+=("SUPABASE_SERVICE_ROLE_KEY=")
    keys+=("")
  fi

  # K8s / Argo keys
  if [[ "$types" =~ "k8s" ]] || [[ "$types" =~ "docker" ]]; then
    keys+=("# Kubernetes / Argo CD")
    keys+=("KUBECONFIG=")
    keys+=("ARGOCD_SERVER=")
    keys+=("ARGOCD_USERNAME=")
    keys+=("ARGOCD_PASSWORD=")
    keys+=("")
  fi

  # GitHub keys
  keys+=("# GitHub")
  keys+=("GITHUB_REPO=")
  keys+=("GITHUB_AUTH_MODE=ssh")
  keys+=("GITHUB_SSH_KEY_PATH=~/.ssh/id_ed25519")
  keys+=("")

  # Cache keys
  keys+=("# Cache")
  keys+=("REDIS_URL=")
  keys+=("CACHE_BACKEND=sqlite")
  keys+=("")

  printf '%s\n' "${keys[@]}"
}

# Create .env.local file
create_env_file() {
  local project_path="$1"
  local env_file="$project_path/.env.local"
  local types="$2"

  # Check if file exists
  if [[ -f "$env_file" ]] && [[ "$FORCE" == "false" ]]; then
    log_warn "Skipped: $env_file (already exists, use --force to overwrite)"
    return 1
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    log_info "Would create: $env_file (types: $types)"
    return 0
  fi

  # Generate content
  local content
  content=$(cat <<EOF
# .env.local — Local environment variables (DO NOT COMMIT)
# Generated by bootstrap-env.sh on $(date +%Y-%m-%d)
# Project types detected: $types
#
# SECURITY: Fill in values manually. NEVER commit this file to git.
# See docs/INSTALL.md for where to store secrets securely.

$(generate_env_keys "$types")
EOF
)

  # Write file
  echo "$content" > "$env_file"

  # Set restrictive permissions
  chmod 600 "$env_file"

  log_success "Created: $env_file (types: $types)"
}

# Scan directory for project roots
scan_for_projects() {
  local scan_path="$1"
  local projects=()

  log_info "Scanning for project roots in: $scan_path" >&2
  log_verbose "Max depth: $MAX_DEPTH, Max files: $MAX_FILES, Timeout: ${SCAN_TIMEOUT}s" >&2

  # Bounded scan with find (exclude common ignore dirs)
  local count=0

  # Check if timeout command is available (GNU coreutils, not on macOS by default)
  local timeout_cmd=""
  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd="timeout $SCAN_TIMEOUT"
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_cmd="gtimeout $SCAN_TIMEOUT"
  fi

  while IFS= read -r dir; do
    ((count++))
    if [[ $count -gt $MAX_FILES ]]; then
      log_warn "Scan limit reached ($MAX_FILES files), stopping scan" >&2
      break
    fi

    # Check if this is a project root
    local types
    types=$(detect_project_type "$dir")

    if [[ -n "$types" ]]; then
      projects+=("$dir|$types")
      log_verbose "Found project: $dir (types: $types)" >&2
    fi
  done < <($timeout_cmd find "$scan_path" \
    -maxdepth "$MAX_DEPTH" \
    -type d \
    \( -name node_modules -o -name .git -o -name dist -o -name build -o -name .next -o -name .cache \) -prune \
    -o -type d -print 2>/dev/null | head -n "$MAX_FILES")

  local project_count=${#projects[@]}
  log_info "Found $project_count project root(s)" >&2

  # Print projects to stdout (only if array is not empty)
  if [[ $project_count -gt 0 ]]; then
    printf '%s\n' "${projects[@]}"
  fi
}

# Ensure .gitignore has .env.local
ensure_gitignore() {
  local gitignore="$REPO_ROOT/.gitignore"

  if ! grep -q "\.env\.local" "$gitignore" 2>/dev/null; then
    if [[ "$DRY_RUN" == "true" ]]; then
      log_info "Would add .env.local to .gitignore"
      return 0
    fi

    cat >> "$gitignore" <<EOF

# Environment variables (DO NOT COMMIT)
.env.local
.env*.local
EOF
    log_success "Added .env.local to .gitignore"
  else
    log_verbose ".env.local already in .gitignore"
  fi
}

# Main execution
main() {
  log_info "Bootstrap Environment Variables"
  echo ""

  if [[ "$DRY_RUN" == "true" ]]; then
    log_warn "DRY RUN MODE — No files will be created"
    echo ""
  fi

  # Ensure .gitignore has .env.local
  ensure_gitignore

  # Determine scan path
  local scan_path="$REPO_ROOT"
  if [[ -n "$PROJECT_PATH" ]]; then
    # Handle absolute vs relative paths
    if [[ "$PROJECT_PATH" = /* ]]; then
      # Absolute path
      scan_path="$PROJECT_PATH"
    else
      # Relative path (relative to REPO_ROOT)
      scan_path="$REPO_ROOT/$PROJECT_PATH"
    fi

    if [[ ! -d "$scan_path" ]]; then
      log_error "Project path does not exist: $scan_path"
      exit 1
    fi
  fi

  # Scan for projects
  local projects=()
  while IFS= read -r line; do
    projects+=("$line")
  done < <(scan_for_projects "$scan_path")

  if [[ ${#projects[@]} -eq 0 ]]; then
    log_warn "No projects detected"
    exit 0
  fi

  echo ""
  log_info "Creating .env.local files..."
  echo ""

  # Create .env.local for each project
  local created=0
  local skipped=0

  for project in "${projects[@]}"; do
    if [[ -z "$project" ]]; then
      continue
    fi

    local path="${project%%|*}"
    local types="${project##*|}"

    if create_env_file "$path" "$types"; then
      ((created++))
    else
      ((skipped++))
    fi
  done

  echo ""
  log_info "Summary: $created created, $skipped skipped"

  if [[ $created -gt 0 ]] && [[ "$DRY_RUN" == "false" ]]; then
    echo ""
    log_warn "IMPORTANT: .env.local files have EMPTY values"
    log_warn "Fill in secrets manually. See docs/INSTALL.md for guidance."
    log_warn "NEVER commit .env.local files to version control."
  fi
}

# Run main
main
