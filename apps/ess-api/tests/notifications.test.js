const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');

/** Tasks D6 and D8: the notifications Inbox, its read state, and the categories turned off. */

const INBOX = '/api/ess/notifications';
const SETTINGS = '/api/ess/notifications/settings';
const NID = (n) => `81000000-0000-4000-8000-${String(n).padStart(12, '0')}`;

const notificationRow = (employeeId, n, change = {}) => ({
  id: NID(n),
  employee_id: employeeId,
  category: 'decisions',
  title: 'Request approved',
  body: 'Your request for on duty on 15 Oct was approved.',
  data: { request_id: '7a000000-0000-4000-8000-000000000001', request_family: 'attendance' },
  read_at: null,
  pushed_at: null,
  push_mode: null,
  push_attempts: 0,
  push_error: null,
  created_at: `2026-10-1${n}T05:00:00+00:00`,
  ...change,
});

const list = (app, token) => request(app).get(INBOX).set(bearer(token));
const readOne = (app, token, id) => request(app).post(`${INBOX}/${id}/read`).set(bearer(token));
const readAll = (app, token) => request(app).post(`${INBOX}/read-all`).set(bearer(token));

describe('GET /api/ess/notifications', () => {
  it('lists the caller\'s own, newest first, with the unread count and no push bookkeeping', async () => {
    const { app, db, people } = buildApp();
    db.tables.hr_ess_notifications = [
      notificationRow(people.attendance.employee.id, 1, { read_at: '2026-10-15T05:00:00+00:00', pushed_at: '2026-10-15T05:00:01+00:00', push_mode: 'log' }),
      notificationRow(people.attendance.employee.id, 2, { category: 'approvals', title: 'New leave request', body: 'Test CAD Faculty asked for casual leave on 20 Oct.' }),
      notificationRow(people.faculty.employee.id, 3),
    ];
    const res = await list(app, tokens.attendance(people.attendance));
    expect(res.status).toBe(200);
    expect(res.body.unread).toBe(1);
    expect(res.body.truncated).toBe(false);
    expect(res.body.notifications.map((n) => n.id)).toEqual([NID(2), NID(1)]);
    expect(res.body.notifications[0]).toEqual({
      id: NID(2),
      category: 'approvals',
      title: 'New leave request',
      body: 'Test CAD Faculty asked for casual leave on 20 Oct.',
      data: { request_id: '7a000000-0000-4000-8000-000000000001', request_family: 'attendance' },
      read_at: null,
      created_at: '2026-10-12T05:00:00+00:00',
    });
    expect(JSON.stringify(res.body)).not.toMatch(/push_mode|pushed_at|push_attempts/);
  });

  it('is an empty Inbox for somebody with none, and 503 before the migration', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    expect((await list(app, tokens.portal(people.faculty))).body).toEqual({ notifications: [], unread: 0, truncated: false });
    db.dropTable('hr_ess_notifications');
    expectRefusal(await list(app, tokens.portal(people.faculty)), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('the read state', () => {
  it('marks one read, idempotently, and only the caller\'s own', async () => {
    const { app, db, people } = buildApp();
    db.tables.hr_ess_notifications = [
      notificationRow(people.attendance.employee.id, 1),
      notificationRow(people.faculty.employee.id, 2),
    ];
    const token = tokens.attendance(people.attendance);
    expect((await readOne(app, token, NID(1))).status).toBe(204);
    expect(db.tables.hr_ess_notifications[0].read_at).toEqual(expect.any(String));
    // Reading again is the same as once.
    expect((await readOne(app, token, NID(1))).status).toBe(204);
    expectRefusal(await readOne(app, token, NID(2)), 404, 'NOT_FOUND');
    expect(db.tables.hr_ess_notifications[1].read_at).toBe(null);
    expectInvalid(await readOne(app, token, 'nope'), MESSAGES.INVALID_ID);
  });

  it('marks every unread one, and says how many', async () => {
    const { app, db, people } = buildApp();
    db.tables.hr_ess_notifications = [
      notificationRow(people.attendance.employee.id, 1, { read_at: '2026-10-15T05:00:00+00:00' }),
      notificationRow(people.attendance.employee.id, 2),
      notificationRow(people.attendance.employee.id, 3),
    ];
    const res = await readAll(app, tokens.attendance(people.attendance));
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ marked: 2 });
    expect((await readAll(app, tokens.attendance(people.attendance))).body).toEqual({ marked: 0 });
    expect((await list(app, tokens.attendance(people.attendance))).body.unread).toBe(0);
  });
});

describe('GET and PUT /api/ess/notifications/settings', () => {
  it('shows every category on by default, with the quiet hours', async () => {
    const { app, people } = buildApp();
    const res = await request(app).get(SETTINGS).set(bearer(tokens.attendance(people.attendance)));
    expect(res.status).toBe(200);
    expect(res.body).toEqual({
      // Phase 2A added the Wall's six (tasks F1-F8); Phase 2B added the Helpdesk's (G2). The
      // order is policy/notifications.js's.
      categories: [
        { category: 'approvals', enabled: true },
        { category: 'decisions', enabled: true },
        { category: 'priority_tasks', enabled: true },
        { category: 'mentions', enabled: true },
        { category: 'replies', enabled: true },
        { category: 'praise', enabled: true },
        { category: 'announcements', enabled: true },
        { category: 'acknowledgements', enabled: true },
        { category: 'polls', enabled: true },
        { category: 'helpdesk', enabled: true },
      ],
      quiet_hours: { from: '21:00', to: '08:00' },
    });
  });

  it('stores what the person turns off, and reads it back', async () => {
    const { app, db, people } = buildApp();
    const token = tokens.attendance(people.attendance);
    const res = await request(app).put(SETTINGS).set(bearer(token)).send({ disabled_categories: ['approvals', 'approvals'] });
    expect(res.status).toBe(200);
    expect(res.body.categories).toEqual([
      { category: 'approvals', enabled: false },
      { category: 'decisions', enabled: true },
      { category: 'priority_tasks', enabled: true },
      { category: 'mentions', enabled: true },
      { category: 'replies', enabled: true },
      { category: 'praise', enabled: true },
      { category: 'announcements', enabled: true },
      { category: 'acknowledgements', enabled: true },
      { category: 'polls', enabled: true },
      { category: 'helpdesk', enabled: true },
    ]);
    expect(db.tables.hr_ess_notification_settings).toEqual([
      expect.objectContaining({ employee_id: people.attendance.employee.id, disabled_categories: ['approvals'] }),
    ]);
    expect((await request(app).get(SETTINGS).set(bearer(token))).body.categories[0].enabled).toBe(false);
  });

  it('refuses a category it does not know, a value that is not a list, and an unknown field', async () => {
    const { app, people } = buildApp();
    const token = tokens.attendance(people.attendance);
    const put = (body) => request(app).put(SETTINGS).set(bearer(token)).send(body);
    expectInvalid(await put({ disabled_categories: ['wall'] }), MESSAGES.NOTIFICATION_SETTINGS);
    expectInvalid(await put({ disabled_categories: ['mentions', 'push'] }), MESSAGES.NOTIFICATION_SETTINGS);
    expectInvalid(await put({ disabled_categories: 'approvals' }), MESSAGES.NOTIFICATION_SETTINGS);
    expectInvalid(await put({ categories: [] }), MESSAGES.UNKNOWN_FIELD);
  });
});

describe('the events that write notifications', () => {
  it('a filed request notifies the manager; the decision notifies the employee', async () => {
    const { app, db, people } = buildApp();
    const filed = await request(app).post('/api/ess/attendance-requests').set(bearer(tokens.portal(people.faculty)))
      .send({ type: 'on_duty', day: '2026-10-15', reason: 'Client visit at the Pune centre.', place: 'Pune centre' });
    expect(filed.status).toBe(201);
    const rows = db.tables.hr_ess_notifications;
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ employee_id: people.hod.employee.id, category: 'approvals', title: 'New attendance request' });
    expect(rows[0].body).toBe('Test CAD Faculty asked for on duty on 15 Oct.');
    expect(rows[0].data).toEqual({ request_id: filed.body.request.id, request_family: 'attendance' });

    const decided = await request(app).post(`/api/ess/approvals/attendance/${filed.body.request.id}/decide`)
      .set(bearer(tokens.portal(people.hod))).send({ decision: 'approve' });
    expect(decided.status).toBe(200);
    expect(db.tables.hr_ess_notifications).toHaveLength(2);
    expect(db.tables.hr_ess_notifications[1]).toMatchObject({
      employee_id: people.faculty.employee.id, category: 'decisions', title: 'Request approved',
    });
    expect(db.tables.hr_ess_notifications[1].body).toBe('Your request for on duty on 15 Oct was approved by Test CAD HOD.');
  });

  it('a request with no manager reaches HR, as the fallback approver', async () => {
    const { app, db, people } = buildApp({ setup: (w) => { w.people.faculty.employee.manager_id = null; } });
    const filed = await request(app).post('/api/ess/leave-requests').set(bearer(tokens.portal(people.faculty)))
      .send({ type: 'cl', day: '2026-10-20', reason: 'Family function at home.' });
    expect(filed.status).toBe(201);
    const rows = db.tables.hr_ess_notifications;
    expect(rows).toHaveLength(1);
    expect(rows[0]).toMatchObject({ employee_id: people.hr.employee.id, category: 'approvals', title: 'New leave request' });
    expect(rows[0].body).toBe('Test CAD Faculty asked for casual leave on 20 Oct.');
  });

  it('filing still succeeds when the notification cannot be written', async () => {
    quietErrors();
    const { app, db, people } = buildApp();
    db.dropTable('hr_ess_notifications');
    const filed = await request(app).post('/api/ess/attendance-requests').set(bearer(tokens.attendance(people.attendance)))
      .send({ type: 'on_duty', day: '2026-10-15', reason: 'Client visit at the Pune centre.', place: 'Pune centre' });
    expect(filed.status).toBe(201);
  });
});
