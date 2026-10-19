const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');
const D = require('./helpers/documentsFixtures');

/** Phase 2C, KP 3: bank details — the person's own entry, the consent it carries, HR's masked read. */

const MY = '/api/ess/me/bank-details';

const save = (app, token, body) => request(app).put(MY).set(bearer(token)).send(body);
const saveBody = (change = {}) => ({
  bank_name: 'State Bank of India',
  branch_name: 'Faridabad Sector 21',
  account_number: '1234567890',
  ifsc_code: 'SBIN0001234',
  consent: true,
  consent_name: 'Test CAD Faculty',
  ...change,
});

describe('GET /api/ess/me/bank-details', () => {
  it('answers null while nothing is saved, and my whole row once it is', async () => {
    const { app, people } = buildApp();
    const empty = await request(app).get(MY).set(bearer(tokens.portal(people.faculty)));
    expect(empty.status).toBe(200);
    expect(empty.body.bank_details).toBeNull();

    const { app: full, people: fullPeople } = buildApp({ setup: (w) => {
      w.tables.hr_ess_bank_details = [D.bankRow(w.people.faculty.employee.id)];
    } });
    const res = await request(full).get(MY).set(bearer(tokens.portal(fullPeople.faculty)));
    expect(res.status).toBe(200);
    expect(res.body.bank_details).toEqual(expect.objectContaining({
      bank_name: 'State Bank of India',
      account_number: '1234567890', // the owner sees the whole number
      ifsc_code: 'SBIN0001234',
      consent_name: 'Test CAD Faculty',
    }));
  });
});

describe('PUT /api/ess/me/bank-details', () => {
  it('saves my details with the consent stamped, and again in place', async () => {
    const { app, db, people } = buildApp();
    const first = await save(app, tokens.portal(people.faculty), saveBody());
    expect(first.status).toBe(200);
    expect(first.body.bank_details).toEqual(expect.objectContaining({
      account_number: '1234567890',
      consent_given_at: expect.any(String),
      consent_name: 'Test CAD Faculty',
      updated_by_name: 'Test CAD Faculty',
    }));
    expect(db.tables.hr_ess_bank_details).toHaveLength(1);
    // A second save updates the one row in place; there is never a second row per person.
    const again = await save(app, tokens.portal(people.faculty), saveBody({ bank_name: 'HDFC Bank' }));
    expect(again.status).toBe(200);
    expect(again.body.bank_details.bank_name).toBe('HDFC Bank');
    expect(db.tables.hr_ess_bank_details).toHaveLength(1);
  });

  it('refuses the shapes the database holds: the IFSC, the account number, and the lengths', async () => {
    const { app, people } = buildApp();
    expectInvalid(await save(app, tokens.portal(people.faculty), saveBody({ ifsc_code: 'sbin000123' })),
      MESSAGES.BANK_IFSC);
    expectInvalid(await save(app, tokens.portal(people.faculty), saveBody({ ifsc_code: 'SBIN1234567' })),
      MESSAGES.BANK_IFSC);
    expectInvalid(await save(app, tokens.portal(people.faculty), saveBody({ account_number: '12345' })),
      MESSAGES.BANK_ACCOUNT);
    // Digits only: a lettered account number never saves.
    expectInvalid(await save(app, tokens.portal(people.faculty), saveBody({ account_number: '1234AB7890' })),
      MESSAGES.BANK_ACCOUNT);
    expectInvalid(await save(app, tokens.portal(people.faculty), saveBody({ bank_name: 'S' })),
      MESSAGES.BANK_NAME);
    expectInvalid(await save(app, tokens.portal(people.faculty), saveBody({ branch_name: 'x'.repeat(121) })),
      MESSAGES.BANK_BRANCH);
    expectInvalid(await save(app, tokens.portal(people.faculty), saveBody({ upi_id: 'a@' })),
      MESSAGES.BANK_UPI);
  });

  it('refuses a save without the consent, and one with a name that is not there', async () => {
    const { app, people } = buildApp();
    expectInvalid(await save(app, tokens.portal(people.faculty), saveBody({ consent: false })),
      MESSAGES.BANK_CONSENT);
    expectInvalid(await save(app, tokens.portal(people.faculty), { ...saveBody(), consent: undefined }),
      MESSAGES.BANK_CONSENT);
    expectInvalid(await save(app, tokens.portal(people.faculty), saveBody({ consent_name: '  ' })),
      MESSAGES.BANK_CONSENT_NAME);
  });

  it('refuses an unknown field, and answers 503 when the table has not been applied', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    expectInvalid(await save(app, tokens.portal(people.faculty), { ...saveBody(), aadhaar_number: '1234' }),
      MESSAGES.UNKNOWN_FIELD);
    db.dropTable('hr_ess_bank_details');
    expectRefusal(await save(app, tokens.portal(people.faculty), saveBody()), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('GET /api/ess/hr/employees/:id/bank-details', () => {
  it('masks the account number to its last four digits, and audits the read first', async () => {
    quietErrors();
    const { app, db, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_bank_details = [D.bankRow(w.people.faculty.employee.id)];
    } });
    const res = await request(app).get(`/api/ess/hr/employees/${people.faculty.employee.id}/bank-details`)
      .set(bearer(tokens.portal(people.hr_executive)));
    expect(res.status).toBe(200);
    expect(res.body.bank_details.account_number).toBe('******7890');
    expect(JSON.stringify(res.body)).not.toContain('1234567890');
    expect(db.tables.hr_ess_audit).toEqual([
      expect.objectContaining({ action: 'bank_details.read', target_employee_id: people.faculty.employee.id }),
    ]);
  });

  it('audits an empty read too, and answers 404 for nobody', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    expectRefusal(await request(app).get(`/api/ess/hr/employees/${D.uuid('e', 98)}/bank-details`)
      .set(bearer(tokens.portal(people.hr))), 404, 'NOT_FOUND');
    expect(db.tables.hr_ess_audit).toEqual([
      expect.objectContaining({ action: 'bank_details.read', details: { found: false } }),
    ]);
  });

  it('refuses a faculty caller', async () => {
    const { app, people } = buildApp();
    expectRefusal(await request(app).get(`/api/ess/hr/employees/${people.hod.employee.id}/bank-details`)
      .set(bearer(tokens.portal(people.faculty))), 403, 'HR_ACCESS_DENIED');
  });
});
