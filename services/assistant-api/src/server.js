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
const SESSION_TTL_MS = Number(process.env.ASSISTANT_SESSION_TTL_MS || 30 * 60 * 1000);

const DATA_DIR = path.join(__dirname, "..", "data");
const AUDIT_LOG_FILE = path.join(DATA_DIR, "assistant-audit.log");
const INTENT_STORE_FILE = path.join(DATA_DIR, "intents.json");

const intents = new Map();
const limiter = new Map();
const sessionContext = new Map();
const knowledge = loadKnowledge();

ensureDir(DATA_DIR);
hydrateIntents();

setInterval(() => {
  pruneExpiredIntents();
  pruneSessionContext();
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

      const rawResult = await processMessage({ message, tier, sessionId });
      const result = normalizeChatResult(rawResult, message);
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
  const normalizedMessage = normalizeString(message);

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

  if (LOCAL_TOOLS_ENABLED && BACKEND_LOCAL_SHARED_SECRET && shouldUseLocalProfileRead(normalizedMessage)) {
    const hermesRead = await callLocalAgent("hermes.profile.answer", { question: normalizedMessage });
    if (hermesRead.ok && hermesRead.message && !isLowSignalLocalResponse(hermesRead.message)) {
      setSessionTopic(sessionId, "experience");
      return {
        reply: hermesRead.message,
        requiresApproval: false,
        intentId: null,
      };
    }
  }

  return {
    reply: answerFromKnowledge(normalizedMessage, sessionId),
    requiresApproval: false,
    intentId: null,
  };
}

function normalizeChatResult(result, userMessage) {
  const safeResult = result && typeof result === "object" ? { ...result } : {};
  const rawReply = normalizeString(safeResult.reply);
  const cleanedReply = sanitizeAssistantReply(rawReply);

  if (cleanedReply) {
    safeResult.reply = cleanedReply;
    return safeResult;
  }

  if (isGreetingMessage(userMessage)) {
    safeResult.reply =
      "Hey — nice to meet you. I can help with Kousha's background, project highlights, and contact details.";
    return safeResult;
  }

  safeResult.reply =
    "I can help with Kousha's background, projects, and contact details. Ask me something specific and I’ll keep it concise.";
  return safeResult;
}

function sanitizeAssistantReply(text) {
  let out = String(text || "").trim();
  if (!out) return "";

  if (isProfileMetadataDump(out)) {
    return "Hey — nice to meet you. Ask me about Kousha’s background, projects, or contact details and I’ll answer naturally.";
  }

  out = out
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/^#{1,6}\s+/gm, "")
    .replace(/\s#{1,6}\s+/g, " ")
    .replace(/#{1,6}\s+/g, "")
    .replace(/\*\*/g, "")
    .replace(/\s*[-*]\s+/g, " ")
    .replace(/\bthis file is a local, assistant-readable cv context source for the assistant mvp\.?/gi, "")
    .replace(/\bpublic context usage\b/gi, "")
    .replace(/\bfocus areas\b/gi, "")
    .replace(/\bprofessional summary\b/gi, "")
    .replace(/\bprofile summary\b/gi, "")
    .replace(/\bkousha\s+ghodsizad\s+[—-]\s*/gi, "Kousha ")
    .replace(/\bkousha\s+madani\b/gi, "Kousha")
    .replace(/\bKousha\s+Kousha\s+is\b/gi, "Kousha is")
    .replace(/\bcv summary\b/gi, "")
    .replace(/\s+/g, " ")
    .trim();

  // Final guard if boilerplate still dominates.
  if (isProfileMetadataDump(out) || out.length < 2) {
    return "I can help with Kousha’s background, projects, or contact details. What would you like to know?";
  }

  return out;
}

function isProfileMetadataDump(text) {
  const t = String(text || "").toLowerCase();
  if (!t) return false;

  return (
    /kousha\s+madani\s+[-—]?\s*cv\s*summary/.test(t) ||
    t.includes("assistant-readable cv context") ||
    t.includes("assistant mvp") ||
    t.includes("public context usage")
  );
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

function answerFromKnowledge(message, sessionId) {
  const q = String(message || "").toLowerCase();
  const tokens = tokenizeQuery(q);
  const previous = sessionId ? sessionContext.get(sessionId) : null;

  if (isGreetingMessage(q)) {
    setSessionTopic(sessionId, "greeting");
    const projectHint = knowledge.projects.length
      ? `A good start is: \"What projects has Kousha built recently?\"`
      : `You can ask about background, experience, contact details, or projects.`;
    return `Hey — nice to meet you. I can help with Kousha's background, projects, experience highlights, and contact details. ${projectHint}`;
  }

  if (isThanksMessage(q)) {
    return "You're welcome — if you'd like, I can also summarize experience, top projects, or the best way to reach out.";
  }

  const topic = detectPrimaryTopic(q, tokens);
  const parts = [];

  if (topic === "projects") {
    const relevant = relevantProjects(tokens);
    if (relevant.length) {
      parts.push(`Here are relevant projects: ${relevant.join("; ")}.`);
    } else if (knowledge.projects.length) {
      parts.push(`Top projects: ${knowledge.projects.slice(0, 3).join("; ")}.`);
    } else if (knowledge.cvSummary) {
      const cv = selectCvHighlights(tokens, 2);
      if (cv.length) parts.push(`I do not have structured project cards loaded right now, but from CV context: ${cv.join(" ")}`);
    }
  }

  if (topic === "about") {
    if (knowledge.about) {
      parts.push(knowledge.about);
    } else if (knowledge.cvSummary) {
      const cv = selectCvHighlights(tokens, 1);
      if (cv.length) parts.push(cv[0]);
    }
  }

  if (topic === "contact") {
    if (knowledge.contact) {
      parts.push(`Best contact routes: ${knowledge.contact}.`);
    } else {
      parts.push("I don't have direct contact fields loaded in this context, but the Contact page is the best route to reach Kousha.");
    }
  }

  if (topic === "experience" && knowledge.cvSummary) {
    const cv = selectCvHighlights(tokens, 2);
    if (cv.length) {
      parts.push(`Experience highlights: ${cv.join(" ")}`);
    }
  }

  if (!parts.length) {
    const lead =
      previous?.topic && previous.topic !== "general"
        ? `If you want, we can continue on ${previous.topic}.`
        : "I can help with concrete details about Kousha.";
    setSessionTopic(sessionId, "general");
    return `${lead} Try one of these: \"What is Kousha's background?\", \"Show project highlights\", or \"How can I contact him?\"`;
  }

  setSessionTopic(sessionId, topic);
  const followUp =
    topic === "projects"
      ? "If you want, I can narrow this down by stack, domain, or business impact."
      : topic === "experience"
        ? "I can also tailor this into a short bio, interview answer, or project-focused summary."
        : topic === "contact"
          ? "If you share your goal, I can suggest the best outreach message."
          : "Let me know if you want this summarized in a shorter form.";

  return `${parts.join(" ")} ${followUp}`;
}

function detectPrimaryTopic(query, tokens) {
  const weights = {
    projects: scoreTopic(query, tokens, ["project", "portfolio", "case study", "build", "built", "product", "app", "apps"]),
    about: scoreTopic(query, tokens, ["about", "who", "bio", "introduction", "intro", "kousha"]),
    contact: scoreTopic(query, tokens, ["contact", "email", "reach", "hire", "linkedin", "github", "phone"]),
    experience: scoreTopic(query, tokens, ["cv", "resume", "experience", "background", "career", "skills", "skill", "work"]),
  };

  const top = Object.entries(weights).sort((a, b) => b[1] - a[1])[0];
  if (!top || top[1] <= 0) return "general";
  return top[0];
}

function scoreTopic(query, tokens, keywords) {
  let score = 0;
  for (const kw of keywords) {
    if (query.includes(kw)) score += 2;
    if (tokens.includes(kw)) score += 1;
  }
  return score;
}

function tokenizeQuery(text) {
  const stop = new Set([
    "the",
    "a",
    "an",
    "and",
    "or",
    "to",
    "of",
    "for",
    "about",
    "is",
    "are",
    "do",
    "does",
    "can",
    "you",
    "me",
    "i",
    "we",
    "on",
    "in",
    "with",
    "what",
    "who",
    "how",
    "hi",
    "hello",
    "hey",
  ]);

  return String(text || "")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .map((t) => t.trim())
    .filter((t) => t && !stop.has(t));
}

function relevantProjects(tokens) {
  if (!knowledge.projects.length) return [];
  if (!tokens.length) return knowledge.projects.slice(0, 3);

  const ranked = knowledge.projects
    .map((project) => {
      const p = project.toLowerCase();
      let score = 0;
      for (const token of tokens) {
        if (token.length < 3) continue;
        if (p.includes(token)) score += 1;
      }
      return { project, score };
    })
    .sort((a, b) => b.score - a.score);

  const best = ranked.filter((item) => item.score > 0).slice(0, 3).map((item) => item.project);
  return best.length ? best : knowledge.projects.slice(0, 3);
}

function selectCvHighlights(tokens, max = 2) {
  const text = String(knowledge.cvSummary || "").trim();
  if (!text) return [];

  const sentences = text
    .split(/(?<=[.!?])\s+/)
    .map((s) => s.trim())
    .filter(Boolean);

  if (!sentences.length) return [text.slice(0, 260)];
  if (!tokens.length) return sentences.slice(0, max);

  const ranked = sentences
    .map((sentence) => {
      const lowered = sentence.toLowerCase();
      let score = 0;
      for (const token of tokens) {
        if (token.length < 3) continue;
        if (lowered.includes(token)) score += 1;
      }
      return { sentence, score };
    })
    .sort((a, b) => b.score - a.score);

  const best = ranked.filter((row) => row.score > 0).slice(0, max).map((row) => row.sentence);
  return best.length ? best : sentences.slice(0, max);
}

function shouldUseLocalProfileRead(message) {
  const q = String(message || "").toLowerCase();
  if (!q) return false;
  if (isGreetingMessage(q) || isThanksMessage(q)) return false;
  return [
    "cv",
    "resume",
    "experience",
    "background",
    "bio",
    "skills",
    "career",
    "education",
    "certification",
    "kousha",
  ].some((kw) => q.includes(kw));
}

function isLowSignalLocalResponse(message) {
  const text = String(message || "").trim().toLowerCase();
  if (!text) return true;
  if (text.includes("no matching local profile context found")) return true;
  if (text.length < 40) return true;
  return false;
}

function isGreetingMessage(text) {
  const q = String(text || "").toLowerCase().trim();
  if (!q) return false;
  return ["hi", "hello", "hey", "yo", "good morning", "good afternoon", "good evening"].some((g) =>
    q === g || q.startsWith(`${g} `)
  );
}

function isThanksMessage(text) {
  const q = String(text || "").toLowerCase();
  return q.includes("thanks") || q.includes("thank you");
}

function setSessionTopic(sessionId, topic) {
  const id = normalizeString(sessionId);
  if (!id) return;
  sessionContext.set(id, {
    topic: normalizeString(topic) || "general",
    updatedAt: Date.now(),
  });
}

function pruneSessionContext() {
  const now = Date.now();
  for (const [id, state] of sessionContext.entries()) {
    if (!state?.updatedAt || now - state.updatedAt > SESSION_TTL_MS) {
      sessionContext.delete(id);
    }
  }
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
  const projectsPage = pages.find((p) => p && p.key === "projects") || {};
  const homePage = pages.find((p) => p && p.key === "home") || {};
  const contactPage = pages.find((p) => p && p.key === "contact") || {};

  const legacyProjects =
    projectsPage?.blocks
      ?.filter((b) => b?.type === "project")
      ?.map((b) => `${b.title || "Untitled"}${b.link ? ` (${b.link})` : ""}`) || [];

  const structuredProjects =
    projectsPage?.content?.sections
      ?.flatMap((section) =>
        (section?.items || []).map((item) => {
          const title = normalizeString(item?.title) || "Untitled";
          const info = normalizeString(item?.info);
          const href = normalizeString(item?.href);
          const infoSuffix = info ? ` — ${info}` : "";
          const hrefSuffix = href ? ` (${href})` : "";
          return `${title}${infoSuffix}${hrefSuffix}`;
        })
      )
      ?.filter(Boolean) || [];

  const projects = structuredProjects.length ? structuredProjects : legacyProjects;

  const legacyAbout =
    homePage?.blocks?.find((b) => b?.type === "about")?.lines?.join(" ") || "";

  const structuredAbout =
    (homePage?.content?.about_spans || [])
      .map((line) => normalizeString(line))
      .filter(Boolean)
      .join(" ");

  const about = structuredAbout || legacyAbout;

  const legacyContact =
    contactPage?.blocks
      ?.find((b) => b?.type === "contact")
      ?.items?.map((i) => `${i.label}: ${i.value}`)
      ?.join(" | ") || "";

  const structuredContact =
    contactPage?.content?.contacts
      ?.map((i) => `${normalizeString(i?.label)}: ${normalizeString(i?.href)}`)
      ?.filter((line) => !line.startsWith(":"))
      ?.join(" | ") || "";

  const contact = structuredContact || legacyContact;

  return {
    projects,
    about,
    contact,
    cvSummary: extractProfessionalSummary(cvRaw) || stripMarkdownToText(cvRaw).slice(0, 550),
  };
}

function extractProfessionalSummary(raw) {
  const lines = String(raw || "").split(/\r?\n/);
  let inSummary = false;
  const collected = [];

  for (const line of lines) {
    const trimmed = line.trim();
    if (/^##\s+professional\s+summary\s*$/i.test(trimmed)) {
      inSummary = true;
      continue;
    }

    if (inSummary && /^##\s+/.test(trimmed)) break;
    if (!inSummary) continue;
    if (!trimmed) continue;
    collected.push(trimmed.replace(/^[-*]\s+/, ""));
  }

  return collected.join(" ").replace(/\s+/g, " ").trim();
}

function stripMarkdownToText(raw) {
  return String(raw || "")
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/^#{1,6}\s+/gm, "")
    .replace(/^\s*[-*]\s+/gm, "")
    .replace(/\*\*/g, "")
    .replace(/\s+/g, " ")
    .trim();
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
