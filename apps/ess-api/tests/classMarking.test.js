const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { uuid } = require('./helpers/fixtures');

/** Task H1 (Phase 2D, decision 8): faculty class marking. */

const BID = (n) => `8d000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const SID = (n) => `9e000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const FACULTY_ID = uuid('f', 11);
const OTHER_FACULTY_ID = uuid('f', 4);
const DAY = '2026-10-16';
const OPEN_DAY = '2026-10-15';
const STAMP = '2026-10-16T06:30:00.000Z';

const batch = (n, facultyId, locationId) => ({
  id: BID(n), name: n === 1 ? 'CAD Morning Batch' : n === 2 ? 'AutoCAD Evening Batch' : 'Pune Weekend Batch',
  faculty_id: facultyId, start_date: '2026-10-01', end_date: '2026-12-31',
  start_time: '09:00:00', end_time: '11:00:00', days_of_week: ['Friday'], schedule: [5], location_id: locationId,
});

const student = (n, name, admission, change = {}) => ({
  id: SID(n), name, admission_number: admission, is_on_hold: false, hold_applied_at: null, ...change,
});

/**
 * One batch the faculty owns, one they cover through a substitution, one that is somebody else's,
 * and the roster cases: joined, not joined, an unjoined admission, a hold period and the
 * students.is_on_hold flag. SID(6) has no admissions row at all and is a legacy/direct add.
 */
const CLASS = (w) => {
  w.tables.batches = [batch(1, FACULTY_ID, 1), batch(2, OTHER_FACULTY_ID, 2), batch(3, OTHER_FACULTY_ID, 2)];
  w.tables.faculty_substitutions = [{
    id: BID(9), batch_id: BID(2), original_faculty_id: OTHER_FACULTY_ID,
    substitute_faculty_id: FACULTY_ID, start_date: '2026-10-01', end_date: '2026-10-31',
  }];
  w.tables.batch_students = [
    { batch_id: BID(1), student_id: SID(1), joined_at: '2026-09-01T00:00:00+00:00' },
    { batch_id: BID(1), student_id: SID(2), joined_at: '2026-09-01T00:00:00+00:00' },
    { batch_id: BID(1), student_id: SID(3), joined_at: null },
    { batch_id: BID(1), student_id: SID(4), joined_at: '2026-09-01T00:00:00+00:00' },
    { batch_id: BID(1), student_id: SID(5), joined_at: '2026-09-01T00:00:00+00:00' },
    { batch_id: BID(1), student_id: SID(6), joined_at: '2026-09-01T00:00:00+00:00' },
    { batch_id: BID(1), student_id: SID(7), joined_at: '2026-09-01T00:00:00+00:00' },
    { batch_id: BID(2), student_id: SID(8), joined_at: '2026-09-15T00:00:00+00:00' },
  ];
  w.tables.students = [
    student(1, 'Aarav Sharma', 'ADM-001'),
    student(2, 'Diya Patel', 'ADM-002'),
    student(3, 'Kabir Singh', 'ADM-003'),
    student(4, 'Meera Rao', 'ADM-004'),
    student(5, 'Rohan Gupta', 'ADM-005'),
    student(6, 'Sara Khan', 'ADM-006'),
    student(7, 'Vikram Joshi', 'ADM-007', { is_on_hold: true, hold_applied_at: '2026-10-10T00:00:00+00:00' }),
    student(8, 'Ananya Das', 'ADM-008'),
  ];
  w.tables.admissions = [
    { student_id: SID(1), joined: true },
    { student_id: SID(2), joined: true },
    { student_id: SID(4), joined: false },
    { student_id: SID(5), joined: true },
    { student_id: SID(7), joined: true },
    { student_id: SID(8), joined: true },
  ];
  w.tables.hold_periods = [{
    student_id: SID(5), hold_start: '2026-10-10', hold_end: null, hold_category: null, hold_remarks: null, applied_by: null,
  }];
  w.tables.student_attendance = [
    { batch_id: BID(1), student_id: SID(1), date: DAY, is_present: true, absent_reason: null, follow_up_comment: null },
    { batch_id: BID(1), student_id: SID(2), date: DAY, is_present: false, absent_reason: null, follow_up_comment: null },
  ];
  const alert = (n, studentId, day, resolved = false) => ({
    id: SID(n), batch_id: BID(1), student_id: studentId, date: day, alert_type: 'absent_remarks_missing',
    is_resolved: resolved, resolved_at: resolved ? '2026-10-16T05:00:00.000Z' : null,
    resolved_by: resolved ? 'Test Admin Manager' : null, location_id: 1,
  });
  w.tables.pending_alerts = [
    alert(20, SID(2), DAY),
    alert(21, SID(2), DAY, true),
    alert(22, SID(1), OPEN_DAY),
    // Diya is saved below with her reason given: her alert for that day is no longer missing.
    alert(24, SID(2), OPEN_DAY),
    // Sara is on the roster but unmarked: nothing may resolve this one on the save below.
    alert(23, SID(6), DAY),
  ];
};

const ROSTER = (id, day = DAY) => `/api/ess/me/batches/${id}/roster?date=${day}`;
const SAVE = (id) => `/api/ess/me/batches/${id}/attendance`;
const REMARK = (id, day = DAY) => `/api/ess/me/batches/${id}/attendance/${day}/remarks`;

const get = (app, path, token) => request(app).get(path).set(bearer(token));
const post = (app, path, token, body) => request(app).post(path).set(bearer(token)).send(body);
const patch = (app, path, token, body) => request(app).patch(path).set(bearer(token)).send(body);

const one = (studentId, present, extra = {}) => ({ student_id: studentId, present, ...extra });

describe('GET /api/ess/me/batches/{id}/roster', () => {
  it('gives the batch owner the eligible roster and the day\'s marks, and nothing personal', async () => {
    const { app, people } = buildApp({ setup: CLASS });
    const res = await get(app, ROSTER(BID(1)), tokens.portal(people.faculty));
    expect(res.status).toBe(200);
    expect(res.body.batch).toEqual({ id: BID(1), name: 'CAD Morning Batch' });
    expect(res.body.date).toBe(DAY);
    expect(res.body.already_marked).toBe(true);
    expect(res.body.can_edit).toBe(false);
    expect(res.body.students.map((s) => s.full_name)).toEqual(['Aarav Sharma', 'Diya Patel', 'Sara Khan']);
    expect(res.body.students[0]).toEqual({
      id: SID(1), full_name: 'Aarav Sharma', admission_number: 'ADM-001',
      marked: 'present', absent_reason: null, follow_up_comment: null,
    });
    expect(res.body.students[1]).toMatchObject({ id: SID(2), marked: 'absent', absent_reason: null });
    // Sara has no mark yet, and no admissions row at all: the Scheduler's legacy add stays eligible.
    expect(res.body.students[2]).toMatchObject({ id: SID(6), marked: null });
    expect(Object.keys(res.body.students[0]).sort()).toEqual([
      'absent_reason', 'admission_number', 'follow_up_comment', 'full_name', 'id', 'marked',
    ]);
    expect(JSON.stringify(res.body)).not.toMatch(/phone|password|fee|email|date_of_birth|remarks_updated/);
  });

  it('lets a covering substitute read, and leaves an ended substitution out', async () => {
    const covered = buildApp({ setup: CLASS });
    const yes = await get(covered.app, ROSTER(BID(2)), tokens.portal(covered.people.faculty));
    expect(yes.status).toBe(200);
    expect(yes.body.batch.name).toBe('AutoCAD Evening Batch');
    expect(yes.body.students.map((s) => s.id)).toEqual([SID(8)]);
    expect(yes.body.already_marked).toBe(false);
    expect(yes.body.can_edit).toBe(true);

    const ended = buildApp({ setup: (w) => {
      CLASS(w);
      w.tables.faculty_substitutions[0].end_date = '2026-10-10';
    } });
    const no = await get(ended.app, ROSTER(BID(2)), tokens.portal(ended.people.faculty));
    expect(no.status).toBe(403);
    expect(no.body.code).toBe('CLASS_NOT_YOURS');
  });

  it('lets an admin read their own branch and the CEO read any branch', async () => {
    const { app, people } = buildApp({ setup: CLASS });
    const admin = await get(app, ROSTER(BID(1)), tokens.portal(people.admin));
    expect(admin.status).toBe(200);
    // An admin may correct the day, so can_edit stays true after the first save.
    expect(admin.body.already_marked).toBe(true);
    expect(admin.body.can_edit).toBe(true);

    const ceo = await get(app, ROSTER(BID(2)), tokens.portal(people.ceo));
    expect(ceo.status).toBe(200);
    expect(ceo.body.can_edit).toBe(true);
  });

  it('refuses every role outside the two sets, an attendance session included', async () => {
    const { app, people } = buildApp({ setup: CLASS });
    for (const who of ['hr', 'hr_executive', 'hod_placement']) {
      const res = await get(app, ROSTER(BID(1)), tokens.portal(people[who]));
      expect(res.status).toBe(403);
      expect(res.body.code).toBe('CLASS_ROLE_DENIED');
      expect(res.body.error).toBe(MESSAGES.CLASS_ROLE_DENIED);
    }
    const punch = await get(app, ROSTER(BID(1)), tokens.attendance(people.attendance));
    expect(punch.status).toBe(403);
    expect(punch.body.code).toBe('CLASS_ROLE_DENIED');
  });

  it('refuses another branch\'s batch to an admin, and an unmapped branch', async () => {
    const { app, people } = buildApp({ setup: CLASS });
    const other = await get(app, ROSTER(BID(2)), tokens.portal(people.admin));
    expect(other.status).toBe(403);
    expect(other.body.code).toBe('CLASS_NOT_YOURS');

    const unmapped = buildApp({ setup: (w) => {
      CLASS(w);
      w.people.admin.employee.branch_id = uuid('b', 9);
    } });
    const res = await get(unmapped.app, ROSTER(BID(1)), tokens.portal(unmapped.people.admin));
    expect(res.status).toBe(403);
    expect(res.body.code).toBe('CLASS_NOT_YOURS');
  });

  it('refuses somebody else\'s batch to a teaching caller', async () => {
    const { app, people } = buildApp({ setup: CLASS });
    const res = await get(app, ROSTER(BID(3)), tokens.portal(people.faculty));
    expect(res.status).toBe(403);
    expect(res.body.code).toBe('CLASS_NOT_YOURS');

    const hod = await get(app, ROSTER(BID(3)), tokens.portal(people.hod));
    expect(hod.status).toBe(200);
  });

  it('holds the date window: no future day, nothing before the batch starts', async () => {
    const { app, people } = buildApp({ setup: CLASS });
    const future = await get(app, ROSTER(BID(1), '2026-10-17'), tokens.portal(people.faculty));
    expect(future.status).toBe(403);
    expect(future.body.code).toBe('CLASS_WINDOW');
    expect(future.body.error).toBe(MESSAGES.CLASS_WINDOW);

    const early = await get(app, ROSTER(BID(1), '2026-09-30'), tokens.portal(people.faculty));
    expect(early.status).toBe(403);
    expect(early.body.code).toBe('CLASS_WINDOW');
  });

  it('refuses a malformed or missing date, a bad id and a missing batch', async () => {
    const { app, people } = buildApp({ setup: CLASS });
    const token = tokens.portal(people.faculty);
    const badDate = await get(app, ROSTER(BID(1), '2026-13-01'), token);
    expect(badDate.status).toBe(400);
    expect(badDate.body.error).toBe(MESSAGES.DATE_FORMAT);

    const missing = await get(app, `/api/ess/me/batches/${BID(1)}/roster`, token);
    expect(missing.status).toBe(400);
    expect(missing.body.code).toBe('VALIDATION_FAILED');

    const badId = await get(app, ROSTER('not-an-id'), token);
    expect(badId.status).toBe(400);
    expect(badId.body.error).toBe(MESSAGES.INVALID_ID);

    const gone = await get(app, ROSTER(BID(9)), token);
    expect(gone.status).toBe(404);
    expect(gone.body.code).toBe('BATCH_NOT_FOUND');
    expect(gone.body.error).toBe(MESSAGES.BATCH_NOT_FOUND);
  });

  it('answers 401 without a token, 429 past the limit, and 503 when the data is missing', async () => {
    const none = buildApp({ setup: CLASS });
    expect((await request(none.app).get(ROSTER(BID(1)))).status).toBe(401);

    const limited = buildApp({ setup: CLASS, limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
    await get(limited.app, ROSTER(BID(1)), tokens.portal(limited.people.faculty));
    const rate = await get(limited.app, ROSTER(BID(1)), tokens.portal(limited.people.faculty));
    expect(rate.status).toBe(429);

    const broken = buildApp({ setup: CLASS });
    broken.db.failWhen = (q) => (q.table === 'students' ? 'error' : null);
    const unavailable = await get(broken.app, ROSTER(BID(1)), tokens.portal(broken.people.faculty));
    expect(unavailable.status).toBe(503);

    const notInstalled = buildApp({ setup: CLASS });
    notInstalled.db.dropTable('student_attendance');
    const missing = await get(notInstalled.app, ROSTER(BID(1)), tokens.portal(notInstalled.people.faculty));
    expect(missing.status).toBe(503);
    expect(missing.body.code).toBe('MODULE_NOT_INSTALLED');
  });
});

describe('POST /api/ess/me/batches/{id}/attendance', () => {
  it('saves the day, its counts and the caller\'s remark stamp, and resolves a present alert', async () => {
    const { app, db, people } = buildApp({ setup: CLASS });
    const res = await post(app, SAVE(BID(1)), tokens.portal(people.faculty), {
      date: OPEN_DAY,
      attendance: [
        one(SID(1), true),
        one(SID(2), false, { absent_reason: 'Fever, informed the office.', follow_up_comment: 'Call the parent.' }),
      ],
    });
    expect(res.status).toBe(200);
    expect(res.body.batch).toEqual({ id: BID(1), name: 'CAD Morning Batch' });
    expect(res.body.date).toBe(OPEN_DAY);
    expect(res.body.counts).toEqual({ present: 1, absent: 1, total: 2 });

    const rows = db.tables.student_attendance.filter((r) => r.date === OPEN_DAY);
    expect(rows).toHaveLength(2);
    expect(rows.find((r) => r.student_id === SID(1))).toMatchObject({
      batch_id: BID(1), is_present: true, absent_reason: null, follow_up_comment: null,
      remarks_updated_by: 'Test CAD Faculty', remarks_updated_at: STAMP,
    });
    expect(rows.find((r) => r.student_id === SID(2))).toMatchObject({
      is_present: false, absent_reason: 'Fever, informed the office.', follow_up_comment: 'Call the parent.',
    });

    const resolved = db.tables.pending_alerts.find((a) => a.id === SID(22));
    expect(resolved).toMatchObject({
      is_resolved: true, resolved_at: STAMP, resolved_by: 'Test CAD Faculty',
    });
    // An absent student whose reason came with the save also has nothing missing.
    expect(db.tables.pending_alerts.find((a) => a.id === SID(24))).toMatchObject({
      is_resolved: true, resolved_at: STAMP, resolved_by: 'Test CAD Faculty',
    });
    // Sara is unmarked: her alert must stay open.
    expect(db.tables.pending_alerts.find((a) => a.id === SID(23)).is_resolved).toBe(false);

    const audit = db.tables.hr_ess_audit.find((a) => a.action === 'class.attendance.marked');
    expect(audit.details).toEqual({ batch_id: BID(1), date: OPEN_DAY, present: 1, absent: 1 });
    expect(JSON.stringify(audit.details)).not.toContain(SID(1));
    expect(JSON.stringify(res.body)).not.toMatch(/phone|password|fee|email/);
  });

  it('refuses an ineligible student: not joined, admissions false, or on hold', async () => {
    for (const studentId of [SID(3), SID(4), SID(5), SID(7)]) {
      const { app, db, people } = buildApp({ setup: CLASS });
      const res = await post(app, SAVE(BID(1)), tokens.portal(people.faculty), {
        date: OPEN_DAY, attendance: [one(studentId, false, { absent_reason: 'Not in class.' })],
      });
      expect(res.status, studentId).toBe(400);
      expect(res.body.code).toBe('VALIDATION_FAILED');
      expect(res.body.error).toBe(MESSAGES.CLASS_ROSTER);
      expect(db.writes().filter((q) => q.table === 'student_attendance')).toHaveLength(0);
      expect(db.writes().filter((q) => q.table === 'pending_alerts')).toHaveLength(0);
    }
  });

  it('accepts a legacy student with no admissions row at all', async () => {
    const { app, people } = buildApp({ setup: CLASS });
    const res = await post(app, SAVE(BID(1)), tokens.portal(people.faculty), {
      date: OPEN_DAY, attendance: [one(SID(6), true)],
    });
    expect(res.status).toBe(200);
    expect(res.body.counts).toEqual({ present: 1, absent: 0, total: 1 });
  });

  it('locks the day for a teaching role after the first save; an admin may correct it', async () => {
    const teaching = buildApp({ setup: CLASS });
    const locked = await post(teaching.app, SAVE(BID(1)), tokens.portal(teaching.people.faculty), {
      date: DAY, attendance: [one(SID(2), true)],
    });
    expect(locked.status).toBe(409);
    expect(locked.body.code).toBe('CLASS_ALREADY_MARKED');
    expect(locked.body.error).toBe(MESSAGES.CLASS_ALREADY_MARKED);
    expect(teaching.db.writes()).toHaveLength(0);

    const admin = buildApp({ setup: CLASS });
    const corrected = await post(admin.app, SAVE(BID(1)), tokens.portal(admin.people.admin), {
      date: DAY, attendance: [one(SID(2), true)],
    });
    expect(corrected.status).toBe(200);
    expect(corrected.body.counts).toEqual({ present: 1, absent: 0, total: 1 });
    const row = admin.db.tables.student_attendance.find((r) => r.batch_id === BID(1) && r.student_id === SID(2) && r.date === DAY);
    expect(row.is_present).toBe(true);
    expect(row.absent_reason).toBeNull();
    const audit = admin.db.tables.hr_ess_audit.find((a) => a.action === 'class.attendance.marked');
    expect(audit.details).toEqual({ batch_id: BID(1), date: DAY, present: 1, absent: 0 });
  });

  it('refuses another branch, another owner and a future day', async () => {
    const { app, people } = buildApp({ setup: CLASS });
    const branch = await post(app, SAVE(BID(2)), tokens.portal(people.admin), {
      date: DAY, attendance: [one(SID(8), true)],
    });
    expect(branch.status).toBe(403);
    expect(branch.body.code).toBe('CLASS_NOT_YOURS');

    const owner = await post(app, SAVE(BID(3)), tokens.portal(people.faculty), {
      date: DAY, attendance: [one(SID(8), true)],
    });
    expect(owner.status).toBe(403);
    expect(owner.body.code).toBe('CLASS_NOT_YOURS');

    const future = await post(app, SAVE(BID(1)), tokens.portal(people.faculty), {
      date: '2026-10-17', attendance: [one(SID(1), true)],
    });
    expect(future.status).toBe(403);
    expect(future.body.code).toBe('CLASS_WINDOW');
  });

  it('refuses a malformed body without writing anything', async () => {
    const { app, db, people } = buildApp({ setup: CLASS });
    const token = tokens.portal(people.faculty);
    const cases = [
      [{ date: OPEN_DAY }, MESSAGES.CLASS_ATTENDANCE],
      [{ date: OPEN_DAY, attendance: [] }, MESSAGES.CLASS_ATTENDANCE],
      [{ date: OPEN_DAY, attendance: [one(SID(1), true), one(SID(1), false)] }, MESSAGES.CLASS_ATTENDANCE],
      [{ date: OPEN_DAY, attendance: [{ student_id: SID(1), present: 'yes' }] }, MESSAGES.CLASS_ATTENDANCE],
      [{ date: OPEN_DAY, attendance: [one(SID(1), false, { absent_reason: 'x' })] }, MESSAGES.CLASS_REMARK],
      [{ date: OPEN_DAY, attendance: [one(SID(1), false, { follow_up_comment: 'x'.repeat(1001) })] }, MESSAGES.CLASS_REMARK],
      [{ date: '2026-02-30', attendance: [one(SID(1), true)] }, MESSAGES.DATE_FORMAT],
      [{ date: OPEN_DAY, attendance: [one(SID(1), true, { employee_id: 'somebody' })] }, MESSAGES.CLASS_ATTENDANCE],
    ];
    for (const [body, message] of cases) {
      const res = await post(app, SAVE(BID(1)), token, body);
      expect(res.status).toBe(400);
      expect(res.body.code).toBe('VALIDATION_FAILED');
      expect(res.body.error).toBe(message);
    }
    expect(db.writes()).toHaveLength(0);

    const unknown = await post(app, SAVE(BID(1)), token, { date: OPEN_DAY, attendance: [one(SID(1), true)], x: 1 });
    expect(unknown.status).toBe(400);
    expect(unknown.body.error).toBe(MESSAGES.UNKNOWN_FIELD);
  });

  it('answers 401, 429, 404 and 503 as the contract says', async () => {
    const none = buildApp({ setup: CLASS });
    expect((await request(none.app).post(SAVE(BID(1))).send({ date: OPEN_DAY, attendance: [one(SID(1), true)] })).status).toBe(401);

    const limited = buildApp({ setup: CLASS, limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
    const body = { date: OPEN_DAY, attendance: [one(SID(1), true)] };
    await post(limited.app, SAVE(BID(1)), tokens.portal(limited.people.faculty), body);
    const rate = await post(limited.app, SAVE(BID(1)), tokens.portal(limited.people.faculty), body);
    expect(rate.status).toBe(429);

    const gone = buildApp({ setup: CLASS });
    const notFound = await post(gone.app, SAVE(BID(9)), tokens.portal(gone.people.faculty), body);
    expect(notFound.status).toBe(404);
    expect(notFound.body.code).toBe('BATCH_NOT_FOUND');

    const broken = buildApp({ setup: CLASS });
    broken.db.failWhen = (q) => (q.table === 'student_attendance' && q.op !== 'select' ? 'error' : null);
    const unavailable = await post(broken.app, SAVE(BID(1)), tokens.portal(broken.people.faculty), body);
    expect(unavailable.status).toBe(503);

    const notInstalled = buildApp({ setup: CLASS });
    notInstalled.db.dropTable('student_attendance');
    const missing = await post(notInstalled.app, SAVE(BID(1)), tokens.portal(notInstalled.people.faculty), body);
    expect(missing.status).toBe(503);
    expect(missing.body.code).toBe('MODULE_NOT_INSTALLED');
  });
});

describe('PATCH /api/ess/me/batches/{id}/attendance/{date}/remarks', () => {
  it('fills an absent student\'s reason, resolves the alert and audits before and after', async () => {
    const { app, db, people } = buildApp({ setup: CLASS });
    const res = await patch(app, REMARK(BID(1)), tokens.portal(people.faculty), {
      student_id: SID(2),
      absent_reason: 'Fever, informed the office.',
      follow_up_comment: 'Call the parent.',
    });
    expect(res.status).toBe(200);
    expect(res.body.batch).toEqual({ id: BID(1), name: 'CAD Morning Batch' });
    expect(res.body.student).toEqual({
      id: SID(2), full_name: 'Diya Patel', admission_number: 'ADM-002',
      marked: 'absent', absent_reason: 'Fever, informed the office.', follow_up_comment: 'Call the parent.',
    });
    const row = db.tables.student_attendance.find((r) => r.batch_id === BID(1) && r.student_id === SID(2) && r.date === DAY);
    expect(row).toMatchObject({
      is_present: false, absent_reason: 'Fever, informed the office.',
      follow_up_comment: 'Call the parent.', remarks_updated_by: 'Test CAD Faculty', remarks_updated_at: STAMP,
    });
    const alert = db.tables.pending_alerts.find((a) => a.id === SID(20));
    expect(alert).toMatchObject({ is_resolved: true, resolved_at: STAMP, resolved_by: 'Test CAD Faculty' });
    const audit = db.tables.hr_ess_audit.find((a) => a.action === 'class.remark.changed');
    expect(audit.details).toEqual({
      batch_id: BID(1), date: DAY, student_id: SID(2), before: null, after: 'Fever, informed the office.',
    });
    expect(JSON.stringify(res.body)).not.toMatch(/phone|password|fee|email/);
  });

  it('lets an admin change a remark a teaching role already filled', async () => {
    const { app, db, people } = buildApp({ setup: (w) => {
      CLASS(w);
      w.tables.student_attendance.find((r) => r.student_id === SID(2)).absent_reason = 'Unwell';
    } });
    const res = await patch(app, REMARK(BID(1)), tokens.portal(people.admin), {
      student_id: SID(2), absent_reason: 'Fever, informed the office.',
    });
    expect(res.status).toBe(200);
    expect(db.tables.student_attendance.find((r) => r.student_id === SID(2)).absent_reason)
      .toBe('Fever, informed the office.');
    expect(db.tables.hr_ess_audit.find((a) => a.action === 'class.remark.changed').details)
      .toMatchObject({ before: 'Unwell', after: 'Fever, informed the office.' });
  });

  it('refuses a present or unmarked student, and a reason outside its limits', async () => {
    const { app, people } = buildApp({ setup: CLASS });
    const token = tokens.portal(people.faculty);
    for (const studentId of [SID(1), SID(6)]) {
      const res = await patch(app, REMARK(BID(1)), token, { student_id: studentId, absent_reason: 'Fever today.' });
      expect(res.status, studentId).toBe(409);
      expect(res.body.code).toBe('CLASS_NOT_ABSENT');
      expect(res.body.error).toBe(MESSAGES.CLASS_NOT_ABSENT);
    }
    const short = await patch(app, REMARK(BID(1)), token, { student_id: SID(2), absent_reason: 'x' });
    expect(short.status).toBe(400);
    expect(short.body.error).toBe(MESSAGES.CLASS_REMARK);

    const long = await patch(app, REMARK(BID(1)), token, { student_id: SID(2), absent_reason: 'x'.repeat(501) });
    expect(long.status).toBe(400);
    expect(long.body.error).toBe(MESSAGES.CLASS_REMARK);
  });

  it('holds the same role, branch, ownership, date and roster rules', async () => {
    const { app, people } = buildApp({ setup: CLASS });
    const body = { student_id: SID(2), absent_reason: 'Fever, informed the office.' };
    const role = await patch(app, REMARK(BID(1)), tokens.portal(people.hr), body);
    expect(role.status).toBe(403);
    expect(role.body.code).toBe('CLASS_ROLE_DENIED');

    const branch = await patch(app, REMARK(BID(2)), tokens.portal(people.admin), { student_id: SID(8), absent_reason: 'Fever today.' });
    expect(branch.status).toBe(403);
    expect(branch.body.code).toBe('CLASS_NOT_YOURS');

    const owner = await patch(app, REMARK(BID(3)), tokens.portal(people.faculty), { student_id: SID(8), absent_reason: 'Fever today.' });
    expect(owner.status).toBe(403);
    expect(owner.body.code).toBe('CLASS_NOT_YOURS');

    const future = await patch(app, REMARK(BID(1), '2026-10-17'), tokens.portal(people.faculty), body);
    expect(future.status).toBe(403);
    expect(future.body.code).toBe('CLASS_WINDOW');

    const ineligible = await patch(app, REMARK(BID(1)), tokens.portal(people.faculty), { student_id: SID(7), absent_reason: 'Fever today.' });
    expect(ineligible.status).toBe(400);
    expect(ineligible.body.error).toBe(MESSAGES.CLASS_ROSTER);

    const badDay = await patch(app, REMARK(BID(1), '2026-13-01'), tokens.portal(people.faculty), body);
    expect(badDay.status).toBe(400);
    expect(badDay.body.error).toBe(MESSAGES.DATE_FORMAT);

    const gone = await patch(app, REMARK(BID(9)), tokens.portal(people.faculty), body);
    expect(gone.status).toBe(404);
    expect(gone.body.code).toBe('BATCH_NOT_FOUND');
  });

  it('answers 401, 429 and 503, and refuses an unknown field', async () => {
    const none = buildApp({ setup: CLASS });
    expect((await request(none.app).patch(REMARK(BID(1))).send({ student_id: SID(2), absent_reason: 'Fever today.' })).status).toBe(401);

    const limited = buildApp({ setup: CLASS, limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
    const token = tokens.portal(limited.people.faculty);
    const body = { student_id: SID(2), absent_reason: 'Fever today.' };
    await patch(limited.app, REMARK(BID(1)), token, body);
    expect((await patch(limited.app, REMARK(BID(1)), token, body)).status).toBe(429);

    const broken = buildApp({ setup: CLASS });
    broken.db.outage = 'error';
    expect((await patch(broken.app, REMARK(BID(1)), tokens.portal(broken.people.faculty), body)).status).toBe(503);

    const unknown = buildApp({ setup: CLASS });
    const res = await patch(unknown.app, REMARK(BID(1)), tokens.portal(unknown.people.faculty), { ...body, x: 1 });
    expect(res.status).toBe(400);
    expect(res.body.error).toBe(MESSAGES.UNKNOWN_FIELD);
  });
});
