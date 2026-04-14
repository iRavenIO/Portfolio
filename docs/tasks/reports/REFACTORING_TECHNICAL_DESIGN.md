# Technical Design Document: Comprehensive Codebase Refactoring

**Author:** Architect Agent
**Date:** 2026-02-10
**Status:** DESIGN PHASE (Do Not Implement)
**Scope:** Track 1 (MCP Server Consolidation), Track 2 (Shell Script Consolidation), Track 3 (Documentation Synchronization)

---

## Table of Contents

1. [Architecture Overview](#1-architecture-overview)
2. [Track 1: MCP Server Library Design](#2-track-1-mcp-server-library-design)
3. [Track 2: Shell Script Library Design](#3-track-2-shell-script-library-design)
4. [Track 3: Documentation Synchronization](#4-track-3-documentation-synchronization)
5. [Testing & Validation Architecture](#5-testing--validation-architecture)
6. [Risk Mitigation Strategies](#6-risk-mitigation-strategies)
7. [Implementation Sequence](#7-implementation-sequence)
8. [File Modification Plan](#8-file-modification-plan)
9. [Rollback Plan](#9-rollback-plan)
10. [Success Criteria](#10-success-criteria)

---

## 1. Architecture Overview

### 1.1 Current State

The factory has 7 MCP servers totaling ~5,032 lines of JavaScript and 35 shell scripts totaling ~13,586 lines of Bash. Each MCP server independently defines the same core utilities (e.g., `getRepoRoot()`, `execFileAsync`, error handling patterns). Similarly, shell scripts independently define identical helper functions (`say()`, `warn()`, `err()`, `have()`, color codes, test framework functions).

### 1.2 Target State

```
.claude/mcp/
  lib/                         <-- NEW: Shared JS library
    index.js                   <-- Central re-export point
    core.js                    <-- getRepoRoot, execSafe, constants
    errors.js                  <-- Error response formatting
    validation.js              <-- Path/input validation, security
    config.js                  <-- Config loading (ops-specific)
    server-bootstrap.js        <-- Server setup + startup boilerplate
  server.js                    <-- MIGRATED: uses lib/*
  server-ctags.js              <-- MIGRATED: uses lib/*
  server-rg.js                 <-- MIGRATED: uses lib/*
  server-fs.js                 <-- MIGRATED: uses lib/*
  server-git.js                <-- MIGRATED: uses lib/*
  server-query.js              <-- MIGRATED: uses lib/*
  server-ops.js                <-- MIGRATED: uses lib/* (complex, last)
  package.json                 <-- UNCHANGED

.claude/scripts/
  lib/                         <-- NEW: Shared shell library
    common.sh                  <-- say/warn/err/have, colors, guards
    test-framework.sh          <-- pass/fail/assert*, counters, summary
    env.sh                     <-- CLAUDE_ROOT detection, env.claude loading
    platform.sh                <-- macOS/Linux detection, wrappers
  *.sh                         <-- MIGRATED: source lib/*.sh
```

### 1.3 Component Interaction Diagram

```
                         .mcp.json
                            |
               +------------+-------------+
               |            |             |
            server.js   server-rg.js  server-ops.js  ... (7 servers)
               |            |             |
               +-----+------+------+------+
                     |             |
               lib/index.js       |
                  |                |
         +-------+-------+        |
         |       |       |        |
     core.js errors.js valid.js config.js
         |
    getRepoRoot()
    execSafe()
    makeTextResponse()


                 .claude/scripts/
                        |
          +--------+--------+--------+
          |        |        |        |
      health-  validate- test-    ci-
      check.sh policies  cache   check
          |        |        |        |
          +---+----+--+-----+--------+
              |       |
          lib/common.sh
          lib/test-framework.sh
          lib/env.sh
          lib/platform.sh
```

### 1.4 Design Principles

1. **Zero breaking changes during migration.** Each server/script works identically after migration. Only internal imports change.
2. **Incremental migration.** One server or script at a time, with tests between each step.
3. **No new dependencies.** Libraries use only Node built-ins and existing `@modelcontextprotocol/sdk` + `zod`.
4. **Security preserved.** All `execFile` usage, path validation, and sanitization stays intact or improves.
5. **ESM throughout.** All JS files use ESM imports (package.json already has `"type": "module"`).

---

## 2. Track 1: MCP Server Library Design

### 2.1 Library Module Structure

**Directory:** `.claude/mcp/lib/`

| Module | Exports | Responsibility |
|--------|---------|---------------|
| `index.js` | Re-exports from all modules | Single import point for servers |
| `core.js` | `getRepoRoot`, `execSafe`, `makeExecFileAsync`, timeout constants | Core command execution and repo detection |
| `errors.js` | `makeTextResponse`, `makeErrorResponse`, `handleExecError` | Consistent MCP response construction |
| `validation.js` | `validateFilePath`, `validateInsideRepo`, `sanitizePath` | Path validation and security |
| `config.js` | `loadJsonConfig`, `watchConfig`, `applyEnvOverrides` | Configuration file management (ops-specific patterns) |
| `server-bootstrap.js` | `createServer`, `startServer` | Server creation and stdio transport startup |

### 2.2 Core Utilities (`lib/core.js`)

```js
// .claude/mcp/lib/core.js

import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

// ── Timeout Constants ──────────────────────────────────────
export const TIMEOUTS = {
  GIT: 30_000,           // 30s - git operations (standard)
  GIT_FAST: 5_000,       // 5s - git operations (ops server, latency-sensitive)
  CTAGS: 180_000,        // 3min - ctags indexing
  RG: 60_000,            // 1min - ripgrep search
  QUERY: 30_000,         // 30s - jq/yq queries
  SEARCH: 120_000,       // 2min - web search
  SAY: 60_000,           // 1min - speech
};

export const BUFFERS = {
  DEFAULT: 5 * 1024 * 1024,   // 5 MB
  LARGE: 10 * 1024 * 1024,    // 10 MB
  SMALL: 1024 * 1024,         // 1 MB
};

// ── getRepoRoot ────────────────────────────────────────────
//
// Two behaviors supported:
//   - Standard (default): throws on failure
//   - Fallback: returns process.cwd() on failure (for server-ops.js)
//
export async function getRepoRoot(options = {}) {
  const { fallback = false, timeout = TIMEOUTS.GIT } = options;

  try {
    const { stdout } = await execFileAsync("git", ["rev-parse", "--show-toplevel"], {
      timeout,
    });
    return stdout.trim();
  } catch (error) {
    if (fallback) {
      return process.cwd();
    }
    throw error;
  }
}

// ── execSafe ───────────────────────────────────────────────
//
// Wraps execFileAsync with structured result object.
// Used by server-ops.js and available for other servers.
//
// Returns: { success: true, stdout, stderr }
//       or { success: false, error, message, stderr? }
//
export async function execSafe(command, args, options = {}) {
  const {
    timeout = 10_000,
    maxBuffer = BUFFERS.DEFAULT,
    env,
    cwd,
  } = options;

  try {
    const { stdout, stderr } = await execFileAsync(command, args, {
      timeout,
      maxBuffer,
      env: env ? { ...process.env, ...env } : undefined,
      cwd,
    });
    return { success: true, stdout: stdout.trim(), stderr: stderr.trim() };
  } catch (error) {
    if (error.code === "ENOENT") {
      return { success: false, error: "command_not_found", message: `${command} not found in PATH` };
    }
    if (error.killed) {
      return { success: false, error: "timeout", message: `Command timed out after ${timeout}ms` };
    }
    return {
      success: false,
      error: "execution_failed",
      message: error.message,
      stderr: error.stderr,
    };
  }
}

// ── Re-export execFileAsync for direct use ─────────────────
export { execFileAsync };
```

**Design decisions:**

- `getRepoRoot({ fallback: true })` replaces the special try/catch in server-ops.js that falls back to `process.cwd()`. All other servers use the default (throws on failure).
- `execSafe` is factored out from server-ops.js's identical function. It provides structured results without throwing.
- `execFileAsync` is re-exported for servers that need raw access (e.g., server-ctags.js for incremental indexing logic).
- Timeout and buffer constants are centralized but servers can still override per-call.

### 2.3 Error Handling (`lib/errors.js`)

```js
// .claude/mcp/lib/errors.js

// ── Response Constructors ──────────────────────────────────

/**
 * Create a standard MCP text response.
 */
export function makeTextResponse(text) {
  return {
    content: [{ type: "text", text }],
  };
}

/**
 * Create an MCP error response.
 */
export function makeErrorResponse(text) {
  return {
    content: [{ type: "text", text }],
    isError: true,
  };
}

// ── Error Type Handlers ────────────────────────────────────

/**
 * Handle common execFileAsync errors with consistent messaging.
 *
 * @param {Error} error - The caught error
 * @param {Object} context - Error context
 * @param {string} context.command - The command that failed
 * @param {number} context.timeoutMs - The timeout value used
 * @param {string} [context.installHint] - Install instructions for ENOENT
 * @param {string} [context.timeoutHint] - Hint for timeout errors
 * @returns {{ content: Array, isError: true }}
 */
export function handleExecError(error, context) {
  const { command, timeoutMs, installHint, timeoutHint } = context;

  if (error.killed) {
    const message = timeoutHint
      || `${command} timed out after ${timeoutMs / 1000}s.`;
    return makeErrorResponse(message);
  }

  if (error.code === "ENOENT") {
    const message = installHint
      || `${command} not found. Ensure it is installed and available in PATH.`;
    return makeErrorResponse(message);
  }

  // General error
  const message = `${command} failed: ${error.stderr || error.message}`;
  return makeErrorResponse(message);
}

/**
 * Handle getRepoRoot() failure consistently.
 */
export function handleRepoRootError(error) {
  if (error.code === "ENOENT") {
    return makeErrorResponse("git not found. Ensure git is installed and in PATH.");
  }
  return makeErrorResponse(`Failed to detect repository root: ${error.message}`);
}
```

**Design decisions:**

- `makeTextResponse` and `makeErrorResponse` eliminate the repeated `{ content: [{ type: "text", text }] }` pattern (appears 50+ times across servers).
- `handleExecError` consolidates the 3-branch error pattern (killed/ENOENT/general) found in every tool handler.
- `handleRepoRootError` consolidates the repo root error handling that appears in every server's tool handlers.

### 2.4 Validation (`lib/validation.js`)

```js
// .claude/mcp/lib/validation.js

import { join, relative, isAbsolute } from "node:path";
import { access } from "node:fs/promises";
import { constants } from "node:fs";

/**
 * Validate that a file path is inside the repository and readable.
 *
 * Extracted from server-query.js's validateFilePath and
 * server-fs.js / server-git.js inline validation patterns.
 *
 * @param {string} filePath - Relative or absolute path
 * @param {string} repoRoot - Repository root directory
 * @param {Object} [options]
 * @param {boolean} [options.checkReadable=true] - Also verify file exists and is readable
 * @returns {Promise<{ absPath: string, relToRepo: string } | { error: string }>}
 */
export async function validateFilePath(filePath, repoRoot, options = {}) {
  const { checkReadable = true } = options;

  const absPath = isAbsolute(filePath) ? filePath : join(repoRoot, filePath);
  const relToRepo = relative(repoRoot, absPath);

  // Directory traversal check
  if (relToRepo.startsWith("..") || isAbsolute(relToRepo)) {
    return { error: `Path is outside the repository: ${filePath}` };
  }

  if (checkReadable) {
    try {
      await access(absPath, constants.R_OK);
    } catch {
      return { error: `File not found or not readable: ${filePath}` };
    }
  }

  return { absPath, relToRepo };
}

/**
 * Validate that a directory path is inside the repository.
 * Does not check readability (directories may not exist yet).
 *
 * @param {string} dirPath - Relative or absolute directory path
 * @param {string} repoRoot - Repository root directory
 * @returns {{ absPath: string, relToRepo: string } | { error: string }}
 */
export function validateDirPath(dirPath, repoRoot) {
  const absPath = isAbsolute(dirPath) ? dirPath : join(repoRoot, dirPath);
  const relToRepo = relative(repoRoot, absPath);

  if (relToRepo.startsWith("..") || isAbsolute(relToRepo)) {
    return { error: `Path is outside the repository: ${dirPath}` };
  }

  return { absPath, relToRepo };
}
```

**Design decisions:**

- The `validateFilePath` function is extracted from `server-query.js` (which already had it as a standalone function) and generalized.
- The `checkReadable` option supports both use cases: `server-query.js` (must be readable) and `server-git.js` blame (path checked by git itself).
- `validateDirPath` is a synchronous variant for directory validation used in `server-fs.js` tree/list operations.

### 2.5 Configuration (`lib/config.js`)

```js
// .claude/mcp/lib/config.js

import { readFileSync, existsSync, watchFile } from "node:fs";
import { resolve } from "node:path";

/**
 * Load a JSON config file with optional hot-reload.
 *
 * Extracted from server-ops.js loadOpsConfig pattern.
 * Generic enough for any server that needs config.
 *
 * @param {string} repoRoot - Repository root
 * @param {string} relativePath - Path relative to repo root
 * @param {Object} [options]
 * @param {boolean} [options.watch=false] - Enable file watching for hot-reload
 * @param {number} [options.watchInterval=5000] - Watch interval in ms
 * @param {Function} [options.onReload] - Callback when config is reloaded
 * @returns {{ config: Object, configPath: string } | null}
 */
export function loadJsonConfig(repoRoot, relativePath, options = {}) {
  const { watch = false, watchInterval = 5000, onReload } = options;
  const configPath = resolve(repoRoot, relativePath);

  if (!existsSync(configPath)) {
    return null;
  }

  try {
    const configData = readFileSync(configPath, "utf-8");
    const config = JSON.parse(configData);

    if (watch && onReload) {
      watchFile(configPath, { interval: watchInterval }, () => {
        try {
          const newData = readFileSync(configPath, "utf-8");
          const newConfig = JSON.parse(newData);
          onReload(newConfig);
        } catch {
          // Silent fail on hot-reload errors
        }
      });
    }

    return { config, configPath };
  } catch {
    return null;
  }
}

/**
 * Apply environment variable overrides to a config object.
 *
 * @param {Object} config - Base config
 * @param {Array<{ envVar: string, path: string, transform?: Function }>} mapping
 * @returns {Object} Config with overrides applied
 */
export function applyEnvOverrides(config, mapping) {
  const result = structuredClone(config);

  for (const { envVar, path, transform } of mapping) {
    const value = process.env[envVar];
    if (value === undefined) continue;

    const keys = path.split(".");
    let target = result;
    for (let i = 0; i < keys.length - 1; i++) {
      if (!target[keys[i]]) target[keys[i]] = {};
      target = target[keys[i]];
    }

    const lastKey = keys[keys.length - 1];
    target[lastKey] = transform ? transform(value) : value;
  }

  return result;
}
```

**Design decisions:**

- This module is primarily for `server-ops.js`, which has the most complex config management (hot-reload, env overrides, validation, migration).
- The simpler servers (server.js, server-rg.js, etc.) define their constants inline and do not need this module.
- `applyEnvOverrides` is made generic via a mapping array, replacing the server-ops.js's hardcoded if-statements.

### 2.6 Server Bootstrap (`lib/server-bootstrap.js`)

```js
// .claude/mcp/lib/server-bootstrap.js

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

/**
 * Create a new MCP server instance.
 *
 * @param {string} name - Server name (e.g., "factory-rg")
 * @param {string} version - Semantic version string
 * @returns {McpServer}
 */
export function createServer(name, version) {
  return new McpServer({ name, version });
}

/**
 * Start an MCP server with stdio transport.
 * Handles fatal errors with consistent error messages.
 *
 * @param {McpServer} server - The MCP server instance
 * @param {string} [label] - Human-readable label for error messages
 */
export async function startServer(server, label) {
  const displayName = label || server.name || "MCP server";
  try {
    const transport = new StdioServerTransport();
    await server.connect(transport);
  } catch (error) {
    console.error(`Fatal: ${displayName} failed to start:`, error);
    process.exit(1);
  }
}
```

**Design decisions:**

- Every server has identical boilerplate: `new McpServer(...)`, `new StdioServerTransport()`, `server.connect(transport)`, and the `.catch()` handler. This eliminates ~7 lines per server (49 lines total).
- The `createServer` function is trivial but exists for symmetry and future extensibility (e.g., adding common middleware).

### 2.7 Central Export (`lib/index.js`)

```js
// .claude/mcp/lib/index.js

// Core utilities
export {
  getRepoRoot,
  execSafe,
  execFileAsync,
  TIMEOUTS,
  BUFFERS,
} from "./core.js";

// Error handling
export {
  makeTextResponse,
  makeErrorResponse,
  handleExecError,
  handleRepoRootError,
} from "./errors.js";

// Validation
export {
  validateFilePath,
  validateDirPath,
} from "./validation.js";

// Configuration
export {
  loadJsonConfig,
  applyEnvOverrides,
} from "./config.js";

// Server bootstrap
export {
  createServer,
  startServer,
} from "./server-bootstrap.js";
```

### 2.8 Migration Strategy

**Migration order** (simple to complex, as recommended by Analyst):

| Order | Server | Complexity | Lines | Key Considerations |
|-------|--------|-----------|-------|-------------------|
| 1 | `server-rg.js` | Low | 169 | Single tool, standard patterns |
| 2 | `server-query.js` | Low | 235 | Two tools, already has `validateFilePath` |
| 3 | `server.js` | Low-Medium | 251 | Three tools, different timeouts |
| 4 | `server-git.js` | Medium | 360 | Four tools, path validation |
| 5 | `server-fs.js` | Medium | 486 | Three tools, complex tree/read helpers |
| 6 | `server-ctags.js` | High | 494 | Complex state management, many helpers |
| 7 | `server-ops.js` | Very High | ~2,000+ | Config, metrics, redaction, approval workflow |

**Per-server migration process:**

1. Create feature branch `refactor/mcp-lib-serverX`
2. Replace inline `getRepoRoot()` with import from `lib/core.js`
3. Replace inline `execFileAsync` import with import from `lib/core.js`
4. Replace error response patterns with `lib/errors.js` helpers
5. Replace path validation with `lib/validation.js` helpers (where applicable)
6. Replace server bootstrap boilerplate with `lib/server-bootstrap.js`
7. Run MCP smoke test (see Section 5.1)
8. Verify no behavioral changes via diff of tool responses
9. Commit

**Backwards compatibility:**

- Each server remains a standalone entry point (no changes to `.mcp.json`)
- All tool names, descriptions, and schemas remain identical
- Response formats remain identical (same JSON structure)
- Error messages remain identical (templates preserve exact wording)

**Example: Migrated `server-rg.js`**

```js
#!/usr/bin/env node

/**
 * Factory MCP Server -- Ripgrep
 * Provides code_search_rg tool for fast code search.
 */

import { z } from "zod";
import {
  getRepoRoot,
  execFileAsync,
  TIMEOUTS,
  BUFFERS,
  makeTextResponse,
  makeErrorResponse,
  handleExecError,
  handleRepoRootError,
  createServer,
  startServer,
} from "./lib/index.js";

// ── Configuration ──────────────────────────────────────────
const RG_TIMEOUT_MS = TIMEOUTS.RG;
const DEFAULT_MAX_RESULTS = 200;

// ── Server setup ───────────────────────────────────────────
const server = createServer("factory-rg", "1.1.0");

// ── Tool: code_search_rg ──────────────────────────────────
server.tool(
  "code_search_rg",
  "Search code in the repository using ripgrep. ...",
  { /* schema unchanged */ },
  async ({ pattern, path, glob, max_results }) => {
    let repoRoot;
    try {
      repoRoot = await getRepoRoot();
    } catch (error) {
      return handleRepoRootError(error);
    }

    const searchPath = path || repoRoot;
    const args = ["--line-number", "--no-heading", "--color", "never"];

    if (glob) {
      const globs = Array.isArray(glob) ? glob : [glob];
      for (const g of globs) args.push("--glob", g);
    }
    args.push("--", pattern, searchPath);

    try {
      const { stdout } = await execFileAsync("rg", args, {
        cwd: repoRoot,
        timeout: RG_TIMEOUT_MS,
        maxBuffer: BUFFERS.DEFAULT,
      });

      const output = stdout.trim();
      if (!output) return makeTextResponse("No matches found.");

      const lines = output.split("\n");
      if (lines.length > max_results) {
        const text = lines.slice(0, max_results).join("\n")
          + `\n\n--- Truncated: showing ${max_results} of ${lines.length} matching lines. ---`;
        return makeTextResponse(text);
      }

      return makeTextResponse(output);
    } catch (error) {
      if (error.code === 1) return makeTextResponse("No matches found.");
      return handleExecError(error, {
        command: "rg",
        timeoutMs: RG_TIMEOUT_MS,
        installHint: "rg (ripgrep) not found. Run ./install.sh to install ripgrep via Homebrew.",
      });
    }
  }
);

// ── Start ──────────────────────────────────────────────────
startServer(server, "ripgrep MCP server");
```

**Lines saved per server (estimated):**

| Server | Current | Migrated | Saved |
|--------|---------|----------|-------|
| server-rg.js | 169 | 125 | 44 |
| server-query.js | 235 | 180 | 55 |
| server.js | 251 | 210 | 41 |
| server-git.js | 360 | 290 | 70 |
| server-fs.js | 486 | 440 | 46 |
| server-ctags.js | 494 | 450 | 44 |
| server-ops.js | ~2,000 | ~1,850 | ~150 |
| **New lib/** | 0 | ~280 | -280 |
| **Net** | **~4,995** | **~3,825** | **~170** |

**Note:** The net savings in raw lines is modest (~170) because the library itself adds ~280 lines. The real value is **eliminating duplication** (same logic defined in one place) and **consistency** (error messages, response formats, security checks are guaranteed identical).

---

## 3. Track 2: Shell Script Library Design

### 3.1 Library Module Structure

**Directory:** `.claude/scripts/lib/`

| Module | Exports | Responsibility |
|--------|---------|---------------|
| `common.sh` | `say()`, `warn()`, `err()`, `have()`, color codes | Basic output and command detection |
| `test-framework.sh` | `pass()`, `fail()`, `print_header()`, `print_test()`, assert helpers, summary | Standardized test infrastructure |
| `env.sh` | `CLAUDE_ROOT`, `_load_env_claude()` | Repo root detection and env.claude loading |
| `platform.sh` | `is_macos()`, `is_linux()`, `has_timeout_cmd()` | Platform detection and cross-platform wrappers |

### 3.2 Common Utilities (`lib/common.sh`)

```bash
# .claude/scripts/lib/common.sh
# Common utility functions for Claude Factory shell scripts.
#
# Usage: source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#     OR source "${CLAUDE_SCRIPTS_DIR}/lib/common.sh"
#
# NOTE: This file MUST be sourced, not executed.

# ── Double-source guard ────────────────────────────────────
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

# ── Color Codes ────────────────────────────────────────────
# Only set if stdout is a terminal (or FORCE_COLOR is set)
if [[ -t 1 ]] || [[ "${FORCE_COLOR:-}" == "1" ]]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  BLUE='\033[0;34m'
  NC='\033[0m'
else
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  NC=''
fi

# ── Output Functions ───────────────────────────────────────
# NOTE: These use printf (not echo) for portability.
# The say/warn/err/have names are chosen to match the existing
# convention used across health-check.sh, validate-policies.sh,
# verify.sh, and ci-check.sh.

say()  { printf "%s\n" "$*"; }
warn() { printf "%s\n" "$*" >&2; }
err()  { printf "%s\n" "$*" >&2; }
have() { command -v "$1" >/dev/null 2>&1; }
```

**Design decisions:**

- The double-source guard pattern (`_COMMON_SH_LOADED`) follows the same pattern already used in `log-helpers.sh` and `notify-helpers.sh`.
- Color codes include terminal detection to avoid escape codes in CI logs.
- The `say()` function is deliberately simple (just `printf "%s\n"`). Some scripts currently prefix with emojis (`warn()` uses "..." prefix); migrated scripts can add their own prefixes if needed.
- Functions do NOT include emoji prefixes because different scripts use different prefix styles. The library provides the base; scripts layer their own decoration.

**IMPORTANT DESIGN NOTE:** Several scripts (health-check.sh, validate-policies.sh) currently define `say()` with emoji prefixes:

```bash
# health-check.sh style:
warn() { printf "...  %s\n" "$*" >&2; }
err()  { printf "... %s\n" "$*" >&2; }

# verify.sh style:
err()  { printf "FAIL: %s\n" "$*" >&2; }
```

The library provides plain functions. Scripts that need special prefixes can define wrapper functions AFTER sourcing the library:

```bash
source "${SCRIPT_DIR}/lib/common.sh"
# Override with script-specific formatting:
warn() { printf "...  %s\n" "$*" >&2; }
```

### 3.3 Test Framework (`lib/test-framework.sh`)

```bash
# .claude/scripts/lib/test-framework.sh
# Shared test framework for Claude Factory test scripts.
#
# Usage:
#   source "${SCRIPT_DIR}/lib/common.sh"
#   source "${SCRIPT_DIR}/lib/test-framework.sh"
#
# Provides:
#   Test lifecycle: print_header, print_test
#   Assertions: pass, fail, assertEqual, assertContains,
#               assertExitCode, assertFileExists, assertDirExists
#   Summary: print_summary, get_exit_code
#
# NOTE: Requires common.sh to be sourced first (for color codes).

# ── Double-source guard ────────────────────────────────────
[[ -n "${_TEST_FRAMEWORK_SH_LOADED:-}" ]] && return 0
_TEST_FRAMEWORK_SH_LOADED=1

# ── Dependency check ───────────────────────────────────────
if [[ -z "${_COMMON_SH_LOADED:-}" ]]; then
  echo "ERROR: test-framework.sh requires common.sh to be sourced first" >&2
  return 1
fi

# ── Test Counters ──────────────────────────────────────────
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

# ── Test Lifecycle ─────────────────────────────────────────

print_header() {
  echo ""
  echo "=========================================="
  echo "$1"
  echo "=========================================="
}

print_test() {
  echo ""
  echo "TEST: $1"
  TESTS_TOTAL=$((TESTS_TOTAL + 1))
}

# ── Pass / Fail ────────────────────────────────────────────

pass() {
  echo -e "${GREEN}PASS${NC}: $1"
  TESTS_PASSED=$((TESTS_PASSED + 1))
}

fail() {
  echo -e "${RED}FAIL${NC}: $1"
  TESTS_FAILED=$((TESTS_FAILED + 1))
}

# ── Assertions ─────────────────────────────────────────────

assertEqual() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  if [[ "$expected" == "$actual" ]]; then
    pass "$description"
  else
    fail "$description"
    echo "  Expected: $expected"
    echo "  Actual:   $actual"
  fi
}

assertContains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    pass "$description"
  else
    fail "$description"
    echo "  Expected to contain: $needle"
  fi
}

assertExitCode() {
  local expected="$1"
  local actual="$2"
  local description="$3"

  if [[ "$expected" -eq "$actual" ]]; then
    pass "$description"
  else
    fail "$description"
    echo "  Expected exit code: $expected"
    echo "  Actual exit code:   $actual"
  fi
}

assertFileExists() {
  local file="$1"
  local description="$2"

  if [[ -f "$file" ]]; then
    pass "$description"
  else
    fail "$description"
    echo "  File not found: $file"
  fi
}

assertDirExists() {
  local dir="$1"
  local description="$2"

  if [[ -d "$dir" ]]; then
    pass "$description"
  else
    fail "$description"
    echo "  Directory not found: $dir"
  fi
}

assertNotContains() {
  local haystack="$1"
  local needle="$2"
  local description="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    pass "$description"
  else
    fail "$description"
    echo "  Expected NOT to contain: $needle"
  fi
}

# ── Summary ────────────────────────────────────────────────

print_summary() {
  print_header "TEST SUMMARY"
  echo "Total Tests:  $TESTS_TOTAL"
  echo -e "Passed:       ${GREEN}$TESTS_PASSED${NC}"
  echo -e "Failed:       ${RED}$TESTS_FAILED${NC}"
  echo ""

  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo -e "${GREEN}ALL TESTS PASSED${NC}"
  else
    echo -e "${RED}SOME TESTS FAILED${NC}"
  fi
  echo ""
}

get_exit_code() {
  if [[ $TESTS_FAILED -eq 0 ]]; then
    echo 0
  else
    echo 1
  fi
}
```

**Design decisions:**

- Counter variables use the same names (`TESTS_TOTAL`, `TESTS_PASSED`, `TESTS_FAILED`) already used by `test-install.sh` and `test-cache.sh`.
- The `pass()`/`fail()` format uses "PASS"/"FAIL" prefix (matching `test-install.sh` style). Scripts like `test-notifications.sh` that use "[PASS]"/"[FAIL]" can override.
- `print_summary` and `get_exit_code` consolidate the summary block that appears at the bottom of every test script.
- The dependency check for `common.sh` provides a clear error if sourcing order is wrong.

### 3.4 Environment Loading (`lib/env.sh`)

```bash
# .claude/scripts/lib/env.sh
# Repository root detection and environment loading for Claude Factory.
#
# Usage: source "${SCRIPT_DIR}/lib/env.sh"
#
# After sourcing, CLAUDE_ROOT and CLAUDE_SCRIPTS_DIR are available.
# If .claude/env.claude exists, its variables are exported.

# ── Double-source guard ────────────────────────────────────
[[ -n "${_ENV_SH_LOADED:-}" ]] && return 0
_ENV_SH_LOADED=1

# ── Repository Root Detection ──────────────────────────────
# Uses BASH_SOURCE to resolve from the script's actual location,
# not the current working directory.

if [[ -z "${CLAUDE_ROOT:-}" ]]; then
  _env_sh_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  CLAUDE_ROOT="$(cd "$_env_sh_dir/../../.." && pwd)"
  unset _env_sh_dir
fi

if [[ -z "${CLAUDE_SCRIPTS_DIR:-}" ]]; then
  CLAUDE_SCRIPTS_DIR="${CLAUDE_ROOT}/.claude/scripts"
fi

export CLAUDE_ROOT
export CLAUDE_SCRIPTS_DIR

# ── Load env.claude ────────────────────────────────────────
# Pattern extracted from health-check.sh and bootstrap-env.sh.
# Uses set -a / set +a to auto-export all sourced variables.
# Suppresses xtrace during sourcing to prevent secret leakage.

_load_env_claude() {
  local _env_file="${CLAUDE_ROOT}/.claude/env.claude"
  if [[ -f "$_env_file" ]]; then
    local _prev_x=false
    [[ $- == *x* ]] && _prev_x=true && set +x
    set -a
    # shellcheck source=/dev/null
    source "$_env_file"
    set +a
    $_prev_x && set -x
  fi
}
_load_env_claude
unset -f _load_env_claude
```

**Design decisions:**

- The `CLAUDE_ROOT` detection uses `BASH_SOURCE[0]` (the library file's location) and navigates up three levels (`.claude/scripts/lib/` -> `.claude/scripts/` -> `.claude/` -> repo root). This is more robust than relying on the calling script's location.
- If `CLAUDE_ROOT` is already set (e.g., by a parent script), it is not overridden.
- The `_load_env_claude` pattern is extracted verbatim from `health-check.sh` and `bootstrap-env.sh` to preserve exact behavior.
- The function is immediately invoked and then unset, matching the current pattern.

### 3.5 Platform Utilities (`lib/platform.sh`)

```bash
# .claude/scripts/lib/platform.sh
# Platform detection and cross-platform wrappers for Claude Factory.
#
# Usage: source "${SCRIPT_DIR}/lib/platform.sh"
#
# Provides:
#   is_macos, is_linux - Platform detection
#   has_timeout_cmd - Check for timeout/gtimeout
#   portable_stat_size - Cross-platform file size
#   portable_timeout - Cross-platform timeout wrapper

# ── Double-source guard ────────────────────────────────────
[[ -n "${_PLATFORM_SH_LOADED:-}" ]] && return 0
_PLATFORM_SH_LOADED=1

# ── Platform Detection ─────────────────────────────────────

is_macos() {
  [[ "$(uname -s)" == "Darwin" ]]
}

is_linux() {
  [[ "$(uname -s)" == "Linux" ]]
}

# ── Cross-Platform Wrappers ────────────────────────────────

# Get the timeout command (GNU timeout or gtimeout on macOS)
has_timeout_cmd() {
  command -v timeout >/dev/null 2>&1 || command -v gtimeout >/dev/null 2>&1
}

get_timeout_cmd() {
  if command -v timeout >/dev/null 2>&1; then
    echo "timeout"
  elif command -v gtimeout >/dev/null 2>&1; then
    echo "gtimeout"
  else
    echo ""
  fi
}

# Portable file size (bytes)
portable_stat_size() {
  local file="$1"
  if is_macos; then
    stat -f%z "$file"
  else
    stat --format=%s "$file"
  fi
}

# Portable sed in-place
portable_sed_inplace() {
  if is_macos; then
    sed -i '' "$@"
  else
    sed -i "$@"
  fi
}
```

**Design decisions:**

- Platform detection is currently done ad-hoc in `bootstrap-env.sh` (timeout detection) and could be needed by future scripts.
- The `get_timeout_cmd()` function replaces the inline pattern in `bootstrap-env.sh`.
- This module is low-priority since most factory scripts run on macOS, but it future-proofs Linux CI support.

### 3.6 Shell Script Migration Strategy

**Migration order** (tests first, then utilities, then CI-critical):

| Phase | Scripts | Risk | Rationale |
|-------|---------|------|-----------|
| Phase A | Test scripts (13 files) | Low | Tests are not CI-critical; if sourcing breaks, only test suites fail |
| Phase B | Utility scripts (log-helpers.sh, notify-helpers.sh, redact.sh) | Low | Already use guard patterns; sourcing library is additive |
| Phase C | CI-critical scripts (health-check.sh, validate-policies.sh, verify.sh, ci-check.sh) | Medium | Must not break CI; needs careful testing |
| Phase D | Remaining scripts (bootstrap-env.sh, cache.sh, build-repo-map.sh) | Low | Not CI-critical; can be migrated independently |
| **Descoped** | `.claude/scripts/ops/*.sh` (5 files) | N/A | Deferred to future phase per Analyst recommendation |

**Per-script migration process:**

1. Add `source "${SCRIPT_DIR}/lib/common.sh"` near the top
2. Remove inline `say()`, `warn()`, `err()`, `have()` definitions
3. Remove inline color code definitions
4. For test scripts: add `source "${SCRIPT_DIR}/lib/test-framework.sh"`
5. Remove inline `pass()`, `fail()`, `print_header()`, `print_test()`, assert functions
6. For scripts that load env.claude: add `source "${SCRIPT_DIR}/lib/env.sh"`
7. Remove inline `_load_env_claude` blocks
8. Remove inline `SCRIPT_DIR` / `REPO_ROOT` detection if using env.sh
9. Run the script to verify behavior
10. Commit

**Sourcing pattern (absolute paths with guards):**

```bash
#!/usr/bin/env bash
set -Eeuo pipefail

# Resolve script location (works from any working directory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source shared libraries
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/env.sh"          # if env.claude needed
source "${SCRIPT_DIR}/lib/test-framework.sh"  # if test script
```

**Lines saved (estimated):**

| Script Group | Count | Avg Lines Saved/Script | Total Saved |
|-------------|-------|----------------------|-------------|
| Test scripts | 13 | 40 | 520 |
| Utility scripts | 5 | 15 | 75 |
| CI-critical scripts | 4 | 20 | 80 |
| Other scripts | 3 | 10 | 30 |
| **New lib/** | 4 | - | -220 |
| **Net** | - | - | **~485** |

---

## 4. Track 3: Documentation Synchronization

### 4.1 VERSION File Format

**File:** `VERSION` (repository root)

```
5.5.0
```

**Versioning scheme:**
- Format: `MAJOR.MINOR.PATCH`
- Current version: `5.5.0` (reflecting Phase 5.5 completion)
- Refactoring versions: `5.6.0-refactor.1`, `5.6.0-refactor.2`, etc.
- After refactoring completes: `6.0.0` (major version bump for architectural change)

**Rules:**
- `VERSION` is a single-line plain text file
- No trailing newline issues (use `printf` to write)
- `validate-policies.sh` checks this file exists and has valid semver format

### 4.2 validate-policies.sh Extensions

Add these new validation checks to `validate-policies.sh`:

**Check 61: Rule count validation**
```bash
# Count rules in critical-rules.md (numbered lines like "1. **...")
RULE_COUNT=$(grep -cE '^\d+\. \*\*' docs/policy/critical-rules.md || true)
# Count the claim in CLAUDE.md (e.g., "31 enforcement rules")
CLAIMED_COUNT=$(grep -oE '\d+ enforcement rules' CLAUDE.md | grep -oE '\d+' || true)
if [[ "$RULE_COUNT" == "$CLAIMED_COUNT" ]]; then
  say "  Rule count matches: $RULE_COUNT"
else
  err "  Rule count mismatch: critical-rules.md has $RULE_COUNT, CLAUDE.md claims $CLAIMED_COUNT"
fi
```

**Check 62: MCP tool count validation**
```bash
# Count unique tool registrations across all server files
TOOL_COUNT=$(grep -c 'server\.tool(' .claude/mcp/server*.js | awk -F: '{s+=$2} END {print s}')
# Count rows in CLAUDE.md MCP Tools table
TABLE_TOOL_COUNT=$(grep -c '| `factory-' CLAUDE.md || true)
```

**Check 63: MCP server count validation**
```bash
# Count servers in .mcp.json
MCP_JSON_COUNT=$(grep -c '"factory-' .mcp.json || true)
# Count claim in CLAUDE.md
CLAIMED_SERVER_COUNT=$(grep -oE '\d+ servers' CLAUDE.md | head -1 | grep -oE '\d+' || true)
```

**Check 64: VERSION file validation**
```bash
if [[ -f "VERSION" ]]; then
  VERSION_CONTENT=$(cat VERSION)
  if [[ "$VERSION_CONTENT" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.]+)?$ ]]; then
    say "  VERSION file valid: $VERSION_CONTENT"
  else
    err "  VERSION file has invalid format: $VERSION_CONTENT"
  fi
else
  err "  VERSION file missing"
fi
```

**Check 65: Policy file count validation**
```bash
# Count policy files listed in CLAUDE.md table
CLAUDE_MD_POLICY_COUNT=$(grep -c 'docs/policy/' CLAUDE.md | head -1)
# Count actual policy files
ACTUAL_POLICY_COUNT=$(find docs/policy -name "*.md" | wc -l | tr -d ' ')
```

### 4.3 Documentation Update Strategy

**CLAUDE.md fixes (specific changes):**

1. **Rule count:** If critical-rules.md has 31 rules, CLAUDE.md must say "31 enforcement rules" (or update to actual count).
2. **Tool count in MCP Tools Table:** Verify every `server.tool()` registration has a corresponding table row. Currently the table lists 30 tools across 7 servers. This must match reality.
3. **Server count:** The architecture diagram lists 7 MCP server files. Verify `.mcp.json` has exactly 7 entries.
4. **Policy table:** Check that every `.md` file in `docs/policy/` is listed in the CLAUDE.md policy table.
5. **Missing policy references:** Ensure `docs/policy/secrets-and-env.md` and `docs/policy/ops-tools.md` appear in both the table and the EXPECTED_REFS array in `validate-policies.sh`.

**Other documentation updates:**

6. **health-check.sh policy file list:** Currently lists 12 policy files. Must match the 17 files in `validate-policies.sh`.
7. **verify.sh MCP server check:** Lists "All 6 MCP server files" but there are 7 (missing server-ops.js). Fix the count and array.

---

## 5. Testing & Validation Architecture

### 5.1 MCP Server Test Harness

**File:** `.claude/scripts/test-mcp-servers.sh`

**Purpose:** Smoke test all MCP servers to verify they start and respond to tool calls.

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/test-framework.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MCP_DIR="$REPO_ROOT/.claude/mcp"

# Test: Each server file can be parsed by Node without syntax errors
print_header "MCP SERVER SYNTAX VALIDATION"

SERVERS=(
  "server.js"
  "server-ctags.js"
  "server-rg.js"
  "server-fs.js"
  "server-git.js"
  "server-query.js"
  "server-ops.js"
)

for server_file in "${SERVERS[@]}"; do
  print_test "Syntax check: $server_file"
  if node --check "$MCP_DIR/$server_file" 2>/dev/null; then
    pass "$server_file has valid syntax"
  else
    fail "$server_file has syntax errors"
  fi
done

# Test: Library modules can be imported
print_header "MCP LIBRARY IMPORT VALIDATION"

if [[ -d "$MCP_DIR/lib" ]]; then
  print_test "Import lib/index.js"
  if node -e "import('$MCP_DIR/lib/index.js')" 2>/dev/null; then
    pass "lib/index.js imports successfully"
  else
    fail "lib/index.js failed to import"
  fi

  LIB_MODULES=("core.js" "errors.js" "validation.js" "config.js" "server-bootstrap.js")
  for mod in "${LIB_MODULES[@]}"; do
    print_test "Import lib/$mod"
    if node -e "import('$MCP_DIR/lib/$mod')" 2>/dev/null; then
      pass "lib/$mod imports successfully"
    else
      fail "lib/$mod failed to import"
    fi
  done
fi

# Test: Server startup (each server starts and exits cleanly when stdin closes)
print_header "MCP SERVER STARTUP VALIDATION"

for server_file in "${SERVERS[@]}"; do
  print_test "Startup: $server_file"
  # Send empty stdin, expect clean exit within 5s
  if timeout 5 node "$MCP_DIR/$server_file" < /dev/null 2>/dev/null; then
    pass "$server_file starts and exits cleanly"
  else
    exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
      # timeout = server is running but hung waiting for input; that is acceptable
      pass "$server_file started (timed out waiting for MCP messages, as expected)"
    else
      fail "$server_file failed to start (exit code: $exit_code)"
    fi
  fi
done

print_summary
exit "$(get_exit_code)"
```

**Key design notes:**

- `node --check` validates syntax without executing (fast, no side effects).
- Dynamic `import()` validates that modules resolve and export correctly.
- The startup test sends `/dev/null` as stdin. MCP servers using stdio transport will either exit cleanly (no messages) or hang waiting for input (timeout = acceptable).
- This test script uses the new library (`lib/common.sh`, `lib/test-framework.sh`) once Track 2 is complete. During Track 1, it can use inline definitions.

### 5.2 Shell Script Test Strategy

**Layer 1: Syntax validation (`bash -n`)**

Add to `ci-check.sh` or create `.claude/scripts/test-shell-syntax.sh`:

```bash
# Validate all .sh files in .claude/scripts/ parse without syntax errors
for script in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR"/lib/*.sh; do
  bash -n "$script" || fail "Syntax error in: $script"
done
```

**Layer 2: Sourcing tests (from different working directories)**

Test that library files can be sourced from any directory:

```bash
# Test sourcing from repo root
(cd / && source "$CLAUDE_SCRIPTS_DIR/lib/common.sh" && say "sourced from /")

# Test sourcing from home directory
(cd ~ && source "$CLAUDE_SCRIPTS_DIR/lib/common.sh" && say "sourced from ~")

# Test sourcing from nested directory
(cd "$REPO_ROOT/docs/policy" && source "$CLAUDE_SCRIPTS_DIR/lib/common.sh" && say "sourced from nested dir")
```

**Layer 3: Function unit tests**

Test individual functions exported by library modules:

```bash
# Test common.sh functions
source lib/common.sh
assertEqual "$(say 'hello')" "hello" "say outputs text"
assertEqual "$(have bash; echo $?)" "0" "have detects existing command"
assertEqual "$(have nonexistent_cmd_xyz; echo $?)" "1" "have detects missing command"
```

**Layer 4: Integration tests**

Verify that migrated scripts produce identical output to their pre-migration versions:

```bash
# Capture output before migration
bash health-check.sh > /tmp/before.txt 2>&1
# After migration
bash health-check.sh > /tmp/after.txt 2>&1
# Compare (ignoring timestamps)
diff <(grep -v 'timestamp' /tmp/before.txt) <(grep -v 'timestamp' /tmp/after.txt)
```

### 5.3 CI Integration

**Pre-commit hook additions:**

Add to `.claude/scripts/ci-check.sh`:

```bash
# Check 4: Shell library syntax
if [ -d "$SCRIPT_DIR/lib" ]; then
    run_check "shell-lib-syntax" bash -n "$SCRIPT_DIR/lib/common.sh" "$SCRIPT_DIR/lib/test-framework.sh" "$SCRIPT_DIR/lib/env.sh" "$SCRIPT_DIR/lib/platform.sh"
fi

# Check 5: MCP library syntax
if [ -d "$REPO_ROOT/.claude/mcp/lib" ]; then
    run_check "mcp-lib-syntax" node --check "$REPO_ROOT/.claude/mcp/lib/index.js"
fi
```

**GitHub Actions workflow updates:**

The existing CI workflow (if any) should include:
1. `bash .claude/scripts/ci-check.sh` (already runs health-check and validate-policies)
2. `bash .claude/scripts/test-mcp-servers.sh` (new, post-Track-1)
3. `bash .claude/scripts/test-shell-syntax.sh` (new, post-Track-2)

---

## 6. Risk Mitigation Strategies

### RISK-1: MCP Server Breakage (CRITICAL)

**Impact:** Factory pipeline inoperable. All agents lose access to MCP tools.

**Technical mitigation:**
1. **Syntax validation gate:** Before committing any server change, run `node --check .claude/mcp/server-*.js` to catch import/syntax errors.
2. **Startup validation:** After each server migration, verify the server starts: `timeout 5 node .claude/mcp/server-X.js < /dev/null`.
3. **One-at-a-time migration:** Never migrate more than one server per commit. Each commit is independently revertable.
4. **Library-first development:** Create and test `lib/` modules BEFORE migrating any server. Libraries are additive (no existing code changes until migration step).

**Rollback mechanism:**
- `git revert <commit>` for any single server migration commit.
- Library files (`lib/`) can remain in place even if server migration is reverted -- they are inert until imported.

**Verification method:**
- Post-migration: run `test-mcp-servers.sh` (startup + syntax for all 7 servers)
- Factory-level: spawn a simple task and confirm all MCP tools respond

### RISK-2: Shell Script CI Failures (CRITICAL)

**Impact:** CI pipeline blocks all PRs. Developer workflow halted.

**Technical mitigation:**
1. **Shell syntax validation:** Run `bash -n` on every `.sh` file before committing.
2. **Sourcing guard pattern:** Every library file has a double-source guard and fails gracefully if dependencies are missing.
3. **Test scripts first:** Migrate test scripts (non-CI-critical) before CI-critical scripts.
4. **CI-safe migration:** For CI-critical scripts (health-check.sh, validate-policies.sh, ci-check.sh), use a feature flag pattern:

```bash
# Feature flag: use library if available, inline fallback otherwise
if [[ -f "${SCRIPT_DIR}/lib/common.sh" ]]; then
  source "${SCRIPT_DIR}/lib/common.sh"
else
  # Inline fallback (to be removed after migration is complete)
  say()  { printf "%s\n" "$*"; }
  warn() { printf "%s\n" "$*" >&2; }
  err()  { printf "%s\n" "$*" >&2; }
  have() { command -v "$1" >/dev/null 2>&1; }
fi
```

**Rollback mechanism:**
- `git revert <commit>` for any single script migration commit.
- The feature flag pattern means scripts work with or without the library.

**Verification method:**
- Run `ci-check.sh` after each script migration
- Run the full test suite: `verify.sh test`

### RISK-3: Shell Library Sourcing Failures (HIGH)

**Impact:** Scripts fail silently or with cryptic errors when sourced from unexpected working directories.

**Technical mitigation:**
1. **Always use absolute paths for sourcing:** `source "${SCRIPT_DIR}/lib/common.sh"` where `SCRIPT_DIR` is computed via `BASH_SOURCE[0]`.
2. **Never use relative paths:** `source ./lib/common.sh` is FORBIDDEN.
3. **Guard pattern on every library:** `[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0`.
4. **Dependency assertion:** Libraries that depend on other libraries check for the guard variable and fail with a clear error message.
5. **Multi-directory sourcing test:** Test sourcing from `/`, `~`, `$REPO_ROOT`, and `$REPO_ROOT/docs/policy`.

**Rollback mechanism:**
- If a library file has sourcing issues, the feature flag fallback in each script ensures CI continues to pass.

**Verification method:**
- Dedicated sourcing test: `test-shell-sourcing.sh` that sources libraries from multiple directories.
- CI integration: add sourcing test to `ci-check.sh`.

---

## 7. Implementation Sequence

### Phase 1: Foundation (Week 1)

| Day | Track | Activity | Deliverables |
|-----|-------|----------|-------------|
| 1 | T3 | Create VERSION file, fix CLAUDE.md doc issues | `VERSION`, updated `CLAUDE.md` |
| 1 | T3 | Add new validate-policies.sh checks (61-65) | Updated `validate-policies.sh` |
| 2 | T3 | Fix verify.sh MCP server count, health-check.sh policy list | Updated `verify.sh`, `health-check.sh` |
| 2 | T1 | Create `.claude/mcp/lib/` directory and all 6 library modules | `lib/*.js` files |
| 3 | T1 | Write MCP test harness | `test-mcp-servers.sh` |
| 3 | T1 | Migrate `server-rg.js` (simplest) | Updated `server-rg.js` |
| 4 | T1 | Migrate `server-query.js` | Updated `server-query.js` |
| 4 | T1 | Migrate `server.js` | Updated `server.js` |
| 5 | T1 | Migrate `server-git.js` | Updated `server-git.js` |
| 5 | T1 | Run full MCP test suite | Verification report |

### Phase 2: MCP Completion + Shell Prep (Week 2)

| Day | Track | Activity | Deliverables |
|-----|-------|----------|-------------|
| 1 | T1 | Migrate `server-fs.js` | Updated `server-fs.js` |
| 2 | T1 | Migrate `server-ctags.js` | Updated `server-ctags.js` |
| 3 | T1 | Migrate `server-ops.js` (most complex) | Updated `server-ops.js` |
| 3 | T1 | Update runbook `.claude/runbooks/add-mcp-server.md` | Updated runbook |
| 4 | T2 | Create `.claude/scripts/lib/` directory and all 4 library modules | `lib/*.sh` files |
| 4 | T2 | Write shell sourcing test | `test-shell-sourcing.sh` |
| 5 | T2 | Migrate test scripts Phase A (13 test scripts) | Updated `test-*.sh` files |

### Phase 3: Shell Scripts + Final Validation (Week 3)

| Day | Track | Activity | Deliverables |
|-----|-------|----------|-------------|
| 1 | T2 | Migrate utility scripts Phase B (log-helpers, notify-helpers, redact) | Updated utility scripts |
| 2 | T2 | Migrate CI-critical scripts Phase C (health-check, validate-policies, verify, ci-check) | Updated CI scripts |
| 3 | T2 | Migrate remaining scripts Phase D (bootstrap-env, cache, build-repo-map) | Updated remaining scripts |
| 4 | All | Full regression testing: all test suites, CI check, MCP smoke test | Full test report |
| 5 | All | Final documentation pass, runbook updates, version bump to 6.0.0 | Final docs |

---

## 8. File Modification Plan

### 8.1 Files to CREATE

| File Path | Purpose | Dependencies | Testing |
|-----------|---------|-------------|---------|
| `.claude/mcp/lib/index.js` | Central JS library export | All lib modules | Import validation |
| `.claude/mcp/lib/core.js` | getRepoRoot, execSafe, constants | Node built-ins | Unit tests in test-mcp-servers.sh |
| `.claude/mcp/lib/errors.js` | MCP response constructors | None | Unit tests |
| `.claude/mcp/lib/validation.js` | Path validation, security | Node `path`, `fs` | Unit tests |
| `.claude/mcp/lib/config.js` | Config loading, env overrides | Node `fs` | Unit tests |
| `.claude/mcp/lib/server-bootstrap.js` | Server creation, startup | `@modelcontextprotocol/sdk` | Startup tests |
| `.claude/scripts/lib/common.sh` | say/warn/err/have, colors | None | Sourcing tests |
| `.claude/scripts/lib/test-framework.sh` | pass/fail/assert, summary | common.sh | Self-test |
| `.claude/scripts/lib/env.sh` | CLAUDE_ROOT, env.claude loading | None | Sourcing tests |
| `.claude/scripts/lib/platform.sh` | Platform detection, wrappers | None | Unit tests |
| `.claude/scripts/test-mcp-servers.sh` | MCP server smoke tests | common.sh, test-framework.sh | Self-executing |
| `.claude/scripts/test-shell-sourcing.sh` | Shell library sourcing validation | lib/*.sh | Self-executing |
| `VERSION` | Semantic version tracking | None | validate-policies.sh check |

### 8.2 Files to MODIFY (MCP Servers)

| File Path | Changes | Dependencies | Testing |
|-----------|---------|-------------|---------|
| `.claude/mcp/server-rg.js` | Replace inline utils with lib imports | lib/*.js | test-mcp-servers.sh |
| `.claude/mcp/server-query.js` | Replace inline utils with lib imports | lib/*.js | test-mcp-servers.sh |
| `.claude/mcp/server.js` | Replace inline utils with lib imports | lib/*.js | test-mcp-servers.sh |
| `.claude/mcp/server-git.js` | Replace inline utils with lib imports | lib/*.js | test-mcp-servers.sh |
| `.claude/mcp/server-fs.js` | Replace inline utils with lib imports | lib/*.js | test-mcp-servers.sh |
| `.claude/mcp/server-ctags.js` | Replace inline utils with lib imports | lib/*.js | test-mcp-servers.sh |
| `.claude/mcp/server-ops.js` | Replace inline utils with lib imports | lib/*.js | test-mcp-servers.sh |

### 8.3 Files to MODIFY (Shell Scripts - Priority)

| File Path | Changes | Dependencies | Testing |
|-----------|---------|-------------|---------|
| `.claude/scripts/test-install.sh` | Replace inline framework with lib sources | lib/common.sh, lib/test-framework.sh | Self-test |
| `.claude/scripts/test-cache.sh` | Replace inline framework with lib sources | lib/common.sh, lib/test-framework.sh | Self-test |
| `.claude/scripts/test-notifications.sh` | Replace inline framework with lib sources | lib/common.sh, lib/test-framework.sh | Self-test |
| `.claude/scripts/test-cli-redaction.sh` | Replace inline framework with lib sources | lib/common.sh, lib/test-framework.sh | Self-test |
| `.claude/scripts/test-bootstrap-env.sh` | Replace inline framework with lib sources | lib/common.sh, lib/test-framework.sh | Self-test |
| `.claude/scripts/test-logging.sh` | Replace inline framework with lib sources | lib/common.sh, lib/test-framework.sh | Self-test |
| `.claude/scripts/test-log-observability.sh` | Replace inline framework with lib sources | lib/common.sh, lib/test-framework.sh | Self-test |
| `.claude/scripts/test-ops-dryrun.sh` | Replace inline framework with lib sources | lib/common.sh, lib/test-framework.sh | Self-test |
| `.claude/scripts/test-ops-stage2.sh` | Replace inline framework with lib sources | lib/common.sh, lib/test-framework.sh | Self-test |
| `.claude/scripts/test-ops-stage3.sh` | Replace inline framework with lib sources | lib/common.sh, lib/test-framework.sh | Self-test |
| `.claude/scripts/test-ops-stage4.sh` | Replace inline framework with lib sources | lib/common.sh, lib/test-framework.sh | Self-test |
| `.claude/scripts/test-phase4-integration.sh` | Replace inline framework with lib sources | lib/common.sh, lib/test-framework.sh | Self-test |
| `.claude/scripts/test-secret-surfaces.sh` | Replace inline framework with lib sources | lib/common.sh, lib/test-framework.sh | Self-test |
| `.claude/scripts/test-secrets-redaction.sh` | Replace inline framework with lib sources | lib/common.sh, lib/test-framework.sh | Self-test |
| `.claude/scripts/test-direct-run-preflight.sh` | Replace inline framework with lib sources | lib/common.sh, lib/test-framework.sh | Self-test |
| `.claude/scripts/health-check.sh` | Replace inline say/warn/err/have, add env.sh | lib/common.sh, lib/env.sh | ci-check.sh |
| `.claude/scripts/validate-policies.sh` | Replace inline say/warn/err, add new checks | lib/common.sh | ci-check.sh |
| `.claude/scripts/verify.sh` | Replace inline say/err/have, fix MCP count | lib/common.sh | Self-test |
| `.claude/scripts/ci-check.sh` | Replace inline colors, add lib checks | lib/common.sh | Self-test |
| `.claude/scripts/bootstrap-env.sh` | Replace inline env loading with lib/env.sh | lib/env.sh, lib/common.sh | test-bootstrap-env.sh |

### 8.4 Files to MODIFY (Documentation)

| File Path | Changes | Testing |
|-----------|---------|---------|
| `CLAUDE.md` | Fix rule count, tool counts, server count, policy references | validate-policies.sh |
| `.claude/runbooks/add-mcp-server.md` | Update to reference lib/ pattern | Manual review |
| `.claude/scripts/validate-policies.sh` | Add checks 61-65 | ci-check.sh |
| `.claude/scripts/health-check.sh` | Update policy file list (12 -> 17) | ci-check.sh |
| `.claude/scripts/verify.sh` | Fix MCP server count (6 -> 7) | Self-test |

### 8.5 Files NOT Modified (Descoped)

| File Path | Reason |
|-----------|--------|
| `.claude/scripts/ops/*.sh` (5 files) | Deferred to future phase per Analyst recommendation |
| `.claude/scripts/cache.sh` | Complex library with many functions; consider descoping |
| `.claude/scripts/build-repo-map.sh` | Standalone utility; low priority |
| `.mcp.json` | No changes needed; server entry points unchanged |
| `.claude/mcp/package.json` | No new dependencies needed |

---

## 9. Rollback Plan

### 9.1 Per-Track Rollback Procedures

**Track 1 (MCP Servers):**

Each server migration is a separate commit. To rollback:

```bash
# Rollback a single server migration
git revert <commit-hash-of-server-migration>

# Rollback all MCP migrations (preserving library)
git revert <commit-hash-range>

# Nuclear rollback: remove library entirely
git rm -r .claude/mcp/lib/
# Then revert all server migrations
```

**Track 2 (Shell Scripts):**

Each script migration is a separate commit. Feature flags ensure scripts work without the library.

```bash
# Rollback a single script migration
git revert <commit-hash>

# Feature flag ensures script works even if lib/ is removed
```

**Track 3 (Documentation):**

Documentation changes are independently revertable:

```bash
git revert <commit-hash-of-doc-change>
```

### 9.2 Rollback Verification Steps

After any rollback:

1. Run `ci-check.sh` -- must pass
2. Run `verify.sh full` -- must pass
3. Run `test-mcp-servers.sh` -- must pass (if library is still present)
4. Manually test one MCP tool: `code_search_rg` with a simple pattern
5. Verify Claude Code `/mcp` shows all 7 servers connected

### 9.3 Recovery Time Objectives

| Scenario | Recovery Action | RTO |
|----------|----------------|-----|
| Single server broken | `git revert` one commit | < 2 minutes |
| All servers broken | `git revert` commit range | < 5 minutes |
| Library has bug | Fix library, re-deploy | < 15 minutes |
| Shell script CI failure | `git revert` one commit | < 2 minutes |
| Complete rollback | Revert all refactoring commits | < 10 minutes |

---

## 10. Success Criteria

### 10.1 Quantitative Metrics

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| MCP `getRepoRoot()` definitions | 7 | 1 | `grep -c "async function getRepoRoot" .claude/mcp/*.js` |
| MCP `execFileAsync` initializations | 7 | 1 | `grep -c "promisify(execFile)" .claude/mcp/*.js` |
| MCP server bootstrap boilerplate instances | 7 | 0 (use `startServer()`) | `grep -c "new StdioServerTransport" .claude/mcp/*.js` |
| Shell `say()` definitions | 5+ | 1 (in lib/common.sh) | `grep -c "^say()" .claude/scripts/*.sh` |
| Shell test framework copy-paste instances | 13+ | 0 (all use lib/test-framework.sh) | `grep -c "^pass()" .claude/scripts/test-*.sh` |
| Shell `_load_env_claude` blocks | 3+ | 1 (in lib/env.sh) | `grep -c "_load_env_claude" .claude/scripts/*.sh` |
| Net lines eliminated (MCP) | 0 | ~170 | `wc -l` comparison |
| Net lines eliminated (Shell) | 0 | ~485 | `wc -l` comparison |
| Documentation sync issues | 7 | 0 | `validate-policies.sh` exits 0 |
| Test coverage (new tests) | 0 | 3 new test scripts | File count |

### 10.2 Qualitative Metrics

| Metric | Target | Verification |
|--------|--------|-------------|
| Adding a new MCP server requires no boilerplate duplication | Yes | Follow updated runbook; measure lines needed |
| Adding a new test script requires no framework copy | Yes | Create test; only test-specific code needed |
| Error message consistency | All MCP servers use identical error formats | Audit error responses across servers |
| Security posture | No reduction in validation/sanitization | Code review of all `validateFilePath` usages |
| Performance | No measurable regression | Time MCP tool responses before/after |

### 10.3 Validation Checkpoints

| Checkpoint | Gate | When |
|-----------|------|------|
| CP1: Library modules created | All 6 JS modules + 4 SH modules pass syntax checks | End of Day 2, Week 1 |
| CP2: First server migrated | server-rg.js works identically with library | End of Day 3, Week 1 |
| CP3: All simple servers migrated | 4 servers migrated, test-mcp-servers.sh passes | End of Week 1 |
| CP4: All servers migrated | All 7 servers migrated, full MCP test passes | End of Day 3, Week 2 |
| CP5: Test scripts migrated | All 13 test scripts use lib/test-framework.sh | End of Week 2 |
| CP6: CI-critical scripts migrated | ci-check.sh passes with library-backed scripts | End of Day 2, Week 3 |
| CP7: Full regression | All existing tests pass, CI clean | End of Day 4, Week 3 |
| CP8: Documentation complete | validate-policies.sh passes all checks including new ones | End of Week 3 |

---

## Appendix A: Duplication Audit Summary

### A.1 MCP Server Duplication (Exact Matches)

| Pattern | Occurrences | Lines Each | Total Duplicated |
|---------|------------|-----------|-----------------|
| `getRepoRoot()` function definition | 7 | 5 | 30 |
| `const execFileAsync = promisify(execFile)` + imports | 7 | 3 | 18 |
| `new StdioServerTransport()` + `server.connect()` + `.catch()` | 7 | 7 | 42 |
| `import { McpServer }` + `import { StdioServerTransport }` | 7 | 2 | 7 |
| `import { z } from "zod"` | 7 | 1 | 0 (kept per-file) |
| Error handling: killed/ENOENT/general pattern | ~20 | 8 | 140 |
| `handleRepoRootError` pattern | 7 | 4 | 24 |
| **Total estimated duplicated lines** | | | **~245** |

### A.2 Shell Script Duplication (Exact or Near-Exact Matches)

| Pattern | Occurrences | Lines Each | Total Duplicated |
|---------|------------|-----------|-----------------|
| `say()/warn()/err()/have()` function block | 5 | 4 | 16 |
| Color code definitions (RED/GREEN/YELLOW/NC) | 8+ | 4 | 28 |
| `SCRIPT_DIR` / `REPO_ROOT` detection | 20+ | 2 | 40 |
| Test framework (`pass/fail/print_header/print_test`) | 13 | 20 | 240 |
| Assert functions (`assertEqual/assertContains/assertExitCode/assertFileExists/assertDirExists`) | 10 | 30 | 270 |
| Test summary block | 13 | 12 | 144 |
| `_load_env_claude` block | 3 | 10 | 20 |
| **Total estimated duplicated lines** | | | **~700+** |

---

## Appendix B: Interface Contracts

### B.1 `getRepoRoot()` Contract

```
Input:  options?: { fallback?: boolean, timeout?: number }
Output: Promise<string> (absolute path to repo root)
Throws: Error if git fails and fallback is false
```

### B.2 `execSafe()` Contract

```
Input:  command: string, args: string[], options?: { timeout, maxBuffer, env, cwd }
Output: { success: true, stdout: string, stderr: string }
      | { success: false, error: string, message: string, stderr?: string }
Never throws.
```

### B.3 `makeTextResponse()` / `makeErrorResponse()` Contract

```
Input:  text: string
Output: { content: [{ type: "text", text }] }          (text)
      | { content: [{ type: "text", text }], isError: true }  (error)
```

### B.4 `validateFilePath()` Contract

```
Input:  filePath: string, repoRoot: string, options?: { checkReadable?: boolean }
Output: Promise<{ absPath: string, relToRepo: string }>
      | Promise<{ error: string }>
Never throws.
```

### B.5 Shell `test-framework.sh` Contract

```
Globals set: TESTS_TOTAL, TESTS_PASSED, TESTS_FAILED (integers)
Functions:   print_header(title), print_test(name),
             pass(desc), fail(desc),
             assertEqual(expected, actual, desc),
             assertContains(haystack, needle, desc),
             assertExitCode(expected, actual, desc),
             assertFileExists(path, desc),
             assertDirExists(path, desc),
             assertNotContains(haystack, needle, desc),
             print_summary(), get_exit_code()
Requires:    common.sh sourced first (_COMMON_SH_LOADED set)
```

---

*End of Technical Design Document*
