/*
 * Local Agent (MVP foundation)
 * - Tailscale-only service target
 * - Signed backend requests (HMAC)
 * - Nonce + timestamp replay protection
 * - Strict action allowlist
 * - Hermes adapter boundary
 */

const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

loadLocalEnv(path.join(__dirname, "..", ".env.local"));

const HOST = process.env.LOCAL_AGENT_HOST || "127.0.0.1";
const PORT = Number(process.env.LOCAL_AGENT_PORT || 7443);
const SHARED_SECRET = process.env.BACKEND_LOCAL_SHARED_SECRET || "";
const AGENT_LOCKDOWN = String(process.env.AGENT_LOCKDOWN || "false") === "true";

const ALLOWED_ACTIONS = new Set(
  String(process.env.AGENT_ALLOWED_ACTIONS || "hermes.health,hermes.profile.answer,hermes.calendar.book_draft,hermes.notify.template")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean)
);

const HERMES_ENDPOINT = process.env.HERMES_ENDPOINT || "";
const HERMES_API_KEY = process.env.HERMES_API_KEY || "";
const PROFILE_FILE = process.env.HERMES_PROFILE_FILE || path.resolve(__dirname, "..", "..", "..", "content", "cv.md");

const DATA_DIR = path.join(__dirname, "..", "data");
const AUDIT_LOG = path.join(DATA_DIR, "local-agent-audit.log");
const seenNonces = new Map();

ensureDir(DATA_DIR);

setInterval(() => {
  const now = Date.now();
  for (const [k, expiresAt] of seenNonces.entries()) {
    if (now > expiresAt) seenNonces.delete(k);
  }
}, 30_000).unref();

const server = http.createServer(async (req, res) => {
  try {
    if (req.url === "/health" && req.method === "GET") {
      return json(res, 200, { ok: true, service: "local-agent", lockdown: AGENT_LOCKDOWN });
    }

    if (req.url === "/execute" && req.method === "POST") {
      if (AGENT_LOCKDOWN) return json(res, 503, { error: "Local agent lockdown is enabled." });
      if (!SHARED_SECRET) return json(res, 500, { error: "Shared secret is not configured." });

      const rawBody = await readRaw(req);
      const providedSig = String(req.headers["x-assistant-signature"] || "");
      const expectedSig = sign(rawBody, SHARED_SECRET);
      if (!safeEq(providedSig, expectedSig)) {
        audit("auth.failed", { reason: "signature_mismatch" });
        return json(res, 401, { error: "Invalid signature" });
      }

      const payload = JSON.parse(rawBody || "{}");
      const action = normalizeString(payload.action);
      const ts = Number(payload.ts || 0);
      const nonce = normalizeString(payload.nonce);
      const args = payload.args || {};

      if (!action) return json(res, 400, { error: "action is required" });
      if (!ALLOWED_ACTIONS.has(action)) {
        audit("action.denied", { action, reason: "not_allowlisted" });
        return json(res, 403, { error: "Action is not allowed" });
      }

      const driftMs = Math.abs(Date.now() - ts);
      if (!ts || driftMs > 60_000) {
        audit("auth.failed", { reason: "timestamp_drift", action, driftMs });
        return json(res, 401, { error: "Expired or invalid timestamp" });
      }
      if (!nonce) return json(res, 400, { error: "nonce is required" });
      if (seenNonces.has(nonce)) {
        audit("auth.failed", { reason: "nonce_replay", action });
        return json(res, 401, { error: "Replay detected" });
      }
      seenNonces.set(nonce, Date.now() + 120_000);

      const result = await executeAction(action, args);
      audit("action.executed", { action, ok: result.ok });

      return json(res, result.ok ? 200 : 502, { result });
    }

    return json(res, 404, { error: "Not found" });
  } catch (error) {
    audit("server.error", { message: error.message });
    return json(res, 500, { error: "Internal server error" });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`[local-agent] listening on http://${HOST}:${PORT}`);
});

async function executeAction(action, args) {
  if (action === "hermes.health") {
    if (!HERMES_ENDPOINT) {
      return { ok: true, message: "Hermes endpoint not configured; running in mock mode." };
    }
    const r = await fetch(`${HERMES_ENDPOINT}/health`, {
      headers: HERMES_API_KEY ? { Authorization: `Bearer ${HERMES_API_KEY}` } : {},
    });
    if (!r.ok) return { ok: false, message: `Hermes health failed (${r.status})` };
    return { ok: true, message: "Hermes health check passed." };
  }

  if (action === "hermes.profile.answer") {
    const q = normalizeString(args.question || "").toLowerCase();
    const text = loadProfileText();
    if (!text) return { ok: false, message: "Profile source not available" };
    const snippet = extractSnippet(text, q);
    return { ok: true, message: snippet || "No matching local profile context found." };
  }

  if (action === "hermes.calendar.book_draft") {
    const when = normalizeString(args.when || "unspecified time");
    const who = normalizeString(args.who || "visitor");
    return {
      ok: true,
      message: `Local Hermes calendar draft prepared for ${who} at ${when}. Final confirmation is still required.`,
    };
  }

  if (action === "hermes.notify.template") {
    const template = normalizeString(args.template || "assistant_info");
    return { ok: true, message: `Template notification '${template}' was accepted by local agent.` };
  }

  return { ok: false, message: "Unknown action" };
}

function loadProfileText() {
  try {
    return fs.readFileSync(PROFILE_FILE, "utf8");
  } catch {
    return "";
  }
}

function extractSnippet(text, query) {
  const normalized = String(text || "").replace(/\s+/g, " ");
  if (!query) return normalized.slice(0, 400);
  const idx = normalized.toLowerCase().indexOf(query);
  if (idx === -1) return normalized.slice(0, 400);
  const start = Math.max(0, idx - 120);
  const end = Math.min(normalized.length, idx + query.length + 180);
  return normalized.slice(start, end);
}

function sign(payload, secret) {
  return crypto.createHmac("sha256", secret).update(payload).digest("hex");
}

function safeEq(a, b) {
  if (!a || !b) return false;
  const aa = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (aa.length !== bb.length) return false;
  return crypto.timingSafeEqual(aa, bb);
}

function normalizeString(v) {
  return typeof v === "string" ? v.trim() : "";
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function json(res, code, payload) {
  res.writeHead(code, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(payload));
}

async function readRaw(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8");
}

function audit(event, data) {
  const line = JSON.stringify({ ts: new Date().toISOString(), event, ...data });
  fs.appendFileSync(AUDIT_LOG, `${line}\n`, "utf8");
}

function loadLocalEnv(filePath) {
  if (!fs.existsSync(filePath)) return;
  const lines = fs.readFileSync(filePath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith("#")) continue;
    const idx = trimmed.indexOf("=");
    if (idx === -1) continue;
    const key = trimmed.slice(0, idx).trim();
    const value = trimmed.slice(idx + 1).trim();
    if (key && !(key in process.env)) process.env[key] = value;
  }
}
