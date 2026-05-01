// .claude/mcp/lib/core.js
//
// Core utilities for Claude Factory MCP servers.
// Provides repo root detection, safe command execution, and shared constants.

import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

// ── Timeout Constants ──────────────────────────────────────
/**
 * Standard timeout values for different operation types.
 * Servers can override these per-call if needed.
 */
export const TIMEOUTS = {
  GIT: 30_000,           // 30s - git operations (standard)
  GIT_FAST: 5_000,       // 5s - git operations (ops server, latency-sensitive)
  CTAGS: 180_000,        // 3min - ctags indexing
  RG: 60_000,            // 1min - ripgrep search
  QUERY: 30_000,         // 30s - jq/yq queries
  SEARCH: 120_000,       // 2min - web search
  SAY: 60_000,           // 1min - speech
};

/**
 * Standard buffer size limits for command output.
 */
export const BUFFERS = {
  DEFAULT: 5 * 1024 * 1024,   // 5 MB
  LARGE: 10 * 1024 * 1024,    // 10 MB
  SMALL: 1024 * 1024,         // 1 MB
};

// ── getRepoRoot ────────────────────────────────────────────
/**
 * Detect the git repository root directory.
 *
 * Two behaviors supported:
 *   - Standard (default): throws on failure
 *   - Fallback: returns process.cwd() on failure (for server-ops.js)
 *
 * @param {Object} [options] - Configuration options
 * @param {boolean} [options.fallback=false] - If true, return cwd instead of throwing on error
 * @param {number} [options.timeout=TIMEOUTS.GIT] - Timeout in milliseconds
 * @returns {Promise<string>} Absolute path to repository root
 * @throws {Error} If git fails and fallback is false
 *
 * @example
 * // Standard usage (throws on error)
 * const repoRoot = await getRepoRoot();
 *
 * @example
 * // Fallback mode (for ops server)
 * const repoRoot = await getRepoRoot({ fallback: true });
 */
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
/**
 * Execute a command with structured error handling (non-throwing).
 *
 * Returns a result object instead of throwing, making it easier to handle
 * different error conditions. Used by server-ops.js and available for other servers.
 *
 * @param {string} command - Command to execute
 * @param {string[]} args - Command arguments
 * @param {Object} [options] - Execution options
 * @param {number} [options.timeout=10000] - Timeout in milliseconds
 * @param {number} [options.maxBuffer=BUFFERS.DEFAULT] - Output buffer size
 * @param {Object} [options.env] - Environment variables
 * @param {string} [options.cwd] - Working directory
 * @returns {Promise<{success: true, stdout: string, stderr: string} | {success: false, error: string, message: string, stderr?: string}>}
 *
 * @example
 * const result = await execSafe('ls', ['-la'], { timeout: 5000 });
 * if (result.success) {
 *   console.log(result.stdout);
 * } else {
 *   console.error(result.message);
 * }
 */
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
/**
 * Promisified version of Node's execFile.
 * Use this for standard async command execution that throws on error.
 * Use execSafe() if you need non-throwing structured error handling.
 */
export { execFileAsync };
