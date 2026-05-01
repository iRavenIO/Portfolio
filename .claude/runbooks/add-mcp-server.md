# Runbook: Add a New MCP Server

## When to Use

Use this runbook when adding a new MCP server to the factory. This covers creating the server implementation, registering it, and updating all relevant documentation and policies.

## Prerequisites

- The wrapped CLI tool must already be installed (or installable via `install.sh`)
- You know the tool name(s) the server will expose
- You know which agents should be allowed to use each tool

## Steps

### 1. Create the Server File

**File:** `.claude/mcp/server-<name>.js`

Copy the structure from an existing server (e.g., `server-rg.js` for single-tool servers, `server.js` for multi-tool servers).

Required pattern:
```js
#!/usr/bin/env node

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

const server = new McpServer({
  name: "factory-<name>",
  version: "1.0.0",
});

server.tool(
  "<tool_name>",
  "<description>",
  { /* zod schema */ },
  async (params) => {
    // Implementation using execFileAsync (no shell)
    // Return { content: [{ type: "text", text: "..." }] }
    // On error: { content: [{ type: "text", text: "..." }], isError: true }
  }
);

async function main() {
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  console.error("Fatal: <name> MCP server failed to start:", error);
  process.exit(1);
});
```

Key conventions:
- Always use `execFile` (never `exec`) to avoid shell injection
- Define timeout and buffer constants at the top
- Include `getRepoRoot()` helper if the tool operates on repository files
- Handle three error cases: timeout (`error.killed`), command not found (`error.code === "ENOENT"`), and general errors
- Use `#!/usr/bin/env node` shebang and ESM imports

### 2. Register in `.mcp.json`

**File:** `.mcp.json` (repository root)

Add the server entry:
```json
{
  "mcpServers": {
    "factory-<name>": {
      "command": "node",
      "args": [".claude/mcp/server-<name>.js"]
    }
  }
}
```

### 3. Update CLAUDE.md — SYSTEM ARCHITECTURE Diagram

Add the new server file to the `.claude/mcp/` tree.

### 4. Update CLAUDE.md — MCP Tools Table

Add a row for each tool the server exposes.

### 5. Update CLAUDE.md — MCP TOOLING POLICY

For EACH agent section, add the new tool with the appropriate permission level (✅, ⚠️, or ❌).

### 6. Update `install.sh` (if needed)

If the wrapped CLI tool requires installation, add a `check_or_install` call and update smoke tests.

### 7. Update `install.sh` Verification Output

Add the new server to the verification section.

### 8. Update MEMORY.md

Document the new server.

### 9. Update README Files

**Files:** `README.md` and `README_CLAUDE.md`

Update both README files to reflect the new MCP server if relevant to the user-facing documentation or the technical overview.

## Verification Checklist

- [ ] Server file exists at `.claude/mcp/server-<name>.js`
- [ ] Server starts cleanly: `node .claude/mcp/server-<name>.js < /dev/null`
- [ ] `.mcp.json` has the new server entry
- [ ] `CLAUDE.md` SYSTEM ARCHITECTURE diagram includes the server
- [ ] `CLAUDE.md` MCP Tools table includes all tools
- [ ] `CLAUDE.md` MCP TOOLING POLICY has permissions for every agent
- [ ] `install.sh` installs any required CLI dependencies
- [ ] `install.sh` lists the server in smoke tests and verification output
- [ ] MEMORY.md is updated with the server details
- [ ] Claude Code `/mcp` command shows the server as connected

## Common Pitfalls

1. **Forgetting agent permissions.** Every agent section in MCP TOOLING POLICY must mention the new tool, even if forbidden.
2. **Using `exec` instead of `execFile`.** Always use `execFile` for security.
3. **Not handling `ENOENT`.** Return helpful install instructions.
4. **Inconsistent naming.** Server name in `McpServer({ name })` must match `.mcp.json`.
5. **Missing `package.json` type: "module".** The shared `package.json` already has `"type": "module"`.

For troubleshooting guidance, see [docs/TROUBLESHOOTING.md](../../docs/TROUBLESHOOTING.md).
