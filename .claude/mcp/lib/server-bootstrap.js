// .claude/mcp/lib/server-bootstrap.js
//
// MCP server creation and startup boilerplate for Claude Factory.
// Eliminates the repetitive server setup code present in all 7 servers.

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";

/**
 * Create a new MCP server instance.
 *
 * Wraps the McpServer constructor with consistent configuration.
 *
 * @param {string} name - Server name (e.g., "factory-rg", "factory-ops")
 * @param {string} version - Semantic version string
 * @returns {McpServer} Configured MCP server instance
 *
 * @example
 * const server = createServer("factory-rg", "1.1.0");
 * server.tool("code_search_rg", "Search code...", schema, handler);
 */
export function createServer(name, version) {
  return new McpServer({ name, version });
}

/**
 * Start an MCP server with stdio transport.
 *
 * Handles fatal errors with consistent error messages and exit behavior.
 * Replaces the main() async function pattern found in all servers.
 *
 * @param {McpServer} server - The MCP server instance to start
 * @param {string} [label] - Human-readable label for error messages (defaults to server.name)
 * @returns {Promise<void>}
 *
 * @example
 * const server = createServer("factory-rg", "1.1.0");
 * // ... register tools ...
 * await startServer(server, "ripgrep MCP server");
 *
 * @example
 * // Minimal usage (uses server.name as label)
 * const server = createServer("factory-git", "1.0.0");
 * // ... register tools ...
 * await startServer(server);
 */
export async function startServer(server, label) {
  const displayName = label || server.name || "MCP server";
  try {
    const transport = new StdioServerTransport();
    await server.connect(transport);
  } catch (error) {
    console.error(`Fatal: ${displayName} failed to start:`, error);
    process.exit(1);
  }
}
