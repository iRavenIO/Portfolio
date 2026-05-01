// .claude/mcp/lib/validation.js
//
// Path validation and security utilities for Claude Factory MCP servers.
// Prevents directory traversal attacks and validates file accessibility.

import { join, relative, isAbsolute } from "node:path";
import { access } from "node:fs/promises";
import { constants } from "node:fs";

/**
 * Validate that a file path is inside the repository and optionally readable.
 *
 * Extracted from server-query.js's validateFilePath and generalized for all servers.
 * Provides directory traversal protection and optional readability checking.
 *
 * @param {string} filePath - Relative or absolute path to validate
 * @param {string} repoRoot - Repository root directory (absolute path)
 * @param {Object} [options] - Validation options
 * @param {boolean} [options.checkReadable=true] - Also verify file exists and is readable
 * @returns {Promise<{absPath: string, relToRepo: string} | {error: string}>}
 *
 * @example
 * // Standard file validation (checks readability)
 * const result = await validateFilePath("src/index.js", repoRoot);
 * if (result.error) {
 *   return makeErrorResponse(result.error);
 * }
 * const { absPath, relToRepo } = result;
 *
 * @example
 * // Skip readability check (for git blame on paths git knows about)
 * const result = await validateFilePath("src/new-file.js", repoRoot, { checkReadable: false });
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
 *
 * Synchronous variant for directory validation. Does not check existence
 * (directories may not exist yet for tree/list operations).
 *
 * @param {string} dirPath - Relative or absolute directory path
 * @param {string} repoRoot - Repository root directory (absolute path)
 * @returns {{absPath: string, relToRepo: string} | {error: string}}
 *
 * @example
 * const result = validateDirPath("docs/policy", repoRoot);
 * if (result.error) {
 *   return makeErrorResponse(result.error);
 * }
 * const { absPath } = result;
 */
export function validateDirPath(dirPath, repoRoot) {
  const absPath = isAbsolute(dirPath) ? dirPath : join(repoRoot, dirPath);
  const relToRepo = relative(repoRoot, absPath);

  if (relToRepo.startsWith("..") || isAbsolute(relToRepo)) {
    return { error: `Path is outside the repository: ${dirPath}` };
  }

  return { absPath, relToRepo };
}
