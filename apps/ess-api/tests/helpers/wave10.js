const request = require('supertest');
const { buildApp, tokens } = require('./app');
const { call, get, post, patch } = require('./wave6a');
const { uuid } = require('./fixtures');

/**
 * Wave 10 (Phase 2D, decision 8): H1 class marking. One entry per documented status of every
 * route it adds. tests/contract.test.js merges it with the earlier waves: the routes covered are
 * exactly the routes the app serves, and every documented status is provoked here.
 *
 * The scenarios run on the same in-memory app and fake database as the other waves, so each is
 * the real route, the real store and the real contract check.
 */

const BID = (n) => `8d000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const SID = (n) => `9e000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const FACULTY_ID = uuid('f', 11);
const OTHER_FACULTY_ID = uuid('f', 4);
const DAY = '2026-10-16';
const OPEN_DAY = '2026-10-15';

const CLASS = (w) => {
  const row = (n, facultyId, locationId, name) => ({
    id: BID(n), name, faculty_id: facultyId, start_date: '2026-10-01', end_date: '2026-12-31',
    start_time: '09:00:00', end_time: '11:00:00', days_of_week: ['Friday'], schedule: [5], location_id: locationId,
  });
  w.tables.batches = [
    row(1, FACULTY_ID, 1, 'CAD Morning Batch'),
    row(2, OTHER_FACULTY_ID, 2, 'AutoCAD Evening Batch'),
    row(3, OTHER_FACULTY_ID, 2, 'Pune Weekend Batch'),
  ];
  w.tables.faculty_substitutions = [{
    id: BID(9), batch_id: BID(2), original_faculty_id: OTHER_FACULTY_ID,
    substitute_faculty_id: FACULTY_ID, start_date: '2026-10-01', end_date: '2026-10-31',
  }];
  w.tables.batch_students = [
    { batch_id: BID(1), student_id: SID(1), joined_at: '2026-09-01T00:00:00+00:00' },
    { batch_id: BID(1), student_id: SID(2), joined_at: '2026-09-01T00:00:00+00:00' },
    { batch_id: BID(1), student_id: SID(3), joined_at: null },
    { batch_id: BID(2), student_id: SID(4), joined_at: '2026-09-15T00:00:00+00:00' },
  ];
  w.tables.students = [
    { id: SID(1), name: 'Aarav Sharma', admission_number: 'ADM-001', is_on_hold: false, hold_applied_at: null },
    { id: SID(2), name: 'Diya Patel', admission_number: 'ADM-002', is_on_hold: false, hold_applied_at: null },
    { id: SID(3), name: 'Kabir Singh', admission_number: 'ADM-003', is_on_hold: false, hold_applied_at: null },
    { id: SID(4), name: 'Ananya Das', admission_number: 'ADM-004', is_on_hold: false, hold_applied_at: null },
  ];
  w.tables.admissions = [
    { student_id: SID(1), joined: true },
    { student_id: SID(2), joined: true },
    { student_id: SID(4), joined: true },
  ];
  w.tables.student_attendance = [
    { batch_id: BID(1), student_id: SID(1), date: DAY, is_present: true, absent_reason: null, follow_up_comment: null },
    { batch_id: BID(1), student_id: SID(2), date: DAY, is_present: false, absent_reason: null, follow_up_comment: null },
  ];
  w.tables.pending_alerts = [
    { id: SID(20), batch_id: BID(1), student_id: SID(2), date: DAY, alert_type: 'absent_remarks_missing',
      is_resolved: false, resolved_at: null, resolved_by: null, location_id: 1 },
  ];
};

const ROSTER = (id, day = DAY) => `/api/ess/me/batches/${id}/roster?date=${day}`;
const SAVE = (id) => `/api/ess/me/batches/${id}/attendance`;
const REMARK = (id, day = DAY) => `/api/ess/me/batches/${id}/attendance/${day}/remarks`;

const as = (people, who) => (who === 'attendance' ? tokens.attendance(people.attendance) : tokens.portal(people[who]));
const mark = (id, present, extra = {}) => ({ student_id: id, present, ...extra });

const noToken = (method, path, body) => async () => {
  const { app } = buildApp();
  const req = method === 'get' ? request(app).get(path) : method === 'post' ? request(app).post(path) : request(app).patch(path);
  return req.send(body === undefined ? {} : body);
};

const rateLimited = (who, send, options = {}) => async () => {
  const world = buildApp({ ...options, limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
  const token = as(world.people, who);
  await send(world.app, token);
  return send(world.app, token);
};

const WAVE_10 = {
  'GET /api/ess/me/batches/{id}/roster': [
    ['200, the batch owner', call('faculty', get(ROSTER(BID(1))), { setup: CLASS })],
    ['200, an admin at the batch\'s branch', call('admin', get(ROSTER(BID(1))), { setup: CLASS })],
    ['400 VALIDATION_FAILED, not a calendar day', call('faculty', get(ROSTER(BID(1), '2026-02-30')), { setup: CLASS })],
    ['401, no token', noToken('get', ROSTER(BID(1)))],
    ['403 CLASS_ROLE_DENIED, HR', call('hr', get(ROSTER(BID(1))), { setup: CLASS })],
    ['403 CLASS_NOT_YOURS, another owner', call('faculty', get(ROSTER(BID(3))), { setup: CLASS })],
    ['403 CLASS_WINDOW, a future day', call('faculty', get(ROSTER(BID(1), '2026-10-17')), { setup: CLASS })],
    ['404 BATCH_NOT_FOUND', call('faculty', get(ROSTER(BID(9))), { setup: CLASS })],
    ['429 RATE_LIMITED', rateLimited('faculty', (app, token) => get(ROSTER(BID(1)))(app, token), { setup: CLASS })],
    ['503 MODULE_NOT_INSTALLED', call('faculty', get(ROSTER(BID(1))), {
      setup: CLASS, prepare: (w) => w.db.dropTable('students'),
    })],
  ],
  'POST /api/ess/me/batches/{id}/attendance': [
    ['200, a day saved', call('faculty', post(SAVE(BID(1)), {
      date: OPEN_DAY,
      attendance: [mark(SID(1), true), mark(SID(2), false, { absent_reason: 'Fever, informed the office.' })],
    }), { setup: CLASS })],
    ['400 VALIDATION_FAILED, a student not on the roster', call('faculty', post(SAVE(BID(1)), {
      date: OPEN_DAY, attendance: [mark(SID(3), true)],
    }), { setup: CLASS })],
    ['400 VALIDATION_FAILED, not a calendar day', call('faculty', post(SAVE(BID(1)), {
      date: '2026-13-01', attendance: [mark(SID(1), true)],
    }), { setup: CLASS })],
    ['401, no token', noToken('post', SAVE(BID(1)), { date: OPEN_DAY, attendance: [mark(SID(1), true)] })],
    ['403 CLASS_ROLE_DENIED, an HR Executive', call('hr_executive', post(SAVE(BID(1)), {
      date: OPEN_DAY, attendance: [mark(SID(1), true)],
    }), { setup: CLASS })],
    ['403 CLASS_NOT_YOURS, another branch', call('admin', post(SAVE(BID(2)), {
      date: OPEN_DAY, attendance: [mark(SID(4), true)],
    }), { setup: CLASS })],
    ['403 CLASS_WINDOW, a future day', call('faculty', post(SAVE(BID(1)), {
      date: '2026-10-17', attendance: [mark(SID(1), true)],
    }), { setup: CLASS })],
    ['404 BATCH_NOT_FOUND', call('admin', post(SAVE(BID(9)), {
      date: OPEN_DAY, attendance: [mark(SID(1), true)],
    }), { setup: CLASS })],
    ['409 CLASS_ALREADY_MARKED, a teaching role', call('faculty', post(SAVE(BID(1)), {
      date: DAY, attendance: [mark(SID(2), true)],
    }), { setup: CLASS })],
    ['429 RATE_LIMITED', rateLimited('faculty', (app, token) => post(SAVE(BID(1)), {
      date: OPEN_DAY, attendance: [mark(SID(1), true)],
    })(app, token), { setup: CLASS })],
    ['503 MODULE_NOT_INSTALLED', call('faculty', post(SAVE(BID(1)), {
      date: OPEN_DAY, attendance: [mark(SID(1), true)],
    }), { setup: CLASS, prepare: (w) => w.db.dropTable('student_attendance') })],
  ],
  'PATCH /api/ess/me/batches/{id}/attendance/{date}/remarks': [
    ['200, the reason filled', call('faculty', patch(REMARK(BID(1)), {
      student_id: SID(2), absent_reason: 'Fever, informed the office.', follow_up_comment: 'Call the parent.',
    }), { setup: CLASS })],
    ['400 VALIDATION_FAILED, a reason too short', call('faculty', patch(REMARK(BID(1)), {
      student_id: SID(2), absent_reason: 'x',
    }), { setup: CLASS })],
    ['400 VALIDATION_FAILED, not a calendar day', call('faculty', patch(REMARK(BID(1), '2026-13-01'), {
      student_id: SID(2), absent_reason: 'Fever, informed the office.',
    }), { setup: CLASS })],
    ['401, no token', noToken('patch', REMARK(BID(1)), {
      student_id: SID(2), absent_reason: 'Fever, informed the office.',
    })],
    ['403 CLASS_ROLE_DENIED, HR', call('hr', patch(REMARK(BID(1)), {
      student_id: SID(2), absent_reason: 'Fever, informed the office.',
    }), { setup: CLASS })],
    ['403 CLASS_NOT_YOURS, another owner', call('faculty', patch(REMARK(BID(3)), {
      student_id: SID(4), absent_reason: 'Fever, informed the office.',
    }), { setup: CLASS })],
    ['403 CLASS_WINDOW, a future day', call('faculty', patch(REMARK(BID(1), '2026-10-17'), {
      student_id: SID(2), absent_reason: 'Fever, informed the office.',
    }), { setup: CLASS })],
    ['404 BATCH_NOT_FOUND', call('faculty', patch(REMARK(BID(9)), {
      student_id: SID(2), absent_reason: 'Fever, informed the office.',
    }), { setup: CLASS })],
    ['409 CLASS_NOT_ABSENT, a present student', call('faculty', patch(REMARK(BID(1)), {
      student_id: SID(1), absent_reason: 'Fever, informed the office.',
    }), { setup: CLASS })],
    ['429 RATE_LIMITED', rateLimited('faculty', (app, token) => patch(REMARK(BID(1)), {
      student_id: SID(2), absent_reason: 'Fever, informed the office.',
    })(app, token), { setup: CLASS })],
    ['503 MODULE_NOT_INSTALLED', call('faculty', patch(REMARK(BID(1)), {
      student_id: SID(2), absent_reason: 'Fever, informed the office.',
    }), { setup: CLASS, prepare: (w) => w.db.dropTable('student_attendance') })],
  ],
};

module.exports = { WAVE_10, CLASS, BID, SID, DAY, OPEN_DAY, FACULTY_ID, OTHER_FACULTY_ID };
