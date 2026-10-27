const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');

/** Tasks D1 and H6: the approvals Inbox, the decision, the archive, cancel, and the limits. */

const INBOX = '/api/ess/approvals';
const REQ = (n) => `7d000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

const inbox = (app, token, query = '') => request(app).get(`${INBOX}${query}`).set(bearer(token));
const decide = (app, token, family, id, body) => request(app).post(`${INBOX}/${family}/${id}/decide`).set(bearer(token)).send(body);
const archive = (app, token, family, id) => request(app).post(`${INBOX}/${family}/${id}/archive`).set(bearer(token));
const hrCancel = (app, token, family, id, body) => request(app).post(`/api/ess/hr/${family === 'leave' ? 'leave-requests' : 'attendance-requests'}/${id}/cancel`).set(bearer(token)).send(body);
const limits = (app, token) => request(app).get('/api/ess/hr/request-limits').set(bearer(token));
const setLimit = (app, token, type, body) => request(app).put(`/api/ess/hr/request-limits/${type}`).set(bearer(token)).send(body);

/** A request row of either family, as the tables hold it. */
const requestRow = (family, employeeId, n, change = {}) => {
  const common = {
    id: REQ(n),
    employee_id: employeeId,
    type: family === 'leave' ? 'cl' : 'on_duty',
    status: 'pending',
    day: '2026-10-15',
    reason: 'Client visit at the Pune centre.',
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
    ...change,
  };
  if (family === 'attendance') {
    return { place: null, fix_in: null, fix_out: null, ...common };
  }
  return common;
};

/** A day row, for the late marks and the days a fix or an excuse lands on. */
const dayRow = (employeeId, day, change = {}) => ({
  id: `7e000000-0000-4000-8000-${String(day.charCodeAt(9) * 31).padStart(12, '0')}`,
  employee_id: employeeId,
  branch_id: null,
  day,
  status: 'present',
  leave_type: null,
  note: null,
  marked_by: null,
  marked_by_name: 'Test (self punch)',
  marked_at: `${day}T04:00:00+00:00`,
  updated_at: `${day}T12:00:00+00:00`,
  source: 'self_punch',
  first_in: `${day}T04:20:00+00:00`,
  last_out: `${day}T12:40:00+00:00`,
  worked_minutes: 500,
  shift_id: null,
  shift_start: null,
  shift_end: null,
  grace_minutes: null,
  late_minutes: null,
  early_exit_minutes: null,
  late_count: null,
  late_half_day: false,
  late_excused: false,
  late_excused_by_name: null,
  late_excused_reason: null,
  late_excused_at: null,
  ...change,
});

/** One pending request from the attendance employee and one from the faculty member. */
function withTwoRequests(w) {
  w.tables.hr_ess_attendance_requests = [
    requestRow('attendance', w.people.attendance.employee.id, 1, { place: 'Pune centre' }),
  ];
  w.tables.hr_ess_leave_requests = [
    requestRow('leave', w.people.faculty.employee.id, 2, {
      day: '2026-10-15',
      stage: 'manager',
      requires_final_approval: true,
      admin_manager_employee_id: w.people.admin_manager.employee.id,
      admin_manager_name: w.people.admin_manager.employee.full_name,
      is_teaching: false,
    }),
  ];
}

/** A leave request already advanced to the super admin's final stage. */
const finalLeave = (w, n, change = {}) => requestRow('leave', w.people.faculty.employee.id, n, {
  stage: 'final',
  requires_final_approval: true,
  admin_manager_employee_id: w.people.admin_manager.employee.id,
  admin_manager_name: w.people.admin_manager.employee.full_name,
  is_teaching: false,
  ...change,
});

const SUBSTITUTE_ID = '7f000000-0000-4000-8000-000000000001';

/** A substitute faculty row, for the teaching-coverage rule. */
function withSubstitute(w) {
  w.tables.faculty.push({
    id: SUBSTITUTE_ID, email: null, name: 'Test Substitute Faculty', location_id: 1, is_active: true,
  });
}

describe('GET /api/ess/approvals', () => {
  it('an Admin Manager sees their branch\'s pending requests, with the context the brief asks for', async () => {
    const { app, people, db } = buildApp({ setup: withTwoRequests });
    // The attendance employee's own day is a late one (fixture, 2026-10-15): context.late reads it.
    db.tables.hr_staff_attendance.find((d) => d.day === '2026-10-15' && d.employee_id === people.attendance.employee.id).late_minutes = 20;
    const res = await inbox(app, tokens.portal(people.admin_manager));
    expect(res.status).toBe(200);
    expect(res.body.counts).toEqual({ attendance: 1, leave: 1, total: 2 });
    expect(res.body.truncated).toBe(false);
    expect(res.body.requests.map((r) => r.id)).toEqual([REQ(1), REQ(2)]);
    const one = res.body.requests.find((r) => r.id === REQ(1));
    expect(one).toMatchObject({
      id: REQ(1), family: 'attendance', type: 'on_duty', status: 'pending', employee: { id: people.attendance.employee.id },
    });
    expect(one.context.type_this_month).toBe(1);
    expect(one.context.month_limit).toBe(null);
    expect(one.context.late).toEqual({ late_minutes: 20, late_count: 1, late_half_day: false, late_excused: false });
    // The faculty member's pending CL for the same day is "who else is off".
    expect(one.context.others_off).toEqual({ count: 1, names: ['Test CAD Faculty'] });
  });

  it('an HOD no longer sees leave: it waits on the branch Admin Manager', async () => {
    const { app, people } = buildApp({ setup: withTwoRequests });
    const res = await inbox(app, tokens.portal(people.hod));
    expect(res.body.requests).toEqual([]);
    expect(res.body.counts).toEqual({ attendance: 0, leave: 0, total: 0 });
  });

  it('an Admin Manager may filter their own attendance by any status; leave history is not their Inbox', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      withTwoRequests(w);
      w.tables.hr_ess_attendance_requests.push(requestRow('attendance', w.people.attendance.employee.id, 3, {
        status: 'approved', decided_by_name: 'Test Admin Manager', decided_at: '2026-10-15T05:00:00+00:00',
      }));
      w.tables.hr_ess_leave_requests.push(requestRow('leave', w.people.faculty.employee.id, 4, {
        status: 'approved', decided_by_name: 'Test HR Manager', decided_at: '2026-10-15T05:00:00+00:00',
      }));
    } });
    const approved = await inbox(app, tokens.portal(people.admin_manager), '?status=approved');
    expect(approved.status).toBe(200);
    expect(approved.body.requests.map((r) => r.id)).toEqual([REQ(3)]);
    const all = await inbox(app, tokens.portal(people.admin_manager), '?status=all');
    expect(all.status).toBe(200);
    expect(all.body.requests.map((r) => r.id)).toEqual([REQ(1), REQ(3), REQ(2)]);
  });

  it('HR sees attendance everywhere, but not leave where an Admin Manager exists', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      withTwoRequests(w);
      w.tables.hr_ess_attendance_requests.push(requestRow('attendance', w.people.faculty.employee.id, 3, {
        status: 'rejected', decided_by_name: 'Test HR Manager', decided_at: '2026-10-15T05:00:00+00:00', decision_note: 'Not this time.',
      }));
    } });
    const all = await inbox(app, tokens.portal(people.hr));
    expect(all.body.requests.map((r) => r.id)).toEqual([REQ(1)]);
    expect(all.body.counts).toEqual({ attendance: 1, leave: 0, total: 1 });
    const rejected = await inbox(app, tokens.portal(people.super_admin), '?status=rejected');
    expect(rejected.body.requests.map((r) => r.id)).toEqual([REQ(3)]);
    expect(rejected.body.counts.total).toBe(1); // the counts are of what still waits, not of the filter
    // Any other status word is refused.
    expectInvalid(await inbox(app, tokens.portal(people.hr), '?status=lost'), MESSAGES.APPROVAL_STATUS);
  });

  it('an hr_executive is a manager, not an HR decider', async () => {
    const { app, people } = buildApp({ setup: withTwoRequests });
    const res = await inbox(app, tokens.portal(people.hr_executive));
    expect(res.body).toEqual({ counts: { attendance: 0, leave: 0, total: 0 }, requests: [], truncated: false });
    // No reports means a filter is empty, not a 403 (issue #11: the manager owns the filter).
    const filtered = await inbox(app, tokens.portal(people.hr_executive), '?status=all');
    expect(filtered.status).toBe(200);
    expect(filtered.body.requests).toEqual([]);
  });

  it('an attendance session that manages somebody no longer sees leave; the Admin Manager does', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      withTwoRequests(w);
      w.people.faculty.employee.manager_id = w.people.attendance.employee.id;
    } });
    const res = await inbox(app, tokens.attendance(people.attendance));
    expect(res.body.requests).toEqual([]);
  });

  it('archiving clears a request for one approver only', async () => {
    const { app, people } = buildApp({ setup: withTwoRequests });
    expect((await archive(app, tokens.portal(people.hr), 'attendance', REQ(1))).status).toBe(204);
    // Again is the same as once.
    expect((await archive(app, tokens.portal(people.hr), 'attendance', REQ(1))).status).toBe(204);
    expect((await inbox(app, tokens.portal(people.hr))).body.requests).toEqual([]);
    // The Admin Manager's Inbox still holds the branch's attendance and leave requests.
    expect((await inbox(app, tokens.portal(people.admin_manager))).body.requests.map((r) => r.id)).toEqual([REQ(1), REQ(2)]);
    expect((await inbox(app, tokens.portal(people.super_admin))).body.requests.map((r) => r.id)).toEqual([REQ(1)]);
    expectRefusal(await archive(app, tokens.portal(people.faculty), 'attendance', REQ(1)), 403, 'NOT_AN_APPROVER');
    expectRefusal(await archive(app, tokens.portal(people.hr), 'wall', REQ(1)), 404, 'NOT_FOUND');
    expectRefusal(await archive(app, tokens.portal(people.hr), 'attendance', REQ(9)), 404, 'NOT_FOUND');
  });

  it('answers 503 MODULE_NOT_INSTALLED before the requests migration', async () => {
    quietErrors();
    const { app, db, people } = buildApp({ setup: withTwoRequests });
    db.dropTable('hr_ess_attendance_requests');
    expectRefusal(await inbox(app, tokens.portal(people.admin_manager)), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('POST /api/ess/approvals/{family}/{id}/decide', () => {
  it('a manager approves an on-duty day from yesterday: the day is written and the request decided', async () => {
    const { app, people, db } = buildApp({ setup: withTwoRequests });
    const res = await decide(app, tokens.portal(people.admin_manager), 'attendance', REQ(1), { decision: 'approve' });
    expect(res.status).toBe(200);
    expect(res.body.request).toMatchObject({
      id: REQ(1), status: 'approved', decided_by_name: 'Test Admin Manager', employee: { id: people.attendance.employee.id },
    });
    const day = db.tables.hr_staff_attendance.find((d) => d.employee_id === people.attendance.employee.id && d.day === '2026-10-15');
    expect(day).toMatchObject({ status: 'present', note: 'On duty: Pune centre', source: 'override', marked_by_name: 'Test Admin Manager' });
    // The day's own punch times are kept: the request names none.
    expect(day.first_in).toBe('2026-10-15T04:20:00+00:00');
    // The seeded row was not filed through the API, so there is no 'filed' row: this is the
    // decision's own history entry.
    expect(db.tables.hr_ess_attendance_request_history.map((h) => h.action)).toEqual(['approved']);
    // A second decision loses the race, whichever approver makes it.
    expectRefusal(await decide(app, tokens.portal(people.hr), 'attendance', REQ(1), { decision: 'approve' }), 409, 'ALREADY_DECIDED');
  });

  it('a rejection needs a reason, records it, and writes no day', async () => {
    const { app, people, db } = buildApp({ setup: withTwoRequests });
    const before = db.tables.hr_staff_attendance.length;
    expectInvalid(await decide(app, tokens.portal(people.admin_manager), 'attendance', REQ(1), { decision: 'reject' }), MESSAGES.DECIDE_REJECT_NOTE);
    expectInvalid(await decide(app, tokens.portal(people.admin_manager), 'attendance', REQ(1), { decision: 'reject', note: ' x ' }), MESSAGES.DECIDE_REJECT_NOTE);
    const res = await decide(app, tokens.portal(people.admin_manager), 'attendance', REQ(1), { decision: 'reject', note: 'The branch needs him that day.' });
    expect(res.status).toBe(200);
    expect(res.body.request).toMatchObject({ status: 'rejected', decision_note: 'The branch needs him that day.' });
    expect(db.tables.hr_staff_attendance).toHaveLength(before);
  });

  it('the Admin Manager advances leave; only a super admin gives final approval and writes the day', async () => {
    const { app, people, db } = buildApp({ setup: withTwoRequests });
    expectRefusal(await decide(app, tokens.attendance(people.attendance), 'leave', REQ(2), { decision: 'approve' }), 403, 'NOT_AN_APPROVER');
    // HR is not the fallback here: the branch has an active Admin Manager.
    expectRefusal(await decide(app, tokens.portal(people.hr), 'leave', REQ(2), { decision: 'approve' }), 403, 'NOT_AN_APPROVER');
    const advanced = await decide(app, tokens.portal(people.admin_manager), 'leave', REQ(2), { decision: 'approve', note: 'Covered.' });
    expect(advanced.status).toBe(200);
    expect(advanced.body.request).toMatchObject({
      status: 'pending', stage: 'final', manager_approved_by_name: 'Test Admin Manager', manager_remark: 'Covered.',
    });
    // The Admin Manager does not write the leave day; the super admin's final approval does.
    expect(db.tables.hr_staff_attendance.find((d) => d.employee_id === people.faculty.employee.id && d.day === '2026-10-15'))
      .toMatchObject({ status: 'present' });
    expect(db.tables.hr_ess_leave_request_history.map((h) => h.action)).toEqual(['manager_approved']);

    expectRefusal(await decide(app, tokens.portal(people.hr), 'leave', REQ(2), { decision: 'approve' }), 403, 'FINAL_APPROVAL_ONLY');
    expectRefusal(await decide(app, tokens.portal(people.ceo), 'leave', REQ(2), { decision: 'approve' }), 403, 'FINAL_APPROVAL_ONLY');
    const final = await decide(app, tokens.portal(people.super_admin), 'leave', REQ(2), { decision: 'approve', note: 'Final.' });
    expect(final.status).toBe(200);
    expect(final.body.request).toMatchObject({ status: 'approved', decided_by_name: 'Test Super Admin', decision_note: 'Final.' });
    const day = db.tables.hr_staff_attendance.find((d) => d.employee_id === people.faculty.employee.id && d.day === '2026-10-15');
    expect(day).toMatchObject({ status: 'leave', leave_type: 'cl', source: 'override' });
  });

  it('a non-faculty leave is one approval by the reporting manager', async () => {
    const { app, people, db } = buildApp({ setup: (w) => {
      w.tables.hr_ess_leave_requests = [requestRow('leave', w.people.attendance.employee.id, 12, {
        stage: 'final',
        requires_final_approval: true,
        final_approver_employee_id: w.people.admin_manager.employee.id,
        final_approver_name: 'Test Admin Manager',
        is_teaching: false,
      })];
    } });
    const manager = tokens.portal(people.admin_manager);
    expect((await inbox(app, manager)).body.requests.map((r) => r.id)).toContain(REQ(12));
    expectRefusal(await decide(app, tokens.portal(people.super_admin), 'leave', REQ(12), { decision: 'approve' }),
      403, 'FINAL_APPROVAL_ONLY');
    const res = await decide(app, manager, 'leave', REQ(12), { decision: 'approve' });
    expect(res.status).toBe(200);
    expect(res.body.request.status).toBe('approved');
    expect(db.tables.hr_staff_attendance.find((d) => d.employee_id === people.attendance.employee.id
      && d.day === '2026-10-15')).toMatchObject({ status: 'leave', leave_type: 'cl' });
  });

  it('only the named final approver may close the faculty request', async () => {
    const { app, people, db } = buildApp({ setup: (w) => {
      withTwoRequests(w);
      w.tables.hr_ess_leave_requests[0].final_approver_employee_id = w.people.hoo.employee.id;
      w.tables.hr_ess_leave_requests[0].final_approver_name = w.people.hoo.employee.full_name;
    } });
    expect((await decide(app, tokens.portal(people.admin_manager), 'leave', REQ(2), { decision: 'approve' })).status).toBe(200);
    expect((await inbox(app, tokens.portal(people.hoo))).body.requests.map((r) => r.id)).toContain(REQ(2));
    expectRefusal(await decide(app, tokens.portal(people.super_admin), 'leave', REQ(2), { decision: 'approve' }),
      403, 'FINAL_APPROVAL_ONLY');
    const final = await decide(app, tokens.portal(people.hoo), 'leave', REQ(2), { decision: 'approve' });
    expect(final.status).toBe(200);
    expect(final.body.request.status).toBe('approved');
    expect(db.tables.hr_staff_attendance.find((d) => d.employee_id === people.faculty.employee.id
      && d.day === '2026-10-15')).toMatchObject({ status: 'leave', leave_type: 'cl' });
  });

  it('teaching leave needs the substitute faculty and class timing before the Admin Manager may advance it', async () => {
    const { app, people, db } = buildApp({ setup: (w) => {
      withTwoRequests(w);
      withSubstitute(w);
      w.tables.hr_ess_leave_requests[0].is_teaching = true;
    } });
    expectRefusal(
      await decide(app, tokens.portal(people.admin_manager), 'leave', REQ(2), { decision: 'approve' }),
      400, 'COVERAGE_REQUIRED',
    );
    expectRefusal(
      await decide(app, tokens.portal(people.admin_manager), 'leave', REQ(2), {
        decision: 'approve', substitute_faculty_id: '7f000000-0000-4000-8000-000000000099', class_timing: '10:00 to 11:00',
      }),
      400, 'BAD_SUBSTITUTE',
    );
    const ok = await decide(app, tokens.portal(people.admin_manager), 'leave', REQ(2), {
      decision: 'approve', substitute_faculty_id: SUBSTITUTE_ID, class_timing: '10:00 to 11:00',
    });
    expect(ok.status).toBe(200);
    expect(ok.body.request).toMatchObject({
      stage: 'final',
      substitute_faculty_id: SUBSTITUTE_ID,
      substitute_faculty_name: 'Test Substitute Faculty',
      class_timing: '10:00 to 11:00',
    });
    expect(db.tables.hr_ess_leave_request_history.find((h) => h.action === 'manager_approved').details)
      .toMatchObject({ substitute_faculty_id: SUBSTITUTE_ID, class_timing: '10:00 to 11:00' });
  });

  it('HR is the first-stage bypass only for a branch with no Admin Manager; the super admin still closes it', async () => {
    const { app, people, db } = buildApp({ setup: (w) => {
      withTwoRequests(w);
      w.tables.hr_ess_leave_requests.push(requestRow('leave', w.people.pune.employee.id, 10, {
        day: '2026-10-15',
        stage: 'manager',
        requires_final_approval: true,
        admin_manager_employee_id: null,
        admin_manager_name: null,
        is_teaching: false,
      }));
    } });
    const hrInbox = await inbox(app, tokens.portal(people.hr));
    expect(hrInbox.body.requests.map((r) => r.id)).toEqual([REQ(1), REQ(10)]);
    const advanced = await decide(app, tokens.portal(people.hr), 'leave', REQ(10), { decision: 'approve' });
    expect(advanced.status).toBe(200);
    expect(advanced.body.request).toMatchObject({ stage: 'final', manager_approved_by_name: 'Test HR Manager' });
    const final = await decide(app, tokens.portal(people.super_admin), 'leave', REQ(10), { decision: 'approve' });
    expect(final.status).toBe(200);
    expect(final.body.request.status).toBe('approved');
    expect(db.tables.hr_staff_attendance.find((d) => d.employee_id === people.pune.employee.id && d.day === '2026-10-15'))
      .toMatchObject({ status: 'leave', leave_type: 'cl' });
  });

  it('a fix a day keeps the other side of the day and writes the corrected times', async () => {
    const { app, people, db } = buildApp({ setup: (w) => {
      withTwoRequests(w);
      w.tables.hr_staff_attendance.push(dayRow(w.people.attendance.employee.id, '2026-10-14', { status: 'absent', source: 'auto', first_in: '2026-10-14T03:30:00+00:00', last_out: null, worked_minutes: null }));
      w.tables.hr_ess_attendance_requests = [requestRow('attendance', w.people.attendance.employee.id, 4, {
        type: 'fix_a_day', day: '2026-10-14', place: null, fix_out: '18:00', reason: 'I forgot to punch out.',
      })];
    } });
    const res = await decide(app, tokens.portal(people.admin_manager), 'attendance', REQ(4), { decision: 'approve' });
    expect(res.status).toBe(200);
    const day = db.tables.hr_staff_attendance.find((d) => d.employee_id === people.attendance.employee.id && d.day === '2026-10-14');
    expect(day).toMatchObject({ status: 'present', source: 'override', note: 'Fix a day: I forgot to punch out.' });
    expect(day.first_in).toBe('2026-10-14T03:30:00+00:00'); // kept
    expect(day.last_out).toBe('2026-10-14T12:30:00.000Z'); // 18:00 IST
    expect(day.worked_minutes).toBe(540);
  });

  it('an excuse lands on the day; a day that is not late is refused and stays pending', async () => {
    const { app, people, db } = buildApp({ setup: (w) => {
      withTwoRequests(w);
      w.tables.hr_staff_attendance.find((d) => d.day === '2026-10-15' && d.employee_id === w.people.attendance.employee.id).late_minutes = 25;
      w.tables.hr_staff_attendance.push(dayRow(w.people.attendance.employee.id, '2026-10-13'));
      w.tables.hr_ess_attendance_requests = [
        requestRow('attendance', w.people.attendance.employee.id, 5, { type: 'excuse_late', day: '2026-10-15', place: null, reason: 'The bus broke down.' }),
        requestRow('attendance', w.people.attendance.employee.id, 6, { type: 'excuse_late', day: '2026-10-13', place: null, reason: 'On time, I think.' }),
      ];
    } });
    const ok = await decide(app, tokens.portal(people.admin_manager), 'attendance', REQ(5), { decision: 'approve' });
    expect(ok.status).toBe(200);
    const late = db.tables.hr_staff_attendance.find((d) => d.day === '2026-10-15' && d.employee_id === people.attendance.employee.id);
    expect(late).toMatchObject({ late_excused: true, late_excused_by_name: 'Test Admin Manager', late_excused_reason: 'The bus broke down.' });
    expectRefusal(await decide(app, tokens.portal(people.admin_manager), 'attendance', REQ(6), { decision: 'approve' }), 409, 'NOT_LATE');
    expect(db.tables.hr_ess_attendance_requests.find((r) => r.id === REQ(6)).status).toBe('pending');
  });

  it('a second CL in the month is refused with CL_LIMIT at final approval, and the request stays pending', async () => {
    const { app, people, db } = buildApp({ setup: (w) => {
      withTwoRequests(w);
      w.tables.hr_ess_leave_requests = [finalLeave(w, 2)];
      w.tables.hr_staff_attendance.push(dayRow(w.people.faculty.employee.id, '2026-10-10', { status: 'leave', leave_type: 'cl', source: 'override', first_in: null, last_out: null, worked_minutes: null }));
    } });
    expectRefusal(await decide(app, tokens.portal(people.super_admin), 'leave', REQ(2), { decision: 'approve' }), 409, 'CL_LIMIT');
    expect(db.tables.hr_ess_leave_requests.find((r) => r.id === REQ(2)).status).toBe('pending');
  });

  it('last month closes after the 5th but not on it, and a day before last month is out of the window', async () => {
    const seed = (w) => {
      w.tables.hr_ess_leave_requests = [
        finalLeave(w, 7, { day: '2026-09-30', type: 'lwp' }),
        finalLeave(w, 8, { day: '2026-08-31', type: 'lwp' }),
      ];
    };
    const closed = buildApp({ now: new Date('2026-10-06T06:30:00.000Z'), setup: seed });
    expectRefusal(await decide(closed.app, tokens.portal(closed.people.super_admin), 'leave', REQ(7), { decision: 'approve' }), 409, 'REQUEST_CLOSED');
    expectRefusal(await decide(closed.app, tokens.portal(closed.people.super_admin), 'leave', REQ(8), { decision: 'approve' }), 409, 'REQUEST_WINDOW');
    const open = buildApp({ now: new Date('2026-10-05T06:30:00.000Z'), setup: seed });
    expect((await decide(open.app, tokens.portal(open.people.super_admin), 'leave', REQ(7), { decision: 'approve' })).status).toBe(200);
  });

  it('answers 404 and 400 for the wrong addresses and bodies', async () => {
    const { app, people, db } = buildApp({ setup: withTwoRequests });
    const token = tokens.portal(people.hr);
    expectRefusal(await decide(app, token, 'wall', REQ(1), { decision: 'approve' }), 404, 'NOT_FOUND');
    expectRefusal(await decide(app, token, 'attendance', REQ(9), { decision: 'approve' }), 404, 'NOT_FOUND');
    expectInvalid(await decide(app, token, 'attendance', REQ(1), {}), MESSAGES.DECIDE_DECISION);
    expectInvalid(await decide(app, token, 'attendance', REQ(1), { decision: 'approve', note: 'x'.repeat(1001) }), MESSAGES.DECIDE_NOTE);
    expectInvalid(await decide(app, token, 'attendance', REQ(1), { decision: 'approve', extra: 1 }), MESSAGES.UNKNOWN_FIELD);
    expectRefusal(await decide(app, token, 'attendance', 'nope', { decision: 'approve' }), 400, 'VALIDATION_FAILED');
    db.dropTable('hr_ess_attendance_requests');
    expectRefusal(await decide(app, token, 'attendance', REQ(1), { decision: 'approve' }), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('HR\'s tools for requests', () => {
  it('cancels an approved request by taking the day back, and records it', async () => {
    const { app, people, db } = buildApp({ setup: withTwoRequests });
    const manager = tokens.portal(people.admin_manager);
    await decide(app, manager, 'attendance', REQ(1), { decision: 'approve' });
    const res = await hrCancel(app, tokens.portal(people.hr), 'attendance', REQ(1), { reason: 'Recorded by mistake.' });
    expect(res.status).toBe(200);
    expect(res.body.request.status).toBe('cancelled');
    // The day existed before the approval, so the cancel puts it back exactly as it was.
    const restored = db.tables.hr_staff_attendance.find((d) => d.employee_id === people.attendance.employee.id && d.day === '2026-10-15');
    expect(restored).toMatchObject({ status: 'present', source: 'self_punch', note: 'Bus was late', first_in: '2026-10-15T04:20:00+00:00' });
    expect(db.tables.hr_ess_audit).toEqual([expect.objectContaining({ action: 'attendance_request.cancelled', actor_name: 'Test HR Manager' })]);
    // Only an approved request can be cancelled; and never by an hr_executive.
    expectRefusal(await hrCancel(app, tokens.portal(people.hr), 'attendance', REQ(1), { reason: 'Again, please.' }), 409, 'CANNOT_CANCEL');
    expectRefusal(await hrCancel(app, tokens.portal(people.hr_executive), 'attendance', REQ(1), { reason: 'Let me, too.' }), 403, 'ATTENDANCE_OVERRIDE_DENIED');
    expectRefusal(await hrCancel(app, tokens.portal(people.hr), 'attendance', REQ(9), { reason: 'Nothing there.' }), 404, 'NOT_FOUND');
    expectInvalid(await hrCancel(app, tokens.portal(people.hr), 'attendance', REQ(1), { reason: 'x' }), MESSAGES.CANCEL_REASON);
  });

  it('reads and changes the limits HR owns, with the change audited', async () => {
    const { app, db, people } = buildApp();
    const listed = await limits(app, tokens.portal(people.hr));
    expect(listed.status).toBe(200);
    expect(listed.body.limits.map((l) => l.type)).toEqual(['excuse_late', 'fix_a_day', 'leave_cl', 'leave_lwp', 'on_duty', 'short_leave']);
    const changed = await setLimit(app, tokens.portal(people.super_admin), 'fix_a_day', { limit_count: 5 });
    expect(changed.status).toBe(200);
    expect(changed.body.limit).toMatchObject({ type: 'fix_a_day', limit_count: 5, updated_by_name: 'Test Super Admin' });
    expect(db.tables.hr_ess_request_limits.find((l) => l.type === 'fix_a_day').limit_count).toBe(5);
    const cleared = await setLimit(app, tokens.portal(people.hr), 'leave_lwp', { limit_count: null });
    expect(cleared.body.limit.limit_count).toBe(null);
    expect(db.tables.hr_ess_audit.map((a) => a.action)).toEqual(['request_limits.set', 'request_limits.set']);
    // Minutes go with minutes: short leave takes limit_minutes and never limit_count.
    expect((await setLimit(app, tokens.portal(people.hr), 'short_leave', { limit_minutes: 120 })).status).toBe(200);
    expectInvalid(await setLimit(app, tokens.portal(people.hr), 'short_leave', { limit_count: 2 }), MESSAGES.UNKNOWN_FIELD);
    expectInvalid(await setLimit(app, tokens.portal(people.hr), 'fix_a_day', { limit_count: -1 }), MESSAGES.LIMIT_VALUE);
    expectInvalid(await setLimit(app, tokens.portal(people.hr), 'tea_break', { limit_count: 2 }), MESSAGES.LIMIT_TYPE);
    // The role guard: HR's attendance set, not the record set.
    expectRefusal(await limits(app, tokens.portal(people.hr_executive)), 403, 'ATTENDANCE_OVERRIDE_DENIED');
    expectRefusal(await setLimit(app, tokens.portal(people.hod), 'fix_a_day', { limit_count: 1 }), 403, 'ATTENDANCE_OVERRIDE_DENIED');
    expectRefusal(await limits(app, tokens.attendance(people.attendance)), 403, 'PORTAL_LOGIN_REQUIRED');
  });
});
