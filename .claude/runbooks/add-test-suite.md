# Runbook: Add a Test Suite to the Factory

## When to Use

Use this runbook when adding automated tests for the factory infrastructure itself. This includes unit tests for MCP servers, integration tests for agent workflows, and end-to-end tests for the full pipeline.

## Prerequisites

- You have identified which factory component needs testing (MCP server, agent, workflow phase, or full pipeline)
- You know which test framework to use (e.g., Jest, Mocha, Vitest, Bats for shell scripts)
- You understand the factory's architecture and workflow (CLAUDE.md)

## Steps

### 1. Choose Test Framework and Scope

**Decision matrix:**

| Component to Test | Framework | Scope |
|-------------------|-----------|-------|
| MCP servers (.js) | Jest or Vitest | Unit + integration |
| Shell scripts (.sh) | Bats | Unit |
| Agent workflows | Manual test scripts | Integration |
| Full pipeline | Manual test scripts | E2E |

For this runbook, we'll use **Jest** for MCP server testing as the primary example.

### 2. Install Test Framework

**File:** `.claude/mcp/package.json`

Add test framework and dependencies:

```bash
cd .claude/mcp
npm install --save-dev jest @types/jest
```

Update `package.json`:
```json
{
  "scripts": {
    "test": "jest",
    "test:watch": "jest --watch",
    "test:coverage": "jest --coverage"
  },
  "jest": {
    "testEnvironment": "node",
    "testMatch": ["**/__tests__/**/*.test.js"],
    "collectCoverageFrom": ["server*.js"]
  }
}
```

### 3. Create Test Directory Structure

**In `.claude/mcp/`:**

```bash
mkdir -p __tests__/unit
mkdir -p __tests__/integration
mkdir -p __tests__/fixtures
```

Structure:
```
.claude/mcp/
├── __tests__/
│   ├── unit/
│   │   ├── server.test.js
│   │   ├── server-ctags.test.js
│   │   ├── server-rg.test.js
│   │   └── ...
│   ├── integration/
│   │   ├── mcp-workflow.test.js
│   │   └── ...
│   └── fixtures/
│       ├── sample-repo/
│       └── ...
├── server.js
├── server-ctags.js
└── package.json
```

### 4. Write Unit Tests for MCP Servers

**File:** `.claude/mcp/__tests__/unit/server-rg.test.js`

Example unit test structure:

```javascript
import { describe, it, expect, beforeAll, afterAll } from '@jest/globals';
import { spawn } from 'child_process';
import { promisify } from 'util';
import { writeFile, mkdir, rm } from 'fs/promises';
import { join } from 'path';

describe('factory-rg MCP server', () => {
  let serverProcess;
  const testDir = join(process.cwd(), '__tests__', 'fixtures', 'test-repo');

  beforeAll(async () => {
    // Set up test fixture
    await mkdir(testDir, { recursive: true });
    await writeFile(join(testDir, 'test.js'), 'function hello() {}');

    // Start MCP server
    serverProcess = spawn('node', ['server-rg.js'], {
      stdio: ['pipe', 'pipe', 'pipe']
    });
  });

  afterAll(async () => {
    // Clean up
    serverProcess.kill();
    await rm(testDir, { recursive: true, force: true });
  });

  it('should start without errors', (done) => {
    serverProcess.on('error', (err) => {
      throw err;
    });
    setTimeout(() => {
      expect(serverProcess.killed).toBe(false);
      done();
    }, 1000);
  });

  it('should respond to code_search_rg tool call', async () => {
    // Send MCP JSON-RPC request
    const request = {
      jsonrpc: '2.0',
      id: 1,
      method: 'tools/call',
      params: {
        name: 'code_search_rg',
        arguments: {
          pattern: 'function',
          path: testDir
        }
      }
    };

    serverProcess.stdin.write(JSON.stringify(request) + '\n');

    // Wait for response
    const response = await new Promise((resolve) => {
      serverProcess.stdout.once('data', (data) => {
        resolve(JSON.parse(data.toString()));
      });
    });

    expect(response.result).toBeDefined();
    expect(response.result.content).toBeDefined();
    expect(response.result.content[0].text).toContain('function hello');
  });
});
```

Repeat for all MCP servers:
- `server.test.js` (factory-tools: research_search_web, notify_say, git_repo_diff)
- `server-ctags.test.js` (factory-ctags: code_index_ctags)
- `server-rg.test.js` (factory-rg: code_search_rg)
- `server-fs.test.js` (factory-fs: fs_tree, fs_read_range, fs_list_files)
- `server-git.test.js` (factory-git: git_status, git_diff_stat, git_log_oneline, git_blame_range)
- `server-query.test.js` (factory-query: query_json, query_yaml)

### 5. Write Integration Tests

**File:** `.claude/mcp/__tests__/integration/mcp-workflow.test.js`

Test multi-tool workflows:

```javascript
describe('MCP server integration', () => {
  it('should complete code search + read workflow', async () => {
    // 1. Use factory-rg to find files
    // 2. Use factory-fs to read specific line ranges
    // 3. Verify workflow completes without errors
  });

  it('should complete ctags index + symbol lookup workflow', async () => {
    // 1. Use factory-ctags to index a test repo
    // 2. Verify tags file is created
    // 3. Search for a symbol using grep on tags
  });
});
```

### 6. Add Shell Script Tests (Optional)

**For testing shell scripts like `install.sh` and `health-check.sh`:**

Install Bats:
```bash
brew install bats-core
```

**File:** `.claude/tests/health-check.bats`

```bash
#!/usr/bin/env bats

setup() {
  # Set up test environment
  export TEST_MODE=1
}

@test "health-check.sh runs without errors" {
  run ./.claude/scripts/health-check.sh
  [ "$status" -eq 0 ]
}

@test "health-check.sh detects missing dependencies" {
  # Mock missing dependency
  run ./.claude/scripts/health-check.sh
  # Assert warnings are shown
}
```

### 7. Update install.sh to Run Tests

**File:** `install.sh`

Add test verification step (optional):

```bash
say "🧪 Running test suite..."
cd .claude/mcp
if npm test; then
  say "  ✅ All tests passed"
else
  warn "  ⚠️  Some tests failed"
fi
cd ../..
```

### 8. Update health-check.sh

**File:** `.claude/scripts/health-check.sh`

Add test suite check:

```bash
say "🔎 Checking test suite..."
if [[ -d ".claude/mcp/__tests__" ]]; then
  say "  ✅ Test suite exists"
else
  warn "  ⚠️  Test suite missing"
fi
say ""
```

### 9. Document Testing in CLAUDE.md

**File:** `CLAUDE.md`

Add a TESTING section:

```markdown
## TESTING

The factory includes a test suite for MCP servers and core infrastructure.

### Running Tests

cd .claude/mcp
npm test                # Run all tests
npm run test:watch     # Run tests in watch mode
npm run test:coverage  # Generate coverage report

### Test Structure

- `__tests__/unit/` — Unit tests for individual MCP servers
- `__tests__/integration/` — Integration tests for multi-tool workflows
- `__tests__/fixtures/` — Test fixtures and sample data

### Coverage Goals

- MCP servers: 80%+ line coverage
- Critical paths (code_search_rg, code_index_ctags): 90%+ coverage
```

### 10. Add CI/CD Integration (Optional)

**File:** `.github/workflows/test.yml`

Add GitHub Actions workflow:

```yaml
name: Test Factory

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      - name: Install dependencies
        run: |
          cd .claude/mcp
          npm install
      - name: Run tests
        run: |
          cd .claude/mcp
          npm test
      - name: Check coverage
        run: |
          cd .claude/mcp
          npm run test:coverage
```

## Verification Checklist

- [ ] Test framework installed (Jest/Vitest/Bats)
- [ ] `package.json` has test scripts configured
- [ ] Test directory structure created (`__tests__/unit`, `__tests__/integration`, `__tests__/fixtures`)
- [ ] Unit tests written for all MCP servers
- [ ] Integration tests written for key workflows
- [ ] All tests pass: `npm test`
- [ ] Coverage report generated: `npm run test:coverage`
- [ ] `health-check.sh` includes test suite check
- [ ] CLAUDE.md documents how to run tests
- [ ] CI/CD pipeline configured (if applicable)

## Common Pitfalls

1. **Not mocking external dependencies.** Always mock CLI tools (rg, ctags, git) in unit tests. Use test fixtures.
2. **Testing in production repo.** Use isolated test fixtures in `__tests__/fixtures/` — never run tests against the main repository.
3. **Incomplete cleanup.** Always use `afterAll` or `afterEach` to clean up test artifacts (temp files, spawned processes).
4. **Flaky tests.** Avoid timing-dependent tests. Use proper async/await patterns and wait for processes to fully start.
5. **Missing edge cases.** Test error paths: missing tools (ENOENT), timeouts, invalid inputs, empty outputs.
6. **Not testing MCP protocol.** Tests should verify JSON-RPC request/response format, not just the underlying tool output.
7. **Ignoring test failures.** Tests should be part of the development workflow, not an afterthought.
8. **Hardcoded paths.** Use `process.cwd()` and `path.join()` for cross-platform compatibility.
9. **No coverage tracking.** Always run `npm run test:coverage` to identify untested code paths.
10. **Forgetting to document.** Update CLAUDE.md and README.md with testing instructions.

For troubleshooting guidance, see [docs/TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md).
