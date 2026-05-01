#!/usr/bin/env node

/**
 * Factory MCP Server — Git
 *
 * Provides granular git tools for repository introspection:
 *   - git_status       → working tree status (porcelain)
 *   - git_diff_stat    → diffstat summary between refs
 *   - git_log_oneline  → compact commit history
 *   - git_blame_range  → line-by-line authorship for a file range
 *
 * Does NOT duplicate git_repo_diff (in factory-tools server.js).
 *
 * Requires: git.
 *
 * Uses stdio transport. Launched automatically by Claude Code
 * via the .mcp.json config at the repository root.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { join, relative, isAbsolute } from "node:path";
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

const DEFAULT_LOG_COUNT = 20;
const MAX_LOG_COUNT = 200;
const DEFAULT_BLAME_LINES = 50;
const MAX_BLAME_LINES = 500;

// ── Server setup ───────────────────────────────────────────────

const server = new McpServer({
  name: "factory-git",
  version: "1.0.0",
});

// ── Tool A: git_status ─────────────────────────────────────────

server.tool(
  "git_status",
  "Show working tree status using git status --porcelain. Returns staged, unstaged, and untracked file changes in a compact machine-readable format.",
  {
    path: z
      .string()
      .optional()
      .describe("Subdirectory to limit status to (relative to repo root). Defaults to entire repo."),
  },
  async ({ path }) => {
    let repoRoot;
    try {
      repoRoot = await getRepoRoot();
    } catch (error) {
      return handleRepoRootError(error);
    }

    const args = ["status", "--porcelain=v1"];
    if (path) {
      args.push("--", path);
    }

    try {
      const { stdout } = await execFileAsync("git", args, {
        cwd: repoRoot,
        timeout: TIMEOUTS.GIT,
        maxBuffer: BUFFERS.LARGE,
      });

      const output = stdout.trim();
      if (!output) {
        return makeTextResponse("Working tree clean. No staged, unstaged, or untracked changes.");
      }

      return makeTextResponse(output);
    } catch (error) {
      return handleExecError(error, {
        command: "git status",
        timeoutMs: TIMEOUTS.GIT,
      });
    }
  }
);

// ── Tool B: git_diff_stat ──────────────────────────────────────

server.tool(
  "git_diff_stat",
  "Show a diffstat summary (files changed, insertions, deletions) using git diff --stat. Can compare working tree, staged changes, or between two refs.",
  {
    ref: z
      .string()
      .optional()
      .describe("Git ref to diff against (commit, branch, tag). If omitted, shows unstaged working tree changes."),
    staged: z
      .boolean()
      .optional()
      .default(false)
      .describe("If true, show staged (cached) changes instead of working tree changes. Ignored if ref is provided."),
    path: z
      .string()
      .optional()
      .describe("Limit diff to a specific path (relative to repo root)."),
  },
  async ({ ref, staged, path }) => {
    let repoRoot;
    try {
      repoRoot = await getRepoRoot();
    } catch (error) {
      return handleRepoRootError(error);
    }

    const args = ["diff", "--stat"];
    if (ref) {
      args.push(ref);
    } else if (staged) {
      args.push("--cached");
    }
    if (path) {
      args.push("--", path);
    }

    try {
      const { stdout } = await execFileAsync("git", args, {
        cwd: repoRoot,
        timeout: TIMEOUTS.GIT,
        maxBuffer: BUFFERS.LARGE,
      });

      const output = stdout.trim();
      if (!output) {
        return makeTextResponse("No differences found.");
      }

      return makeTextResponse(output);
    } catch (error) {
      return handleExecError(error, {
        command: "git diff",
        timeoutMs: TIMEOUTS.GIT,
      });
    }
  }
);

// ── Tool C: git_log_oneline ────────────────────────────────────

server.tool(
  "git_log_oneline",
  "Show recent commit history in compact one-line format. Returns abbreviated commit hash and subject for each commit.",
  {
    count: z
      .number()
      .int()
      .min(1)
      .max(MAX_LOG_COUNT)
      .optional()
      .default(DEFAULT_LOG_COUNT)
      .describe(`Number of commits to show (1-${MAX_LOG_COUNT}, default ${DEFAULT_LOG_COUNT}).`),
    path: z
      .string()
      .optional()
      .describe("Limit log to commits affecting this path (relative to repo root)."),
    ref: z
      .string()
      .optional()
      .describe("Starting ref (branch, tag, commit). Defaults to HEAD."),
  },
  async ({ count, path, ref }) => {
    let repoRoot;
    try {
      repoRoot = await getRepoRoot();
    } catch (error) {
      return handleRepoRootError(error);
    }

    const args = ["log", "--oneline", `-n`, String(count)];
    if (ref) {
      args.push(ref);
    }
    if (path) {
      args.push("--", path);
    }

    try {
      const { stdout } = await execFileAsync("git", args, {
        cwd: repoRoot,
        timeout: TIMEOUTS.GIT,
        maxBuffer: BUFFERS.LARGE,
      });

      const output = stdout.trim();
      if (!output) {
        return makeTextResponse("No commits found.");
      }

      return makeTextResponse(output);
    } catch (error) {
      return handleExecError(error, {
        command: "git log",
        timeoutMs: TIMEOUTS.GIT,
      });
    }
  }
);

// ── Tool D: git_blame_range ────────────────────────────────────

server.tool(
  "git_blame_range",
  "Show line-by-line authorship annotation for a specific range of lines in a file using git blame. Useful for understanding who changed specific code and when.",
  {
    path: z
      .string()
      .min(1, "Path must not be empty")
      .describe("File path (relative to repo root, or absolute)."),
    start_line: z
      .number()
      .int()
      .min(1)
      .describe("Starting line number (1-based)."),
    end_line: z
      .number()
      .int()
      .min(1)
      .optional()
      .describe(`Ending line number (1-based, inclusive). Defaults to start_line + ${DEFAULT_BLAME_LINES - 1}. Max range: ${MAX_BLAME_LINES} lines.`),
    ref: z
      .string()
      .optional()
      .describe("Git ref to blame at (commit, branch, tag). Defaults to HEAD."),
  },
  async ({ path: filePath, start_line, end_line, ref }) => {
    let repoRoot;
    try {
      repoRoot = await getRepoRoot();
    } catch (error) {
      return handleRepoRootError(error);
    }

    const absPath = isAbsolute(filePath) ? filePath : join(repoRoot, filePath);
    const relToRepo = relative(repoRoot, absPath);
    if (relToRepo.startsWith("..") || isAbsolute(relToRepo)) {
      return makeErrorResponse(`Path is outside the repository: ${filePath}`);
    }

    const effectiveEnd = end_line || (start_line + DEFAULT_BLAME_LINES - 1);
    if (effectiveEnd < start_line) {
      return makeErrorResponse(`end_line (${effectiveEnd}) must be >= start_line (${start_line}).`);
    }
    if ((effectiveEnd - start_line + 1) > MAX_BLAME_LINES) {
      return makeErrorResponse(`Range too large: ${effectiveEnd - start_line + 1} lines requested, maximum is ${MAX_BLAME_LINES}.`);
    }

    const args = ["blame", "-L", `${start_line},${effectiveEnd}`];
    if (ref) {
      args.push(ref);
    }
    args.push("--", relToRepo);

    try {
      const { stdout } = await execFileAsync("git", args, {
        cwd: repoRoot,
        timeout: TIMEOUTS.GIT,
        maxBuffer: BUFFERS.LARGE,
      });

      const output = stdout.trim();
      if (!output) {
        return makeTextResponse("No blame output. The file or line range may not exist.");
      }

      return makeTextResponse(`File: ${relToRepo}\nLines: ${start_line}-${effectiveEnd}\n\n${output}`);
    } catch (error) {
      const stderr = error.stderr || error.message;
      if (stderr.includes("no such path") || stderr.includes("does not exist")) {
        return makeErrorResponse(`File not found in repository: ${relToRepo}`);
      }
      return handleExecError(error, {
        command: "git blame",
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
  console.error("Fatal: git MCP server failed to start:", error);
  process.exit(1);
});
