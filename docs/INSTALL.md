# Installation & Quickstart Guide

**Phase 5.5 — Safe Project Bootstrap + Environment Variable Management**

This guide covers setting up the Claude Factory repository and safely managing secrets across development, staging, and production environments.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Behavioral Modes](#behavioral-modes)
3. [Environment Bootstrap](#environment-bootstrap)
4. [Secret Management](#secret-management)
5. [Verification](#verification)
6. [Troubleshooting](#troubleshooting)

---

## Quick Start

### Prerequisites

- **Bash** 4.0+ (macOS, Linux, WSL)
- **Node.js** 20+ (for MCP servers)
- **Git** 2.0+

### 1. Clone Repository

```bash
git clone <repository-url>
cd Claude
```

### 2. Install Dependencies

```bash
cd .claude/mcp
npm install
```

### 3. Bootstrap Environment Variables

```bash
# Scan entire repo and create .env.local files with empty values
bash .claude/scripts/bootstrap-env.sh

# Dry run to see what would be created (recommended first step)
bash .claude/scripts/bootstrap-env.sh --dry-run

# Bootstrap specific project only
bash .claude/scripts/bootstrap-env.sh --project apps/web
```

### 4. Fill in Secrets

The bootstrap script creates `.env.local` files with **EMPTY values only**. You must fill in secrets manually.

**IMPORTANT:** Never commit `.env.local` files to git. They are in `.gitignore`.

See [Secret Management](#secret-management) for where to get each secret.

### 5. Verify Installation

```bash
# Run health check
bash .claude/scripts/health-check.sh

# Run E2E tests
bash .claude/scripts/test-ops-stage4.sh
bash .claude/scripts/test-bootstrap-env.sh
```

---

## Behavioral Modes

Claude Factory supports two **behavioral profiles** that control how Claude operates. These are **behavior-only settings** — all tools and capabilities remain identical.

### LIGHT Mode (Default, Recommended)

**Single-pass, token-efficient execution.**

```bash
cfmode light  # Switch to LIGHT mode
```

**Behavior:**
- ✅ One-pass execution: brief plan → implement → test → concise summary
- ✅ Direct tool usage (no multi-agent orchestration)
- ✅ Token-efficient (uses FAST model by default, STRONG only when needed)
- ✅ Concise output (2-3 sentence summaries)
- ❌ No elaborate reports or voice notifications by default

**Best for:**
- Most development tasks (bugs, features, refactors)
- Routine maintenance and updates
- Quick prototyping
- Token-conscious workflows

**Example workflow:**
```
User: "Add input validation to login form"
→ Claude reads code, makes brief plan, implements, tests, provides summary
→ Total: 1 interaction, ~5-10k tokens
```

### FULL Mode (Optional, for Complex Tasks)

**Multi-phase workflow with complete orchestration.**

```bash
cfmode full  # Switch to FULL mode
```

**Behavior:**
- ✅ Multi-phase pipeline (Analyst → Researcher → Architect → Developer → Reviewer → Tester → Reporter)
- ✅ Comprehensive planning and research
- ✅ Detailed reports in docs/tasks/reports/
- ✅ Voice notifications via notify_say
- ✅ Heavy orchestration with specialized agents

**Best for:**
- Complex architectural designs
- Security audits
- Multi-system integrations
- Tasks requiring extensive research
- When you explicitly want detailed documentation

**Example workflow:**
```
User: "Design and implement comprehensive caching strategy"
→ Analyst analyzes requirements (5k tokens)
→ Researcher investigates caching patterns (10k tokens)
→ Architect designs solution (15k tokens)
→ Developer implements (20k tokens)
→ Reviewer reviews code (10k tokens)
→ Tester runs tests (5k tokens)
→ Reporter generates docs/tasks/reports/TASK_REPORT.md (5k tokens)
→ Total: 7 phases, ~70k tokens
```

### Comparison

| Aspect | LIGHT Mode | FULL Mode |
|--------|-----------|-----------|
| **Default** | ✅ Yes | No (opt-in) |
| **Execution** | Single-pass | Multi-phase pipeline |
| **Agents** | None (direct tools) | 7 specialized agents |
| **Planning** | Inline (≤8 bullets) | Detailed execution plan |
| **Reports** | Concise (2-3 sentences) | Comprehensive (docs/tasks/reports/) |
| **Model usage** | FAST default, STRONG when needed | Fixed per phase |
| **Notifications** | None | Voice (notify_say) |
| **Token cost** | Low (~5-20k typical) | High (~50-100k typical) |
| **Best for** | Most tasks | Complex architecture, audits |

### Switching Modes

**From command line:**
```bash
# Switch to LIGHT (default)
cfmode light

# Switch to FULL
cfmode full

# Check current mode
cfmode status
```

**From within repo:**
The mode is determined by which profile is active in `CLAUDE.md`:
- `CLAUDE.md` → `CLAUDE.light.md` (LIGHT mode)
- `CLAUDE.md` → `CLAUDE.full.md` (FULL mode)

**Installation default:**
Both `cfactory` and `cfactorylite` install with LIGHT mode by default.

### When to Use Each Mode

**Use LIGHT mode (default) for:**
- Bug fixes
- Feature additions
- Refactoring
- Code reviews
- Testing
- Documentation updates
- Configuration changes
- Dependency updates

**Use FULL mode when:**
- User explicitly requests "comprehensive", "detailed", or "research-based" approach
- Task involves novel architectural decisions
- Security-critical implementations requiring deep analysis
- Multi-system integrations with many unknowns
- You need detailed documentation and reports

**Rule of thumb:** Start with LIGHT. Switch to FULL only if task clearly benefits from it.

---

## Claude Factory Environment (`env.claude`)

### What is `env.claude`?

A **factory-scoped** configuration file for Claude Factory scripts, MCP servers, and Ops tooling. This is separate from application-level `.env.local` files.

| File | Purpose | Contains Secrets? | Scope |
|------|---------|-------------------|-------|
| `.claude/env.claude` | Factory/MCP/Ops configuration | **No** | Claude Factory tooling |
| `.env.local` (per-project) | Application runtime secrets | **Yes** | Application code |

### Setup

```bash
# Copy the sample file
cp .claude/env.claude.sample .claude/env.claude

# Edit with your preferred settings
vim .claude/env.claude
```

### Configuration Keys

| Category | Key | Default | Description |
|----------|-----|---------|-------------|
| **Ops** | `OPS_DISCOVERY_TIMEOUT` | `30000` | Discovery tool timeout (ms) |
| **Ops** | `OPS_MAX_CONCURRENT` | `5` | Max parallel discovery tools |
| **Ops** | `OPS_ENABLE_*` | `true` | Enable/disable discovery backends |
| **Ops** | `OPS_APPROVAL_TTL_MINUTES` | `60` | Approval plan TTL |
| **Observability** | `LOG_LEVEL` | `info` | Log verbosity (debug/info/warn/error) |
| **Observability** | `LOG_DIR` | `.claude/logs` | Log output directory |
| **Observability** | `MCP_REQUEST_LOGGING` | `false` | Log MCP server requests |
| **Cache** | `CACHE_BACKEND` | `sqlite` | Cache backend (sqlite/redis/both) |
| **Cache** | `CACHE_DB_PATH` | `.claude/cache/cache.db` | Cache database path |
| **Cache** | `CACHE_DEFAULT_TTL` | `300` | Default cache TTL (seconds) |
| **Paths** | `CTAGS_PATH` | (auto-detect) | Override ctags binary path |
| **Paths** | `RG_PATH` | (auto-detect) | Override ripgrep binary path |
| **Paths** | `GEMINI_PATH` | (auto-detect) | Override gemini binary path |
| **Features** | `ENABLE_VOICE_NOTIFY` | `true` | Voice notifications (macOS) |
| **Features** | `ENABLE_REPO_MAP` | `true` | Repo map generation |
| **Features** | `REDACT_PARTIAL` | `false` | Partial secret redaction |

### Infrastructure Connection Keys

The following keys are for **external infrastructure connections** and should be treated as **SECRETS**. These are automatically loaded by MCP servers via the JavaScript `env-loader.js` module.

| Key | Purpose | Used By | Format | Security Level |
|-----|---------|---------|--------|----------------|
| `KUBECONFIG` | Kubernetes cluster config path | `ops_discover_k8s` | File path | **SECRET** |
| `ARGOCD_SERVER` | Argo CD server URL | `ops_discover_argocd` | `argocd.example.com` | Public |
| `ARGOCD_AUTH_TOKEN` | Argo CD auth token | `ops_discover_argocd` | Token string | **SECRET** |
| `DATABASE_URL` | PostgreSQL connection string | `ops_discover_postgres` | `postgresql://user:pass@host:port/db` | **SECRET** |
| `SUPABASE_PROJECT_REF` | Supabase project reference ID | `ops_discover_supabase` | `abcdefghijklm` | Public |
| `SUPABASE_ACCESS_TOKEN` | Supabase API access token | `ops_discover_supabase` | Token string | **SECRET** |
| `AWS_ACCESS_KEY_ID` | AWS access key | `ops_discover_s3` | `AKIA...` | **SECRET** |
| `AWS_SECRET_ACCESS_KEY` | AWS secret key | `ops_discover_s3` | Key string | **SECRET** |
| `AWS_DEFAULT_REGION` | AWS region | `ops_discover_s3` | `us-east-1` | Public |
| `GITHUB_TOKEN` | GitHub personal access token | `ops_discover_github` | `ghp_...` | **SECRET** |
| `REDIS_URL` | Redis connection URL | `ops_discover_redis` | `redis://[user:pass@]host:port[/db]` | **SECRET** |

**IMPORTANT SECURITY NOTES:**

- These keys are **automatically redacted** from all MCP tool output per `docs/policy/secrets-and-env.md`
- **DO NOT** commit `.claude/env.claude` with real values
- **USE** environment-specific files (`.claude/env.claude.local`) for production
- **ROTATE** credentials every 90 days
- See [Secret Management](#secret-management) section for details on obtaining each credential

### How It Works

**Bash Layer** (for factory scripts):

Factory scripts automatically source `.claude/env.claude` on startup if the file exists. Loading is:
- **Silent** -- no output is produced during loading
- **Conditional** -- scripts work normally without the file
- **Safe** -- trace mode (`set -x`) is suppressed during sourcing to prevent value leakage

**JavaScript Layer** (for MCP servers):

All 7 MCP servers load environment variables using the `env-loader.js` module:
```javascript
import { loadClaudeEnv } from "./lib/env-loader.js";
loadClaudeEnv();
```

The loader:
- Searches for `.claude/env.claude` or `.claude.env` (fallback)
- Parses KEY=VALUE format with quote support
- **Never overwrites** existing `process.env` values (security)
- **Never logs** variable names or values (security)
- Returns gracefully on error (never throws)

**Search Order:**
1. `.claude/env.claude` (primary)
2. `.claude.env` (fallback for compatibility)

Factory scripts automatically source `.claude/env.claude` on startup if the file exists. Loading is:
- **Silent** -- no output is produced during loading
- **Conditional** -- scripts work normally without the file
- **Safe** -- trace mode (`set -x`) is suppressed during sourcing to prevent value leakage

### Security Note

`.claude/env.claude` is gitignored and will not be committed. The sample file (`.claude/env.claude.sample`) contains only non-secret defaults and placeholders. **Never put API keys, passwords, tokens, or connection strings in this file** -- use `.env.local` for those (see [Secret Management](#secret-management)).

### LIGHT Mode: Environment Auto-Loading

**In LIGHT mode, Claude automatically loads environment configuration before running Bash or MCP commands that need config.**

#### Load Order
1. `.claude/env.claude` (base configuration)
2. `.claude/env.claude.local` (secrets and overrides)

#### The DATABASE_URL Interpolation Pitfall

**Problem:** If you set `DATABASE_URL` in `.claude/env.claude` using shell variable interpolation:
```bash
# In .claude/env.claude
POSTGRES_USER=myuser
POSTGRES_HOST=localhost
POSTGRES_PORT=5432
POSTGRES_DB=mydb
# ⚠️ This will NOT work if POSTGRES_PASSWORD is in .local file
DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST}:${POSTGRES_PORT}/${POSTGRES_DB}"
```

When this file is sourced, `${POSTGRES_PASSWORD}` is **empty** (it's defined in `.claude/env.claude.local` which loads AFTER).

**Solution:** Use `.claude/scripts/load-env-safe.sh` which:
1. Sources both files in order
2. **Rebuilds** `DATABASE_URL` AFTER loading `.claude/env.claude.local`
3. Ensures all interpolated variables are set

#### Usage Pattern

**Before any Bash/MCP command needing config:**
```bash
# Source the safe loader
. .claude/scripts/load-env-safe.sh

# Now DATABASE_URL is correctly built with secrets loaded
psql "$DATABASE_URL" -c 'SELECT version();'
```

**Output (presence only, no values):**
```
✓ Env loaded from: .claude/env.claude .claude/env.claude.local
✓ DATABASE_URL: set
✓ POSTGRES_PASSWORD: set
```

#### Key Points

- **LIGHT mode uses this loader by default** before DB/infra operations
- Secrets are **never printed** (only "set" or "not set" confirmation)
- Works for all MCP ops tools requiring `DATABASE_URL`, `REDIS_URL`, etc.
- If loader finds no env files, commands still work (graceful degradation)

---

## Environment Bootstrap

### What is `bootstrap-env.sh`?

A safe environment variable scaffolding tool that:
- Detects project types (Node.js, Next.js, Supabase, Docker, K8s)
- Creates `.env.local` files with **keys only** (no values)
- Never writes real secrets to files
- Redacts output to prevent accidental leakage

### Usage

#### Basic Usage

```bash
# Scan and bootstrap entire repo
bash .claude/scripts/bootstrap-env.sh
```

**Output:**
```
ℹ Bootstrap Environment Variables

ℹ Scanning for project roots in: /Users/you/Claude
ℹ Found 3 project root(s)

ℹ Creating .env.local files...

✓ Created: /Users/you/Claude/apps/web/.env.local (types: node nextjs)
✓ Created: /Users/you/Claude/supabase/.env.local (types: supabase)
⚠ Skipped: /Users/you/Claude/infra/.env.local (already exists, use --force to overwrite)

ℹ Summary: 2 created, 1 skipped

⚠ IMPORTANT: .env.local files have EMPTY values
⚠ Fill in secrets manually. See docs/INSTALL.md for guidance.
⚠ NEVER commit .env.local files to version control.
```

#### Flags

| Flag | Description | Example |
|------|-------------|---------|
| `--dry-run` | Print planned actions without creating files | `bash bootstrap-env.sh --dry-run` |
| `--force` | Overwrite existing `.env.local` files | `bash bootstrap-env.sh --force` |
| `--project PATH` | Bootstrap a specific project root only | `bash bootstrap-env.sh --project apps/web` |
| `--format FORMAT` | Output format: `dotenv` (default) or `yaml` | `bash bootstrap-env.sh --format yaml` |
| `--verbose` | Show detailed scanning output | `bash bootstrap-env.sh --verbose` |
| `-h, --help` | Show help message | `bash bootstrap-env.sh --help` |

#### Examples

**Dry Run (Recommended First Step):**
```bash
bash .claude/scripts/bootstrap-env.sh --dry-run
```

**Force Overwrite (Update Templates):**
```bash
bash .claude/scripts/bootstrap-env.sh --force
```

**Specific Project:**
```bash
bash .claude/scripts/bootstrap-env.sh --project apps/web
```

**Verbose Output:**
```bash
bash .claude/scripts/bootstrap-env.sh --verbose
```

### What Gets Created?

For each detected project root, a `.env.local` file is created with empty values:

**Example: Next.js Project**

File: `apps/web/.env.local`

```bash
# .env.local — Local environment variables (DO NOT COMMIT)
# Generated by bootstrap-env.sh on 2026-02-10
# Project types detected: node nextjs
#
# SECURITY: Fill in values manually. NEVER commit this file to git.
# See docs/INSTALL.md for where to store secrets securely.

# Database
DATABASE_URL=

# Node.js / Next.js
NODE_ENV=development
PORT=3000

# Supabase
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=

# Kubernetes / Argo CD
KUBECONFIG=
ARGOCD_SERVER=
ARGOCD_USERNAME=
ARGOCD_PASSWORD=

# GitHub
GITHUB_REPO=
GITHUB_AUTH_MODE=ssh
GITHUB_SSH_KEY_PATH=~/.ssh/id_ed25519

# Cache
REDIS_URL=
CACHE_BACKEND=sqlite
```

---

## Secret Management

### General Principles

1. **Never commit secrets to git** — Use `.env.local` (gitignored)
2. **Rotate secrets regularly** — Every 90 days recommended
3. **Least-privilege access** — Don't reuse admin keys for dev
4. **Prefer managed secrets** — 1Password, AWS Secrets Manager, Vault
5. **One secret per environment** — Separate dev/staging/prod secrets

### Where to Store Secrets

#### 🔐 KUBECONFIG (Kubernetes Config)

**Recommended:** Shell export or direnv (NOT `.env` file)

```bash
# Add to ~/.bashrc or ~/.zshrc:
export KUBECONFIG="$HOME/.kube/config"

# Or use direnv (.envrc):
export KUBECONFIG="/path/to/project-kubeconfig"
```

**Getting the Config:**
```bash
# From cluster admin
kubectl config view --raw > ~/.kube/my-cluster-config

# Merge with existing config
export KUBECONFIG=$HOME/.kube/config:$HOME/.kube/my-cluster-config
kubectl config view --flatten > ~/.kube/merged-config
```

#### 🔐 ARGOCD_SERVER / ARGOCD_PASSWORD (Argo CD)

**Recommended:** Use `argocd login` (stores in local config)

```bash
# Login (interactive)
argocd login argocd.example.com

# Login with credentials (less secure)
argocd login argocd.example.com --username admin --password 'your-password'
```

**Why NOT `.env`:**
- Argo CD CLI stores tokens in `~/.argocd/config` (encrypted)
- Storing passwords in plaintext `.env` is a security risk

**If you MUST use `.env`:**
```bash
# .env.local (NOT RECOMMENDED)
ARGOCD_SERVER=argocd.example.com
ARGOCD_USERNAME=admin
ARGOCD_PASSWORD='your-password'  # ⚠️ INSECURE
```

#### 🔐 DATABASE_URL (PostgreSQL)

**Recommended:** `.env.local` OR `~/.pgpass`

**Option 1: .env.local (for app code)**
```bash
# .env.local
DATABASE_URL=postgres://user:password@localhost:5432/mydb
```

**Option 2: ~/.pgpass (for CLI tools like `psql`)**
```bash
# ~/.pgpass (chmod 600)
localhost:5432:mydb:user:password
```

**Getting the URL:**
```bash
# From Supabase dashboard
# Project Settings → Database → Connection String (URI)

# From local PostgreSQL
psql -U postgres -c "SELECT current_database(), current_user;"
```

#### 🔐 SUPABASE_URL / SUPABASE_ANON_KEY / SUPABASE_SERVICE_ROLE_KEY

**Recommended:** `.env.local` (public keys) + server-side only (service role)

**Getting Keys:**
1. Go to [Supabase Dashboard](https://app.supabase.com)
2. Select your project
3. Settings → API

**Public Keys (safe for frontend):**
```bash
# .env.local
NEXT_PUBLIC_SUPABASE_URL=https://abcdefgh.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Service Role Key (SECRET — server-side only):**
```bash
# .env.local (NEVER expose to frontend)
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

⚠️ **WARNING:** Service role key **bypasses Row Level Security**. Never use in frontend code.

#### 🔐 GITHUB_TOKEN / GITHUB_SSH_KEY_PATH (GitHub Auth)

**Recommended:** `gh auth login` OR SSH agent (NOT `.env` file)

**Option 1: GitHub CLI (recommended)**
```bash
# Login with GitHub CLI
gh auth login

# Verify
gh auth status
```

**Option 2: SSH Agent (recommended)**
```bash
# Generate SSH key (if you don't have one)
ssh-keygen -t ed25519 -C "your_email@example.com"

# Add to SSH agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Add public key to GitHub
# Settings → SSH and GPG keys → New SSH key
cat ~/.ssh/id_ed25519.pub
```

**Option 3: Personal Access Token (NOT RECOMMENDED)**
```bash
# .env.local (INSECURE)
GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

⚠️ **WARNING:** Never store SSH private keys in `.env` files. Use SSH agent.

#### 🔐 REDIS_URL (Redis Cache)

**Recommended:** `.env.local`

```bash
# .env.local
REDIS_URL=redis://localhost:6379/0

# With authentication
REDIS_URL=redis://:password@localhost:6379/0

# Redis Cloud / Upstash
REDIS_URL=redis://default:xxxxx@redis-12345.upstash.io:6379
```

**Getting the URL:**
```bash
# Local Redis
redis-cli ping  # Should return PONG

# Upstash (Redis Cloud)
# Dashboard → Database → Connection String
```

---

## Verification

### 1. Health Check

```bash
bash .claude/scripts/health-check.sh
```

**Expected Output:**
```
✓ Node.js installed (v20.x.x)
✓ npm installed (v10.x.x)
✓ git installed (v2.x.x)
✓ MCP dependencies installed
✓ All MCP servers registered
✓ .gitignore includes .env.local
```

### 2. Run Tests

```bash
# Bootstrap tests
bash .claude/scripts/test-bootstrap-env.sh

# Ops MCP tests
bash .claude/scripts/test-ops-stage4.sh
```

**Expected Output:**
```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Test Results: bootstrap-env.sh E2E Tests
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Total Tests:  12
Passed:       12
Failed:       0
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
✓ All tests passed
```

### 3. Check .env.local Files

```bash
# List all .env.local files
find . -name ".env.local" -type f

# Show keys (not values)
cat apps/web/.env.local | grep -E "^[A-Z_]+=" | cut -d'=' -f1
```

### 4. Verify Git Ignore

```bash
# Check .gitignore
cat .gitignore | grep "env.local"

# Test: Create a fake .env.local
touch test.env.local

# Verify it's ignored
git status | grep "test.env.local"  # Should NOT appear
rm test.env.local
```

---

## Troubleshooting

### Issue: `.env.local` Not Created

**Symptoms:**
- Bootstrap script runs but no `.env.local` files created
- "Found 0 project root(s)" message

**Causes:**
- No detectable project roots (no `package.json`, `docker-compose.yml`, etc.)
- Scan depth too shallow
- Running from wrong directory

**Solutions:**

1. **Verify project structure:**
   ```bash
   ls -la apps/web/package.json
   ls -la supabase/config.toml
   ```

2. **Run verbose mode:**
   ```bash
   bash .claude/scripts/bootstrap-env.sh --verbose
   ```

3. **Check scan depth:**
   ```bash
   # Default max depth is 4
   # Edit bootstrap-env.sh and increase MAX_DEPTH if needed
   ```

4. **Manual creation:**
   ```bash
   cp .env.example apps/web/.env.local
   ```

### Issue: "Permission Denied" Error

**Symptoms:**
- `bash: ./bootstrap-env.sh: Permission denied`

**Solution:**
```bash
chmod +x .claude/scripts/bootstrap-env.sh
```

### Issue: Script Hangs During Scan

**Symptoms:**
- Bootstrap script runs for >30 seconds
- No output, appears frozen

**Causes:**
- Large `node_modules` or `dist` directories
- Scan timeout too high
- Disk I/O bottleneck

**Solutions:**

1. **Use `--project` flag:**
   ```bash
   bash .claude/scripts/bootstrap-env.sh --project apps/web
   ```

2. **Reduce scan limits** (edit `bootstrap-env.sh`):
   ```bash
   MAX_DEPTH=2
   MAX_FILES=5000
   SCAN_TIMEOUT=10
   ```

3. **Exclude large directories:**
   ```bash
   # Already excluded: node_modules, .git, dist, build, .next, .cache
   # Add more in find command if needed
   ```

### Issue: Secrets Leaked in Output

**Symptoms:**
- Console output shows `DATABASE_URL=postgres://user:password@...`
- Raw secrets visible in logs

**Solution:**

1. **Check redaction function:**
   ```bash
   grep -A20 "redact_output" .claude/scripts/bootstrap-env.sh
   ```

2. **Test redaction:**
   ```bash
   export DATABASE_URL="postgres://user:secret@host/db"
   bash .claude/scripts/bootstrap-env.sh --dry-run 2>&1 | grep "secret"
   # Should NOT show "secret"
   ```

3. **Report issue:**
   - If secrets leak, file a bug immediately
   - Rotate affected secrets

### Issue: `.env.local` Already Exists

**Symptoms:**
- "Skipped: .env.local (already exists)" message

**Solution:**

1. **Use `--force` flag:**
   ```bash
   bash .claude/scripts/bootstrap-env.sh --force
   ```

2. **Manual update:**
   ```bash
   # Backup existing file
   cp apps/web/.env.local apps/web/.env.local.backup

   # Edit manually
   vim apps/web/.env.local
   ```

### Issue: Wrong Project Type Detected

**Symptoms:**
- Supabase keys added to non-Supabase project
- K8s keys added to simple Node.js app

**Cause:**
- Detection heuristics too broad
- Multiple project markers in same directory

**Solution:**

1. **Check detection logic:**
   ```bash
   # See what types are detected
   bash .claude/scripts/bootstrap-env.sh --dry-run --verbose
   ```

2. **Manual template:**
   ```bash
   # Use project-specific template
   cp .claude/templates/env/nextjs.env apps/web/.env.local
   ```

3. **Edit generated file:**
   ```bash
   # Remove unwanted keys
   vim apps/web/.env.local
   ```

---

## Secret Rotation

### When to Rotate Secrets

- **Every 90 days** (recommended)
- **Immediately if leaked** (committed to git, exposed in logs)
- **When employee leaves** (revoke their access)
- **After security incident**

### How to Rotate

#### 1. Database Passwords

```bash
# PostgreSQL
psql -U postgres -d mydb -c "ALTER USER myuser PASSWORD 'new-password';"

# Update .env.local
vim .env.local
# Change: DATABASE_URL=postgres://myuser:new-password@...
```

#### 2. Supabase Keys

```bash
# Cannot rotate ANON key (public, rate-limited)
# To rotate SERVICE_ROLE key:
# 1. Go to Supabase Dashboard → Settings → API
# 2. Click "Reset service_role key"
# 3. Copy new key to .env.local
```

#### 3. GitHub Personal Access Tokens

```bash
# 1. Go to https://github.com/settings/tokens
# 2. Find old token, click "Delete"
# 3. Generate new token with same scopes
# 4. Update .env.local (or re-run `gh auth login`)
```

#### 4. Argo CD Passwords

```bash
# Reset admin password
argocd account update-password

# Update .env.local (if used)
vim .env.local
# Change: ARGOCD_PASSWORD='new-password'
```

### If Secrets Leak (Committed to Git)

**IMMEDIATE ACTIONS:**

1. **Rotate ALL affected secrets** (within 1 hour)
2. **Revoke compromised tokens/keys**
3. **Audit access logs** for unauthorized use
4. **Notify security team** (if enterprise)

**GIT CLEANUP:**

```bash
# Option 1: Remove from history (dangerous - rewrites history)
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch .env.local" \
  --prune-empty --tag-name-filter cat -- --all

# Option 2: BFG Repo-Cleaner (safer)
brew install bfg
bfg --delete-files .env.local
git reflog expire --expire=now --all
git gc --prune=now --aggressive

# Force push (WARNING: breaks forks)
git push origin --force --all
git push origin --force --tags
```

**PREVENTION:**

1. **Update `.gitignore`:**
   ```bash
   echo ".env.local" >> .gitignore
   git add .gitignore
   git commit -m "chore: ensure .env.local is ignored"
   ```

2. **Add pre-commit hook:**
   ```bash
   # .git/hooks/pre-commit
   if git diff --cached --name-only | grep -q "\.env\.local"; then
     echo "ERROR: Attempting to commit .env.local"
     exit 1
   fi
   ```

3. **Enable secret scanning** (GitHub):
   - Settings → Code security and analysis → Secret scanning

---

## Best Practices

### ✅ DO

- ✅ Use `.env.local` for local development secrets
- ✅ Rotate secrets every 90 days
- ✅ Use least-privilege access (separate dev/prod secrets)
- ✅ Store production secrets in managed services (AWS Secrets Manager, Vault)
- ✅ Use `gh auth login` or SSH agent for GitHub auth
- ✅ Use `argocd login` for Argo CD auth
- ✅ Keep `.env.local` permissions at 600 (`chmod 600 .env.local`)
- ✅ Review `.gitignore` regularly

### ❌ DON'T

- ❌ **Never commit** `.env.local` to git
- ❌ **Never store** SSH private keys in `.env` files
- ❌ **Never reuse** admin credentials for development
- ❌ **Never share** `.env.local` files (even in Slack, email)
- ❌ **Never hardcode** secrets in source code
- ❌ **Never use** the same secret across environments (dev/prod)
- ❌ **Never ignore** secret scanning alerts

---

## Additional Resources

- [Security Best Practices](../policy/mcp-security.md)
- [Ops MCP Tools](../policy/ops-tools.md)
- [Troubleshooting Guide](../TROUBLESHOOTING.md)
- [Phase 5.5 Completion Report](../tasks/reports/PHASE_5_5_COMPLETE.md)

---

**Last Updated:** 2026-02-10
**Phase:** 5.5 — Project Bootstrap + Safe Env Scaffolding
