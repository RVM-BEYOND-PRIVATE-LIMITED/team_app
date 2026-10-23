const request = require('supertest');
const bcrypt = require('bcryptjs');
const { buildApp, tokens, bearer } = require('./helpers/app');

/**
 * Issue #10: an attendance-only sign-in can open Account & Security and change its own
 * password. Email and phone stay HR-managed for that sign-in (they are the login identifiers),
 * while a portal login keeps using the Scheduler's own two-step change.
 */

const PORTAL_PASSWORD = 'PortalPass123';
const ATTENDANCE_PASSWORD = 'OldPass123';

const withRealHashes = (world) => {
  world.people.admin.user.password_hash = bcrypt.hashSync(PORTAL_PASSWORD, 4);
  world.people.attendance.account.password_hash = bcrypt.hashSync(ATTENDANCE_PASSWORD, 4);
};

describe('GET /api/ess/me/account', () => {
  it('answers an attendance-only sign-in from the HR record, with no portal fields', async () => {
    const { app, people } = buildApp({ setup: withRealHashes });
    const res = await request(app).get('/api/ess/me/account').set(bearer(tokens.attendance(people.attendance)));
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      login_kind: 'attendance',
      username: people.attendance.employee.employee_code,
      phone_number: people.attendance.employee.phone,
      can_change_email: false,
      can_change_phone: false,
      can_change_password: true,
      can_use_two_factor: false,
    });
    expect(res.body.email).toBeNull();
    expect(res.body.note).toMatch(/Ask HR/);
  });

  it('answers a portal sign-in from the users row', async () => {
    const { app, people } = buildApp({ setup: withRealHashes });
    const res = await request(app).get('/api/ess/me/account').set(bearer(tokens.portal(people.admin)));
    expect(res.status).toBe(200);
    expect(res.body).toMatchObject({
      login_kind: 'portal',
      email: people.admin.user.email,
      can_change_email: true,
      can_change_phone: true,
      can_use_two_factor: true,
    });
  });

  it('needs a token', async () => {
    const { app } = buildApp({ setup: withRealHashes });
    const res = await request(app).get('/api/ess/me/account');
    expect(res.status).toBe(401);
  });
});

describe('POST /api/ess/me/password', () => {
  it('changes an attendance password, bumps the cut-off and ends the old session', async () => {
    const { app, people, db } = buildApp({ setup: withRealHashes });
    const oldToken = tokens.attendance(people.attendance);

    const wrong = await request(app).post('/api/ess/me/password').set(bearer(oldToken))
      .send({ current_password: 'not-it', new_password: 'NewPass456', confirm_password: 'NewPass456' });
    expect(wrong.status).toBe(401);
    expect(wrong.body.code).toBe('WRONG_PASSWORD');

    const changed = await request(app).post('/api/ess/me/password').set(bearer(oldToken))
      .send({ current_password: ATTENDANCE_PASSWORD, new_password: 'NewPass456', confirm_password: 'NewPass456' });
    expect(changed.status).toBe(200);
    expect(changed.body.signed_out).toBe(true);

    const row = db.tables.hr_attendance_accounts.find((r) => r.employee_id === people.attendance.employee.id);
    expect(await bcrypt.compare('NewPass456', row.password_hash)).toBe(true);
    expect(await bcrypt.compare(ATTENDANCE_PASSWORD, row.password_hash)).toBe(false);

    // The Scheduler's own cut-off: a session issued before the change is refused.
    const old = await request(app).get('/api/ess/me').set(bearer(oldToken));
    expect(old.status).toBe(401);
  });

  it('lets a first-time attendance login set a password without a current one', async () => {
    const { app, people, db } = buildApp({
      setup: (world) => {
        withRealHashes(world);
        world.people.attendance.account.password_hash = null;
      },
    });
    const res = await request(app).post('/api/ess/me/password').set(bearer(tokens.attendance(people.attendance)))
      .send({ new_password: 'FirstPass123', confirm_password: 'FirstPass123' });
    expect(res.status).toBe(200);
    const row = db.tables.hr_attendance_accounts.find((r) => r.employee_id === people.attendance.employee.id);
    expect(await bcrypt.compare('FirstPass123', row.password_hash)).toBe(true);
  });

  it('sends a portal login to the Scheduler, which owns all four credential changes', async () => {
    const { app, people } = buildApp({ setup: withRealHashes });
    const res = await request(app).post('/api/ess/me/password').set(bearer(tokens.portal(people.admin)))
      .send({ current_password: PORTAL_PASSWORD, new_password: 'NewPortal456', confirm_password: 'NewPortal456' });
    expect(res.status).toBe(409);
    expect(res.body.code).toBe('USE_SCHEDULER');
  });

  it('refuses a short password, a mismatch, and a missing current one', async () => {
    const { app, people } = buildApp({ setup: withRealHashes });
    const token = bearer(tokens.attendance(people.attendance));

    expect((await request(app).post('/api/ess/me/password').set(token)
      .send({ current_password: ATTENDANCE_PASSWORD, new_password: 'short', confirm_password: 'short' })).status).toBe(400);
    expect((await request(app).post('/api/ess/me/password').set(token)
      .send({ current_password: ATTENDANCE_PASSWORD, new_password: 'NewPass456', confirm_password: 'NewPass457' })).status).toBe(400);
    expect((await request(app).post('/api/ess/me/password').set(token)
      .send({ new_password: 'NewPass456', confirm_password: 'NewPass456' })).status).toBe(400);
  });

  it('refuses a field it does not take', async () => {
    const { app, people } = buildApp({ setup: withRealHashes });
    const res = await request(app).post('/api/ess/me/password').set(bearer(tokens.attendance(people.attendance)))
      .send({ current_password: ATTENDANCE_PASSWORD, new_password: 'NewPass456', confirm_password: 'NewPass456', admin: true });
    expect(res.status).toBe(400);
  });
});
