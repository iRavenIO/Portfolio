import fs from "fs";
import path from "path";
import YAML from "yaml";

const CONTENT_PATH = path.join(process.cwd(), "content", "site.yaml");
const SUPPORTED_PAGE_TYPES = new Set(["home", "projects", "info", "profile", "contact"]);

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
  const details = Array.isArray(item.details) ? item.details : [];
  const detailsHtml = details.length
    ? `<ul class="project_details">${details
        .filter((detail) => typeof detail === "string")
        .map((detail) => `<li>${escapeHtml(detail)}</li>`)
        .join("")}</ul>`
    : "";

  return `<a class="project_item text-btn" href="${href}" target="${escapeHtml(target)}" rel="${escapeHtml(rel)}"><div class="project_title">${title}</div><div class="project_info">${info}</div>${detailsHtml}</a>`;
}

function renderSimpleList(items, className) {
  const values = Array.isArray(items) ? items : [];
  if (values.length === 0) return "";

  return `<ul class="${escapeHtml(className)}">${values
    .filter((item) => typeof item === "string")
    .map((item) => `<li>${escapeHtml(item)}</li>`)
    .join("")}</ul>`;
}

function renderProfileSection(section) {
  const heading = escapeHtml(section.heading || "");
  const paragraphs = Array.isArray(section.paragraphs) ? section.paragraphs : [];
  const items = Array.isArray(section.items) ? section.items : [];
  const headingHtml = heading ? `<h3>${heading}</h3>` : "";
  const paragraphHtml = paragraphs
    .filter((paragraph) => typeof paragraph === "string")
    .map((paragraph) => `<p>${escapeHtml(paragraph)}</p>`)
    .join("");

  const itemHtml = items.length
    ? `<div class="profile_cards">${items
        .map((item) => {
          const label = escapeHtml(item.label || item.title || "");
          const text = escapeHtml(item.description || item.text || "");
          return `<div class="profile_card"><strong>${label}</strong><span>${text}</span></div>`;
        })
        .join("")}</div>`
    : "";

  const bulletsHtml = renderSimpleList(section.bullets, "profile_bullets");
  return `<section class="profile_section">${headingHtml}${paragraphHtml}${itemHtml}${bulletsHtml}</section>`;
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

    return `<div class="page_content project">${sectionsHtml}<style>.project{white-space:initial;overflow-x:clip}.project_section{width:min(100%,1040px);margin-left:auto}.project_heading{margin-left:auto;max-width:1040px;line-height:1.2}.project_list{width:100%;max-width:1040px;margin-left:auto;align-items:stretch;row-gap:clamp(28px,3.4vw,46px)}.project_item{display:flex!important;flex-direction:column;align-items:flex-end;width:100%;max-width:100%;min-width:0;min-height:unset;padding-bottom:clamp(20px,2.1vw,28px);border-bottom:1px solid rgba(242,242,242,.12);white-space:normal;text-align:right}.project_title{display:block;max-width:min(100%,820px);min-width:0;overflow-wrap:anywhere;word-break:normal;text-wrap:balance;line-height:.96;font-size:clamp(38px,4.2vw,58px)}.project_info{display:block;max-width:min(100%,620px);margin-top:clamp(6px,.75vw,10px);line-height:1.35;color:rgba(242,242,242,.74);white-space:normal;text-align:right}.project_details{width:min(100%,760px);margin:clamp(12px,1.4vw,18px) 0 0;padding:.9rem 0 0 1.05rem;border-top:1px solid rgba(242,242,242,.08);color:rgba(242,242,242,.72);font-size:clamp(12px,.82vw,14px);line-height:1.46;font-weight:360;text-align:left;white-space:normal}.project_details li{margin:.3rem 0}.project_details li::marker{color:rgba(242,242,242,.42)}@media(min-width:1720px){.project_section,.project_list,.project_heading{max-width:1120px}.project_title{font-size:clamp(46px,3.25vw,60px)}}@media(max-width:1180px){.project_section,.project_list,.project_heading{max-width:100%}.project_title{font-size:clamp(36px,5.8vw,52px)}.project_info{max-width:min(100%,560px)}.project_details{width:min(100%,720px)}}@media(max-width:980px){.project_list{row-gap:30px}.project_title{font-size:clamp(34px,7.6vw,48px)}.project_details{font-size:12px}}@media(max-width:640px){.project{padding-left:calc(var(--pad)*2);padding-right:calc(var(--pad)*2)}.project_item{align-items:flex-start;text-align:left}.project_title,.project_info{text-align:left}.project_title{font-size:clamp(32px,11vw,44px)}.project_details{width:100%}}</style></div>`;
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

  if (page.type === "profile") {
    const title = escapeHtml(page.content.title || "");
    const subtitle = escapeHtml(page.content.subtitle || "");
    const paragraphs = Array.isArray(page.content.paragraphs) ? page.content.paragraphs : [];
    const paragraphsHtml = paragraphs
      .filter((paragraph) => typeof paragraph === "string")
      .map((paragraph) => `<p>${escapeHtml(paragraph)}</p>`)
      .join("");
    const sections = Array.isArray(page.content.sections) ? page.content.sections : [];
    const sectionsHtml = sections.map(renderProfileSection).join("");

    const titleHtml = title ? `<h2>${title}</h2>` : "";
    const subtitleHtml = subtitle ? `<p class="profile_subtitle">${subtitle}</p>` : "";
    const profileStyles = `<style>
.profile{min-height:calc(var(--vh,1vh)*100);padding:clamp(126px,18vh,172px) clamp(24px,5vw,72px) clamp(42px,7vh,72px);white-space:initial;overflow-x:clip}.profile_content{width:min(100%,840px);max-width:calc(100vw - clamp(300px,28vw,430px));margin-left:clamp(260px,28vw,420px);margin-right:auto;line-height:1.48;font-size:clamp(14px,.9vw,16px);font-weight:400;color:rgba(242,242,242,.88)}.profile_hero{margin:0 0 clamp(14px,2.4vh,22px)}.profile_content h2{max-width:820px;margin:0 0 clamp(10px,1.6vh,16px);font-weight:260;font-size:clamp(38px,4.65vw,66px);line-height:1.01;letter-spacing:-.04em;text-align:left;text-wrap:balance;color:rgba(255,255,255,.98)}.profile_subtitle{max-width:620px;margin:0!important;text-align:left!important;font-size:clamp(16px,1.16vw,20px);line-height:1.36;font-weight:400;color:rgba(242,242,242,.72);text-wrap:balance}.profile_section{border-top:1px solid rgba(242,242,242,.14);padding-top:clamp(14px,2vh,20px);margin-top:clamp(14px,2vh,22px)}.profile_about{border-top:0;padding-top:0;margin-top:clamp(12px,1.8vh,18px);max-width:720px}.profile_about p{margin-bottom:.72em}.profile_section h3{margin:0 0 clamp(10px,1.6vh,14px);font-weight:460;font-size:clamp(12px,.82vw,14px);line-height:1.2;letter-spacing:.09em;text-transform:uppercase;color:rgba(242,242,242,.78)}.profile_content p{margin:0 0 .86em;text-align:left}.profile_cards{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:10px}.profile_card{min-width:0;border:1px solid rgba(242,242,242,.12);padding:12px 13px;background:rgba(255,255,255,.025)}.profile_card strong{display:block;margin:0 0 .28rem;font-size:.96em;line-height:1.22;font-weight:520;color:rgba(242,242,242,.95)}.profile_card span{display:block;color:rgba(242,242,242,.66);font-size:.88em;line-height:1.38}.profile_bullets{margin:0;padding-left:1rem;color:rgba(242,242,242,.74)}.profile_bullets li{margin:.34rem 0;line-height:1.42}body:has(.page[data-page="profile"].is-selected) .siteHeader_title{font-size:clamp(28px,3.2vw,46px);opacity:.78}body:has(.page[data-page="profile"].is-selected) .siteHeader_label{max-width:220px;line-height:1.28;opacity:.66}body:has(.page[data-page="profile"].is-selected) .siteHeader_nav{margin-top:34px;opacity:.74}body:has(.page[data-page="profile"].is-selected) .siteHeader_nav ol{row-gap:12px}@media(max-width:1180px){.profile{padding-top:clamp(132px,18vh,158px)}.profile_content{max-width:calc(100vw - clamp(330px,38vw,420px));margin-left:clamp(230px,27vw,320px);font-size:14px}.profile_content h2{font-size:clamp(36px,4.6vw,54px)}.profile_subtitle{font-size:clamp(15px,1.45vw,18px)}.profile_cards{grid-template-columns:1fr 1fr}.profile_card{padding:11px 12px}}@media(max-width:980px){.profile{padding:calc(var(--pad)*2 + 116px) calc(var(--pad)*2) calc(var(--pad)*2)}.profile_content{width:100%;max-width:100%;margin-left:0;margin-right:0;font-size:15px}.profile_content h2{font-size:clamp(36px,8.4vw,58px);line-height:1.02}.profile_subtitle{max-width:680px}.profile_cards{grid-template-columns:1fr 1fr}}@media(max-width:720px){.profile{padding-top:calc(var(--pad)*2 + 96px)}.profile_content h2{font-size:clamp(34px,11vw,48px);letter-spacing:-.035em}.profile_subtitle{font-size:16px}.profile_cards{grid-template-columns:1fr}.profile_section{margin-top:20px;padding-top:18px}}@media(max-height:760px) and (min-width:981px){.profile{padding-top:clamp(104px,14vh,126px)}.profile_content{font-size:14px}.profile_content h2{font-size:clamp(36px,4.25vw,58px);line-height:1}.profile_subtitle{font-size:clamp(15px,1vw,18px);max-width:580px}.profile_section{margin-top:12px;padding-top:12px}.profile_cards{gap:8px}.profile_card{padding:10px 11px}.profile_card span{font-size:.84em;line-height:1.32}body:has(.page[data-page="profile"].is-selected) .siteHeader_nav{margin-top:26px}}</style>`;

    return `<div class="page_content profile"><article class="profile_content"><header class="profile_hero">${titleHtml}${subtitleHtml}</header><section class="profile_section profile_about">${paragraphsHtml}</section>${sectionsHtml}</article>${profileStyles}</div>`;
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
