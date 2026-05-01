#!/usr/bin/env node

/**
 * test-env-loader.js — Unit Tests for env-loader.js
 *
 * Tests parsing, loading, local overrides, quoting, comments, overwrite protection
 * Uses node:assert and node:fs for testing
 * Cleans up temp files after tests
 *
 * Run: node .claude/mcp/lib/test-env-loader.js
 * Expected: 11 tests passing
 */

import { strict as assert } from "node:assert";
import { writeFileSync, unlinkSync, existsSync, mkdirSync, rmSync } from "node:fs";
import { resolve, dirname } from "node:path";
import { tmpdir } from "node:os";
import { loadClaudeEnv, getModuleDir } from "./env-loader.js";

// Colors for output
const GREEN = "\x1b[32m";
const RED = "\x1b[31m";
const YELLOW = "\x1b[33m";
const RESET = "\x1b[0m";

// Test counters
let testsRun = 0;
let testsPassed = 0;
let testsFailed = 0;

// Helper functions
function pass(name) {
  console.log(`${GREEN}✓${RESET} ${name}`);
  testsPassed++;
  testsRun++;
}

function fail(name, error) {
  console.log(`${RED}✗${RESET} ${name}`);
  console.log(`  Error: ${error.message}`);
  testsFailed++;
  testsRun++;
}

function info(message) {
  console.log(`${YELLOW}ℹ${RESET} ${message}`);
}

// Test helpers
function createTestEnvFile(path, content) {
  const dir = dirname(path);
  if (!existsSync(dir)) {
    mkdirSync(dir, { recursive: true });
  }
  writeFileSync(path, content, "utf8");
}

function cleanupTestFile(path) {
  if (existsSync(path)) {
    unlinkSync(path);
  }
}

// Create temp test directory
const testDir = resolve(tmpdir(), `env-loader-test-${Date.now()}`);
const testRepoRoot = resolve(testDir, "test-repo");
const testClaudeDir = resolve(testRepoRoot, ".claude");
const testEnvFile = resolve(testClaudeDir, "env.claude");
const testLocalEnvFile = resolve(testClaudeDir, "env.claude.local");
const testGitDir = resolve(testRepoRoot, ".git");

// Cleanup function
function cleanup() {
  try {
    if (existsSync(testDir)) {
      rmSync(testDir, { recursive: true, force: true });
    }
  } catch (error) {
    // Ignore cleanup errors
  }
}

process.on("exit", cleanup);

// ============================================================================
// TEST SUITE
// ============================================================================

info("Starting env-loader.js test suite");

// Test 1: Parse simple KEY=VALUE
try {
  const { parseEnvFile } = await import("./env-loader.js");
  // We need to test parseEnvFile but it's not exported, so we test via loadClaudeEnv

  // Create test file
  const content = "TEST_KEY=test_value";
  createTestEnvFile(testEnvFile, content);
  mkdirSync(testGitDir, { recursive: true });

  // Load and verify
  const result = loadClaudeEnv({ repoRoot: testRepoRoot });
  assert.equal(result, true, "loadClaudeEnv should return true");
  assert.equal(process.env.TEST_KEY, "test_value", "Environment variable should be set");

  delete process.env.TEST_KEY;
  cleanupTestFile(testEnvFile);
  pass("Test 1: Parse simple KEY=VALUE");
} catch (error) {
  fail("Test 1: Parse simple KEY=VALUE", error);
}

// Test 2: Parse double-quoted values
try {
  const content = 'TEST_QUOTED="value with spaces"';
  createTestEnvFile(testEnvFile, content);

  loadClaudeEnv({ repoRoot: testRepoRoot });
  assert.equal(process.env.TEST_QUOTED, "value with spaces", "Quoted value should preserve spaces");

  delete process.env.TEST_QUOTED;
  cleanupTestFile(testEnvFile);
  pass("Test 2: Parse double-quoted values");
} catch (error) {
  fail("Test 2: Parse double-quoted values", error);
}

// Test 3: Parse single-quoted values
try {
  const content = "TEST_SINGLE='single quoted value'";
  createTestEnvFile(testEnvFile, content);

  loadClaudeEnv({ repoRoot: testRepoRoot });
  assert.equal(process.env.TEST_SINGLE, "single quoted value", "Single-quoted value should work");

  delete process.env.TEST_SINGLE;
  cleanupTestFile(testEnvFile);
  pass("Test 3: Parse single-quoted values");
} catch (error) {
  fail("Test 3: Parse single-quoted values", error);
}

// Test 4: Skip comments
try {
  const content = `# This is a comment
TEST_UNCOMMENTED=value
# Another comment`;
  createTestEnvFile(testEnvFile, content);

  loadClaudeEnv({ repoRoot: testRepoRoot });
  assert.equal(process.env.TEST_UNCOMMENTED, "value", "Should load value and skip comments");

  delete process.env.TEST_UNCOMMENTED;
  cleanupTestFile(testEnvFile);
  pass("Test 4: Skip comments");
} catch (error) {
  fail("Test 4: Skip comments", error);
}

// Test 5: Skip empty lines
try {
  const content = `TEST_FIRST=value1

TEST_SECOND=value2


TEST_THIRD=value3`;
  createTestEnvFile(testEnvFile, content);

  loadClaudeEnv({ repoRoot: testRepoRoot });
  assert.equal(process.env.TEST_FIRST, "value1", "First value should load");
  assert.equal(process.env.TEST_SECOND, "value2", "Second value should load");
  assert.equal(process.env.TEST_THIRD, "value3", "Third value should load");

  delete process.env.TEST_FIRST;
  delete process.env.TEST_SECOND;
  delete process.env.TEST_THIRD;
  cleanupTestFile(testEnvFile);
  pass("Test 5: Skip empty lines");
} catch (error) {
  fail("Test 5: Skip empty lines", error);
}

// Test 6: Handle inline comments
try {
  const content = "TEST_INLINE=value # this is a comment";
  createTestEnvFile(testEnvFile, content);

  loadClaudeEnv({ repoRoot: testRepoRoot });
  assert.equal(process.env.TEST_INLINE, "value", "Should strip inline comment");

  delete process.env.TEST_INLINE;
  cleanupTestFile(testEnvFile);
  pass("Test 6: Handle inline comments");
} catch (error) {
  fail("Test 6: Handle inline comments", error);
}

// Test 7: Never overwrite existing env vars (default)
try {
  process.env.TEST_EXISTING = "original_value";

  const content = "TEST_EXISTING=new_value";
  createTestEnvFile(testEnvFile, content);

  loadClaudeEnv({ repoRoot: testRepoRoot });
  assert.equal(process.env.TEST_EXISTING, "original_value", "Should not overwrite existing value");

  delete process.env.TEST_EXISTING;
  cleanupTestFile(testEnvFile);
  pass("Test 7: Never overwrite existing env vars (default)");
} catch (error) {
  fail("Test 7: Never overwrite existing env vars", error);
}

// Test 8: Overwrite when explicitly enabled
try {
  process.env.TEST_OVERWRITE = "original_value";

  const content = "TEST_OVERWRITE=new_value";
  createTestEnvFile(testEnvFile, content);

  loadClaudeEnv({ repoRoot: testRepoRoot, overwrite: true });
  assert.equal(process.env.TEST_OVERWRITE, "new_value", "Should overwrite when option enabled");

  delete process.env.TEST_OVERWRITE;
  cleanupTestFile(testEnvFile);
  pass("Test 8: Overwrite when explicitly enabled");
} catch (error) {
  fail("Test 8: Overwrite when explicitly enabled", error);
}

// Test 9: Return false when file doesn't exist
try {
  cleanupTestFile(testLocalEnvFile);
  cleanupTestFile(testEnvFile); // Ensure file doesn't exist

  const result = loadClaudeEnv({ repoRoot: testRepoRoot });
  assert.equal(result, false, "Should return false when file doesn't exist");

  pass("Test 9: Return false when file doesn't exist");
} catch (error) {
  fail("Test 9: Return false when file doesn't exist", error);
}

// Test 10: Local env overrides base env
try {
  createTestEnvFile(testEnvFile, "TEST_SHARED=base_value\nTEST_BASE_ONLY=base_only");
  createTestEnvFile(testLocalEnvFile, "TEST_SHARED=local_value\nTEST_LOCAL_ONLY=local_only");

  loadClaudeEnv({ repoRoot: testRepoRoot });
  assert.equal(process.env.TEST_SHARED, "local_value", "Local file should override base file");
  assert.equal(process.env.TEST_BASE_ONLY, "base_only", "Base-only value should still load");
  assert.equal(process.env.TEST_LOCAL_ONLY, "local_only", "Local-only value should load");

  delete process.env.TEST_SHARED;
  delete process.env.TEST_BASE_ONLY;
  delete process.env.TEST_LOCAL_ONLY;
  cleanupTestFile(testEnvFile);
  cleanupTestFile(testLocalEnvFile);
  pass("Test 10: Local env overrides base env");
} catch (error) {
  fail("Test 10: Local env overrides base env", error);
}

// Test 11: Return false when not in git repo
try {
  // Remove .git directory
  if (existsSync(testGitDir)) {
    rmSync(testGitDir, { recursive: true, force: true });
  }

  const result = loadClaudeEnv({ repoRoot: testRepoRoot });
  assert.equal(result, false, "Should return false when .git not found");

  pass("Test 11: Return false when not in git repo");
} catch (error) {
  fail("Test 11: Return false when not in git repo", error);
}

// ============================================================================
// SUMMARY
// ============================================================================

console.log("");
console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
console.log("Test Results: env-loader.js");
console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
console.log(`Total Tests:  ${testsRun}`);
console.log(`Passed:       ${GREEN}${testsPassed}${RESET}`);
console.log(`Failed:       ${RED}${testsFailed}${RESET}`);
console.log("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

if (testsFailed === 0) {
  console.log(`${GREEN}✓ All tests passed${RESET}`);
  process.exit(0);
} else {
  console.log(`${RED}✗ ${testsFailed} test(s) failed${RESET}`);
  process.exit(1);
}
