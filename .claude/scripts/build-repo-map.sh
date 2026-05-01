#!/usr/bin/env bash
# build-repo-map.sh — Generate repository structure map
# Called by cache.sh's build_repo_map function

set -euo pipefail

CLAUDE_ROOT="${CLAUDE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"

# ============================================================================
# CONFIGURATION
# ============================================================================

TREE_DEPTH="${TREE_DEPTH:-3}"
MAX_FILES="${MAX_FILES:-10000}"
IGNORE_PATTERNS="node_modules|.git|.next|dist|build|*.pyc|__pycache__|coverage|.cache"

# ============================================================================
# HELPER FUNCTIONS
# ============================================================================

count_files() {
  find "$CLAUDE_ROOT" -type f 2>/dev/null | wc -l | tr -d ' '
}

count_tracked_files() {
  if git -C "$CLAUDE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$CLAUDE_ROOT" ls-files | wc -l | tr -d ' '
  else
    echo "0"
  fi
}

is_git_repo() {
  if git -C "$CLAUDE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "yes"
  else
    echo "no"
  fi
}

# ============================================================================
# TREE GENERATION
# ============================================================================

generate_tree() {
  # Use tree if available, otherwise fallback to find
  if command -v tree >/dev/null 2>&1; then
    tree -L "$TREE_DEPTH" -I "$IGNORE_PATTERNS" --noreport --dirsfirst "$CLAUDE_ROOT" 2>/dev/null
  else
    # Fallback: use find with depth limit
    find "$CLAUDE_ROOT" -maxdepth "$TREE_DEPTH" -type d ! -path "*/.git/*" ! -path "*/node_modules/*" 2>/dev/null | \
      sort | \
      awk -v root="$CLAUDE_ROOT" '{
        depth = gsub("/", "/", substr($0, length(root)+2));
        indent = "";
        for (i=0; i<depth; i++) indent = indent "  ";
        name = substr($0, length(root)+2);
        if (name == "") name = ".";
        print indent name "/"
      }' | head -100
  fi
}

generate_key_directories() {
  echo ""
  echo "Key directories:"

  # Policies
  local policy_count=$(ls "$CLAUDE_ROOT"/docs/policy/*.md 2>/dev/null | wc -l | tr -d ' ')
  echo "  Policies:  docs/policy/*.md ($policy_count files)"

  # Runbooks
  local runbook_count=$(ls "$CLAUDE_ROOT"/.claude/runbooks/*.md 2>/dev/null | wc -l | tr -d ' ')
  echo "  Runbooks:  .claude/runbooks/*.md ($runbook_count files)"

  # Agents
  local agent_count=$(ls "$CLAUDE_ROOT"/.claude/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
  echo "  Agents:    .claude/agents/*.md ($agent_count files)"

  # Scripts
  local script_count=$(ls "$CLAUDE_ROOT"/.claude/scripts/*.sh 2>/dev/null | wc -l | tr -d ' ')
  echo "  Scripts:   .claude/scripts/*.sh ($script_count files)"

  # MCP Servers
  local mcp_count=$(ls "$CLAUDE_ROOT"/.claude/mcp/server*.js 2>/dev/null | wc -l | tr -d ' ')
  echo "  MCP:       .claude/mcp/server*.js ($mcp_count files)"
}

generate_file_type_summary() {
  echo ""
  echo "File types (tracked files only):"

  if git -C "$CLAUDE_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$CLAUDE_ROOT" ls-files | \
      awk -F. '{if (NF>1) print $NF}' | \
      sort | uniq -c | sort -rn | head -10 | \
      awk '{printf "  %-8s %s files\n", "."$2, $1}'
  else
    echo "  (not a git repository)"
  fi
}

# ============================================================================
# MAIN
# ============================================================================

main() {
  local timestamp=$(date -u +"%Y-%m-%d %H:%M:%S")
  local total_files=$(count_files)
  local tracked_files=$(count_tracked_files)
  local git_repo=$(is_git_repo)

  # Header
  echo "REPOSITORY MAP (generated $timestamp)"
  echo "Total files: $total_files | Tracked files: $tracked_files | Git repo: $git_repo"
  echo ""

  # Safety check: skip tree for huge repos
  if [[ "$total_files" -gt "$MAX_FILES" ]]; then
    echo "Repository is very large ($total_files files) — skipping detailed tree."
    echo "Use 'find' or 'tree' commands manually to explore."
    generate_key_directories
    generate_file_type_summary
    return 0
  fi

  # Generate tree
  generate_tree

  # Key directories
  generate_key_directories

  # File type summary
  generate_file_type_summary
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main
fi
