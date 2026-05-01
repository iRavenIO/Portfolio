#!/usr/bin/env bash
set -Eeuo pipefail

# ╔═══════════════════════════════════════════════════════════════╗
# ║  🧩 Claude Factory — install.sh                               ║
# ║  Safe bootstrap for Phase 2 (policies, validation, tooling)    ║
# ║  Supports: --mode full (default) | --mode lite                 ║
# ╚═══════════════════════════════════════════════════════════════╝

# Detect repository root with robust fallback chain:
#   1. git rev-parse --show-toplevel (works for normal repos, worktrees, submodules)
#   2. Walk from script location (fallback when git is unavailable)
detect_repo_root() {
  # Method 1: Ask git (handles worktrees, submodules, symlinks)
  if command -v git >/dev/null 2>&1; then
    local git_root
    git_root="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null)" && {
      printf '%s' "$git_root"
      return 0
    }
  fi

  # Method 2: Resolve from script's own location (pre-git fallback)
  (cd "$(dirname "$0")" && pwd -P)
}

REPO_ROOT="$(detect_repo_root)"

# -----------------------------
# Parse arguments
# -----------------------------
INSTALL_MODE="full"  # full | lite

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      INSTALL_MODE="$2"
      shift 2
      ;;
    --mode=*)
      INSTALL_MODE="${1#*=}"
      shift
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--mode full|lite]" >&2
      exit 1
      ;;
  esac
done

# Validate mode
if [[ "$INSTALL_MODE" != "full" && "$INSTALL_MODE" != "lite" ]]; then
  echo "❌ Invalid mode: $INSTALL_MODE (must be 'full' or 'lite')" >&2
  exit 1
fi

# -----------------------------
# Config (override via env)
# -----------------------------
: "${CLAUDE_FACTORY_SKIP_DEPS:=0}"          # 1 = don't install deps, only verify presence
: "${CLAUDE_FACTORY_NOTIFY:=1}"             # 0 = disable any voice/notify steps (if present)
: "${CLAUDE_FACTORY_CTAGS_MODE:=smart}"     # smart | always | off  (Phase 2.3+)
: "${CLAUDE_FACTORY_TAGS_OUT:=tags}"
: "${CLAUDE_FACTORY_LOGS_DIR:=.claude/logs}"
: "${CLAUDE_FACTORY_MCP_DIR:=.claude/mcp}"
: "${CLAUDE_FACTORY_INDEX_STATE:=.claude/index-state.json}"
: "${CLAUDE_FACTORY_MAX_TAG_FILES:=200000}" # safety cap

# Lite mode overrides
if [[ "$INSTALL_MODE" == "lite" ]]; then
  CLAUDE_FACTORY_CTAGS_MODE="off"  # No ctags in lite mode
fi

CTAGS_BIN=""

say()  { printf "%s\n" "$*"; }
warn() { printf "⚠️  %s\n" "$*" >&2; }
err()  { printf "❌ %s\n" "$*" >&2; }
die()  { err "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

resolve_ctags_bin() {
  if [[ -n "${CLAUDE_FACTORY_CTAGS_BIN:-}" ]] && [[ -x "${CLAUDE_FACTORY_CTAGS_BIN}" ]]; then
    printf '%s\n' "$CLAUDE_FACTORY_CTAGS_BIN"
    return 0
  fi

  if [[ -x "/opt/homebrew/opt/universal-ctags/bin/ctags" ]]; then
    printf '%s\n' "/opt/homebrew/opt/universal-ctags/bin/ctags"
    return 0
  fi

  if [[ -x "/usr/local/opt/universal-ctags/bin/ctags" ]]; then
    printf '%s\n' "/usr/local/opt/universal-ctags/bin/ctags"
    return 0
  fi

  if have brew; then
    local brew_ctags
    brew_ctags="$(brew --prefix universal-ctags 2>/dev/null)/bin/ctags"
    if [[ -x "$brew_ctags" ]]; then
      printf '%s\n' "$brew_ctags"
      return 0
    fi
  fi

  if have ctags; then
    command -v ctags
    return 0
  fi

  return 1
}

if [[ "$CLAUDE_FACTORY_CTAGS_MODE" != "off" ]]; then
  CTAGS_BIN="$(resolve_ctags_bin 2>/dev/null || true)"
fi

sanitize_gitignore_docs_rules() {
  [[ -f ".gitignore" ]] || return 0

  local tmp
  tmp="$(mktemp)"

  grep -vE '^[[:space:]]*/?docs/.*$|^[[:space:]]*\*\.md[[:space:]]*$' .gitignore > "$tmp" || true

  if ! cmp -s .gitignore "$tmp"; then
    mv "$tmp" .gitignore
    echo "[ok] Removed invalid docs ignore rules from .gitignore"
  else
    rm -f "$tmp"
  fi
}

normalize_active_profiles() {
  local opencode_template="opencode.full.json"
  if [[ "$INSTALL_MODE" == "lite" ]]; then
    opencode_template="opencode.lite.json"
  fi

  [[ -f "CLAUDE.light.md" ]] && cp "CLAUDE.light.md" "CLAUDE.md"
  [[ -f "AGENTS.light.md" ]] && cp "AGENTS.light.md" "AGENTS.md"
  [[ -f "$opencode_template" ]] && cp "$opencode_template" "opencode.json"

  return 0
}

bootstrap_factory_env() {
  [[ -d ".claude" ]] || return 0

  local shared_root="${CLAUDE_FACTORY_SHARED_INFRA_ROOT:-$HOME/Sites/Local/Infrastructures}"
  local shared_claude_dir="$shared_root/.claude"
  local repo_root_real
  local shared_root_real=""

  repo_root_real="$(pwd -P)"
  if [[ -d "$shared_root" ]]; then
    shared_root_real="$(cd "$shared_root" && pwd -P)"
  fi

  if [[ ! -f ".claude/env.claude" ]]; then
    if [[ -n "$shared_root_real" ]] && [[ "$repo_root_real" != "$shared_root_real" ]] && [[ -f "$shared_claude_dir/env.claude" ]]; then
      cp "$shared_claude_dir/env.claude" ".claude/env.claude"
      echo "[ok] Seeded .claude/env.claude from shared infrastructure defaults"
    elif [[ -f ".claude/env.claude.sample" ]]; then
      cp ".claude/env.claude.sample" ".claude/env.claude"
      echo "[ok] Bootstrapped .claude/env.claude from template"
    fi
  fi

  if [[ ! -f ".claude/env.claude.local" ]]; then
    if [[ -n "$shared_root_real" ]] && [[ "$repo_root_real" != "$shared_root_real" ]] && [[ -f "$shared_claude_dir/env.claude.local" ]]; then
      cp "$shared_claude_dir/env.claude.local" ".claude/env.claude.local"
      echo "[ok] Seeded .claude/env.claude.local from shared infrastructure secrets"
    else
      cat > ".claude/env.claude.local" <<'EOF'
# Local Claude Factory secrets and overrides
# This file is gitignored.
# Fill only what your repo needs.

# Vault
VAULT_TOKEN=

# Argo CD
ARGOCD_AUTH_TOKEN=
ARGOCD_USERNAME=
ARGOCD_PASSWORD=

# Databases / services
DATABASE_URL=
SUPABASE_ACCESS_TOKEN=
GITHUB_TOKEN=
REDIS_URL=
EOF
      chmod 600 ".claude/env.claude.local" 2>/dev/null || true
      echo "[ok] Created .claude/env.claude.local template"
    fi
  fi
}

bootstrap_project_context() {
  [[ -d ".claude" ]] || return 0

  if [[ ! -f ".claude/project-context.md" && -f ".claude/project-context.md.sample" ]]; then
    cp ".claude/project-context.md.sample" ".claude/project-context.md"
    echo "[ok] Bootstrapped .claude/project-context.md from template"
  fi
}

ensure_executable() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  chmod +x "$f" 2>/dev/null || true
}

echo "=== Claude Factory — Setup (Mode: $INSTALL_MODE) ==="
echo "Repo: $REPO_ROOT"
echo ""

cd "$REPO_ROOT"

# ── 1) Basic repo sanity ─────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  warn "Not inside a git work tree. Features requiring git (index-state, smart ctags) will be skipped."
fi
[[ -d ".claude" ]] || die "Missing .claude/ directory (Factory core)."

if [[ "$INSTALL_MODE" == "full" ]]; then
  [[ -f ".mcp.json" ]] || warn "Missing .mcp.json (needed for full mode)."
  [[ -d "docs/policy" ]] || die "Missing docs/policy/ (Phase 2 policies)."
else
  # Lite mode checks
  [[ -f ".mcp.lite.json" ]] || warn "Missing .mcp.lite.json (needed for lite mode)."
fi

# Create all required runtime directories (idempotent via mkdir -p)
mkdir -p "$CLAUDE_FACTORY_LOGS_DIR"
mkdir -p ".claude/cache"
mkdir -p ".claude/memory"

sanitize_gitignore_docs_rules
normalize_active_profiles
bootstrap_factory_env
bootstrap_project_context

# Restrict permissions on sensitive directories (idempotent — chmod is a no-op if already set)
chmod 700 ".claude/cache" 2>/dev/null || true
chmod 700 ".claude/memory" 2>/dev/null || true

# ── 2) Dependencies ──────────────────────────────────────────────
if [[ "$CLAUDE_FACTORY_SKIP_DEPS" == "1" ]]; then
  say "[skip] deps (CLAUDE_FACTORY_SKIP_DEPS=1)"
else
  # macOS-friendly: brew install rg/ctags if missing, but do NOT auto-install node
  if [[ "$(uname -s)" == "Darwin" ]]; then
    if ! have brew; then
      warn "Homebrew not found. You can install dependencies manually."
    else
      if ! have rg; then
        say "[..] Installing ripgrep (rg) via brew..."
        brew install ripgrep
      fi
      if ! have ctags; then
        say "[..] Installing universal-ctags via brew..."
        brew install universal-ctags
      fi
    fi
  fi

  have git   || die "git not found (required)."
  have node  || die "node not found (required for MCP deps). Install via brew/nvm/nodejs."
  have npm   || die "npm not found (required for MCP deps)."
  have rg    || warn "rg not found (recommended)."
  have ctags || warn "ctags not found (recommended if you want tags)."
fi

echo ""

# ── 3) MCP server dependencies ───────────────────────────────────
if [[ -d "$CLAUDE_FACTORY_MCP_DIR" ]]; then
  echo "--- Installing MCP server dependencies ---"
  # Idempotency guard: only run npm install if node_modules missing or package.json newer
  if [[ ! -d "$CLAUDE_FACTORY_MCP_DIR/node_modules" ]] || \
     [[ "$CLAUDE_FACTORY_MCP_DIR/package.json" -nt "$CLAUDE_FACTORY_MCP_DIR/node_modules" ]]; then
    (cd "$CLAUDE_FACTORY_MCP_DIR" && npm install --no-fund --no-audit) || warn "npm install failed (non-fatal)"
  else
    say "[skip] MCP dependencies already installed"
  fi
  echo "[ok] MCP dependencies verified"
  echo ""
else
  warn "Missing $CLAUDE_FACTORY_MCP_DIR — skipping npm install."
  echo ""
fi

# ── 4) Cache subsystem initialization ────────────────────────────
echo "--- Initializing cache subsystem ---"

# Migration: context.db → cache.db (one-time, idempotent)
OLD_CACHE=".claude/cache/context.db"
NEW_CACHE=".claude/cache/cache.db"
if [[ -f "$OLD_CACHE" && ! -f "$NEW_CACHE" ]]; then
  echo "[migration] Renaming $OLD_CACHE → $NEW_CACHE"
  mv "$OLD_CACHE" "$NEW_CACHE" || warn "Failed to migrate cache database (non-fatal)"
elif [[ -f "$OLD_CACHE" && -f "$NEW_CACHE" ]]; then
  echo "[migration] Both databases exist — removing old context.db"
  rm -f "$OLD_CACHE" || warn "Failed to remove old cache database (non-fatal)"
else
  say "[skip] Cache migration not needed"
fi

if [[ -f "./.claude/scripts/cache.sh" ]]; then
  # Source cache library
  source ./.claude/scripts/cache.sh || die "Failed to source cache.sh"

  # Ensure decision_memory table exists (idempotent)
  sqlite3 "$CACHE_DB" <<'EOF' 2>/dev/null || warn "SQLite schema migration failed (non-fatal)"
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

  echo "[ok] Cache subsystem initialized"

  # Check for Redis (optional - warning only)
  if command -v redis-cli >/dev/null 2>&1 && redis-cli PING >/dev/null 2>&1; then
    echo "[ok] Redis detected and available"
  else
    warn "Redis not available (optional) — cache will use SQLite only"
  fi
  echo ""
else
  warn "cache.sh not found — cache subsystem not initialized"
  echo ""
fi

# ── 5) Make scripts executable ───────────────────────────────────
echo "--- Ensuring scripts are executable ---"
_scripts_fixed=0
for script in .claude/scripts/*.sh; do
  [[ -f "$script" ]] || continue
  if [[ ! -x "$script" ]]; then
    chmod +x "$script" 2>/dev/null && _scripts_fixed=$((_scripts_fixed + 1)) || true
  fi
done
if [[ $_scripts_fixed -gt 0 ]]; then
  echo "[ok] Fixed permissions on $_scripts_fixed script(s)"
else
  say "[skip] All scripts already executable"
fi

# Ensure cf runner is executable (if present)
if [[ -f "$REPO_ROOT/cf" ]]; then
  if [[ ! -x "$REPO_ROOT/cf" ]]; then
    chmod +x "$REPO_ROOT/cf" 2>/dev/null && echo "[ok] Made cf runner executable" || true
  fi
fi

# ── 6) Tags (ctags) generation ───────────────────────────────────
# Phase 2.3+: configurable via CLAUDE_FACTORY_CTAGS_MODE: smart|always|off
if [[ "${CLAUDE_FACTORY_CTAGS_MODE}" == "off" ]]; then
  say "[skip] tags (CLAUDE_FACTORY_CTAGS_MODE=off)"
elif ! have ctags; then
  warn "ctags not available; skipping tags generation."
else
  echo "--- Building tags (ctags) ---"
  rm -f "$CLAUDE_FACTORY_TAGS_OUT"

  # "smart": index tracked files only (fast + respects repo boundaries)
  # "always": index everything relevant (heavier, still excludes common junk)
  mode="$CLAUDE_FACTORY_CTAGS_MODE"
  if [[ "$mode" != "smart" && "$mode" != "always" ]]; then
    warn "Unknown CLAUDE_FACTORY_CTAGS_MODE=$mode; defaulting to smart."
    mode="smart"
  fi

  tmp_list="$(mktemp)"
  if [[ "$mode" == "smart" ]] && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git ls-files > "$tmp_list"
    # Fresh repo guard: if git tracks zero files, fall back to filesystem scan
    if [[ ! -s "$tmp_list" ]]; then
      warn "git ls-files returned 0 files (fresh repo?); falling back to filesystem scan."
      mode="always"
    fi
  fi

  if [[ "$mode" == "always" ]]; then
    # intentionally exclude obvious junk + secrets
    find "$REPO_ROOT" \
      -type d \( -name ".git" -o -name "node_modules" -o -name "dist" -o -name "build" -o -name ".next" -o -name ".turbo" -o -name "coverage" -o -path "*/.claude/mcp/node_modules" \) -prune -o \
      -type f \( \
        -name "*.ts" -o -name "*.tsx" -o -name "*.js" -o -name "*.jsx" -o -name "*.mjs" -o -name "*.cjs" -o \
        -name "*.json" -o -name "*.jsonc" -o -name "*.yml" -o -name "*.yaml" -o \
        -name "*.md" -o -name "*.mdx" -o \
        -name "*.sh" -o -name "*.zsh" -o \
        -name "*.sql" -o -name "*.graphql" -o -name "*.gql" \
      \) -print > "$tmp_list"
  fi

  # Safety cap
  file_count="$(wc -l < "$tmp_list" | tr -d ' ')"
  if [[ "$file_count" -gt "$CLAUDE_FACTORY_MAX_TAG_FILES" ]]; then
    rm -f "$tmp_list"
    die "Too many files to index ($file_count > $CLAUDE_FACTORY_MAX_TAG_FILES). Use CTAGS_MODE=smart or raise the cap."
  fi

  [[ -n "$CTAGS_BIN" ]] || die "ctags not found or unsupported"

  "$CTAGS_BIN" -L "$tmp_list" -f "$CLAUDE_FACTORY_TAGS_OUT" || {
    rm -f "$tmp_list"
    die "ctags failed"
  }
  rm -f "$tmp_list"

  echo "[ok] tags built: $CLAUDE_FACTORY_TAGS_OUT"
  echo ""
fi

# ── 7) Phase 2.5 required validation (hardening) ─────────────────
# Phase 2.5 expects these to exist and pass on install.
# Run AFTER tags generation to avoid circular dependency.
if [[ "$INSTALL_MODE" == "full" ]]; then
  if [[ -f "./.claude/scripts/health-check.sh" ]]; then
    echo "--- Running health-check.sh ---"
    ./.claude/scripts/health-check.sh
    echo "[ok] health-check.sh PASS"
    echo ""
  else
    warn "health-check.sh not found; Phase 2.5 expects it."
    echo ""
  fi

  if [[ -f "./.claude/scripts/validate-policies.sh" ]]; then
    echo "--- Running validate-policies.sh ---"
    ./.claude/scripts/validate-policies.sh
    echo "[ok] validate-policies.sh PASS"
    echo ""
  else
    warn "validate-policies.sh not found; Phase 2.5 expects it."
    echo ""
  fi
else
  say "[skip] Validation scripts (lite mode)"
fi

# ── 8) index-state (optional) ────────────────────────────────────
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  head_sha="$(git rev-parse HEAD 2>/dev/null || true)"
  if [[ -n "$head_sha" ]]; then
    mkdir -p "$(dirname "$CLAUDE_FACTORY_INDEX_STATE")"
    printf '{ "head": "%s", "timestamp": "%s" }\n' "$head_sha" "$(date -Iseconds)" > "$CLAUDE_FACTORY_INDEX_STATE"
    echo "[ok] wrote $CLAUDE_FACTORY_INDEX_STATE"
  fi
fi

echo ""
echo "✅ Setup complete (mode: $INSTALL_MODE)."
echo ""

if [[ "$INSTALL_MODE" == "lite" ]]; then
  echo "Next steps (Lite Mode):"
  echo "  1) Open this repo in Claude Code or OpenCode, or run: ./cf-lite"
  echo "  2) Configure MCP environment (optional):"
  echo "     vim .claude/env.claude                            # customize shared defaults"
  echo "     vim .claude/env.claude.local                      # add secrets/overrides"
  echo "     # Note: both files are repo-local and gitignored"
  echo "  3) Verify MCP connection:"
  echo "     claude --mcp-config .mcp.lite.json --mcp-status"
  echo "     opencode                                           # verify opencode.json is picked up"
  echo ""
  echo "Lite mode includes:"
  echo "  • 3 MCP servers: factory-ops, factory-git, factory-fs"
  echo "  • No workflow automation (MCP tools only)"
  echo "  • No ctags indexing or cache subsystem"
  echo ""
  echo "To upgrade to full mode:"
  echo "  ./install.sh --mode full"
else
  echo "Next steps (Full Mode):"
  echo "  1) Open this repo in Claude Code or OpenCode"
  echo "  2) Run: /mcp  (to verify MCP servers are connected)"
  echo "  3) Configure Factory environment (optional):"
  echo "     vim .claude/env.claude                            # customize shared defaults"
  echo "     vim .claude/env.claude.local                      # add secrets/overrides"
  echo "     # Note: both files are repo-local and gitignored"
  echo "  4) Bootstrap app environment variables (optional):"
  echo "     bash .claude/scripts/bootstrap-env.sh --dry-run  # preview"
  echo "     bash .claude/scripts/bootstrap-env.sh            # generate .env.local files"
  echo "     # Note: Creates .env.local files with EMPTY values only (no secrets)"
  echo "     # See docs/INSTALL.md for secret placement guidance"
  echo "  5) Start a task — Claude and OpenCode are ready"
  echo ""
  echo "Verify installation:"
  echo "  ./.claude/scripts/verify.sh              # quick verification (default)"
  echo "  ./.claude/scripts/verify.sh full         # full health + policy check"
  echo "  ./.claude/scripts/verify.sh smoke        # operational smoke tests"
fi

echo ""
echo "Runtime directories (gitignored):"
echo "  .claude/cache/    — SQLite cache database"
echo "  .claude/logs/     — run logs and audit trail"
echo "  .claude/memory/   — decision memory tracking"
