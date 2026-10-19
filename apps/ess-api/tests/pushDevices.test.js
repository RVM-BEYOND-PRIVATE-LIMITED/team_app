const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');

/** Task D5: the phone registers its push token, and revokes it on sign-out. */

const DEVICES = '/api/ess/push-devices';
const TOKEN = `test-token-${'a'.repeat(40)}`;

const register = (app, token, body) => request(app).post(DEVICES).set(bearer(token)).send(body);
const revoke = (app, token, id) => request(app).delete(`${DEVICES}/${id}`).set(bearer(token));

describe('POST /api/ess/push-devices', () => {
  it('registers a token for either sign-in, and never sends it back', async () => {
    const { app, db, people } = buildApp();
    const res = await register(app, tokens.attendance(people.attendance), { token: TOKEN, device_label: 'Pixel 8' });
    expect(res.status).toBe(201);
    expect(res.body).toEqual({
      device: {
        id: expect.any(String),
        platform: 'android',
        device_label: 'Pixel 8',
        install_id: null,
        created_at: expect.any(String),
        updated_at: expect.any(String),
        last_seen_at: expect.any(String),
      },
    });
    expect(JSON.stringify(res.body)).not.toContain(TOKEN.slice(0, 20));
    const stored = db.tables.hr_ess_push_devices;
    expect(stored).toHaveLength(1);
    expect(stored[0]).toMatchObject({ employee_id: people.attendance.employee.id, token: TOKEN, revoked_at: null });
  });

  it('moves a token that another person held, and lifts its revocation: one install, one row', async () => {
    const { app, db, people } = buildApp();
    db.tables.hr_ess_push_devices = [{
      id: '80000000-0000-4000-8000-000000000001', employee_id: people.faculty.employee.id, token: TOKEN,
      platform: 'android', device_label: null, install_id: null, created_at: '2026-10-10T05:00:00+00:00',
      updated_at: '2026-10-10T05:00:00+00:00', last_seen_at: '2026-10-10T05:00:00+00:00', revoked_at: '2026-10-11T05:00:00+00:00',
    }];
    const res = await register(app, tokens.attendance(people.attendance), { token: TOKEN });
    expect(res.status).toBe(201);
    expect(db.tables.hr_ess_push_devices).toHaveLength(1);
    expect(db.tables.hr_ess_push_devices[0]).toMatchObject({
      id: '80000000-0000-4000-8000-000000000001',
      employee_id: people.attendance.employee.id,
      revoked_at: null,
    });
  });

  it.each([
    ['no token', { }, MESSAGES.PUSH_TOKEN],
    ['a token that is too short', { token: 'short' }, MESSAGES.PUSH_TOKEN],
    ['a token with a control character', { token: `test-token-${'a'.repeat(30)}\u0007` }, MESSAGES.PUSH_TOKEN],
    ['a phone name over 80 characters', { token: TOKEN, device_label: 'x'.repeat(81) }, MESSAGES.PUSH_DEVICE_LABEL],
    ['an install id over 128 characters', { token: TOKEN, install_id: 'x'.repeat(129) }, MESSAGES.BAD_INSTALL_ID],
    ['an unknown field', { token: TOKEN, platform: 'ios' }, MESSAGES.UNKNOWN_FIELD],
  ])('refuses %s with 400', async (_label, body, message) => {
    const { app, people } = buildApp();
    expectInvalid(await register(app, tokens.attendance(people.attendance), body), message);
  });

  it('answers 401 with no token and 503 before the migration', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    expectRefusal(await request(app).post(DEVICES).send({ token: TOKEN }), 401, 'NOT_AUTHENTICATED');
    db.dropTable('hr_ess_push_devices');
    expectRefusal(await register(app, tokens.attendance(people.attendance), { token: TOKEN }), 503, 'MODULE_NOT_INSTALLED');
  });

  it('refuses a session still on HR\'s first-time password, as every ESS endpoint does', async () => {
    const { app, people } = buildApp({ setup: (w) => { w.people.attendance.account.password_set_at = null; } });
    expectRefusal(await register(app, tokens.attendance(people.attendance, 'pw'), { token: TOKEN }), 403, 'PASSWORD_CHANGE_REQUIRED');
  });
});

describe('DELETE /api/ess/push-devices/{id}', () => {
  it('revokes the caller\'s own phone, once', async () => {
    const { app, db, people } = buildApp();
    await register(app, tokens.attendance(people.attendance), { token: TOKEN });
    const id = db.tables.hr_ess_push_devices[0].id;
    expect((await revoke(app, tokens.attendance(people.attendance), id)).status).toBe(204);
    expect(db.tables.hr_ess_push_devices[0].revoked_at).toEqual(expect.any(String));
    expectRefusal(await revoke(app, tokens.attendance(people.attendance), id), 404, 'NOT_FOUND');
  });

  it('answers 404 for somebody else\'s phone and 400 for an id that is not one', async () => {
    const { app, db, people } = buildApp();
    await register(app, tokens.attendance(people.attendance), { token: TOKEN });
    const id = db.tables.hr_ess_push_devices[0].id;
    expectRefusal(await revoke(app, tokens.portal(people.faculty), id), 404, 'NOT_FOUND');
    expect(db.tables.hr_ess_push_devices[0].revoked_at).toBe(null);
    expectInvalid(await revoke(app, tokens.attendance(people.attendance), 'nope'), MESSAGES.INVALID_ID);
  });
});
