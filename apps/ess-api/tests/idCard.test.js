const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { signVerifyToken } = require('../src/lib/idCardKit');
const { expectRefusal, quietErrors } = require('./helpers/expect');
const { NOW } = require('./helpers/constants');

/** Phase 2C: the staff ID card — the holder's card, and the no-sign-in verification link. */

const MY_CARD = '/api/ess/me/id-card';

describe('GET /api/ess/me/id-card', () => {
  it('hands my card from the HR record, with a verification link', async () => {
    const { app, people } = buildApp();
    const res = await request(app).get(MY_CARD).set(bearer(tokens.portal(people.faculty)));
    expect(res.status).toBe(200);
    expect(res.body.card).toEqual({
      full_name: 'Test CAD Faculty',
      employee_code: 'RVM-011',
      designation: 'CAD Faculty',
      department_name: 'Technical Training',
      branch_name: 'Faridabad',
      photo_url: `https://storage.test/documents/hr/photos/faculty.jpg?token=test-signed&expires=300`,
      verify_url: expect.stringMatching(/^\/api\/ess\/id-card\/verify\//),
    });
  });

  it('gives an employee without a photo a null link', async () => {
    const { app, people } = buildApp();
    const res = await request(app).get(MY_CARD).set(bearer(tokens.attendance(people.attendance)));
    expect(res.status).toBe(200);
    expect(res.body.card.photo_url).toBeNull();
    expect(res.body.card.employee_code).toBe('RVM-050');
  });
});

describe('GET /api/ess/id-card/verify/:token', () => {
  it('answers what the card shows, with no token at all', async () => {
    const { app, people } = buildApp();
    const card = await request(app).get(MY_CARD).set(bearer(tokens.portal(people.faculty)));
    const token = card.body.card.verify_url.replace('/api/ess/id-card/verify/', '');
    const res = await request(app).get(`/api/ess/id-card/verify/${token}`);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      valid: true,
      full_name: 'Test CAD Faculty',
      employee_code: 'RVM-011',
      designation: 'CAD Faculty',
      branch_name: 'Faridabad',
    });
    expect(JSON.stringify(res.body)).not.toContain('photo');
  });

  it('refuses a forged, mangled and expired token with one 401', async () => {
    const { app, config, people } = buildApp();
    const card = await request(app).get(MY_CARD).set(bearer(tokens.portal(people.faculty)));
    const token = card.body.card.verify_url.replace('/api/ess/id-card/verify/', '');
    // A byte changed: the signature no longer matches.
    const [payload, signature] = token.split('.');
    const forged = `${payload}.${signature.slice(0, -2)}aa`;
    expectRefusal(await request(app).get(`/api/ess/id-card/verify/${forged}`), 401, 'ID_CARD_BAD_TOKEN');
    expectRefusal(await request(app).get('/api/ess/id-card/verify/not-a-token'), 401, 'ID_CARD_BAD_TOKEN');
    // Expired: a link minted 91 days ago has passed its 90 days.
    const expired = signVerifyToken({
      jwtSecret: config.jwtSecret,
      employeeId: people.faculty.employee.id,
      now: new Date(NOW.getTime() - 91 * 86400000),
    });
    expectRefusal(await request(app).get(`/api/ess/id-card/verify/${expired}`), 401, 'ID_CARD_BAD_TOKEN');
    expect(MESSAGES.ID_CARD_BAD_TOKEN).toBeTruthy();
  });

  it('answers 401 for a card whose holder has left the record', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    const card = await request(app).get(MY_CARD).set(bearer(tokens.portal(people.faculty)));
    const token = card.body.card.verify_url.replace('/api/ess/id-card/verify/', '');
    const link = db.tables.hr_employees.find((e) => e.id === people.faculty.employee.id);
    link.is_archived = true;
    expectRefusal(await request(app).get(`/api/ess/id-card/verify/${token}`), 401, 'ID_CARD_BAD_TOKEN');
  });

  it('is limited per address, like the sign-in is', async () => {
    const { app } = buildApp({ limits: { idCardVerify: { windowMs: 60 * 1000, limit: 1 } } });
    const path = '/api/ess/id-card/verify/not-a-token';
    expectRefusal(await request(app).get(path), 401, 'ID_CARD_BAD_TOKEN');
    expectRefusal(await request(app).get(path), 429, 'RATE_LIMITED');
  });
});
