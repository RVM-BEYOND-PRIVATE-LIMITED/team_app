const request = require('supertest');
const { buildApp } = require('./helpers/app');
const { NOW } = require('./helpers/constants');
const pkg = require('../package.json');

/** GET /api/ess/health: no sign-in, always 200 while the process is up, db 'ok' or 'unavailable'. */

const health = (app, headers = {}) => request(app).get('/api/ess/health').set(headers);

describe('GET /api/ess/health', () => {
  it('answers the documented shape, with no sign-in', async () => {
    const { app } = buildApp();
    const res = await health(app);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      ok: true,
      server_time: NOW.toISOString(),
      version: pkg.version,
      min_app_version: null,
      latest_app_version: null,
      db: 'ok',
    });
  });

  it('reports the versions it was deployed with', async () => {
    const { app } = buildApp({ env: { APP_VERSION: '0.3.1', GIT_SHA: 'abc123', MIN_APP_VERSION: '1.0.0', LATEST_APP_VERSION: '1.2.0+14' } });
    const res = await health(app);
    expect(res.body).toMatchObject({ version: '0.3.1', min_app_version: '1.0.0', latest_app_version: '1.2.0+14' });
  });

  it('falls back to the commit the deploy wrote when there is no APP_VERSION', async () => {
    const { app } = buildApp({ env: { GIT_SHA: '916e2f5c0ffee' } });
    expect((await health(app)).body.version).toBe('916e2f5c0ffee');
  });

  it('ignores whatever Authorization header comes with it', async () => {
    const { app } = buildApp();
    expect((await health(app, { Authorization: 'Bearer nonsense' })).status).toBe(200);
  });

  it('reads one row of one small table, naming its column', async () => {
    const { app, db } = buildApp();
    await health(app);
    expect(db.queries).toEqual([expect.objectContaining({ table: 'hr_branches', columns: ['id'], limit: 1 })]);
  });

  describe('with the database in trouble', () => {
    beforeEach(() => {
      vi.spyOn(console, 'error').mockImplementation(() => {});
    });

    it.each([['error'], ['throw']])('still answers 200, with db unavailable, when the client returns %s', async (outage) => {
      const { app, db } = buildApp();
      db.outage = outage;
      const res = await health(app);
      expect(res.status).toBe(200);
      expect(res.body).toMatchObject({ ok: true, db: 'unavailable' });
    });

    it('gives up on a database that does not answer, and says so', async () => {
      const { app, db } = buildApp({ limits: { healthDbTimeoutMs: 50 } });
      db.outage = 'hang';
      const started = Date.now();
      const res = await health(app);
      expect(res.status).toBe(200);
      expect(res.body.db).toBe('unavailable');
      expect(Date.now() - started).toBeLessThan(2000);
      // The read was cancelled, not left running.
      expect(db.queries[0].aborted).toBe(true);
    });

    it('answers db unavailable when the table it reads is not there', async () => {
      const { app, db } = buildApp();
      db.dropTable('hr_branches');
      expect((await health(app)).body.db).toBe('unavailable');
    });
  });

  it('stays up while ESS_ENABLED=false switches everything else off', async () => {
    const { app } = buildApp({ env: { ESS_ENABLED: 'false' } });
    const res = await health(app);
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  it('is never cached', async () => {
    const { app } = buildApp();
    expect((await health(app)).headers['cache-control']).toBe('no-store');
  });
});
