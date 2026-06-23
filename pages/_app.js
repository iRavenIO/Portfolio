import * as Sentry from "@sentry/browser";
import { makeScrubber } from "../lib/sentry-scrub";

// Browser/client DSN is the PUBLIC GlitchTip ingest host. It is NEXT_PUBLIC_ so
// the value is inlined into the client bundle at build time via the Dockerfile
// build-arg. When unset the call below no-ops and the bundle is inert.
const dsn = process.env.NEXT_PUBLIC_SENTRY_DSN;

if (typeof window !== "undefined" && dsn && !window.__SENTRY_INITIALIZED__) {
  Sentry.init({
    dsn,
    environment:
      process.env.NEXT_PUBLIC_SENTRY_ENVIRONMENT || process.env.NODE_ENV,
    release: process.env.NEXT_PUBLIC_SENTRY_RELEASE,
    tracesSampleRate: 0,
    // GlitchTip cannot ingest Session Replay, so it stays disabled and the
    // Replay integration is intentionally omitted below.
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: 0,
    sendDefaultPii: false,
    integrations: [],
    beforeSend: makeScrubber("kousha-web"),
  });
  window.__SENTRY_INITIALIZED__ = true;
}

export default function PortfolioApp({ Component, pageProps }) {
  return <Component {...pageProps} />;
}
