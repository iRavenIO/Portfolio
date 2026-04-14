import Head from "next/head";

export default function NotFoundPage({ legacyHtml, head }) {
  const canonicalBase = String(head.canonical_url || "").replace(/\/?$/, "/");
  const canonical404 = `${canonicalBase}404/`;

  return (
    <>
      <Head>
        <title>404 — Page Not Found | {head.og_site_name}</title>
        <meta name="viewport" content="width=device-width,initial-scale=1" />
        <meta name="description" content="The page you are looking for does not exist." />
        <link rel="canonical" href={canonical404} />
        <meta property="og:locale" content={head.og_locale} />
        <meta property="og:type" content={head.og_type} />
        <meta property="og:site_name" content={head.og_site_name} />
        <meta property="og:title" content="404 — Page Not Found" />
        <meta property="og:description" content="The page you are looking for does not exist." />
        <meta property="og:url" content={canonical404} />
        <meta property="og:image" content={head.share_image_url} />
        <meta property="og:image:type" content={head.share_image_type} />
        <meta property="og:image:width" content={head.share_image_width} />
        <meta property="og:image:height" content={head.share_image_height} />
        <meta name="twitter:card" content={head.twitter_card} />
        {head.google_meta.map((content) => (
          <meta key={`google-${content}`} name="google" content={content} />
        ))}
        <meta name="robots" content="noindex,follow" />
        <link rel="stylesheet" href={head.stylesheet_path} />
        <link rel="icon" href={head.favicon_path} />
        <link rel="apple-touch-icon" href={head.apple_touch_icon_path} />
      </Head>

      <div
        style={{ display: "contents" }}
        dangerouslySetInnerHTML={{ __html: legacyHtml }}
        suppressHydrationWarning
      />
    </>
  );
}

export async function getStaticProps() {
  const { buildHeadProps, buildNotFoundLegacyMarkup, loadSiteContent } = await import(
    "../lib/siteContent.server"
  );
  const siteContent = loadSiteContent();

  return {
    props: {
      legacyHtml: buildNotFoundLegacyMarkup(siteContent),
      head: buildHeadProps(siteContent)
    }
  };
}
