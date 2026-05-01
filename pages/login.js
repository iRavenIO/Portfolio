import fs from "fs";
import path from "path";
import Head from "next/head";

export default function LoginPage({ styleHtml, bodyHtml }) {
  return (
    <>
      <Head>
        <title>Login</title>
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="robots" content="noindex,nofollow" />
        <script
          dangerouslySetInnerHTML={{
            __html: "window.PORTFOLIO_API_BASE='/api/v1';",
          }}
        />
        <style dangerouslySetInnerHTML={{ __html: styleHtml }} />
      </Head>
      <div dangerouslySetInnerHTML={{ __html: bodyHtml }} />
    </>
  );
}

export async function getStaticProps() {
  const adminHtmlPath = path.join(process.cwd(), "services", "admin-api", "public", "index.html");
  const html = fs.readFileSync(adminHtmlPath, "utf8");
  const styleHtml = html.match(/<style>([\s\S]*?)<\/style>/)?.[1] || "";
  const bodyHtml = html.match(/<body>([\s\S]*?)<\/body>/)?.[1] || "";

  return {
    props: {
      styleHtml,
      bodyHtml,
    },
  };
}
