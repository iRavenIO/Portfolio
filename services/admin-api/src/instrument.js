/*
 * Sentry/GlitchTip instrumentation for the portfolio admin-api Node service.
 *
 * Required at the very top of `server.js` (before any other require) so the
 * Sentry SDK can install its global error hooks before the HTTP server is
 * constructed.
 *
 * Server-side DSN comes from the in-cluster GlitchTip service via the
 * `SENTRY_DSN` env var (injected by the Helm chart's ExternalSecret). When
 * unset the SDK call no-ops, so the admin-api still boots in local dev.
 */

const Sentry = require("@sentry/node");
const { makeScrubber } = require("../../../lib/sentry-scrub");

const dsn = process.env.SENTRY_DSN;

if (dsn) {
  Sentry.init({
    dsn,
    environment: process.env.SENTRY_ENVIRONMENT || process.env.NODE_ENV,
    release: process.env.SENTRY_RELEASE,
    tracesSampleRate: 0,
    sendDefaultPii: false,
    beforeSend: makeScrubber("kousha-admin-api"),
  });
}

module.exports = Sentry;
