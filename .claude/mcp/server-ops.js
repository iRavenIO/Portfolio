#!/usr/bin/env node

/**
 * Factory MCP Server — Ops Autodiscovery (Stage 1 + Stage 2 + Stage 3)
 *
 * Provides fourteen READ/WRITE-tier operational tools:
 *
 * READ-tier (9 discovery tools):
 *   - ops_discover_k8s               → Kubernetes cluster resources
 *   - ops_discover_argocd            → Argo CD applications
 *   - ops_discover_postgres          → PostgreSQL databases and schemas
 *   - ops_discover_supabase          → Supabase project configuration
 *   - ops_discover_s3                → AWS S3 buckets and objects (Stage 2)
 *   - ops_discover_github            → GitHub repos, workflows, releases (Stage 2)
 *   - ops_discover_docker            → Docker containers, images, networks (Stage 2)
 *   - ops_discover_redis             → Redis server info and keyspace (Stage 2)
 *   - ops_discover_argo_workflows    → Argo Workflows status (Stage 2)
 *
 * Unified discovery (Stage 3):
 *   - ops_discover                   → Aggregates all 9 discovery tools
 *
 * WRITE/INFRASTRUCTURE-tier (Stage 3 approval-gated workflow):
 *   - ops_plan_mutation              → Plan mutation (returns plan_id + hash)
 *   - ops_approve                    → Approve plan with hash verification
 *   - ops_list_pending               → List pending approval plans
 *   - ops_execute                    → Execute approved plan
 *
 * Design principles:
 *   - Security: execFile only, never exec; parameterized queries
 *   - Graceful degradation: returns { available: false } if tool missing
 *   - Redaction: All output redacted before returning
 *   - Approval workflow: SHA256 hash verification + TTL enforcement
 *   - Per-project config: .claude/config/ops.json with hot-reload
 *   - Timeout handling: 5-15s per operation
 *
 * Uses stdio transport. Launched automatically by Claude Code
 * via the .mcp.json config at the repository root.
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { readFileSync, existsSync, watchFile } from "node:fs";
import { resolve } from "node:path";
import { createHash } from "node:crypto";
import { loadClaudeEnv } from "./lib/env-loader.js";
import {
  getRepoRoot,
  execFileAsync,
  execSafe,
  makeTextResponse,
  makeErrorResponse,
  TIMEOUTS,
  BUFFERS,
} from "./lib/index.js";

loadClaudeEnv();

// ── Configuration ──────────────────────────────────────────────

// Observability
const ENABLE_METRICS = process.env.OPS_ENABLE_METRICS !== "false";
const ENABLE_LOGGING = process.env.OPS_ENABLE_LOGGING !== "false";
const LOG_FILE = ".claude/logs/ops-mcp.log";

// Performance tracking
const metrics = {
  toolCalls: {},
  errors: {},
  totalCalls: 0,
  totalErrors: 0,
  startTime: Date.now()
};

const K8S_TIMEOUT_MS = 10_000;        // 10 seconds
const ARGOCD_TIMEOUT_MS = 15_000;     // 15 seconds
const POSTGRES_TIMEOUT_MS = 10_000;   // 10 seconds
const SUPABASE_TIMEOUT_MS = 15_000;   // 15 seconds
const S3_TIMEOUT_MS = 15_000;         // 15 seconds
const GITHUB_TIMEOUT_MS = 15_000;     // 15 seconds
const DOCKER_TIMEOUT_MS = 10_000;     // 10 seconds
const REDIS_TIMEOUT_MS = 5_000;       // 5 seconds
const ARGO_WORKFLOWS_TIMEOUT_MS = 10_000; // 10 seconds

// Cache TTL (seconds) - for documentation, actual caching handled by cache.sh
const CACHE_TTL_K8S = 30;
const CACHE_TTL_ARGOCD = 60;
const CACHE_TTL_POSTGRES = 120;
const CACHE_TTL_SUPABASE = 120;
const CACHE_TTL_S3 = 60;
const CACHE_TTL_GITHUB = 60;
const CACHE_TTL_DOCKER = 30;
const CACHE_TTL_REDIS = 30;
const CACHE_TTL_ARGO_WORKFLOWS = 30;

// ── Config Management ──────────────────────────────────────────

let opsConfig = {
  enabled: true,
  discovery: {
    enabled: true,
    tools: {
      k8s: { enabled: true, timeout_ms: K8S_TIMEOUT_MS },
      argocd: { enabled: true, timeout_ms: ARGOCD_TIMEOUT_MS },
      postgres: { enabled: true, timeout_ms: POSTGRES_TIMEOUT_MS },
      supabase: { enabled: true, timeout_ms: SUPABASE_TIMEOUT_MS },
      s3: { enabled: true, timeout_ms: S3_TIMEOUT_MS },
      github: { enabled: true, timeout_ms: GITHUB_TIMEOUT_MS },
      docker: { enabled: true, timeout_ms: DOCKER_TIMEOUT_MS },
      redis: { enabled: true, timeout_ms: REDIS_TIMEOUT_MS },
      argo_workflows: { enabled: true, timeout_ms: ARGO_WORKFLOWS_TIMEOUT_MS }
    }
  },
  approval: {
    enabled: true,
    ttl_minutes: 30,
    require_hash_match: true,
    max_pending: 100
  },
  unified_discovery: {
    enabled: true,
    parallel_execution: true,
    max_concurrent: 5
  }
};

/**
 * Migrate config to latest schema version
 */
function migrateConfig(config) {
  const currentVersion = config.version || "1.0.0";
  let migrated = { ...config };

  // Migration v1.0.0 → v1.1.0 (add observability field)
  if (currentVersion === "1.0.0") {
    migrated.observability = {
      metrics_enabled: true,
      logging_enabled: true
    };
    migrated.version = "1.1.0";
    logEvent("info", "config_migrated", { from: "1.0.0", to: "1.1.0" });
  }

  // Future migrations can be added here
  // if (migrated.version === "1.1.0") { ... }

  return migrated;
}

/**
 * Validate config against schema
 */
function validateConfig(config) {
  const errors = [];

  // Required fields
  if (typeof config.enabled !== "boolean") {
    errors.push("Field 'enabled' must be boolean");
  }

  // Discovery section
  if (config.discovery) {
    if (typeof config.discovery.enabled !== "boolean") {
      errors.push("Field 'discovery.enabled' must be boolean");
    }
    if (config.discovery.tools && typeof config.discovery.tools !== "object") {
      errors.push("Field 'discovery.tools' must be object");
    }
  }

  // Approval section
  if (config.approval) {
    if (typeof config.approval.enabled !== "boolean") {
      errors.push("Field 'approval.enabled' must be boolean");
    }
    if (config.approval.ttl_minutes && (typeof config.approval.ttl_minutes !== "number" || config.approval.ttl_minutes < 1)) {
      errors.push("Field 'approval.ttl_minutes' must be positive number");
    }
    if (config.approval.max_pending && (typeof config.approval.max_pending !== "number" || config.approval.max_pending < 1)) {
      errors.push("Field 'approval.max_pending' must be positive number");
    }
  }

  return errors;
}

/**
 * Apply environment variable overrides
 */
function applyEnvOverrides(config) {
  const overridden = { ...config };

  // Global enable/disable
  if (process.env.OPS_ENABLED !== undefined) {
    overridden.enabled = process.env.OPS_ENABLED === "true";
  }

  // Discovery overrides
  if (process.env.OPS_DISCOVERY_ENABLED !== undefined) {
    overridden.discovery = overridden.discovery || {};
    overridden.discovery.enabled = process.env.OPS_DISCOVERY_ENABLED === "true";
  }

  // Approval overrides
  if (process.env.OPS_APPROVAL_ENABLED !== undefined) {
    overridden.approval = overridden.approval || {};
    overridden.approval.enabled = process.env.OPS_APPROVAL_ENABLED === "true";
  }

  if (process.env.OPS_APPROVAL_TTL_MINUTES !== undefined) {
    overridden.approval = overridden.approval || {};
    const ttl = parseInt(process.env.OPS_APPROVAL_TTL_MINUTES, 10);
    if (!isNaN(ttl) && ttl > 0) {
      overridden.approval.ttl_minutes = ttl;
    }
  }

  // Observability overrides
  if (process.env.OPS_ENABLE_METRICS !== undefined) {
    overridden.observability = overridden.observability || {};
    overridden.observability.metrics_enabled = process.env.OPS_ENABLE_METRICS !== "false";
  }

  if (process.env.OPS_ENABLE_LOGGING !== undefined) {
    overridden.observability = overridden.observability || {};
    overridden.observability.logging_enabled = process.env.OPS_ENABLE_LOGGING !== "false";
  }

  return overridden;
}

/**
 * Load ops configuration from .claude/config/ops.json
 * Config is optional - defaults to enabled if not found
 */
async function loadOpsConfig() {
  try {
    const repoRoot = await getRepoRootWithFallback();
    const configPath = resolve(repoRoot, ".claude/config/ops.json");

    if (existsSync(configPath)) {
      const configData = readFileSync(configPath, "utf-8");
      let parsed = JSON.parse(configData);

      // Migrate to latest version
      parsed = migrateConfig(parsed);

      // Validate config
      const errors = validateConfig(parsed);
      if (errors.length > 0) {
        console.error("Config validation errors:", errors);
        logEvent("error", "config_validation_failed", { errors });
        // Continue with defaults on validation failure
        return;
      }

      // Apply environment variable overrides
      parsed = applyEnvOverrides(parsed);

      // Deep merge with defaults
      opsConfig = {
        ...opsConfig,
        ...parsed,
        discovery: {
          ...opsConfig.discovery,
          ...parsed.discovery,
          tools: {
            ...opsConfig.discovery.tools,
            ...parsed.discovery?.tools
          }
        },
        approval: {
          ...opsConfig.approval,
          ...parsed.approval
        },
        unified_discovery: {
          ...opsConfig.unified_discovery,
          ...parsed.unified_discovery
        },
        observability: {
          metrics_enabled: ENABLE_METRICS,
          logging_enabled: ENABLE_LOGGING,
          ...parsed.observability
        }
      };

      logEvent("info", "config_loaded", { config_path: configPath, version: opsConfig.version || "1.0.0" });

      // Hot-reload: watch for changes
      watchFile(configPath, { interval: 5000 }, () => {
        loadOpsConfig().catch(() => {
          // Silent fail on hot-reload errors
        });
      });
    } else {
      // Apply environment overrides even without config file
      const withEnv = applyEnvOverrides(opsConfig);
      opsConfig = withEnv;
      logEvent("info", "config_defaults_used", { reason: "config file not found" });
    }
  } catch (error) {
    // Config is optional - use defaults if load fails
    console.error("Warning: Failed to load ops config, using defaults:", error.message);
    logEvent("error", "config_load_failed", { error: error.message });
  }
}

/**
 * Check if a tool is enabled in config
 */
function isToolEnabled(toolName) {
  if (!opsConfig.enabled) return false;
  if (!opsConfig.discovery.enabled) return false;
  return opsConfig.discovery.tools[toolName]?.enabled !== false;
}

/**
 * Get timeout for a tool from config
 */
function getToolTimeout(toolName) {
  return opsConfig.discovery.tools[toolName]?.timeout_ms || 10000;
}

// ── Helpers ────────────────────────────────────────────────────

/**
 * Get repository root using git
 */
// Note: ops server uses fallback mode (returns cwd instead of throwing)
// This is different from other servers which throw on git failure
async function getRepoRootWithFallback() {
  return await getRepoRoot({ fallback: true, timeout: TIMEOUTS.GIT_FAST });
}

/**
 * Structured logging with JSON format
 */
function logEvent(level, event, details = {}) {
  if (!ENABLE_LOGGING) return;

  try {
    const logEntry = {
      timestamp: new Date().toISOString(),
      level,
      event,
      ...details
    };

    const logLine = JSON.stringify(logEntry) + "\n";

    // Append to log file
    const { appendFileSync, mkdirSync, existsSync } = require("node:fs");
    const { dirname } = require("node:path");
    const logDir = dirname(resolve(process.cwd(), LOG_FILE));

    if (!existsSync(logDir)) {
      mkdirSync(logDir, { recursive: true });
    }

    appendFileSync(resolve(process.cwd(), LOG_FILE), logLine);
  } catch (error) {
    // Silent fail on logging errors
    console.error("Warning: Failed to write log:", error.message);
  }
}

/**
 * Track tool performance metrics
 */
function recordMetric(toolName, duration, success = true) {
  if (!ENABLE_METRICS) return;

  if (!metrics.toolCalls[toolName]) {
    metrics.toolCalls[toolName] = { count: 0, totalDuration: 0, errors: 0 };
  }

  metrics.toolCalls[toolName].count++;
  metrics.toolCalls[toolName].totalDuration += duration;
  metrics.totalCalls++;

  if (!success) {
    metrics.toolCalls[toolName].errors++;
    metrics.totalErrors++;

    if (!metrics.errors[toolName]) {
      metrics.errors[toolName] = 0;
    }
    metrics.errors[toolName]++;
  }
}

/**
 * Get metrics summary
 */
function getMetricsSummary() {
  const uptime = Date.now() - metrics.startTime;
  const summary = {
    uptime_ms: uptime,
    uptime_human: `${Math.floor(uptime / 60000)}m ${Math.floor((uptime % 60000) / 1000)}s`,
    total_calls: metrics.totalCalls,
    total_errors: metrics.totalErrors,
    error_rate: metrics.totalCalls > 0 ? (metrics.totalErrors / metrics.totalCalls * 100).toFixed(2) + "%" : "0%",
    tools: {}
  };

  for (const [tool, data] of Object.entries(metrics.toolCalls)) {
    summary.tools[tool] = {
      count: data.count,
      avg_duration_ms: data.count > 0 ? Math.round(data.totalDuration / data.count) : 0,
      errors: data.errors,
      error_rate: data.count > 0 ? (data.errors / data.count * 100).toFixed(2) + "%" : "0%"
    };
  }

  return summary;
}

/**
 * Execute a command safely with timeout and error handling
 * Returns: { success: true, stdout, stderr } or { success: false, error }
 */
// execSafe now provided by lib/index.js

/**
 * Redact secrets from output using Node.js regex (in-process)
 * Patterns based on .claude/scripts/redact.sh
 */
function redactOutput(text) {
  if (!text) return text;

  let redacted = text;

  // Pattern 1: Connection strings (protocol://user:pass@host/db)
  const connectionProtocols = [
    "postgres", "postgresql", "mysql", "mongodb", "redis", "amqp",
    "rabbitmq", "kafka", "cassandra", "elasticsearch"
  ];
  for (const proto of connectionProtocols) {
    const regex = new RegExp(`${proto}://[^\\s@]*:[^\\s@]*@[^\\s]*`, "g");
    redacted = redacted.replace(regex, `${proto}://***REDACTED***`);
  }

  // Pattern 2: Value-based tokens (Anthropic API keys, JWTs, AWS keys, GitHub PATs)
  const tokenPattern = /sk-ant-api[0-9]+-[A-Za-z0-9_-]{95,}|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|AKIA[0-9A-Z]{16}|github_pat_[0-9a-zA-Z_]{70,}|ghp_[0-9a-zA-Z]{36}|gho_[0-9a-zA-Z]{36}|ya29\.[0-9A-Za-z_-]+|AIza[0-9A-Za-z_-]{30,}/g;
  redacted = redacted.replace(tokenPattern, "***REDACTED***");

  // Pattern 3: Environment variable patterns (KEY=value)
  const secretVarPatterns = [
    /_TOKEN=/g, /_SECRET=/g, /_KEY=/g, /_PASSWORD=/g, /_PASS=/g,
    /API_TOKEN=/g, /API_KEY=/g, /DATABASE_URL=/g, /DB_URL=/g,
    /PGPASSWORD=/g, /KUBECONFIG=/g, /DOCKER_PASSWORD=/g
  ];
  for (const pattern of secretVarPatterns) {
    redacted = redacted.replace(pattern, (match) => match.split("=")[0] + "=***REDACTED***");
  }

  // Pattern 4: IP addresses (optional - can be commented out if IPs are not sensitive)
  // redacted = redacted.replace(/\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b/g, "[IP_REDACTED]");

  // Pattern 5: JSON secret fields
  const jsonSecretKeys = ["password", "secret", "token", "api_key", "apiKey", "private_key", "privateKey"];
  for (const key of jsonSecretKeys) {
    const regex = new RegExp(`"${key}"\\s*:\\s*"[^"]+"`, "gi");
    redacted = redacted.replace(regex, `"${key}": "***REDACTED***"`);
  }

  // Phase 5.2: Additional patterns for S3, Docker, Redis, GitHub

  // Pattern 6: AWS S3 pre-signed URLs (contain signatures)
  const s3PresignedPattern = /https:\/\/[^?]+\?[^"]*X-Amz-Signature=[^"&\s]+[^"'\s]*/g;
  redacted = redacted.replace(s3PresignedPattern, "https://s3.***REDACTED_PRESIGNED_URL***");

  // Pattern 7: AWS Account IDs (12-digit numbers in ARN context)
  const arnPattern = /arn:aws[^:]*:[^:]+:[^:]*:(\d{12}):/g;
  redacted = redacted.replace(arnPattern, (match, accountId) =>
    match.replace(accountId, "***ACCOUNT***")
  );

  // Pattern 8: Docker registry auth tokens
  const dockerAuthPattern = /"auth"\s*:\s*"[A-Za-z0-9+/=]+"/g;
  redacted = redacted.replace(dockerAuthPattern, '"auth": "***REDACTED***"');

  // Pattern 9: Redis AUTH password in connection URLs
  const redisAuthPattern = /AUTH\s+[^\s"]+/gi;
  redacted = redacted.replace(redisAuthPattern, "AUTH ***REDACTED***");

  return redacted;
}

/**
 * Cache wrapper using bash cache.sh
 * Note: Actual caching is done via bash wrapper calling cache.sh functions
 * This is a placeholder for future integration if we move caching to Node.js
 */
async function cacheGet(key) {
  // For now, no Node.js caching - cache.sh will handle this via bash wrappers
  return null;
}

async function cacheSet(key, value, ttl) {
  // For now, no Node.js caching - cache.sh will handle this via bash wrappers
  return;
}

// ── Approval Store (SQLite) ────────────────────────────────────

let approvalDb = null;

/**
 * Initialize approval store database
 */
async function initApprovalStore() {
  try {
    const repoRoot = await getRepoRootWithFallback();
    const dbPath = resolve(repoRoot, ".claude/cache/approvals.db");

    // Ensure cache directory exists
    const { dirname } = await import("node:path");
    const { mkdirSync } = await import("node:fs");
    const cacheDir = dirname(dbPath);
    if (!existsSync(cacheDir)) {
      mkdirSync(cacheDir, { recursive: true, mode: 0o700 });
    }

    // Use sqlite3 CLI for database operations (no npm dependencies)
    const initSQL = `
      CREATE TABLE IF NOT EXISTS approvals (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_id TEXT NOT NULL UNIQUE,
        plan_hash TEXT NOT NULL,
        plan_details TEXT NOT NULL,
        tier TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        version INTEGER NOT NULL DEFAULT 1,
        created_at INTEGER NOT NULL,
        approved_at INTEGER,
        executed_at INTEGER,
        result TEXT,
        metadata TEXT
      );
      CREATE INDEX IF NOT EXISTS idx_plan_id ON approvals(plan_id);
      CREATE INDEX IF NOT EXISTS idx_status ON approvals(status);
      CREATE INDEX IF NOT EXISTS idx_created_at ON approvals(created_at);
      CREATE INDEX IF NOT EXISTS idx_plan_hash ON approvals(plan_hash);

      CREATE TABLE IF NOT EXISTS audit_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_id TEXT NOT NULL,
        action TEXT NOT NULL,
        actor TEXT,
        timestamp INTEGER NOT NULL,
        details TEXT,
        FOREIGN KEY (plan_id) REFERENCES approvals(plan_id)
      );
      CREATE INDEX IF NOT EXISTS idx_audit_plan_id ON audit_log(plan_id);
      CREATE INDEX IF NOT EXISTS idx_audit_timestamp ON audit_log(timestamp);

      CREATE TABLE IF NOT EXISTS plan_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        plan_id TEXT NOT NULL,
        version INTEGER NOT NULL,
        plan_hash TEXT NOT NULL,
        plan_details TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (plan_id) REFERENCES approvals(plan_id)
      );
      CREATE INDEX IF NOT EXISTS idx_history_plan_id ON plan_history(plan_id);

      PRAGMA journal_mode=WAL;
    `;

    await execSafe("sqlite3", [dbPath, initSQL], { timeout: 5000 });
    approvalDb = dbPath;
  } catch (error) {
    console.error("Warning: Failed to init approval store:", error.message);
  }
}

/**
 * Execute SQLite query on approval store with proper parameterization
 */
async function approvalQuery(sql, params = []) {
  if (!approvalDb) {
    throw new Error("Approval store not initialized");
  }

  try {
    if (params.length === 0) {
      // No parameters - execute directly
      const result = await execSafe("sqlite3", [approvalDb, "-json", sql], { timeout: 5000 });
      if (result.success) {
        try {
          return JSON.parse(result.stdout || "[]");
        } catch {
          return [];
        }
      }
      throw new Error(result.message || "Query failed");
    }

    // Build parameterized query using sqlite3 .param commands
    const args = [approvalDb, "-json"];

    // Add .param init command
    args.push("-cmd", ".param init");

    // Add parameter bindings
    params.forEach((param, i) => {
      args.push("-cmd", `.param set :${i + 1} '${String(param).replace(/'/g, "''")}'`);
    });

    // Replace ? with :1, :2, etc.
    let parameterizedSQL = sql;
    let paramIndex = 1;
    parameterizedSQL = parameterizedSQL.replace(/\?/g, () => `:${paramIndex++}`);

    // Add the query
    args.push(parameterizedSQL);

    const result = await execSafe("sqlite3", args, { timeout: 5000 });
    if (result.success) {
      try {
        return JSON.parse(result.stdout || "[]");
      } catch {
        return [];
      }
    }
    throw new Error(result.message || "Query failed");
  } catch (error) {
    throw new Error(`Approval query failed: ${error.message}`);
  }
}

/**
 * Generate plan hash
 */
function hashPlan(planDetails) {
  return createHash("sha256").update(JSON.stringify(planDetails)).digest("hex");
}

/**
 * Generate unique plan ID
 */
function generatePlanId() {
  return `plan_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

/**
 * Log audit event
 */
async function logAudit(plan_id, action, details = {}) {
  try {
    const timestamp = Math.floor(Date.now() / 1000);
    const actor = details.actor || "system";
    const detailsJson = JSON.stringify({ ...details, action_timestamp: new Date(timestamp * 1000).toISOString() });

    const insertSQL = `INSERT INTO audit_log (plan_id, action, actor, timestamp, details) VALUES (?, ?, ?, ?, ?)`;
    await approvalQuery(insertSQL, [plan_id, action, actor, timestamp, detailsJson]);
  } catch (error) {
    // Silent fail on audit logging errors (non-critical)
    console.error("Warning: Audit logging failed:", error.message);
  }
}

/**
 * Check for plan hash collision
 */
async function checkPlanCollision(plan_hash) {
  try {
    const rows = await approvalQuery(`SELECT plan_id, status, created_at FROM approvals WHERE plan_hash = ? LIMIT 5`, [plan_hash]);
    return rows;
  } catch (error) {
    return [];
  }
}

/**
 * Save plan version to history
 */
async function savePlanHistory(plan_id, version, plan_hash, plan_details) {
  try {
    const created_at = Math.floor(Date.now() / 1000);
    const insertSQL = `INSERT INTO plan_history (plan_id, version, plan_hash, plan_details, created_at) VALUES (?, ?, ?, ?, ?)`;
    await approvalQuery(insertSQL, [plan_id, version, plan_hash, JSON.stringify(plan_details), created_at]);
  } catch (error) {
    console.error("Warning: Failed to save plan history:", error.message);
  }
}

// ── Server setup ───────────────────────────────────────────────

const server = new McpServer({
  name: "factory-ops",
  version: "1.0.0",
});

// ── Tool 1: ops_discover_k8s ───────────────────────────────────

server.tool(
  "ops_discover_k8s",
  "Discover Kubernetes cluster resources (namespaces, pods, services, deployments). Returns structured JSON with resource inventory. READ-tier operation (non-mutating). Gracefully degrades if kubectl not available.",
  {
    namespace: z
      .string()
      .optional()
      .describe("Filter by namespace. If omitted, discovers all namespaces."),
    resource_types: z
      .array(z.enum(["namespaces", "pods", "services", "deployments", "ingresses", "configmaps"]))
      .optional()
      .default(["namespaces", "pods", "services", "deployments"])
      .describe("Resource types to discover. Default: namespaces, pods, services, deployments."),
  },
  async ({ namespace, resource_types }) => {
    // Check if kubectl is available
    const checkResult = await execSafe("kubectl", ["version", "--client", "--output=json"], { timeout: 5_000 });
    if (!checkResult.success) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            available: false,
            tool: "kubectl",
            reason: checkResult.error === "command_not_found" ? "kubectl not found in PATH" : checkResult.message,
            suggestion: "Install kubectl: brew install kubectl",
            isError: true
          }, null, 2)
        }]
      };
    }

    // Discover resources
    const resources = {};
    const errors = [];

    for (const resourceType of resource_types) {
      const args = ["get", resourceType, "--output=json"];
      if (namespace && resourceType !== "namespaces") {
        args.push(`--namespace=${namespace}`);
      } else if (resourceType !== "namespaces") {
        args.push("--all-namespaces");
      }

      const result = await execSafe("kubectl", args, { timeout: K8S_TIMEOUT_MS });
      if (result.success) {
        try {
          const parsed = JSON.parse(result.stdout);
          resources[resourceType] = {
            count: parsed.items?.length || 0,
            items: parsed.items?.map(item => ({
              name: item.metadata?.name,
              namespace: item.metadata?.namespace,
              status: item.status?.phase || item.status?.conditions?.[0]?.type || "unknown"
            })) || []
          };
        } catch (parseError) {
          errors.push({ resource: resourceType, error: "Failed to parse JSON output" });
        }
      } else {
        errors.push({ resource: resourceType, error: result.message });
      }
    }

    const output = {
      available: true,
      tool: "kubectl",
      namespace: namespace || "all",
      resources,
      errors: errors.length > 0 ? errors : undefined,
      cache_ttl: CACHE_TTL_K8S
    };

    const redactedOutput = redactOutput(JSON.stringify(output, null, 2));

    return {
      content: [{
        type: "text",
        text: redactedOutput
      }]
    };
  }
);

// ── Tool 2: ops_discover_argocd ────────────────────────────────

server.tool(
  "ops_discover_argocd",
  "Discover Argo CD applications and their sync status. Returns structured JSON with app inventory. READ-tier operation (non-mutating). Gracefully degrades if argocd CLI not available.",
  {
    app_name: z
      .string()
      .optional()
      .describe("Filter by application name. If omitted, discovers all applications."),
  },
  async ({ app_name }) => {
    // Check if argocd CLI is available
    const checkResult = await execSafe("argocd", ["version", "--client"], { timeout: 5_000 });
    if (!checkResult.success) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            available: false,
            tool: "argocd",
            reason: checkResult.error === "command_not_found" ? "argocd CLI not found in PATH" : checkResult.message,
            suggestion: "Install argocd CLI: brew install argocd",
            isError: true
          }, null, 2)
        }]
      };
    }

    // Discover applications
    let apps = [];
    const errors = [];

    if (app_name) {
      // Get specific app
      const result = await execSafe("argocd", ["app", "get", app_name, "--output=json"], { timeout: ARGOCD_TIMEOUT_MS });
      if (result.success) {
        try {
          const parsed = JSON.parse(result.stdout);
          apps.push({
            name: parsed.metadata?.name,
            namespace: parsed.metadata?.namespace,
            project: parsed.spec?.project,
            sync_status: parsed.status?.sync?.status,
            health_status: parsed.status?.health?.status,
            repo_url: parsed.spec?.source?.repoURL,
            path: parsed.spec?.source?.path,
            target_revision: parsed.spec?.source?.targetRevision
          });
        } catch (parseError) {
          errors.push({ app: app_name, error: "Failed to parse JSON output" });
        }
      } else {
        errors.push({ app: app_name, error: result.message });
      }
    } else {
      // List all apps
      const result = await execSafe("argocd", ["app", "list", "--output=json"], { timeout: ARGOCD_TIMEOUT_MS });
      if (result.success) {
        try {
          const parsed = JSON.parse(result.stdout);
          apps = parsed.map(app => ({
            name: app.metadata?.name,
            namespace: app.metadata?.namespace,
            project: app.spec?.project,
            sync_status: app.status?.sync?.status,
            health_status: app.status?.health?.status,
            repo_url: app.spec?.source?.repoURL,
            path: app.spec?.source?.path,
            target_revision: app.spec?.source?.targetRevision
          }));
        } catch (parseError) {
          errors.push({ error: "Failed to parse JSON output" });
        }
      } else {
        errors.push({ error: result.message });
      }
    }

    const output = {
      available: true,
      tool: "argocd",
      applications: {
        count: apps.length,
        items: apps
      },
      errors: errors.length > 0 ? errors : undefined,
      cache_ttl: CACHE_TTL_ARGOCD
    };

    const redactedOutput = redactOutput(JSON.stringify(output, null, 2));

    return {
      content: [{
        type: "text",
        text: redactedOutput
      }]
    };
  }
);

// ── Tool 3: ops_discover_postgres ──────────────────────────────

server.tool(
  "ops_discover_postgres",
  "Discover PostgreSQL databases, schemas, and tables. Returns structured JSON with database inventory. READ-tier operation (read-only query). Requires DATABASE_URL env var or connection params. Gracefully degrades if psql not available.",
  {
    database_url: z
      .string()
      .optional()
      .describe("PostgreSQL connection URL. If omitted, uses DATABASE_URL env var."),
    database: z
      .string()
      .optional()
      .describe("Database name. If omitted with database_url, lists all databases."),
  },
  async ({ database_url, database }) => {
    // Check if psql is available
    const checkResult = await execSafe("psql", ["--version"], { timeout: 5_000 });
    if (!checkResult.success) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            available: false,
            tool: "psql",
            reason: checkResult.error === "command_not_found" ? "psql not found in PATH" : checkResult.message,
            suggestion: "Install PostgreSQL client: brew install postgresql",
            isError: true
          }, null, 2)
        }]
      };
    }

    // Use provided URL or env var
    const connUrl = database_url || process.env.DATABASE_URL;
    if (!connUrl) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            available: true,
            tool: "psql",
            error: "No database connection provided. Set DATABASE_URL env var or provide database_url parameter."
          }, null, 2)
        }]
      };
    }

    const discoveries = {};
    const errors = [];

    // Validate database and schema names to prevent SQL injection
    const identifierRegex = /^[a-zA-Z_][a-zA-Z0-9_]*$/;
    if (database && !identifierRegex.test(database)) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            available: true,
            error: "Invalid database name. Must start with letter/underscore and contain only alphanumeric characters and underscores.",
            isError: true
          }, null, 2)
        }]
      };
    }

    // Discover databases (if no specific database provided)
    if (!database) {
      const query = "SELECT datname, pg_size_pretty(pg_database_size(datname)) as size FROM pg_database WHERE datistemplate = false ORDER BY datname;";
      const result = await execSafe("psql", [connUrl, "-t", "-c", query], { timeout: POSTGRES_TIMEOUT_MS });
      if (result.success) {
        const lines = result.stdout.split("\n").filter(line => line.trim());
        discoveries.databases = lines.map(line => {
          const parts = line.trim().split("|").map(p => p.trim());
          return { name: parts[0], size: parts[1] };
        });
      } else {
        errors.push({ operation: "list_databases", error: result.message });
      }
    } else {
      // Discover schemas in specific database
      const dbConnUrl = connUrl.includes("?") ? `${connUrl}&dbname=${database}` : `${connUrl}/${database}`;
      const schemaQuery = "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast') ORDER BY schema_name;";
      const result = await execSafe("psql", [dbConnUrl, "-t", "-c", schemaQuery], { timeout: POSTGRES_TIMEOUT_MS });
      if (result.success) {
        const schemas = result.stdout.split("\n").filter(line => line.trim()).map(line => line.trim());
        discoveries.schemas = schemas;

        // Discover tables in each schema (limit to first 3 schemas to avoid timeout)
        discoveries.tables = {};
        for (const schema of schemas.slice(0, 3)) {
          // Validate schema name to prevent SQL injection
          if (!identifierRegex.test(schema)) {
            errors.push({ operation: `list_tables_${schema}`, error: "Invalid schema name format" });
            continue;
          }
          // Use parameterized query with $1 placeholder for schema name
          const tableQuery = `SELECT table_name, pg_size_pretty(pg_total_relation_size(quote_ident($1) || '.' || quote_ident(table_name))) as size FROM information_schema.tables WHERE table_schema = $1 AND table_type = 'BASE TABLE' ORDER BY table_name LIMIT 50;`;
          // Use psql -v to pass parameter safely
          const tableResult = await execSafe("psql", [dbConnUrl, "-t", "-v", `schema=${schema}`, "-c", tableQuery.replace(/\$1/g, ':schema')], { timeout: POSTGRES_TIMEOUT_MS });
          if (tableResult.success) {
            const lines = tableResult.stdout.split("\n").filter(line => line.trim());
            discoveries.tables[schema] = lines.map(line => {
              const parts = line.trim().split("|").map(p => p.trim());
              return { name: parts[0], size: parts[1] || "unknown" };
            });
          }
        }
      } else {
        errors.push({ operation: "list_schemas", error: result.message });
      }
    }

    const output = {
      available: true,
      tool: "psql",
      database: database || "all",
      discoveries,
      errors: errors.length > 0 ? errors : undefined,
      cache_ttl: CACHE_TTL_POSTGRES
    };

    const redactedOutput = redactOutput(JSON.stringify(output, null, 2));

    return {
      content: [{
        type: "text",
        text: redactedOutput
      }]
    };
  }
);

// ── Tool 4: ops_discover_supabase ──────────────────────────────

server.tool(
  "ops_discover_supabase",
  "Discover Supabase project configuration (project ref, database status, API endpoints). Returns structured JSON. READ-tier operation. Gracefully degrades if supabase CLI not available.",
  {
    project_ref: z
      .string()
      .optional()
      .describe("Supabase project reference ID. If omitted, uses linked project."),
  },
  async ({ project_ref }) => {
    // Check if supabase CLI is available
    const checkResult = await execSafe("supabase", ["--version"], { timeout: 5_000 });
    if (!checkResult.success) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            available: false,
            tool: "supabase",
            reason: checkResult.error === "command_not_found" ? "supabase CLI not found in PATH" : checkResult.message,
            suggestion: "Install supabase CLI: brew install supabase/tap/supabase",
            isError: true
          }, null, 2)
        }]
      };
    }

    const discoveries = {};
    const errors = [];

    // Get project status
    const repoRoot = await getRepoRootWithFallback();
    const statusResult = await execSafe("supabase", ["status"], { timeout: SUPABASE_TIMEOUT_MS, cwd: repoRoot });
    if (statusResult.success) {
      // Parse status output (format varies, best-effort parsing)
      const lines = statusResult.stdout.split("\n");
      const status = {};
      for (const line of lines) {
        if (line.includes(":")) {
          const [key, value] = line.split(":").map(s => s.trim());
          status[key.toLowerCase().replace(/\s+/g, "_")] = value;
        }
      }
      discoveries.status = status;
    } else {
      errors.push({ operation: "status", error: statusResult.message });
    }

    // Get project details (if project_ref provided)
    if (project_ref) {
      // Note: supabase CLI doesn't have a direct "get project" command
      // This is a placeholder for when such functionality exists
      discoveries.project_ref = project_ref;
      discoveries.note = "Project details require Supabase Management API integration (not yet implemented)";
    }

    // Check for local config file
    try {
      const configPath = resolve(repoRoot, "supabase", "config.toml");
      const configExists = existsSync(configPath);
      discoveries.local_config_exists = configExists;
    } catch (error) {
      // Ignore file check errors
    }

    const output = {
      available: true,
      tool: "supabase",
      project_ref: project_ref || "linked_project",
      discoveries,
      errors: errors.length > 0 ? errors : undefined,
      cache_ttl: CACHE_TTL_SUPABASE
    };

    const redactedOutput = redactOutput(JSON.stringify(output, null, 2));

    return {
      content: [{
        type: "text",
        text: redactedOutput
      }]
    };
  }
);

// ── Tool 5: ops_discover_s3 ────────────────────────────────────

server.tool(
  "ops_discover_s3",
  "Discover AWS S3 buckets and their configuration. Returns structured JSON with bucket inventory. READ-tier operation. Gracefully degrades if aws CLI not available.",
  {
    bucket: z
      .string()
      .optional()
      .describe("Filter by bucket name. If omitted, lists all buckets."),
    prefix: z
      .string()
      .optional()
      .describe("List objects under this prefix (requires bucket)."),
    max_keys: z
      .number()
      .optional()
      .default(100)
      .describe("Maximum objects to list (default 100, max 1000)."),
  },
  async ({ bucket, prefix, max_keys }) => {
    // Check if aws CLI is available
    const checkResult = await execSafe("aws", ["--version"], { timeout: 5_000 });
    if (!checkResult.success) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            available: false,
            tool: "aws",
            reason: checkResult.error === "command_not_found" ? "aws CLI not found in PATH" : checkResult.message,
            suggestion: "Install AWS CLI: brew install awscli",
            isError: true
          }, null, 2)
        }]
      };
    }

    const discoveries = {};
    const errors = [];

    // Limit max_keys to 1000
    const limitedMaxKeys = Math.min(max_keys, 1000);

    if (!bucket) {
      // List all buckets
      const result = await execSafe("aws", ["s3api", "list-buckets", "--output", "json"], { timeout: S3_TIMEOUT_MS });
      if (result.success) {
        try {
          const parsed = JSON.parse(result.stdout);
          discoveries.buckets = {
            count: parsed.Buckets?.length || 0,
            items: parsed.Buckets?.map(b => ({
              name: b.Name,
              creation_date: b.CreationDate
            })) || []
          };
        } catch (parseError) {
          errors.push({ operation: "list_buckets", error: "Failed to parse JSON output" });
        }
      } else {
        errors.push({ operation: "list_buckets", error: result.message });
      }
    } else {
      // Get bucket location
      const locationResult = await execSafe("aws", ["s3api", "get-bucket-location", "--bucket", bucket, "--output", "json"], { timeout: S3_TIMEOUT_MS });
      if (locationResult.success) {
        try {
          const parsed = JSON.parse(locationResult.stdout);
          discoveries.bucket = {
            name: bucket,
            location: parsed.LocationConstraint || "us-east-1"
          };
        } catch (parseError) {
          errors.push({ operation: "get_bucket_location", error: "Failed to parse JSON output" });
        }
      } else {
        errors.push({ operation: "get_bucket_location", error: locationResult.message });
      }

      // List objects if bucket specified
      const listArgs = ["s3api", "list-objects-v2", "--bucket", bucket, "--max-keys", String(limitedMaxKeys), "--output", "json"];
      if (prefix) {
        listArgs.push("--prefix", prefix);
      }

      const objectsResult = await execSafe("aws", listArgs, { timeout: S3_TIMEOUT_MS });
      if (objectsResult.success) {
        try {
          const parsed = JSON.parse(objectsResult.stdout);
          discoveries.objects = {
            count: parsed.KeyCount || 0,
            items: parsed.Contents?.slice(0, limitedMaxKeys).map(obj => ({
              key: obj.Key,
              size: obj.Size,
              last_modified: obj.LastModified,
              storage_class: obj.StorageClass
            })) || []
          };
        } catch (parseError) {
          errors.push({ operation: "list_objects", error: "Failed to parse JSON output" });
        }
      } else {
        errors.push({ operation: "list_objects", error: objectsResult.message });
      }
    }

    const output = {
      available: true,
      tool: "aws s3",
      bucket: bucket || "all",
      discoveries,
      errors: errors.length > 0 ? errors : undefined,
      cache_ttl: CACHE_TTL_S3
    };

    const redactedOutput = redactOutput(JSON.stringify(output, null, 2));

    return {
      content: [{
        type: "text",
        text: redactedOutput
      }]
    };
  }
);

// ── Tool 6: ops_discover_github ────────────────────────────────

server.tool(
  "ops_discover_github",
  "Discover GitHub repository metadata, workflows, and recent CI status. Returns structured JSON. READ-tier operation. Gracefully degrades if gh CLI not available.",
  {
    repo: z
      .string()
      .optional()
      .describe("Repository in owner/repo format. If omitted, uses current repo."),
    include: z
      .array(z.enum(["workflows", "releases", "branches"]))
      .optional()
      .default(["workflows", "branches"])
      .describe("What to discover. Default: workflows and branches."),
  },
  async ({ repo, include }) => {
    // Check if gh CLI is available
    const checkResult = await execSafe("gh", ["--version"], { timeout: 5_000 });
    if (!checkResult.success) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            available: false,
            tool: "gh",
            reason: checkResult.error === "command_not_found" ? "gh CLI not found in PATH" : checkResult.message,
            suggestion: "Install GitHub CLI: brew install gh",
            isError: true
          }, null, 2)
        }]
      };
    }

    const discoveries = {};
    const errors = [];

    // Get repo info
    const repoArgs = ["repo", "view", "--json", "name,description,defaultBranchRef,isPrivate"];
    if (repo) {
      repoArgs.push(repo);
    }

    const repoResult = await execSafe("gh", repoArgs, { timeout: GITHUB_TIMEOUT_MS });
    if (repoResult.success) {
      try {
        const parsed = JSON.parse(repoResult.stdout);
        discoveries.repository = {
          name: parsed.name,
          description: parsed.description,
          default_branch: parsed.defaultBranchRef?.name,
          is_private: parsed.isPrivate
        };
      } catch (parseError) {
        errors.push({ operation: "repo_view", error: "Failed to parse JSON output" });
      }
    } else {
      errors.push({ operation: "repo_view", error: repoResult.message });
    }

    // Get workflows if requested
    if (include.includes("workflows")) {
      const workflowArgs = ["run", "list", "--limit", "10", "--json", "status,name,conclusion,createdAt"];
      if (repo) {
        workflowArgs.push("--repo", repo);
      }

      const workflowResult = await execSafe("gh", workflowArgs, { timeout: GITHUB_TIMEOUT_MS });
      if (workflowResult.success) {
        try {
          const parsed = JSON.parse(workflowResult.stdout);
          discoveries.workflows = {
            count: parsed.length,
            recent_runs: parsed.map(run => ({
              name: run.name,
              status: run.status,
              conclusion: run.conclusion,
              created_at: run.createdAt
            }))
          };
        } catch (parseError) {
          errors.push({ operation: "run_list", error: "Failed to parse JSON output" });
        }
      } else {
        errors.push({ operation: "run_list", error: workflowResult.message });
      }
    }

    // Get releases if requested
    if (include.includes("releases")) {
      const releaseArgs = ["release", "list", "--limit", "5", "--json", "tagName,name,publishedAt"];
      if (repo) {
        releaseArgs.push("--repo", repo);
      }

      const releaseResult = await execSafe("gh", releaseArgs, { timeout: GITHUB_TIMEOUT_MS });
      if (releaseResult.success) {
        try {
          const parsed = JSON.parse(releaseResult.stdout);
          discoveries.releases = {
            count: parsed.length,
            items: parsed.map(rel => ({
              tag: rel.tagName,
              name: rel.name,
              published_at: rel.publishedAt
            }))
          };
        } catch (parseError) {
          errors.push({ operation: "release_list", error: "Failed to parse JSON output" });
        }
      } else {
        errors.push({ operation: "release_list", error: releaseResult.message });
      }
    }

    // Get branches if requested
    if (include.includes("branches")) {
      let branchResult;
      if (repo) {
        // Explicit repo provided in owner/repo format
        branchResult = await execSafe("gh", ["api", `repos/${repo}/branches`, "--paginate=false"], { timeout: GITHUB_TIMEOUT_MS });
      } else {
        // Use current repo (gh will infer from git context)
        branchResult = await execSafe("gh", ["api", "repos/{owner}/{repo}/branches", "--paginate=false"], { timeout: GITHUB_TIMEOUT_MS });
      }

      if (branchResult.success) {
        try {
          const parsed = JSON.parse(branchResult.stdout);
          discoveries.branches = {
            count: parsed.length,
            items: parsed.slice(0, 20).map(branch => ({
              name: branch.name,
              protected: branch.protected,
              commit_sha: branch.commit?.sha?.substring(0, 7)
            }))
          };
        } catch (parseError) {
          errors.push({ operation: "branches_list", error: "Failed to parse JSON output" });
        }
      } else {
        errors.push({ operation: "branches_list", error: branchResult.message });
      }
    }

    const output = {
      available: true,
      tool: "gh",
      repo: repo || "current",
      discoveries,
      errors: errors.length > 0 ? errors : undefined,
      cache_ttl: CACHE_TTL_GITHUB
    };

    const redactedOutput = redactOutput(JSON.stringify(output, null, 2));

    return {
      content: [{
        type: "text",
        text: redactedOutput
      }]
    };
  }
);

// ── Tool 7: ops_discover_docker ────────────────────────────────

server.tool(
  "ops_discover_docker",
  "Discover Docker containers, images, and networks. Returns structured JSON. READ-tier operation. Gracefully degrades if docker CLI not available.",
  {
    include: z
      .array(z.enum(["containers", "images", "networks", "volumes"]))
      .optional()
      .default(["containers", "images"])
      .describe("What to discover. Default: containers and images."),
    all: z
      .boolean()
      .optional()
      .default(false)
      .describe("Include stopped containers (default: running only)."),
  },
  async ({ include, all }) => {
    // Check if docker CLI is available
    const checkResult = await execSafe("docker", ["--version"], { timeout: 5_000 });
    if (!checkResult.success) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            available: false,
            tool: "docker",
            reason: checkResult.error === "command_not_found" ? "docker CLI not found in PATH" : checkResult.message,
            suggestion: "Install Docker: https://docs.docker.com/get-docker/",
            isError: true
          }, null, 2)
        }]
      };
    }

    const discoveries = {};
    const errors = [];

    // Get containers
    if (include.includes("containers")) {
      const psArgs = ["ps", "--format", "json", "--no-trunc"];
      if (all) {
        psArgs.push("-a");
      }

      const containerResult = await execSafe("docker", psArgs, { timeout: DOCKER_TIMEOUT_MS });
      if (containerResult.success) {
        try {
          // Docker ps --format json outputs one JSON object per line (JSONL)
          const lines = containerResult.stdout.split("\n").filter(line => line.trim());
          const containers = lines.map(line => JSON.parse(line));
          discoveries.containers = {
            count: containers.length,
            items: containers.map(c => ({
              id: c.ID?.substring(0, 12),
              name: c.Names,
              image: c.Image,
              status: c.Status,
              state: c.State,
              ports: c.Ports
            }))
          };
        } catch (parseError) {
          errors.push({ operation: "ps", error: "Failed to parse JSON output" });
        }
      } else {
        errors.push({ operation: "ps", error: containerResult.message });
      }
    }

    // Get images
    if (include.includes("images")) {
      const imageResult = await execSafe("docker", ["images", "--format", "json", "--no-trunc"], { timeout: DOCKER_TIMEOUT_MS });
      if (imageResult.success) {
        try {
          // Docker images --format json outputs one JSON object per line (JSONL)
          const lines = imageResult.stdout.split("\n").filter(line => line.trim());
          const images = lines.map(line => JSON.parse(line));
          discoveries.images = {
            count: images.length,
            items: images.map(img => ({
              id: img.ID?.substring(7, 19), // Strip sha256: prefix
              repository: img.Repository,
              tag: img.Tag,
              size: img.Size,
              created: img.CreatedAt
            }))
          };
        } catch (parseError) {
          errors.push({ operation: "images", error: "Failed to parse JSON output" });
        }
      } else {
        errors.push({ operation: "images", error: imageResult.message });
      }
    }

    // Get networks
    if (include.includes("networks")) {
      const networkResult = await execSafe("docker", ["network", "ls", "--format", "json"], { timeout: DOCKER_TIMEOUT_MS });
      if (networkResult.success) {
        try {
          const lines = networkResult.stdout.split("\n").filter(line => line.trim());
          const networks = lines.map(line => JSON.parse(line));
          discoveries.networks = {
            count: networks.length,
            items: networks.map(net => ({
              id: net.ID?.substring(0, 12),
              name: net.Name,
              driver: net.Driver,
              scope: net.Scope
            }))
          };
        } catch (parseError) {
          errors.push({ operation: "network_ls", error: "Failed to parse JSON output" });
        }
      } else {
        errors.push({ operation: "network_ls", error: networkResult.message });
      }
    }

    // Get volumes
    if (include.includes("volumes")) {
      const volumeResult = await execSafe("docker", ["volume", "ls", "--format", "json"], { timeout: DOCKER_TIMEOUT_MS });
      if (volumeResult.success) {
        try {
          const lines = volumeResult.stdout.split("\n").filter(line => line.trim());
          const volumes = lines.map(line => JSON.parse(line));
          discoveries.volumes = {
            count: volumes.length,
            items: volumes.map(vol => ({
              name: vol.Name,
              driver: vol.Driver,
              mountpoint: vol.Mountpoint
            }))
          };
        } catch (parseError) {
          errors.push({ operation: "volume_ls", error: "Failed to parse JSON output" });
        }
      } else {
        errors.push({ operation: "volume_ls", error: volumeResult.message });
      }
    }

    const output = {
      available: true,
      tool: "docker",
      include_stopped: all,
      discoveries,
      errors: errors.length > 0 ? errors : undefined,
      cache_ttl: CACHE_TTL_DOCKER
    };

    const redactedOutput = redactOutput(JSON.stringify(output, null, 2));

    return {
      content: [{
        type: "text",
        text: redactedOutput
      }]
    };
  }
);

// ── Tool 8: ops_discover_redis ─────────────────────────────────

server.tool(
  "ops_discover_redis",
  "Discover Redis server info, databases, and key statistics. Returns structured JSON. READ-tier operation. Gracefully degrades if redis-cli not available.",
  {
    url: z
      .string()
      .optional()
      .describe("Redis connection URL. If omitted, uses REDIS_URL env var or localhost:6379."),
    section: z
      .array(z.enum(["server", "memory", "keyspace", "clients", "stats"]))
      .optional()
      .default(["server", "memory", "keyspace"])
      .describe("INFO sections to query. Default: server, memory, keyspace."),
  },
  async ({ url, section }) => {
    // Check if redis-cli is available
    const checkResult = await execSafe("redis-cli", ["--version"], { timeout: 5_000 });
    if (!checkResult.success) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            available: false,
            tool: "redis-cli",
            reason: checkResult.error === "command_not_found" ? "redis-cli not found in PATH" : checkResult.message,
            suggestion: "Install Redis: brew install redis",
            isError: true
          }, null, 2)
        }]
      };
    }

    // Use provided URL or env var or default
    const connUrl = url || process.env.REDIS_URL || "redis://localhost:6379";

    const discoveries = {};
    const errors = [];

    // Get INFO for each requested section
    for (const sec of section) {
      const infoResult = await execSafe("redis-cli", ["-u", connUrl, "INFO", sec], { timeout: REDIS_TIMEOUT_MS });
      if (infoResult.success) {
        try {
          // Parse INFO output (key:value pairs)
          const lines = infoResult.stdout.split("\n").filter(line => line.trim() && !line.startsWith("#"));
          const info = {};
          for (const line of lines) {
            const [key, value] = line.split(":").map(s => s.trim());
            if (key && value !== undefined) {
              info[key] = value;
            }
          }
          discoveries[sec] = info;
        } catch (parseError) {
          errors.push({ operation: `info_${sec}`, error: "Failed to parse INFO output" });
        }
      } else {
        errors.push({ operation: `info_${sec}`, error: infoResult.message });
      }
    }

    // Get DBSIZE (total key count)
    const dbsizeResult = await execSafe("redis-cli", ["-u", connUrl, "DBSIZE"], { timeout: REDIS_TIMEOUT_MS });
    if (dbsizeResult.success) {
      const parsedSize = parseInt(dbsizeResult.stdout.trim(), 10);
      discoveries.dbsize = isNaN(parsedSize) ? 0 : parsedSize;
    } else {
      errors.push({ operation: "dbsize", error: dbsizeResult.message });
    }

    const output = {
      available: true,
      tool: "redis-cli",
      connection: "redacted",
      discoveries,
      errors: errors.length > 0 ? errors : undefined,
      cache_ttl: CACHE_TTL_REDIS
    };

    const redactedOutput = redactOutput(JSON.stringify(output, null, 2));

    return {
      content: [{
        type: "text",
        text: redactedOutput
      }]
    };
  }
);

// ── Tool 9: ops_discover_argo_workflows ────────────────────────

server.tool(
  "ops_discover_argo_workflows",
  "Discover Argo Workflows and their status. Returns structured JSON. READ-tier operation. Gracefully degrades if argo CLI not available.",
  {
    namespace: z
      .string()
      .optional()
      .describe("Kubernetes namespace. Defaults to 'argo-workflows'."),
    all_namespaces: z
      .boolean()
      .optional()
      .default(false)
      .describe("Search all namespaces (equivalent to argo list -A)."),
    status: z
      .enum(["Running", "Succeeded", "Failed", "Error", "Pending"])
      .optional()
      .describe("Filter by workflow status."),
    limit: z
      .number()
      .optional()
      .default(20)
      .describe("Maximum workflows to list (default 20, max 100)."),
  },
  async ({ namespace, all_namespaces, status, limit }) => {
    // Check if argo CLI is available
    const checkResult = await execSafe("argo", ["version"], { timeout: 5_000 });
    if (!checkResult.success) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            available: false,
            tool: "argo",
            reason: checkResult.error === "command_not_found" ? "argo CLI not found in PATH" : checkResult.message,
            suggestion: "Install Argo Workflows CLI: brew install argo",
            isError: true
          }, null, 2)
        }]
      };
    }

    const discoveries = {};
    const errors = [];
    const ns = namespace || "argo-workflows";
    const limitedLimit = Math.min(limit, 100);

    // List workflows
    const listArgs = ["list"];
    if (all_namespaces) {
      listArgs.push("-A");  // All namespaces
    } else {
      listArgs.push("--namespace", ns);
    }
    listArgs.push("--output", "json");
    if (status) {
      listArgs.push("--status", status);
    }

    const listResult = await execSafe("argo", listArgs, { timeout: ARGO_WORKFLOWS_TIMEOUT_MS });
    if (listResult.success) {
      try {
        const parsed = JSON.parse(listResult.stdout);
        const workflows = Array.isArray(parsed) ? parsed : (parsed.items || []);
        discoveries.workflows = {
          count: workflows.length,
          items: workflows.slice(0, limitedLimit).map(wf => ({
            name: wf.metadata?.name,
            namespace: wf.metadata?.namespace,
            status: wf.status?.phase,
            started_at: wf.status?.startedAt,
            finished_at: wf.status?.finishedAt,
            progress: wf.status?.progress
          }))
        };
        // Add helpful hint if no workflows found
        if (workflows.length === 0) {
          discoveries.workflows.hint = all_namespaces
            ? "No workflows found in any namespace. Check: kubectl get workflows -A"
            : `No workflows found in namespace "${ns}". Try all_namespaces: true or check: kubectl get workflows -A`;
        }
      } catch (parseError) {
        errors.push({ operation: "list", error: "Failed to parse JSON output" });
      }
    } else {
      errors.push({ operation: "list", error: listResult.message });
    }

    const output = {
      available: true,
      tool: "argo",
      namespace: all_namespaces ? "all" : ns,
      all_namespaces: all_namespaces || false,
      filter_status: status || "all",
      discoveries,
      errors: errors.length > 0 ? errors : undefined,
      cache_ttl: CACHE_TTL_ARGO_WORKFLOWS
    };

    const redactedOutput = redactOutput(JSON.stringify(output, null, 2));

    return {
      content: [{
        type: "text",
        text: redactedOutput
      }]
    };
  }
);

// ── Tool 10: ops_discover (Unified Discovery) ──────────────────

server.tool(
  "ops_discover",
  "Unified discovery tool that aggregates all 9 infrastructure discovery tools. Executes tools in parallel (configurable) and returns combined results. Useful for getting a comprehensive infrastructure snapshot.",
  {
    tools: z
      .array(z.enum([
        "k8s", "argocd", "postgres", "supabase", "s3",
        "github", "docker", "redis", "argo_workflows"
      ]))
      .optional()
      .default(["k8s", "argocd", "postgres", "supabase", "s3", "github", "docker", "redis", "argo_workflows"])
      .describe("Tools to run. Default: all 9 tools."),
    parallel: z
      .boolean()
      .optional()
      .describe("Execute in parallel. Defaults to config setting."),
    timeout_override: z
      .number()
      .optional()
      .describe("Override timeout for all tools (ms)."),
  },
  async ({ tools, parallel, timeout_override }) => {
    if (!opsConfig.unified_discovery.enabled) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            error: "Unified discovery is disabled in config",
            suggestion: "Set unified_discovery.enabled: true in .claude/config/ops.json"
          }, null, 2)
        }]
      };
    }

    const useParallel = parallel !== undefined ? parallel : opsConfig.unified_discovery.parallel_execution;
    const startTime = Date.now();

    // Map tool names to their internal handlers
    const toolHandlers = {
      k8s: async () => {
        if (!isToolEnabled("k8s")) return { tool: "k8s", enabled: false, reason: "Disabled in config" };
        const checkResult = await execSafe("kubectl", ["version", "--client", "--output=json"], { timeout: 5000 });
        if (!checkResult.success) return { tool: "k8s", available: false, reason: "kubectl not found" };

        const args = ["get", "pods", "--all-namespaces", "--output=json"];
        const result = await execSafe("kubectl", args, { timeout: timeout_override || getToolTimeout("k8s") });
        if (result.success) {
          try {
            const parsed = JSON.parse(result.stdout);
            return {
              tool: "k8s",
              available: true,
              summary: {
                pod_count: parsed.items?.length || 0,
                namespaces: [...new Set(parsed.items?.map(p => p.metadata?.namespace) || [])].length
              }
            };
          } catch {
            return { tool: "k8s", available: true, parse_error: true };
          }
        }
        return { tool: "k8s", available: true, error: result.message };
      },
      argocd: async () => {
        if (!isToolEnabled("argocd")) return { tool: "argocd", enabled: false };
        const checkResult = await execSafe("argocd", ["version", "--client"], { timeout: 5000 });
        if (!checkResult.success) return { tool: "argocd", available: false };

        const result = await execSafe("argocd", ["app", "list", "--output=json"], { timeout: timeout_override || getToolTimeout("argocd") });
        if (result.success) {
          try {
            const parsed = JSON.parse(result.stdout);
            return {
              tool: "argocd",
              available: true,
              summary: {
                app_count: parsed.length,
                synced: parsed.filter(a => a.status?.sync?.status === "Synced").length
              }
            };
          } catch {
            return { tool: "argocd", available: true, parse_error: true };
          }
        }
        return { tool: "argocd", available: true, error: result.message };
      },
      postgres: async () => {
        if (!isToolEnabled("postgres")) return { tool: "postgres", enabled: false };
        const checkResult = await execSafe("psql", ["--version"], { timeout: 5000 });
        if (!checkResult.success) return { tool: "postgres", available: false };

        const connUrl = process.env.DATABASE_URL;
        if (!connUrl) return { tool: "postgres", available: true, error: "No DATABASE_URL" };

        const result = await execSafe("psql", [connUrl, "-t", "-c", "SELECT count(*) FROM pg_database WHERE datistemplate = false;"], { timeout: timeout_override || getToolTimeout("postgres") });
        if (result.success) {
          return {
            tool: "postgres",
            available: true,
            summary: { database_count: parseInt(result.stdout.trim()) || 0 }
          };
        }
        return { tool: "postgres", available: true, error: result.message };
      },
      supabase: async () => {
        if (!isToolEnabled("supabase")) return { tool: "supabase", enabled: false };
        const checkResult = await execSafe("supabase", ["--version"], { timeout: 5000 });
        if (!checkResult.success) return { tool: "supabase", available: false };
        return { tool: "supabase", available: true, summary: { status: "connected" } };
      },
      s3: async () => {
        if (!isToolEnabled("s3")) return { tool: "s3", enabled: false };
        const checkResult = await execSafe("aws", ["--version"], { timeout: 5000 });
        if (!checkResult.success) return { tool: "s3", available: false };

        const result = await execSafe("aws", ["s3api", "list-buckets", "--output", "json"], { timeout: timeout_override || getToolTimeout("s3") });
        if (result.success) {
          try {
            const parsed = JSON.parse(result.stdout);
            return {
              tool: "s3",
              available: true,
              summary: { bucket_count: parsed.Buckets?.length || 0 }
            };
          } catch {
            return { tool: "s3", available: true, parse_error: true };
          }
        }
        return { tool: "s3", available: true, error: result.message };
      },
      github: async () => {
        if (!isToolEnabled("github")) return { tool: "github", enabled: false };
        const checkResult = await execSafe("gh", ["--version"], { timeout: 5000 });
        if (!checkResult.success) return { tool: "github", available: false };

        const result = await execSafe("gh", ["repo", "view", "--json", "name,defaultBranchRef"], { timeout: timeout_override || getToolTimeout("github") });
        if (result.success) {
          try {
            const parsed = JSON.parse(result.stdout);
            return {
              tool: "github",
              available: true,
              summary: { repo: parsed.name, default_branch: parsed.defaultBranchRef?.name }
            };
          } catch {
            return { tool: "github", available: true, parse_error: true };
          }
        }
        return { tool: "github", available: true, error: result.message };
      },
      docker: async () => {
        if (!isToolEnabled("docker")) return { tool: "docker", enabled: false };
        const checkResult = await execSafe("docker", ["--version"], { timeout: 5000 });
        if (!checkResult.success) return { tool: "docker", available: false };

        const result = await execSafe("docker", ["ps", "--format", "json"], { timeout: timeout_override || getToolTimeout("docker") });
        if (result.success) {
          const lines = result.stdout.split("\n").filter(l => l.trim());
          return {
            tool: "docker",
            available: true,
            summary: { container_count: lines.length }
          };
        }
        return { tool: "docker", available: true, error: result.message };
      },
      redis: async () => {
        if (!isToolEnabled("redis")) return { tool: "redis", enabled: false };
        const checkResult = await execSafe("redis-cli", ["--version"], { timeout: 5000 });
        if (!checkResult.success) return { tool: "redis", available: false };

        const connUrl = process.env.REDIS_URL || "redis://localhost:6379";
        const result = await execSafe("redis-cli", ["-u", connUrl, "DBSIZE"], { timeout: timeout_override || getToolTimeout("redis") });
        if (result.success) {
          const parsedSize = parseInt(result.stdout.trim(), 10);
          return {
            tool: "redis",
            available: true,
            summary: { key_count: isNaN(parsedSize) ? 0 : parsedSize }
          };
        }
        return { tool: "redis", available: true, error: result.message };
      },
      argo_workflows: async () => {
        if (!isToolEnabled("argo_workflows")) return { tool: "argo_workflows", enabled: false };
        const checkResult = await execSafe("argo", ["version"], { timeout: 5000 });
        if (!checkResult.success) return { tool: "argo_workflows", available: false };

        const result = await execSafe("argo", ["list", "--namespace", "argo", "--output", "json"], { timeout: timeout_override || getToolTimeout("argo_workflows") });
        if (result.success) {
          try {
            const parsed = JSON.parse(result.stdout);
            const workflows = Array.isArray(parsed) ? parsed : (parsed.items || []);
            return {
              tool: "argo_workflows",
              available: true,
              summary: { workflow_count: workflows.length }
            };
          } catch {
            return { tool: "argo_workflows", available: true, parse_error: true };
          }
        }
        return { tool: "argo_workflows", available: true, error: result.message };
      }
    };

    // Execute tools
    let results;
    if (useParallel) {
      // Parallel execution with concurrency limit
      const maxConcurrent = opsConfig.unified_discovery.max_concurrent;
      const chunks = [];
      for (let i = 0; i < tools.length; i += maxConcurrent) {
        chunks.push(tools.slice(i, i + maxConcurrent));
      }

      results = [];
      for (const chunk of chunks) {
        const chunkResults = await Promise.all(
          chunk.map(tool => toolHandlers[tool]().catch(error => ({
            tool,
            error: error.message
          })))
        );
        results.push(...chunkResults);
      }
    } else {
      // Sequential execution
      results = [];
      for (const tool of tools) {
        try {
          const result = await toolHandlers[tool]();
          results.push(result);
        } catch (error) {
          results.push({ tool, error: error.message });
        }
      }
    }

    const duration = Date.now() - startTime;

    const output = {
      unified_discovery: true,
      execution_mode: useParallel ? "parallel" : "sequential",
      duration_ms: duration,
      tools_requested: tools.length,
      tools_executed: results.length,
      summary: {
        available: results.filter(r => r.available === true).length,
        unavailable: results.filter(r => r.available === false).length,
        disabled: results.filter(r => r.enabled === false).length,
        errors: results.filter(r => r.error).length
      },
      results
    };

    const redactedOutput = redactOutput(JSON.stringify(output, null, 2));

    return {
      content: [{
        type: "text",
        text: redactedOutput
      }]
    };
  }
);

// ── Tool 11: ops_plan_mutation ─────────────────────────────────

server.tool(
  "ops_plan_mutation",
  "Plan a mutating operation (WRITE/INFRASTRUCTURE tier). Creates an execution plan with hash for approval. Returns plan_id and dry-run output. Does not execute - requires approval via ops_approve.",
  {
    tier: z
      .enum(["WRITE", "INFRASTRUCTURE"])
      .describe("Permission tier for this operation."),
    operation: z
      .string()
      .describe("Operation type (e.g., 'kubectl_apply', 'argocd_sync', 'postgres_migrate')."),
    scope: z
      .object({
        namespace: z.string().optional(),
        resource: z.string().optional(),
        target: z.string().optional()
      })
      .describe("Operation scope (namespace, resource, target)."),
    params: z
      .record(z.any())
      .describe("Operation-specific parameters (e.g., file path, query, flags)."),
    dry_run_output: z
      .string()
      .optional()
      .describe("Optional pre-computed dry-run output for validation."),
  },
  async ({ tier, operation, scope, params, dry_run_output }) => {
    if (!opsConfig.approval.enabled) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            error: "Approval workflow is disabled in config",
            suggestion: "Set approval.enabled: true in .claude/config/ops.json"
          }, null, 2)
        }]
      };
    }

    try {
      // Generate plan
      const planDetails = {
        tier,
        operation,
        scope,
        params,
        dry_run_output: dry_run_output || "[No dry-run output provided]",
        timestamp: new Date().toISOString()
      };

      const planId = generatePlanId();
      const planHash = hashPlan(planDetails);
      const createdAt = Math.floor(Date.now() / 1000);

      // Check for hash collision
      const existingPlans = await checkPlanCollision(planHash);
      const collision_warning = existingPlans.length > 0 ? {
        warning: "Identical plan(s) already exist",
        existing_plans: existingPlans.map(p => ({
          plan_id: p.plan_id,
          status: p.status,
          created_at: new Date(p.created_at * 1000).toISOString()
        }))
      } : undefined;

      // Store in approval database (using parameterized query for SQL injection protection)
      const planDetailsJson = JSON.stringify(planDetails);
      const version = 1;
      const insertSQL = `INSERT INTO approvals (plan_id, plan_hash, plan_details, tier, status, version, created_at) VALUES (?, ?, ?, ?, 'pending', ?, ?)`;

      // Use sqlite3 with bind parameters
      await execSafe("sqlite3", [
        approvalDb,
        "-cmd", `.param init`,
        "-cmd", `.param set :1 ${planId}`,
        "-cmd", `.param set :2 ${planHash}`,
        "-cmd", `.param set :3 ${planDetailsJson}`,
        "-cmd", `.param set :4 ${tier}`,
        "-cmd", `.param set :5 ${version}`,
        "-cmd", `.param set :6 ${createdAt}`,
        insertSQL.replace(/\?/g, (_, i) => `:${i + 1}`)
      ], { timeout: 5000 });

      // Save to plan history
      await savePlanHistory(planId, version, planHash, planDetails);

      // Log audit event
      await logAudit(planId, "plan_created", {
        tier,
        operation,
        collision: existingPlans.length > 0
      });

      const output = {
        plan_id: planId,
        plan_hash: planHash,
        version,
        tier,
        operation,
        scope,
        params: redactOutput(JSON.stringify(params)),
        dry_run_output: redactOutput(dry_run_output || ""),
        status: "pending_approval",
        ttl_minutes: opsConfig.approval.ttl_minutes,
        collision_warning,
        next_step: "Call ops_approve with plan_id and plan_hash to approve this operation"
      };

      return {
        content: [{
          type: "text",
          text: JSON.stringify(output, null, 2)
        }]
      };
    } catch (error) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            error: "Failed to create plan",
            message: error.message
          }, null, 2)
        }],
        isError: true
      };
    }
  }
);

// ── Tool 11: ops_approve ───────────────────────────────────────

server.tool(
  "ops_approve",
  "Approve a pending mutation plan. Verifies plan_hash to prevent tampering. Approvals are valid for 30 minutes (configurable). After approval, use ops_execute to run the operation.",
  {
    plan_id: z
      .string()
      .describe("Plan ID from ops_plan_mutation."),
    plan_hash: z
      .string()
      .describe("Plan hash from ops_plan_mutation (tamper protection)."),
  },
  async ({ plan_id, plan_hash }) => {
    if (!opsConfig.approval.enabled) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            error: "Approval workflow is disabled in config"
          }, null, 2)
        }]
      };
    }

    try {
      // Validate plan_id format (SQL injection protection)
      const planIdRegex = /^plan_\d+_[a-z0-9]{8,16}$/;
      if (!planIdRegex.test(plan_id)) {
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              error: "Invalid plan_id format",
              plan_id
            }, null, 2)
          }],
          isError: true
        };
      }

      // Load plan (parameterized query)
      const rows = await approvalQuery(`SELECT * FROM approvals WHERE plan_id = ?`, [plan_id]);

      if (rows.length === 0) {
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              error: "Plan not found",
              plan_id
            }, null, 2)
          }],
          isError: true
        };
      }

      const plan = rows[0];

      // Verify hash
      if (opsConfig.approval.require_hash_match && plan.plan_hash !== plan_hash) {
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              error: "Plan hash mismatch - potential tampering detected",
              plan_id,
              expected_hash: plan.plan_hash,
              provided_hash: plan_hash
            }, null, 2)
          }],
          isError: true
        };
      }

      // Check TTL
      const now = Math.floor(Date.now() / 1000);
      const age = now - plan.created_at;
      const maxAge = opsConfig.approval.ttl_minutes * 60;

      if (age > maxAge) {
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              error: "Plan expired",
              plan_id,
              age_seconds: age,
              max_age_seconds: maxAge,
              suggestion: "Create a new plan with ops_plan_mutation"
            }, null, 2)
          }],
          isError: true
        };
      }

      // Check current status
      if (plan.status !== "pending") {
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              error: "Plan not in pending status",
              plan_id,
              current_status: plan.status
            }, null, 2)
          }],
          isError: true
        };
      }

      // Approve (parameterized query)
      const approvedAt = Math.floor(Date.now() / 1000);
      const updateSQL = `UPDATE approvals SET status = 'approved', approved_at = ? WHERE plan_id = ?`;
      await approvalQuery(updateSQL, [approvedAt, plan_id]);

      // Log audit event
      const planDetailsObj = JSON.parse(plan.plan_details);
      await logAudit(plan_id, "plan_approved", {
        tier: plan.tier,
        operation: planDetailsObj.operation,
        hash_verified: true
      });

      const output = {
        approved: true,
        plan_id,
        tier: plan.tier,
        operation: planDetailsObj.operation,
        approved_at: new Date(approvedAt * 1000).toISOString(),
        expires_at: new Date((plan.created_at + maxAge) * 1000).toISOString(),
        next_step: "Call ops_execute with plan_id to execute this operation"
      };

      return {
        content: [{
          type: "text",
          text: JSON.stringify(output, null, 2)
        }]
      };
    } catch (error) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            error: "Failed to approve plan",
            message: error.message
          }, null, 2)
        }],
        isError: true
      };
    }
  }
);

// ── Tool 12: ops_list_pending ──────────────────────────────────

server.tool(
  "ops_list_pending",
  "List pending approval plans. Shows all plans awaiting approval, with age and expiration info.",
  {
    include_expired: z
      .boolean()
      .optional()
      .default(false)
      .describe("Include expired plans in results."),
  },
  async ({ include_expired }) => {
    if (!opsConfig.approval.enabled) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            error: "Approval workflow is disabled in config"
          }, null, 2)
        }]
      };
    }

    try {
      const rows = await approvalQuery(`SELECT * FROM approvals WHERE status = 'pending' ORDER BY created_at DESC LIMIT 100`);

      const now = Math.floor(Date.now() / 1000);
      const maxAge = opsConfig.approval.ttl_minutes * 60;

      let pending = rows.map(plan => {
        const age = now - plan.created_at;
        const expired = age > maxAge;
        const planDetails = JSON.parse(plan.plan_details);

        return {
          plan_id: plan.plan_id,
          plan_hash: plan.plan_hash,
          tier: plan.tier,
          operation: planDetails.operation,
          scope: planDetails.scope,
          created_at: new Date(plan.created_at * 1000).toISOString(),
          age_seconds: age,
          expired,
          expires_at: new Date((plan.created_at + maxAge) * 1000).toISOString()
        };
      });

      if (!include_expired) {
        pending = pending.filter(p => !p.expired);
      }

      const output = {
        count: pending.length,
        max_pending: opsConfig.approval.max_pending,
        ttl_minutes: opsConfig.approval.ttl_minutes,
        pending_plans: pending
      };

      return {
        content: [{
          type: "text",
          text: JSON.stringify(output, null, 2)
        }]
      };
    } catch (error) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            error: "Failed to list pending plans",
            message: error.message
          }, null, 2)
        }],
        isError: true
      };
    }
  }
);

// ── Tool 13: ops_audit_log ─────────────────────────────────────

server.tool(
  "ops_audit_log",
  "View audit log for approval workflow. Shows who approved/executed plans and when. Supports filtering by plan_id or time range.",
  {
    plan_id: z
      .string()
      .optional()
      .describe("Filter by specific plan ID. If omitted, shows recent logs."),
    limit: z
      .number()
      .optional()
      .default(50)
      .describe("Maximum number of log entries to return (default 50, max 200)."),
    since: z
      .number()
      .optional()
      .describe("Show logs since this Unix timestamp."),
  },
  async ({ plan_id, limit, since }) => {
    if (!opsConfig.approval.enabled) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            error: "Approval workflow is disabled in config"
          }, null, 2)
        }]
      };
    }

    try {
      const limitedLimit = Math.min(limit, 200);
      let query = `SELECT * FROM audit_log`;
      const params = [];
      const conditions = [];

      if (plan_id) {
        conditions.push(`plan_id = ?`);
        params.push(plan_id);
      }

      if (since) {
        conditions.push(`timestamp >= ?`);
        params.push(since);
      }

      if (conditions.length > 0) {
        query += ` WHERE ` + conditions.join(" AND ");
      }

      query += ` ORDER BY timestamp DESC LIMIT ?`;
      params.push(limitedLimit);

      const rows = await approvalQuery(query, params);

      const logs = rows.map(log => ({
        plan_id: log.plan_id,
        action: log.action,
        actor: log.actor,
        timestamp: new Date(log.timestamp * 1000).toISOString(),
        details: log.details ? JSON.parse(log.details) : {}
      }));

      const output = {
        audit_log: true,
        count: logs.length,
        filter: {
          plan_id: plan_id || "all",
          since: since ? new Date(since * 1000).toISOString() : undefined
        },
        logs
      };

      return {
        content: [{
          type: "text",
          text: JSON.stringify(output, null, 2)
        }]
      };
    } catch (error) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            error: "Failed to retrieve audit log",
            message: error.message
          }, null, 2)
        }],
        isError: true
      };
    }
  }
);

// ── Tool 14: ops_plan_history ──────────────────────────────────

server.tool(
  "ops_plan_history",
  "View version history for a plan. Shows all versions, changes, and provides diff visualization between versions.",
  {
    plan_id: z
      .string()
      .describe("Plan ID to view history for."),
    show_diff: z
      .boolean()
      .optional()
      .default(false)
      .describe("Include diff between consecutive versions."),
  },
  async ({ plan_id, show_diff }) => {
    if (!opsConfig.approval.enabled) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            error: "Approval workflow is disabled in config"
          }, null, 2)
        }]
      };
    }

    try {
      // Get current plan
      const currentRows = await approvalQuery(`SELECT * FROM approvals WHERE plan_id = ? LIMIT 1`, [plan_id]);
      if (currentRows.length === 0) {
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              error: "Plan not found",
              plan_id
            }, null, 2)
          }],
          isError: true
        };
      }

      // Get history
      const historyRows = await approvalQuery(`SELECT * FROM plan_history WHERE plan_id = ? ORDER BY version ASC`, [plan_id]);

      const current = currentRows[0];
      const versions = historyRows.map(h => ({
        version: h.version,
        plan_hash: h.plan_hash,
        created_at: new Date(h.created_at * 1000).toISOString(),
        plan_details: JSON.parse(h.plan_details)
      }));

      // Add current version
      versions.push({
        version: current.version,
        plan_hash: current.plan_hash,
        created_at: new Date(current.created_at * 1000).toISOString(),
        plan_details: JSON.parse(current.plan_details),
        status: current.status
      });

      const output = {
        plan_id,
        total_versions: versions.length,
        current_version: current.version,
        current_status: current.status,
        versions
      };

      // Add simple diff if requested
      if (show_diff && versions.length > 1) {
        const diffs = [];
        for (let i = 1; i < versions.length; i++) {
          const prev = versions[i - 1];
          const curr = versions[i];

          const changes = [];
          if (prev.plan_hash !== curr.plan_hash) {
            changes.push({
              field: "plan_hash",
              from: prev.plan_hash,
              to: curr.plan_hash
            });
          }

          // Compare plan details fields
          const prevDetails = prev.plan_details;
          const currDetails = curr.plan_details;

          for (const key of Object.keys(currDetails)) {
            if (JSON.stringify(prevDetails[key]) !== JSON.stringify(currDetails[key])) {
              changes.push({
                field: `plan_details.${key}`,
                from: prevDetails[key],
                to: currDetails[key]
              });
            }
          }

          diffs.push({
            from_version: prev.version,
            to_version: curr.version,
            changes
          });
        }
        output.diffs = diffs;
      }

      return {
        content: [{
          type: "text",
          text: JSON.stringify(output, null, 2)
        }]
      };
    } catch (error) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            error: "Failed to retrieve plan history",
            plan_id,
            message: error.message
          }, null, 2)
        }],
        isError: true
      };
    }
  }
);

// ── Tool 15: ops_health ────────────────────────────────────────

server.tool(
  "ops_health",
  "Health check endpoint for Ops MCP server. Returns uptime, metrics, database status, and configuration state.",
  {},
  async () => {
    const startTime = Date.now();

    try {
      const health = {
        status: "healthy",
        timestamp: new Date().toISOString(),
        uptime: getMetricsSummary(),
        database: {
          approvals_db: approvalDb ? "connected" : "not initialized"
        },
        configuration: {
          enabled: opsConfig.enabled,
          discovery_enabled: opsConfig.discovery.enabled,
          approval_enabled: opsConfig.approval.enabled,
          unified_discovery_enabled: opsConfig.unified_discovery.enabled
        },
        environment: {
          node_version: process.version,
          platform: process.platform,
          metrics_enabled: ENABLE_METRICS,
          logging_enabled: ENABLE_LOGGING
        }
      };

      // Test database connectivity
      if (approvalDb) {
        try {
          await approvalQuery(`SELECT COUNT(*) as count FROM approvals`, []);
          health.database.approvals_db = "healthy";
        } catch (error) {
          health.database.approvals_db = "error: " + error.message;
          health.status = "degraded";
        }
      }

      const duration = Date.now() - startTime;
      recordMetric("ops_health", duration, true);
      logEvent("info", "health_check", { status: health.status, duration_ms: duration });

      return {
        content: [{
          type: "text",
          text: JSON.stringify(health, null, 2)
        }]
      };
    } catch (error) {
      const duration = Date.now() - startTime;
      recordMetric("ops_health", duration, false);
      logEvent("error", "health_check_failed", { error: error.message, duration_ms: duration });

      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            status: "unhealthy",
            error: error.message,
            timestamp: new Date().toISOString()
          }, null, 2)
        }],
        isError: true
      };
    }
  }
);

// ── Tool 16: ops_metrics ───────────────────────────────────────

server.tool(
  "ops_metrics",
  "View performance metrics for Ops MCP server. Shows call counts, average durations, error rates per tool.",
  {
    reset: z
      .boolean()
      .optional()
      .default(false)
      .describe("Reset metrics counters after retrieving."),
  },
  async ({ reset }) => {
    try {
      const metricsData = getMetricsSummary();

      if (reset) {
        // Reset counters
        metrics.toolCalls = {};
        metrics.errors = {};
        metrics.totalCalls = 0;
        metrics.totalErrors = 0;
        metrics.startTime = Date.now();

        logEvent("info", "metrics_reset", {});
      }

      return {
        content: [{
          type: "text",
          text: JSON.stringify(metricsData, null, 2)
        }]
      };
    } catch (error) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            error: "Failed to retrieve metrics",
            message: error.message
          }, null, 2)
        }],
        isError: true
      };
    }
  }
);

// ── Tool 17: ops_config_validate ───────────────────────────────

server.tool(
  "ops_config_validate",
  "Validate ops configuration file against schema. Checks syntax, required fields, and value types. Returns validation errors or success status.",
  {
    config_path: z
      .string()
      .optional()
      .describe("Path to config file. Defaults to .claude/config/ops.json."),
  },
  async ({ config_path }) => {
    try {
      const repoRoot = await getRepoRootWithFallback();
      const configFilePath = config_path || resolve(repoRoot, ".claude/config/ops.json");

      // Check if file exists
      if (!existsSync(configFilePath)) {
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              valid: false,
              error: "Config file not found",
              path: configFilePath,
              suggestion: "Create config file or use default configuration"
            }, null, 2)
          }]
        };
      }

      // Read and parse
      const configData = readFileSync(configFilePath, "utf-8");
      let parsed;
      try {
        parsed = JSON.parse(configData);
      } catch (parseError) {
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              valid: false,
              error: "Invalid JSON syntax",
              message: parseError.message,
              path: configFilePath
            }, null, 2)
          }],
          isError: true
        };
      }

      // Validate schema
      const errors = validateConfig(parsed);
      if (errors.length > 0) {
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              valid: false,
              validation_errors: errors,
              path: configFilePath,
              config_version: parsed.version || "unknown"
            }, null, 2)
          }],
          isError: true
        };
      }

      // Check if migration needed
      const currentVersion = parsed.version || "1.0.0";
      const latestVersion = "1.1.0"; // Update as schema evolves
      const migrationNeeded = currentVersion !== latestVersion;

      // Check environment overrides
      const envOverrides = [];
      if (process.env.OPS_ENABLED !== undefined) envOverrides.push("OPS_ENABLED");
      if (process.env.OPS_DISCOVERY_ENABLED !== undefined) envOverrides.push("OPS_DISCOVERY_ENABLED");
      if (process.env.OPS_APPROVAL_ENABLED !== undefined) envOverrides.push("OPS_APPROVAL_ENABLED");
      if (process.env.OPS_APPROVAL_TTL_MINUTES !== undefined) envOverrides.push("OPS_APPROVAL_TTL_MINUTES");
      if (process.env.OPS_ENABLE_METRICS !== undefined) envOverrides.push("OPS_ENABLE_METRICS");
      if (process.env.OPS_ENABLE_LOGGING !== undefined) envOverrides.push("OPS_ENABLE_LOGGING");

      const output = {
        valid: true,
        path: configFilePath,
        version: currentVersion,
        latest_version: latestVersion,
        migration_needed: migrationNeeded,
        migration_path: migrationNeeded ? `${currentVersion} → ${latestVersion}` : undefined,
        environment_overrides: envOverrides.length > 0 ? envOverrides : undefined,
        configuration: {
          enabled: parsed.enabled,
          discovery_enabled: parsed.discovery?.enabled,
          approval_enabled: parsed.approval?.enabled,
          unified_discovery_enabled: parsed.unified_discovery?.enabled
        }
      };

      return {
        content: [{
          type: "text",
          text: JSON.stringify(output, null, 2)
        }]
      };
    } catch (error) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            valid: false,
            error: "Validation failed",
            message: error.message
          }, null, 2)
        }],
        isError: true
      };
    }
  }
);

// ── Tool 18: ops_execute ───────────────────────────────────────

server.tool(
  "ops_execute",
  "Execute an approved mutation plan. Verifies approval status and TTL before execution. Returns operation result. This is a WRITE/INFRASTRUCTURE tier operation - use with caution.",
  {
    plan_id: z
      .string()
      .describe("Plan ID from ops_plan_mutation (must be approved)."),
  },
  async ({ plan_id }) => {
    if (!opsConfig.approval.enabled) {
      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            error: "Approval workflow is disabled in config"
          }, null, 2)
        }]
      };
    }

    try {
      // Validate plan_id format (SQL injection protection)
      const planIdRegex = /^plan_\d+_[a-z0-9]{8,16}$/;
      if (!planIdRegex.test(plan_id)) {
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              error: "Invalid plan_id format",
              plan_id
            }, null, 2)
          }],
          isError: true
        };
      }

      // Load plan (parameterized query)
      const rows = await approvalQuery(`SELECT * FROM approvals WHERE plan_id = ?`, [plan_id]);

      if (rows.length === 0) {
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              error: "Plan not found",
              plan_id
            }, null, 2)
          }],
          isError: true
        };
      }

      const plan = rows[0];

      // Check status
      if (plan.status !== "approved") {
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              error: "Plan not approved",
              plan_id,
              current_status: plan.status,
              suggestion: plan.status === "pending" ? "Call ops_approve first" : "Plan already executed or invalid"
            }, null, 2)
          }],
          isError: true
        };
      }

      // Check TTL
      const now = Math.floor(Date.now() / 1000);
      const age = now - plan.created_at;
      const maxAge = opsConfig.approval.ttl_minutes * 60;

      if (age > maxAge) {
        return {
          content: [{
            type: "text",
            text: JSON.stringify({
              error: "Plan expired",
              plan_id,
              age_seconds: age,
              max_age_seconds: maxAge
            }, null, 2)
          }],
          isError: true
        };
      }

      // Mark as executing (parameterized query)
      const executingAt = Math.floor(Date.now() / 1000);
      await approvalQuery(`UPDATE approvals SET status = 'executing', executed_at = ? WHERE plan_id = ?`, [executingAt, plan_id]);

      // Log audit event
      const planDetails = JSON.parse(plan.plan_details);
      await logAudit(plan_id, "plan_executing", {
        tier: plan.tier,
        operation: planDetails.operation
      });

      // NOTE: This is a placeholder - actual execution would dispatch to appropriate CLI
      // For Stage 3, we return a simulation message
      const simulatedResult = {
        executed: true,
        plan_id,
        tier: plan.tier,
        operation: planDetails.operation,
        scope: planDetails.scope,
        executed_at: new Date(executingAt * 1000).toISOString(),
        result: "SIMULATION: Execution framework not yet implemented. In production, this would dispatch to the appropriate CLI wrapper with the approved parameters.",
        note: "Stage 3 implements the approval workflow structure. Stage 4 will add actual CLI execution dispatch."
      };

      // Store result (parameterized query)
      const resultJSON = JSON.stringify(simulatedResult);
      await approvalQuery(`UPDATE approvals SET status = 'executed', result = ? WHERE plan_id = ?`, [resultJSON, plan_id]);

      // Log audit event
      await logAudit(plan_id, "plan_executed", {
        tier: plan.tier,
        operation: planDetails.operation,
        success: true
      });

      const redactedResult = redactOutput(JSON.stringify(simulatedResult, null, 2));

      return {
        content: [{
          type: "text",
          text: redactedResult
        }]
      };
    } catch (error) {
      // Mark as failed (parameterized query)
      try {
        const errorJSON = JSON.stringify({ error: error.message });
        await approvalQuery(`UPDATE approvals SET status = 'failed', result = ? WHERE plan_id = ?`, [errorJSON, plan_id]);

        // Log audit event
        await logAudit(plan_id, "plan_failed", {
          error: error.message,
          success: false
        });
      } catch {
        // Silent fail on error update
      }

      return {
        content: [{
          type: "text",
          text: JSON.stringify({
            error: "Failed to execute plan",
            plan_id,
            message: error.message
          }, null, 2)
        }],
        isError: true
      };
    }
  }
);

// ── Start server ───────────────────────────────────────────────

async function main() {
  // Initialize config and approval store
  await loadOpsConfig();
  await initApprovalStore();

  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((error) => {
  console.error("Fatal: ops MCP server failed to start:", error);
  process.exit(1);
});
