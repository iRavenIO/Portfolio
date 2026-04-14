# Next Static Migration Design

## Summary

Convert the current static portfolio site into a Next.js Pages Router app that renders the same HTML, CSS, and JS, while adding file-based routing and static export output. The migration preserves the existing visual layout, runtime behavior, and asset paths, with the only acceptable markup differences being Next.js required artifacts like the `__NEXT_DATA__` script, the `#__next` wrapper, a neutral legacy wrapper element (rendered with `display: contents`), and inert `data-nextjs` attributes.

## Goals

- Preserve current appearance and behavior (theme toggle, font toggle, canvas animation, nav highlighting).
- Keep routing at `/`, `/projects/`, `/info/`, `/contact/` with trailing slashes.
- Ship as a static export (no server required), compatible with current hosting patterns.
- Minimize risk by avoiding JSX conversion of the legacy markup.

## Non-Goals

- Rewriting the UI into React components.
- Changing content, styling, or interaction behavior.
- Adding new pages or functionality.

## Current State

- Static `index.html` defines all markup, head metadata, and script tags.
- Styles are in `assets/css/style.css` and fonts/images in `assets/`.
- Behavior is provided by `assets/js/main.js` (minified bundle).
- Routing today is handled by the host via `try_files $uri $uri/ /index.html`.

## Proposed Approach

### Dependencies

- Use Next.js >= 13.4 (required for `output: "export"` and `trailingSlash`).

### Routing

- Use Next Pages Router with a single catch-all page: `pages/[[...slug]].js`.
- `getStaticPaths` returns the four known routes:

```js
return {
  paths: [
    { params: { slug: [] } },
    { params: { slug: ["projects"] } },
    { params: { slug: ["info"] } },
    { params: { slug: ["contact"] } }
  ],
  fallback: false
};
```

- `getStaticProps` returns `{ props: {} }` since the page renders static markup from `legacyBodyHtml`.

### HTML Rendering

- Keep the legacy body markup as a raw HTML string.
- Store the string in `lib/legacyMarkup.js` as `legacyBodyHtml` and import it into `pages/[[...slug]].js`.
- Source the string by copying the `<body>` contents from `index.html`, excluding the two script tags at the end. The string starts at `<div id="EnterView">` and ends after the closing `</div>` of `#Page`. After migration, `lib/legacyMarkup.js` is the single source of truth and `index.html` remains a reference snapshot only.
- Render it with `dangerouslySetInnerHTML` to preserve attributes like `class`, `x-data`, `@click`, and `:class` exactly as-is.
- Wrap the legacy HTML with a neutral `<div>` that has no class or id and `style={{ display: "contents" }}`; apply `suppressHydrationWarning` only if warnings appear.
- Do not convert the markup to JSX to avoid breaking custom attributes or Alpine-style directives.
- Store the HTML as a template literal with no interpolation; if future updates add backticks or `${`, escape them or switch to `String.raw`.

### Head and Scripts

- Add `pages/_document.js` to set `<Html lang="en">` and reproduce the current `<head>` contents.
- Include canonical, OpenGraph, Twitter, and icon tags exactly as in the current `index.html` for all routes (no per-route variation).
- Load the stylesheet via `<link rel="stylesheet" href="/assets/css/style.css">`.
- Add the `main.js` script tag followed by the async gtag loader and the inline gtag init script, preserving the exact ordering from `index.html`.
- Insert these three script tags in `pages/_document.js` immediately after `<Main />` and before `<NextScript />` so they remain at the end of `<body>` and before any Next-generated scripts.
- The inline gtag init script is inserted via `dangerouslySetInnerHTML` in `_document.js` to keep the script content identical.

### Legacy Head Block (Verbatim)

The `<head>` contents copied into `_document.js` are:

```html
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Kousha Ghodsizad</title>
<meta name="description" content="Software Architecture and Engineer Amsterdam">
<link rel="canonical" href="https://kousha.dev">
<meta property="og:locale" content="nl_nl">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Kousha Ghodsizad">
<meta property="og:title" content="Kousha Ghodsizad">
<meta property="og:description" content="Software Architecture and Engineer">
<meta property="og:url" content="https://kousha.dev">
<meta property="og:image" content="https://kousha.dev/assets/share-image.png">
<meta property="og:image:type" content="image/png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<meta name="google" content="nositelinkssearchbox">
<meta name="google" content="notranslate">
<link rel="stylesheet" href="/assets/css/style.css">
<link rel="icon" href="/assets/favicon.png">
<link rel="apple-touch-icon" href="/assets/favicon.png">
```

### Static Export

- `next.config.js` sets `output: "export"` and `trailingSlash: true`.
- Keep default Next runtime JS; the page renders a static `dangerouslySetInnerHTML` string so hydration should be stable.
- If hydration warnings appear, add `suppressHydrationWarning` to the wrapper element around the legacy HTML.

### Deployment and 404 Behavior

- Deploy the `out/` directory produced by `next build` (static export output).
- The host should serve `out/` as the web root; the repo-root `index.html` is not deployed or used by the host.
- Keep the current host fallback (`try_files $uri $uri/ /index.html`) so unknown routes load `out/index.html`, matching current behavior. The generated `404.html` is not used under this configuration.
- On hosts that cannot rewrite to `/index.html`, unknown routes will serve `404.html` instead; this is acceptable but not identical to current behavior.

### Assets

- Move `assets/` to `public/assets/` unchanged to keep `/assets/...` URLs working.

## File Layout (Planned)

- `package.json` (Next + scripts)
- `next.config.js`
- `pages/[[...slug]].js`
- `pages/_document.js`
- `public/assets/` (moved from `assets/`)
- Keep the original `index.html` at repo root as a reference (unused by Next).

## Risks and Mitigations

- **DOM mismatch / hydration warnings:** keep legacy HTML in a static `dangerouslySetInnerHTML` string; add `suppressHydrationWarning` on the wrapper if any warnings appear.
- **Broken asset paths:** keep `/assets/...` paths and move assets to `public/assets/`.
- **Script ordering changes:** keep script tags at end of `<body>` in the same order as today.
- **Trailing slash differences:** enable `trailingSlash: true` and prebuild static routes with slashes.
- **`#__next` wrapper side effects:** verify CSS/JS do not rely on direct body children; if needed, add `#__next { display: contents; }` to preserve layout/DOM expectations.

## Verification

- `npm install`
- `npm run dev` and verify `/`, `/projects/`, `/info/`, `/contact/`.
- Check theme toggle, font toggle, canvas animation, and nav highlight state.
- `npm run build` and `npx serve out` to confirm static export works.
- One-time parity check: confirm `lib/legacyMarkup.js` matches the `<body>` contents from `index.html` (excluding script tags).
- DOM structure check: verify CSS/JS behavior with `#__next` wrapper; apply `#__next { display: contents; }` if any direct-child assumptions are found.
