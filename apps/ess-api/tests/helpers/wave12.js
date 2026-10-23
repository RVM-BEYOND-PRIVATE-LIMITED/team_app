const request = require('supertest');
const bcrypt = require('bcryptjs');
const { buildApp, tokens } = require('./app');
const { call, get, post } = require('./wave6a');

/**
 * Wave 12 (issue #10): Account & Security for both sign-in kinds.
 *
 * `GET /api/ess/me/account` answers a portal login from users and an attendance-only login
 * from its HR record. `POST /api/ess/me/password` changes the password each sign-in uses.
 * tests/contract.test.js merges this table with the earlier waves, so every documented status
 * is provoked here.
 */

const ACCOUNT = '/api/ess/me/account';
const PASSWORD = '/api/ess/me/password';
const PORTAL_PASSWORD = 'PortalPass123';
const ATTENDANCE_PASSWORD = 'OldPass123';

const realHashes = (w) => {
  // The app reads db.tables, a copy made when buildApp ran; prepare() must edit that copy.
  const user = w.tables.users.find((u) => u.id === w.people.admin.user.id);
  const account = w.tables.hr_attendance_accounts.find((a) => a.employee_id === w.people.attendance.employee.id);
  user.password_hash = bcrypt.hashSync(PORTAL_PASSWORD, 4);
  account.password_hash = bcrypt.hashSync(ATTENDANCE_PASSWORD, 4);
};

const noToken = (method, path, body) => async () => {
  const { app } = buildApp();
  const req = method === 'get' ? request(app).get(path) : request(app).post(path);
  return req.send(body === undefined ? {} : body);
};

const rateLimited = (who, send) => async () => {
  const world = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
  const token = who === 'attendance' ? tokens.attendance(world.people.attendance) : tokens.portal(world.people[who]);
  await send(world.app, token);
  return send(world.app, token);
};

const WAVE_12 = {
  'GET /api/ess/me/account': [
    ['200, a portal login', call('faculty', get(ACCOUNT))],
    ['200, an attendance-only login', call('attendance', get(ACCOUNT))],
    ['401, no token', noToken('get', ACCOUNT)],
    ['403 NOT_LINKED, a desk login', call('desk', get(ACCOUNT))],
    ['429 RATE_LIMITED', rateLimited('faculty', (app, token) => get(ACCOUNT)(app, token))],
    ['503 MODULE_NOT_INSTALLED', call('faculty', get(ACCOUNT), { prepare: (w) => w.db.dropTable('users') })],
  ],
  'POST /api/ess/me/password': [
    ['200, an attendance password', call('attendance', post(PASSWORD, {
      current_password: ATTENDANCE_PASSWORD, new_password: 'NewPass456', confirm_password: 'NewPass456',
    }), { prepare: realHashes })],
    ['400 INVALID_PASSWORD, too short', call('attendance', post(PASSWORD, {
      current_password: ATTENDANCE_PASSWORD, new_password: 'short', confirm_password: 'short',
    }), { prepare: realHashes })],
    ['400 PASSWORD_MISMATCH, the confirmation differs', call('attendance', post(PASSWORD, {
      current_password: ATTENDANCE_PASSWORD, new_password: 'NewPass456', confirm_password: 'NewPass457',
    }), { prepare: realHashes })],
    ['401, no token', noToken('post', PASSWORD, { new_password: 'NewPass456' })],
    ['401 WRONG_PASSWORD, a wrong current password', call('attendance', post(PASSWORD, {
      current_password: 'not-it', new_password: 'NewPass456', confirm_password: 'NewPass456',
    }), { prepare: realHashes })],
    ['403 NOT_LINKED, a desk login', call('desk', post(PASSWORD, {
      new_password: 'NewPass456', confirm_password: 'NewPass456',
    }))],
    ['409 USE_SCHEDULER, a portal login', call('admin', post(PASSWORD, {
      current_password: PORTAL_PASSWORD, new_password: 'NewPortal456', confirm_password: 'NewPortal456',
    }), { prepare: realHashes })],
    ['429 RATE_LIMITED', rateLimited('attendance', (app, token) => post(PASSWORD, {
      current_password: ATTENDANCE_PASSWORD, new_password: 'NewPass456', confirm_password: 'NewPass456',
    })(app, token))],
    ['503 MODULE_NOT_INSTALLED', call('attendance', post(PASSWORD, {
      current_password: ATTENDANCE_PASSWORD, new_password: 'NewPass456', confirm_password: 'NewPass456',
    }), { prepare: (w) => { realHashes(w); w.db.dropTable('hr_attendance_accounts'); } })],
  ],
};

module.exports = { WAVE_12 };
