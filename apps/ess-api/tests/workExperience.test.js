const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');

/** Issue #31: my work experience — self only, newest first, replaced as a whole. */

const PATH = '/api/ess/me/work-experience';

const entry = (change = {}) => ({
  company: 'RVM CAD',
  role_title: 'CAD Faculty',
  from_date: '2023-04-01',
  is_current: true,
  location: 'Faridabad',
  description: 'AutoCAD and 3D modelling.',
  is_visible: true,
  ...change,
});

const as = (app, person) => request(app).get(PATH).set(bearer(tokens.portal(person)));
const put = (app, person, body) => request(app).put(PATH).set(bearer(tokens.portal(person))).send(body);

describe('GET /api/ess/me/work-experience', () => {
  it('returns my whole list, hidden entries included, newest first', async () => {
    const { app, people } = buildApp({
      setup: (w) => {
        w.tables.hr_ess_work_experience = [
          { id: '1a000000-0000-4000-8000-000000000001', employee_id: w.people.faculty.employee.id, company: 'ACME Ltd', role_title: 'Designer', from_date: '2020-06-01', to_date: '2023-03-31', is_current: false, location: null, description: null, is_visible: false, created_at: '2026-10-16T06:00:00+00:00', updated_at: '2026-10-16T06:00:00+00:00' },
          { id: '1a000000-0000-4000-8000-000000000002', employee_id: w.people.faculty.employee.id, company: 'RVM CAD', role_title: 'CAD Faculty', from_date: '2023-04-01', to_date: null, is_current: true, location: 'Faridabad', description: 'AutoCAD.', is_visible: true, created_at: '2026-10-16T06:00:00+00:00', updated_at: '2026-10-16T06:00:00+00:00' },
        ];
      },
    });
    const res = await as(app, people.faculty);
    expect(res.status).toBe(200);
    expect(res.body.entries.map((e) => e.company)).toEqual(['RVM CAD', 'ACME Ltd']);
    expect(res.body.entries[1].is_visible).toBe(false);
    expect(Object.keys(res.body.entries[0]).sort()).toEqual([
      'company', 'description', 'from_date', 'id', 'is_current', 'is_visible', 'location', 'role_title', 'to_date',
    ]);
  });

  it('is self only: HR sees their own empty list, not mine', async () => {
    const { app, people } = buildApp();
    await put(app, people.faculty, { entries: [entry()] });
    const mine = await as(app, people.faculty);
    expect(mine.body.entries).toHaveLength(1);
    const hr = await as(app, people.hr);
    expect(hr.body.entries).toEqual([]);
  });

  it('answers 401 with no token and 403 for the desk login', async () => {
    const { app, people } = buildApp();
    expectRefusal(await request(app).get(PATH), 401, 'NOT_AUTHENTICATED');
    expectRefusal(await request(app).get(PATH).set(bearer(tokens.portal(people.desk))), 403, 'NOT_LINKED');
  });

  it('answers 503 when the migration has not been applied', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    db.dropTable('hr_ess_work_experience');
    expectRefusal(await as(app, people.faculty), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('PUT /api/ess/me/work-experience', () => {
  it('replaces the list and returns it in the saved order', async () => {
    const { app, people, db } = buildApp();
    const res = await put(app, people.faculty, {
      entries: [
        entry({ company: 'RVM CAD', from_date: '2023-04-01' }),
        entry({ company: 'ACME Ltd', role_title: 'Designer', from_date: '2020-06-01', to_date: '2023-03-31', is_current: false }),
      ],
    });
    expect(res.status).toBe(200);
    expect(res.body.entries.map((e) => e.company)).toEqual(['RVM CAD', 'ACME Ltd']);
    expect(res.body.entries[1].is_current).toBe(false);
    expect(db.tables.hr_ess_work_experience).toHaveLength(2);
    // The audit carries the count, never the company names.
    const audit = db.tables.hr_ess_audit.find((a) => a.action === 'work_experience.changed');
    expect(audit.details).toEqual({ count: 2 });
    expect(JSON.stringify(audit)).not.toContain('ACME');
  });

  it('clears the list with an empty array', async () => {
    const { app, people, db } = buildApp();
    await put(app, people.faculty, { entries: [entry()] });
    const res = await put(app, people.faculty, { entries: [] });
    expect(res.status).toBe(200);
    expect(res.body.entries).toEqual([]);
    expect(db.tables.hr_ess_work_experience).toEqual([]);
  });

  it('accepts a full list of 20 entries with long descriptions', async () => {
    const { app, people } = buildApp();
    const entries = Array.from({ length: 20 }, (_, i) => entry({
      company: `Company ${i + 1}`,
      location: 'y'.repeat(200),
      description: 'x'.repeat(1000),
    }));
    const res = await put(app, people.faculty, { entries });
    expect(res.status).toBe(200);
    expect(res.body.entries).toHaveLength(20);
  });

  it('accepts a past role with no end date and defaults visibility on', async () => {
    const { app, people } = buildApp();
    const res = await put(app, people.faculty, {
      entries: [{ company: 'ACME Ltd', role_title: 'Designer', from_date: '2020-06-01' }],
    });
    expect(res.status).toBe(200);
    expect(res.body.entries[0].to_date).toBe(null);
    expect(res.body.entries[0].is_visible).toBe(true);
  });

  it.each([
    ['more than 20 entries', { entries: Array.from({ length: 21 }, () => entry()) }, MESSAGES.WORK_EXPERIENCE],
    ['a blank company', { entries: [entry({ company: '   ' })] }, MESSAGES.WORK_EXPERIENCE],
    ['a date that is not a day', { entries: [entry({ from_date: '2026-02-30', is_current: false })] }, MESSAGES.WORK_EXPERIENCE_DATE],
    ['an end before the start', { entries: [entry({ to_date: '2020-01-01' })] }, MESSAGES.WORK_EXPERIENCE_DATE],
    ['a current role with an end date', { entries: [entry({ to_date: '2026-10-01' })] }, MESSAGES.WORK_EXPERIENCE_CURRENT],
    ['a location over 200 characters', { entries: [entry({ location: 'x'.repeat(201) })] }, MESSAGES.WORK_EXPERIENCE_TEXT],
    ['a description over 1,000 characters', { entries: [entry({ description: 'x'.repeat(1001) })] }, MESSAGES.WORK_EXPERIENCE_TEXT],
  ])('refuses %s with 400', async (_label, body, message) => {
    const { app, people } = buildApp();
    expectInvalid(await put(app, people.faculty, body), message);
  });

  it('refuses a field it does not take', async () => {
    const { app, people } = buildApp();
    expectInvalid(await put(app, people.faculty, { entries: [{ ...entry(), salary: '100' }] }), MESSAGES.WORK_EXPERIENCE);
  });

  it('answers 401 with no token and 403 for the desk login', async () => {
    const { app, people } = buildApp();
    expectRefusal(await request(app).put(PATH).send({ entries: [] }), 401, 'NOT_AUTHENTICATED');
    expectRefusal(await request(app).put(PATH).set(bearer(tokens.portal(people.desk))).send({ entries: [] }), 403, 'NOT_LINKED');
  });

  it('answers 503 when the migration has not been applied', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    db.dropTable('hr_ess_work_experience');
    expectRefusal(await put(app, people.faculty, { entries: [entry()] }), 503, 'MODULE_NOT_INSTALLED');
  });
});
