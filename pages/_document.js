import { Head, Html, Main, NextScript } from "next/document";
import { buildScriptProps, loadSiteContent } from "../lib/siteContent.server";

export default function Document() {
  const siteContent = loadSiteContent();
  const scripts = buildScriptProps(siteContent);
  const lang = siteContent?.site?.lang || "en";

  return (
    <Html lang={lang}>
      <Head />
      <body>
        <Main />
        {scripts.google_tag_id ? (
          <>
            <script
              async
              src={`https://www.googletagmanager.com/gtag/js?id=${scripts.google_tag_id}`}
            ></script>
            <script
              dangerouslySetInnerHTML={{
                __html: `window.dataLayer = window.dataLayer || [];
function gtag(){dataLayer.push(arguments);}
gtag('js', new Date());

gtag('config', '${scripts.google_tag_id}');`
              }}
            ></script>
          </>
        ) : null}
        <NextScript />
        <script defer src={scripts.main_js_path}></script>
      </body>
    </Html>
  );
}
