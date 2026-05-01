#!/usr/bin/env zsh
# ╔═══════════════════════════════════════════════════════════════╗
# ║  Claude Factory — Zsh Helpers                                  ║
# ║  Installation, uninstallation, and runtime helpers             ║
# ╚═══════════════════════════════════════════════════════════════╝
#
# To use these helpers, source this file in your ~/.zshrc:
#   source /path/to/claude-factory/.zsh/claude-factory-helpers.zsh
#
# Or copy it to ~/.zshrc.d/ if you use that pattern:
#   cp .zsh/claude-factory-helpers.zsh ~/.zshrc.d/

# ─────────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────────

# Path to Claude Factory source repository
# Override by setting CLAUDE_FACTORY_SOURCE before sourcing this file
: "${CLAUDE_FACTORY_SOURCE:=$HOME/Sites/Local/Applications/Network/Claude}"

# ─────────────────────────────────────────────────────────────────
# cfactory — Install Claude Factory (FULL mode)
# ─────────────────────────────────────────────────────────────────
# Usage:
#   cfactory [target-dir]
#   cfactory /path/to/project
#
# Installs full Claude Factory with all features for Claude and OpenCode:
#   • All 7 MCP servers
#   • Multi-agent workflow pipeline
#   • Full policy documentation
#   • Health checks and validation
#   • Ctags indexing and cache subsystem
#
cfactory() {
  local target="${1:-.}"
  local source="$CLAUDE_FACTORY_SOURCE"

  if [[ ! -d "$source" ]]; then
    echo "❌ Factory source not found: $source"
    echo "Set CLAUDE_FACTORY_SOURCE or edit this file"
    return 1
  fi

  echo "🏭 Installing Claude Factory (FULL mode) for Claude and OpenCode..."
  echo "   Source: $source"
  echo "   Target: $target"
  echo ""

  # Create target directory if needed
  mkdir -p "$target"
  cd "$target" || return 1

  # Initialize git repo if not already
  if [[ ! -d .git ]]; then
    echo "→ Initializing git repository..."
    git init
  fi

  # Copy factory files (full mode)
  echo "→ Copying factory files..."
  rsync -av --exclude='.git' \
    --exclude='node_modules' \
    --exclude='.claude/cache/*' \
    --exclude='.claude/logs/*' \
    --exclude='.claude/memory/*' \
    --exclude='*.db' \
    --exclude='tags' \
    "$source/" ./

  if [[ -f ".opencode/project.template.yml" ]] && [[ ! -f ".opencode/project.yml" ]]; then
    cp .opencode/project.template.yml .opencode/project.yml
  fi
  if [[ -f ".opencode/overrides.template.md" ]] && [[ ! -f ".opencode/overrides.md" ]]; then
    cp .opencode/overrides.template.md .opencode/overrides.md
  fi
  if [[ -f ".claude/project-context.md.sample" ]] && [[ ! -f ".claude/project-context.md" ]]; then
    cp .claude/project-context.md.sample .claude/project-context.md
  fi

  [[ -f "CLAUDE.light.md" ]] && cp CLAUDE.light.md CLAUDE.md
  [[ -f "AGENTS.light.md" ]] && cp AGENTS.light.md AGENTS.md
  [[ -f "opencode.full.json" ]] && cp opencode.full.json opencode.json

  # Run install script (full mode)
  echo ""
  echo "→ Running install.sh --mode full..."
  ./install.sh --mode full

  echo ""
  echo "✅ Claude Factory (FULL) installed successfully"
  echo ""
  echo "Behavioral mode: LIGHT (default)"
  echo "  Switch to FULL workflow: cfmode full"
  echo ""
  echo "Next steps:"
  echo "  cd $target"
  echo "  claude    # Open in Claude Code"
  echo "  opencode  # Open in OpenCode"
}

# ─────────────────────────────────────────────────────────────────
# cfactorylite — Install Claude Factory (LITE mode)
# ─────────────────────────────────────────────────────────────────
# Usage:
#   cfactorylite [target-dir]
#   cfactorylite /path/to/project
#
# Installs lite Claude Factory with minimal features for Claude and OpenCode:
#   • 3 MCP servers (ops, git, fs)
#   • No workflow automation
#   • Minimal documentation
#   • No ctags/cache subsystem
#
cfactorylite() {
  local target="${1:-.}"
  local source="$CLAUDE_FACTORY_SOURCE"

  if [[ ! -d "$source" ]]; then
    echo "❌ Factory source not found: $source"
    echo "Set CLAUDE_FACTORY_SOURCE or edit this file"
    return 1
  fi

  echo "🏭 Installing Claude Factory (LITE mode)..."
  echo "   Source: $source"
  echo "   Target: $target"
  echo ""

  # Create target directory if needed
  mkdir -p "$target"
  cd "$target" || return 1

  # Initialize git repo if not already
  if [[ ! -d .git ]]; then
    echo "→ Initializing git repository..."
    git init
  fi

  # Copy only lite mode files
  echo "→ Copying lite mode files..."

  # Create directory structure
  mkdir -p .claude/mcp

  # Copy essential files
  rsync -av \
    --include='/.mcp.lite.json' \
    --include='/.claude/' \
    --include='/.claude/mcp/***' \
    --include='/.claude/env.claude.sample' \
    --include='/.claude/project-context.md.sample' \
    --include='/.opencode/***' \
    --include='/install.sh' \
    --include='/scripts/install-opencode.sh' \
    --include='/cf-lite' \
    --include='/CLAUDE.md' \
    --include='/CLAUDE.light.md' \
    --include='/AGENTS.md' \
    --include='/AGENTS.light.md' \
    --include='/opencode.json' \
    --include='/opencode.lite.json' \
    --include='/CLAUDE_LITE.md' \
    --include='/docs/' \
    --include='/docs/opencode/***' \
    --include='/docs/policy/' \
    --include='/docs/policy/mcp-security.md' \
    --include='/docs/policy/secrets-and-env.md' \
    --include='/docs/policy/ops-tools.md' \
    --include='/docs/MVP_OPERATIONS_REFERENCE.md' \
    --include='/.gitignore' \
    --exclude='*' \
    "$source/" ./

  if [[ -f ".opencode/project.template.yml" ]] && [[ ! -f ".opencode/project.yml" ]]; then
    cp .opencode/project.template.yml .opencode/project.yml
  fi
  if [[ -f ".opencode/overrides.template.md" ]] && [[ ! -f ".opencode/overrides.md" ]]; then
    cp .opencode/overrides.template.md .opencode/overrides.md
  fi
  if [[ -f ".claude/project-context.md.sample" ]] && [[ ! -f ".claude/project-context.md" ]]; then
    cp .claude/project-context.md.sample .claude/project-context.md
  fi

  # Exclude heavy directories from .claude/mcp
  rm -rf .claude/mcp/node_modules 2>/dev/null || true

  # Run install script (lite mode - installs all files but sets LIGHT behavioral mode)
  echo ""
  echo "→ Running install.sh --mode lite..."
  ./install.sh --mode lite

  # Ensure LIGHT behavioral profile is active (already default, but be explicit)
  if [[ -f "CLAUDE.light.md" ]]; then
    cp CLAUDE.light.md CLAUDE.md
    echo "[ok] Behavioral mode set to LIGHT"
  fi
  if [[ -f "AGENTS.light.md" ]]; then
    cp AGENTS.light.md AGENTS.md
    echo "[ok] OpenCode profile set to LIGHT"
  fi
  if [[ -f "opencode.lite.json" ]]; then
    cp opencode.lite.json opencode.json
    echo "[ok] OpenCode MCP config set to lite"
  fi

  echo ""
  echo "✅ Claude Factory (LITE) installed successfully"
  echo ""
  echo "Behavioral mode: LIGHT (single-pass)"
  echo "  Switch to FULL workflow: cfmode full"
  echo ""
  echo "Next steps:"
  echo "  cd $target"
  echo "  ./cf-lite   # Run Claude in lite mode"
  echo "  opencode    # Run OpenCode with opencode.json"
}

# ─────────────────────────────────────────────────────────────────
# cunfactory — Uninstall Claude Factory
# ─────────────────────────────────────────────────────────────────
# Usage:
#   cunfactory [target-dir]              # Dry-run (preview)
#   cunfactory --apply [target-dir]      # Apply removal
#   cunfactory --apply --force [target]  # Force removal (no confirm)
#
# Safely removes Claude Factory installation.
# Default: dry-run mode (preview only)
# Use --apply to actually remove files
#
cunfactory() {
  local apply=0
  local force=0
  local target="."

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --apply)
        apply=1
        shift
        ;;
      --force)
        force=1
        shift
        ;;
      -*)
        echo "❌ Unknown option: $1" >&2
        echo "Usage: cunfactory [--apply] [--force] [target-dir]" >&2
        return 1
        ;;
      *)
        target="$1"
        shift
        ;;
    esac
  done

  cd "$target" || return 1

  # Detect installation mode
  local mode="unknown"
  if [[ -f ".mcp.json" ]] && [[ -d "docs/policy" ]]; then
    mode="full"
  elif [[ -f ".mcp.lite.json" ]]; then
    mode="lite"
  else
    echo "❌ No Claude Factory installation detected in: $PWD"
    return 1
  fi

  echo "🗑️  Claude Factory Uninstall (mode: $mode)"
  echo "   Target: $PWD"
  echo ""

  # Define files to remove based on mode
  local files_to_remove=()

  if [[ "$mode" == "full" ]]; then
    files_to_remove=(
      ".mcp.json"
      ".claude/"
      "CLAUDE.md"
      "AGENTS.md"
      "AGENTS.light.md"
      "AGENTS.full.md"
      "opencode.json"
      "opencode.full.json"
      "opencode.lite.json"
      "cf"
      "install.sh"
      "docs/policy/"
      "docs/tasks/"
      "docs/TROUBLESHOOTING.md"
      "docs/MVP_OPERATIONS_REFERENCE.md"
      "tags"
    )
  else
    files_to_remove=(
      ".mcp.lite.json"
      ".claude/"
      "CLAUDE_LITE.md"
      "AGENTS.md"
      "AGENTS.light.md"
      "opencode.json"
      "opencode.lite.json"
      "cf-lite"
      "install.sh"
      "docs/policy/mcp-security.md"
      "docs/policy/secrets-and-env.md"
      "docs/policy/ops-tools.md"
      "docs/MVP_OPERATIONS_REFERENCE.md"
    )
  fi

  # Show what will be removed
  echo "Files to remove:"
  local found_count=0
  local missing_count=0
  for file in "${files_to_remove[@]}"; do
    if [[ -e "$file" ]]; then
      echo "  [x] $file"
      ((found_count++))
    else
      echo "  [ ] $file (not found)"
      ((missing_count++))
    fi
  done
  echo ""
  echo "Summary: $found_count files found, $missing_count already removed"
  echo ""

  # Check for local env files (never remove these)
  local env_files=(
    ".claude/env.claude"
    ".claude/env.claude.local"
    ".env.local"
  )
  local has_env=0
  for env_file in "${env_files[@]}"; do
    if [[ -f "$env_file" ]]; then
      has_env=1
      echo "⚠️  Local env file detected: $env_file (will NOT be removed)"
    fi
  done
  [[ $has_env -eq 1 ]] && echo ""

  # Dry-run mode
  if [[ $apply -eq 0 ]]; then
    echo "🔍 DRY-RUN MODE (no files removed)"
    echo "   To apply removal, run: cunfactory --apply"
    return 0
  fi

  # Confirm before removal (unless --force)
  if [[ $force -eq 0 ]]; then
    echo -n "⚠️  Remove $found_count files? [y/N] "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
      echo "❌ Aborted"
      return 1
    fi
  fi

  # Remove files
  echo "→ Removing factory files..."
  local removed=0
  for file in "${files_to_remove[@]}"; do
    if [[ -e "$file" ]]; then
      rm -rf "$file" && ((removed++)) || echo "⚠️  Failed to remove: $file"
    fi
  done

  echo ""
  echo "✅ Removed $removed files"

  if [[ $has_env -eq 1 ]]; then
    echo ""
    echo "📝 Note: Local env files were preserved"
    echo "   Remove manually if needed (they contain your configuration)"
  fi
}

# ─────────────────────────────────────────────────────────────────
# cfmode — Switch behavioral profile (LIGHT ↔ FULL)
# ─────────────────────────────────────────────────────────────────
# Usage:
#   cfmode light       # Single-pass, token-efficient (default)
#   cfmode full        # Multi-phase workflow orchestration
#   cfmode status      # Show current mode
#
# Switches CLAUDE.md and AGENTS.md between LIGHT and FULL behavioral profiles.
# This is a repo-level switch (does not reinstall anything).
#
cfmode() {
  local mode="${1:-status}"
  local target="${2:-.}"

  cd "$target" || return 1

  case "$mode" in
    light)
      if [[ ! -f "CLAUDE.light.md" ]]; then
        echo "❌ CLAUDE.light.md not found in: $PWD"
        echo "This repo may not have behavioral profiles installed."
        return 1
      fi

      cp CLAUDE.light.md CLAUDE.md
      [[ -f "AGENTS.light.md" ]] && cp AGENTS.light.md AGENTS.md
      echo "✅ Switched to LIGHT mode (single-pass)"
      echo "   Profile: CLAUDE.light.md → CLAUDE.md"
      if [[ -f "AGENTS.light.md" ]]; then
        echo "   Profile: AGENTS.light.md → AGENTS.md"
      fi
      echo ""
      echo "LIGHT mode behavior:"
      echo "  • Single-pass execution"
      echo "  • Token-efficient"
      echo "  • No multi-agent orchestration by default"
      echo "  • Brief plans and concise summaries"
      ;;

    full)
      if [[ ! -f "CLAUDE.full.md" ]]; then
        echo "❌ CLAUDE.full.md not found in: $PWD"
        echo "This repo may not have behavioral profiles installed."
        return 1
      fi

      cp CLAUDE.full.md CLAUDE.md
      [[ -f "AGENTS.full.md" ]] && cp AGENTS.full.md AGENTS.md
      echo "✅ Switched to FULL mode (multi-phase)"
      echo "   Profile: CLAUDE.full.md → CLAUDE.md"
      if [[ -f "AGENTS.full.md" ]]; then
        echo "   Profile: AGENTS.full.md → AGENTS.md"
      fi
      echo ""
      echo "FULL mode behavior:"
      echo "  • Multi-phase workflow pipeline"
      echo "  • Complete agent orchestration"
      echo "  • Detailed execution plans and reports"
      echo "  • Voice notifications"
      ;;

    status)
      if [[ ! -f "CLAUDE.md" ]]; then
        echo "❌ CLAUDE.md not found in: $PWD"
        return 1
      fi

      local claude_header=$(head -1 CLAUDE.md)
      local claude_mode="unknown"
      local agents_mode="missing"

      if echo "$claude_header" | grep -qi "LIGHT MODE"; then
        claude_mode="LIGHT"
      elif echo "$claude_header" | grep -qi "MULTI-AGENT\|AUTONOMOUS.*FACTORY"; then
        claude_mode="FULL"
      fi

      echo "Claude mode:   $claude_mode"

      if [[ -f "AGENTS.md" ]]; then
        local agents_header=$(head -1 AGENTS.md)
        if echo "$agents_header" | grep -qi "LIGHT MODE"; then
          agents_mode="LIGHT"
        elif echo "$agents_header" | grep -qi "FULL MODE"; then
          agents_mode="FULL"
        else
          agents_mode="unknown"
        fi
        echo "OpenCode mode: $agents_mode"
      else
        echo "OpenCode mode: missing"
      fi

      if [[ "$claude_mode" != "unknown" ]] && [[ "$agents_mode" != "missing" ]] && [[ "$claude_mode" != "$agents_mode" ]]; then
        echo ""
        echo "⚠ Profiles are out of sync between Claude and OpenCode"
      fi

      echo ""
      echo "Switch modes:"
      echo "  cfmode light   # Single-pass, token-efficient"
      echo "  cfmode full    # Multi-phase workflow"
      ;;

    *)
      echo "❌ Unknown mode: $mode"
      echo ""
      echo "Usage: cfmode light|full|status [target-dir]"
      return 1
      ;;
  esac
}

# ─────────────────────────────────────────────────────────────────
# Show available commands on load
# ─────────────────────────────────────────────────────────────────
if [[ "${ZSH_EVAL_CONTEXT:-}" == "file" ]]; then
  # Only show on initial load, not on nested source
  echo "✅ Claude Factory helpers loaded"
  echo "   Commands: cfactory, cfactorylite, cunfactory, cfmode"
  echo "   Source:   $CLAUDE_FACTORY_SOURCE"
fi
