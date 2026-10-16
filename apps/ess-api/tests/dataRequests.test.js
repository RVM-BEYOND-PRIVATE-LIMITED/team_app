const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { NOW } = require('./helpers/constants');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors, CALLERS, guardOutcome } = require('./helpers/expect');

/** Task A8: requests to correct or delete my data, and HR's queue for them. */

const MINE = '/api/ess/me/data-requests';
const HR = '/api/ess/hr/data-requests';
const HR_ROLES = ['hr', 'hr_executive', 'ceo', 'super_admin'];

const file = (app, token, body) => request(app).post(MINE).set(bearer(token)).send(body);
const resolve = (app, token, id, body) => request(app).patch(`${HR}/${id}`).set(bearer(token)).send(body);

/** A world with one open request from the attendance employee and one from HR, filed through the API. */
async function withRequests(options) {
  const world = buildApp(options);
  const { app, people } = world;
  const fromStaff = await file(app, tokens.attendance(people.attendance), { kind: 'correct', details: 'My employee code is wrong.' });
  const fromHr = await file(app, tokens.portal(people.hr), { kind: 'delete', details: 'Delete my old address.' });
  return { ...world, staffRequest: fromStaff.body.request, hrRequest: fromHr.body.request };
}

describe('POST /api/ess/me/data-requests', () => {
  it.each([['a portal login', (p) => tokens.portal(p.faculty), 'faculty'], ['an attendance session', (p) => tokens.attendance(p.attendance), 'attendance']])(
    'files a request for %s, about the caller only',
    async (_label, token, who) => {
      const { app, db, people } = buildApp();
      const res = await file(app, token(people), { kind: 'delete', details: '  Please delete my second phone number.  ' });
      expect(res.status).toBe(201);
      expect(res.body).toEqual({
        request: {
          id: expect.any(String),
          kind: 'delete',
          details: 'Please delete my second phone number.',
          status: 'open',
          created_at: NOW.toISOString(),
          resolved_at: null,
          resolution_note: null,
        },
      });
      const stored = db.tables.hr_ess_data_requests;
      expect(stored).toHaveLength(1);
      expect(stored[0].employee_id).toBe(people[who].employee.id);
    },
  );

  it('takes no employee id from the body, so nobody can file in somebody else\'s name', async () => {
    const { app, people } = buildApp();
    const res = await file(app, tokens.portal(people.faculty), { kind: 'correct', details: 'Fix my name.', employee_id: people.hr.employee.id });
    expectInvalid(res, MESSAGES.UNKNOWN_FIELD);
  });

  it.each([
    ['no kind', { details: 'Fix my name please.' }, MESSAGES.DATA_REQUEST_KIND],
    ['another kind', { kind: 'export', details: 'Fix my name please.' }, MESSAGES.DATA_REQUEST_KIND],
    ['no details', { kind: 'correct' }, MESSAGES.DATA_REQUEST_DETAILS],
    ['details that are only spaces', { kind: 'correct', details: '      ' }, MESSAGES.DATA_REQUEST_DETAILS],
    ['details under 5 characters', { kind: 'correct', details: 'fix' }, MESSAGES.DATA_REQUEST_DETAILS],
    ['details over 2,000 characters', { kind: 'correct', details: 'x'.repeat(2001) }, MESSAGES.DATA_REQUEST_DETAILS],
    ['details that are not text', { kind: 'correct', details: 12345 }, MESSAGES.DATA_REQUEST_DETAILS],
    ['a list for a body', [{ kind: 'correct' }], MESSAGES.BODY_NOT_OBJECT],
  ])('refuses %s with 400', async (_label, body, message) => {
    const { app, people } = buildApp();
    expectInvalid(await file(app, tokens.portal(people.faculty), body), message);
  });

  it('counts 2,000 characters as characters, not UTF-16 units', async () => {
    const { app, people } = buildApp();
    const res = await file(app, tokens.portal(people.faculty), { kind: 'correct', details: '👍'.repeat(2000) });
    expect(res.status).toBe(201);
  });

  it('refuses a sixth open request with 409 TOO_MANY_OPEN_REQUESTS, and takes one again once HR answers', async () => {
    const { app, people } = buildApp();
    const token = tokens.attendance(people.attendance);
    const ids = [];
    for (let i = 0; i < 5; i++) ids.push((await file(app, token, { kind: 'correct', details: `Request number ${i}` })).body.request.id);
    expectRefusal(await file(app, token, { kind: 'correct', details: 'One request too many' }), 409, 'TOO_MANY_OPEN_REQUESTS');
    expect((await resolve(app, tokens.portal(people.hr), ids[0], { status: 'done' })).status).toBe(200);
    expect((await file(app, token, { kind: 'correct', details: 'Room for this one' })).status).toBe(201);
  });

  it('holds the limit of five when requests arrive in parallel: the database counts, under a lock', async () => {
    const spy = quietErrors();
    const { app, db, people } = buildApp();
    const realFrom = db.from;
    db.from = (table) => {
      const q = realFrom(table);
      const run = q.run.bind(q);
      q.run = async () => { await new Promise((r) => { setTimeout(r, 15); }); return run(); };
      return q;
    };
    const token = tokens.portal(people.faculty);
    const results = await Promise.all(Array.from({ length: 12 }, (_, i) => file(app, token, { kind: 'correct', details: `Request number ${i}` })));
    const open = db.tables.hr_ess_data_requests.filter((r) => r.employee_id === people.faculty.employee.id && r.status === 'open');
    expect(results.filter((r) => r.status === 201)).toHaveLength(5);
    for (const r of results.filter((x) => x.status !== 201)) expectRefusal(r, 409, 'TOO_MANY_OPEN_REQUESTS');
    expect(open).toHaveLength(5);
    // The database's refusal is an expected answer, not a failure to report.
    expect(spy).not.toHaveBeenCalled();
  });

  it('answers 503 MODULE_NOT_INSTALLED, naming the table, before the migration', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_data_requests');
    const res = await file(app, tokens.portal(people.faculty), { kind: 'correct', details: 'Fix my name please.' });
    expectRefusal(res, 503, 'MODULE_NOT_INSTALLED');
    expect(res.body.error).toMatch(/hr_ess_data_requests/);
  });

  it('answers 401 with no token and 503 UNAVAILABLE during an outage, never a 401', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    expectRefusal(await request(app).post(MINE).send({ kind: 'correct', details: 'Fix my name.' }), 401, 'NOT_AUTHENTICATED');
    const token = tokens.portal(people.faculty);
    db.outage = 'error';
    expectRefusal(await file(app, token, { kind: 'correct', details: 'Fix my name.' }), 503, 'UNAVAILABLE');
  });

  it('is refused to a session still on HR\'s first-time password, as every ESS endpoint is', async () => {
    const { app, people } = buildApp({ setup: (w) => { w.people.attendance.account.password_set_at = null; } });
    expectRefusal(await file(app, tokens.attendance(people.attendance, 'pw'), { kind: 'correct', details: 'Fix my name.' }), 403, 'PASSWORD_CHANGE_REQUIRED');
  });
});

describe('GET /api/ess/me/data-requests', () => {
  it('lists the caller\'s own requests only, newest first, without HR\'s account details', async () => {
    const { app, people, db } = await withRequests();
    db.tables.hr_ess_data_requests.push({
      id: '50000000-0000-4000-8000-000000000001', employee_id: people.attendance.employee.id, kind: 'delete',
      details: 'An older request.', status: 'rejected', created_at: '2026-10-01T04:00:00.000Z', resolved_at: '2026-10-02T04:00:00.000Z',
      resolved_by_user_id: people.hr.user.id, resolved_by_name: 'Test HR Manager', resolution_note: 'We must keep this for payroll.',
    });
    const res = await request(app).get(MINE).set(bearer(tokens.attendance(people.attendance)));
    expect(res.status).toBe(200);
    expect(res.body.requests.map((r) => r.details)).toEqual(['My employee code is wrong.', 'An older request.']);
    expect(res.body.requests[1]).toEqual({
      id: '50000000-0000-4000-8000-000000000001', kind: 'delete', details: 'An older request.', status: 'rejected',
      created_at: '2026-10-01T04:00:00.000Z', resolved_at: '2026-10-02T04:00:00.000Z', resolution_note: 'We must keep this for payroll.',
    });
    expect(JSON.stringify(res.body)).not.toMatch(/resolved_by|Delete my old address/);
  });

  it('is an empty list for somebody with none', async () => {
    const { app, people } = await withRequests();
    const res = await request(app).get(MINE).set(bearer(tokens.portal(people.faculty)));
    expect(res.body).toEqual({ requests: [] });
  });

  it('answers 503 MODULE_NOT_INSTALLED before the migration', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_data_requests');
    expectRefusal(await request(app).get(MINE).set(bearer(tokens.portal(people.faculty))), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('GET /api/ess/hr/data-requests', () => {
  it.each(CALLERS)('%s', async (who, token) => {
    const { app, people } = await withRequests();
    const res = await request(app).get(HR).set(bearer(token(people)));
    const refused = guardOutcome(who, HR_ROLES, 'HR_ACCESS_DENIED');
    if (refused) {
      expectRefusal(res, 403, refused);
      expect(res.body.error).toBe(MESSAGES[refused]);
    } else {
      expect(res.status).toBe(200);
    }
  });

  it('shows the open requests by default, newest first, with whose each is', async () => {
    const { app, people, db } = await withRequests();
    db.tables.hr_ess_data_requests[0].created_at = '2026-10-16T06:00:00.000Z';
    const res = await request(app).get(HR).set(bearer(tokens.portal(people.hr_executive)));
    expect(res.body.truncated).toBe(false);
    expect(res.body.requests.map((r) => r.employee.id)).toEqual([people.hr.employee.id, people.attendance.employee.id]);
    expect(res.body.requests[1]).toEqual({
      id: expect.any(String), kind: 'correct', details: 'My employee code is wrong.', status: 'open',
      created_at: '2026-10-16T06:00:00.000Z', resolved_at: null, resolution_note: null, resolved_by_name: null,
      employee: { id: people.attendance.employee.id, full_name: 'Test Office Assistant', employee_code: 'RVM-050' },
    });
    // The card, never the rest of the HR record.
    expect(JSON.stringify(res.body)).not.toMatch(/phone|email|9710000050/);
  });

  it.each([
    ['done', 1],
    ['rejected', 0],
    ['open', 1],
    ['all', 2],
  ])('filters with status=%s', async (status, count) => {
    const { app, people, staffRequest } = await withRequests();
    await resolve(app, tokens.portal(people.hr), staffRequest.id, { status: 'done', note: 'Corrected.' });
    const res = await request(app).get(`${HR}?status=${status}`).set(bearer(tokens.portal(people.super_admin)));
    expect(res.body.requests).toHaveLength(count);
  });

  it.each([['status=closed'], ['status=open&status=done']])('refuses ?%s with 400', async (query) => {
    const { app, people } = buildApp();
    expectInvalid(await request(app).get(`${HR}?${query}`).set(bearer(tokens.portal(people.hr))), MESSAGES.DATA_REQUEST_STATUS_FILTER);
  });

  it('answers 503 MODULE_NOT_INSTALLED before the migration', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_data_requests');
    expectRefusal(await request(app).get(HR).set(bearer(tokens.portal(people.hr))), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('PATCH /api/ess/hr/data-requests/:id', () => {
  it('marks a request done, says who did it, and records it in the audit trail', async () => {
    const { app, db, people, staffRequest } = await withRequests();
    const res = await resolve(app, tokens.portal(people.hr), staffRequest.id, { status: 'done', note: 'Code corrected to RVM-050.' });
    expect(res.status).toBe(200);
    expect(res.body.request).toEqual({
      ...staffRequest,
      status: 'done',
      resolved_at: NOW.toISOString(),
      resolution_note: 'Code corrected to RVM-050.',
      resolved_by_name: 'Test HR Manager',
      employee: { id: people.attendance.employee.id, full_name: 'Test Office Assistant', employee_code: 'RVM-050' },
    });
    expect(db.tables.hr_ess_data_requests.find((r) => r.id === staffRequest.id).resolved_by_user_id).toBe(people.hr.user.id);
    expect(db.tables.hr_ess_audit).toEqual([{
      id: expect.any(String),
      at: NOW.toISOString(),
      actor_user_id: people.hr.user.id,
      actor_employee_id: people.hr.employee.id,
      actor_name: 'Test HR Manager',
      action: 'data_request.resolved',
      target_employee_id: people.attendance.employee.id,
      details: { request_id: staffRequest.id, kind: 'correct', status: 'done' },
    }]);
    // The employee sees the answer.
    const mine = await request(app).get(MINE).set(bearer(tokens.attendance(people.attendance)));
    expect(mine.body.requests[0]).toMatchObject({ status: 'done', resolution_note: 'Code corrected to RVM-050.' });
  });

  it('rejects a request with the reason the employee is owed', async () => {
    const { app, people, staffRequest } = await withRequests();
    const res = await resolve(app, tokens.portal(people.hr_executive), staffRequest.id, { status: 'rejected', note: 'Your code is right.' });
    expect(res.status).toBe(200);
    expect(res.body.request).toMatchObject({ status: 'rejected', resolution_note: 'Your code is right.', resolved_by_name: 'Test HR Executive' });
  });

  it('marks a request done with no note', async () => {
    const { app, people, staffRequest } = await withRequests();
    const res = await resolve(app, tokens.portal(people.super_admin), staffRequest.id, { status: 'done' });
    expect(res.status).toBe(200);
    expect(res.body.request.resolution_note).toBeNull();
  });

  it('refuses an HR person their own request with 409 OWN_REQUEST, and lets a colleague resolve it', async () => {
    const { app, db, people, hrRequest } = await withRequests();
    expectRefusal(await resolve(app, tokens.portal(people.hr), hrRequest.id, { status: 'done' }), 409, 'OWN_REQUEST');
    expect(db.tables.hr_ess_data_requests.find((r) => r.id === hrRequest.id).status).toBe('open');
    expect(db.tables.hr_ess_audit || []).toEqual([]);
    expect((await resolve(app, tokens.portal(people.hr_executive), hrRequest.id, { status: 'done' })).status).toBe(200);
  });

  it('refuses a request already resolved with 409 ALREADY_RESOLVED', async () => {
    const { app, people, staffRequest } = await withRequests();
    await resolve(app, tokens.portal(people.hr), staffRequest.id, { status: 'done' });
    expectRefusal(await resolve(app, tokens.portal(people.super_admin), staffRequest.id, { status: 'rejected', note: 'Too late.' }), 409, 'ALREADY_RESOLVED');
  });

  it('refuses the loser of two HR people answering at once with 409 ALREADY_RESOLVED', async () => {
    const { app, db, people, staffRequest } = await withRequests();
    // The other answer lands between this request's read and its write.
    const realFrom = db.from;
    db.from = (table) => {
      const q = realFrom(table);
      const realUpdate = q.update.bind(q);
      q.update = (patch) => {
        db.tables.hr_ess_data_requests.find((r) => r.id === staffRequest.id).status = 'done';
        return realUpdate(patch);
      };
      return q;
    };
    expectRefusal(await resolve(app, tokens.portal(people.hr), staffRequest.id, { status: 'rejected', note: 'No.' }), 409, 'ALREADY_RESOLVED');
  });

  it('answers 404 NOT_FOUND for a request that is not there, and 400 for an id that cannot be one', async () => {
    const { app, people } = await withRequests();
    expectRefusal(await resolve(app, tokens.portal(people.hr), '50000000-0000-4000-8000-000000000999', { status: 'done' }), 404, 'NOT_FOUND');
    expectInvalid(await resolve(app, tokens.portal(people.hr), 'not-an-id', { status: 'done' }), MESSAGES.INVALID_ID);
  });

  it.each([
    ['no status', { note: 'Done.' }, MESSAGES.RESOLVE_STATUS],
    ['status open', { status: 'open' }, MESSAGES.RESOLVE_STATUS],
    ['a rejection with no note', { status: 'rejected' }, MESSAGES.REJECT_NOTE_REQUIRED],
    ['a rejection with a 2-character note', { status: 'rejected', note: 'no' }, MESSAGES.REJECT_NOTE_REQUIRED],
    ['a note over 1,000 characters', { status: 'done', note: 'x'.repeat(1001) }, MESSAGES.RESOLVE_NOTE],
    ['a note that is not text', { status: 'done', note: 5 }, MESSAGES.RESOLVE_NOTE],
    ['a field it does not take', { status: 'done', resolved_by_name: 'Somebody else' }, MESSAGES.UNKNOWN_FIELD],
  ])('refuses %s with 400', async (_label, body, message) => {
    const { app, people, staffRequest } = await withRequests();
    expectInvalid(await resolve(app, tokens.portal(people.hr), staffRequest.id, body), message);
  });

  it.each(CALLERS)('%s', async (who, token) => {
    const { app, people, staffRequest } = await withRequests();
    const res = await resolve(app, token(people), staffRequest.id, { status: 'done' });
    const refused = guardOutcome(who, HR_ROLES, 'HR_ACCESS_DENIED');
    if (refused) expectRefusal(res, 403, refused);
    else expect(res.status).toBe(200);
  });

  it('still resolves when the audit row cannot be written, and puts the entry in the log', async () => {
    const spy = quietErrors();
    const { app, db, people, staffRequest } = await withRequests();
    db.dropTable('hr_ess_audit');
    const res = await resolve(app, tokens.portal(people.hr), staffRequest.id, { status: 'done' });
    expect(res.status).toBe(200);
    expect(spy).toHaveBeenCalledWith(expect.stringMatching(/AUDIT NOT WRITTEN.*data_request\.resolved/));
  });

  it('answers 503 MODULE_NOT_INSTALLED before the migration', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_data_requests');
    expectRefusal(await resolve(app, tokens.portal(people.hr), '50000000-0000-4000-8000-000000000001', { status: 'done' }), 503, 'MODULE_NOT_INSTALLED');
  });
});
