const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { startApprovalsJob } = require('../src/jobs/approvals');

/** Task D4: the request's approval chain, the archive that clears an Inbox, and the escalation job. */

const INBOX = '/api/ess/approvals';
const AID = (n) => `7c000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
const CHAIN = (family, id) => `${INBOX}/${family}/${id}/chain`;
const ARCHIVE = (family, id) => `${INBOX}/${family}/${id}/archive`;

const dayRow = (employeeId, day, change = {}) => ({
  id: `86000000-0000-4000-8000-${String(Math.abs(day.charCodeAt(9) * 7)).padStart(12, '0')}`,
  employee_id: employeeId, branch_id: null, day, status: 'present', leave_type: null, note: null,
  marked_by: null, marked_by_name: 'Test (self punch)', marked_at: `${day}T04:00:00+00:00`,
  updated_at: `${day}T12:00:00+00:00`, source: 'self_punch', first_in: `${day}T04:20:00+00:00`,
  last_out: `${day}T12:40:00+00:00`, worked_minutes: 500, shift_id: null, shift_start: null, shift_end: null,
  grace_minutes: null, late_minutes: null, early_exit_minutes: null, late_count: null, late_half_day: false,
  late_excused: false, late_excused_by_name: null, late_excused_reason: null, late_excused_at: null, ...change,
});

const requestRow = (family, employeeId, id, change = {}) => ({
  id,
  employee_id: employeeId,
  type: family === 'leave' ? 'cl' : 'on_duty',
  status: 'pending',
  day: '2026-10-15',
  reason: 'Client visit at the Pune centre.',
  place: family === 'attendance' ? 'Pune centre' : null,
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
  created_at: '2026-10-13T05:00:00+00:00',
  updated_at: '2026-10-13T05:00:00+00:00',
  ...change,
});

const withRequests = (w) => {
  w.tables.hr_ess_attendance_requests = [requestRow('attendance', w.people.attendance.employee.id, AID(1))];
};

describe('GET /api/ess/approvals/{family}/{id}/chain', () => {
  it('the requester reads their own line, first unskipped level first', async () => {
    const { app, people } = buildApp({ setup: withRequests });
    const res = await request(app).get(CHAIN('attendance', AID(1))).set(bearer(tokens.attendance(people.attendance)));
    expect(res.status).toBe(200);
    expect(res.body.request.id).toBe(AID(1));
    expect(res.body.chain.map((e) => e.employee.full_name)).toEqual([
      people.admin_manager.employee.full_name,
      people.hoo.employee.full_name,
      people.ceo.employee.full_name,
    ]);
    expect(res.body.chain[0]).toMatchObject({ may_decide: true, skipped: null });
    expect(res.body.chain[1].may_decide).toBe(false);
    expect(res.body.hr_fallback).toBe(false);
  });

  it('a level on leave that day is skipped, and the next one may decide', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      withRequests(w);
      w.tables.hr_staff_attendance.push(dayRow(w.people.admin_manager.employee.id, '2026-10-15', {
        status: 'leave', source: 'override', first_in: null, last_out: null, worked_minutes: null,
      }));
    } });
    const res = await request(app).get(CHAIN('attendance', AID(1))).set(bearer(tokens.portal(people.admin_manager)));
    expect(res.status).toBe(200);
    expect(res.body.chain[0]).toMatchObject({ may_decide: false, skipped: 'on_leave' });
    expect(res.body.chain[1]).toMatchObject({ may_decide: true, skipped: null });
  });

  it('nobody on the line: the HR fallback is all that is left', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_attendance_requests = [requestRow('attendance', w.people.ceo.employee.id, AID(4))];
    } });
    const res = await request(app).get(CHAIN('attendance', AID(4))).set(bearer(tokens.portal(people.hr)));
    expect(res.status).toBe(200);
    expect(res.body.chain).toEqual([]);
    expect(res.body.hr_fallback).toBe(true);
  });

  it('refuses somebody outside the line, and an unknown request or family', async () => {
    const { app, people } = buildApp({ setup: withRequests });
    const stranger = await request(app).get(CHAIN('attendance', AID(1))).set(bearer(tokens.portal(people.faculty)));
    expect(stranger.status).toBe(403);
    expect(stranger.body.code).toBe('NOT_AN_APPROVER');
    expect(stranger.body.error).toBe(MESSAGES.NOT_AN_APPROVER);

    const missing = await request(app).get(CHAIN('attendance', AID(9))).set(bearer(tokens.portal(people.hr)));
    expect(missing.status).toBe(404);
    expect(missing.body.code).toBe('NOT_FOUND');

    const family = await request(app).get(CHAIN('wall', AID(1))).set(bearer(tokens.portal(people.hr)));
    expect(family.status).toBe(404);
    expect(family.body.code).toBe('NOT_FOUND');

    const bad = await request(app).get(CHAIN('attendance', 'nope')).set(bearer(tokens.portal(people.hr)));
    expect(bad.status).toBe(400);
    expect(bad.body.code).toBe('VALIDATION_FAILED');

    const none = await request(app).get(CHAIN('attendance', AID(1)));
    expect(none.status).toBe(401);
  });
});

describe('POST /api/ess/approvals/{family}/{id}/archive', () => {
  it('clears the request from my Inbox without deciding it', async () => {
    const { app, people } = buildApp({ setup: withRequests });
    const before = await request(app).get(INBOX).set(bearer(tokens.portal(people.admin_manager)));
    expect(before.body.requests.map((r) => r.id)).toContain(AID(1));

    const archived = await request(app).post(ARCHIVE('attendance', AID(1))).set(bearer(tokens.portal(people.admin_manager)));
    expect(archived.status).toBe(204);

    const after = await request(app).get(INBOX).set(bearer(tokens.portal(people.admin_manager)));
    expect(after.body.requests.map((r) => r.id)).not.toContain(AID(1));
    const other = await request(app).get(INBOX).set(bearer(tokens.portal(people.hr)));
    expect(other.body.requests.map((r) => r.id)).toContain(AID(1));
  });

  it('refuses somebody outside the line, and an unknown request', async () => {
    const { app, people } = buildApp({ setup: withRequests });
    const stranger = await request(app).post(ARCHIVE('attendance', AID(1))).set(bearer(tokens.portal(people.faculty)));
    expect(stranger.status).toBe(403);
    expect(stranger.body.code).toBe('NOT_AN_APPROVER');
    const missing = await request(app).post(ARCHIVE('attendance', AID(9))).set(bearer(tokens.portal(people.hr)));
    expect(missing.status).toBe(404);
    expect(missing.body.code).toBe('NOT_FOUND');
  });
});

describe('the approvals escalation job', () => {
  const run = (world) => {
    const log = { log: () => {}, error: () => {} };
    const job = startApprovalsJob({
      store: world.store,
      now: () => new Date('2026-10-16T06:30:00Z'),
      immediate: false,
      intervalMs: 60 * 60 * 1000,
      log,
    });
    return job.runOnce().finally(() => job.stop());
  };

  it('escalates a request pending more than two days to the first level, and tells them', async () => {
    const world = buildApp({ setup: withRequests });
    const out = await run(world);
    expect(out.escalated).toBeGreaterThanOrEqual(1);
    const rows = await world.store.listEscalationsFor('attendance', AID(1));
    expect(rows.map((r) => r.to_employee_id)).toContain(world.people.admin_manager.employee.id);
    const told = world.db.tables.hr_ess_notifications.filter((n) => (
      n.employee_id === world.people.admin_manager.employee.id && n.category === 'approvals'
    ));
    expect(told.length).toBeGreaterThanOrEqual(1);
    expect(told[0].data.request_id).toBe(AID(1));
  });

  it('moves one level per run and never escalates the same person twice', async () => {
    const world = buildApp({ setup: withRequests });
    await run(world);
    await run(world);
    const rows = await world.store.listEscalationsFor('attendance', AID(1));
    expect(rows.map((r) => r.to_employee_id)).toEqual([
      world.people.admin_manager.employee.id,
      world.people.hoo.employee.id,
    ]);
  });

  it('falls back to HR when the line is exhausted', async () => {
    const world = buildApp({ setup: (w) => {
      w.tables.hr_ess_attendance_requests = [requestRow('attendance', w.people.ceo.employee.id, AID(5))];
    } });
    await run(world);
    const rows = await world.store.listEscalationsFor('attendance', AID(5));
    expect(rows.map((r) => r.to_employee_id)).toContain(world.people.hr.employee.id);
  });
});
