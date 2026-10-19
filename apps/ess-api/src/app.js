const express = require('express');
const { HttpError, MESSAGES, sendError } = require('./lib/errors');
const { createEmployeeAuth } = require('./middleware/employeeAuth');
const { DEFAULT_LIMITS, createIpLimiter, createEmployeeLimiter, createIdentifierLimiter } = require('./middleware/rateLimit');
const { healthRoute } = require('./routes/health');
const { meRoute } = require('./routes/me');
const { capabilitiesRoute } = require('./routes/capabilities');
const { sessionRoutes } = require('./routes/sessions');
const { signInResolveRoute } = require('./routes/signIn');
const { requireRoles } = require('./middleware/requireRoles');
const { HR_RECORD_ROLES, ATTENDANCE_ROLES } = require('./policy/hrAccess');
const dataRequests = require('./routes/dataRequests');
const personal = require('./routes/personal');
const mockLocation = require('./routes/mockLocation');
const devices = require('./routes/devices');
const { attendanceDayRoute } = require('./routes/attendanceDay');
const attendanceRequests = require('./routes/attendanceRequests');
const leaveRequests = require('./routes/leaveRequests');
const approvals = require('./routes/approvals');
const hrRequests = require('./routes/hrRequests');
const pushDevices = require('./routes/pushDevices');
const notifications = require('./routes/notifications');

/** How long the health check waits for the database before it answers db 'unavailable'. */
const HEALTH_DB_TIMEOUT_MS = 2000;

/** Every request body the ESS takes is a small JSON form; files will arrive as multipart. */
const JSON_BODY_LIMIT = '16kb';

/**
 * The bodies that are lists rather than forms, with their own limit: HR's bulk phone reset takes
 * up to 500 employee ids (about 20 kB of JSON). nginx allows far more (ADR-0019: 12 MB).
 */
const LARGE_JSON_BODIES = Object.freeze({ '/hr/devices/reset': '32kb' });

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
 * @param {object} [deps.limits] tests only: smaller rate limits (any DEFAULT_LIMITS name) and health deadline
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

  const parseJson = express.json({ limit: JSON_BODY_LIMIT });
  // A Map, so no request path can reach an Object prototype property.
  const parseLargeJson = new Map(Object.entries(LARGE_JSON_BODIES).map(([path, limit]) => [path, express.json({ limit })]));
  api.use((req, res, next) => (parseLargeJson.get(req.path) || parseJson)(req, res, next));

  // Sign-in and the per-person limit are attached route by route, not with api.use, so that an
  // unknown address answers 404 whether or not a token came with it.
  const limit = (name) => limits[name] || DEFAULT_LIMITS[name];
  const asEmployee = [
    createEmployeeAuth({ config, store, now }),
    createEmployeeLimiter(limit('perEmployee')),
  ];
  api.get('/me', asEmployee, meRoute({ store }));
  api.get('/me/capabilities', asEmployee, capabilitiesRoute({ config, store, now }));

  // Staying signed in (task A3). Refresh and sign-out by refresh token take no bearer, so they
  // share a strict per-address limit instead; a sign-out with no refresh token falls through to
  // the bearer.
  const sessions = sessionRoutes({ config, store, now });
  const sessionLimiter = createIpLimiter(limit('sessionPerIp'));
  api.post('/session', asEmployee, createEmployeeLimiter(limit('exchangePerEmployee')), sessions.exchange);
  api.post('/session/refresh', sessionLimiter, sessions.refresh);
  api.post('/session/sign-out', sessionLimiter, sessions.signOutWithRefreshToken, asEmployee, sessions.signOut);
  api.get('/sessions', asEmployee, sessions.list);
  api.delete('/sessions/:id', asEmployee, sessions.end);

  // The one-field sign-in (task A5): no token, so limited per address and per identifier.
  api.post(
    '/sign-in/resolve',
    createIpLimiter(limit('signInPerIp')),
    createIdentifierLimiter(limit('signInPerIdentifier')),
    signInResolveRoute({ store, now }),
  );
  // HR's tools: the sign-in, the per-person limit, then the exact-role check
  // (middleware/requireRoles.js; the role sets are policy/hrAccess.js).
  const asHrRecords = [...asEmployee, requireRoles(HR_RECORD_ROLES, 'HR_ACCESS_DENIED')];
  const asAttendanceHr = [...asEmployee, requireRoles(ATTENDANCE_ROLES, 'ATTENDANCE_OVERRIDE_DENIED')];

  // A8: requests to correct or delete my data.
  api.post('/me/data-requests', asEmployee, dataRequests.createMyDataRequest({ store }));
  api.get('/me/data-requests', asEmployee, dataRequests.listMyDataRequests({ store }));
  api.get('/hr/data-requests', asHrRecords, dataRequests.listDataRequests({ store }));
  api.patch('/hr/data-requests/:id', asHrRecords, dataRequests.resolveDataRequest({ store, now }));

  // E9: personal details.
  api.get('/me/personal', asEmployee, personal.getMyPersonal({ store }));
  api.put('/me/personal', asEmployee, personal.putMyPersonal({ store, now }));
  api.get('/hr/employees/:id/personal', asHrRecords, personal.getEmployeePersonal({ store }));
  api.put('/hr/employees/:id/personal', asHrRecords, personal.putEmployeePersonal({ store, now }));

  // B1: one of my days, with the server's clock, the day's note and HR's remark.
  api.get('/attendance/day', asEmployee, attendanceDayRoute({ store, now }));

  // B14: a mocked location the phone refused to punch with, reported for HR.
  const mockReportLimiter = createEmployeeLimiter(limit('mockReports'), MESSAGES.REPORTS_RATE_LIMITED);
  api.post('/attendance/mock-location', asEmployee, mockReportLimiter, mockLocation.reportMockLocation({ store }));
  api.get('/hr/mock-location-reports', asAttendanceHr, mockLocation.listMockLocationReports({ store, now }));

  // B8: registered phones, and HR's bulk reset.
  api.get('/hr/devices', asAttendanceHr, devices.listDevices({ store }));
  api.post('/hr/devices/reset', asAttendanceHr, devices.resetDevices({ store, now }));

  // C1-C5: my requests and balances. The decision itself is the approvals route's.
  api.post('/attendance-requests', asEmployee, attendanceRequests.createMyAttendanceRequest({ store, now }));
  api.get('/attendance-requests', asEmployee, attendanceRequests.listMyAttendanceRequests({ store }));
  api.post('/attendance-requests/:id/withdraw', asEmployee, attendanceRequests.withdrawMyAttendanceRequest({ store, now }));
  api.post('/leave-requests', asEmployee, leaveRequests.createMyLeaveRequest({ store, now }));
  api.get('/leave-requests', asEmployee, leaveRequests.listMyLeaveRequests({ store }));
  api.post('/leave-requests/:id/withdraw', asEmployee, leaveRequests.withdrawMyLeaveRequest({ store, now }));
  api.get('/leave/balances', asEmployee, leaveRequests.myLeaveBalances({ store, now }));

  // D1, H6: the approvals Inbox, the decision, and the archive that clears it for one approver.
  api.get('/approvals', asEmployee, approvals.listApprovals({ store, now }));
  api.post('/approvals/:family/:id/decide', asEmployee, approvals.decideRequest({ store, now }));
  api.post('/approvals/:family/:id/archive', asEmployee, approvals.archiveRequest({ store }));

  // HR's own tools: cancelling an approved request, and the monthly limits.
  api.post('/hr/attendance-requests/:id/cancel', asAttendanceHr, hrRequests.cancelAttendanceRequest({ store, now }));
  api.post('/hr/leave-requests/:id/cancel', asAttendanceHr, hrRequests.cancelLeaveRequest({ store, now }));
  api.get('/hr/request-limits', asAttendanceHr, hrRequests.listRequestLimits({ store }));
  api.put('/hr/request-limits/:type', asAttendanceHr, hrRequests.setRequestLimit({ store, now }));

  // D5: the phone's push registration.
  api.post('/push-devices', asEmployee, pushDevices.registerPushDevice({ store, now }));
  api.delete('/push-devices/:id', asEmployee, pushDevices.revokePushDevice({ store, now }));

  // D6, D8: notifications, their read state, and the categories a person turns off.
  api.get('/notifications', asEmployee, notifications.listNotifications({ store }));
  api.post('/notifications/read-all', asEmployee, notifications.readAllNotifications({ store, now }));
  api.get('/notifications/settings', asEmployee, notifications.getSettings({ store }));
  api.put('/notifications/settings', asEmployee, notifications.putSettings({ store, now }));
  api.post('/notifications/:id/read', asEmployee, notifications.readNotification({ store, now }));

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
    return sendError(res, err.status, err.code, err.message, err.extra);
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

module.exports = { createApp, HEALTH_DB_TIMEOUT_MS, JSON_BODY_LIMIT, LARGE_JSON_BODIES };
