const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { DEFAULT_LIMITS } = require('../src/middleware/rateLimit');

/**
 * The two limits: per address before sign-in, per employee after it. Small limits are passed in
 * so a test does not have to send hundreds of requests; the production numbers are checked
 * separately.
 *
 * Requests arrive through `trust proxy` 1 as nginx would hand them over, so X-Forwarded-For
 * names the caller's address.
 */

const from = (address) => ({ 'X-Forwarded-For': address });

const expectLimited = (res) => {
  expect(res.status).toBe(429);
  expect(res.body).toEqual({ error: expect.any(String), code: 'RATE_LIMITED' });
  expect(Number(res.headers['retry-after'])).toBeGreaterThan(0);
};

describe('the per-address limit, before sign-in', () => {
  const limits = { perIp: { windowMs: 60 * 1000, limit: 3 } };

  it('answers 429 RATE_LIMITED past the limit, and only to that address', async () => {
    const { app } = buildApp({ limits });
    for (let i = 0; i < 3; i++) expect((await request(app).get('/api/ess/health').set(from('203.0.113.7'))).status).toBe(200);
    expectLimited(await request(app).get('/api/ess/health').set(from('203.0.113.7')));
    expect((await request(app).get('/api/ess/health').set(from('203.0.113.8'))).status).toBe(200);
  });

  it('counts requests with no token or a bad one, which never reach sign-in', async () => {
    const { app } = buildApp({ limits });
    for (let i = 0; i < 3; i++) expect((await request(app).get('/api/ess/me').set(from('198.51.100.4'))).status).toBe(401);
    expectLimited(await request(app).get('/api/ess/me').set(from('198.51.100.4')).set(bearer('guess')));
  });

  it('counts unknown addresses too', async () => {
    const { app } = buildApp({ limits });
    for (let i = 0; i < 3; i++) await request(app).get('/api/ess/nothing').set(from('198.51.100.5'));
    expectLimited(await request(app).get('/api/ess/nothing').set(from('198.51.100.5')));
  });

  it('puts the addresses of one IPv6 /56 in one bucket', async () => {
    const { app } = buildApp({ limits });
    await request(app).get('/api/ess/health').set(from('2001:db8:abcd:1201::1'));
    await request(app).get('/api/ess/health').set(from('2001:db8:abcd:12fe::9'));
    await request(app).get('/api/ess/health').set(from('2001:db8:abcd:1255:aaaa::3'));
    expectLimited(await request(app).get('/api/ess/health').set(from('2001:db8:abcd:1200::7')));
    // The next /56 is somebody else.
    expect((await request(app).get('/api/ess/health').set(from('2001:db8:abcd:1300::1'))).status).toBe(200);
  });
});

describe('the per-employee limit, after sign-in', () => {
  const limits = { perIp: { windowMs: 60 * 1000, limit: 1000 }, perEmployee: { windowMs: 60 * 1000, limit: 2 } };

  it('answers 429 RATE_LIMITED to that person only, on the same office address', async () => {
    const { app, people } = buildApp({ limits });
    const office = from('203.0.113.50');
    const faculty = bearer(tokens.portal(people.faculty));
    expect((await request(app).get('/api/ess/me').set(office).set(faculty)).status).toBe(200);
    expect((await request(app).get('/api/ess/me/capabilities').set(office).set(faculty)).status).toBe(200);
    expectLimited(await request(app).get('/api/ess/me').set(office).set(faculty));
    expect((await request(app).get('/api/ess/me').set(office).set(bearer(tokens.portal(people.hr)))).status).toBe(200);
  });

  it('is one count per person, whichever sign-in they use', async () => {
    const { app, people } = buildApp({
      limits,
      setup: (w) => w.tables.hr_attendance_accounts.push({
        ...w.people.attendance.account, id: '90000000-0000-4000-8000-000000000097', employee_id: w.people.faculty.employee.id,
      }),
    });
    expect((await request(app).get('/api/ess/me').set(bearer(tokens.portal(people.faculty)))).status).toBe(200);
    expect((await request(app).get('/api/ess/me').set(bearer(tokens.attendance(people.faculty)))).status).toBe(200);
    expectLimited(await request(app).get('/api/ess/me').set(bearer(tokens.portal(people.faculty))));
  });

  it('does not count refused sign-ins against anybody', async () => {
    const { app, people } = buildApp({ limits: { ...limits, perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
    for (let i = 0; i < 3; i++) expect((await request(app).get('/api/ess/me').set(bearer('guess'))).status).toBe(401);
    expect((await request(app).get('/api/ess/me').set(bearer(tokens.portal(people.hr)))).status).toBe(200);
  });
});

describe('the production limits', () => {
  it('leave a whole branch room behind one office address, and one person a fifth of it', () => {
    expect(DEFAULT_LIMITS.perIp).toEqual({ windowMs: 60 * 1000, limit: 600 });
    expect(DEFAULT_LIMITS.perEmployee).toEqual({ windowMs: 60 * 1000, limit: 120 });
  });

  it('apply when no limits are passed in', async () => {
    const { app } = buildApp();
    const res = await request(app).get('/api/ess/health');
    expect(res.headers['ratelimit-limit']).toBe('600');
  });
});
