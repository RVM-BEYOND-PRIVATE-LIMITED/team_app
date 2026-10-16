const request = require('supertest');
const jwt = require('jsonwebtoken');
const { bearer } = require('./app');
const { INSTALL_ID } = require('./fixtures');
const { NOW } = require('./constants');

/**
 * The session endpoints (task A3) as the app calls them, and a clock a test can move, so a
 * sign-in can be kept, refreshed an hour later and left to expire after 90 days.
 */

const MINUTE = 60 * 1000;
const HOUR = 60 * MINUTE;
const DAY = 24 * HOUR;

/** A clock for buildApp({ now: clock.now }) that starts at `start` and moves when told. */
function clockAt(start = NOW) {
  let t = start.getTime();
  return {
    now: () => new Date(t),
    advance(ms) { t += ms; },
    get ms() { return t; },
  };
}

const keep = (app, token, body = { install_id: INSTALL_ID, device_label: 'Test phone' }) =>
  request(app).post('/api/ess/session').set(bearer(token)).send(body);

const refresh = (app, refreshToken, installId = INSTALL_ID) =>
  request(app).post('/api/ess/session/refresh').send({ refresh_token: refreshToken, install_id: installId });

const signOut = (app, { token, refreshToken } = {}) => {
  const req = request(app).post('/api/ess/session/sign-out');
  if (token) req.set(bearer(token));
  return refreshToken === undefined ? req.send({}) : req.send({ refresh_token: refreshToken });
};

const listSessions = (app, token) => request(app).get('/api/ess/sessions').set(bearer(token));

const endSession = (app, token, id) => request(app).delete(`/api/ess/sessions/${id}`).set(bearer(token));

const me = (app, token) => request(app).get('/api/ess/me').set(bearer(token));

/** A token's claims, read without checking the signature: what the app itself may do with `exp`. */
const claims = (token) => jwt.decode(token);

/** The row behind a session, its family, and what became of it. */
const familyRows = (db, familyId) => db.tables.hr_ess_sessions.filter((r) => r.family_id === familyId);
const liveRows = (db, familyId) => familyRows(db, familyId).filter((r) => r.revoked_at == null);

module.exports = { MINUTE, HOUR, DAY, clockAt, keep, refresh, signOut, listSessions, endSession, me, claims, familyRows, liveRows };
