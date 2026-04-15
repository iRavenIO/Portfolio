import fs from "fs";
import path from "path";
import YAML from "yaml";

const CONTENT_PATH = path.join(process.cwd(), "content", "site.yaml");
const SUPPORTED_PAGE_TYPES = new Set(["home", "projects", "info", "contact", "assistant"]);

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

  if (page.type === "assistant") {
    return `<div class="page_content assistant" style="position:relative;min-height:calc(var(--vh, 1vh)*100);box-sizing:border-box;overflow:hidden;"><div class="assistant-hero" data-assistant-hero data-api-base="/assistant-api/v1"><p class="assistant-hero__prompt">Ask about my work, projects, or experience</p><form class="assistant-hero__form" novalidate><input name="q" type="text" autocomplete="off" placeholder="Type and press Enter" aria-label="Ask assistant" /></form><div class="assistant-float-layer" aria-hidden="true"></div></div><script defer src="/assets/js/assistant-hero.js"></script><style>.assistant-hero{position:absolute;right:clamp(72px,6vw,88px);bottom:clamp(64px,5.2vw,80px);width:clamp(320px,31vw,380px);max-width:calc(100% - 2.2rem);display:grid;gap:12px;align-items:start;justify-items:start}.assistant-hero__prompt{margin:0;color:rgba(242,242,242,.82);font-size:clamp(15px,1.24vw,18px);font-weight:360;letter-spacing:.013em;line-height:1.2}.assistant-hero__form{display:block;width:100%}.assistant-hero__form input{width:100%;height:48px;box-sizing:border-box;background:rgba(8,8,8,.2);color:rgba(247,247,247,.93);border:1px solid rgba(208,208,208,.24);border-radius:4px;padding:0 .82rem;font:inherit;font-size:15px;letter-spacing:.004em;outline:none;backdrop-filter:blur(1.5px);-webkit-backdrop-filter:blur(1.5px);transition:border-color .2s ease,box-shadow .2s ease,background-color .2s ease}.assistant-hero__form input::placeholder{color:rgba(224,224,224,.48)}.assistant-hero__form input:focus{border-color:rgba(242,242,242,.5);box-shadow:0 0 0 1px rgba(255,255,255,.05);background:rgba(10,10,10,.26)}.assistant-float-layer{position:absolute;left:0;right:0;bottom:58px;max-height:min(58vh,560px);display:flex;flex-direction:column;gap:10px;pointer-events:none;overflow:hidden}.assistant-float-message{max-width:min(78vw,420px);margin:0;padding:.46rem .62rem;border:1px solid rgba(210,210,210,.14);border-radius:4px;background:rgba(10,10,10,.22);color:rgba(244,244,244,.9);font-size:14px;line-height:1.35;letter-spacing:.003em;white-space:pre-wrap;word-break:break-word}.assistant-float-message.is-assistant{align-self:flex-start;border-color:rgba(186,186,186,.22);color:rgba(236,236,236,.84)}.assistant-float-message.is-user{align-self:flex-end;border-color:rgba(218,218,218,.22);color:rgba(247,247,247,.95)}@media (max-width:980px){.assistant-hero{right:clamp(20px,5vw,30px);bottom:clamp(28px,8vw,46px);width:min(92vw,360px);gap:10px}.assistant-hero__prompt{font-size:clamp(14px,4vw,16px)}.assistant-hero__form input{height:46px;font-size:14px;padding:0 .72rem}.assistant-float-layer{max-height:min(46vh,420px)}}</style></div>`;
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

export function buildNotFoundLegacyMarkup(siteContent) {
  const shell = siteContent.shell || {};
  const theme = shell.theme || {};

  const notFoundHtml = `<section class="page" data-page="home"><div style="min-height:calc(var(--vh, 1vh)*100);display:grid;place-items:center;padding:calc(var(--pad)*2);"><div style="width:min(100%, 44rem);line-height:1.15;"><p class="project_title" style="margin:0;line-height:1;">404</p><p style="margin:.35rem 0 0;font-size:1.4rem;font-weight:400;">Page Not Found</p><p style="margin:.9rem 0 0;font-size:1rem;font-weight:400;opacity:.8;line-height:1.4;">The page you requested could not be found.</p></div></div></section>`;

  return `<div id="EnterView"><div class="_t1">&nbsp;</div><div class="_t2">&nbsp;</div></div><div id="Page"><div id="Background"><canvas></canvas></div><div class="mask" id="Mask"><div class="mask_top"></div><div class="mask_bottom"></div></div><div class="frame" id="Frame"><div class="frame_line frame_line-left"></div><div class="frame_line frame_line-right"></div><div class="frame_line frame_line-top"></div><div class="frame_line frame_line-bottom"></div></div><div class="theme" id="Theme" x-data><div class="theme_colors" @click="$store.app.toggleTheme()"><div class="theme_btn" :class="{ 'is-selected': $store.app.theme === 'light' }"><div class="_box"></div><div class="_text">${escapeHtml(theme.light_label || "Light")}</div></div><div class="theme_btn" :class="{ 'is-selected': $store.app.theme === 'dark' }"><div class="_box"></div><div class="_text">${escapeHtml(theme.dark_label || "Dark")}</div></div></div><div class="theme_btn" :class="{ 'is-selected': $store.app.fontStyle === 'mono' }" @click="$store.app.toggleFontStyle()"><div class="_box"></div><div class="_text">${escapeHtml(theme.mono_label || "Monospaced")}</div></div></div><header class="siteHeader" id="SiteHeader" style="visibility:hidden;pointer-events:none;"></header><div id="Copyright" style="visibility:hidden;pointer-events:none;"></div><main class="content" id="Content" data-scroll="area"><div class="content_inner" data-scroll="target">${notFoundHtml}</div></main></div>`;
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
