const crypto = require('crypto');
const { HttpError, MESSAGES, asyncRoute, notAuthenticated } = require('../lib/errors');
const { istDay } = require('../lib/time');
const { isActive } = require('../policy/employment');
const { isStaffRole } = require('../policy/staff');
const { sessionProblem, passwordChangeDue } = require('../middleware/employeeAuth');
const P = require('../policy/sessions');
const T = require('../lib/accessTokens');

/**
 * Staying signed in (task A3; KP, 16 Oct 2026). The flow is in docs/04-build-plan.md, Wave 2, and
 * the numbers in policy/sessions.js.
 *
 *   POST   /api/ess/session            trade a fresh Scheduler sign-in for a kept one
 *   POST   /api/ess/session/refresh    a refresh token for the next access and refresh token
 *   POST   /api/ess/session/sign-out   end a kept sign-in
 *   GET    /api/ess/sessions           my kept sign-ins
 *   DELETE /api/ess/sessions/:id       end one of mine
 *
 * A kept sign-in is a family of hr_ess_sessions rows, one per refresh token, and its id is the
 * family's. Every write to a live row goes through the migration's two functions, which lock the
 * family, so a refresh and a sign-out or a reuse cannot cross: the sign-out always wins.
 *
 * 401 here means the sign-in is over and the app signs out, as everywhere in the ESS; a refused
 * refresh says why in `reason`. A database failure is 503 and ends nothing: every check is read
 * before anything is revoked, and a revoke that fails is not reported as done.
 */

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** What the person is told for each reason a refresh is refused (policy/sessions.js REFUSAL_REASONS). */
const REFUSED = Object.freeze({
  unknown: MESSAGES.SIGN_IN_AGAIN,
  expired: MESSAGES.SESSION_EXPIRED,
  signed_out: MESSAGES.SIGNED_OUT,
  reuse: MESSAGES.SIGNED_OUT_FOR_SAFETY,
  password_changed: MESSAGES.PASSWORD_CHANGED,
  login_off: MESSAGES.ATTENDANCE_LOGIN_OFF,
  left: MESSAGES.NOT_ACTIVE,
  unlinked: MESSAGES.SESSION_UNLINKED,
});

const refused = (reason) => {
  const known = Object.prototype.hasOwnProperty.call(REFUSED, reason) ? reason : 'unknown';
  return new HttpError(401, 'NOT_AUTHENTICATED', REFUSED[known], { reason: known });
};

const unavailable = () => new HttpError(503, 'UNAVAILABLE', MESSAGES.UNAVAILABLE);
const inProgress = () => new HttpError(409, 'REFRESH_IN_PROGRESS', MESSAGES.REFRESH_IN_PROGRESS);
const notFound = () => new HttpError(404, 'NOT_FOUND', MESSAGES.SESSION_NOT_FOUND);

/** PostgREST spells a timestamptz with +00:00; the app always gets one spelling. */
const iso = (value) => new Date(value).toISOString();

function sessionRoutes({ config, store, now }) {
  const hashOf = (refreshToken) => T.refreshTokenHash(refreshToken, config.jwtSecret);

  /** What exchange and refresh both answer: the session, a new access token and the next refresh token. */
  function sessionReply(session, refreshToken, user, nowMs) {
    const access = T.mintAccessToken(session, { user, nowMs, jwtSecret: config.jwtSecret });
    return {
      session: { id: session.family_id, expires_at: iso(session.expires_at) },
      access_token: access.token,
      access_expires_at: access.expiresAt.toISOString(),
      refresh_token: refreshToken,
      login: { kind: session.login_kind, role: user ? user.role ?? null : null, user_id: session.user_id ?? null },
    };
  }

  /**
   * Is the person behind this session still somebody employeeAuth would let in? The same checks in
   * the same order (middleware/employeeAuth.js, from the Scheduler's loadEmployee and
   * sessionProblem), answered as the reason the sign-in ends instead of as a refusal. Plus one the
   * Scheduler lacks: a portal password changed since the sign-in, by a path that stamps
   * users.password_changed_at or by one that does not (policy/sessions.js passwordChangedSince).
   *
   * @returns {Promise<{ problem: string } | { user: object|null }>}
   */
  async function personProblem(session, today) {
    const signedInMs = Date.parse(session.signed_in_at);
    if (session.login_kind === 'attendance') {
      const employee = await store.getEmployeeById(session.employee_id);
      if (!employee || !isActive(employee, today)) return { problem: 'left' };
      const account = await store.getAttendanceAccount(employee.id);
      const problem = sessionProblem({ issuedAt: signedInMs }, account);
      // A cut-off the database could not give in a readable form is the server's fault: 503.
      if (problem && problem.status === 503) throw problem;
      if (problem) return { problem: problem.code === 'NO_ATTENDANCE_LOGIN' ? 'login_off' : 'password_changed' };
      // Back on HR's first-time password without a cut-off: the sign-in was made with an older one.
      if (passwordChangeDue({ method: session.method }, account)) return { problem: 'password_changed' };
      return { user: null };
    }
    // Read afresh at every refresh: the next token carries the role and branch as they are now.
    const user = await store.getUserForToken(session.user_id);
    if (!user || !isStaffRole(user.role)) return { problem: 'unlinked' };
    const employee = await store.getEmployeeByUserId(user.id);
    if (!employee || employee.id !== session.employee_id) return { problem: 'unlinked' };
    if (!isActive(employee, today)) return { problem: 'left' };
    const changed = P.passwordChangedSince(user.password_changed_at, signedInMs);
    if (changed === 'unreadable') throw unavailable();
    if (changed) return { problem: 'password_changed' };
    // Three of the Scheduler's password writes leave password_changed_at alone, so the database
    // also compares the hash with the one the sign-in was kept with. Anything but "the same" ends
    // it: a sign-in the database cannot vouch for is not renewed.
    if ((await store.isSessionPasswordCurrent(session.id)) !== true) return { problem: 'password_changed' };
    return { user };
  }

  /**
   * POST /api/ess/session (exchange), behind employeeAuth, so every Wave 1 check has passed:
   * a staff login, linked, on strength, and not on HR's first-time password.
   */
  const exchange = asyncRoute(async (req, res) => {
    const { auth } = req;
    // A token the ESS minted is already a kept sign-in; trading it would start a second family
    // from one sign-in, and with no fresh proof of who is holding the phone.
    if (auth.sessionId) throw new HttpError(409, 'ALREADY_EXCHANGED', MESSAGES.ALREADY_EXCHANGED);
    const at = now();
    const nowMs = at.getTime();
    if (!P.isFreshSignIn(auth.issuedAt, nowMs)) throw new HttpError(403, 'SIGN_IN_NOT_FRESH', MESSAGES.SIGN_IN_NOT_FRESH);

    const body = req.body || {};
    const installId = P.readInstallId(body.install_id);
    if (!installId) throw new HttpError(400, 'BAD_INSTALL_ID', MESSAGES.BAD_INSTALL_ID);
    const label = P.readDeviceLabel(body.device_label);
    if (label.error) throw new HttpError(400, 'BAD_DEVICE_LABEL', MESSAGES.BAD_DEVICE_LABEL);

    let user = null;
    if (auth.kind === 'portal') {
      user = await store.getUserForToken(auth.userId);
      if (!user) throw notAuthenticated(MESSAGES.SIGN_IN_AGAIN);
      if (!isStaffRole(user.role)) throw new HttpError(403, 'NOT_AN_EMPLOYEE', MESSAGES.NOT_AN_EMPLOYEE);
      // Signed in before the password last changed: that sign-in is over, kept or not. A change by
      // a path that leaves password_changed_at alone, inside the ten minutes before the trade, is
      // the one change the ESS cannot see: the fingerprint it keeps is of the new password.
      const changed = P.passwordChangedSince(user.password_changed_at, auth.issuedAt);
      if (changed === 'unreadable') throw unavailable();
      if (changed) throw notAuthenticated(MESSAGES.PASSWORD_CHANGED);
    }

    // The family's id is its first row's, so the sign-in's start is that row's created_at.
    const id = crypto.randomUUID();
    const refreshToken = T.newRefreshToken();
    const session = {
      id,
      family_id: id,
      employee_id: auth.employee.id,
      login_kind: auth.kind,
      user_id: auth.kind === 'portal' ? auth.userId : null,
      location_name: auth.kind === 'portal' ? auth.locationName : null,
      method: auth.kind === 'attendance' ? auth.method : null,
      // The traded token's iat, whole seconds: every token minted from this sign-in carries it.
      signed_in_at: new Date(Math.floor(auth.issuedAt / 1000) * 1000).toISOString(),
      install_id: installId,
      device_label: label.value,
      refresh_hash: hashOf(refreshToken),
      created_at: at.toISOString(),
      last_used_at: at.toISOString(),
      expires_at: new Date(nowMs + P.SESSION_MS).toISOString(),
    };
    // One Scheduler sign-in is kept once. A second trade of the same token is somebody else with a
    // copy of it, or the app retrying an exchange whose answer it lost; either way it signs in again.
    if (!(await store.createSession(session))) throw new HttpError(409, 'ALREADY_EXCHANGED', MESSAGES.SIGN_IN_ALREADY_KEPT);
    res.status(201).json(sessionReply(session, refreshToken, user, nowMs));
  });

  /** POST /api/ess/session/refresh { refresh_token, install_id }, with no bearer. */
  const refresh = asyncRoute(async (req, res) => {
    const at = now();
    const nowMs = at.getTime();
    const body = req.body || {};
    const presented = P.readRefreshToken(body.refresh_token);
    if (!presented) throw refused('unknown');
    // A malformed install id is the app's mistake, not evidence of a stolen token: nothing ends.
    const installId = P.readInstallId(body.install_id);
    if (!installId) throw new HttpError(400, 'BAD_INSTALL_ID', MESSAGES.BAD_INSTALL_ID);

    // Under a rotated JWT_SECRET no hash matches, so every kept sign-in is unknown and ends.
    const row = await store.getSessionByRefreshHash(hashOf(presented));
    if (!row) throw refused('unknown');

    /** Ends the whole family, then answers why. A revoke that fails is a 503, not a 401. */
    const endFamily = async (reason) => {
      await store.revokeFamily({ familyId: row.family_id, reason, at: at.toISOString() });
      return refused(reason);
    };
    const expired = (session) => !(Date.parse(session.expires_at) > nowMs);

    if (row.revoked_at) {
      if (row.revoked_reason !== 'rotated') throw refused(row.revoked_reason);
      // A token already traded in. If its family has ended since, there is nothing left to end.
      const head = await store.getLiveSession(row.family_id);
      if (!head) throw refused('reuse');
      if (expired(head)) throw await endFamily('expired');
      // The same install, moments later: the app lost track of a refresh it made (two calls at
      // once). It retries with its newest token. Anything else is somebody else holding a copy.
      if (installId === row.install_id && nowMs - Date.parse(row.revoked_at) <= P.REFRESH_RETRY_MS) throw inProgress();
      throw await endFamily('reuse');
    }

    if (expired(row)) throw await endFamily('expired');
    // The token was issued to one install; presented by another, it has been copied.
    if (installId !== row.install_id) throw await endFamily('reuse');

    const checked = await personProblem(row, istDay(at));
    if (checked.problem) throw await endFamily(checked.problem);

    const nextId = crypto.randomUUID();
    const nextToken = T.newRefreshToken();
    const rotated = await store.rotateSession({
      sessionId: row.id,
      newId: nextId,
      refreshHash: hashOf(nextToken),
      at: at.toISOString(),
      expiresAt: new Date(nowMs + P.SESSION_MS).toISOString(),
    });
    // Another refresh with this same token got there first: the app uses the newest one it has.
    if (!rotated) throw inProgress();
    res.json(sessionReply({ ...row, expires_at: rotated.expires_at }, nextToken, checked.user, nowMs));
  });

  /**
   * POST /api/ess/session/sign-out with { refresh_token }: ends that token's family, with no
   * bearer needed, because the access token may have run out already. 204 whether or not there
   * was anything to end, so it answers nothing about a token. Without a refresh token the request
   * goes on to employeeAuth and signOut below.
   */
  const signOutWithRefreshToken = asyncRoute(async (req, res, next) => {
    const body = req.body || {};
    if (body.refresh_token === undefined || body.refresh_token === null) return next();
    const presented = P.readRefreshToken(body.refresh_token);
    const row = presented ? await store.getSessionByRefreshHash(hashOf(presented)) : null;
    if (row) await store.revokeFamily({ familyId: row.family_id, reason: 'signed_out', at: now().toISOString() });
    return res.status(204).end();
  });

  /**
   * POST /api/ess/session/sign-out with the bearer access token: ends its family. A Scheduler
   * token carries no family, and the ESS cannot end the Scheduler's own tokens, so there is nothing
   * to do for one: 204 all the same, and the app forgets it.
   */
  const signOut = asyncRoute(async (req, res) => {
    if (req.auth.sessionId) {
      await store.revokeFamily({ familyId: req.auth.sessionId, reason: 'signed_out', at: now().toISOString() });
    }
    res.status(204).end();
  });

  /** GET /api/ess/sessions: the caller's live sign-ins, newest use first. Never another person's. */
  const list = asyncRoute(async (req, res) => {
    const nowMs = now().getTime();
    const live = (await store.listLiveSessions(req.auth.employee.id)).filter((s) => Date.parse(s.expires_at) > nowMs);
    const starts = live.length ? await store.listSessionStarts(live.map((s) => s.family_id)) : [];
    const startOf = new Map(starts.map((r) => [r.id, r.created_at]));
    const sessions = live.map((s) => ({
      id: s.family_id,
      device_label: s.device_label ?? null,
      // KP deletes old rows by hand (ADR-0015); a family whose first row is gone began no later
      // than its sign-in.
      created_at: iso(startOf.get(s.family_id) ?? s.signed_in_at),
      last_used_at: iso(s.last_used_at),
      expires_at: iso(s.expires_at),
      current: s.family_id === req.auth.sessionId,
    }));
    sessions.sort((a, b) => b.last_used_at.localeCompare(a.last_used_at) || a.id.localeCompare(b.id));
    res.json({ sessions });
  });

  /**
   * DELETE /api/ess/sessions/:id: ends one of the caller's own sign-ins. Somebody else's, an id that
   * does not exist and one already ended are all the same 404, so ids cannot be probed.
   */
  const end = asyncRoute(async (req, res) => {
    const id = String(req.params.id || '');
    if (!UUID_RE.test(id)) throw notFound();
    const ended = await store.revokeFamily({ familyId: id.toLowerCase(), reason: 'signed_out', at: now().toISOString(), employeeId: req.auth.employee.id });
    if (!ended) throw notFound();
    res.status(204).end();
  });

  return { exchange, refresh, signOutWithRefreshToken, signOut, list, end };
}

module.exports = { sessionRoutes, REFUSED };
