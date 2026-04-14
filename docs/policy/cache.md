# UNIVERSAL CONTEXT CACHE POLICY

## PURPOSE

This policy defines the Universal Context Cache system — a persistent, session-spanning knowledge layer that eliminates redundant file reads and accelerates agent spawning by pre-loading stable repository context.

**Design Goals:**
1. **Reduce token waste** — Stop re-reading unchanged files across agents and sessions
2. **Accelerate spawning** — Pre-load stable context (policies, runbooks, architecture) into agent prompts
3. **Preserve freshness** — Automatically invalidate cache entries when files change
4. **Enable adaptive learning** — Track which context is actually used vs. ignored
5. **Support offline operation** — All cache operations work without network connectivity

---

## CACHE ARCHITECTURE

### Storage Model

The cache uses **SQLite** as the primary store with **Redis** (optional) for hot-path acceleration:

```
.claude/cache/
├── cache.db            ← SQLite database (primary store)
├── repo-map.txt        ← Repository structure snapshot (regenerated on demand)
└── .gitignore          ← Excluded from version control
```

**SQLite Schema:**

```sql
CREATE TABLE cache_entries (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  key          TEXT NOT NULL UNIQUE,     -- e.g., "file:/path/to/file.md"
  value        TEXT NOT NULL,            -- file content or computed context
  type         TEXT NOT NULL,            -- "file" | "policy" | "repo_map" | "runbook"
  created_at   INTEGER NOT NULL,         -- Unix timestamp
  last_read    INTEGER NOT NULL,         -- Unix timestamp (updated on read)
  read_count   INTEGER DEFAULT 0,        -- How many times this entry was read
  file_mtime   INTEGER,                  -- File modification time (for invalidation)
  file_hash    TEXT,                     -- SHA-256 hash (for change detection)
  metadata     TEXT                      -- JSON blob (e.g., {"agent": "analyst", "phase": 1})
);

CREATE INDEX idx_key ON cache_entries(key);
CREATE INDEX idx_type ON cache_entries(type);
CREATE INDEX idx_last_read ON cache_entries(last_read);
```

**Key Naming Convention:**

- `file:<absolute_path>` — Raw file content (e.g., `file:/Users/kousha/.../CLAUDE.md`)
- `policy:<name>` — Policy file content (e.g., `policy:orchestration`)
- `runbook:<name>` — Runbook content (e.g., `runbook:add-mcp-server`)
- `repo_map` — Repository structure tree (singleton key)
- `spawn:<agent>:<phase>` — Computed spawn prompt context (e.g., `spawn:analyst:1`)

### Redis Integration (Optional)

If `redis-cli` is available, `.claude/scripts/cache.sh` MAY use Redis as a hot-path cache with **5-minute TTL**:

- **Reads:** Check Redis first → if miss, query SQLite → write to Redis
- **Writes:** Write to SQLite (source of truth) → write to Redis
- **Invalidation:** Delete from both SQLite and Redis

Redis keys use the same naming convention with a `factory:` prefix:
- `factory:file:/path/to/file.md`
- `factory:policy:orchestration`

**Fallback:** If Redis is unavailable, all operations fall back to SQLite transparently.

---

## CACHE LIFECYCLE

### 1. Cache Population (Proactive)

**When:** Phase 0 (Task Detection) — before spawning any agents

**What:** The Manager calls `cache_prime` to pre-load stable, high-value context:

```bash
source .claude/scripts/cache.sh

# Prime cache with core policies and runbooks
cache_prime "policies" "CLAUDE.md,docs/policy/*.md"
cache_prime "runbooks" ".claude/runbooks/*.md"
cache_prime "repo_map" "$(build_repo_map)"
```

**Priming Logic:**
- Read each file once, compute SHA-256 hash, store in SQLite
- If file already cached and hash matches → skip (no re-read)
- If hash differs → invalidate old entry, cache new content
- Update `read_count = 0`, `last_read = now()`

### 2. Cache Retrieval (Lazy)

**When:** Spawning an agent (Analyst, Architect, Developer, etc.)

**What:** The Manager injects a `CACHE CONTEXT` block into the agent's spawn prompt:

```markdown
CACHE CONTEXT (pre-loaded — do NOT re-read unless changed):
- CLAUDE.md (read 3 times, last: 2m ago)
- docs/policy/orchestration.md (read 5 times, last: 1m ago)
- docs/policy/spawn-templates.md (read 2 times, last: 5m ago)
- .claude/runbooks/add-mcp-server.md (read 1 time, last: 10m ago)
- Repository map (547 files, generated 3m ago)

FILES ALREADY READ: [See cache above]
```

**Agent Behavior:**
- Agents MUST NOT re-read files listed in `CACHE CONTEXT` unless `git_repo_diff` shows changes
- Agents MAY reference cached files by name when making decisions
- If a cached file is stale (changed since cache entry), agent MUST read fresh version

### 3. Cache Invalidation (Automatic)

**Triggers:**
1. **File modification:** After any Write/Edit operation, the Manager calls `cache_invalidate "file:<path>"`
2. **Batch completion:** After multi-task batch ends, invalidate all `file:*` entries (policies/runbooks stay cached)
3. **Manual flush:** `cache_flush` clears entire cache (used by `health-check.sh` on demand)

**Invalidation Rules:**
- **Per-file:** Remove single entry from SQLite and Redis
- **Per-type:** Remove all entries where `type = "file"` (preserves policies/runbooks)
- **Full flush:** `DELETE FROM cache_entries` (nuclear option)

### 4. Cache Metrics (Observability)

Every cache operation writes to `.claude/logs/factory.log` and updates the token ledger:

```json
{
  "timestamp": "2026-02-09T14:32:01Z",
  "event": "cache_hit",
  "key": "policy:orchestration",
  "bytes_saved": 8432,
  "read_count": 6,
  "last_read_ago_seconds": 120
}
```

**Metrics Tracked:**
- **Cache hit rate** — `hits / (hits + misses)`
- **Bytes saved** — Sum of `file_size` for all cache hits
- **Token savings** — Estimated tokens saved (bytes * 0.33)
- **Eviction count** — How many entries were invalidated

The Reporter includes cache metrics in the final report:

```markdown
## Cache Performance
- Hit rate: 78% (42 hits, 12 misses)
- Tokens saved: ~14,200 (via cached policies and repo map)
- Most-read: docs/policy/spawn-templates.md (8 reads)
```

---

## CACHE PRECHECK BLOCK

The Cache Precheck Block is a standardized metadata header that the Manager injects into every agent spawn prompt. It provides agents with visibility into cache operational state for debugging and observability purposes.

**Purpose:**
- Inform agents of cache availability (sqlite, redis, unavailable)
- Record Run ID for log correlation
- Provide warm cache statistics for context awareness
- Include decision memory context for adaptive optimization
- **NOT for agent action** — agents MUST NOT modify their behavior based on this block; it is for Reporter metrics and audit trail only

**Format:**
```
CACHE PRECHECK (operational — do NOT act on this, for Reporter metrics only):
  Run ID: <run_id>
  Git HEAD: <short_sha>
  Cache Backend: <sqlite | sqlite+redis | unavailable>
  Warm Stats: <N> files cached
  Decision Memory: <stats_json>
```

**Field Definitions:**
- **Run ID:** Value of `$CLAUDE_FACTORY_RUN_ID` (set by run-preflight.sh); format `YYYYMMDD-HHMMSS` or "unavailable" if not set
- **Git HEAD:** Short commit hash from `git rev-parse --short HEAD`; format 7-char hex or "unavailable" if git fails
- **Cache Backend:** One of:
  - `sqlite+redis` — Both SQLite and Redis are operational
  - `sqlite` — SQLite operational, Redis unavailable
  - `unavailable` — Cache system failed to initialize
- **Warm Stats:** Output of `cache_warm` function (e.g., "12 files cached"); reports how many files were pre-loaded into cache during Phase 0; "N/A" if cache unavailable
- **Decision Memory:** JSON output of `decision_memory_stats()` (e.g., `{"total_runs":42,"avg_tokens":45231,...}`); "N/A" if no prior runs or cache unavailable

**Example (Healthy Cache):**
```
CACHE PRECHECK (operational — do NOT act on this, for Reporter metrics only):
  Run ID: 20260209-143201
  Git HEAD: a1b2c3d
  Cache Backend: sqlite+redis
  Warm Stats: 12 files cached
  Decision Memory: {"total_runs":42,"avg_tokens":45231,"avg_loops":1.8,"avg_duration":124,"architect_skip_rate":23.8,"mode_breakdown":"MICRO-CHANGE:12 STANDARD:28 VERIFICATION:2"}
```

**Example (Degraded Cache):**
```
CACHE PRECHECK (operational — do NOT act on this, for Reporter metrics only):
  Run ID: 20260209-143201
  Git HEAD: a1b2c3d
  Cache Backend: sqlite
  Warm Stats: 12 files cached
  Decision Memory: N/A
```

**Example (Cache Unavailable):**
```
CACHE PRECHECK (operational — do NOT act on this, for Reporter metrics only):
  Run ID: 20260209-143201
  Git HEAD: a1b2c3d
  Cache Backend: unavailable
  Warm Stats: N/A
  Decision Memory: N/A
```

**Manager Responsibilities:**
1. **Generate precheck data** during Phase 0 (after Cache Bootstrap, before first agent spawn)
2. **Inject precheck block** into EVERY agent spawn prompt (after BUDGET BLOCK, before FILES ALREADY READ)
3. **Update Run ID** for each new task in multi-task runs (all other fields remain static for the batch)
4. **Pass precheck data to Reporter** for inclusion in EXECUTION METRICS section

**Agent Responsibilities:**
1. **Do NOT act on precheck data** — agents MUST NOT skip reads, change tool usage, or modify behavior based on cache backend state
2. **Ignore block during execution** — this block is metadata for observability, not operational guidance
3. **Reporter exception:** The Reporter MAY extract precheck data for inclusion in the EXECUTION METRICS section of the final report

**Integration with Other Policies:**
- **Cache Bootstrap (workflow.md):** Manager generates precheck data during Cache Bootstrap
- **Spawn Templates (spawn-templates.md):** All templates include CACHE PRECHECK block injection point
- **Observability (observability.md):** Reporter extracts precheck data for cache performance metrics
- **Decision Memory (cache.md, Section "Decision Memory"):** Reporter uses Decision Memory field for continuous improvement insights

---

## CACHE USAGE RULES

### Rule 32: Cache-Aware File Reads

**Applies to:** Manager, all agents

**Rule:**
Before reading any file, the Manager MUST check the cache:

```bash
content=$(cache_get "file:$filepath")
if [[ -n "$content" ]]; then
  # Use cached content
  echo "$content"
else
  # Cache miss — read file, populate cache
  content=$(cat "$filepath")
  cache_set "file:$filepath" "$content" "file" "$filepath"
  echo "$content"
fi
```

Agents receive cached content in their spawn prompts via `CACHE CONTEXT`. Agents MUST NOT re-read cached files unless:
1. `git_repo_diff` shows the file changed since cache entry
2. The file is not listed in `FILES ALREADY READ`

**Enforcement:**
- The Manager tracks which files are passed in `CACHE CONTEXT`
- If an agent reads a cached file unnecessarily, the Reviewer flags it as a policy violation

### Rule 33: Cache Invalidation After Edits

**Applies to:** Manager (auto), Developer (advisory)

**Rule:**
After any Write or Edit operation, the Manager MUST invalidate the cache entry:

```bash
# Example: Developer edited orchestration.md
cache_invalidate "file:/Users/kousha/.../docs/policy/orchestration.md"
cache_invalidate "policy:orchestration"  # Also invalidate typed key
```

**Behavior:**
- **Single-task:** Invalidate immediately after edit
- **Multi-task:** Batch invalidations, flush at task boundaries (onTaskEnd)

**Purpose:**
Prevents agents from reading stale cached content when files have changed mid-pipeline.

---

## REPOSITORY MAP

### Purpose

The repository map is a lightweight, human-readable directory tree cached as `repo_map` in SQLite. It provides agents with instant spatial awareness without scanning the filesystem.

**Generated by:** `.claude/scripts/build-repo-map.sh`

**Example Output:**

```
REPOSITORY MAP (generated 2026-02-09 14:32:01)
Total files: 547 | Tracked files: 512 | Git repo: yes

.
├── .claude/
│   ├── agents/ (9 files)
│   ├── mcp/ (7 files)
│   ├── runbooks/ (4 files)
│   └── scripts/ (8 files)
├── docs/
│   ├── policy/ (12 files)
│   └── tasks/
│       └── reports/ (3 files)
├── src/ (247 files)
├── tests/ (89 files)
├── CLAUDE.md
├── README.md
└── package.json

Key directories:
  Policies:  docs/policy/*.md (12 files)
  Runbooks:  .claude/runbooks/*.md (4 files)
  Agents:    .claude/agents/*.md (9 files)
  Scripts:   .claude/scripts/*.sh (8 files)
```

### Generation Rules

1. **Trigger:** Automatically generated at batch start (multi-task) or on first cache prime
2. **Refresh interval:** 10 minutes (configurable via `CACHE_REPO_MAP_TTL`)
3. **Scope:** Includes only tracked files (respects `.gitignore`)
4. **Depth:** 3 levels by default (expandable to 5 for large repos)
5. **File count threshold:** If repo has >10,000 files, skip repo map (performance safeguard)

### Usage in Spawn Prompts

The Manager injects the repo map into Analyst and Architect prompts:

```markdown
REPOSITORY STRUCTURE:
[See cached repo map above — 547 files, generated 3m ago]

Use this map to understand the codebase layout before reading files.
Do NOT re-generate this map unless it's stale (>10m old).
```

---

## CACHE TUNING

### Configuration Variables

Defined in `.claude/scripts/cache.sh`:

```bash
CACHE_DIR="${CLAUDE_ROOT}/.claude/cache"
CACHE_DB="${CACHE_DIR}/cache.db"
CACHE_TTL_SECONDS=300              # Redis TTL: 5 minutes
CACHE_REPO_MAP_TTL=600             # Repo map refresh: 10 minutes
CACHE_MAX_FILE_SIZE=1048576        # Skip caching files >1MB
CACHE_EVICTION_THRESHOLD=1000      # Evict oldest entries if >1000 cached
```

### Performance Targets

| Metric | Target | Measurement |
|--------|--------|-------------|
| Cache hit rate | >70% | `hits / (hits + misses)` |
| Tokens saved per session | >10K | Sum of cached file tokens |
| Cache lookup latency | <10ms | SQLite query time |
| Invalidation latency | <5ms | DELETE + Redis DEL |

### Eviction Policy

When `cache_entries` row count exceeds `CACHE_EVICTION_THRESHOLD`:
1. Compute `score = read_count * log(now - last_read)`
2. Keep top 80% by score (frequently read + recently used)
3. Evict bottom 20% (rarely read + stale)

---

## OBSERVABILITY INTEGRATION

### Token Ledger

All cache operations emit structured logs to `.claude/logs/factory.log`:

```json
{
  "timestamp": "2026-02-09T14:32:01Z",
  "event": "cache_operation",
  "operation": "hit",
  "key": "policy:orchestration",
  "bytes": 8432,
  "tokens_saved_estimate": 2783,
  "read_count": 6,
  "age_seconds": 120
}
```

### Performance Metrics

The Reporter aggregates cache metrics across the session:

```markdown
## Cache Performance (Session Summary)
- **Hit rate:** 78% (42 hits / 54 requests)
- **Tokens saved:** ~14,200 (estimated)
- **Top cached files:**
  1. docs/policy/spawn-templates.md (8 reads, 3.2KB)
  2. CLAUDE.md (6 reads, 12.4KB)
  3. docs/policy/orchestration.md (5 reads, 8.4KB)
- **Evictions:** 3 entries (stale files from previous session)
```

### Audit Trail

Every cache invalidation is logged with reason:

```json
{
  "timestamp": "2026-02-09T14:35:12Z",
  "event": "cache_invalidation",
  "key": "file:/Users/kousha/.../orchestration.md",
  "reason": "file_edited",
  "triggered_by": "manager",
  "phase": "implementation"
}
```

---

## FAILURE MODES

### Cache Corruption

**Symptom:** SQLite database is unreadable or missing schema

**Recovery:**
1. Detect via `PRAGMA integrity_check` (in `health-check.sh`)
2. Backup corrupted DB to `.claude/cache/cache.db.bak`
3. Drop and recreate schema
4. Log error: `Cache DB corrupted — regenerated empty cache`

**Prevention:**
- Use SQLite's `PRAGMA journal_mode=WAL` for write safety
- Run `VACUUM` weekly (via `health-check.sh`)

### Redis Unavailable

**Symptom:** `redis-cli PING` fails

**Recovery:**
- All operations fall back to SQLite transparently
- Log warning: `Redis unavailable — using SQLite only`
- No impact on correctness, slight performance degradation

### Stale Cache

**Symptom:** Agent reads cached file, but `git_repo_diff` shows it changed

**Recovery:**
1. Agent detects staleness: `File X changed since cache entry — re-reading`
2. Agent calls `Read` tool to fetch fresh content
3. Manager invalidates stale entry after agent reports it

**Prevention:**
- Manager calls `cache_invalidate` immediately after Write/Edit
- Architect confirmation gate triggers cache refresh before Developer spawns

### Cache Thrashing

**Symptom:** High invalidation rate (>50% of entries per task)

**Recovery:**
1. Detect via `invalidation_rate = evictions / writes`
2. If rate >0.5 → disable cache for remainder of session
3. Log warning: `Cache thrashing detected — disabling cache`

**Prevention:**
- Use coarse-grained invalidation (type-level, not per-file) during multi-task batches
- Defer invalidations until task boundaries

---

## DECISION MEMORY

### Purpose

The Decision Memory system tracks Manager orchestration decisions across sessions to enable data-driven optimization of task mode classification, architect skipping, and token budget allocation.

### Schema

```sql
CREATE TABLE decision_memory (
  id                  INTEGER PRIMARY KEY AUTOINCREMENT,
  run_id              TEXT NOT NULL,
  task_mode           TEXT NOT NULL,      -- MICRO-CHANGE | STANDARD | VERIFICATION
  tokens_estimated    INTEGER,            -- Pre-execution estimate
  tokens_actual       INTEGER,            -- Actual tokens used
  architect_skipped   INTEGER DEFAULT 0,  -- 1 if Architect was skipped, 0 otherwise
  loops               INTEGER DEFAULT 0,  -- Number of implementation loop iterations
  duration_seconds    INTEGER,            -- Task duration
  created_at          INTEGER NOT NULL    -- Unix timestamp
);
```

### Recording Decisions

The Manager MUST call `decision_memory_record()` at the end of each task (Phase 5, after Reporter completes):

```bash
decision_memory_record \
  "$run_id" \
  "$task_mode" \
  "$tokens_estimated" \
  "$tokens_actual" \
  "$architect_skipped" \
  "$loops" \
  "$duration_seconds"
```

**Example:**

```bash
decision_memory_record \
  "cf-20260209-143201" \
  "MICRO-CHANGE" \
  15000 \
  12340 \
  1 \
  1 \
  87
```

### Analyzing Decisions

The Reporter MAY call `decision_memory_stats()` to compute aggregate metrics:

```bash
stats=$(decision_memory_stats)
# Returns: {"total_runs":42,"avg_tokens":45231,"avg_loops":1.8,"avg_duration":124,"architect_skip_rate":23.8,"mode_breakdown":"MICRO-CHANGE:12 STANDARD:28 VERIFICATION:2"}
```

**Use Cases:**

1. **Task Mode Accuracy:** Compare `task_mode` classification vs. actual `tokens_actual` and `loops` to identify misclassifications
2. **Architect Skip Efficacy:** Analyze tasks where `architect_skipped=1` — did they require fewer loops? Lower token usage?
3. **Token Budget Calibration:** Compare `tokens_estimated` vs. `tokens_actual` to refine Budget Block ranges
4. **Performance Trends:** Track `duration_seconds` over time to identify performance regressions

### Reporter Integration

The Reporter MUST include a "Decision Memory Summary" section in the final report when `decision_memory_summary()` returns valid data. The Manager generates this by calling `decision_memory_summary 10` and injects the output into the Reporter's spawn prompt as DECISION MEMORY CONTEXT.

**Summary contents (last N=10 runs):**
- Architect skip rate
- Average loops by task mode (MICRO-CHANGE, STANDARD, VERIFICATION)
- Token trend (increasing/decreasing/stable, with percentage)
- Mode breakdown counts

```markdown
## Decision Memory Summary (last 10 of 42 runs)

| Metric | Value |
|--------|-------|
| Architect skip rate | 23.8% |
| Avg loops (MICRO-CHANGE) | 1.0 |
| Avg loops (STANDARD) | 1.8 |
| Avg loops (VERIFICATION) | 1.0 |
| Avg tokens (recent) | 38120 |
| Token trend | decreasing (-12%) |
| Avg duration | 124s |
| Mode breakdown | MICRO-CHANGE:12 STANDARD:28 VERIFICATION:2 |
```

### Manager Prediction Integration

The Manager SHOULD call `decision_memory_predict <task_mode>` during Phase 0 to adjust orchestration:

```bash
prediction=$(decision_memory_predict "STANDARD")
# Returns: {"prediction":"available","mode":"STANDARD","samples":28,"predicted_loops":1.8,...}
```

**Decision influence rules (data-driven only):**
1. **Task mode prediction:** If `predicted_loops < 1.2` for MICRO-CHANGE, confirm MICRO-CHANGE classification is accurate
2. **Architect skip:** If `recommend_architect_skip == true` (skip_rate > 30% AND skipped tasks have fewer loops), the Manager MAY skip Architect for that task mode
3. **Token budget:** Use `recommended_token_budget` (120% of historical average) instead of default Budget Block ranges
4. **Insufficient data:** If `prediction == "insufficient_data"` (fewer than 3 samples), use default Budget Block without adjustment

**Safety rule:** The Manager MUST NOT guess or extrapolate. All adjustments must be based on `decision_memory_predict()` output from recorded stats only.

---

## CACHE.SH API REFERENCE

See `.claude/scripts/cache.sh` for full implementation. Key functions:

| Function | Purpose | Example |
|----------|---------|---------|
| `cache_init` | Initialize SQLite DB and schema | `cache_init` |
| `cache_set <key> <value> <type> [metadata]` | Store entry | `cache_set "policy:orchestration" "$content" "policy"` |
| `cache_get <key>` | Retrieve entry (updates `last_read`) | `cache_get "file:/path/to/file"` |
| `cache_invalidate <key>` | Delete single entry | `cache_invalidate "file:/path/to/file"` |
| `cache_invalidate_type <type>` | Delete all entries of type | `cache_invalidate_type "file"` |
| `cache_flush` | Clear entire cache | `cache_flush` |
| `cache_prime <type> <pattern>` | Bulk populate cache | `cache_prime "policies" "docs/policy/*.md"` |
| `cache_stats` | Compute metrics | `cache_stats` → JSON |
| `build_repo_map` | Generate repository tree | `build_repo_map` → text |
| `cache_lock` | Acquire exclusive lock | `cache_lock` |
| `cache_unlock` | Release lock | `cache_unlock` |
| `cache_warm` | Pre-populate high-value files | `cache_warm` → count |
| `cache_gc` | Remove stale entries | `cache_gc` → count removed |
| `decision_memory_record <args>` | Record Manager decision | `decision_memory_record "$run_id" "MICRO-CHANGE" 15000 12340 1 1 87` |
| `decision_memory_stats` | Compute decision metrics | `decision_memory_stats` → JSON |
| `decision_memory_summary [N]` | Formatted summary for Reporter (last N runs) | `decision_memory_summary 10` → markdown table |
| `decision_memory_predict <mode>` | Predict task characteristics from history | `decision_memory_predict "STANDARD"` → JSON with predictions |
| `cached_rg <pattern> [path]` | Cached ripgrep | `cached_rg "export" "."` → output |
| `cached_git_diff [base] [head]` | Cached git diff | `cached_git_diff "HEAD~1" "HEAD"` → output |
| `cached_file_list [pattern]` | Cached file list | `cached_file_list "*.md"` → paths |

---

## SECURITY CONSIDERATIONS

### Path Sanitization

All file paths MUST be canonicalized before cache operations:

```bash
filepath=$(realpath "$input_path")  # Resolve symlinks, remove ../
cache_get "file:$filepath"
```

**Purpose:** Prevent cache poisoning via path traversal (e.g., `../../etc/passwd`)

### Content Validation

Cache entries MUST NOT contain:
- Environment variables (e.g., `$HOME`, `$API_KEY`)
- Credentials or secrets (detected via regex: `password|token|secret|key`)
- Binary data (cache is text-only)

**Enforcement:** `cache_set` validates content before writing. If validation fails, log error and skip caching.

### Access Control

Cache DB and Redis are local-only:
- SQLite: `chmod 600 .claude/cache/cache.db`
- Redis: Bound to `127.0.0.1` (no network exposure)

---

## TESTING

### Unit Tests

Test suite: `.claude/scripts/test-cache.sh`

**Coverage:**
1. `cache_init` creates schema correctly
2. `cache_set` + `cache_get` round-trip preserves content
3. `cache_invalidate` removes entry
4. `cache_prime` populates multiple entries
5. `build_repo_map` generates valid tree
6. `cache_stats` computes correct metrics
7. Redis fallback works when Redis unavailable

### Integration Test

Add to `health-check.sh`:

```bash
# Check 14: Cache system operational
source .claude/scripts/cache.sh
cache_init
cache_set "test:key" "test_value" "test"
value=$(cache_get "test:key")
if [[ "$value" == "test_value" ]]; then
  echo "✅ Cache system: operational"
else
  echo "❌ Cache system: failed (init or read error)"
fi
cache_invalidate "test:key"
```

---

## ROLLOUT PLAN

### Phase 1: Core Infrastructure (THIS RELEASE)
- ✅ Create `cache.md` (this file)
- ✅ Implement `.claude/scripts/cache.sh` (SQLite + Redis)
- ✅ Add `build-repo-map.sh`
- ✅ Update spawn templates to inject `CACHE CONTEXT`
- ✅ Add cache checks to `health-check.sh`

### Phase 2: Priming Integration (COMPLETED)
- ✅ Integrate `cache_prime` into Manager's Phase 0
- ✅ Add `cache_invalidate` hooks after Write/Edit
- ✅ Emit cache metrics to token ledger
- ✅ Add `decision_memory` table to track Manager decisions

### Phase 3: Adaptive Tuning (FUTURE)
- Track per-agent cache usage patterns
- Auto-adjust `CACHE_TTL` based on hit rate
- Implement smart eviction (LFU + recency)

---

## CHANGELOG

| Version | Date       | Changes |
|---------|------------|---------|
| 1.0     | 2026-02-09 | Initial cache policy (SQLite + Redis, repo map, Rules 32-33) |

---

**END OF POLICY**
