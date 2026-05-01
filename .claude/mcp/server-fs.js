#!/usr/bin/env node

/**
 * Factory MCP Server — File System
 *
 * Provides filesystem tools for efficient, targeted file access:
 *   - fs_tree       → depth-limited directory tree of tracked files
 *   - fs_read_range → read specific line range from a file
 *   - fs_list_files → glob-based listing of tracked files
 *
 * Uses git ls-files for .gitignore-aware file listing (no untracked
 * or ignored files leak through). fs_read_range uses pure Node.js
 * streaming APIs for efficient partial reads.
 *
 * Requires: git.
 *
 * Uses stdio transport. Launched automatically by Claude Code
 * via the .mcp.json config at the repository root.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { createReadStream } from "node:fs";
import { createInterface } from "node:readline";
import { join, relative, isAbsolute } from "node:path";
import { access } from "node:fs/promises";
import { constants } from "node:fs";
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

const DEFAULT_MAX_DEPTH = 3;
const MAX_DEPTH_LIMIT = 10;
const DEFAULT_READ_LIMIT = 200;
const MAX_READ_LIMIT = 2000;
const DEFAULT_LIST_LIMIT = 500;
const MAX_LIST_LIMIT = 5000;

function buildTree(filePaths, maxDepth, rootPrefix) {
  const tree = {};

  for (const filePath of filePaths) {
    let rel = filePath;
    if (rootPrefix) {
      if (!filePath.startsWith(rootPrefix)) continue;
      rel = filePath.slice(rootPrefix.length);
      if (rel.startsWith("/")) rel = rel.slice(1);
      if (!rel) continue;
    }

    const parts = rel.split("/");

    if (parts.length > maxDepth) {
      let node = tree;
      for (let i = 0; i < maxDepth; i++) {
        const part = parts[i];
        if (i === maxDepth - 1) {
          if (!node[part + "/"]) node[part + "/"] = { "...": null };
          else if (!node[part + "/"]["..."]) node[part + "/"]["..."] = null;
        } else {
          if (!node[part + "/"]) node[part + "/"] = {};
          node = node[part + "/"];
        }
      }
      continue;
    }

    let node = tree;
    for (let i = 0; i < parts.length; i++) {
      const part = parts[i];
      if (i === parts.length - 1) {
        node[part] = null;
      } else {
        if (!node[part + "/"]) node[part + "/"] = {};
        node = node[part + "/"];
      }
    }
  }

  const lines = [];

  function formatNode(node, indent) {
    const keys = Object.keys(node).sort((a, b) => {
      const aDir = a.endsWith("/");
      const bDir = b.endsWith("/");
      if (aDir && !bDir) return -1;
      if (!aDir && bDir) return 1;
      return a.localeCompare(b);
    });

    for (const key of keys) {
      if (key === "...") {
        lines.push(`${indent}...`);
      } else if (node[key] === null) {
        lines.push(`${indent}${key}`);
      } else {
        lines.push(`${indent}${key}`);
        formatNode(node[key], indent + "  ");
      }
    }
  }

  formatNode(tree, "");
  return lines.join("\n");
}

async function readLineRange(filePath, offset, limit) {
  return new Promise((resolve, reject) => {
    const stream = createReadStream(filePath, { encoding: "utf8" });
    const rl = createInterface({ input: stream, crlfDelay: Infinity });

    let currentLine = 0;
    let linesCollected = 0;
    const lines = [];
    let finished = false;

    rl.on("line", (line) => {
      currentLine++;
      if (currentLine >= offset && linesCollected < limit) {
        const truncated = line.length > 2000 ? line.slice(0, 2000) + " [truncated]" : line;
        lines.push(`${String(currentLine).padStart(6)}\t${truncated}`);
        linesCollected++;
      }
      if (linesCollected >= limit) {
        finished = true;
        rl.close();
        stream.destroy();
      }
    });

    rl.on("close", () => {
      resolve({
        text: lines.join("\n"),
        totalLines: finished ? -1 : currentLine,
        linesReturned: linesCollected,
      });
    });

    rl.on("error", reject);
    stream.on("error", reject);
  });
}

// ── Server setup ───────────────────────────────────────────────

const server = new McpServer({
  name: "factory-fs",
  version: "1.0.0",
});

// ── Tool: fs_tree ──────────────────────────────────────────────

server.tool(
  "fs_tree",
  "Show a depth-limited directory tree of tracked files in the repository. Respects .gitignore. Useful for understanding project structure without listing every file.",
  {
    path: z
      .string()
      .optional()
      .describe("Subdirectory to show (relative to repo root). Defaults to repo root."),
    depth: z
      .number()
      .int()
      .min(1)
      .max(MAX_DEPTH_LIMIT)
      .optional()
      .default(DEFAULT_MAX_DEPTH)
      .describe(`Maximum directory depth to display (1-${MAX_DEPTH_LIMIT}, default ${DEFAULT_MAX_DEPTH}).`),
  },
  async ({ path, depth }) => {
    let repoRoot;
    try {
      repoRoot = await getRepoRoot();
    } catch (error) {
      return handleRepoRootError(error);
    }

    try {
      const { stdout } = await execFileAsync("git", ["ls-files"], {
        cwd: repoRoot,
        timeout: TIMEOUTS.GIT,
        maxBuffer: BUFFERS.LARGE,
      });

      const files = stdout.trim().split("\n").filter(Boolean);
      if (files.length === 0) {
        return makeTextResponse("No tracked files found.");
      }

      let rootPrefix = "";
      if (path) {
        // Validate path is within repo
        const absPath = isAbsolute(path) ? path : join(repoRoot, path);
        const relToRepo = relative(repoRoot, absPath);
        if (relToRepo.startsWith("..") || isAbsolute(relToRepo)) {
          return makeErrorResponse(`Path is outside the repository: ${path}`);
        }
        rootPrefix = relToRepo;
        const hasFiles = files.some((f) => f === rootPrefix || f.startsWith(rootPrefix + "/"));
        if (!hasFiles) {
          return makeTextResponse(`No tracked files found under path: ${path}`);
        }
      }

      const label = rootPrefix || ".";
      const tree = buildTree(files, depth, rootPrefix);
      const text = `${label}/\n${tree ? tree.split("\n").map((l) => "  " + l).join("\n") : "  (empty)"}`;

      return makeTextResponse(text);
    } catch (error) {
      return handleExecError(error, {
        command: "git ls-files",
        timeoutMs: TIMEOUTS.GIT,
      });
    }
  }
);

// ── Tool: fs_read_range ────────────────────────────────────────

server.tool(
  "fs_read_range",
  "Read a specific range of lines from a file. Efficient for large files — streams only the needed portion. Returns lines with line numbers (1-based). Lines longer than 2000 characters are truncated.",
  {
    path: z
      .string()
      .min(1, "Path must not be empty")
      .describe("File path (relative to repo root, or absolute)."),
    offset: z
      .number()
      .int()
      .min(1)
      .optional()
      .default(1)
      .describe("Line number to start reading from (1-based, default 1)."),
    limit: z
      .number()
      .int()
      .min(1)
      .max(MAX_READ_LIMIT)
      .optional()
      .default(DEFAULT_READ_LIMIT)
      .describe(`Number of lines to read (1-${MAX_READ_LIMIT}, default ${DEFAULT_READ_LIMIT}).`),
  },
  async ({ path: filePath, offset, limit }) => {
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

    try {
      await access(absPath, constants.R_OK);
    } catch {
      return makeErrorResponse(`File not found or not readable: ${filePath}`);
    }

    try {
      const result = await readLineRange(absPath, offset, limit);

      if (result.linesReturned === 0) {
        return makeTextResponse(`No lines found at offset ${offset}. The file may have fewer lines.`);
      }

      let header = `File: ${relToRepo}\nLines: ${offset}-${offset + result.linesReturned - 1}`;
      if (result.totalLines > 0) {
        header += ` (of ${result.totalLines} total)`;
      }
      header += "\n\n";

      return makeTextResponse(header + result.text);
    } catch (error) {
      return makeErrorResponse(`Failed to read file: ${error.message}`);
    }
  }
);

// ── Tool: fs_list_files ────────────────────────────────────────

server.tool(
  "fs_list_files",
  "List tracked files in the repository matching glob patterns. Respects .gitignore. Returns file paths relative to repo root, sorted alphabetically.",
  {
    pattern: z
      .union([z.string(), z.array(z.string())])
      .optional()
      .describe("Glob pattern(s) to match files, e.g. '*.js' or ['*.ts', '*.tsx']. If omitted, lists all tracked files."),
    path: z
      .string()
      .optional()
      .describe("Subdirectory to search within (relative to repo root). Defaults to repo root."),
    limit: z
      .number()
      .int()
      .min(1)
      .max(MAX_LIST_LIMIT)
      .optional()
      .default(DEFAULT_LIST_LIMIT)
      .describe(`Maximum number of files to return (1-${MAX_LIST_LIMIT}, default ${DEFAULT_LIST_LIMIT}).`),
  },
  async ({ pattern, path, limit }) => {
    let repoRoot;
    try {
      repoRoot = await getRepoRoot();
    } catch (error) {
      return handleRepoRootError(error);
    }

    // Validate path is within repo
    if (path) {
      const absPath = isAbsolute(path) ? path : join(repoRoot, path);
      const relToRepo = relative(repoRoot, absPath);
      if (relToRepo.startsWith("..") || isAbsolute(relToRepo)) {
        return makeErrorResponse(`Path is outside the repository: ${path}`);
      }
    }

    const args = ["ls-files"];

    if (path) {
      args.push("--", path);
    }

    try {
      const { stdout } = await execFileAsync("git", args, {
        cwd: repoRoot,
        timeout: TIMEOUTS.GIT,
        maxBuffer: BUFFERS.LARGE,
      });

      let files = stdout.trim().split("\n").filter(Boolean);

      if (pattern) {
        const patterns = Array.isArray(pattern) ? pattern : [pattern];
        const regexes = patterns.map(globToRegex);
        files = files.filter((f) => {
          const filename = f.split("/").pop();
          return regexes.some((re) => re.test(filename) || re.test(f));
        });
      }

      if (files.length === 0) {
        return makeTextResponse("No matching tracked files found.");
      }

      files.sort();

      let text;
      if (files.length > limit) {
        text = files.slice(0, limit).join("\n");
        text += `\n\n--- Truncated: showing ${limit} of ${files.length} matching files. Use a more specific pattern to narrow results. ---`;
      } else {
        text = files.join("\n");
        text += `\n\nTotal: ${files.length} file(s)`;
      }

      return makeTextResponse(text);
    } catch (error) {
      return handleExecError(error, {
        command: "git ls-files",
        timeoutMs: TIMEOUTS.GIT,
      });
    }
  }
);

function globToRegex(glob) {
  let regex = "";
  let i = 0;
  let braceDepth = 0;
  while (i < glob.length) {
    const c = glob[i];
    if (c === "*") {
      if (glob[i + 1] === "*") {
        regex += ".*";
        i += 2;
        if (glob[i] === "/") i++;
        continue;
      }
      regex += "[^/]*";
    } else if (c === "?") {
      regex += "[^/]";
    } else if (c === ".") {
      regex += "\\.";
    } else if (c === "(") {
      regex += "\\(";
    } else if (c === ")") {
      regex += "\\)";
    } else if (c === "{") {
      braceDepth++;
      regex += "(?:";
    } else if (c === "}") {
      braceDepth--;
      regex += ")";
    } else if (c === "," && braceDepth > 0) {
      regex += "|";
    } else if (c === "[") {
      regex += "[";
    } else if (c === "]") {
      regex += "]";
    } else {
      regex += c;
    }
    i++;
  }
  return new RegExp(`^${regex}$`);
}

// ── Start server ───────────────────────────────────────────────

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  console.error("Fatal: filesystem MCP server failed to start:", error);
  process.exit(1);
});
