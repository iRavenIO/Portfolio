/*
 * Portfolio Content Admin API (local MVP)
 * - Token-protected local browser editor for content/site.yaml
 * - Schema validation before writes
 * - Atomic file saves with timestamped backups
 * - No commit, tag, push, deploy, shell execution, or arbitrary file writes
 */

// Must be first so Sentry can install global error hooks before any other
// require runs and before the HTTP server is constructed. No-ops if
// SENTRY_DSN is unset.
require("./instrument");

const http = require("http");
const fs = require("fs");
const path = require("path");
const crypto = require("crypto");
const { execFileSync } = require("child_process");
const { validateSiteYaml } = require("./contentValidation");
const {
  createPool,
  hasMysqlConfig,
  loadSiteYamlFromDb,
  saveSiteYamlToDb,
} = require("./mysqlStore");

loadLocalEnv(path.join(__dirname, "..", ".env.local"));

const REPO_ROOT = path.resolve(__dirname, "..", "..", "..");
const CONTENT_PATH = path.join(REPO_ROOT, "content", "site.yaml");
const HOST = process.env.ADMIN_API_HOST || "127.0.0.1";
const PORT = Number(process.env.ADMIN_API_PORT || 8791);
const ADMIN_EMAIL = process.env.PORTFOLIO_ADMIN_EMAIL || process.env.ADMIN_EMAIL || "";
const ADMIN_PASSWORD = process.env.PORTFOLIO_ADMIN_PASSWORD || process.env.ADMIN_PASSWORD || "";
const ADMIN_TOKEN = process.env.PORTFOLIO_ADMIN_TOKEN || process.env.ADMIN_TOKEN || "";
const MAX_BODY_BYTES = Number(process.env.ADMIN_MAX_BODY_BYTES || 1_000_000);
const DATA_DIR = path.join(__dirname, "..", "data");
const BACKUP_DIR = path.join(DATA_DIR, "backups");
const AUDIT_LOG = path.join(DATA_DIR, "admin-audit.log");
const PUBLIC_DIR = path.join(__dirname, "..", "public");
const MYSQL_ENABLED = hasMysqlConfig();
const mysqlPoolPromise = MYSQL_ENABLED ? createPool().catch((error) => {
  audit("mysql.connect.failed", { message: error.message });
  return null;
}) : Promise.resolve(null);

const limiter = new Map();

ensureDir(DATA_DIR);
ensureDir(BACKUP_DIR);

const server = http.createServer(async (req, res) => {
  try {
    setSecurityHeaders(res);

    if (req.method === "OPTIONS") {
      setCors(res);
      res.writeHead(204);
      res.end();
      return;
    }

    const url = new URL(req.url, `http://${req.headers.host || `${HOST}:${PORT}`}`);

    if (url.pathname === "/" || url.pathname === "/admin" || url.pathname === "/login") {
      return serveFile(res, path.join(PUBLIC_DIR, "index.html"), "text/html; charset=utf-8");
    }

    const apiPath = normalizeApiPath(url.pathname);

    if (apiPath === "/v1/health" && req.method === "GET") {
      return json(res, 200, {
        ok: true,
        service: "portfolio-admin-api",
        authConfigured: Boolean((ADMIN_EMAIL && ADMIN_PASSWORD) || ADMIN_TOKEN),
        storage: MYSQL_ENABLED ? "mysql" : "file",
      });
    }

    if (!apiPath.startsWith("/v1/")) {
      return json(res, 404, { error: "Not found" });
    }

    setCors(res);

    const rate = checkRate(req);
    if (!rate.ok) return json(res, 429, { error: rate.error });

    const auth = requireAdmin(req);
    if (!auth.ok) return json(res, auth.code, { error: auth.error });

    if (apiPath === "/v1/content" && req.method === "GET") {
      const yamlText = await readContentSource();
      const validation = validateSiteYaml(yamlText);
      audit("content.read", { ok: validation.ok, sha: sha256(yamlText) });
      return json(res, 200, {
        yamlText,
        validation,
        contentPath: MYSQL_ENABLED ? "mysql:content_documents/site" : "content/site.yaml",
        lastModified: fs.existsSync(CONTENT_PATH) ? fs.statSync(CONTENT_PATH).mtime.toISOString() : null,
        git: getContentGitStatus(),
      });
    }

    if (apiPath === "/v1/validate" && req.method === "POST") {
      const body = await readJson(req);
      const yamlText = String(body.yamlText || "");
      const validation = validateSiteYaml(yamlText);
      audit("content.validate", { ok: validation.ok, sha: sha256(yamlText) });
      return json(res, validation.ok ? 200 : 422, { validation });
    }

    if (apiPath === "/v1/content" && req.method === "PUT") {
      const body = await readJson(req);
      const yamlText = String(body.yamlText || "");
      const validation = validateSiteYaml(yamlText);

      if (!validation.ok) {
        audit("content.save.rejected", { sha: sha256(yamlText), errors: validation.errors.length });
        return json(res, 422, { error: "Validation failed; content was not saved.", validation });
      }

      const previousText = await readContentSource();
      if (previousText === yamlText) {
        audit("content.save.noop", { sha: sha256(yamlText) });
        return json(res, 200, {
          ok: true,
          changed: false,
          message: "No changes detected.",
          validation,
          git: getContentGitStatus(),
        });
      }

      const backupPath = writeBackup(previousText);
      const normalizedYaml = yamlText.endsWith("\n") ? yamlText : `${yamlText}\n`;
      const mysqlPool = await mysqlPoolPromise;
      if (mysqlPool) {
        await saveSiteYamlToDb(mysqlPool, normalizedYaml, "admin");
      } else {
        atomicWrite(CONTENT_PATH, normalizedYaml);
      }

      audit("content.save", {
        oldSha: sha256(previousText),
        newSha: sha256(yamlText),
        backup: path.basename(backupPath),
      });

      return json(res, 200, {
        ok: true,
        changed: true,
        message: mysqlPool
          ? "Saved content in MySQL."
          : "Saved content/site.yaml locally. Review git diff, then commit/tag/deploy when ready.",
        validation,
        backup: path.relative(REPO_ROOT, backupPath),
        git: getContentGitStatus(),
      });
    }

    if (apiPath === "/v1/audit" && req.method === "GET") {
      return json(res, 200, { lines: readRecentAuditLines(100) });
    }

    if (apiPath === "/v1/publish" && req.method === "POST") {
      audit("publish.rejected", { reason: "not_implemented" });
      return json(res, 501, {
        error:
          "Publish automation is intentionally disabled in this MVP. Save locally, inspect the diff, then commit/tag/deploy explicitly.",
      });
    }

    return json(res, 404, { error: "Not found" });
  } catch (error) {
    audit("server.error", { message: error.message });
    return json(res, 500, { error: "Internal server error" });
  }
});

function normalizeApiPath(pathname) {
  if (pathname.startsWith("/api/v1/")) return pathname.replace(/^\/api/, "");
  if (pathname === "/api/v1") return "/v1";
  return pathname;
}

server.listen(PORT, HOST, () => {
  console.log(`[admin-api] listening on http://${HOST}:${PORT}`);
  if (!((ADMIN_EMAIL && ADMIN_PASSWORD) || ADMIN_TOKEN)) {
    console.warn("[admin-api] admin credentials are not set; API endpoints will reject requests.");
  }
});

function requireAdmin(req) {
  if (!((ADMIN_EMAIL && ADMIN_PASSWORD) || ADMIN_TOKEN)) {
    return { ok: false, code: 503, error: "Login is not configured." };
  }

  const header = String(req.headers.authorization || "");
  const basic = parseBasicAuth(header);
  const email = basic?.username || String(req.headers["x-admin-email"] || "");
  const password = basic?.password || String(req.headers["x-admin-password"] || "");
  const token = header.startsWith("Bearer ") ? header.slice(7) : String(req.headers["x-admin-token"] || "");

  const passwordOk = ADMIN_EMAIL && ADMIN_PASSWORD && safeEq(email, ADMIN_EMAIL) && safeEq(password, ADMIN_PASSWORD);
  const tokenOk = ADMIN_TOKEN && safeEq(token, ADMIN_TOKEN);

  if (!passwordOk && !tokenOk) {
    audit("auth.failed", { ip: clientIp(req) });
    return { ok: false, code: 401, error: "Invalid login." };
  }

  return { ok: true };
}

function parseBasicAuth(header) {
  if (!header.startsWith("Basic ")) return null;
  try {
    const decoded = Buffer.from(header.slice(6), "base64").toString("utf8");
    const idx = decoded.indexOf(":");
    if (idx === -1) return null;
    return {
      username: decoded.slice(0, idx),
      password: decoded.slice(idx + 1),
    };
  } catch {
    return null;
  }
}

function readContent() {
  return fs.readFileSync(CONTENT_PATH, "utf8");
}

async function readContentSource() {
  const mysqlPool = await mysqlPoolPromise;
  if (mysqlPool) {
    try {
      const yamlText = await loadSiteYamlFromDb(mysqlPool);
      if (yamlText) return yamlText;
      audit("mysql.content.missing", { fallback: "content/site.yaml" });
    } catch (error) {
      audit("mysql.content.read.failed", { message: error.message, fallback: "content/site.yaml" });
    }
  }
  return readContent();
}

function writeBackup(text) {
  const stamp = new Date().toISOString().replace(/[:.]/g, "-");
  const backupPath = path.join(BACKUP_DIR, `site-${stamp}.yaml`);
  fs.writeFileSync(backupPath, text, { encoding: "utf8", mode: 0o600 });
  return backupPath;
}

function atomicWrite(filePath, text) {
  const tmpPath = `${filePath}.${process.pid}.${Date.now()}.tmp`;
  fs.writeFileSync(tmpPath, text, { encoding: "utf8", mode: 0o600 });
  fs.renameSync(tmpPath, filePath);
}

function getContentGitStatus() {
  try {
    const short = execFileSync("git", ["status", "--short", "--", "content/site.yaml"], {
      cwd: REPO_ROOT,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
      timeout: 3_000,
    }).trim();
    const stat = execFileSync("git", ["diff", "--stat", "--", "content/site.yaml"], {
      cwd: REPO_ROOT,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"],
      timeout: 3_000,
    }).trim();
    return { short, stat, dirty: Boolean(short) };
  } catch {
    return { short: "", stat: "", dirty: false, unavailable: true };
  }
}

function checkRate(req) {
  const key = clientIp(req);
  const now = Date.now();
  const windowMs = 60_000;
  const limit = 120;
  const entry = limiter.get(key) || { count: 0, resetAt: now + windowMs };
  if (now > entry.resetAt) {
    entry.count = 0;
    entry.resetAt = now + windowMs;
  }
  entry.count += 1;
  limiter.set(key, entry);
  if (entry.count > limit) return { ok: false, error: "Rate limit exceeded." };
  return { ok: true };
}

function setCors(res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET,POST,PUT,OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization, X-Admin-Token");
}

function setSecurityHeaders(res) {
  res.setHeader("Cache-Control", "no-store");
  res.setHeader("X-Content-Type-Options", "nosniff");
  res.setHeader("X-Frame-Options", "DENY");
  res.setHeader("Referrer-Policy", "no-referrer");
}

function serveFile(res, filePath, contentType) {
  if (!fs.existsSync(filePath)) return json(res, 404, { error: "Not found" });
  res.writeHead(200, { "Content-Type": contentType, "Cache-Control": "no-store" });
  res.end(fs.readFileSync(filePath));
}

function json(res, code, payload) {
  res.writeHead(code, { "Content-Type": "application/json; charset=utf-8" });
  res.end(JSON.stringify(payload));
}

async function readJson(req) {
  const chunks = [];
  let size = 0;
  for await (const chunk of req) {
    size += chunk.length;
    if (size > MAX_BODY_BYTES) throw new Error("Request body is too large");
    chunks.push(chunk);
  }
  const raw = Buffer.concat(chunks).toString("utf8") || "{}";
  return JSON.parse(raw);
}

function readRecentAuditLines(limit = 100) {
  if (!fs.existsSync(AUDIT_LOG)) return [];
  const raw = fs.readFileSync(AUDIT_LOG, "utf8").trim();
  if (!raw) return [];
  const lines = raw.split("\n").filter(Boolean);
  return lines.slice(Math.max(0, lines.length - limit));
}

function audit(event, data) {
  const safeData = data && typeof data === "object" ? data : {};
  const line = JSON.stringify({ ts: new Date().toISOString(), event, ...safeData });
  fs.appendFileSync(AUDIT_LOG, `${line}\n`, "utf8");
}

function sha256(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex");
}

function clientIp(req) {
  const xff = req.headers["x-forwarded-for"];
  if (typeof xff === "string") return xff.split(",")[0].trim();
  return req.socket.remoteAddress || "unknown";
}

function safeEq(a, b) {
  if (!a || !b) return false;
  const aa = Buffer.from(String(a));
  const bb = Buffer.from(String(b));
  if (aa.length !== bb.length) return false;
  return crypto.timingSafeEqual(aa, bb);
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
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
