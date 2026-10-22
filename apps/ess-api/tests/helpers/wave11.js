const request = require('supertest');
const { buildApp, tokens } = require('./app');
const { call, get, put } = require('./wave6a');
const { uuid } = require('./fixtures');

/**
 * Wave 11 (KP, 22 Oct 2026): work from home. One entry per documented status of every route it
 * adds: HR's allowance list and save, and the employee's own reading. tests/contract.test.js
 * merges it with the earlier waves, so the routes covered are exactly the routes the app serves
 * and every documented status is provoked here.
 *
 * A request for a WFH day is not a new route: it is `POST /api/ess/leave-requests` with
 * `type: 'wfh'`, whose 409 `WFH_NOT_ALLOWED` and `WFH_LIMIT` are documented on that route.
 */

const ALLOWANCES = '/api/ess/hr/wfh-allowances';
const MINE = '/api/ess/me/wfh';
const NOT_AN_EMPLOYEE = '8f000000-0000-4000-8000-000000000099';

/** One allowance row for the faculty member, as HR's save writes it. */
const WITH_ALLOWANCE = (w) => {
  w.tables.hr_ess_wfh_allowances = [{
    employee_id: w.people.faculty.employee.id,
    is_enabled: true,
    monthly_limit_days: 4,
    note: 'Two days a week while the centre is being painted.',
    set_by_user_id: w.people.hr.user.id,
    set_by_name: 'Test HR Manager',
    created_at: '2026-10-22T06:30:00+00:00',
    updated_at: '2026-10-22T06:30:00+00:00',
  }];
};

const noToken = (method, path, body) => async () => {
  const { app } = buildApp();
  const req = method === 'get' ? request(app).get(path) : request(app).put(path);
  return req.send(body === undefined ? {} : body);
};

const rateLimited = (who, send, options = {}) => async () => {
  const world = buildApp({ ...options, limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
  const token = who === 'attendance' ? tokens.attendance(world.people.attendance) : tokens.portal(world.people[who]);
  await send(world.app, token);
  return send(world.app, token);
};

const WAVE_11 = {
  'GET /api/ess/hr/wfh-allowances': [
    ['200, the allowances HR has set', call('hr', get(ALLOWANCES), { setup: WITH_ALLOWANCE })],
    ['200, a search by name', call('hr', get(`${ALLOWANCES}?q=Faculty`), { setup: WITH_ALLOWANCE })],
    ['400 VALIDATION_FAILED, a search longer than 60 characters', call('hr', get(`${ALLOWANCES}?q=${'a'.repeat(61)}`))],
    ['401, no token', noToken('get', ALLOWANCES)],
    ['403 ATTENDANCE_OVERRIDE_DENIED, an HR Executive', call('hr_executive', get(ALLOWANCES))],
    ['429 RATE_LIMITED', rateLimited('hr', (app, token) => get(ALLOWANCES)(app, token))],
    ['503 MODULE_NOT_INSTALLED', call('hr', get(ALLOWANCES), { prepare: (w) => w.db.dropTable('hr_ess_wfh_allowances') })],
  ],
  'PUT /api/ess/hr/wfh-allowances/{employeeId}': [
    ['200, a new allowance', call('hr', put(`${ALLOWANCES}/${uuid('e', 11)}`, {
      enabled: true, monthly_limit_days: 4, note: 'Two days a week while the centre is being painted.',
    }))],
    ['200, switched off with its limit kept', call('super_admin', put(`${ALLOWANCES}/${uuid('e', 11)}`, {
      enabled: false, monthly_limit_days: 4,
    }), { setup: WITH_ALLOWANCE })],
    ['400 VALIDATION_FAILED, a limit of zero', call('hr', put(`${ALLOWANCES}/${uuid('e', 11)}`, {
      enabled: true, monthly_limit_days: 0,
    }))],
    ['400 VALIDATION_FAILED, a note over 300 characters', call('hr', put(`${ALLOWANCES}/${uuid('e', 11)}`, {
      enabled: true, monthly_limit_days: 4, note: 'x'.repeat(301),
    }))],
    ['401, no token', noToken('put', `${ALLOWANCES}/${uuid('e', 11)}`, { enabled: true, monthly_limit_days: 4 })],
    ['403 ATTENDANCE_OVERRIDE_DENIED, an Admin Manager', call('admin_manager', put(`${ALLOWANCES}/${uuid('e', 11)}`, {
      enabled: true, monthly_limit_days: 4,
    }))],
    ['404 EMPLOYEE_NOT_FOUND', call('hr', put(`${ALLOWANCES}/${NOT_AN_EMPLOYEE}`, {
      enabled: true, monthly_limit_days: 4,
    }))],
    ['429 RATE_LIMITED', rateLimited('hr', (app, token) => put(`${ALLOWANCES}/${uuid('e', 11)}`, {
      enabled: true, monthly_limit_days: 4,
    })(app, token))],
    ['503 MODULE_NOT_INSTALLED', call('hr', put(`${ALLOWANCES}/${uuid('e', 11)}`, {
      enabled: true, monthly_limit_days: 4,
    }), { prepare: (w) => w.db.dropTable('hr_ess_wfh_allowances') })],
  ],
  'GET /api/ess/me/wfh': [
    ['200, an enabled allowance', call('faculty', get(MINE), { setup: WITH_ALLOWANCE })],
    ['200, not selected for WFH', call('faculty', get(MINE))],
    ['401, no token', noToken('get', MINE)],
    ['403 NOT_LINKED, a desk login', call('desk', get(MINE))],
    ['429 RATE_LIMITED', rateLimited('faculty', (app, token) => get(MINE)(app, token))],
    ['503 MODULE_NOT_INSTALLED', call('faculty', get(MINE), { prepare: (w) => w.db.dropTable('hr_ess_wfh_allowances') })],
  ],
};

module.exports = { WAVE_11, ALLOWANCES, MINE, WITH_ALLOWANCE };
