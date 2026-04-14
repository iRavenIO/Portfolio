import fs from "fs";
import path from "path";
import YAML from "yaml";

const CONTENT_PATH = path.join(process.cwd(), "content", "site.yaml");
const SUPPORTED_PAGE_TYPES = new Set(["home", "projects", "info", "contact"]);

function assert(condition, message) {
  if (!condition) {
    throw new Error(message);
  }
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function normalizePath(routePath) {
  const value = String(routePath || "/").trim();
  if (value === "/") {
    return "/";
  }

  const trimmed = value.replace(/^\/+|\/+$/g, "");
  return `/${trimmed}/`;
}

export function slugToPath(slug) {
  if (!slug || slug.length === 0) {
    return "/";
  }

  return `/${slug.join("/")}/`;
}

export function pathToSlug(routePath) {
  const normalized = normalizePath(routePath);
  if (normalized === "/") {
    return [];
  }

  return normalized.split("/").filter(Boolean);
}

function normalizeContent(rawContent) {
  assert(rawContent && typeof rawContent === "object", "site.yaml must be an object.");
  assert(Array.isArray(rawContent.pages), "site.yaml must include a pages array.");

  const pageTypeMap = rawContent.page_types || {};
  const knownTypes = new Set(Object.keys(pageTypeMap));

  for (const supportedType of SUPPORTED_PAGE_TYPES) {
    assert(
      knownTypes.has(supportedType),
      `site.yaml page_types must define '${supportedType}'.`
    );
  }

  const seenKeys = new Set();
  const seenPaths = new Set();

  const pages = rawContent.pages.map((page, index) => {
    assert(page && typeof page === "object", `pages[${index}] must be an object.`);
    assert(page.key, `pages[${index}].key is required.`);
    assert(page.type, `pages[${index}].type is required.`);
    assert(page.path, `pages[${index}].path is required.`);

    const key = String(page.key).trim();
    const type = String(page.type).trim();
    const routePath = normalizePath(page.path);

    assert(key.length > 0, `pages[${index}].key cannot be empty.`);
    assert(
      SUPPORTED_PAGE_TYPES.has(type),
      `pages[${index}].type '${type}' is not supported.`
    );
    assert(
      knownTypes.has(type),
      `pages[${index}] type '${type}' is missing from page_types.`
    );
    assert(!seenKeys.has(key), `Duplicate page key '${key}' in site.yaml.`);
    assert(!seenPaths.has(routePath), `Duplicate page path '${routePath}' in site.yaml.`);

    seenKeys.add(key);
    seenPaths.add(routePath);

    return {
      ...page,
      key,
      type,
      path: routePath,
      nav_label: page.nav_label ? String(page.nav_label) : "",
      content: page.content || {}
    };
  });

  return {
    ...rawContent,
    pages
  };
}

export function loadSiteContent() {
  const yamlText = fs.readFileSync(CONTENT_PATH, "utf8");
  const parsed = YAML.parse(yamlText);
  return normalizeContent(parsed);
}

function renderProjectItem(item) {
  const href = escapeHtml(item.href || "#");
  const title = escapeHtml(item.title || "");
  const info = escapeHtml(item.info || "");
  const target = item.target ? String(item.target) : "_blank";
  const rel = item.rel ? String(item.rel) : "noopener";

  return `<a class="project_item text-btn" href="${href}" target="${escapeHtml(target)}" rel="${escapeHtml(rel)}"><div class="project_title">${title}</div><div class="project_info">${info}</div></a>`;
}

function renderInfoItem(item) {
  if (item.kind === "link") {
    const href = escapeHtml(item.href || "#");
    const label = escapeHtml(item.label || "");
    const target = item.target ? String(item.target) : "_blank";
    const rel = item.rel ? String(item.rel) : "noopener";
    return `<li><a class="text-btn" href="${href}" target="${escapeHtml(target)}" rel="${escapeHtml(rel)}">${label}</a></li>`;
  }

  const segments = Array.isArray(item.segments) ? item.segments : [];
  const html = segments
    .map((segment) => {
      const text = escapeHtml(segment.text || "");
      const className = segment.light ? " class=\"is-light\"" : "";
      const suffix = segment.br ? "<br>" : "";
      return `<span${className}>${text}${suffix}</span>`;
    })
    .join("");

  return `<li>${html}</li>`;
}

function renderPageContent(page) {
  if (page.type === "home") {
    const spans = Array.isArray(page.content.about_spans) ? page.content.about_spans : [];
    const aboutHtml = spans.map((span) => `<span>${escapeHtml(span)}</span>`).join("");
    return `<div class="page_content home"><p class="home_aboutme">${aboutHtml}</p></div>`;
  }

  if (page.type === "projects") {
    const sections = Array.isArray(page.content.sections) ? page.content.sections : [];
    const sectionsHtml = sections
      .map((section) => {
        const heading = escapeHtml(section.heading || "");
        const items = Array.isArray(section.items) ? section.items : [];
        const itemsHtml = items.map(renderProjectItem).join("");
        return `<div class="project_section"><h2 class="project_heading">${heading}</h2><div class="project_list">${itemsHtml}</div></div>`;
      })
      .join("");

    return `<div class="page_content project">${sectionsHtml}</div>`;
  }

  if (page.type === "info") {
    const columns = Array.isArray(page.content.columns) ? page.content.columns : [];
    const columnsHtml = columns
      .map((column, index) => {
        const items = Array.isArray(column.items) ? column.items : [];
        const itemsHtml = items.map(renderInfoItem).join("");
        return `<div class="info_item info_item-${index + 1}"><div class="info_content"><ul>${itemsHtml}</ul></div></div>`;
      })
      .join("");

    return `<div class="page_content info">${columnsHtml}</div>`;
  }

  const contacts = Array.isArray(page.content.contacts) ? page.content.contacts : [];
  const contactsHtml = contacts
    .map((contact) => {
      const href = escapeHtml(contact.href || "#");
      const label = escapeHtml(contact.label || "");
      const target = contact.target ? String(contact.target) : "_blank";
      const rel = contact.rel ? String(contact.rel) : "noopener";
      return `<div class="contact_wrap"><a class="contact_text jp text-btn" href="${href}" target="${escapeHtml(target)}" rel="${escapeHtml(rel)}">${label}</a></div>`;
    })
    .join("");

  return `<div class="page_content contact">${contactsHtml}</div>`;
}

function renderNav(pages) {
  const navPages = pages.filter((page) => page.nav_label && page.nav_visible !== false);

  return navPages
    .map((page) => {
      const path = String(page.path).replace(/'/g, "\\'");
      const label = escapeHtml(page.nav_label);
      return `<li :class="{ 'is-selected': $store.app.currentPath === '${path}' }"><div class="_dot">&#x25cf;</div><a class="_text" href="${escapeHtml(page.path)}">${label}</a></li>`;
    })
    .join("");
}

export function buildLegacyMarkup(siteContent) {
  const shell = siteContent.shell || {};
  const enterView = shell.enter_view || {};
  const theme = shell.theme || {};
  const header = shell.header || {};
  const copyrightText = shell.copyright || "";

  const pagesHtml = siteContent.pages
    .map((page) => {
      const dataPage = escapeHtml(page.key);
      return `<section class="page" data-page="${dataPage}">${renderPageContent(page)}</section>`;
    })
    .join("");

  return `<div id="EnterView"><div class="_t1">${escapeHtml(enterView.title || "")}</div><div class="_t2">${escapeHtml(enterView.subtitle || "")}</div></div><div id="Page"><div id="Background"><canvas></canvas></div><div class="mask" id="Mask"><div class="mask_top"></div><div class="mask_bottom"></div></div><div class="frame" id="Frame"><div class="frame_line frame_line-left"></div><div class="frame_line frame_line-right"></div><div class="frame_line frame_line-top"></div><div class="frame_line frame_line-bottom"></div></div><div class="theme" id="Theme" x-data><div class="theme_colors" @click="$store.app.toggleTheme()"><div class="theme_btn" :class="{ 'is-selected': $store.app.theme === 'light' }"><div class="_box"></div><div class="_text">${escapeHtml(theme.light_label || "Light")}</div></div><div class="theme_btn" :class="{ 'is-selected': $store.app.theme === 'dark' }"><div class="_box"></div><div class="_text">${escapeHtml(theme.dark_label || "Dark")}</div></div></div><div class="theme_btn" :class="{ 'is-selected': $store.app.fontStyle === 'mono' }" @click="$store.app.toggleFontStyle()"><div class="_box"></div><div class="_text">${escapeHtml(theme.mono_label || "Monospaced")}</div></div></div><header class="siteHeader" id="SiteHeader"><h1 class="siteHeader_title">${escapeHtml(header.title || "")}</h1><p class="siteHeader_label">${escapeHtml(header.label || "")}</p><nav class="siteHeader_nav" x-data><ol>${renderNav(siteContent.pages)}</ol></nav></header><div id="Copyright"><p>${escapeHtml(copyrightText)}</p></div><main class="content" id="Content" data-scroll="area"><div class="content_inner" data-scroll="target">${pagesHtml}</div></main></div>`;
}

export function buildHeadProps(siteContent) {
  const site = siteContent.site || {};
  const assets = siteContent.assets || {};
  const og = site.og || {};

  return {
    lang: site.lang || "en",
    title: site.title || "",
    description: site.description || "",
    canonical_url: site.canonical_url || "",
    og_locale: og.locale || "",
    og_type: og.type || "website",
    og_site_name: og.site_name || "",
    og_title: og.title || "",
    og_description: og.description || "",
    og_url: og.url || "",
    twitter_card: site.twitter_card || "summary_large_image",
    google_meta: Array.isArray(site.google_meta) ? site.google_meta : [],
    stylesheet_path: assets.stylesheet_path || "/assets/css/style.css",
    favicon_path: assets.favicon_path || "/assets/favicon.png",
    apple_touch_icon_path: assets.apple_touch_icon_path || "/assets/favicon.png",
    share_image_url: assets.share_image_url || "",
    share_image_type: assets.share_image_type || "image/png",
    share_image_width: String(assets.share_image_width || "1200"),
    share_image_height: String(assets.share_image_height || "630")
  };
}

export function buildScriptProps(siteContent) {
  const assets = siteContent.assets || {};
  const analytics = siteContent.analytics || {};

  return {
    main_js_path: assets.main_js_path || "/assets/js/main.js",
    google_tag_id: analytics.google_tag_id || ""
  };
}
