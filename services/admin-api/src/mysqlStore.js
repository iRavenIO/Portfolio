const fs = require("fs");
const crypto = require("crypto");
const mysql = require("mysql2/promise");

const DOCUMENT_KEY = "site";

function mysqlConfigFromEnv(env = process.env) {
  return {
    host: env.PORTFOLIO_MYSQL_HOST || env.MYSQL_HOST || "",
    port: Number(env.PORTFOLIO_MYSQL_PORT || env.MYSQL_PORT || 3306),
    database: env.PORTFOLIO_MYSQL_DATABASE || env.MYSQL_DATABASE || "portfolio",
    user: env.PORTFOLIO_MYSQL_USER || env.MYSQL_USER || "portfolio_admin",
    password: env.PORTFOLIO_MYSQL_PASSWORD || env.MYSQL_PASSWORD || "",
  };
}

function mysqlAdminConfigFromEnv(env = process.env) {
  const base = mysqlConfigFromEnv(env);
  return {
    host: base.host,
    port: base.port,
    user: env.PORTFOLIO_MYSQL_ADMIN_USER || env.MYSQL_ADMIN_USER || env.MYSQL_ROOT_USER || base.user,
    password: env.PORTFOLIO_MYSQL_ADMIN_PASSWORD || env.MYSQL_ADMIN_PASSWORD || env.MYSQL_ROOT_PASSWORD || base.password,
  };
}

function hasMysqlConfig(env = process.env) {
  const config = mysqlConfigFromEnv(env);
  return Boolean(config.host && config.user && config.password && config.database);
}

async function createPool(env = process.env) {
  const config = mysqlConfigFromEnv(env);
  if (!hasMysqlConfig(env)) return null;
  return mysql.createPool({
    ...config,
    waitForConnections: true,
    connectionLimit: Number(env.PORTFOLIO_MYSQL_CONNECTION_LIMIT || 5),
    namedPlaceholders: true,
    charset: "utf8mb4",
  });
}

async function loadSiteYamlFromDb(pool) {
  if (!pool) return null;
  const [rows] = await pool.execute(
    "SELECT body FROM content_documents WHERE document_key = ? LIMIT 1",
    [DOCUMENT_KEY]
  );
  return rows[0]?.body || null;
}

async function saveSiteYamlToDb(pool, yamlText, changedBy = "admin") {
  if (!pool) throw new Error("MySQL pool is not configured.");
  const checksum = sha256(yamlText);
  const connection = await pool.getConnection();

  try {
    await connection.beginTransaction();
    const [existingRows] = await connection.execute(
      "SELECT body, checksum FROM content_documents WHERE document_key = ? FOR UPDATE",
      [DOCUMENT_KEY]
    );

    const existing = existingRows[0] || null;
    if (existing?.checksum === checksum) {
      await connection.commit();
      return { changed: false, checksum };
    }

    if (existing) {
      await connection.execute(
        "INSERT INTO content_history (document_key, body, checksum, changed_by) VALUES (?, ?, ?, ?)",
        [DOCUMENT_KEY, existing.body, existing.checksum, changedBy]
      );
    }

    await connection.execute(
      `INSERT INTO content_documents (document_key, format, body, checksum)
       VALUES (?, 'yaml', ?, ?)
       ON DUPLICATE KEY UPDATE body = VALUES(body), checksum = VALUES(checksum), updated_at = CURRENT_TIMESTAMP`,
      [DOCUMENT_KEY, yamlText, checksum]
    );

    await connection.commit();
    return { changed: true, checksum };
  } catch (error) {
    await connection.rollback();
    throw error;
  } finally {
    connection.release();
  }
}

async function seedSiteYamlIfMissing(pool, contentPath) {
  if (!pool) throw new Error("MySQL pool is not configured.");
  const yamlText = fs.readFileSync(contentPath, "utf8");
  const [rows] = await pool.execute(
    "SELECT id FROM content_documents WHERE document_key = ? LIMIT 1",
    [DOCUMENT_KEY]
  );
  if (rows.length > 0) return { inserted: false, checksum: sha256(yamlText) };

  await pool.execute(
    "INSERT INTO content_documents (document_key, format, body, checksum) VALUES (?, 'yaml', ?, ?)",
    [DOCUMENT_KEY, yamlText, sha256(yamlText)]
  );
  return { inserted: true, checksum: sha256(yamlText) };
}

function sha256(value) {
  return crypto.createHash("sha256").update(String(value)).digest("hex");
}

module.exports = {
  DOCUMENT_KEY,
  mysqlConfigFromEnv,
  mysqlAdminConfigFromEnv,
  hasMysqlConfig,
  createPool,
  loadSiteYamlFromDb,
  saveSiteYamlToDb,
  seedSiteYamlIfMissing,
};
