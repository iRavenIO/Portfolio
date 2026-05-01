// .claude/mcp/lib/errors.js
//
// Error handling utilities for Claude Factory MCP servers.
// Provides consistent response formatting and error message construction.

// ── Response Constructors ──────────────────────────────────

/**
 * Create a standard MCP text response.
 *
 * @param {string} text - The response text
 * @returns {{content: Array<{type: string, text: string}>}}
 *
 * @example
 * return makeTextResponse("Operation completed successfully");
 */
export function makeTextResponse(text) {
  return {
    content: [{ type: "text", text }],
  };
}

/**
 * Create an MCP error response.
 *
 * @param {string} text - The error message
 * @returns {{content: Array<{type: string, text: string}>, isError: true}}
 *
 * @example
 * return makeErrorResponse("File not found: config.json");
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
 * Covers the three most common error types:
 *   - killed (timeout)
 *   - ENOENT (command not found)
 *   - general execution failure
 *
 * @param {Error} error - The caught error from execFileAsync
 * @param {Object} context - Error context information
 * @param {string} context.command - The command that failed
 * @param {number} context.timeoutMs - The timeout value used (in milliseconds)
 * @param {string} [context.installHint] - Custom install instructions for ENOENT errors
 * @param {string} [context.timeoutHint] - Custom message for timeout errors
 * @returns {{content: Array, isError: true}}
 *
 * @example
 * try {
 *   await execFileAsync("rg", args, { timeout: 60000 });
 * } catch (error) {
 *   return handleExecError(error, {
 *     command: "rg",
 *     timeoutMs: 60000,
 *     installHint: "ripgrep not found. Run ./install.sh to install.",
 *   });
 * }
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
 *
 * Provides standardized error messages for git repo detection failures.
 *
 * @param {Error} error - The error from getRepoRoot()
 * @returns {{content: Array, isError: true}}
 *
 * @example
 * try {
 *   repoRoot = await getRepoRoot();
 * } catch (error) {
 *   return handleRepoRootError(error);
 * }
 */
export function handleRepoRootError(error) {
  if (error.code === "ENOENT") {
    return makeErrorResponse("git not found. Ensure git is installed and in PATH.");
  }
  return makeErrorResponse(`Failed to detect repository root: ${error.message}`);
}
