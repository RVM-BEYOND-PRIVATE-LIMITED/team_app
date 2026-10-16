const request = require('supertest');
const { createApp } = require('../src/app');
const { loadConfig } = require('../src/config');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { NOW, TEST_ENV } = require('./helpers/constants');

/** What every reply has in common: JSON in the house shape, also for the paths no route handles. */

const expectRefusal = (res, status, code) => {
  expect(res.status).toBe(status);
  expect(res.headers['content-type']).toMatch(/^application\/json/);
  expect(res.body).toEqual({ error: expect.any(String), code });
};

describe('an unknown address', () => {
  it('is a JSON 404 NOT_FOUND under /api/ess, with or without a token', async () => {
    const { app, people } = buildApp();
    expectRefusal(await request(app).get('/api/ess/nothing-here'), 404, 'NOT_FOUND');
    expectRefusal(await request(app).get('/api/ess/nothing-here').set(bearer(tokens.portal(people.hr))), 404, 'NOT_FOUND');
    expectRefusal(await request(app).get('/api/ess/me/nothing-here'), 404, 'NOT_FOUND');
  });

  it('is a JSON 404 outside /api/ess too', async () => {
    const { app } = buildApp();
    expectRefusal(await request(app).get('/'), 404, 'NOT_FOUND');
    expectRefusal(await request(app).get('/api/users'), 404, 'NOT_FOUND');
  });

  it('is a 404 for a method the route does not take', async () => {
    const { app, people } = buildApp();
    expectRefusal(await request(app).delete('/api/ess/me').set(bearer(tokens.portal(people.hr))), 404, 'NOT_FOUND');
  });

  it('is a JSON 404 for OPTIONS too, where Express would answer with an HTML "GET,HEAD"', async () => {
    const { app } = buildApp();
    for (const address of ['/api/ess/me', '/api/ess/health', '/api/ess/me/capabilities', '/api/ess/nothing-here']) {
      const res = await request(app).options(address);
      expectRefusal(res, 404, 'NOT_FOUND');
      expect(res.headers.allow).toBeUndefined();
    }
  });
});

describe('a request body', () => {
  it('that is not valid JSON is a 400 INVALID_JSON, not an HTML page', async () => {
    const { app } = buildApp();
    const res = await request(app).post('/api/ess/me').set('Content-Type', 'application/json').send('{"name": ');
    expectRefusal(res, 400, 'INVALID_JSON');
  });

  it('over the size limit is a 413 PAYLOAD_TOO_LARGE', async () => {
    const { app } = buildApp();
    const res = await request(app).post('/api/ess/me').set('Content-Type', 'application/json')
      .send(JSON.stringify({ note: 'x'.repeat(20 * 1024) }));
    expectRefusal(res, 413, 'PAYLOAD_TOO_LARGE');
  });

  it('in an encoding the server does not read is a 415', async () => {
    const { app } = buildApp();
    const res = await request(app).post('/api/ess/me').set('Content-Type', 'application/json')
      .set('Content-Encoding', 'compress-of-some-kind').send('{}');
    expectRefusal(res, 415, 'UNSUPPORTED_MEDIA_TYPE');
  });
});

describe('ESS_ENABLED=false', () => {
  it.each([['FALSE'], ['false'], [' false ']])('(%s) switches every endpoint but health off with 503 MODULE_DISABLED', async (value) => {
    const { app, people } = buildApp({ env: { ESS_ENABLED: value } });
    const token = tokens.portal(people.hr);
    expectRefusal(await request(app).get('/api/ess/me').set(bearer(token)), 503, 'MODULE_DISABLED');
    expectRefusal(await request(app).get('/api/ess/me/capabilities').set(bearer(token)), 503, 'MODULE_DISABLED');
    expectRefusal(await request(app).get('/api/ess/anything'), 503, 'MODULE_DISABLED');
    expect((await request(app).get('/api/ess/health')).status).toBe(200);
  });

  it('is checked before the token, so the app hears "switched off", not "signed out"', async () => {
    const { app } = buildApp({ env: { ESS_ENABLED: 'false' } });
    expectRefusal(await request(app).get('/api/ess/me'), 503, 'MODULE_DISABLED');
  });

  it.each([['true'], [''], ['yes']])('anything else (%j) leaves the ESS on, as the Scheduler\'s switch does', async (value) => {
    const { app, people } = buildApp({ env: { ESS_ENABLED: value } });
    expect((await request(app).get('/api/ess/me').set(bearer(tokens.portal(people.hr)))).status).toBe(200);
  });
});

describe('an unexpected failure', () => {
  it('is a 500 INTERNAL_ERROR with no stack trace and no detail of the cause', async () => {
    const spy = vi.spyOn(console, 'error').mockImplementation(() => {});
    const { store, people } = buildApp();
    const broken = { ...store, getBranch: async () => { throw new TypeError('Cannot read properties of undefined (reading "secret_column")'); } };
    const app = createApp({ config: loadConfig(TEST_ENV), store: broken, now: () => new Date(NOW.getTime()) });
    const res = await request(app).get('/api/ess/me').set(bearer(tokens.portal(people.hr)));
    expectRefusal(res, 500, 'INTERNAL_ERROR');
    expect(JSON.stringify(res.body)).not.toMatch(/secret_column|TypeError|at .*\.js/);
    // The detail goes to the server log instead.
    expect(spy).toHaveBeenCalled();
  });
});

describe('every reply', () => {
  it('is not cached, is not sniffed, and does not advertise Express', async () => {
    const { app, people } = buildApp();
    for (const res of [
      await request(app).get('/api/ess/me').set(bearer(tokens.portal(people.hr))),
      await request(app).get('/api/ess/me'),
      await request(app).get('/api/ess/nothing-here'),
      await request(app).get('/api/ess/health'),
    ]) {
      expect(res.headers['cache-control']).toBe('no-store');
      expect(res.headers['x-content-type-options']).toBe('nosniff');
      expect(res.headers['x-powered-by']).toBeUndefined();
      expect(res.headers.etag).toBeUndefined();
    }
  });

  it('never carries CORS headers: the app is native, and no browser should read these replies', async () => {
    const { app } = buildApp();
    const res = await request(app).get('/api/ess/health').set('Origin', 'https://example.test');
    expect(res.headers['access-control-allow-origin']).toBeUndefined();
  });
});

describe('createApp', () => {
  it('refuses to build without its config or its store', () => {
    const config = loadConfig(TEST_ENV);
    expect(() => createApp({ store: {} })).toThrow(/config/);
    expect(() => createApp({ config })).toThrow(/store/);
  });
});
