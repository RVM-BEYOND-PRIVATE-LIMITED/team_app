const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { NOW } = require('./helpers/constants');
const { BRANCH_ID, BRANCH_PUNE_ID, uuid } = require('./helpers/fixtures');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors, CALLERS, guardOutcome } = require('./helpers/expect');

/**
 * Task B8: registered phones, and HR's bulk reset, which writes exactly the rows the Scheduler's
 * own reset writes (controllers/hr/attendanceAdminController.js:280-293).
 *
 * The fixture's phones: the faculty member's (Faridabad, active), the attendance employee's
 * (Faridabad, one active and one already reset) and the Pune counsellor's (active).
 */

const LIST = '/api/ess/hr/devices';
const RESET = '/api/ess/hr/devices/reset';
const ATTENDANCE_ROLES = ['hr', 'ceo', 'super_admin'];

const PHONE = (n) => uuid('7', n);
const reset = (app, token, body) => request(app).post(RESET).set(bearer(token)).send(body);
const device = (db, n) => db.tables.hr_attendance_devices.find((d) => d.id === PHONE(n));

describe('GET /api/ess/hr/devices', () => {
  it.each(CALLERS)('%s', async (who, token) => {
    const { app, people } = buildApp();
    const res = await request(app).get(LIST).set(bearer(token(people)));
    const refused = guardOutcome(who, ATTENDANCE_ROLES, 'ATTENDANCE_OVERRIDE_DENIED');
    if (refused) expectRefusal(res, 403, refused);
    else expect(res.status).toBe(200);
  });

  it('lists the active phones by default, newest first, with whose phone each is and their branch', async () => {
    const { app, people } = buildApp();
    const res = await request(app).get(LIST).set(bearer(tokens.portal(people.hr)));
    expect(res.body.truncated).toBe(false);
    expect(res.body.devices.map((d) => d.id)).toEqual([PHONE(4), PHONE(2), PHONE(1)]);
    expect(res.body.devices[1]).toEqual({
      id: PHONE(2), status: 'active', bound_at: '2026-10-02T04:00:00+00:00', last_seen_at: '2026-10-16T04:10:00+00:00',
      revoked_at: null, revoked_by_name: null, revoke_reason: null,
      employee: { id: people.attendance.employee.id, full_name: 'Test Office Assistant', employee_code: 'RVM-050' },
      branch: { id: BRANCH_ID, name: 'Faridabad' },
    });
  });

  it('never sends a token hash, the phone\'s address or its user agent', async () => {
    const { app, db, people } = buildApp();
    const res = await request(app).get(`${LIST}?status=all`).set(bearer(tokens.portal(people.ceo)));
    expect(JSON.stringify(res.body)).not.toMatch(/token|hash|203\.0\.113|Mozilla/);
    const read = db.queries.find((q) => q.table === 'hr_attendance_devices');
    expect(read.columns).not.toContain('token_hash');
  });

  it.each([['revoked', [PHONE(3)]], ['all', [PHONE(4), PHONE(3), PHONE(2), PHONE(1)]], ['active', [PHONE(4), PHONE(2), PHONE(1)]]])(
    'filters with status=%s',
    async (status, ids) => {
      const { app, people } = buildApp();
      const res = await request(app).get(`${LIST}?status=${status}`).set(bearer(tokens.portal(people.super_admin)));
      expect(res.body.devices.map((d) => d.id)).toEqual(ids);
    },
  );

  it('shows who reset a phone, and why', async () => {
    const { app, people } = buildApp();
    const res = await request(app).get(`${LIST}?status=revoked`).set(bearer(tokens.portal(people.hr)));
    expect(res.body.devices[0]).toMatchObject({ status: 'revoked', revoked_at: '2026-10-02T05:00:00+00:00', revoked_by_name: 'hr.login', revoke_reason: 'Phone lost' });
  });

  it('filters by the employees\' branch', async () => {
    const { app, people } = buildApp();
    const res = await request(app).get(`${LIST}?branch_id=${BRANCH_PUNE_ID}`).set(bearer(tokens.portal(people.hr)));
    expect(res.body.devices.map((d) => d.id)).toEqual([PHONE(4)]);
    expect(res.body.devices[0].branch).toEqual({ id: BRANCH_PUNE_ID, name: 'Pune' });
  });

  it.each([['status=lost', MESSAGES.DEVICE_STATUS_FILTER], ['branch_id=1', MESSAGES.BRANCH_ID], ['status=active&status=all', MESSAGES.DEVICE_STATUS_FILTER]])(
    'refuses ?%s with 400',
    async (query, message) => {
      const { app, people } = buildApp();
      expectInvalid(await request(app).get(`${LIST}?${query}`).set(bearer(tokens.portal(people.hr))), message);
    },
  );

  it('answers 404 NOT_FOUND for a branch that is not there', async () => {
    const { app, people } = buildApp();
    expectRefusal(await request(app).get(`${LIST}?branch_id=b0000000-0000-4000-8000-000000000999`).set(bearer(tokens.portal(people.hr))), 404, 'NOT_FOUND');
  });

  it('answers 503 MODULE_NOT_INSTALLED, naming the table, before migration 20261020000000', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_attendance_devices');
    const res = await request(app).get(LIST).set(bearer(tokens.portal(people.hr)));
    expectRefusal(res, 503, 'MODULE_NOT_INSTALLED');
    expect(res.body.error).toMatch(/hr_attendance_devices/);
  });
});

describe('POST /api/ess/hr/devices/reset', () => {
  it('resets every active phone at a branch with exactly the Scheduler\'s update, and nothing else', async () => {
    const { app, db, people } = buildApp();
    const before = JSON.parse(JSON.stringify(db.tables.hr_attendance_devices));
    const res = await reset(app, tokens.portal(people.hr), { branch_id: BRANCH_ID, reason: 'Moving to the Team RVM app' });
    expect(res.status).toBe(200);
    expect(res.body.reset).toBe(2);
    expect([...res.body.device_ids].sort()).toEqual([PHONE(1), PHONE(2)]);

    const revoked = { status: 'revoked', revoked_at: NOW.toISOString(), revoked_by: people.hr.user.id, revoked_by_name: 'hr.login', revoke_reason: 'Moving to the Team RVM app' };
    expect(device(db, 1)).toEqual({ ...before.find((d) => d.id === PHONE(1)), ...revoked });
    expect(device(db, 2)).toEqual({ ...before.find((d) => d.id === PHONE(2)), ...revoked });
    // Already reset, and another branch: untouched.
    expect(device(db, 3)).toEqual(before.find((d) => d.id === PHONE(3)));
    expect(device(db, 4)).toEqual(before.find((d) => d.id === PHONE(4)));

    // The write is the Scheduler's: these five columns, only on rows still active.
    const writes = db.writes().filter((w) => w.table === 'hr_attendance_devices');
    expect(writes).toHaveLength(1);
    expect(Object.keys(writes[0].values[0]).sort()).toEqual(['revoke_reason', 'revoked_at', 'revoked_by', 'revoked_by_name', 'status']);
    expect(writes[0].conditions).toContainEqual(['eq', 'status', 'active']);
    expect(db.writes().map((w) => w.table).sort()).toEqual(['hr_attendance_devices', 'hr_ess_audit']);
  });

  it('records the reset in the audit trail: who, which branch, which phones and why', async () => {
    const { app, db, people } = buildApp();
    const res = await reset(app, tokens.portal(people.ceo), { branch_id: BRANCH_PUNE_ID, reason: 'Go-live, Pune' });
    expect(db.tables.hr_ess_audit).toEqual([{
      id: expect.any(String), at: NOW.toISOString(), actor_user_id: people.ceo.user.id, actor_employee_id: people.ceo.employee.id,
      actor_name: 'Test Chief Executive Officer', action: 'devices.reset', target_employee_id: null,
      details: {
        branch_id: BRANCH_PUNE_ID, employees_asked: 1, reset: 1, device_ids: res.body.device_ids,
        employee_ids: [people.pune.employee.id], reason: 'Go-live, Pune',
      },
    }]);
  });

  it('resets a list of people, skipping ids nobody has and repeated ids', async () => {
    const { app, db, people } = buildApp();
    const res = await reset(app, tokens.portal(people.super_admin), {
      employee_ids: [people.pune.employee.id, people.pune.employee.id.toUpperCase(), people.hr.employee.id, 'e0000000-0000-4000-8000-000000000999'],
      reason: 'Changed phones',
    });
    expect(res.body).toEqual({ reset: 1, device_ids: [PHONE(4)] });
    expect(device(db, 4).revoked_by_name).toBe('super_admin.login');
    expect(device(db, 1).status).toBe('active');
  });

  it('resets nothing twice: a second reset of the same branch counts 0', async () => {
    const { app, people } = buildApp();
    await reset(app, tokens.portal(people.hr), { branch_id: BRANCH_ID, reason: 'First go' });
    expect((await reset(app, tokens.portal(people.hr), { branch_id: BRANCH_ID, reason: 'Second go' })).body).toEqual({ reset: 0, device_ids: [] });
  });

  it('takes a list of 500 people, which is more JSON than the ESS\'s usual 16 kB', async () => {
    const { app, people } = buildApp();
    const ids = Array.from({ length: 499 }, (_, i) => `e2000000-0000-4000-8000-${String(i).padStart(12, '0')}`);
    const body = { employee_ids: [...ids, people.pune.employee.id], reason: 'x'.repeat(200) };
    expect(JSON.stringify(body).length).toBeGreaterThan(16 * 1024);
    expect((await reset(app, tokens.portal(people.hr), body)).body).toEqual({ reset: 1, device_ids: [PHONE(4)] });
  });

  it('still refuses a body over 32 kB, and keeps the 16 kB limit everywhere else', async () => {
    const { app, people } = buildApp();
    const big = JSON.stringify({ branch_id: BRANCH_ID, reason: 'x'.repeat(33 * 1024) });
    expectRefusal(await request(app).post(RESET).set(bearer(tokens.portal(people.hr))).set('Content-Type', 'application/json').send(big), 413, 'PAYLOAD_TOO_LARGE');
    const medium = JSON.stringify({ kind: 'correct', details: 'x'.repeat(20 * 1024) });
    expectRefusal(await request(app).post('/api/ess/me/data-requests').set(bearer(tokens.portal(people.hr))).set('Content-Type', 'application/json').send(medium), 413, 'PAYLOAD_TOO_LARGE');
  });

  it('resets a branch of more than 150 people in slices, as long IN lists must be', async () => {
    const { app, db, people } = buildApp({
      setup: (w) => {
        for (let i = 0; i < 160; i++) {
          const id = `e1000000-0000-4000-8000-${String(i).padStart(12, '0')}`;
          w.tables.hr_employees.push({ id, full_name: `Bulk ${i}`, employee_code: `B-${i}`, branch_id: BRANCH_PUNE_ID, is_archived: false, employment_status: 'active' });
          w.tables.hr_attendance_devices.push({ id: `71000000-0000-4000-8000-${String(i).padStart(12, '0')}`, employee_id: id, token_hash: `h${i}`, status: 'active', bound_at: '2026-10-05T04:00:00+00:00' });
        }
      },
    });
    const res = await reset(app, tokens.portal(people.hr), { branch_id: BRANCH_PUNE_ID, reason: 'Go-live, Pune' });
    expect(res.body.reset).toBe(161);
    expect(db.writes().filter((w) => w.table === 'hr_attendance_devices')).toHaveLength(2);
  });

  describe('when a later slice fails, after earlier ones have reset phones', () => {
    const bulkPune = (w) => {
      for (let i = 0; i < 160; i++) {
        const id = `e1000000-0000-4000-8000-${String(i).padStart(12, '0')}`;
        w.tables.hr_employees.push({ id, full_name: `Bulk ${i}`, employee_code: `B-${i}`, branch_id: BRANCH_PUNE_ID, is_archived: false, employment_status: 'active' });
        w.tables.hr_attendance_devices.push({ id: `71000000-0000-4000-8000-${String(i).padStart(12, '0')}`, employee_id: id, token_hash: `h${i}`, status: 'active', bound_at: '2026-10-05T04:00:00+00:00' });
      }
    };
    const failSecondUpdate = (db) => {
      let updates = 0;
      db.failWhen = (q) => (q.table === 'hr_attendance_devices' && q.op === 'update' && ++updates === 2 ? 'error' : null);
    };

    it('answers 503 and records every phone it did reset, marked incomplete, with HR\'s reason', async () => {
      quietErrors();
      const { app, db, people } = buildApp({ setup: bulkPune });
      failSecondUpdate(db);
      const res = await reset(app, tokens.portal(people.hr), { branch_id: BRANCH_PUNE_ID, reason: 'Go-live, Pune' });
      expectRefusal(res, 503, 'UNAVAILABLE');
      const revoked = db.tables.hr_attendance_devices.filter((d) => d.status === 'revoked' && d.revoke_reason === 'Go-live, Pune');
      expect(revoked).toHaveLength(150);
      expect(db.tables.hr_ess_audit).toHaveLength(1);
      const [row] = db.tables.hr_ess_audit;
      expect(row).toMatchObject({ action: 'devices.reset', actor_user_id: people.hr.user.id });
      expect(row.details).toMatchObject({ branch_id: BRANCH_PUNE_ID, employees_asked: 161, reset: 150, incomplete: true, reason: 'Go-live, Pune' });
      expect([...row.details.device_ids].sort()).toEqual(revoked.map((d) => d.id).sort());
    });

    it('puts the same entry in the log when the audit row cannot be written either', async () => {
      const spy = quietErrors();
      const { app, db, people } = buildApp({ setup: bulkPune });
      failSecondUpdate(db);
      db.dropTable('hr_ess_audit');
      expectRefusal(await reset(app, tokens.portal(people.hr), { branch_id: BRANCH_PUNE_ID, reason: 'Go-live, Pune' }), 503, 'UNAVAILABLE');
      const logged = spy.mock.calls.map((c) => c.join(' ')).join('\n');
      const revoked = db.tables.hr_attendance_devices.filter((d) => d.status === 'revoked' && d.revoke_reason === 'Go-live, Pune');
      expect(revoked).toHaveLength(150);
      for (const d of revoked) expect(logged).toContain(d.id);
      expect(logged).toMatch(/AUDIT NOT WRITTEN.*"incomplete":true/);
    });

    it('a retry resets the rest and records them as a complete reset', async () => {
      quietErrors();
      const { app, db, people } = buildApp({ setup: bulkPune });
      failSecondUpdate(db);
      await reset(app, tokens.portal(people.hr), { branch_id: BRANCH_PUNE_ID, reason: 'Go-live, Pune' });
      db.failWhen = null;
      const res = await reset(app, tokens.portal(people.hr), { branch_id: BRANCH_PUNE_ID, reason: 'Go-live, Pune' });
      expect(res.status).toBe(200);
      expect(res.body.reset).toBe(11);
      expect(db.tables.hr_ess_audit[1].details).not.toHaveProperty('incomplete');
    });
  });

  it.each(CALLERS)('%s', async (who, token) => {
    const { app, db, people } = buildApp();
    const res = await reset(app, token(people), { branch_id: BRANCH_ID, reason: 'Moving to the app' });
    const refused = guardOutcome(who, ATTENDANCE_ROLES, 'ATTENDANCE_OVERRIDE_DENIED');
    if (refused) {
      expectRefusal(res, 403, refused);
      expect(db.writes()).toEqual([]);
    } else {
      expect(res.status).toBe(200);
    }
  });

  it('refuses HR on an attendance session with 403 PORTAL_LOGIN_REQUIRED: revoked_by must be a users.id', async () => {
    const { app, db, people } = buildApp({
      setup: (w) => w.tables.hr_attendance_accounts.push({ ...w.people.attendance.account, id: '90000000-0000-4000-8000-000000000096', employee_id: w.people.hr.employee.id }),
    });
    const res = await reset(app, tokens.attendance(people.hr), { branch_id: BRANCH_ID, reason: 'Moving to the app' });
    expectRefusal(res, 403, 'PORTAL_LOGIN_REQUIRED');
    expect(db.writes()).toEqual([]);
  });

  it('names the actor "unknown", as the Scheduler does, when the login has no username', async () => {
    const { app, db, people } = buildApp({ setup: (w) => { w.people.hr.user.username = null; } });
    await reset(app, tokens.portal(people.hr), { employee_ids: [people.pune.employee.id], reason: 'Changed phone' });
    expect(device(db, 4).revoked_by_name).toBe('unknown');
  });

  it.each([
    ['neither branch nor people', { reason: 'Moving' }, MESSAGES.RESET_TARGET],
    ['both', { branch_id: BRANCH_ID, employee_ids: [uuid('e', 1)], reason: 'Moving' }, MESSAGES.RESET_TARGET],
    ['an empty list', { employee_ids: [], reason: 'Moving' }, MESSAGES.RESET_TARGET],
    ['501 people', { employee_ids: Array.from({ length: 501 }, (_, i) => `e2000000-0000-4000-8000-${String(i).padStart(12, '0')}`), reason: 'Moving' }, MESSAGES.RESET_TARGET],
    ['an id that cannot be one', { employee_ids: ['RVM-050'], reason: 'Moving' }, MESSAGES.RESET_TARGET],
    ['a list that is not a list', { employee_ids: uuid('e', 1), reason: 'Moving' }, MESSAGES.RESET_TARGET],
    ['a branch id that cannot be one', { branch_id: 'Faridabad', reason: 'Moving' }, MESSAGES.BRANCH_ID],
    ['no reason', { branch_id: BRANCH_ID }, MESSAGES.RESET_REASON],
    ['a 2-character reason', { branch_id: BRANCH_ID, reason: ' ok ' }, MESSAGES.RESET_REASON],
    ['a reason over 200 characters', { branch_id: BRANCH_ID, reason: 'x'.repeat(201) }, MESSAGES.RESET_REASON],
    ['a field it does not take', { branch_id: BRANCH_ID, reason: 'Moving', status: 'active' }, MESSAGES.UNKNOWN_FIELD],
  ])('refuses %s with 400, and writes nothing', async (_label, body, message) => {
    const { app, db, people } = buildApp();
    expectInvalid(await reset(app, tokens.portal(people.hr), body), message);
    expect(db.writes()).toEqual([]);
  });

  it('answers 404 NOT_FOUND for a branch that is not there', async () => {
    const { app, db, people } = buildApp();
    expectRefusal(await reset(app, tokens.portal(people.hr), { branch_id: 'b0000000-0000-4000-8000-000000000999', reason: 'Moving' }), 404, 'NOT_FOUND');
    expect(db.writes()).toEqual([]);
  });

  it('still answers the reset when the audit row cannot be written, and puts the entry in the log', async () => {
    const spy = quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_audit');
    const res = await reset(app, tokens.portal(people.hr), { employee_ids: [people.pune.employee.id], reason: 'Changed phone' });
    expect(res.body.reset).toBe(1);
    expect(spy).toHaveBeenCalledWith(expect.stringMatching(new RegExp(`AUDIT NOT WRITTEN.*devices\\.reset.*${PHONE(4)}`)));
  });

  it('answers 503 MODULE_NOT_INSTALLED before migration 20261020000000', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_attendance_devices');
    expectRefusal(await reset(app, tokens.portal(people.hr), { branch_id: BRANCH_ID, reason: 'Moving' }), 503, 'MODULE_NOT_INSTALLED');
  });

  it('answers 503 UNAVAILABLE during an outage, never a 401', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    const realFrom = db.from;
    db.from = (table) => {
      if (table === 'hr_attendance_devices') db.outage = 'error';
      return realFrom(table);
    };
    expectRefusal(await reset(app, tokens.portal(people.hr), { branch_id: BRANCH_ID, reason: 'Moving' }), 503, 'UNAVAILABLE');
  });
});
