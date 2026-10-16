const express = require('express');
const { HttpError, MESSAGES, sendError } = require('./lib/errors');
const { createEmployeeAuth } = require('./middleware/employeeAuth');
const { DEFAULT_LIMITS, createIpLimiter, createEmployeeLimiter } = require('./middleware/rateLimit');
const { healthRoute } = require('./routes/health');
const { meRoute } = require('./routes/me');
const { capabilitiesRoute } = require('./routes/capabilities');

/** How long the health check waits for the database before it answers db 'unavailable'. */
const HEALTH_DB_TIMEOUT_MS = 2000;

/** Every request body the ESS takes is a small JSON form; files will arrive as multipart. */
const JSON_BODY_LIMIT = '16kb';

/**
 * The ESS as an Express app, with nothing listening yet: server.js listens, and tests build it
 * with an in-memory store and a fixed clock.
 *
 * Everything is under /api/ess: the app calls https://<ESS host>/api/ess (ADR-0019), and the
 * ESS's own nginx block forwards it, path unchanged, to this process on 127.0.0.1:3740.
 *
 * @param {object} deps
 * @param {object} deps.config   from config.js loadConfig
 * @param {object} deps.store    lib/store.js createSupabaseStore, or a test stand-in
 * @param {() => Date} [deps.now]
 * @param {object} [deps.limits] tests only: smaller rate limits and health deadline
 */
function createApp({ config, store, now = () => new Date(), limits = {} } = {}) {
  if (!config) throw new Error('createApp needs the config (config.js loadConfig).');
  if (!store) throw new Error('createApp needs a store (lib/store.js createSupabaseStore).');

  const app = express();
  app.disable('x-powered-by');
  // No ETags: replies are never cached (below), so a 304 for one person's data has no use.
  app.set('etag', false);
  // nginx on the same server is the one proxy in front. `1` and not `true`: trusting the whole
  // chain would let a client write its own X-Forwarded-For and choose its rate-limit bucket.
  // The Scheduler sets the same, for the same reason (server.js:88-100 at c28b9ca).
  app.set('trust proxy', 1);

  app.use((_req, res, next) => {
    // Every reply is about one signed-in person or the server's state at this moment, so no
    // proxy or phone cache may keep it.
    res.set('Cache-Control', 'no-store');
    res.set('X-Content-Type-Options', 'nosniff');
    next();
  });

  // Before anything else, so that requests with no token or a forged one count too.
  app.use(createIpLimiter(limits.perIp || DEFAULT_LIMITS.perIp));

  // Express answers OPTIONS on a known address by itself, with a text/html "GET,HEAD". Nothing
  // here needs OPTIONS (no CORS: the app is not a browser), so it gets the same JSON 404 as any
  // other method an address does not take, and every reply stays JSON.
  app.options('*', (_req, res) => sendError(res, 404, 'NOT_FOUND', MESSAGES.NOT_FOUND));

  const api = express.Router();

  // Before the module switch: the app still needs the minimum version, and the deploy still
  // needs to see the process answer, while everything else is switched off.
  api.get('/health', healthRoute({ config, store, now, timeoutMs: limits.healthDbTimeoutMs || HEALTH_DB_TIMEOUT_MS }));

  // ESS_ENABLED=false and a restart (the deploy writes the setting and restarts the ESS) switch it
  // off with no code change and no database change:
  // the fastest rollback there is. 503 and not 404, so the app can tell "switched off" from
  // "wrong address"; the Scheduler's HR switch does the same (routes/hr.js:57-74).
  api.use((_req, res, next) => (config.essEnabled
    ? next()
    : sendError(res, 503, 'MODULE_DISABLED', MESSAGES.MODULE_DISABLED)));

  api.use(express.json({ limit: JSON_BODY_LIMIT }));

  // Sign-in and the per-person limit are attached route by route, not with api.use, so that an
  // unknown address answers 404 whether or not a token came with it.
  const asEmployee = [
    createEmployeeAuth({ config, store, now }),
    createEmployeeLimiter(limits.perEmployee || DEFAULT_LIMITS.perEmployee),
  ];
  api.get('/me', asEmployee, meRoute({ store }));
  api.get('/me/capabilities', asEmployee, capabilitiesRoute({ config, store, now }));

  app.use('/api/ess', api);

  app.use((_req, res) => sendError(res, 404, 'NOT_FOUND', MESSAGES.NOT_FOUND));
  app.use(errorHandler);
  return app;
}

/** body-parser's own refusals, which carry a status and a type, in the house shape. */
const CLIENT_ERROR_CODES = { 400: 'BAD_REQUEST', 413: 'PAYLOAD_TOO_LARGE', 415: 'UNSUPPORTED_MEDIA_TYPE' };

/**
 * The last stop. Always JSON, never a stack trace: the app shows `error` to staff, and any
 * reply that is not JSON reads to it as "the server is restarting" (ADR-0005). Express knows
 * it for an error handler by its four parameters.
 */
function errorHandler(err, req, res, next) {
  if (res.headersSent) return next(err);
  if (err instanceof HttpError) {
    // RFC 6750: a 401 says which scheme would have worked.
    if (err.status === 401) res.set('WWW-Authenticate', 'Bearer');
    return sendError(res, err.status, err.code, err.message);
  }
  if (err && err.type === 'entity.parse.failed') return sendError(res, 400, 'INVALID_JSON', MESSAGES.INVALID_JSON);
  const status = err && (err.status || err.statusCode);
  if (Number.isInteger(status) && status >= 400 && status < 500) {
    const code = CLIENT_ERROR_CODES[status] || 'BAD_REQUEST';
    return sendError(res, status, code, MESSAGES[code]);
  }
  console.error(`[ess] ${req.method} ${req.path} failed:`, err);
  return sendError(res, 500, 'INTERNAL_ERROR', MESSAGES.INTERNAL_ERROR);
}

module.exports = { createApp, HEALTH_DB_TIMEOUT_MS, JSON_BODY_LIMIT };
