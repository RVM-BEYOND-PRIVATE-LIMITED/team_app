const { call, get, shared } = require('./wave6a');
const { uuid } = require('./fixtures');

/**
 * Wave 9 (Phase 2D): the leaders' overview (H5) and the approval chain (D4). One entry per
 * documented status of every route the phase adds. tests/contract.test.js merges it with the
 * earlier waves: the routes covered must be exactly the routes the app serves, and every
 * documented status must be provoked here.
 *
 * The scenarios run on the same in-memory app and fixtures as the other waves (tests/helpers/
 * app.js buildApp), so a request here is the real route, the real store and the real contract.
 */

const AID = (n) => `7c000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const BID = (n) => `8d000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const SID = (n) => `9e000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

/** The faculty fixture's account carries this faculty record (tests/helpers/fixtures.js). */
const FACULTY_ID = uuid('f', 11);
const OTHER_FACULTY_ID = uuid('f', 4);

/** One morning batch the faculty owns and one evening batch they cover, both running on Fridays. */
const TEACHING = (w) => {
  w.tables.batches = [
    { id: BID(1), name: 'CAD Morning Batch', faculty_id: FACULTY_ID, start_date: '2026-10-01', end_date: '2026-12-31',
      start_time: '09:00:00', end_time: '11:00:00', days_of_week: ['Friday'], schedule: [5], location_id: 1 },
    { id: BID(2), name: 'AutoCAD Evening Batch', faculty_id: OTHER_FACULTY_ID, start_date: '2026-10-01', end_date: '2026-12-31',
      start_time: '18:00:00', end_time: '20:00:00', days_of_week: [], schedule: [5], location_id: 2 },
  ];
  w.tables.faculty_substitutions = [
    { id: BID(9), batch_id: BID(2), original_faculty_id: OTHER_FACULTY_ID,
      substitute_faculty_id: FACULTY_ID, start_date: '2026-10-01', end_date: '2026-10-31' },
  ];
  w.tables.batch_students = [
    { batch_id: BID(1), student_id: SID(1), joined_at: '2026-09-01T00:00:00+00:00' },
    { batch_id: BID(1), student_id: SID(2), joined_at: '2026-09-01T00:00:00+00:00' },
    { batch_id: BID(1), student_id: SID(3), joined_at: null },
    { batch_id: BID(2), student_id: SID(4), joined_at: '2026-09-15T00:00:00+00:00' },
  ];
  w.tables.student_attendance = [
    { batch_id: BID(1), student_id: SID(1), date: '2026-10-16', is_present: true },
  ];
  w.tables.hold_periods = [
    { student_id: SID(1), hold_start: '2026-10-10', hold_end: null, hold_category: null, hold_remarks: null, applied_by: null },
  ];
  w.tables.pending_alerts = [
    { id: SID(8), batch_id: BID(1), student_id: SID(2), date: '2026-10-16', alert_type: 'absent_remarks_missing', is_resolved: false },
    { id: SID(9), batch_id: BID(1), student_id: SID(2), date: '2026-10-16', alert_type: 'absent_remarks_missing', is_resolved: true },
  ];
};

/** One pending on-duty request from the attendance employee, whose line starts at the admin manager. */
const REQUESTS = (w) => {
  w.tables.hr_ess_attendance_requests = [{
    id: AID(1),
    employee_id: w.people.attendance.employee.id,
    type: 'on_duty',
    status: 'pending',
    day: '2026-10-15',
    reason: 'Client visit at the Pune centre.',
    place: 'Pune centre',
    fix_in: null,
    fix_out: null,
    minutes: null,
    day_before: null,
    day_written_at: null,
    decided_by_employee_id: null,
    decided_by_user_id: null,
    decided_by_name: null,
    decided_at: null,
    decision_note: null,
    cancelled_by_user_id: null,
    cancelled_by_name: null,
    cancelled_at: null,
    cancel_reason: null,
    created_at: '2026-10-14T05:00:00+00:00',
    updated_at: '2026-10-14T05:00:00+00:00',
  }];
};

const CHAIN = `/api/ess/approvals/attendance/${AID(1)}/chain`;
const OVERVIEW = '/api/ess/leaders/overview';

const WAVE_9 = {
  'GET /api/ess/approvals/{family}/{id}/chain': [
    ['200, the requester reads their own chain', call('attendance', get(CHAIN), { setup: REQUESTS })],
    ['200, a manager on the chain', call('admin_manager', get(CHAIN), { setup: REQUESTS })],
    ['200, HR-wide', call('hr', get(CHAIN), { setup: REQUESTS })],
    ['400 VALIDATION_FAILED, not an id', call('hr', get('/api/ess/approvals/attendance/nope/chain'), { setup: REQUESTS })],
    ['403 NOT_AN_APPROVER, somebody outside the line', call('faculty', get(CHAIN), { setup: REQUESTS })],
    ['404 NOT_FOUND, no such request', call('hr', get(`/api/ess/approvals/attendance/${AID(9)}/chain`), { setup: REQUESTS })],
    ['404 NOT_FOUND, no such family', call('hr', get(`/api/ess/approvals/wall/${AID(1)}/chain`), { setup: REQUESTS })],
    ...shared('hr', 'get', CHAIN, { table: 'hr_ess_attendance_requests', seed: REQUESTS }),
  ],
  'GET /api/ess/leaders/overview': [
    ['200, the CEO', call('ceo', get(OVERVIEW))],
    ['200, a super admin', call('super_admin', get(OVERVIEW))],
    ['403 HR_ACCESS_DENIED, any other role', call('hr', get(OVERVIEW))],
    ['403 PORTAL_LOGIN_REQUIRED, an attendance session', call('attendance', get(OVERVIEW))],
    ...shared('ceo', 'get', OVERVIEW, { table: 'hr_staff_attendance' }),
  ],
  'GET /api/ess/me/faculty-day': [
    ['200, a teaching day', call('faculty', get('/api/ess/me/faculty-day'), { setup: TEACHING })],
    ['400 VALIDATION_FAILED, not a calendar day', call('faculty', get('/api/ess/me/faculty-day?date=26-10'), { setup: TEACHING })],
    ['400 DAY_OUT_OF_RANGE, a day long past', call('faculty', get('/api/ess/me/faculty-day?date=2026-08-01'), { setup: TEACHING })],
    ['403 NOT_FACULTY, a login with no faculty record', call('hr', get('/api/ess/me/faculty-day'), { setup: TEACHING })],
    ['403 NOT_FACULTY, an attendance session', call('attendance', get('/api/ess/me/faculty-day'), { setup: TEACHING })],
    ...shared('faculty', 'get', '/api/ess/me/faculty-day', { table: 'student_attendance', seed: TEACHING }),
  ],
};

module.exports = { WAVE_9, AID, TEACHING, FACULTY_ID };
