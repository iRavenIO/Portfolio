// .claude/mcp/lib/index.js
//
// Central re-export point for Claude Factory MCP server library.
// Servers can import everything they need from this single entry point.
//
// Usage:
//   import { getRepoRoot, makeTextResponse, startServer } from "./lib/index.js";

// Core utilities
export {
  getRepoRoot,
  execSafe,
  execFileAsync,
  TIMEOUTS,
  BUFFERS,
} from "./core.js";

// Error handling
export {
  makeTextResponse,
  makeErrorResponse,
  handleExecError,
  handleRepoRootError,
} from "./errors.js";

// Validation
export {
  validateFilePath,
  validateDirPath,
} from "./validation.js";

// Configuration
export {
  loadJsonConfig,
  applyEnvOverrides,
} from "./config.js";

// Server bootstrap
export {
  createServer,
  startServer,
} from "./server-bootstrap.js";
