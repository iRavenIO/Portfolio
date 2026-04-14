# Factory Troubleshooting Guide

Comprehensive troubleshooting reference for the Autonomous Multi-Agent Software Factory. This guide covers installation issues, MCP server problems, cache/database issues, tags indexing, git operations, and configuration errors.

## Quick Reference Table

| Error Scenario | Section | Symptom | Quick Fix |
|----------------|---------|---------|-----------|
| Missing .claude/ directory | Installation | `.mcp.json` registered but MCP servers fail to connect | Run `./install.sh` to create directory structure |
| Missing docs/policy/ | Installation | Manager says "CLAUDE.md policy file not found" | Run bootstrap runbook or copy from source factory |
| node/npm/git not found | Installation | `install.sh` fails with "command not found" | Install Node.js, npm, and git then re-run |
| git ls-files returned 0 files | Installation | ctags index empty despite having files in repo | See Fresh Repo Edge Cases in bootstrap runbook |
| Too many files to index | Tags | ctags hangs or times out during install | Set `CLAUDE_FACTORY_MAX_TAG_FILES` environment variable |
| ctags failed | Tags | Error: "ctags: command not found" | Install Universal Ctags: `brew install universal-ctags` |
| MCP node_modules missing | MCP | MCP servers fail to start with module not found | Run `cd .claude/mcp && npm install` |
| ctags not Universal Ctags | Tags | Tags index incomplete or missing modern language support | Uninstall old ctags, install universal-ctags |
| Cache database corrupted | Cache | Error: "SQLite database is malformed" | Delete `.claude/cache/cache.db` and restart |
| Not a git repository | Git | Error: "fatal: not a git repository" | Run `git init` or verify you're in the correct directory |
| Auto-commit skipped: submodule changes | Git | Reporter says "Submodule changes detected, blocking commit" | Commit submodule changes separately |
| Auto-commit blocked: credentials | Git | Reporter says "Potential credentials detected, blocking commit" | Review changes, remove credentials, commit manually |

## Installation Failures

### 1. Missing .claude/ Directory

**Symptom:**
- `.mcp.json` is present but MCP servers fail to connect
- Claude Code shows "Server startup failed" in logs
- Running `./install.sh` says ".claude/mcp/package.json not found"

**Diagnosis:**
```bash
ls -la .claude/
# Should show: mcp/ agents/ runbooks/ scripts/ cache/
```

**Fix:**
```bash
# If .claude/ is missing entirely, you need to bootstrap the factory
# Option 1: Copy from source factory repository
SOURCE_REPO="/path/to/source-factory"
cp -R "$SOURCE_REPO/.claude" .

# Option 2: Run bootstrap runbook
# See .claude/runbooks/bootstrap-new-repo.md for full instructions
```

**Context:** The `.claude/` directory contains all factory infrastructure. If it's missing, the MCP servers cannot start because their source files don't exist.

---

### 2. Missing docs/policy/

**Symptom:**
- Manager starts but immediately fails with "CLAUDE.md references policy file not found"
- Policy files referenced in CLAUDE.md return 404
- Agents spawn with incomplete instructions

**Diagnosis:**
```bash
ls -la docs/policy/
# Should show at least 15 policy files (.md files)
.claude/scripts/health-check.sh
# Check 10 should show: "✅ Policy directory exists (>=12 files)"
```

**Fix:**
```bash
# Copy policy files from source factory
SOURCE_REPO="/path/to/source-factory"
mkdir -p docs/policy
cp -R "$SOURCE_REPO/docs/policy/"* docs/policy/

# Verify
.claude/scripts/validate-policies.sh
```

**Context:** Policy files are modular governance documents that define how the factory operates. CLAUDE.md is just a thin orchestrator that references these files.

---

### 3. node/npm/git Not Found

**Symptom:**
- `./install.sh` fails with "node: command not found" or "npm: command not found"
- MCP servers cannot start
- ctags indexing fails with "git: command not found"

**Diagnosis:**
```bash
which node   # Should return a path like /usr/local/bin/node
which npm    # Should return a path
which git    # Should return a path

node --version  # Should be >= 18
npm --version
git --version
```

**Fix:**
```bash
# Install Node.js (includes npm)
# Option 1: Homebrew (macOS/Linux)
brew install node

# Option 2: nvm (cross-platform)
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
nvm install 18
nvm use 18

# Install git (if not present)
brew install git

# Verify
node --version  # Should show v18.x or higher
npm --version
git --version

# Re-run install
./install.sh
```

**Context:** Node.js 18+ is required for ESM module support in MCP servers. Git is required for ctags incremental indexing.

---

### 4. Fresh Repo Edge Cases

**Symptom:**
- `./install.sh` reports "git ls-files returned 0 files — cannot index empty repository"
- Tags file is created but empty (0 bytes)
- Bootstrap runbook Step 3 fails

**Diagnosis:**
```bash
git ls-files | wc -l
# If output is 0, no files are tracked yet

git status
# Shows all files as untracked
```

**Fix:**
See bootstrap-new-repo.md Step 1A for detailed guidance. Summary:

```bash
# Add at minimum: CLAUDE.md, .mcp.json, install.sh, .claude/, docs/policy/
git add CLAUDE.md .mcp.json install.sh .claude/ docs/policy/

# Verify files are staged
git ls-files | wc -l
# Should now show a positive count

# Re-run install
./install.sh
```

**Context:** `git ls-files` only returns tracked files (staged or committed). In a fresh repo with no initial commit, all files are untracked, so ctags has nothing to index. The solution is to stage essential factory files before running `install.sh`.

---

## MCP Server Issues

### Systematic MCP Diagnosis

When MCP servers fail to connect or tools return errors, follow this 5-step diagnostic protocol:

**Step 1: Verify MCP server registration**
```bash
cat .mcp.json | grep factory-
# Should show 6 servers: factory-tools, factory-ctags, factory-rg, factory-fs, factory-git, factory-query
```

**Step 2: Check MCP server files exist**
```bash
ls -lh .claude/mcp/server*.js
# Should show:
# server.js, server-ctags.js, server-rg.js, server-fs.js, server-git.js, server-query.js
```

**Step 3: Verify node_modules installed**
```bash
ls -la .claude/mcp/node_modules
# Should show @modelcontextprotocol, zod, and other dependencies
```

If missing:
```bash
cd .claude/mcp && npm install && cd ../..
```

**Step 4: Test server startup**
```bash
cd .claude/mcp
node server.js < /dev/null &
PID=$!
sleep 2
kill $PID 2>/dev/null
# If no error, server started successfully. Repeat for all 6 servers.
```

**Step 5: Check Claude Code logs**
In Claude Code:
- Help → Show Logs
- Look for MCP server startup errors
- Common errors: module not found, syntax error, port conflict

---

### 5. MCP node_modules Missing

**Symptom:**
- Error: "Cannot find module '@modelcontextprotocol/sdk'"
- MCP servers fail to start
- Claude Code logs show "Error: MODULE_NOT_FOUND"

**Diagnosis:**
```bash
ls .claude/mcp/node_modules/@modelcontextprotocol
# Should exist and contain sdk/
```

**Fix:**
```bash
cd .claude/mcp
npm install
cd ../..

# Verify
ls node_modules/@modelcontextprotocol/sdk/server/
# Should show mcp.js, stdio.js, etc.

# Restart Claude Code to reconnect servers
```

**Context:** MCP servers are Node.js ESM modules that depend on the MCP SDK. `install.sh` runs `npm install` automatically, but if you copied the factory manually or deleted node_modules, you need to reinstall.

---

### 6. Tool Returns "command not found"

**Symptom:**
- `code_search_rg` returns "rg: command not found"
- `code_index_ctags` returns "ctags: command not found"
- `research_search_web` returns "gemini: command not found"

**Diagnosis:**
```bash
which rg      # Should return /usr/local/bin/rg or similar
which ctags   # Should return /usr/local/bin/ctags
which gemini  # Should return a path

# Check if they're the correct versions
ctags --version  # Should say "Universal Ctags"
rg --version     # Should show ripgrep version
```

**Fix:**

**For rg (ripgrep):**
```bash
brew install ripgrep
which rg  # Verify
```

**For ctags (Universal Ctags, NOT Exuberant Ctags):**
```bash
brew install universal-ctags
ctags --version  # Should say "Universal Ctags"
```

If you have old ctags:
```bash
which ctags  # Note the path
brew unlink ctags  # If installed via Homebrew
brew install universal-ctags
which ctags  # Verify it's now the universal-ctags version
```

**For gemini CLI:**
```bash
npm install -g @google/genai-for-devs
which gemini  # Verify

# Configure API key
export GOOGLE_AI_API_KEY="your-api-key-here"
# Add to ~/.bashrc or ~/.zshrc for persistence
```

**Context:** MCP tools wrap CLI utilities. If the underlying CLI tool is not installed or not in PATH, the MCP tool will fail with ENOENT (command not found).

---

### 7. MCP Tool Fallback to Bash

**Symptom:**
- Agent says "MCP tool unavailable, falling back to Bash"
- Works but slower or less safe than MCP
- No structured output (plain text instead of JSON)

**Diagnosis:**
```bash
# In Claude Code, run:
/mcp
# Check if all 6 servers are listed as "Connected"
```

**Fix:**
If servers are not connected:
1. Follow systematic MCP diagnosis (above)
2. Restart Claude Code
3. Verify `/mcp` shows all 6 servers

If servers are connected but tools still unavailable:
- Check agent MCP tool permissions in `docs/policy/agents.md`
- Verify the tool name matches exactly (e.g., `code_search_rg`, not `search_rg`)
- Check Claude Code logs for tool call errors

**Context:** Agents are designed to fall back to Bash equivalents when MCP tools are unavailable. This is a safety mechanism but loses the benefits of MCP (input validation, structured output, security sandboxing).

---

## Cache and Database Issues

### 8. SQLite Database Corrupted

**Symptom:**
- Error: "SQLite database is malformed"
- Cache reads/writes fail
- `.claude/cache/cache.db` exists but unreadable

**Diagnosis:**
```bash
sqlite3 .claude/cache/cache.db "PRAGMA integrity_check;"
# Should return "ok"
# If it returns errors or hangs, the database is corrupted
```

**Fix:**
```bash
# Delete the corrupted database
rm .claude/cache/cache.db

# The cache system will auto-create a new database on next run
# No data loss — cache is ephemeral by design

# Restart Claude Code and re-run your task
```

**Context:** The SQLite cache is used for repository maps and tool result caching. Corruption can occur from unclean shutdowns or disk errors. Deleting the cache is safe — all data can be regenerated.

---

### 9. Cache Directory Permissions

**Symptom:**
- Error: "EACCES: permission denied, mkdir '.claude/cache/'"
- Cache reads/writes fail
- Agents report "Cannot write to cache"

**Diagnosis:**
```bash
ls -ld .claude/cache/
# Should show drwxr-xr-x (readable and writable by owner)

ls -l .claude/cache/cache.db
# Should show -rw-r--r-- (writable by owner)
```

**Fix:**
```bash
# Fix directory permissions
chmod 755 .claude/cache/

# Fix database file permissions (if it exists)
chmod 644 .claude/cache/cache.db

# If owned by wrong user
sudo chown -R $(whoami) .claude/cache/
```

**Context:** Cache files are created at runtime with default umask permissions. If the factory was run by a different user (e.g., via sudo), ownership may be incorrect.

---

### 10. Stale Cache Entries

**Symptom:**
- Tools return outdated results
- Repository map shows deleted files
- Cache hits on stale data

**Diagnosis:**
```bash
# Check cache age
stat -f "%Sm" .claude/cache/cache.db
# If older than 24 hours, may contain stale data

# Check cache.sh TTL defaults
grep "TTL_DEFAULT" .claude/scripts/cache.sh
# Should show 3600 (1 hour) for most entries
```

**Fix:**
```bash
# Clear all cache entries
rm .claude/cache/cache.db

# Or clear specific cache keys using cache.sh
.claude/scripts/cache.sh delete repo-map
.claude/scripts/cache.sh delete <key>

# Rebuild repo map
.claude/scripts/build-repo-map.sh > .claude/cache/repo-map.txt
```

**Context:** Cache entries have TTLs but are not actively expired until the next read. If a file is deleted, the cache may still serve the old entry until TTL expires or the cache is cleared.

---

## Tags and Indexing Issues

### 11. Tags Index Empty or Incomplete

**Symptom:**
- `tags` file exists but has 0 bytes or very few entries
- Agents cannot find symbols in code
- `code_index_ctags` reports "Indexed 0 files"

**Diagnosis:**
```bash
ls -lh tags
# Check size — should be at least a few KB for non-trivial repos

head -20 tags
# Should show symbol entries like:
# functionName	src/file.js	/^function functionName/;"	f

wc -l tags
# Count of symbols — should be > 0
```

**Fix:**

**If tags file is empty:**
```bash
# Force a full rebuild
rm tags
rm .claude/index-state.json
./install.sh

# Or manually via MCP tool
# In Claude Code: (Manager only)
# code_index_ctags({ "mode": "full" })

# Or via Bash
git ls-files | ctags -L - -f tags --fields=+lnS --extras=+q
```

**If tags file is incomplete:**
```bash
# Check which languages ctags supports
ctags --list-languages

# Check if your files are supported
git ls-files | grep -E '\.(js|ts|py|go|java)$' | wc -l
# Compare to tags line count

# If language is supported but symbols missing, check .gitignore
cat .gitignore | grep -E 'src/|lib/'
# Ensure important source directories are not ignored
```

**Context:** ctags indexes only tracked git files (via `git ls-files`). If files are untracked or ignored, they won't be indexed. Also, ctags must be Universal Ctags (not Exuberant Ctags) for modern language support.

---

### 12. ctags Not Universal Ctags

**Symptom:**
- Tags index missing TypeScript, modern JavaScript, or other language features
- `ctags --version` shows "Exuberant Ctags" instead of "Universal Ctags"
- Symbol lookups fail for recent language constructs

**Diagnosis:**
```bash
ctags --version
# Should output: "Universal Ctags x.y.z"
# If it says "Exuberant Ctags", you have the wrong version

which -a ctags
# Shows all ctags binaries in PATH — check if multiple exist
```

**Fix:**
```bash
# Uninstall Exuberant Ctags
# If installed via Homebrew:
brew uninstall ctags

# If installed via apt (Linux):
sudo apt remove exuberant-ctags

# Install Universal Ctags
brew install universal-ctags

# Verify
ctags --version  # Should say "Universal Ctags"
which ctags       # Should point to Homebrew path (/usr/local/bin/ctags)

# Rebuild tags
rm tags .claude/index-state.json
./install.sh
```

**Context:** Exuberant Ctags is an older, unmaintained fork. Universal Ctags is the actively maintained version with support for TypeScript, JSX, modern JavaScript, Go modules, and many other languages. The factory requires Universal Ctags.

---

### 13. Incremental Indexing Falling Back to Full

**Symptom:**
- `code_index_ctags` logs say "Auto-escalating to full rebuild"
- Indexing takes a long time despite only a few files changing
- `.claude/index-state.json` shows old or missing `last_indexed_sha`

**Diagnosis:**
```bash
cat .claude/index-state.json
# Check last_indexed_sha, last_full_indexed_at, last_mode

git log --oneline -1
# Compare HEAD sha to last_indexed_sha

# Check auto-escalation thresholds
grep -E "MAX_CHANGED_FILES|STALENESS_HOURS" .claude/mcp/server-ctags.js
```

**Fix:**
This is expected behavior in these cases:
- More than 1,500 files changed
- Any deletes or renames detected (append can't remove stale symbols)
- More than 24 hours since last full index
- last_indexed_sha is not an ancestor of HEAD (rebase/force-push)

To reduce full rebuilds:
```bash
# Avoid large batch changes — split into smaller commits
# Avoid rebases when possible
# Ensure full index runs at least daily (auto-escalation will handle this)
```

To force incremental (not recommended):
```bash
# Edit server-ctags.js and increase thresholds (at your own risk)
# This may result in stale symbols in the index
```

**Context:** Auto-escalation ensures correctness. Incremental mode is fast but cannot remove stale symbols from deleted/renamed files. The 24-hour threshold prevents indefinite accumulation of stale entries.

---

## Git Issues

### 14. Not a Git Repository

**Symptom:**
- Error: "fatal: not a git repository (or any of the parent directories): .git"
- `git ls-files` returns nothing
- ctags fails with "Cannot determine repository root"

**Diagnosis:**
```bash
git status
# Should show branch name and status
# If error: "fatal: not a git repository", you're not in a git repo

ls -la .git
# Should exist and be a directory (not a file)
```

**Fix:**
```bash
# If .git is missing entirely, initialize the repo
git init
git add .
git commit -m "Initial commit"

# Then run install.sh
./install.sh

# If you're in a subdirectory, navigate to repo root
git rev-parse --show-toplevel
cd $(git rev-parse --show-toplevel)
```

**Context:** The factory requires a git repository for ctags incremental indexing and file tracking. `git ls-files` is used to determine which files to index.

---

### 15. Auto-Commit Blocked: Submodule Changes

**Symptom:**
- Reporter says "Submodule changes detected in: <paths>"
- Commit is blocked and not created
- Changes remain unstaged

**Diagnosis:**
```bash
git status
# Look for lines like:
# modified:   path/to/submodule (new commits)

cat .gitmodules
# Shows submodule paths

git diff --name-only | grep -F "$(git config --file .gitmodules --get-regexp path | awk '{print $2}')"
# Lists changed files inside submodules
```

**Fix:**
```bash
# Submodule changes must be committed separately
cd path/to/submodule
git add .
git commit -m "Submodule changes"
cd ../..

# Then update the parent repo pointer
git add path/to/submodule
git commit -m "Update submodule reference"

# Now factory can auto-commit remaining changes
```

**Context:** Auto-commit intentionally blocks submodule changes to prevent accidental commits of unreviewed submodule state. See `docs/policy/git-automation.md` SUBMODULE HANDLING section for detailed rationale.

---

### 16. Auto-Commit Blocked: Potential Credentials

**Symptom:**
- Reporter says "Potential credentials detected in: <files>"
- Commit is blocked and not created
- Manual review required

**Diagnosis:**
```bash
git diff | grep -iE 'api[_-]?key|password|secret|token|credential'
# Shows lines that triggered the block

# Check specific files
git diff path/to/file.js
```

**Fix:**
```bash
# Review the flagged files
# If credentials are real:
1. Remove them from code
2. Move to environment variables or secret manager
3. Add to .gitignore if it's a config file

# If false positive (e.g., "password" is a variable name, not a value):
# Commit manually with explicit intent
git add <files>
git commit -m "Your commit message

(Reviewed: flagged patterns are false positives)

Co-Authored-By: Claude Sonnet 4.5 <noreply@anthropic.com>"
```

**Context:** Auto-commit scans diffs for common credential patterns. This is a safety mechanism to prevent accidental credential leaks. See `docs/policy/secrets-and-env.md` for full denylist patterns.

---

## Configuration Issues

### 17. Invalid .gitignore Patterns

**Symptom:**
- Files are ignored that shouldn't be (or vice versa)
- `git ls-files` shows unexpected files
- ctags indexes files that should be ignored

**Diagnosis:**
```bash
# Check if a file is ignored
git check-ignore -v path/to/file

# Test .gitignore patterns
git ls-files --ignored --exclude-standard
# Shows all ignored tracked files (shouldn't be any)

# Validate .gitignore syntax
git check-ignore --verbose .
```

**Fix:**
```bash
# Common .gitignore mistakes:
# ❌ node_modules     (matches nested paths too)
# ✅ /node_modules/   (matches only at repo root)

# ❌ *.log            (ignores all .log files)
# ✅ *.log            (if you want this, it's correct)
# ✅ /logs/*.log      (only .log files in /logs)

# Edit .gitignore to fix patterns
# Reference: https://git-scm.com/docs/gitignore

# Re-index after fixing
rm tags .claude/index-state.json
./install.sh
```

**Context:** .gitignore uses glob patterns with special rules. Leading `/` anchors to repo root. Trailing `/` matches only directories. See bootstrap-new-repo.md Step 2 for factory .gitignore best practices.

---

### 18. Environment Variables Not Set

**Symptom:**
- Factory behavior doesn't change despite setting environment variables
- `./cf` script doesn't export run ID
- Auto-commit still runs despite `CLAUDE_FACTORY_AUTO_COMMIT=0`

**Diagnosis:**
```bash
# Check if variables are set in current shell
env | grep CLAUDE_FACTORY

# Check if install.sh sources them
grep "export" install.sh

# Check if .bashrc or .zshrc exports them
grep CLAUDE_FACTORY ~/.bashrc ~/.zshrc
```

**Fix:**
```bash
# Set environment variables before running commands
export CLAUDE_FACTORY_AUTO_COMMIT=0
export CLAUDE_FACTORY_SKIP_CONFIRMATION=1
./cf claude "your prompt"

# Or inline
CLAUDE_FACTORY_AUTO_COMMIT=0 ./cf claude "your prompt"

# For persistence, add to shell profile
echo 'export CLAUDE_FACTORY_AUTO_COMMIT=0' >> ~/.bashrc  # or ~/.zshrc
source ~/.bashrc  # or source ~/.zshrc
```

**Context:** Environment variables must be set in the shell where the command runs. Setting them in one terminal doesn't affect other terminals unless exported in the shell profile.

---

### 19. .mcp.json Path Issues

**Symptom:**
- MCP servers registered but fail to start
- Claude Code logs: "Cannot find module '.claude/mcp/server.js'"
- Servers work when run manually but not via Claude Code

**Diagnosis:**
```bash
cat .mcp.json | jq '.mcpServers."factory-tools".args'
# Should show: [".claude/mcp/server.js"]
# NOT: ["server.js"] or ["/.claude/mcp/server.js"]

# Test relative path from repo root
node .claude/mcp/server.js < /dev/null
# Should start without errors
```

**Fix:**
```bash
# Edit .mcp.json
# Ensure all paths are relative to repo root (no leading /)
{
  "mcpServers": {
    "factory-tools": {
      "command": "node",
      "args": [".claude/mcp/server.js"]  ← correct
    }
  }
}

# Restart Claude Code after editing .mcp.json
```

**Context:** Claude Code executes MCP server commands from the repository root. Paths must be relative to that root. Absolute paths (`/Users/...`) break portability.

---

## Verification Script Failures

### 20. health-check.sh Reports Failures

**Symptom:**
- `./claude/scripts/health-check.sh` exits with errors
- One or more checks show ❌ instead of ✅
- Factory may still work but is in degraded state

**Diagnosis:**
```bash
./.claude/scripts/health-check.sh
# Read the failed check messages

# Common failures:
# ❌ MCP dependencies not installed → run npm install
# ❌ Tags file missing or empty → run ./install.sh
# ❌ Policy file count < 12 → copy missing policy files
```

**Fix:**
Follow the suggestions in the health check output. Most failures have a one-line fix:
```bash
# For MCP dependencies
cd .claude/mcp && npm install && cd ../..

# For missing tags
rm tags .claude/index-state.json && ./install.sh

# For missing policy files
# See "Missing docs/policy/" section above
```

**Context:** health-check.sh runs 13 critical checks in ~3 seconds. It's designed to catch 90% of factory setup issues. Always run after bootstrap or when troubleshooting.

---

### 21. validate-policies.sh Reports Failures

**Symptom:**
- `./.claude/scripts/validate-policies.sh` exits with errors
- Policy files missing expected sections or references
- Factory may spawn agents with incomplete instructions

**Diagnosis:**
```bash
./.claude/scripts/validate-policies.sh
# Read the failed validation messages

# Common failures:
# ❌ orchestration.md missing BUDGET BLOCK SYSTEM
# ❌ spawn-templates.md missing QUOTA SNAPSHOT references
# ❌ critical-rules.md rule count < 28
```

**Fix:**
```bash
# If policy file structure is wrong, re-copy from source factory
SOURCE_REPO="/path/to/source-factory"
cp "$SOURCE_REPO/docs/policy/<file>.md" docs/policy/

# If policy files are from an older version, update the factory
# (This usually means pulling latest changes from the factory repo)

# Verify
./.claude/scripts/validate-policies.sh
```

**Context:** validate-policies.sh checks policy file integrity (existence, section structure, cross-references). It ensures CLAUDE.md's references are valid and agents receive complete instructions.

---

## Getting Help

If this guide doesn't resolve your issue:

1. **Check the logs**
   - Claude Code: Help → Show Logs
   - cf runner: `.claude/logs/run-*.log`
   - MCP servers: stderr output (captured in Claude Code logs)

2. **Run verification scripts**
   ```bash
   ./.claude/scripts/health-check.sh
   ./.claude/scripts/validate-policies.sh
   ```

3. **Search this guide**
   - Use your browser's find (Cmd+F / Ctrl+F) to search error messages
   - Check the Quick Reference Table at the top

4. **Review policy files**
   - Most factory behavior is defined in `docs/policy/*.md`
   - CLAUDE.md links to relevant policies for each feature

5. **Check runbooks**
   - `.claude/runbooks/` contains step-by-step procedures for common operations
   - bootstrap-new-repo.md covers fresh repo setup
   - add-mcp-server.md and add-agent.md cover extensions

6. **Incremental debugging**
   - Test MCP servers individually (see Systematic MCP Diagnosis)
   - Verify prerequisites (Node.js, git, CLI tools)
   - Start with a minimal task to isolate the issue

7. **Review recent changes**
   ```bash
   git log --oneline -10
   git diff HEAD~1
   # Check if recent commits broke the factory
   ```

8. **Restore known-good state**
   ```bash
   git checkout <last-working-commit>
   ./install.sh
   # Verify factory works, then incrementally re-apply changes
   ```

For factory development issues, see `docs/policy/failure-recovery.md` for adaptive escalation rules and recovery patterns.
