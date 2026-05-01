const fs = require("fs");
const path = require("path");
const mysql = require("mysql2/promise");
const {
  createPool,
  mysqlConfigFromEnv,
  mysqlAdminConfigFromEnv,
  seedSiteYamlIfMissing,
} = require("./mysqlStore");

loadLocalEnv(path.join(__dirname, "..", ".env.local"));

const REPO_ROOT = path.resolve(__dirname, "..", "..", "..");
const CONTENT_PATH = path.join(REPO_ROOT, "content", "site.yaml");
const MIGRATIONS_DIR = path.join(__dirname, "..", "migrations");

main().catch((error) => {
  console.error(`[portfolio-db] migration failed: ${error.message}`);
  process.exit(1);
});

async function main() {
  const appConfig = mysqlConfigFromEnv();
  if (!appConfig.host || !appConfig.user || !appConfig.password || !appConfig.database) {
    throw new Error("MySQL configuration is incomplete.");
  }

  await ensureDatabaseAndUser(appConfig);

  const pool = await createPool();
  if (!pool) throw new Error("MySQL pool could not be created.");

  try {
    await applyMigrations(pool);
    const seed = await seedSiteYamlIfMissing(pool, CONTENT_PATH);
    console.log(`[portfolio-db] seed ${seed.inserted ? "inserted" : "skipped"}`);
  } finally {
    await pool.end();
  }
}

async function ensureDatabaseAndUser(appConfig) {
  const adminConfig = mysqlAdminConfigFromEnv();
  const connection = await mysql.createConnection({
    host: adminConfig.host,
    port: adminConfig.port,
    user: adminConfig.user,
    password: adminConfig.password,
    multipleStatements: false,
  });

  try {
    await connection.execute(`CREATE DATABASE IF NOT EXISTS ${escapeIdentifier(appConfig.database)} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci`);
    await connection.execute(
      `CREATE USER IF NOT EXISTS ${escapeString(appConfig.user)}@'%' IDENTIFIED BY ${escapeString(appConfig.password)}`
    );
    await connection.execute(
      `GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX ON ${escapeIdentifier(appConfig.database)}.* TO ${escapeString(appConfig.user)}@'%'`
    );
    await connection.execute("FLUSH PRIVILEGES");
    console.log("[portfolio-db] database and application user ensured");
  } finally {
    await connection.end();
  }
}

async function applyMigrations(pool) {
  const files = fs
    .readdirSync(MIGRATIONS_DIR)
    .filter((file) => /^\d+_.+\.sql$/.test(file))
    .sort();

  for (const file of files) {
    const id = file.replace(/\.sql$/, "");
    const [rows] = await pool.execute("SELECT id FROM schema_migrations WHERE id = ? LIMIT 1", [id]).catch(async (error) => {
      if (!/schema_migrations/i.test(error.message)) throw error;
      return [[]];
    });

    if (rows.length > 0) {
      console.log(`[portfolio-db] migration ${id} skipped`);
      continue;
    }

    const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), "utf8");
    const statements = splitSql(sql);
    const connection = await pool.getConnection();
    try {
      await connection.beginTransaction();
      for (const statement of statements) {
        await connection.query(statement);
      }
      await connection.execute("INSERT INTO schema_migrations (id) VALUES (?)", [id]);
      await connection.commit();
      console.log(`[portfolio-db] migration ${id} applied`);
    } catch (error) {
      await connection.rollback();
      throw error;
    } finally {
      connection.release();
    }
  }
}

function splitSql(sql) {
  const withoutLineComments = String(sql)
    .split(/\r?\n/)
    .filter((line) => !line.trim().startsWith("--"))
    .join("\n");

  return withoutLineComments
    .split(/;\s*(?:\r?\n|$)/)
    .map((statement) => statement.trim())
    .filter(Boolean);
}

function escapeIdentifier(value) {
  return `\`${String(value).replace(/`/g, "``")}\``;
}

function escapeString(value) {
  return `'${String(value).replace(/'/g, "''")}'`;
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
