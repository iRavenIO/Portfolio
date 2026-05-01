#!/usr/bin/env node

/**
 * Factory MCP Server — Query
 *
 * Provides structured data query tools:
 *   - query_json → run jq expressions against JSON files
 *   - query_yaml → run yq expressions against YAML files
 *
 * Requires: jq (for query_json), yq (for query_yaml).
 * Each tool gracefully handles the case where its binary is not installed.
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
  validateFilePath,
  TIMEOUTS,
  BUFFERS,
} from "./lib/index.js";

loadClaudeEnv();

// ── Server setup ───────────────────────────────────────────────

const server = new McpServer({
  name: "factory-query",
  version: "1.0.0",
});

// ── Tool: query_json ───────────────────────────────────────────

server.tool(
  "query_json",
  "Run a jq expression against a JSON file. Returns the query result. Requires jq to be installed.",
  {
    file_path: z
      .string()
      .min(1, "File path must not be empty")
      .describe("Path to the JSON file (relative to repo root, or absolute)."),
    expression: z
      .string()
      .min(1, "Expression must not be empty")
      .describe("jq filter expression, e.g. '.dependencies', '.[] | .name'."),
    raw_output: z
      .boolean()
      .optional()
      .default(false)
      .describe("If true, output raw strings without JSON quotes (jq -r)."),
  },
  async ({ file_path, expression, raw_output }) => {
    let repoRoot;
    try {
      repoRoot = await getRepoRoot();
    } catch (error) {
      return handleRepoRootError(error);
    }

    const validated = await validateFilePath(file_path, repoRoot);
    if (validated.error) {
      return makeErrorResponse(validated.error);
    }

    const args = [];
    if (raw_output) args.push("-r");
    args.push(expression, validated.absPath);

    try {
      const { stdout } = await execFileAsync("jq", args, {
        cwd: repoRoot,
        timeout: TIMEOUTS.QUERY,
        maxBuffer: BUFFERS.DEFAULT,
      });

      const output = stdout.trim();
      if (!output) {
        return makeTextResponse("Query returned empty result.");
      }

      return makeTextResponse(output);
    } catch (error) {
      return handleExecError(error, {
        command: "jq",
        timeoutMs: TIMEOUTS.QUERY,
        installHint: "jq not found. Install with: brew install jq",
        timeoutHint: `Query timed out after ${TIMEOUTS.QUERY / 1000}s. Try a simpler expression.`,
      });
    }
  }
);

// ── Tool: query_yaml ───────────────────────────────────────────

server.tool(
  "query_yaml",
  "Run a yq expression against a YAML file. Returns the query result. Requires yq to be installed.",
  {
    file_path: z
      .string()
      .min(1, "File path must not be empty")
      .describe("Path to the YAML file (relative to repo root, or absolute)."),
    expression: z
      .string()
      .min(1, "Expression must not be empty")
      .describe("yq expression, e.g. '.services', '.spec.containers[].image'."),
    raw_output: z
      .boolean()
      .optional()
      .default(false)
      .describe("If true, output raw strings without YAML formatting (yq -r)."),
  },
  async ({ file_path, expression, raw_output }) => {
    let repoRoot;
    try {
      repoRoot = await getRepoRoot();
    } catch (error) {
      return handleRepoRootError(error);
    }

    const validated = await validateFilePath(file_path, repoRoot);
    if (validated.error) {
      return makeErrorResponse(validated.error);
    }

    const args = [];
    if (raw_output) args.push("-r");
    args.push(expression, validated.absPath);

    try {
      const { stdout } = await execFileAsync("yq", args, {
        cwd: repoRoot,
        timeout: TIMEOUTS.QUERY,
        maxBuffer: BUFFERS.DEFAULT,
      });

      const output = stdout.trim();
      if (!output) {
        return makeTextResponse("Query returned empty result.");
      }

      return makeTextResponse(output);
    } catch (error) {
      return handleExecError(error, {
        command: "yq",
        timeoutMs: TIMEOUTS.QUERY,
        installHint: "yq not found. Install with: brew install yq",
        timeoutHint: `Query timed out after ${TIMEOUTS.QUERY / 1000}s. Try a simpler expression.`,
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
  console.error("Fatal: query MCP server failed to start:", error);
  process.exit(1);
});
