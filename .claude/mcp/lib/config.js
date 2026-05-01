// .claude/mcp/lib/config.js
//
// Configuration loading utilities for Claude Factory MCP servers.
// Primarily used by server-ops.js but generic enough for any server needing config files.

import { readFileSync, existsSync, watchFile } from "node:fs";
import { resolve } from "node:path";

/**
 * Load a JSON config file with optional hot-reload.
 *
 * Extracted from server-ops.js loadOpsConfig pattern and generalized.
 *
 * @param {string} repoRoot - Repository root directory
 * @param {string} relativePath - Path relative to repo root (e.g., ".claude/config/ops.json")
 * @param {Object} [options] - Configuration options
 * @param {boolean} [options.watch=false] - Enable file watching for hot-reload
 * @param {number} [options.watchInterval=5000] - Watch interval in milliseconds
 * @param {Function} [options.onReload] - Callback(newConfig) when config is reloaded
 * @returns {{config: Object, configPath: string} | null} Config object and path, or null if not found
 *
 * @example
 * // Simple load
 * const result = loadJsonConfig(repoRoot, ".claude/config/ops.json");
 * if (!result) {
 *   console.error("Config not found");
 *   return;
 * }
 * const { config } = result;
 *
 * @example
 * // With hot-reload
 * let currentConfig;
 * const result = loadJsonConfig(repoRoot, ".claude/config/ops.json", {
 *   watch: true,
 *   onReload: (newConfig) => {
 *     currentConfig = newConfig;
 *     console.log("Config reloaded");
 *   }
 * });
 * currentConfig = result.config;
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
          // Silent fail on hot-reload errors (malformed JSON during edit, etc.)
        }
      });
    }

    return { config, configPath };
  } catch {
    // Parse error or read error
    return null;
  }
}

/**
 * Apply environment variable overrides to a config object.
 *
 * Uses a mapping array to define which env vars map to which config keys.
 * Supports nested config paths via dot notation.
 *
 * @param {Object} config - Base configuration object
 * @param {Array<{envVar: string, path: string, transform?: Function}>} mapping - Override mappings
 * @returns {Object} New config object with overrides applied
 *
 * @example
 * const config = { discovery: { timeout: 10000 } };
 * const overridden = applyEnvOverrides(config, [
 *   { envVar: "OPS_DISCOVERY_TIMEOUT", path: "discovery.timeout", transform: parseInt },
 *   { envVar: "OPS_PARALLEL", path: "parallel", transform: (v) => v === "true" }
 * ]);
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
