/*
 * Assistant API (MVP+)
 * - Tiered permission model
 * - Intent + approval workflow for sensitive operations
 * - Signed local-agent bridge calls
 * - Intent persistence + expiration
 * - Audit logging
 */

const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const YAML = require("yaml");

loadLocalEnv(path.join(__dirname, "..", ".env.local"));

const PORT = Number(process.env.ASSISTANT_API_PORT || 8787);
const HOST = process.env.ASSISTANT_API_HOST || "0.0.0.0";
const CORS_ORIGIN = process.env.ASSISTANT_CORS_ORIGIN || "*";

const PUBLIC_RPM = Number(process.env.ASSISTANT_PUBLIC_RPM || 20);
const AUTH_RPM = Number(process.env.ASSISTANT_AUTH_RPM || 60);
const PRIV_RPM = Number(process.env.ASSISTANT_PRIV_RPM || 120);

const AUTH_USER_TOKEN = process.env.ASSISTANT_USER_TOKEN || "";
const AUTH_PRIVILEGED_TOKEN = process.env.ASSISTANT_PRIVILEGED_TOKEN || "";
const AUTH_HIGH_TRUST_TOKEN = process.env.ASSISTANT_HIGH_TRUST_TOKEN || "";

const LOCAL_TOOLS_ENABLED = String(process.env.LOCAL_TOOLS_ENABLED || "false") === "true";
const LOCAL_AGENT_URL = process.env.LOCAL_AGENT_URL || "http://127.0.0.1:7443";
const BACKEND_LOCAL_SHARED_SECRET = process.env.BACKEND_LOCAL_SHARED_SECRET || "";

const INTENT_TTL_MS = Number(process.env.ASSISTANT_INTENT_TTL_MS || 10 * 60 * 1000);

const DATA_DIR = path.join(__dirname, "..", "data");
const AUDIT_LOG_FILE = path.join(DATA_DIR, "assistant-audit.log");
const INTENT_STORE_FILE = path.join(DATA_DIR, "intents.json");

const intents = new Map();
const limiter = new Map();
const knowledge = loadKnowledge();

ensureDir(DATA_DIR);
hydrateIntents();

setInterval(() => {
  pruneExpiredIntents();
}, 30_000).unref();

const server = http.createServer(async (req, res) => {
  try {
    setCors(res);
    setSecurityHeaders(res);

    if (req.method === "OPTIONS") {
      res.writeHead(204);
      res.end();
      return;
    }

    if (req.url === "/v1/health" && req.method === "GET") {
      return json(res, 200, {
        ok: true,
        service: "assistant-api",
        localToolsEnabled: LOCAL_TOOLS_ENABLED,
      });
    }

    if (req.url === "/v1/chat" && req.method === "POST") {
      const tier = authTier(req);
      const rate = checkRate(req, tier);
      if (!rate.ok) return json(res, 429, { error: rate.error });

      const body = await readJson(req);
      if (!body.message || typeof body.message !== "string") {
        return json(res, 400, { error: "message is required" });
      }

      const sessionId = normalizeString(body.sessionId) || randomId("session");
      const message = body.message.trim();

      const result = await processMessage({ message, tier, sessionId });
      audit("chat.request", {
        tier,
        sessionId,
        messageHash: sha(message),
        requiresApproval: result.requiresApproval,
        intentId: result.intentId || null,
      });

      return json(res, 200, {
        sessionId,
        tier,
        ...result,
      });
    }

    if (req.url === "/v1/approve" && req.method === "POST") {
      const tier = authTier(req);
      if (!isPrivilegedTier(tier)) return json(res, 403, { error: "privileged tier required" });

      const body = await readJson(req);
      const intentId = normalizeString(body.intentId);
      const approved = Boolean(body.approved);

      if (!intentId) return json(res, 400, { error: "intentId is required" });
      const intent = intents.get(intentId);
      if (!intent) return json(res, 404, { error: "intent not found" });

      if (intent.status !== "pending") {
        return json(res, 409, { error: `intent is ${intent.status}` });
      }

      if (Date.now() > intent.expiresAt) {
        intent.status = "expired";
        intent.updatedAt = Date.now();
        persistIntents();
        return json(res, 410, { error: "intent expired" });
      }

      if (!approved) {
        intent.status = "rejected";
        intent.updatedAt = Date.now();
        persistIntents();
        audit("intent.rejected", { intentId, action: intent.action, tier });
        return json(res, 200, { ok: true, result: { message: "Action rejected." } });
      }

      const exec = await executeIntent(intent, tier);
      intent.status = exec.ok ? "executed" : "failed";
      intent.updatedAt = Date.now();
      intent.result = exec;
      persistIntents();

      audit("intent.executed", {
        intentId,
        action: intent.action,
        tier,
        ok: exec.ok,
      });

      return json(res, exec.ok ? 200 : 502, { ok: exec.ok, result: exec });
    }

    if (req.url.startsWith("/v1/intents/") && req.method === "GET") {
      const tier = authTier(req);
      if (tier === "public") return json(res, 403, { error: "authenticated tier required" });

      const intentId = req.url.replace("/v1/intents/", "").trim();
      const intent = intents.get(intentId);
      if (!intent) return json(res, 404, { error: "intent not found" });

      return json(res, 200, {
        id: intent.id,
        type: intent.type,
        action: intent.action,
        status: intent.status,
        createdAt: intent.createdAt,
        updatedAt: intent.updatedAt,
        expiresAt: intent.expiresAt,
      });
    }

    if (req.url === "/v1/audit" && req.method === "GET") {
      const tier = authTier(req);
      if (tier !== "high_trust") return json(res, 403, { error: "high trust token required" });
      return json(res, 200, { lines: readRecentAuditLines(100) });
    }

    return json(res, 404, { error: "Not found" });
  } catch (error) {
    audit("server.error", { message: error.message });
    return json(res, 500, { error: "Internal server error" });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`[assistant-api] listening on http://${HOST}:${PORT}`);
});

async function processMessage({ message, tier, sessionId }) {
  if (isBookingIntent(message)) {
    if (tier === "public") {
      return {
        reply:
          "I can help with appointment booking, but final booking requires authenticated and privileged approval.",
        requiresApproval: false,
        intentId: null,
      };
    }

    const booking = parseBookingRequest(message);
    const intent = createIntent({
      type: "booking",
      action: "hermes.calendar.book_draft",
      tierRequired: "privileged",
      sessionId,
      args: booking,
    });

    return {
      reply:
        "I prepared a booking draft action. Please approve to execute. No appointment is finalized without explicit confirmation.",
      requiresApproval: true,
      intentId: intent.id,
    };
  }

  if (isNotificationIntent(message)) {
    if (tier === "public") {
      return {
        reply: "Notifications require privileged mode and explicit approval.",
        requiresApproval: false,
        intentId: null,
      };
    }

    const intent = createIntent({
      type: "notification",
      action: "hermes.notify.template",
      tierRequired: "privileged",
      sessionId,
      args: { template: "assistant_info", message },
    });

    return {
      reply: "I prepared a notification action. Please approve to execute.",
      requiresApproval: true,
      intentId: intent.id,
    };
  }

  if (isLocalProfileIntent(message)) {
    if (!isPrivilegedTier(tier)) {
      return {
        reply:
          "Local Hermes profile answering is restricted. Use privileged mode and explicit approval for local actions.",
        requiresApproval: false,
        intentId: null,
      };
    }

    const intent = createIntent({
      type: "local_profile",
      action: "hermes.profile.answer",
      tierRequired: "privileged",
      sessionId,
      args: { question: message },
    });

    return {
      reply: "I prepared a local Hermes profile query. Please approve to execute.",
      requiresApproval: true,
      intentId: intent.id,
    };
  }

  if (LOCAL_TOOLS_ENABLED && BACKEND_LOCAL_SHARED_SECRET) {
    const hermesRead = await callLocalAgent("hermes.profile.answer", { question: message });
    if (hermesRead.ok && hermesRead.message) {
      return {
        reply: hermesRead.message,
        requiresApproval: false,
        intentId: null,
      };
    }
  }

  return {
    reply: answerFromKnowledge(message),
    requiresApproval: false,
    intentId: null,
  };
}

async function executeIntent(intent, tier) {
  if (intent.tierRequired === "privileged" && !isPrivilegedTier(tier)) {
    return { ok: false, message: "Insufficient tier" };
  }

  if (!intent.action.startsWith("hermes.")) {
    return { ok: false, message: "Unsupported action" };
  }

  if (!LOCAL_TOOLS_ENABLED) {
    return { ok: false, message: "Local tools are disabled by kill switch." };
  }
  if (!BACKEND_LOCAL_SHARED_SECRET) {
    return { ok: false, message: "Local bridge secret is not configured." };
  }
  return callLocalAgent(intent.action, intent.args || {});
}

async function callLocalAgent(action, args) {
  const payload = {
    action,
    args,
    ts: Date.now(),
    nonce: randomId("nonce"),
  };
  const body = JSON.stringify(payload);
  const signature = crypto.createHmac("sha256", BACKEND_LOCAL_SHARED_SECRET).update(body).digest("hex");

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 8_000);
  try {
    const res = await fetch(`${LOCAL_AGENT_URL}/execute`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-assistant-signature": signature,
      },
      body,
      signal: controller.signal,
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      return { ok: false, message: data.error || `Local agent error (${res.status})` };
    }
    return {
      ok: true,
      message: data?.result?.message || "Local action completed.",
      local: data?.result || null,
    };
  } catch (error) {
    return { ok: false, message: `Local bridge request failed: ${error.message}` };
  } finally {
    clearTimeout(timeout);
  }
}

function createIntent({ type, action, tierRequired, sessionId, args }) {
  const now = Date.now();
  const intent = {
    id: randomId("intent"),
    type,
    action,
    tierRequired,
    sessionId,
    status: "pending",
    args,
    createdAt: now,
    updatedAt: now,
    expiresAt: now + INTENT_TTL_MS,
  };
  intents.set(intent.id, intent);
  persistIntents();
  return intent;
}

function pruneExpiredIntents() {
  const now = Date.now();
  let dirty = false;
  for (const intent of intents.values()) {
    if (intent.status === "pending" && now > intent.expiresAt) {
      intent.status = "expired";
      intent.updatedAt = now;
      dirty = true;
      audit("intent.expired", { intentId: intent.id, action: intent.action });
    }
  }
  if (dirty) persistIntents();
}

function persistIntents() {
  const list = Array.from(intents.values()).slice(-500);
  fs.writeFileSync(INTENT_STORE_FILE, JSON.stringify(list, null, 2), "utf8");
}

function hydrateIntents() {
  if (!fs.existsSync(INTENT_STORE_FILE)) return;
  try {
    const list = JSON.parse(fs.readFileSync(INTENT_STORE_FILE, "utf8"));
    if (!Array.isArray(list)) return;
    for (const item of list) {
      if (!item?.id) continue;
      intents.set(item.id, item);
    }
  } catch {
    // ignore corrupt state and continue
  }
}

function answerFromKnowledge(message) {
  const q = message.toLowerCase();
  const snippets = [];

  if (q.includes("project") && knowledge.projects.length) {
    snippets.push(`Projects: ${knowledge.projects.slice(0, 4).join("; ")}.`);
  }
  if ((q.includes("about") || q.includes("who") || q.includes("kousha")) && knowledge.about) {
    snippets.push(knowledge.about);
  }
  if (q.includes("contact") && knowledge.contact) {
    snippets.push(`Contact: ${knowledge.contact}`);
  }
  if ((q.includes("cv") || q.includes("resume") || q.includes("experience")) && knowledge.cvSummary) {
    snippets.push(`CV summary: ${knowledge.cvSummary}`);
  }

  if (!snippets.length) {
    return "I can answer questions about Kousha based on website and CV context, help prepare appointment requests, and run approved limited actions.";
  }
  return snippets.join(" ");
}

function loadKnowledge() {
  const root = path.resolve(__dirname, "..", "..", "..");
  const sitePath = path.join(root, "content", "site.yaml");
  const cvPath = path.join(root, "content", "cv.md");

  let site = {};
  let cvRaw = "";
  try {
    site = YAML.parse(fs.readFileSync(sitePath, "utf8")) || {};
  } catch {
    site = {};
  }
  try {
    cvRaw = fs.readFileSync(cvPath, "utf8");
  } catch {
    cvRaw = "";
  }

  const pages = Array.isArray(site.pages) ? site.pages : [];
  const projects =
    pages
      .find((p) => p && p.key === "projects")
      ?.blocks?.filter((b) => b?.type === "project")
      ?.map((b) => `${b.title || "Untitled"}${b.link ? ` (${b.link})` : ""}`) || [];

  const about =
    pages
      .find((p) => p && p.key === "home")
      ?.blocks?.find((b) => b?.type === "about")
      ?.lines?.join(" ") || "";

  const contact =
    pages
      .find((p) => p && p.key === "contact")
      ?.blocks?.find((b) => b?.type === "contact")
      ?.items?.map((i) => `${i.label}: ${i.value}`)
      ?.join(" | ") || "";

  return {
    projects,
    about,
    contact,
    cvSummary: cvRaw.replace(/\s+/g, " ").trim().slice(0, 550),
  };
}

function authTier(req) {
  const header = req.headers.authorization || "";
  const token = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (AUTH_HIGH_TRUST_TOKEN && token === AUTH_HIGH_TRUST_TOKEN) return "high_trust";
  if (AUTH_PRIVILEGED_TOKEN && token === AUTH_PRIVILEGED_TOKEN) return "privileged";
  if (AUTH_USER_TOKEN && token === AUTH_USER_TOKEN) return "authenticated";
  return "public";
}

function isPrivilegedTier(tier) {
  return tier === "privileged" || tier === "high_trust";
}

function checkRate(req, tier) {
  const key = `${clientIp(req)}:${tier}`;
  const now = Date.now();
  const windowMs = 60_000;
  const limit = tier === "public" ? PUBLIC_RPM : tier === "authenticated" ? AUTH_RPM : PRIV_RPM;

  const state = limiter.get(key) || { started: now, count: 0 };
  if (now - state.started > windowMs) {
    state.started = now;
    state.count = 0;
  }
  state.count += 1;
  limiter.set(key, state);

  if (state.count > limit) return { ok: false, error: "Too many requests" };
  return { ok: true };
}

function setCors(res) {
  res.setHeader("Access-Control-Allow-Origin", CORS_ORIGIN);
  if (CORS_ORIGIN !== "*") {
    res.setHeader("Access-Control-Allow-Credentials", "true");
  }
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization");
}

function setSecurityHeaders(res) {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("X-Content-Type-Options", "nosniff");
}

function json(res, code, payload) {
  res.writeHead(code, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(payload));
}

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const raw = Buffer.concat(chunks).toString("utf8") || "{}";
  try {
    return JSON.parse(raw);
  } catch {
    throw new Error("Invalid JSON payload");
  }
}

function isBookingIntent(text) {
  const t = text.toLowerCase();
  return ["book", "appointment", "meeting", "schedule"].some((k) => t.includes(k));
}

function isNotificationIntent(text) {
  const t = text.toLowerCase();
  return ["notify", "inform", "remind"].some((k) => t.includes(k));
}

function isLocalProfileIntent(text) {
  const t = text.toLowerCase();
  return t.includes("hermes") || t.includes("local profile") || t.includes("local cv");
}

function parseBookingRequest(message) {
  const text = normalizeString(message);
  const timeHintMatch = text.match(/\b(today|tomorrow|next\s+week|monday|tuesday|wednesday|thursday|friday|saturday|sunday|\d{1,2}(:\d{2})?\s?(am|pm)?)\b/i);
  return {
    requestText: text,
    when: normalizeString(timeHintMatch?.[0] || "to be confirmed"),
    who: "visitor",
  };
}

function randomId(prefix) {
  return `${prefix}_${crypto.randomBytes(8).toString("hex")}`;
}

function normalizeString(v) {
  return typeof v === "string" ? v.trim() : "";
}

function clientIp(req) {
  const xff = req.headers["x-forwarded-for"];
  if (typeof xff === "string") return xff.split(",")[0].trim();
  return req.socket.remoteAddress || "unknown";
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
}

function audit(event, data) {
  const line = JSON.stringify({ ts: new Date().toISOString(), event, ...data });
  fs.appendFileSync(AUDIT_LOG_FILE, `${line}\n`, "utf8");
}

function readRecentAuditLines(limit = 100) {
  if (!fs.existsSync(AUDIT_LOG_FILE)) return [];
  const raw = fs.readFileSync(AUDIT_LOG_FILE, "utf8").trim();
  if (!raw) return [];
  const lines = raw.split("\n").filter(Boolean);
  return lines.slice(Math.max(0, lines.length - limit));
}

function sha(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex");
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
