#!/usr/bin/env node

/**
 * Factory MCP Server
 *
 * Project-scoped MCP server exposing three tools:
 *   - research.search_web  → runs gemini -p for web research
 *   - notify.say           → runs macOS say for voice notifications
 *   - git_repo_diff        → runs git diff for structured file change list
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

const MAX_QUERY_LENGTH = 500;
const MAX_SAY_LENGTH = 1000;

// ── Server setup ───────────────────────────────────────────────

const server = new McpServer({
  name: "factory-tools",
  version: "1.1.0",
});

// ── Tool A: research.search_web ────────────────────────────────

server.tool(
  "research_search_web",
  "Search the web using gemini CLI. Used by the Researcher agent to gather external knowledge, compare libraries, investigate best practices, and find documentation.",
  {
    query: z
      .string()
      .min(1, "Query must not be empty")
      .max(MAX_QUERY_LENGTH, `Query must be at most ${MAX_QUERY_LENGTH} characters`),
  },
  async ({ query }) => {
    try {
      // execFile passes args directly — no shell, no injection risk
      const { stdout, stderr } = await execFileAsync("gemini", ["-p", query], {
        timeout: TIMEOUTS.SEARCH,
        maxBuffer: BUFFERS.SMALL,
        env: { ...process.env },
      });

      const output = stdout.trim();
      const warnings = stderr.trim();

      if (!output && !warnings) {
        return makeTextResponse("Search returned no results. Try rephrasing the query.");
      }

      let text = output;
      if (warnings) {
        text += `\n\n--- stderr ---\n${warnings}`;
      }

      return makeTextResponse(text);
    } catch (error) {
      return handleExecError(error, {
        command: "gemini",
        timeoutMs: TIMEOUTS.SEARCH,
        installHint: "gemini command not found. Ensure it is installed and available in PATH.",
        timeoutHint: `Search timed out after ${TIMEOUTS.SEARCH / 1000}s. Try a more specific query.`,
      });
    }
  }
);

// ── Tool B: notify.say ─────────────────────────────────────────

server.tool(
  "notify_say",
  "Speak text aloud using macOS say command. Used by the Reporter agent to deliver a voice summary when a task is complete.",
  {
    text: z
      .string()
      .min(1, "Text must not be empty")
      .max(MAX_SAY_LENGTH, `Text must be at most ${MAX_SAY_LENGTH} characters`),
  },
  async ({ text }) => {
    try {
      // execFile passes args directly — no shell, no injection risk
      await execFileAsync("say", [text], {
        timeout: TIMEOUTS.SAY,
        env: { ...process.env },
      });

      return makeTextResponse(`Spoke aloud: "${text.slice(0, 80)}${text.length > 80 ? "..." : ""}"`);
    } catch (error) {
      return handleExecError(error, {
        command: "say",
        timeoutMs: TIMEOUTS.SAY,
        installHint: "say command not found. This tool requires macOS.",
        timeoutHint: `Speech timed out after ${TIMEOUTS.SAY / 1000}s. Text may have been too long.`,
      });
    }
  }
);

// ── Tool C: git.repo_diff ──────────────────────────────────────

server.tool(
  "git_repo_diff",
  "Get the list of changed files between two git refs using git diff --name-status. Returns structured output with file status (Added, Modified, Deleted, Renamed, Copied, Type-changed) and paths.",
  {
    base: z
      .string()
      .optional()
      .default("HEAD~1")
      .describe("Base git ref (commit, branch, tag). Defaults to HEAD~1."),
    head: z
      .string()
      .optional()
      .default("HEAD")
      .describe("Head git ref. Defaults to HEAD."),
  },
  async ({ base, head }) => {
    // ── Resolve repo root ──────────────────────────────────
    let repoRoot;
    try {
      repoRoot = await getRepoRoot();
    } catch (error) {
      return handleRepoRootError(error);
    }

    // ── Run git diff ───────────────────────────────────────
    try {
      const { stdout } = await execFileAsync(
        "git",
        ["diff", "--name-status", `${base}..${head}`],
        { cwd: repoRoot, timeout: TIMEOUTS.GIT, maxBuffer: BUFFERS.LARGE }
      );

      // ── Parse output ───────────────────────────────────────
      const entries = [];
      const statusLabels = {
        A: "Added",
        M: "Modified",
        D: "Deleted",
        R: "Renamed",
        C: "Copied",
        T: "Type-changed",
      };

      for (const line of stdout.split("\n")) {
        if (!line.trim()) continue;
        const parts = line.split("\t");
        const status = parts[0].charAt(0); // R100 → R, C050 → C
        const label = statusLabels[status] || "Unknown";

        if (status === "R" || status === "C") {
          // Rename/Copy: 3 parts [status, old_path, new_path]
          entries.push({
            status,
            label,
            old_path: parts[1],
            path: parts[2],
          });
        } else {
          // A/M/D/T: 2 parts [status, path]
          entries.push({
            status,
            label,
            path: parts[1],
          });
        }
      }

      return makeTextResponse(
        JSON.stringify({ base, head, total: entries.length, files: entries }, null, 2)
      );
    } catch (error) {
      return handleExecError(error, {
        command: "git",
        timeoutMs: TIMEOUTS.GIT,
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
  console.error("Fatal: MCP server failed to start:", error);
  process.exit(1);
});
