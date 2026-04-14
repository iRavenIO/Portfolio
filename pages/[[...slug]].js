import Head from "next/head";

export default function LegacyPage({ legacyHtml, head }) {
  return (
    <>
      <Head>
        <title>{head.title}</title>
        <meta name="viewport" content="width=device-width,initial-scale=1" />
        <meta name="description" content={head.description} />
        <link rel="canonical" href={head.canonical_url} />
        <meta property="og:locale" content={head.og_locale} />
        <meta property="og:type" content={head.og_type} />
        <meta property="og:site_name" content={head.og_site_name} />
        <meta property="og:title" content={head.og_title} />
        <meta property="og:description" content={head.og_description} />
        <meta property="og:url" content={head.og_url} />
        <meta property="og:image" content={head.share_image_url} />
        <meta property="og:image:type" content={head.share_image_type} />
        <meta property="og:image:width" content={head.share_image_width} />
        <meta property="og:image:height" content={head.share_image_height} />
        <meta name="twitter:card" content={head.twitter_card} />
        {head.google_meta.map((content) => (
          <meta key={`google-${content}`} name="google" content={content} />
        ))}
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

export async function getStaticProps(context) {
  const { buildHeadProps, buildLegacyMarkup, loadSiteContent, slugToPath } = await import(
    "../lib/siteContent.server"
  );

  const siteContent = loadSiteContent();
  const routePath = slugToPath(context.params?.slug);
  const exists = siteContent.pages.some((page) => page.path === routePath);

  if (!exists) {
    return { notFound: true };
  }

  return {
    props: {
      legacyHtml: buildLegacyMarkup(siteContent),
      head: buildHeadProps(siteContent)
    }
  };
}

export async function getStaticPaths() {
  const { loadSiteContent, pathToSlug } = await import("../lib/siteContent.server");
  const siteContent = loadSiteContent();

  return {
    paths: siteContent.pages.map((page) => ({
      params: {
        slug: pathToSlug(page.path)
      }
    })),
    fallback: false
  };
}
