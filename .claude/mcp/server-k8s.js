#!/usr/bin/env node

/**
 * Factory MCP Server — Kubernetes Multi-Cluster
 *
 * Provides read-only kubectl tools against any cluster whose kubeconfig
 * lives under KUBECONFIG_DIR (default: .../Atlantis/kube-config).
 *
 * Tools:
 *   k8s_list_clusters  → List available clusters and their server URLs
 *   k8s_get            → kubectl get / describe for any resource type
 *   k8s_logs           → kubectl logs for a specific pod
 *
 * Security model:
 *   - execFile only, never exec/shell — no injection possible
 *   - Always passes --kubeconfig <file> (never inherits ambient KUBECONFIG)
 *   - Only read-only subcommands exposed (get, describe, logs)
 *   - Output redacted before returning
 *   - Cluster names validated against discovered file list
 */

import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { readdirSync, existsSync } from "node:fs";
import { resolve } from "node:path";
import { loadClaudeEnv } from "./lib/env-loader.js";
import { execSafe, makeTextResponse, makeErrorResponse } from "./lib/index.js";

loadClaudeEnv();

// ── Config ─────────────────────────────────────────────────────

const DEFAULT_KUBECONFIG_DIR =
  "/Users/kousha/Sites/IRavenIO/Infrastructures/Atlantis/kube-config";

const KUBECONFIG_DIR =
  process.env.KUBECONFIG_DIR || DEFAULT_KUBECONFIG_DIR;

const KUBECTL_TIMEOUT_MS = 15_000;

// ── Cluster Discovery ──────────────────────────────────────────

/**
 * Scan KUBECONFIG_DIR and return a map of { clusterName → filePath }.
 * Uses `kubectl config view` to extract the canonical cluster name.
 */
async function discoverClusters() {
  if (!existsSync(KUBECONFIG_DIR)) {
    return {};
  }

  let files;
  try {
    files = readdirSync(KUBECONFIG_DIR).filter(
      (f) => f.endsWith("-config") || f.endsWith(".yaml") || f.endsWith(".yml")
    );
  } catch {
    return {};
  }

  const clusters = {};
  for (const file of files) {
    const filePath = resolve(KUBECONFIG_DIR, file);
    const result = await execSafe(
      "kubectl",
      ["config", "view", "--kubeconfig", filePath, "--output=jsonpath={range .clusters[*]}{.name}={.cluster.server}{\"\\n\"}{end}"],
      { timeout: 5_000 }
    );
    if (!result.success) continue;

    for (const line of result.stdout.split("\n")) {
      const [name, server] = line.split("=", 2);
      if (name && name.trim()) {
        clusters[name.trim()] = { file: filePath, server: server?.trim() || "" };
      }
    }
  }
  return clusters;
}

/**
 * Resolve a cluster name to its kubeconfig file path.
 * Returns null if not found.
 */
async function resolveCluster(clusterName) {
  const clusters = await discoverClusters();
  return clusters[clusterName] || null;
}

// ── Redaction ──────────────────────────────────────────────────

function redactOutput(text) {
  if (!text) return text;
  let out = text;

  // Connection strings
  for (const proto of ["postgres", "postgresql", "mysql", "mongodb", "redis"]) {
    out = out.replace(
      new RegExp(`${proto}://[^\\s@]*:[^\\s@]*@[^\\s]*`, "g"),
      `${proto}://***REDACTED***`
    );
  }

  // Token patterns
  out = out.replace(
    /sk-ant-api[0-9]+-[A-Za-z0-9_-]{95,}|eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+|AKIA[0-9A-Z]{16}|github_pat_[0-9a-zA-Z_]{70,}|ghp_[0-9a-zA-Z]{36}/g,
    "***REDACTED***"
  );

  // JSON secret fields
  for (const key of ["password", "secret", "token", "api_key", "apiKey", "private_key"]) {
    out = out.replace(
      new RegExp(`"${key}"\\s*:\\s*"[^"]+"`, "gi"),
      `"${key}": "***REDACTED***"`
    );
  }

  return out;
}

// ── MCP Server ─────────────────────────────────────────────────

const server = new McpServer({
  name: "factory-k8s",
  version: "1.0.0",
});

// ── Tool 1: k8s_list_clusters ──────────────────────────────────

server.tool(
  "k8s_list_clusters",
  "List all available Kubernetes clusters from the kubeconfig directory. Returns cluster names, server URLs, and kubeconfig file paths. Use this first to know which cluster names to pass to other k8s tools.",
  {},
  async () => {
    const checkResult = await execSafe("kubectl", ["version", "--client", "--output=json"], { timeout: 5_000 });
    if (!checkResult.success) {
      return makeErrorResponse("kubectl not found. Install with: brew install kubectl");
    }

    const clusters = await discoverClusters();
    const clusterList = Object.entries(clusters).map(([name, info]) => ({
      name,
      server: info.server,
      kubeconfig: info.file,
    }));

    if (clusterList.length === 0) {
      return makeTextResponse(JSON.stringify({
        available: false,
        reason: `No kubeconfig files found in ${KUBECONFIG_DIR}`,
        kubeconfig_dir: KUBECONFIG_DIR,
      }, null, 2));
    }

    return makeTextResponse(JSON.stringify({
      available: true,
      kubeconfig_dir: KUBECONFIG_DIR,
      clusters: clusterList,
      hint: "Pass the cluster 'name' to k8s_get or k8s_logs",
    }, null, 2));
  }
);

// ── Tool 2: k8s_get ────────────────────────────────────────────

server.tool(
  "k8s_get",
  "Run kubectl get or kubectl describe for any resource type on a specific cluster. Specify cluster by name (from k8s_list_clusters). Examples: get pods in all namespaces, describe a specific deployment, list nodes.",
  {
    cluster: z.string().describe("Cluster name, e.g. k3s-master, k3s-ha00, k3s-ha01, k3s-pi"),
    verb: z.enum(["get", "describe"]).default("get").describe("kubectl verb: 'get' returns structured data, 'describe' returns human-readable details"),
    resource: z.string().describe("Resource type: pods, deployments, services, nodes, namespaces, configmaps, ingresses, events, daemonsets, statefulsets, persistentvolumes, persistentvolumeclaims, replicasets, jobs, cronjobs"),
    name: z.string().optional().describe("Specific resource name (optional — omit to list all)"),
    namespace: z.string().optional().describe("Namespace. Omit or pass empty string to query all namespaces (-A)"),
    output: z.enum(["json", "yaml", "wide", "name"]).default("json").describe("Output format (only applies to 'get' verb)"),
    selector: z.string().optional().describe("Label selector, e.g. app=nginx"),
  },
  async ({ cluster, verb, resource, name, namespace, output, selector }) => {
    const info = await resolveCluster(cluster);
    if (!info) {
      const clusters = await discoverClusters();
      return makeErrorResponse(
        `Unknown cluster "${cluster}". Available: ${Object.keys(clusters).join(", ") || "(none found)"}`
      );
    }

    // Build args
    const args = ["--kubeconfig", info.file, verb, resource];

    if (name) {
      args.push(name);
    }

    if (namespace && namespace.trim()) {
      args.push("--namespace", namespace.trim());
    } else {
      args.push("--all-namespaces");
    }

    if (verb === "get") {
      args.push(`--output=${output}`);
    }

    if (selector) {
      args.push("--selector", selector);
    }

    const result = await execSafe("kubectl", args, { timeout: KUBECTL_TIMEOUT_MS });

    if (!result.success) {
      return makeErrorResponse(`kubectl ${verb} failed: ${result.message}`);
    }

    let parsed;
    if (verb === "get" && output === "json") {
      try {
        parsed = JSON.parse(result.stdout);
      } catch {
        parsed = result.stdout;
      }
    } else {
      parsed = result.stdout;
    }

    const response = {
      cluster,
      server: info.server,
      verb,
      resource,
      namespace: namespace || "all",
      result: parsed,
    };

    return makeTextResponse(redactOutput(
      typeof parsed === "string"
        ? result.stdout
        : JSON.stringify(response, null, 2)
    ));
  }
);

// ── Tool 3: k8s_logs ──────────────────────────────────────────

server.tool(
  "k8s_logs",
  "Get logs from a pod on a specific cluster. Supports tail limit, container selection, and previous container logs.",
  {
    cluster: z.string().describe("Cluster name, e.g. k3s-master, k3s-ha00"),
    pod: z.string().describe("Pod name"),
    namespace: z.string().describe("Namespace the pod is in"),
    container: z.string().optional().describe("Container name (optional — needed if pod has multiple containers)"),
    tail: z.number().int().min(1).max(1000).default(100).describe("Number of recent log lines to return (default 100, max 1000)"),
    previous: z.boolean().default(false).describe("Return logs from the previous (crashed) container instance"),
  },
  async ({ cluster, pod, namespace, container, tail, previous }) => {
    const info = await resolveCluster(cluster);
    if (!info) {
      const clusters = await discoverClusters();
      return makeErrorResponse(
        `Unknown cluster "${cluster}". Available: ${Object.keys(clusters).join(", ") || "(none found)"}`
      );
    }

    const args = [
      "--kubeconfig", info.file,
      "logs", pod,
      "--namespace", namespace,
      `--tail=${tail}`,
    ];

    if (container) args.push("--container", container);
    if (previous) args.push("--previous");

    const result = await execSafe("kubectl", args, { timeout: KUBECTL_TIMEOUT_MS });

    if (!result.success) {
      return makeErrorResponse(`kubectl logs failed: ${result.message}`);
    }

    return makeTextResponse(redactOutput(result.stdout));
  }
);

// ── Start ──────────────────────────────────────────────────────

const transport = new StdioServerTransport();
await server.connect(transport);
