# CACHED TOOL ADOPTION POLICY

## PURPOSE

This policy defines when and how agents MUST use cached tool wrappers (`cached_rg`, `cached_git_diff`, `cached_file_list`) instead of direct tool calls. Cached wrappers eliminate redundant tool invocations within a task run by returning cached results when inputs and git HEAD have not changed.

---

## CACHED TOOL WRAPPERS

### Available Wrappers

| Wrapper | Wraps | Cache Key Strategy | Default TTL |
|---------|-------|-------------------|-------------|
| `cached_rg <pattern> [path]` | `rg` (ripgrep) | `tool:rg:<sha256(pattern + path + HEAD)>` | Until git HEAD changes |
| `cached_git_diff [base] [head]` | `git diff --name-status` | `tool:git_diff:<sha256(base + head + HEAD)>` | Until git HEAD changes |
| `cached_file_list [pattern]` | `git ls-files` / `find` | `tool:file_list:<sha256(pattern + HEAD)>` | Until git HEAD changes |

### Cache Key Fingerprint

All cached wrappers use a composite fingerprint:
```
sha256(tool_name + ":" + args + ":" + git_HEAD)
```

This ensures cache entries automatically become stale when:
- The git HEAD changes (new commits, checkouts, pulls)
- Different arguments are provided
- A different tool is called

---

## WHEN TO USE CACHED WRAPPERS

### MUST Use (Mandatory)

Agents MUST use cached wrappers when:

1. **Repeated searches within the same task** — If an agent needs to search for the same pattern more than once (e.g., finding usages, then verifying after implementation), use `cached_rg` for the second call
2. **File listing for scope verification** — When the Reviewer or Tester needs the file list that the Developer already generated, use `cached_file_list`
3. **Diff retrieval in implementation loop** — After the first iteration's diff is cached, subsequent iterations SHOULD use `cached_git_diff` for unchanged base/head pairs
4. **Evidence Pack assembly** — The Manager SHOULD use `cached_git_diff` when assembling the Evidence Pack across loop iterations (DIFF SUMMARY regeneration)

### MAY Use (Recommended)

Agents MAY use cached wrappers when:

1. **Cross-agent pattern discovery** — If the Analyst searched for a pattern, the Architect can benefit from the cached result
2. **Exploratory searches** — When exploring the codebase with broad patterns that are likely to be repeated

### MUST NOT Use (Prohibited)

Agents MUST NOT use cached wrappers when:

1. **Files have been modified since the cache entry** — After the Developer writes files, any cached search results covering those files are stale. The Manager MUST call `cache_invalidate_for_write` before agents use cached results
2. **Git HEAD has changed** — After commits, checkouts, or pulls, all cached tool output is automatically invalidated (fingerprint includes HEAD)
3. **Searching for secrets or credentials** — NEVER cache output from searches that may contain secrets (see Safety Constraints below)

---

## SAFETY CONSTRAINTS

### Never Cache Secrets

The following patterns MUST NOT be cached:

- Search results from `.env`, `.env.*`, `credentials.json`, `*.pem`, `*.key` files
- Search results matching patterns: `password`, `secret`, `token`, `api_key`, `private_key`
- Output from `git diff` that includes credential file changes

**Enforcement:** `cache_set` in `cache.sh` already validates content and rejects entries containing secret patterns. Additionally, the Manager MUST provide a "Files to ignore" list to agents.

### Files to Ignore

The Manager MUST provide each agent with a scoped ignore list to prevent accidental caching of sensitive content:

```
CACHED TOOL SAFETY — Files to ignore (do NOT cache results from these):
  .env, .env.*, credentials.json, *.pem, *.key, *.p12, *.pfx
  secrets/, .secrets/, config/secrets.*
```

### Scope Constraints

- **Tight file scopes:** When using `cached_rg`, always provide a specific path argument rather than searching the entire repository. This limits cache entries to relevant directories only.
- **Pattern specificity:** Prefer specific regex patterns over broad wildcards. `cached_rg "export function" "src/"` is better than `cached_rg "export" "."`.

---

## TTL DEFAULTS

| Cache Type | Default TTL | Invalidation Trigger |
|------------|------------|---------------------|
| `cached_rg` output | Until HEAD changes | File write in searched path, git HEAD change |
| `cached_git_diff` output | Until HEAD changes | Any git operation (commit, checkout, merge) |
| `cached_file_list` output | Until HEAD changes | File creation/deletion, git HEAD change |
| Redis hot-path | 5 minutes | Time-based expiry |

**TTL Override:** The Manager MAY set a shorter TTL for specific operations by invalidating cache entries at task boundaries (via `cache_invalidate_for_git_head_change` or `cache_invalidate_type "tool_output"`).

---

## AGENT SPAWN INTEGRATION

### Manager Responsibilities

1. **Inject cached tool instructions** into every Developer, Reviewer, and Tester spawn prompt:

```
CACHED TOOL POLICY:
  Prefer cached wrappers for repeated operations:
  - cached_rg <pattern> [path] — instead of raw rg for second+ searches
  - cached_git_diff [base] [head] — instead of raw git diff for Evidence Pack
  - cached_file_list [pattern] — instead of raw git ls-files for scope checks

  CACHED TOOL SAFETY — Files to ignore (do NOT cache results from these):
  .env, .env.*, credentials.json, *.pem, *.key, *.p12, *.pfx
  secrets/, .secrets/, config/secrets.*

  Use tight file scopes: always provide a path argument to cached_rg.
```

2. **Call invalidation hooks** after file modifications (see `docs/policy/orchestration.md`, Auto-Invalidation Hooks section)

3. **Track cache hit/miss** in the token ledger for observability

### Agent Responsibilities

1. **Check cache first** before making tool calls that may have been cached by prior agents
2. **Use tight scopes** — always provide path arguments to limit cache entries
3. **Never cache secret-containing results** — if search results include sensitive data, use raw tool calls
4. **Report cache usage** — include cache hit/miss stats in output when available

---

## VALIDATION

The following checks are enforced by `validate-policies.sh`:

1. `cached-tools.md` exists at `docs/policy/cached-tools.md`
2. `cache.sh` contains all three cached wrapper functions (`cached_rg`, `cached_git_diff`, `cached_file_list`)
3. Spawn templates reference CACHED TOOL POLICY (in Developer, Reviewer, Tester prompts)
4. `cache-hooks.sh` exists with invalidation functions

---

## CHANGELOG

| Version | Date       | Changes |
|---------|------------|---------|
| 1.0     | 2026-02-09 | Initial cached tool adoption policy |

---

**END OF POLICY**
