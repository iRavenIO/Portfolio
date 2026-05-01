#!/usr/bin/env node

/**
 * Factory MCP Server — Ripgrep
 *
 * Provides code_search_rg tool for fast code search.
 * Uses rg (ripgrep) which respects .gitignore by default.
 * Requires: rg (ripgrep), git.
 *
 * Uses stdio transport. Launched automatically by Claude Code
 * via the .mcp.json config at the repository root.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { loadClaudeEnv } from "./lib/env-loader.js";
import {
  getRepoRoot,
  execFileAsync,
  makeTextResponse,
  makeErrorResponse,
  handleExecError,
  handleRepoRootError,
  TIMEOUTS,
  BUFFERS,
} from "./lib/index.js";

loadClaudeEnv();

// ── Configuration ──────────────────────────────────────────────

const DEFAULT_MAX_RESULTS = 200;

// ── Server setup ───────────────────────────────────────────────

const server = new McpServer({
  name: "factory-rg",
  version: "1.0.0",
});

// ── Tool: code_search_rg ───────────────────────────────────────

server.tool(
  "code_search_rg",
  "Search code in the repository using ripgrep. Fast, respects .gitignore by default. Returns matching lines with file paths and line numbers.",
  {
    pattern: z
      .string()
      .min(1, "Pattern must not be empty")
      .describe("Regex pattern to search for."),
    path: z
      .string()
      .optional()
      .describe("Directory or file to search within. Defaults to repository root."),
    glob: z
      .union([z.string(), z.array(z.string())])
      .optional()
      .describe("Glob pattern(s) to filter files, e.g. '*.js' or ['*.ts', '*.tsx']."),
    max_results: z
      .number()
      .int()
      .positive()
      .max(1000)
      .optional()
      .default(DEFAULT_MAX_RESULTS)
      .describe("Maximum matching lines to return (1–1000, default 200)."),
  },
  async ({ pattern, path, glob, max_results }) => {
    // Resolve repository root
    let repoRoot;
    try {
      repoRoot = await getRepoRoot();
    } catch (error) {
      return handleRepoRootError(error);
    }

    const searchPath = path || repoRoot;

    // Build ripgrep arguments
    const args = [
      "--line-number",
      "--no-heading",
      "--color", "never",
    ];

    // Add glob filters
    if (glob) {
      const globs = Array.isArray(glob) ? glob : [glob];
      for (const g of globs) {
        args.push("--glob", g);
      }
    }

    args.push("--", pattern, searchPath);

    try {
      const { stdout } = await execFileAsync("rg", args, {
        cwd: repoRoot,
        timeout: TIMEOUTS.RG,
        maxBuffer: BUFFERS.DEFAULT,
      });

      const output = stdout.trim();
      if (!output) {
        return makeTextResponse("No matches found.");
      }

      // Truncate to max_results lines
      const lines = output.split("\n");
      let text;
      if (lines.length > max_results) {
        text = lines.slice(0, max_results).join("\n");
        text += `\n\n--- Truncated: showing ${max_results} of ${lines.length} matching lines. Use a more specific pattern or glob to narrow results. ---`;
      } else {
        text = output;
      }

      return makeTextResponse(text);
    } catch (error) {
      // ripgrep exit code 1 = no matches (normal, not an error)
      if (error.code === 1) {
        return makeTextResponse("No matches found.");
      }
      // ripgrep exit code 2 = actual error
      if (error.code === 2) {
        return makeErrorResponse(`Search failed: ${error.stderr || error.message}`);
      }
      // Handle standard errors (ENOENT, timeout, etc.)
      return handleExecError(error, {
        command: "rg",
        timeoutMs: TIMEOUTS.RG,
        installHint: "rg (ripgrep) not found. Run ./install.sh to install ripgrep via Homebrew.",
        timeoutHint: `Search timed out after ${TIMEOUTS.RG / 1000}s. Try a more specific pattern.`,
      });
    }
  }
);

// ── Start server ───────────────────────────────────────────────

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  console.error("Fatal: ripgrep MCP server failed to start:", error);
  process.exit(1);
});
