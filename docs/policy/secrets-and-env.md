# SECRETS AND ENVIRONMENT PROTECTION POLICY

## PURPOSE

This policy defines comprehensive protection rules for secrets, credentials, and sensitive environment variables throughout the software factory. It establishes patterns for detecting secrets, rules for their handling, and a unified redaction interface used by all factory components.

**Core Principle:** Secrets MUST NEVER appear in logs, cache databases, commit messages, reports, or any persistent storage outside their designated secure locations (.env files, credential stores).

---

## SCOPE

This policy applies to:
- All factory agents (Manager, Analyst, Researcher, Architect, Developer, Reviewer, Tester, Reporter)
- All MCP tools and wrapper scripts
- Cache system (context.db, repo-map.txt)
- Logging and observability infrastructure
- Git operations and commit automation
- Report generation

---

## SECRET PATTERNS — DENYLIST

### Environment Variable Patterns

The following environment variable name patterns are classified as secrets and MUST be redacted:

**Token Patterns:**
- `*_TOKEN`
- `*TOKEN*` (if not explicitly allowlisted)
- `AUTH_TOKEN`
- `API_TOKEN`
- `ACCESS_TOKEN`
- `REFRESH_TOKEN`
- `GITHUB_TOKEN`
- `GITLAB_TOKEN`
- `ANTHROPIC_API_KEY`

**Secret Patterns:**
- `*_SECRET`
- `*SECRET*`
- `CLIENT_SECRET`
- `SESSION_SECRET`
- `JWT_SECRET`
- `WEBHOOK_SECRET`

**Key Patterns:**
- `*_KEY`
- `*KEY*` (if not explicitly allowlisted)
- `API_KEY`
- `PRIVATE_KEY`
- `PUBLIC_KEY` (context-dependent)
- `SUPABASE_ANON_KEY`
- `SUPABASE_SERVICE_ROLE_KEY`
- `ENCRYPTION_KEY`

**Password Patterns:**
- `*_PASSWORD`
- `*PASSWORD*`
- `*_PASS`
- `*PASS*`
- `DB_PASSWORD`
- `POSTGRES_PASSWORD`
- `MYSQL_PASSWORD`
- `REDIS_PASSWORD`
- `PGPASSWORD`
- `PGPASSFILE`

**Database Connection Strings:**
- `DATABASE_URL`
- `DB_URL`
- `MONGODB_URI`
- `REDIS_URL`
- `POSTGRES_URL`
- `MYSQL_URL`
- `CONNECTION_STRING`

**Cloud Provider Credentials:**
- `AWS_*` (all AWS variables containing credentials)
  - `AWS_ACCESS_KEY_ID`
  - `AWS_SECRET_ACCESS_KEY`
  - `AWS_SESSION_TOKEN`
  - `AWS_SECURITY_TOKEN`
- `GCP_*` (all GCP variables containing credentials)
  - `GCP_SERVICE_ACCOUNT_KEY`
  - `GOOGLE_APPLICATION_CREDENTIALS`
- `AZURE_*` (all Azure variables containing credentials)
  - `AZURE_CLIENT_ID`
  - `AZURE_CLIENT_SECRET`
  - `AZURE_TENANT_ID`
- `SUPABASE_*_KEY`
  - `SUPABASE_ANON_KEY`
  - `SUPABASE_SERVICE_ROLE_KEY`

**Allowlist Exceptions:**

The following patterns are NOT secrets despite matching denylist patterns:
- `NODE_ENV`
- `PATH`
- `HOME`
- `USER`
- `SHELL`
- `LANG`
- `LC_*`
- `DISPLAY`
- `TERM`
- `PWD`
- `OLDPWD`
- `SHLVL`
- `EDITOR`
- `PAGER`

---

## FILE PATTERNS — SECRET FILES

### Secret File Extensions

Files with the following extensions are classified as secret files and MUST NOT be:
- Logged in full
- Cached without redaction
- Included in repository maps
- Committed to version control (unless explicitly encrypted/sealed)

**Extensions:**
- `.env`
- `.env.*` (e.g., `.env.local`, `.env.production`)
- `.pem`
- `.key`
- `.p12`
- `.pfx`
- `.crt` (context-dependent)
- `.csr` (context-dependent)
- `.cer`
- `.der`
- `.jks`
- `.keystore`

**File Names:**
- `.env`
- `.env.local`
- `.env.development`
- `.env.test`
- `.env.production`
- `.env.staging`
- `credentials.json`
- `service-account.json`
- `*-credentials.json`
- `secrets.yml`
- `secrets.yaml`
- `vault-pass`
- `id_rsa`
- `id_dsa`
- `id_ed25519`
- `*.pem`
- `*.key`

### .gitignore Protection

Secret files MUST be listed in `.gitignore`. The factory MUST verify this before any git commit operation.

**Standard .gitignore patterns for secrets:**
```
.env
.env.*
*.pem
*.key
*.p12
*.pfx
credentials.json
service-account.json
secrets.yml
secrets.yaml
```

---

## REDACTION RULES

### Rule 1: Environment Variable Values

When logging or caching environment variable names and values:
- IF the variable name matches a denylist pattern → replace the value with `***REDACTED***`
- IF the variable name is on the allowlist → include the value as-is
- IF uncertain → redact (fail-safe default)

**Example:**
```
DATABASE_URL=postgres://user:pass@localhost:5432/db  →  DATABASE_URL=***REDACTED***
NODE_ENV=production                                  →  NODE_ENV=production
API_TOKEN=abc123                                     →  API_TOKEN=***REDACTED***
```

### Rule 2: File Content Redaction

When reading or caching secret files:
- IF the file matches secret file patterns → redact all lines containing `=` by replacing the value after `=` with `***REDACTED***`
- IF the file is a certificate or key file → replace entire content with `[REDACTED SECRET FILE: <filename>]`
- IF the file is JSON containing secrets → redact values of secret-like keys

**Example (.env file):**
```
# Original
DATABASE_URL=postgres://user:pass@localhost:5432/db
NODE_ENV=production
API_TOKEN=abc123

# Redacted
DATABASE_URL=***REDACTED***
NODE_ENV=***REDACTED***
API_TOKEN=***REDACTED***
```

**Example (JSON credential file):**
```json
{
  "type": "service_account",
  "project_id": "my-project",
  "private_key": "-----BEGIN PRIVATE KEY-----\nMIIE...",
  "client_email": "service@my-project.iam.gserviceaccount.com"
}
```
Becomes:
```
[REDACTED SECRET FILE: service-account.json]
```

### Rule 3: Stream Redaction

When processing command output streams (stdout/stderr):
- Scan each line for patterns matching secret values (e.g., `export VAR=value`, `VAR=value`, `"api_key": "value"`)
- Replace matched secret values with `***REDACTED***`
- Preserve structure and readability

### Rule 4: Partial Redaction for Debugging

For debugging purposes, the first 4 characters of a secret MAY be preserved, followed by `***`:
```
API_TOKEN=abc123def456  →  API_TOKEN=abc1***
```

This is OPTIONAL and should only be enabled via explicit configuration flag (`REDACT_PARTIAL=true`).

---

## REDACTION INTERFACE

### Primary Tool: `.claude/scripts/redact.sh`

All factory components MUST use the unified redaction script located at `.claude/scripts/redact.sh`.

**Interface:**

```bash
# Source the script to access redaction functions
source .claude/scripts/redact.sh

# Function 1: Stream redaction
redact_stream < input.txt > output.txt
echo "API_KEY=secret123" | redact_stream

# Function 2: Check if a file is a secret file
if is_secret_file "/path/to/.env"; then
  echo "This is a secret file"
fi

# Function 3: Redact a file and output to stdout
redact_file "/path/to/.env"
```

**Configuration:**

Environment variables that control redaction behavior:
- `REDACT_PARTIAL=true` — Enable partial redaction (first 4 chars visible)
- `REDACT_DISABLED=true` — Disable redaction (for debugging only, NOT for production)

---

## INTEGRATION POINTS

### 1. Cache System (cache.sh)

**Requirements:**
- `cache_get` and `cache_set` MUST call `redact_stream` before writing to context.db
- `cache_file` MUST check `is_secret_file` and refuse to cache secret files
- Repository map generation MUST exclude secret files

**Implementation:**
```bash
cache_set "key" "$(echo "$value" | redact_stream)"
cache_file "$path" "$(is_secret_file "$path" && echo "[REDACTED]" || cat "$path" | redact_stream)"
```

### 2. MCP Tools

**Tools that MUST apply redaction:**
- `factory-tools:git_repo_diff` — Redact diff content if it includes secret files
- `factory-fs:fs_read_range` — Redact output if reading secret files
- `factory-git:git_status` — Safe (only file paths, no content)
- `factory-git:git_log_oneline` — Safe (no secret content)

**Integration:**
MCP server implementations MUST wrap output through `redact_stream` before returning to the agent.

### 3. Logging (observability.md)

**Requirements:**
- All log entries MUST pass through `redact_stream` before writing to disk
- Token ledger MUST NOT log command output containing secrets
- Performance metrics MAY log file paths but MUST NOT log file content

**Implementation:**
```bash
log_entry "$(echo "$message" | redact_stream)"
```

### 4. Git Automation (git-automation.md)

**Requirements:**
- Pre-commit hook MUST verify no secret files are staged (unless explicitly allowed)
- Commit messages MUST NOT contain secret values
- `git diff` output used in commit message generation MUST be redacted

**Implementation:**
```bash
# In pre-commit hook
for file in $(git diff --cached --name-only); do
  if is_secret_file "$file"; then
    echo "ERROR: Attempting to commit secret file: $file"
    exit 1
  fi
done
```

### 5. Agent Spawning (spawn-templates.md)

**Requirements:**
- Evidence Packs passed to agents MUST be redacted
- File content passed as context MUST be redacted if from secret files
- Budget Blocks MUST NOT contain secret values

**Implementation:**
Manager MUST call `redact_stream` on all context before spawning agents.

### 6. Report Generation (Reporter agent)

**Requirements:**
- All reports (TASK_REPORT.md, BATCH_REPORT.md) MUST NOT contain secrets
- Code snippets included in reports MUST be redacted if they contain secret patterns
- Notify_say summaries MUST NOT contain secrets

**Implementation:**
Reporter agent MUST verify all output through redaction before writing reports.

---

## ENFORCEMENT

### Enforcement Level: CRITICAL

Violation of this policy constitutes a **CRITICAL ERROR** that MUST halt the pipeline.

### Automated Checks

**Pre-Flight Checks (health-check.sh):**
1. Verify `redact.sh` exists and is executable
2. Verify `.gitignore` contains secret file patterns
3. Test redaction functions with sample input

**Runtime Checks:**
1. Before any cache write → verify redaction applied
2. Before any git commit → verify no secret files staged
3. Before any report write → verify redaction applied
4. Before any notify_say → verify redaction applied

### Manual Review Gates

**Reviewer Agent Responsibilities:**
- Scan all code changes for hardcoded secrets
- Verify `.env.example` files do NOT contain real secrets
- Ensure secret files are in `.gitignore`
- Check that new environment variables follow naming conventions (no secrets in code)

**Reporter Agent Responsibilities:**
- Final scan of all report content for secret patterns
- Verify redaction applied to any environment variable listings
- Check that no secret file paths are exposed with content

---

## FAILURE RESPONSE

### If Secrets Are Detected in Output

**Immediate Actions:**
1. HALT the current operation
2. Delete or redact the contaminated output
3. Log the incident (with redacted details)
4. Notify the Manager

**Recovery:**
1. Re-run the operation with redaction enabled
2. Verify redaction is working correctly
3. Audit recent operations for similar leaks
4. Update relevant policy if gap identified

### If Secrets Are Committed to Git

**Immediate Actions:**
1. DO NOT push to remote
2. Amend or rewrite the commit to remove secrets
3. Verify secrets are removed from git history
4. Rotate the compromised secrets

**If Secrets Are Pushed to Remote:**
1. Immediately rotate all exposed secrets
2. Use `git filter-branch` or BFG Repo-Cleaner to remove from history
3. Force-push corrected history
4. Notify all team members to re-clone

---

## TESTING

### Unit Tests

Test suite: `.claude/scripts/test-redact.sh` (to be created as part of add-test-suite.md runbook)

**Test Cases:**
1. Environment variable redaction
2. .env file redaction
3. JSON credential file redaction
4. Stream redaction with mixed content
5. Secret file detection
6. Allowlist exceptions
7. Partial redaction (if enabled)

### Integration Tests

Test cache.sh integration with redact.sh:
1. Cache a secret file → verify redaction applied
2. Cache an environment variable → verify redaction applied
3. Cache a non-secret file → verify no redaction

---

## CONFIGURATION EXAMPLES

### Sample .env.example

```bash
# Database
DATABASE_URL=postgres://username:password@localhost:5432/dbname

# API Keys
API_TOKEN=your_token_here
ANTHROPIC_API_KEY=your_api_key_here

# Non-secret configuration
NODE_ENV=development
PORT=3000
LOG_LEVEL=debug
```

### Sample .gitignore (secrets section)

```
# Secrets and environment files
.env
.env.*
!.env.example
*.pem
*.key
*.p12
*.pfx
credentials.json
service-account.json
secrets.yml
secrets.yaml
vault-pass
id_rsa
id_dsa
id_ed25519
```

---

## REVISION HISTORY

- **2026-02-10:** Initial policy (Phase 4, Task Group C)

---

**END OF POLICY**
