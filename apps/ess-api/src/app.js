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
const { PORTAL_ROLES } = require('./policy/helpdesk');
const { LEADER_ROLES } = require('./policy/leaders');
const dataRequests = require('./routes/dataRequests');
const personal = require('./routes/personal');
const mockLocation = require('./routes/mockLocation');
const devices = require('./routes/devices');
const { attendanceDayRoute } = require('./routes/attendanceDay');
const attendanceRequests = require('./routes/attendanceRequests');
const leaveRequests = require('./routes/leaveRequests');
const approvals = require('./routes/approvals');
const leaders = require('./routes/leaders');
const hrRequests = require('./routes/hrRequests');
const pushDevices = require('./routes/pushDevices');
const notifications = require('./routes/notifications');
const meProfile = require('./routes/meProfile');
const meOrg = require('./routes/meOrg');
const facultyDay = require('./routes/facultyDay');
const classMarking = require('./routes/classMarking');
const team = require('./routes/team');
const wallPosts = require('./routes/wallPosts');
const wallComments = require('./routes/wallComments');
const wallReactions = require('./routes/wallReactions');
const wallPraise = require('./routes/wallPraise');
const wallPolls = require('./routes/wallPolls');
const wallAnnouncements = require('./routes/wallAnnouncements');
const wallCelebrations = require('./routes/wallCelebrations');
const wallModeration = require('./routes/wallModeration');
const wallSettings = require('./routes/wallSettings');
const helpdeskCategories = require('./routes/helpdeskCategories');
const helpdeskTickets = require('./routes/helpdeskTickets');
const helpdeskQueue = require('./routes/helpdeskQueue');
const documents = require('./routes/documents');
const changeRequests = require('./routes/changeRequests');
const bankDetails = require('./routes/bankDetails');
const idCard = require('./routes/idCard');

/** How long the health check waits for the database before it answers db 'unavailable'. */
const HEALTH_DB_TIMEOUT_MS = 2000;

/** Every request body the ESS takes is a small JSON form; files will arrive as multipart. */
const JSON_BODY_LIMIT = '16kb';

/**
 * The bodies that are lists rather than forms, with their own limit: HR's bulk phone reset takes
 * up to 500 employee ids (about 20 kB of JSON). nginx allows far more (ADR-0019: 12 MB).
 */
const LARGE_JSON_BODIES = Object.freeze({
  '/hr/devices/reset': '32kb',
  // A photo arrives as base64 (the app compresses to under 1 MB first): about 1.4 MB on the wire.
  '/me/photo': '2mb',
  // F9: a Wall post, a praise or an announcement may carry up to five files, each under 1 MB
  // decoded, so the same limit as one photo fits five of them at about 7 MB: nginx allows 12 MB
  // (ADR-0019), and this is the smallest ceiling that takes the full five.
  '/wall/posts': '7mb',
  '/wall/praise': '7mb',
  '/wall/announcements': '7mb',
  // G2: a Helpdesk ticket may carry the same five files as a Wall post.
  '/helpdesk/tickets': '7mb',
  // KP 1 (Phase 2C): one document of up to 5 MB decoded arrives as base64 — about 7 MB on the
  // wire, the same ceiling the five Wall files take.
  '/me/documents': '7mb',
});

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

  // D1, H6: the approvals Inbox, the decision, the archive that clears it for one approver, and
  // D4: the chain one request waits on.
  api.get('/approvals', asEmployee, approvals.listApprovals({ store, now }));
  api.post('/approvals/:family/:id/decide', asEmployee, approvals.decideRequest({ store, now }));
  api.post('/approvals/:family/:id/archive', asEmployee, approvals.archiveRequest({ store, now }));
  api.get('/approvals/:family/:id/chain', asEmployee, approvals.requestChain({ store, now }));

  // H5: the leaders' overview. A portal screen (ceo, super_admin), so an attendance session is
  // refused with PORTAL_LOGIN_REQUIRED before the role check answers HR_ACCESS_DENIED.
  const asLeader = [...asEmployee, requireRoles(LEADER_ROLES, 'HR_ACCESS_DENIED')];
  api.get('/leaders/overview', asLeader, leaders.leadersOverview({ store, now }));

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

  // E1-E12: Me and My Team.
  api.get('/me/profile', asEmployee, meProfile.myProfile({ store }));
  api.put('/me/photo', asEmployee, meProfile.putMyPhoto({ store, now }));
  api.get('/me/org', asEmployee, meOrg.myOrg({ store }));
  // H7: the faculty "my day" and the indicators card (Phase 2D).
  api.get('/me/faculty-day', asEmployee, facultyDay.facultyDayRoute({ store, now }));
  // H1: class marking (Phase 2D, decision 8): the day's eligible roster, the save and a remark.
  api.get('/me/batches/:id/roster', asEmployee, classMarking.classRoster({ store, now }));
  api.post('/me/batches/:id/attendance', asEmployee, classMarking.saveClassAttendance({ store, now }));
  api.patch('/me/batches/:id/attendance/:date/remarks', asEmployee, classMarking.updateClassRemark({ store, now }));
  api.get('/directory', asEmployee, meOrg.directory({ store }));
  api.get('/team/today', asEmployee, team.teamToday({ store, now }));
  api.get('/team/off-this-week', asEmployee, team.teamOffThisWeek({ store, now }));

  /* ── F1-F9: the Wall (Phase 2A) ── */

  // A post and a comment are the two things one person may do in a burst, so each has its own
  // daily bucket on top of the per-employee limit, as the mocked-location reports do.
  const wallPostLimiter = createEmployeeLimiter(limit('wallPosts'), MESSAGES.MODERATION_LIMIT);
  const wallCommentLimiter = createEmployeeLimiter(limit('wallComments'), MESSAGES.MODERATION_LIMIT);
  // Reactions are small and fast: a minute's own bucket, so a stuck phone cannot burn a day.
  const reactionLimiter = createEmployeeLimiter(limit('wallReactions'), MESSAGES.WALL_REACTION_LIMIT);

  // F1, F2: the feed, one post with its thread, the author's edit and delete, and comments.
  api.get('/wall/posts', asEmployee, wallPosts.listWallPosts({ store, now }));
  api.post('/wall/posts', asEmployee, wallPostLimiter, wallPosts.createWallPost({ store, now }));
  api.get('/wall/posts/:id', asEmployee, wallPosts.getWallPost({ store, now }));
  api.patch('/wall/posts/:id', asEmployee, wallPosts.editWallPost({ store, now }));
  api.delete('/wall/posts/:id', asEmployee, wallPosts.deleteWallPost({ store, now }));
  api.post('/wall/posts/:id/comments', asEmployee, wallCommentLimiter, wallComments.createWallComment({ store, now }));
  api.patch('/wall/comments/:id', asEmployee, wallComments.editWallComment({ store, now }));
  api.delete('/wall/comments/:id', asEmployee, wallComments.deleteWallComment({ store, now }));

  // F2: the six reactions, on a post or on a comment, with who reacted.
  api.get('/wall/posts/:id/reactions', asEmployee, wallReactions.listPostReactions({ store }));
  api.put('/wall/posts/:id/reaction', asEmployee, reactionLimiter, wallReactions.putPostReaction({ store, now }));
  api.delete('/wall/posts/:id/reaction', asEmployee, reactionLimiter, wallReactions.deletePostReaction({ store, now }));
  api.get('/wall/comments/:id/reactions', asEmployee, wallReactions.listCommentReactions({ store }));
  api.put('/wall/comments/:id/reaction', asEmployee, reactionLimiter, wallReactions.putCommentReaction({ store, now }));
  api.delete('/wall/comments/:id/reaction', asEmployee, reactionLimiter, wallReactions.deleteCommentReaction({ store, now }));

  // F3: praise, in the feed and on the receiver's own read.
  api.post('/wall/praise', asEmployee, wallPostLimiter, wallPraise.createPraise({ store, now }));
  api.get('/me/praise', asEmployee, wallPraise.listPraise({ store }));

  // F4: a poll after it is up — voting, one more option before the first vote, closing early.
  api.get('/wall/polls/:id', asEmployee, wallPolls.getPoll({ store, now }));
  api.post('/wall/polls/:id/vote', asEmployee, wallPolls.votePoll({ store, now }));
  api.delete('/wall/polls/:id/vote', asEmployee, wallPolls.withdrawPollVote({ store, now }));
  api.post('/wall/polls/:id/options', asEmployee, wallPolls.addPollOption({ store, now }));
  api.post('/wall/polls/:id/close', asEmployee, wallPolls.closePoll({ store, now }));

  // F5: announcements — the sender's tools, and the reader's own list, read state and ack.
  api.post('/wall/announcements', asEmployee, wallPostLimiter, wallAnnouncements.createAnnouncement({ store, now }));
  api.get('/wall/announcements', asEmployee, wallAnnouncements.listAnnouncements({ store }));
  api.get('/wall/hr/announcements', asEmployee, wallAnnouncements.listMyAnnouncements({ store }));
  api.get('/wall/announcements/:id', asEmployee, wallAnnouncements.getAnnouncement({ store }));
  api.patch('/wall/announcements/:id', asEmployee, wallAnnouncements.editAnnouncement({ store, now }));
  api.delete('/wall/announcements/:id', asEmployee, wallAnnouncements.deleteAnnouncement({ store, now }));
  api.post('/wall/announcements/:id/read', asEmployee, wallAnnouncements.readAnnouncement({ store, now }));
  api.post('/wall/announcements/:id/ack', asEmployee, wallAnnouncements.ackAnnouncement({ store, now }));
  api.get('/wall/announcements/:id/counts', asEmployee, wallAnnouncements.announcementCounts({ store }));

  // F6: celebrations, the one-tap wish, and my own birthday switch.
  api.get('/wall/celebrations', asEmployee, wallCelebrations.listCelebrations({ store, now }));
  api.post('/wall/wishes', asEmployee, wallPostLimiter, wallCelebrations.createWish({ store, now }));
  api.get('/me/celebration-optout', asEmployee, wallCelebrations.getOptout({ store }));
  api.put('/me/celebration-optout', asEmployee, wallCelebrations.putOptout({ store, now }));

  // F7: reporting, HR's queue, the hides with their reasons, and the log they leave.
  api.post('/wall/posts/:id/reports', asEmployee, wallModeration.reportPost({ store }));
  api.post('/wall/comments/:id/reports', asEmployee, wallModeration.reportComment({ store }));
  api.get('/wall/hr/reports', asEmployee, wallModeration.listReports({ store }));
  api.post('/wall/hr/reports/:id/resolve', asEmployee, wallModeration.resolveReport({ store, now }));
  api.get('/wall/hr/moderation-log', asEmployee, wallModeration.moderationLog({ store }));
  api.post('/wall/posts/:id/hide', asEmployee, wallModeration.hidePost({ store, now }));
  api.delete('/wall/posts/:id/hide', asEmployee, wallModeration.restorePost({ store }));
  api.post('/wall/comments/:id/hide', asEmployee, wallModeration.hideComment({ store, now }));
  api.delete('/wall/comments/:id/hide', asEmployee, wallModeration.restoreComment({ store }));

  // F8: the rules document.
  api.get('/wall/settings', asEmployee, wallSettings.getWallSettings());

  /* ── G1-G5: the Helpdesk (Phase 2B) ── */

  // G2: a raise is one form, with its own daily bucket on top of the per-employee limit, as the
  // Wall's posts have.
  const helpdeskRaiseLimiter = createEmployeeLimiter(limit('helpdeskTickets'), MESSAGES.HELPDESK_TICKETS_LIMIT);

  // G1: the category list and the rules document, for the raise form.
  api.get('/helpdesk/categories', asEmployee, helpdeskCategories.listHelpdeskCategoriesRoute({ store }));

  // G2: the raise, the raiser's own list, one ticket with its thread, and the moves both sides make.
  api.post('/helpdesk/tickets', asEmployee, helpdeskRaiseLimiter, helpdeskTickets.createTicket({ store, now }));
  api.get('/helpdesk/tickets', asEmployee, helpdeskTickets.listMyTickets({ store, now }));
  api.get('/helpdesk/tickets/:id', asEmployee, helpdeskTickets.getTicket({ store, now }));
  api.post('/helpdesk/tickets/:id/comments', asEmployee, helpdeskTickets.createComment({ store, now }));
  api.post('/helpdesk/tickets/:id/withdraw', asEmployee, helpdeskTickets.withdrawTicket({ store, now }));
  api.post('/helpdesk/tickets/:id/reopen', asEmployee, helpdeskTickets.reopenTicket({ store, now }));
  api.post('/helpdesk/tickets/:id/close', asEmployee, helpdeskTickets.closeTicket({ store, now }));
  api.post('/helpdesk/tickets/:id/claim', asEmployee, helpdeskTickets.claimTicket({ store, now }));
  api.post('/helpdesk/tickets/:id/status', asEmployee, helpdeskTickets.moveTicketStatus({ store, now }));

  // G5: the team's queue. A portal screen, so an attendance session is refused with
  // PORTAL_LOGIN_REQUIRED; a portal role that serves no category is answered an empty queue.
  const asHelpdeskQueue = [...asEmployee, requireRoles(PORTAL_ROLES, 'HR_ACCESS_DENIED')];
  api.get('/helpdesk/queue', asHelpdeskQueue, helpdeskQueue.listQueue({ store, now }));

  // KP 5 (Phase 2C): the team assigns a live ticket to a named handler, and reassigns it.
  api.post('/helpdesk/tickets/:id/assign', asEmployee, helpdeskTickets.assignTicket({ store, now }));

  /* ── Phase 2C: My Documents, profile-change requests, bank details, the ID card ── */

  // KP 1: an upload is one big file, with its own daily bucket on top of the per-employee limit,
  // as the Wall's posts and the Helpdesk's raises have.
  const documentsUploadLimiter = createEmployeeLimiter(limit('documentsUploads'));
  api.get('/me/documents', asEmployee, documents.listMyDocuments({ store }));
  api.post('/me/documents', asEmployee, documentsUploadLimiter, documents.createMyDocument({ store, now }));
  api.get('/me/documents/:id/file', asEmployee, documents.getMyDocumentFile({ store }));

  // E3: my change requests, and HR's queue over them.
  api.get('/me/change-requests', asEmployee, changeRequests.listMyChangeRequests({ store }));
  api.post('/me/change-requests', asEmployee, changeRequests.createMyChangeRequest({ store, now }));
  api.get('/hr/change-requests', asHrRecords, changeRequests.listChangeRequests({ store }));
  api.post('/hr/change-requests/:id/decide', asHrRecords, changeRequests.decideChangeRequest({ store, now }));

  // KP 3: my bank details, and HR's masked, audited read of one person's.
  api.get('/me/bank-details', asEmployee, bankDetails.getMyBankDetails({ store }));
  api.put('/me/bank-details', asEmployee, bankDetails.putMyBankDetails({ store, now }));
  api.get('/hr/employees/:id/bank-details', asHrRecords, bankDetails.getEmployeeBankDetails({ store }));

  // KP 1, KP 2: HR's desk over one person's documents.
  api.get('/hr/employees/:id/documents', asHrRecords, documents.listEmployeeDocuments({ store }));
  api.get('/hr/employees/:id/documents/:documentId/file', asHrRecords, documents.getEmployeeDocumentFile({ store }));
  api.post('/hr/employees/:id/documents/:documentId/verify', asHrRecords, documents.verifyEmployeeDocument({ store, now }));
  api.post('/hr/employees/:id/documents/:documentId/reject', asHrRecords, documents.rejectEmployeeDocument({ store, now }));
  api.delete('/hr/employees/:id/documents/:documentId', asHrRecords, documents.deleteEmployeeDocument({ store }));

  // The ID card: the holder's own card, and the verification link, which takes no token at all
  // and is limited per address instead (as the sign-in is).
  api.get('/me/id-card', asEmployee, idCard.getMyIdCard({ store, config, now }));
  api.get('/id-card/verify/:token', createIpLimiter(limit('idCardVerify')), idCard.verifyIdCard({ store, config, now }));

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
