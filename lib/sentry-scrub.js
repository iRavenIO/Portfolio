/*
 * Shared Sentry/GlitchTip event scrubber for the Portfolio (kousha.dev).
 *
 * Used by `beforeSend` in the browser bundle (pages/_app.js) and the Node
 * admin-api (services/admin-api/src/instrument.js). Strips credentials and
 * sensitive query parameters, drops request bodies entirely, and tags every
 * event with the originating service so a shared GlitchTip project can
 * distinguish kousha-web from kousha-admin-api.
 *
 * CommonJS so the same file can be `require`d from Node and bundled by
 * webpack for the browser.
 */

const SENSITIVE_QUERY_PARAMS = new Set([
  "token",
  "access_token",
  "refresh_token",
  "api_key",
  "apikey",
  "key",
  "signature",
  "sig",
  "secret",
  "password",
]);

const REDACTED = "[redacted]";

function redactQueryString(queryString) {
  const hasLeadingQuestion = queryString.startsWith("?");
  const raw = hasLeadingQuestion ? queryString.slice(1) : queryString;
  if (raw.length === 0) {
    return queryString;
  }

  const pairs = raw.split(/[&;]/).map((pair) => {
    const eqIndex = pair.indexOf("=");
    if (eqIndex === -1) {
      return pair;
    }
    const rawName = pair.slice(0, eqIndex);
    let decodedName = rawName;
    try {
      decodedName = decodeURIComponent(rawName);
    } catch (_err) {
      // Leave the raw name as-is if it is not valid percent-encoding.
    }
    if (SENSITIVE_QUERY_PARAMS.has(decodedName.toLowerCase())) {
      return `${rawName}=${REDACTED}`;
    }
    return pair;
  });

  const rebuilt = pairs.join("&");
  return hasLeadingQuestion ? `?${rebuilt}` : rebuilt;
}

function redactUrl(url) {
  const queryIndex = url.indexOf("?");
  if (queryIndex === -1) {
    return url;
  }
  const base = url.slice(0, queryIndex);
  const fragmentIndex = url.indexOf("#", queryIndex);
  const query =
    fragmentIndex === -1
      ? url.slice(queryIndex + 1)
      : url.slice(queryIndex + 1, fragmentIndex);
  const fragment = fragmentIndex === -1 ? "" : url.slice(fragmentIndex);
  return `${base}?${redactQueryString(query)}${fragment}`;
}

function makeScrubber(serviceTag) {
  return function scrubEvent(event) {
    const request = event && event.request;
    if (request) {
      // Cookies can carry session/refresh tokens — never send them.
      delete request.cookies;

      if (request.headers) {
        delete request.headers["Authorization"];
        delete request.headers["authorization"];
        delete request.headers["Cookie"];
        delete request.headers["cookie"];
      }

      if (typeof request.query_string === "string") {
        request.query_string = redactQueryString(request.query_string);
      }

      if (typeof request.url === "string") {
        request.url = redactUrl(request.url);
      }

      // Request bodies may contain admin credentials. Drop entirely.
      if ("data" in request) {
        delete request.data;
      }
    }

    event.tags = Object.assign({}, event.tags, { service: serviceTag });
    return event;
  };
}

module.exports = { makeScrubber, redactQueryString, redactUrl };
