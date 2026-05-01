#!/usr/bin/env node

/**
 * Factory MCP Server — Ctags
 *
 * Provides code_index_ctags tool for generating ctags indexes.
 * Supports real incremental indexing via git diff + ctags --append,
 * with automatic full-rebuild fallback when correctness is at risk.
 *
 * State is persisted in .claude/index-state.json so incremental
 * indexing can resume across sessions.
 *
 * Requires: git, ctags (Universal Ctags preferred).
 *
 * Uses stdio transport. Launched automatically by Claude Code
 * via the .mcp.json config at the repository root.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { writeFile, readFile, unlink, access } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
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

// Incremental → full fallback thresholds
const MAX_CHANGED_FILES = 1500;
const STALENESS_MS = 24 * 60 * 60 * 1000; // 24 hours

const STATE_FILENAME = "index-state.json";

// Cached ctags capability detection (lazy, once per process)
let cachedCapabilities = null;

async function getHeadSha(repoRoot) {
  try {
    const { stdout } = await execFileAsync("git", ["rev-parse", "HEAD"], {
      cwd: repoRoot,
      timeout: TIMEOUTS.GIT,
    });
    return stdout.trim();
  } catch {
    return null;
  }
}

async function fileExists(path) {
  try {
    await access(path, constants.F_OK);
    return true;
  } catch {
    return false;
  }
}

/**
 * Detect which flags the installed ctags supports.
 * Runs once per server lifetime; result is cached.
 */
async function detectCtagsCapabilities() {
  try {
    const { stdout, stderr } = await execFileAsync("ctags", ["--version"], {
      timeout: 5000,
    });
    const combined = (stdout + "\n" + stderr).toLowerCase();
    const isUniversal = combined.includes("universal ctags");
    const isExuberant = !isUniversal && combined.includes("exuberant ctags");

    if (!isUniversal && isExuberant) {
      console.error("[ctags] Note: Exuberant Ctags detected; using --extra (not --extras).");
    } else if (!isUniversal && !isExuberant) {
      console.error("[ctags] Warning: Unknown ctags variant; extended flags will be skipped.");
    }

    const supportsFields = isUniversal || isExuberant;
    const supportsExtras = isUniversal || isExuberant;
    let extrasFlag = "";
    if (isUniversal) extrasFlag = "--extras=+q";
    else if (isExuberant) extrasFlag = "--extra=+q";

    return { isUniversal, isExuberant, supportsFields, supportsExtras, extrasFlag };
  } catch {
    console.error("[ctags] Warning: could not detect ctags capabilities; extended flags will be skipped.");
    return { isUniversal: false, isExuberant: false, supportsFields: false, supportsExtras: false, extrasFlag: "" };
  }
}

async function getCtagsCapabilities() {
  if (cachedCapabilities === null) {
    cachedCapabilities = await detectCtagsCapabilities();
  }
  return cachedCapabilities;
}

function buildCtagsFlags(capabilities) {
  const flags = [];
  if (capabilities.supportsFields) flags.push("--fields=+lnS");
  if (capabilities.supportsExtras && capabilities.extrasFlag) flags.push(capabilities.extrasFlag);
  return flags;
}

function getStatePath(repoRoot) {
  return join(repoRoot, ".claude", STATE_FILENAME);
}

async function readState(repoRoot) {
  try {
    const raw = await readFile(getStatePath(repoRoot), "utf8");
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

async function writeState(repoRoot, state) {
  await writeFile(getStatePath(repoRoot), JSON.stringify(state, null, 2) + "\n");
}

/**
 * Check if a SHA is an ancestor of the current HEAD.
 */
async function shaExistsInHistory(repoRoot, sha) {
  try {
    await execFileAsync("git", ["merge-base", "--is-ancestor", sha, "HEAD"], {
      cwd: repoRoot,
      timeout: TIMEOUTS.GIT,
    });
    return true;
  } catch {
    return false;
  }
}

/**
 * Parse git diff --name-status output into changed files and risky change count.
 *
 * Status letters:
 *   A = added, M = modified, C = copied, T = type-change → include path
 *   D = deleted → risky (stale symbols)
 *   R = renamed → include NEW path, count as risky (old path symbols stale)
 */
function parseDiffNameStatus(output) {
  const changedFiles = [];
  let riskyChanges = 0;

  for (const line of output.split("\n")) {
    if (!line.trim()) continue;
    const parts = line.split("\t");
    const status = parts[0].charAt(0); // R100 → R, C050 → C

    if (status === "A" || status === "M" || status === "C" || status === "T") {
      changedFiles.push(parts[1]);
    } else if (status === "R") {
      // Rename: parts[1] = old, parts[2] = new
      changedFiles.push(parts[2]);
      riskyChanges++;
    } else if (status === "D") {
      riskyChanges++;
    }
  }

  return { changedFiles, riskyChanges };
}

// ── Full index ─────────────────────────────────────────────────

async function runFullIndex(repoRoot, tagsPath) {
  const result = await execFileAsync("git", ["ls-files"], {
    cwd: repoRoot,
    timeout: TIMEOUTS.GIT,
    maxBuffer: BUFFERS.LARGE,
  });
  const filesOutput = result.stdout.trim();
  const files = filesOutput.split("\n").filter(Boolean);

  if (files.length === 0) {
    return { success: true, fileCount: 0, message: "No tracked files found." };
  }

  const tmpFile = join(tmpdir(), `ctags-filelist-${process.pid}-${Date.now()}.txt`);
  await writeFile(tmpFile, filesOutput + "\n");

  try {
    const capabilities = await getCtagsCapabilities();
    const extraFlags = buildCtagsFlags(capabilities);
    await execFileAsync(
      "ctags",
      ["-L", tmpFile, "-f", tagsPath, ...extraFlags],
      { cwd: repoRoot, timeout: TIMEOUTS.CTAGS, maxBuffer: BUFFERS.LARGE }
    );
    return { success: true, fileCount: files.length };
  } finally {
    await unlink(tmpFile).catch(() => {});
  }
}

// ── Incremental index (append mode) ───────────────────────────

async function runIncrementalIndex(repoRoot, tagsPath, changedFiles) {
  if (changedFiles.length === 0) {
    return { success: true, fileCount: 0 };
  }

  const tmpFile = join(tmpdir(), `ctags-incr-${process.pid}-${Date.now()}.txt`);
  await writeFile(tmpFile, changedFiles.join("\n") + "\n");

  try {
    const capabilities = await getCtagsCapabilities();
    const extraFlags = buildCtagsFlags(capabilities);
    await execFileAsync(
      "ctags",
      ["--append", "-L", tmpFile, "-f", tagsPath, ...extraFlags],
      { cwd: repoRoot, timeout: TIMEOUTS.CTAGS, maxBuffer: BUFFERS.LARGE }
    );
    return { success: true, fileCount: changedFiles.length };
  } finally {
    await unlink(tmpFile).catch(() => {});
  }
}

// ── Server setup ───────────────────────────────────────────────

const server = new McpServer({
  name: "factory-ctags",
  version: "2.2.0",
});

// ── Tool: code_index_ctags ─────────────────────────────────────

server.tool(
  "code_index_ctags",
  [
    "Generate or update a ctags index for the repository.",
    "mode='incremental' uses git diff to update only changed files (fast).",
    "The tool auto-escalates to a full rebuild when correctness requires it",
    "(missing tags, stale state, many deletes/renames, 24h staleness, etc.).",
    "mode='full' always does a complete rebuild.",
  ].join(" "),
  {
    mode: z
      .enum(["full", "incremental"])
      .default("full")
      .describe("'incremental' updates only changed files (fast); auto-escalates to full when needed. 'full' always rebuilds."),
    output: z
      .string()
      .optional()
      .describe("Output path for the tags file. Defaults to 'tags' at the repository root."),
  },
  async ({ mode, output }) => {
    // ── Resolve repo root ──────────────────────────────────
    let repoRoot;
    try {
      repoRoot = await getRepoRoot();
    } catch (error) {
      return handleRepoRootError(error);
    }

    const tagsPath = output || join(repoRoot, "tags");
    const tagsExist = await fileExists(tagsPath);

    // ── Get current HEAD ───────────────────────────────────
    const headSha = await getHeadSha(repoRoot);

    // ── Full mode: always do a complete rebuild ────────────
    if (mode === "full") {
      return await doFullIndex(repoRoot, tagsPath, headSha, "full (explicit)");
    }

    // ── No HEAD (fresh repo with no commits): force full ──
    if (headSha === null) {
      return await doFullIndex(repoRoot, tagsPath, null,
        "incremental→full: HEAD does not exist (no commits yet)");
    }

    // ── Incremental mode: check fallback conditions ────────
    const state = await readState(repoRoot);
    const now = Date.now();
    let fallbackReason = null;

    if (!tagsExist) {
      fallbackReason = "tags file does not exist";
    } else if (!state || !state.last_indexed_sha) {
      fallbackReason = "state file missing or last_indexed_sha missing";
    } else if (!(await shaExistsInHistory(repoRoot, state.last_indexed_sha))) {
      fallbackReason = `last_indexed_sha (${state.last_indexed_sha.slice(0, 8)}) is not an ancestor of HEAD (likely rebase or force-push)`;
    } else if (state.last_full_indexed_at && (now - state.last_full_indexed_at) > STALENESS_MS) {
      fallbackReason = `last full index was >24h ago (${Math.round((now - state.last_full_indexed_at) / 3600000)}h)`;
    } else if (!state.last_full_indexed_at && state.last_indexed_at && (now - state.last_indexed_at) > STALENESS_MS) {
      fallbackReason = `last index was >24h ago and no full index timestamp recorded`;
    }

    if (fallbackReason) {
      return await doFullIndex(repoRoot, tagsPath, headSha, `incremental→full: ${fallbackReason}`);
    }

    // ── No early fallback — compute the diff ───────────────
    const lastSha = state.last_indexed_sha;

    // If HEAD hasn't moved, nothing to do
    if (lastSha === headSha) {
      return {
        content: [{
          type: "text",
          text: [
            "No changes since last index; skipping.",
            `HEAD: ${headSha.slice(0, 8)}`,
            `Last indexed: ${new Date(state.last_indexed_at).toISOString()}`,
          ].join("\n"),
        }],
      };
    }

    let diffOutput;
    try {
      const result = await execFileAsync(
        "git", ["diff", "--name-status", `${lastSha}..HEAD`],
        { cwd: repoRoot, timeout: TIMEOUTS.GIT, maxBuffer: BUFFERS.LARGE }
      );
      diffOutput = result.stdout;
    } catch (error) {
      return await doFullIndex(repoRoot, tagsPath, headSha,
        `incremental→full: git diff failed (${error.message})`);
    }

    const { changedFiles, riskyChanges } = parseDiffNameStatus(diffOutput);

    // Any deletes or renames → full rebuild (append cannot remove stale symbols)
    if (riskyChanges > 0) {
      return await doFullIndex(repoRoot, tagsPath, headSha,
        `incremental→full: ${riskyChanges} delete(s)/rename(s) detected — full rebuild required to remove stale symbols`);
    }

    // No changes at all
    if (changedFiles.length === 0) {
      await writeState(repoRoot, {
        ...state,
        last_indexed_sha: headSha,
        last_indexed_at: now,
        last_mode: "incremental",
      });
      return {
        content: [{
          type: "text",
          text: [
            "No file changes detected in diff; index is current.",
            `HEAD: ${headSha.slice(0, 8)}`,
          ].join("\n"),
        }],
      };
    }

    // Too many changed files → full rebuild
    if (changedFiles.length > MAX_CHANGED_FILES) {
      return await doFullIndex(repoRoot, tagsPath, headSha,
        `incremental→full: ${changedFiles.length} changed files exceeds threshold (${MAX_CHANGED_FILES})`);
    }

    // ── Attempt incremental append ─────────────────────────
    try {
      const result = await runIncrementalIndex(repoRoot, tagsPath, changedFiles);

      await writeState(repoRoot, {
        ...state,
        last_indexed_sha: headSha,
        last_indexed_at: now,
        last_mode: "incremental",
        last_file_count: result.fileCount,
        last_full_indexed_at: state.last_full_indexed_at, // preserve
      });

      return {
        content: [{
          type: "text",
          text: [
            "Incremental index updated successfully.",
            `Files updated: ${result.fileCount}`,
            `Risky changes (D/R): ${riskyChanges}`,
            `Output: ${tagsPath}`,
            `HEAD: ${headSha.slice(0, 8)}`,
          ].join("\n"),
        }],
      };
    } catch (error) {
      // Append failed — fall back to full
      if (error.code === "ENOENT") {
        return {
          content: [{
            type: "text",
            text: "ctags not found. Run ./install.sh to install Universal Ctags via Homebrew.",
          }],
          isError: true,
        };
      }
      return await doFullIndex(repoRoot, tagsPath, headSha,
        `incremental→full: ctags --append failed (${error.message})`);
    }
  }
);

// ── Full index with state update ───────────────────────────────

async function doFullIndex(repoRoot, tagsPath, headSha, reason) {
  const now = Date.now();

  try {
    const result = await runFullIndex(repoRoot, tagsPath);

    if (result.fileCount === 0) {
      return makeTextResponse("No tracked files found in the repository.");
    }

    await writeState(repoRoot, {
      last_indexed_sha: headSha,
      last_indexed_at: now,
      last_mode: "full",
      last_file_count: result.fileCount,
      last_full_indexed_at: now,
    });

    return makeTextResponse([
      "Tags generated successfully (full rebuild).",
      `Reason: ${reason}`,
      `Output: ${tagsPath}`,
      `Files indexed: ${result.fileCount}`,
      `HEAD: ${headSha ? headSha.slice(0, 8) : "(no commits)"}`,
    ].join("\n"));
  } catch (error) {
    return handleExecError(error, {
      command: "ctags",
      timeoutMs: TIMEOUTS.CTAGS,
      installHint: "ctags not found. Run ./install.sh to install Universal Ctags via Homebrew.",
      timeoutHint: `ctags timed out after ${TIMEOUTS.CTAGS / 1000}s. The repository may be very large.`,
    });
  }
}

// ── Start server ───────────────────────────────────────────────

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  console.error("Fatal: ctags MCP server failed to start:", error);
  process.exit(1);
});
