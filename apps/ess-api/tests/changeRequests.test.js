const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');
const D = require('./helpers/documentsFixtures');

/** Phase 2C, E3: profile-change requests — my asks, HR's queue, and the decision HR records. */

const MY = '/api/ess/me/change-requests';
const HR = '/api/ess/hr/change-requests';

const ask = (app, token, body) => request(app).post(MY).set(bearer(token)).send(body);
const askBody = (change = {}) => ({
  field: 'address',
  old_value: 'House 12, Sector 21',
  new_value: 'House 14, Sector 22',
  reason: 'The record has the old house number.',
  ...change,
});

describe('POST /api/ess/me/change-requests', () => {
  it('files one ask, with what it says now and what it should read', async () => {
    const { app, db, people } = buildApp();
    const res = await ask(app, tokens.portal(people.faculty), askBody());
    expect(res.status).toBe(201);
    expect(res.body.request).toEqual(expect.objectContaining({
      employee_id: people.faculty.employee.id,
      field: 'address',
      status: 'open',
      decided_by_name: null,
    }));
    expect(db.tables.hr_ess_change_requests).toEqual([
      expect.objectContaining({ field: 'address', status: 'open' }),
    ]);
  });

  it('files one without "what it says now", when the person does not know', async () => {
    const { app, people } = buildApp();
    const res = await ask(app, tokens.portal(people.faculty), askBody({ old_value: null }));
    expect(res.status).toBe(201);
    expect(res.body.request.old_value).toBeNull();
  });

  it('refuses a field that is not one of the three, and thin or long text', async () => {
    const { app, people } = buildApp();
    expectInvalid(await ask(app, tokens.portal(people.faculty), askBody({ field: 'salary' })),
      MESSAGES.CHANGE_FIELD);
    expectInvalid(await ask(app, tokens.portal(people.faculty), askBody({ new_value: ' ' })),
      MESSAGES.CHANGE_NEW_VALUE);
    expectInvalid(await ask(app, tokens.portal(people.faculty), askBody({ reason: 'no' })),
      MESSAGES.CHANGE_REASON);
    expectInvalid(await ask(app, tokens.portal(people.faculty), askBody({ old_value: 'x'.repeat(501) })),
      MESSAGES.CHANGE_OLD_VALUE);
  });

  it('refuses a second open ask for the same field, with the 409 the contract quotes', async () => {
    const { app, db, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_change_requests = [D.changeRequestRow(w.people.faculty.employee.id, 1)];
    } });
    const res = await ask(app, tokens.portal(people.faculty), askBody());
    expectRefusal(res, 409, 'CHANGE_ALREADY_OPEN');
    expect(res.body.error).toBe(MESSAGES.CHANGE_ALREADY_OPEN);
    expect(db.tables.hr_ess_change_requests).toHaveLength(1);
    // Another field still gets through, and an answered ask makes room for the next.
    const other = await ask(app, tokens.portal(people.faculty), askBody({ field: 'legal_name' }));
    expect(other.status).toBe(201);
    db.tables.hr_ess_change_requests[0].status = 'rejected';
    const again = await ask(app, tokens.portal(people.faculty), askBody());
    expect(again.status).toBe(201);
  });

  it('answers 503 when the table has not been applied', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_change_requests');
    expectRefusal(await ask(app, tokens.portal(people.faculty), askBody()), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('GET /api/ess/me/change-requests', () => {
  it('lists my asks, newest first, and nothing of anybody else\'s', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_change_requests = [
        D.changeRequestRow(w.people.faculty.employee.id, 2, { created_at: '2026-10-15T05:00:00+00:00' }),
        D.changeRequestRow(w.people.faculty.employee.id, 1, { field: 'legal_name' }),
        D.changeRequestRow(w.people.hod.employee.id, 3),
      ];
    } });
    const res = await request(app).get(MY).set(bearer(tokens.portal(people.faculty)));
    expect(res.status).toBe(200);
    expect(res.body.requests.map((r) => r.field)).toEqual(['legal_name', 'address']);
  });
});

describe('HR change requests (E3)', () => {
  it('lists the queue, held to a status', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_change_requests = [
        D.changeRequestRow(w.people.faculty.employee.id, 1),
        D.changeRequestRow(w.people.hod.employee.id, 2, { status: 'approved', decided_by_name: 'Test HR Manager', decided_at: D.AT }),
      ];
    } });
    const res = await request(app).get(HR).set(bearer(tokens.portal(people.hr)));
    expect(res.status).toBe(200);
    expect(res.body.requests).toHaveLength(2);
    expect(JSON.stringify(res.body)).not.toContain('decided_by_user_id');
    const open = await request(app).get(`${HR}?status=open`).set(bearer(tokens.portal(people.hr)));
    expect(open.body.requests).toHaveLength(1);
    expectInvalid(await request(app).get(`${HR}?status=withdrawn`).set(bearer(tokens.portal(people.hr))),
      MESSAGES.CHANGE_STATUS_FILTER);
  });

  it('approves, recording the decision only — the record itself is never written', async () => {
    const { app, db, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_change_requests = [D.changeRequestRow(w.people.faculty.employee.id, 1)];
    } });
    const res = await request(app)
      .post(`/api/ess/hr/change-requests/${D.CHANGE_ID(1)}/decide`)
      .set(bearer(tokens.portal(people.hr_executive)))
      .send({ decision: 'approved', note: 'Corrected in the record.' });
    expect(res.status).toBe(200);
    expect(res.body.request).toEqual(expect.objectContaining({
      status: 'approved', decided_by_name: 'Test HR Executive', decision_note: 'Corrected in the record.',
    }));
    // The ESS keeps the decision on its own row; hr_employees carries nothing new.
    expect(db.tables.hr_ess_change_requests[0].status).toBe('approved');
    expect(JSON.stringify(db.tables.hr_employees)).not.toContain('House 14');
  });

  it('refuses a rejection without the reason the employee sees, and a second decide', async () => {
    quietErrors();
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_change_requests = [D.changeRequestRow(w.people.faculty.employee.id, 1)];
    } });
    const url = `/api/ess/hr/change-requests/${D.CHANGE_ID(1)}/decide`;
    expectInvalid(await request(app).post(url).set(bearer(tokens.portal(people.hr)))
      .send({ decision: 'rejected' }), MESSAGES.CHANGE_REJECT_NOTE);
    const ok = await request(app).post(url).set(bearer(tokens.portal(people.hr)))
      .send({ decision: 'rejected', note: 'No proof attached.' });
    expect(ok.status).toBe(200);
    expectRefusal(await request(app).post(url).set(bearer(tokens.portal(people.hr)))
      .send({ decision: 'approved' }), 409, 'ALREADY_DECIDED');
  });

  it('refuses a decision that is not one, a missing request, and a faculty caller', async () => {
    quietErrors();
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_change_requests = [D.changeRequestRow(w.people.faculty.employee.id, 1)];
    } });
    expectInvalid(await request(app).post(`/api/ess/hr/change-requests/${D.CHANGE_ID(1)}/decide`)
      .set(bearer(tokens.portal(people.hr))).send({ decision: 'deferred' }), MESSAGES.CHANGE_DECISION);
    expectRefusal(await request(app).post(`/api/ess/hr/change-requests/${D.CHANGE_ID(9)}/decide`)
      .set(bearer(tokens.portal(people.hr))).send({ decision: 'approved' }), 404, 'NOT_FOUND');
    expectRefusal(await request(app).get(HR).set(bearer(tokens.portal(people.faculty))), 403, 'HR_ACCESS_DENIED');
  });
});
