const YAML = require("yaml");

const SUPPORTED_PAGE_TYPES = new Set(["home", "projects", "info", "profile", "contact"]);
const URL_FIELDS = new Set(["href", "canonical_url", "url", "share_image_url", "stylesheet_path", "favicon_path", "apple_touch_icon_path", "main_js_path"]);

function parseSiteYaml(yamlText) {
  const errors = [];
  let parsed = null;

  try {
    const document = YAML.parseDocument(String(yamlText || ""), { prettyErrors: false });
    if (document.errors.length > 0) {
      for (const error of document.errors) {
        errors.push(formatYamlError(error));
      }
    }
    parsed = document.toJSON();
  } catch (error) {
    errors.push(`YAML parse failed: ${error.message}`);
  }

  return { parsed, errors };
}

function validateSiteYaml(yamlText) {
  const { parsed, errors } = parseSiteYaml(yamlText);
  if (errors.length > 0) {
    return { ok: false, errors, warnings: [], summary: null };
  }

  return validateSiteContent(parsed);
}

function validateSiteContent(rawContent) {
  const errors = [];
  const warnings = [];

  requireObject(rawContent, "site.yaml", errors);
  if (errors.length > 0) return result(errors, warnings);

  requireObject(rawContent.site, "site", errors);
  requireObject(rawContent.assets, "assets", errors);
  requireObject(rawContent.shell, "shell", errors);
  requireObject(rawContent.page_types, "page_types", errors);
  requireArray(rawContent.pages, "pages", errors);

  validateKnownPageTypes(rawContent.page_types, errors, warnings);
  scanUnsafeUrls(rawContent, "site.yaml", errors);

  if (Array.isArray(rawContent.pages)) {
    validatePages(rawContent.pages, rawContent.page_types || {}, errors, warnings);
  }

  if (rawContent.analytics?.google_tag_id && !/^G-[A-Z0-9]+$/.test(String(rawContent.analytics.google_tag_id))) {
    warnings.push("analytics.google_tag_id does not look like a GA4 measurement id.");
  }

  const summary = buildSummary(rawContent);
  return result(errors, warnings, summary);
}

function validateKnownPageTypes(pageTypes, errors, warnings) {
  if (!pageTypes || typeof pageTypes !== "object" || Array.isArray(pageTypes)) return;

  for (const pageType of SUPPORTED_PAGE_TYPES) {
    if (!Object.prototype.hasOwnProperty.call(pageTypes, pageType)) {
      errors.push(`page_types must define '${pageType}'.`);
    }
  }

  for (const pageType of Object.keys(pageTypes)) {
    if (!SUPPORTED_PAGE_TYPES.has(pageType)) {
      warnings.push(`page_types.${pageType} is defined but is not rendered by the static site.`);
    }
  }
}

function validatePages(pages, pageTypes, errors, warnings) {
  const seenKeys = new Set();
  const seenPaths = new Set();

  pages.forEach((page, index) => {
    const label = `pages[${index}]`;
    requireObject(page, label, errors);
    if (!page || typeof page !== "object" || Array.isArray(page)) return;

    const key = normalizeString(page.key);
    const type = normalizeString(page.type);
    const routePath = normalizePath(page.path);

    if (!key) errors.push(`${label}.key is required.`);
    if (!type) errors.push(`${label}.type is required.`);
    if (!page.path) errors.push(`${label}.path is required.`);

    if (key && seenKeys.has(key)) errors.push(`Duplicate page key '${key}'.`);
    if (routePath && seenPaths.has(routePath)) errors.push(`Duplicate page path '${routePath}'.`);
    if (key) seenKeys.add(key);
    if (routePath) seenPaths.add(routePath);

    if (type && !SUPPORTED_PAGE_TYPES.has(type)) {
      errors.push(`${label}.type '${type}' is not supported.`);
    }
    if (type && !Object.prototype.hasOwnProperty.call(pageTypes, type)) {
      errors.push(`${label}.type '${type}' is missing from page_types.`);
    }

    if (page.nav_label !== undefined && typeof page.nav_label !== "string") {
      errors.push(`${label}.nav_label must be a string when provided.`);
    }
    if (page.nav_visible !== undefined && typeof page.nav_visible !== "boolean") {
      errors.push(`${label}.nav_visible must be a boolean when provided.`);
    }
    requireObject(page.content, `${label}.content`, errors);

    validatePageContent(type, page.content || {}, label, errors, warnings);
  });

  if (!pages.some((page) => normalizePath(page?.path) === "/")) {
    errors.push("At least one page must use path '/'.");
  }
}

function validatePageContent(type, content, label, errors, warnings) {
  if (!content || typeof content !== "object" || Array.isArray(content)) return;

  if (type === "home") {
    requireStringArray(content.about_spans, `${label}.content.about_spans`, errors);
  }

  if (type === "projects") {
    requireArray(content.sections, `${label}.content.sections`, errors);
    if (Array.isArray(content.sections)) {
      content.sections.forEach((section, sectionIndex) => {
        const sectionLabel = `${label}.content.sections[${sectionIndex}]`;
        requireObject(section, sectionLabel, errors);
        requireString(section?.heading, `${sectionLabel}.heading`, errors);
        requireArray(section?.items, `${sectionLabel}.items`, errors);
        if (Array.isArray(section?.items)) {
          section.items.forEach((item, itemIndex) => validateLinkItem(item, `${sectionLabel}.items[${itemIndex}]`, ["title", "info", "href"], errors));
        }
      });
    }
  }

  if (type === "info") {
    requireArray(content.columns, `${label}.content.columns`, errors);
    if (Array.isArray(content.columns)) {
      content.columns.forEach((column, columnIndex) => {
        const columnLabel = `${label}.content.columns[${columnIndex}]`;
        requireArray(column?.items, `${columnLabel}.items`, errors);
        if (Array.isArray(column?.items)) {
          column.items.forEach((item, itemIndex) => validateInfoItem(item, `${columnLabel}.items[${itemIndex}]`, errors));
        }
      });
    }
  }

  if (type === "profile") {
    if (content.title !== undefined && typeof content.title !== "string") {
      errors.push(`${label}.content.title must be a string when provided.`);
    }
    requireStringArray(content.paragraphs, `${label}.content.paragraphs`, errors);
    if (Array.isArray(content.paragraphs) && content.paragraphs.length > 18) {
      warnings.push(`${label}.content.paragraphs is long; consider splitting or tightening the profile copy.`);
    }
  }

  if (type === "contact") {
    requireArray(content.contacts, `${label}.content.contacts`, errors);
    if (Array.isArray(content.contacts)) {
      content.contacts.forEach((contact, index) => validateLinkItem(contact, `${label}.content.contacts[${index}]`, ["label", "href"], errors));
    }
  }
}

function validateInfoItem(item, label, errors) {
  requireObject(item, label, errors);
  if (!item || typeof item !== "object" || Array.isArray(item)) return;

  const kind = normalizeString(item.kind || "segments");
  if (!new Set(["link", "segments"]).has(kind)) {
    errors.push(`${label}.kind must be 'link' or 'segments'.`);
    return;
  }

  if (kind === "link") {
    validateLinkItem(item, label, ["label", "href"], errors);
    return;
  }

  requireArray(item.segments, `${label}.segments`, errors);
  if (Array.isArray(item.segments)) {
    item.segments.forEach((segment, index) => {
      const segmentLabel = `${label}.segments[${index}]`;
      requireObject(segment, segmentLabel, errors);
      requireString(segment?.text, `${segmentLabel}.text`, errors);
      if (segment?.light !== undefined && typeof segment.light !== "boolean") {
        errors.push(`${segmentLabel}.light must be a boolean when provided.`);
      }
      if (segment?.br !== undefined && typeof segment.br !== "boolean") {
        errors.push(`${segmentLabel}.br must be a boolean when provided.`);
      }
    });
  }
}

function validateLinkItem(item, label, fields, errors) {
  requireObject(item, label, errors);
  if (!item || typeof item !== "object" || Array.isArray(item)) return;

  for (const field of fields) {
    requireString(item[field], `${label}.${field}`, errors);
  }

  if (item.href && !isSafeUrl(item.href)) {
    errors.push(`${label}.href uses an unsafe or unsupported URL scheme.`);
  }
}

function scanUnsafeUrls(value, path, errors) {
  if (Array.isArray(value)) {
    value.forEach((item, index) => scanUnsafeUrls(item, `${path}[${index}]`, errors));
    return;
  }

  if (!value || typeof value !== "object") return;

  for (const [key, child] of Object.entries(value)) {
    const childPath = `${path}.${key}`;
    if (URL_FIELDS.has(key) && child && !isSafeUrl(child)) {
      errors.push(`${childPath} uses an unsafe or unsupported URL scheme.`);
    }
    scanUnsafeUrls(child, childPath, errors);
  }
}

function isSafeUrl(value) {
  const text = String(value || "").trim();
  if (!text) return true;
  if (text.startsWith("/") || text.startsWith("#")) return true;
  return /^(https?:|mailto:|tel:)/i.test(text);
}

function normalizePath(routePath) {
  const value = String(routePath || "").trim();
  if (!value) return "";
  if (value === "/") return "/";
  const trimmed = value.replace(/^\/+|\/+$/g, "");
  return `/${trimmed}/`;
}

function requireObject(value, label, errors) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    errors.push(`${label} must be an object.`);
  }
}

function requireArray(value, label, errors) {
  if (!Array.isArray(value)) {
    errors.push(`${label} must be an array.`);
  }
}

function requireString(value, label, errors) {
  if (typeof value !== "string" || value.trim().length === 0) {
    errors.push(`${label} must be a non-empty string.`);
  }
}

function requireStringArray(value, label, errors) {
  requireArray(value, label, errors);
  if (!Array.isArray(value)) return;
  value.forEach((item, index) => {
    if (typeof item !== "string") {
      errors.push(`${label}[${index}] must be a string.`);
    }
  });
}

function normalizeString(value) {
  return typeof value === "string" ? value.trim() : "";
}

function buildSummary(rawContent) {
  const pages = Array.isArray(rawContent.pages) ? rawContent.pages : [];
  return {
    title: rawContent.site?.title || "",
    pages: pages.map((page) => ({
      key: page.key || "",
      type: page.type || "",
      path: normalizePath(page.path || ""),
      nav_label: page.nav_label || "",
    })),
  };
}

function result(errors, warnings, summary = null) {
  return { ok: errors.length === 0, errors, warnings, summary };
}

function formatYamlError(error) {
  const line = error.linePos?.[0]?.line;
  const col = error.linePos?.[0]?.col;
  const location = line ? ` at ${line}:${col || 1}` : "";
  return `YAML ${error.name || "error"}${location}: ${error.message}`;
}

module.exports = {
  SUPPORTED_PAGE_TYPES,
  parseSiteYaml,
  validateSiteYaml,
  validateSiteContent,
};
