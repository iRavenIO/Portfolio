/**
 * env-loader.js — Environment Variable Loader for Claude Factory
 *
 * Loads environment variables from .claude/env.claude and optional local
 * overrides for Claude Factory MCP servers and tools. Provides graceful,
 * silent loading with no logging.
 *
 * Design principles:
 *   - Never overwrite existing process.env values
 *   - Never log variable names or values (security)
 *   - Graceful degradation (returns false on error, never throws)
 *   - Minimal dependencies (node:fs, node:path only)
 *
 * Usage:
 *   import { loadClaudeEnv } from "./lib/env-loader.js";
 *   loadClaudeEnv(); // Call once at server startup
 */

import { readFileSync, existsSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

/**
 * Find repository root by walking up from cwd looking for .git
 * @returns {string|null} Repository root path or null if not found
 */
function findRepoRoot() {
  let current = process.cwd();
  const root = "/";

  // Walk up directory tree until we find .git or reach root
  while (current !== root) {
    if (existsSync(resolve(current, ".git"))) {
      return current;
    }
    const parent = dirname(current);
    if (parent === current) break; // Reached root without finding .git
    current = parent;
  }

  return null;
}

/**
 * Parse env file content into key-value pairs
 * Supports:
 *   - KEY=value
 *   - KEY="value with spaces"
 *   - KEY='single quotes'
 *   - Comments (lines starting with #)
 *   - Empty lines
 *   - Inline comments (after value)
 *
 * @param {string} content - File content to parse
 * @returns {Record<string, string>} Parsed environment variables
 */
function parseEnvFile(content) {
  const env = {};
  const lines = content.split("\n");

  for (let line of lines) {
    // Trim whitespace
    line = line.trim();

    // Skip empty lines and comments
    if (!line || line.startsWith("#")) {
      continue;
    }

    // Find first = sign
    const equalsIndex = line.indexOf("=");
    if (equalsIndex === -1) {
      continue; // Skip malformed lines
    }

    // Extract key and value
    const key = line.slice(0, equalsIndex).trim();
    let value = line.slice(equalsIndex + 1).trim();

    // Skip invalid keys (empty or containing spaces)
    if (!key || key.includes(" ")) {
      continue;
    }

    // Handle quoted values
    if (
      (value.startsWith('"') && value.includes('"', 1)) ||
      (value.startsWith("'") && value.includes("'", 1))
    ) {
      const quote = value[0];
      const endQuote = value.indexOf(quote, 1);
      if (endQuote !== -1) {
        value = value.slice(1, endQuote);
      }
    } else {
      // Handle inline comments (not inside quotes)
      const commentIndex = value.indexOf("#");
      if (commentIndex !== -1) {
        value = value.slice(0, commentIndex).trim();
      }
    }

    env[key] = value;
  }

  return env;
}

/**
 * Load environment variables from repo-local Claude Factory env files.
 *
 * Search order:
 *   Base file:
 *     1. .claude/env.claude (primary)
 *     2. .claude.env (fallback for compatibility)
 *   Local override file:
 *     1. .claude/env.claude.local (primary)
 *     2. .claude.env.local (fallback for compatibility)
 *
 * @param {Object} options - Loading options
 * @param {string} [options.repoRoot] - Repository root path (auto-detected if not provided)
 * @param {boolean} [options.overwrite=false] - Overwrite existing env vars (NOT RECOMMENDED)
 * @returns {boolean} True if file was loaded, false otherwise
 */
export function loadClaudeEnv(options = {}) {
  const { repoRoot: providedRoot = null, overwrite = false } = options;

  // Find repository root
  const repoRoot = providedRoot || findRepoRoot();
  if (!repoRoot) {
    return false; // Not in a git repository
  }

  const basePaths = [
    resolve(repoRoot, ".claude", "env.claude"),
    resolve(repoRoot, ".claude.env"),
  ];
  const localPaths = [
    resolve(repoRoot, ".claude", "env.claude.local"),
    resolve(repoRoot, ".claude.env.local"),
  ];

  const filesToLoad = [];
  const pickFirstExisting = (paths) => paths.find((path) => existsSync(path)) || null;

  const baseFile = pickFirstExisting(basePaths);
  const localFile = pickFirstExisting(localPaths);

  if (baseFile) {
    filesToLoad.push(baseFile);
  }
  if (localFile) {
    filesToLoad.push(localFile);
  }

  // No env file found
  if (filesToLoad.length === 0) {
    return false;
  }

  const originalKeys = new Set(Object.keys(process.env));

  let loadedCount = 0;
  for (const filePath of filesToLoad) {
    let content;
    try {
      content = readFileSync(filePath, "utf8");
    } catch (error) {
      continue;
    }

    const env = parseEnvFile(content);
    for (const [key, value] of Object.entries(env)) {
      // Preserve true process env values unless overwrite is explicitly enabled.
      if (!overwrite && originalKeys.has(key)) {
        continue;
      }

      process.env[key] = value;
      loadedCount++;
    }
  }

  return loadedCount > 0;
}

/**
 * Get current module directory (for testing)
 * @returns {string} Directory path of this module
 */
export function getModuleDir() {
  return dirname(fileURLToPath(import.meta.url));
}
