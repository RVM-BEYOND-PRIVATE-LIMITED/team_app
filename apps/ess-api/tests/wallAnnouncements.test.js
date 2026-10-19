const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');
const { NOW } = require('./helpers/constants');
const W = require('./helpers/wallFixtures');

/** Task F5: announcements — audience, scheduling, acknowledgement, counts, pins, and the log-only mail. */

const WALL = '/api/ess/wall/announcements';
const HR_LIST = '/api/ess/wall/hr/announcements';

const create = (app, token, body) => request(app).post(WALL).set(bearer(token)).send(body);
const inbox = (app, token) => request(app).get(WALL).set(bearer(token));
const one = (app, token, id) => request(app).get(`${WALL}/${id}`).set(bearer(token));
const edit = (app, token, id, body) => request(app).patch(`${WALL}/${id}`).set(bearer(token)).send(body);
const remove = (app, token, id) => request(app).delete(`${WALL}/${id}`).set(bearer(token));
const read = (app, token, id) => request(app).post(`${WALL}/${id}/read`).set(bearer(token));
const ack = (app, token, id) => request(app).post(`${WALL}/${id}/ack`).set(bearer(token));
const counts = (app, token, id) => request(app).get(`${WALL}/${id}/counts`).set(bearer(token));
const mine = (app, token, query = '') => request(app).get(`${HR_LIST}${query}`).set(bearer(token));

const BODY = {
  title: 'Diwali holiday',
  body: 'The office is closed on 8 November. Attendance is not expected that day.',
};

describe('POST /api/ess/wall/announcements', () => {
  it('posts one now to everybody, resolves the audience and counts it', async () => {
    const { app, people, db } = buildApp();
    const res = await create(app, tokens.portal(people.hr), BODY);
    expect(res.status).toBe(201);
    expect(res.body.announcement).toMatchObject({
      title: 'Diwali holiday',
      audience_label: 'Everybody',
      mine: true,
      needs_ack: false,
      pinned: false,
    });
    expect(res.body.announcement.audience).toBeUndefined();
    expect(res.body.scheduled).toBe(false);
    expect(res.body.counts).toEqual({ sent: 13, read: 0, acknowledged: 0, not_acknowledged: 13 });
    expect(db.tables.hr_ess_announcement_audience).toHaveLength(13);
  });

  it('resolves an audience by branch, department, role and named people', async () => {
    const { app, people } = buildApp();
    const byBranch = await create(app, tokens.portal(people.hr), { ...BODY, audience: { branch_ids: [people.pune.employee.branch_id] } });
    expect(byBranch.body.counts.sent).toBe(1);
    expect(byBranch.body.announcement.audience_label).toBe('Branches: Pune');
    const byRole = await create(app, tokens.portal(people.hr), { ...BODY, audience: { roles: ['faculty', 'hod'] } });
    expect(byRole.body.counts.sent).toBe(2);
    const byPerson = await create(app, tokens.portal(people.hr), { ...BODY, audience: { employee_ids: [people.faculty.employee.id] } });
    expect(byPerson.body.counts.sent).toBe(1);
    expect(byPerson.body.announcement.audience_label).toBe('People: Test CAD Faculty');
    const byDepartment = await create(app, tokens.portal(people.hr), { ...BODY, audience: { department_ids: [people.hr.employee.department_id] } });
    expect(byDepartment.body.counts.sent).toBe(2);
  });

  it('stores a scheduled one as a draft and publishes only when the job runs', async () => {
    const { app, people, db } = buildApp();
    const res = await create(app, tokens.portal(people.hr), { ...BODY, publish_at: '2026-10-20T04:00:00.000Z' });
    expect(res.status).toBe(201);
    expect(res.body.scheduled).toBe(true);
    expect(res.body.counts.sent).toBe(0);
    expect(db.tables.hr_ess_announcements[0].published_at).toBe(null);
    // Nobody's inbox shows it, and its sender sees it as a draft.
    const reader = await inbox(app, tokens.portal(people.faculty));
    expect(reader.body.announcements).toEqual([]);
    const sender = await mine(app, tokens.portal(people.hr), '?status=draft');
    expect(sender.body.announcements.map((a) => a.title)).toEqual(['Diwali holiday']);
  });

  it('refuses a publish time in the past, a missing acknowledgement close, and a close with no ask', async () => {
    const { app, people } = buildApp();
    const token = tokens.portal(people.hr);
    expectInvalid(await create(app, token, { ...BODY, publish_at: '2026-10-15T04:00:00.000Z' }), MESSAGES.WALL_ANNOUNCEMENT_PUBLISH_PAST);
    expectInvalid(await create(app, token, { ...BODY, publish_at: 'tomorrow' }), MESSAGES.WALL_ANNOUNCEMENT_PUBLISH);
    expectInvalid(await create(app, token, { ...BODY, needs_ack: true }), MESSAGES.WALL_ANNOUNCEMENT_CLOSES);
    expectInvalid(await create(app, token, { ...BODY, closes_on: '2026-11-05' }), MESSAGES.WALL_ANNOUNCEMENT_CLOSES);
    expectInvalid(await create(app, token, { ...BODY, needs_ack: true, closes_on: '2026-10-01' }), MESSAGES.WALL_ANNOUNCEMENT_CLOSES_PAST);
    expectInvalid(await create(app, token, { ...BODY, audience: { teams: ['cad'] } }), MESSAGES.WALL_ANNOUNCEMENT_AUDIENCE);
    expectInvalid(await create(app, token, { ...BODY, title: 'Hi' }), MESSAGES.WALL_ANNOUNCEMENT_TITLE);
  });

  it('refuses anybody but HR, the CEO and super admins', async () => {
    const { app, people } = buildApp();
    for (const who of ['faculty', 'hod', 'admin_manager', 'hr_executive']) {
      expectRefusal(await create(app, tokens.portal(people[who]), BODY), 403, 'NOT_AN_ANNOUNCER');
    }
    for (const who of ['hr', 'ceo', 'super_admin']) {
      expect((await create(app, tokens.portal(people[who]), BODY)).status).toBe(201);
    }
    // An attendance-only session carries no portal role, so it has no announcement right.
    expectRefusal(await create(app, tokens.attendance(people.attendance), BODY), 403, 'NOT_AN_ANNOUNCER');
  });

  it('refuses a fourth pinned announcement', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_announcements = [1, 2, 3].map((n) => W.announcementRow(w.people.hr.employee.id, n, { pinned: true }));
    } });
    expectRefusal(await create(app, tokens.portal(people.hr), { ...BODY, pinned: true }), 409, 'PIN_LIMIT');
    expect((await create(app, tokens.portal(people.hr), BODY)).status).toBe(201);
  });

  it('answers 503 MODULE_NOT_INSTALLED before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    db.dropTable('hr_ess_announcement_audience');
    expectRefusal(await create(app, tokens.portal(people.hr), BODY), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('GET /api/ess/wall/announcements', () => {
  it('shows what was sent to me, pinned first, with my own read state', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_announcements = [
        W.announcementRow(w.people.hr.employee.id, 1, { title: 'Reply to the email thread' }),
        W.announcementRow(w.people.hr.employee.id, 2, { title: 'Pinned: canteen timings', pinned: true }),
      ];
      w.tables.hr_ess_announcement_audience = [
        W.audienceRow(W.ANNOUNCEMENT_ID(1), w.people.faculty.employee.id),
        W.audienceRow(W.ANNOUNCEMENT_ID(2), w.people.faculty.employee.id),
      ];
      w.tables.hr_ess_announcement_reads = [W.readRow(W.ANNOUNCEMENT_ID(1), w.people.faculty.employee.id)];
    } });
    const res = await inbox(app, tokens.portal(people.faculty));
    expect(res.status).toBe(200);
    expect(res.body.announcements.map((a) => a.title)).toEqual(['Pinned: canteen timings', 'Reply to the email thread']);
    expect(res.body.announcements[1].read_at).toBe(W.AT);
    expect(res.body.announcements[0].read_at).toBe(null);
    // Somebody it was never sent to sees an empty list, not a refusal: the Wall is everybody's.
    const outsider = await inbox(app, tokens.portal(people.faculty));
    expect(outsider.status).toBe(200);
  });

  it('leaves a draft and a deleted one out', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_announcements = [
        W.announcementRow(w.people.hr.employee.id, 1, { published_at: null }),
        W.announcementRow(w.people.hr.employee.id, 2, { deleted_at: W.AT }),
        W.announcementRow(w.people.hr.employee.id, 3),
      ];
      w.tables.hr_ess_announcement_audience = [1, 2, 3].map((n) => W.audienceRow(W.ANNOUNCEMENT_ID(n), w.people.faculty.employee.id));
    } });
    const res = await inbox(app, tokens.portal(people.faculty));
    expect(res.body.announcements.map((a) => a.id)).toEqual([W.ANNOUNCEMENT_ID(3)]);
  });

  it('answers 503 MODULE_NOT_INSTALLED before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp({ setup: (w) => {
      w.tables.hr_ess_announcement_audience = [W.audienceRow(W.ANNOUNCEMENT_ID(1), w.people.faculty.employee.id)];
    } });
    db.dropTable('hr_ess_announcements');
    expectRefusal(await inbox(app, tokens.portal(people.faculty)), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('GET, PATCH and DELETE /api/ess/wall/announcements/{id}', () => {
  const seeded = (change = {}) => (w) => {
    w.tables.hr_ess_announcements = [W.announcementRow(w.people.hr.employee.id, 1, change)];
    w.tables.hr_ess_announcement_audience = [W.audienceRow(W.ANNOUNCEMENT_ID(1), w.people.faculty.employee.id)];
  };

  it('shows one to somebody it reached, and shows its sender the counts', async () => {
    const { app, people } = buildApp({ setup: seeded() });
    const reader = await one(app, tokens.portal(people.faculty), W.ANNOUNCEMENT_ID(1));
    expect(reader.status).toBe(200);
    expect(reader.body.announcement.counts).toBeUndefined();
    const sender = await one(app, tokens.portal(people.hr), W.ANNOUNCEMENT_ID(1));
    expect(sender.body.announcement.counts).toEqual({ sent: 1, read: 0, acknowledged: 0, not_acknowledged: 1 });
  });

  it('refuses somebody it was never sent to, and a draft to anybody but its sender', async () => {
    const { app, people } = buildApp({ setup: seeded() });
    expectRefusal(await one(app, tokens.portal(people.hod), W.ANNOUNCEMENT_ID(1)), 404, 'NOT_FOUND');
    const draft = buildApp({ setup: seeded({ published_at: null }) });
    expectRefusal(await one(draft.app, tokens.portal(draft.people.faculty), W.ANNOUNCEMENT_ID(1)), 404, 'NOT_FOUND');
    // Its sender reads it before it goes out, which is what "preview" means.
    expect((await one(draft.app, tokens.portal(draft.people.hr), W.ANNOUNCEMENT_ID(1))).status).toBe(200);
  });

  it('edits the sender\'s own, marks it edited, and refuses somebody else\'s', async () => {
    const { app, people } = buildApp({ setup: seeded() });
    const res = await edit(app, tokens.portal(people.hr), W.ANNOUNCEMENT_ID(1), { title: 'Diwali holiday (updated)' });
    expect(res.status).toBe(200);
    expect(res.body.announcement.title).toBe('Diwali holiday (updated)');
    expect(res.body.announcement.edited).toBe(true);
    expectRefusal(await edit(app, tokens.portal(people.ceo), W.ANNOUNCEMENT_ID(1), { title: 'Mine now' }), 403, 'NOT_YOURS');
    expectInvalid(await edit(app, tokens.portal(people.hr), W.ANNOUNCEMENT_ID(1), {}), MESSAGES.NOTHING_TO_CHANGE);
  });

  it('deletes the sender\'s own, and keeps the row so the counts survive', async () => {
    const { app, people, db } = buildApp({ setup: seeded() });
    expectRefusal(await remove(app, tokens.portal(people.faculty), W.ANNOUNCEMENT_ID(1)), 403, 'NOT_YOURS');
    const res = await remove(app, tokens.portal(people.hr), W.ANNOUNCEMENT_ID(1));
    expect(res.status).toBe(204);
    expect(db.tables.hr_ess_announcements[0].deleted_at).toBe(NOW.toISOString());
    expectRefusal(await remove(app, tokens.portal(people.hr), W.ANNOUNCEMENT_ID(1)), 404, 'NOT_FOUND');
  });

  it('answers 503 for a read, an edit and a delete before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp({ setup: seeded() });
    db.dropTable('hr_ess_announcements');
    expectRefusal(await one(app, tokens.portal(people.hr), W.ANNOUNCEMENT_ID(1)), 503, 'MODULE_NOT_INSTALLED');
    expectRefusal(await edit(app, tokens.portal(people.hr), W.ANNOUNCEMENT_ID(1), { title: 'Later' }), 503, 'MODULE_NOT_INSTALLED');
    expectRefusal(await remove(app, tokens.portal(people.hr), W.ANNOUNCEMENT_ID(1)), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('read and acknowledgement', () => {
  const seeded = (change = {}) => (w) => {
    w.tables.hr_ess_announcements = [W.announcementRow(w.people.hr.employee.id, 1, change)];
    w.tables.hr_ess_announcement_audience = [
      W.audienceRow(W.ANNOUNCEMENT_ID(1), w.people.faculty.employee.id),
      W.audienceRow(W.ANNOUNCEMENT_ID(1), w.people.hod.employee.id),
    ];
  };

  it('marks a read once, and the sender\'s read count moves with it', async () => {
    const { app, people, db } = buildApp({ setup: seeded() });
    const token = tokens.portal(people.faculty);
    expect((await read(app, token, W.ANNOUNCEMENT_ID(1))).status).toBe(204);
    expect((await read(app, token, W.ANNOUNCEMENT_ID(1))).status).toBe(204);
    expect(db.tables.hr_ess_announcement_reads).toHaveLength(1);
    expect(db.tables.hr_ess_announcements[0].read_count).toBe(1);
    const sender = await counts(app, tokens.portal(people.hr), W.ANNOUNCEMENT_ID(1));
    expect(sender.body.counts).toEqual({ sent: 2, read: 1, acknowledged: 0, not_acknowledged: 2 });
  });

  it('acknowledges once, inside the closing date, and the sender\'s counts follow', async () => {
    const { app, people, db } = buildApp({ setup: seeded({ needs_ack: true, closes_on: '2026-11-05' }) });
    const token = tokens.portal(people.faculty);
    const res = await ack(app, token, W.ANNOUNCEMENT_ID(1));
    expect(res.status).toBe(200);
    expect(res.body.ack_at).toBe(NOW.toISOString());
    expect((await ack(app, token, W.ANNOUNCEMENT_ID(1))).status).toBe(200);
    expect(db.tables.hr_ess_announcement_reads).toHaveLength(1);
    expect(db.tables.hr_ess_announcements[0].ack_count).toBe(1);
    const sender = await counts(app, tokens.portal(people.hr), W.ANNOUNCEMENT_ID(1));
    expect(sender.body.counts).toEqual({ sent: 2, read: 1, acknowledged: 1, not_acknowledged: 1 });
    expect(sender.body).toMatchObject({ needs_ack: true, closes_on: '2026-11-05' });
  });

  it('refuses an acknowledgement an announcement did not ask for, one past its close, and one from outside the audience', async () => {
    const plain = buildApp({ setup: seeded() });
    expectInvalid(await ack(plain.app, tokens.portal(plain.people.faculty), W.ANNOUNCEMENT_ID(1)), MESSAGES.WALL_ANNOUNCEMENT_ACK);
    const late = buildApp({ setup: seeded({ needs_ack: true, closes_on: '2026-10-01' }) });
    expectRefusal(await ack(late.app, tokens.portal(late.people.faculty), W.ANNOUNCEMENT_ID(1)), 409, 'ACK_CLOSED');
    const asking = buildApp({ setup: seeded({ needs_ack: true, closes_on: '2026-11-05' }) });
    expectRefusal(await ack(asking.app, tokens.portal(asking.people.hoo), W.ANNOUNCEMENT_ID(1)), 403, 'NOT_IN_AUDIENCE');
    expectRefusal(await read(asking.app, tokens.portal(asking.people.hoo), W.ANNOUNCEMENT_ID(1)), 403, 'NOT_IN_AUDIENCE');
  });

  it('answers 503 for a read, an ack and the counts before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp({ setup: seeded({ needs_ack: true, closes_on: '2026-11-05' }) });
    const token = tokens.portal(people.faculty);
    db.dropTable('hr_ess_announcement_reads');
    expectRefusal(await read(app, token, W.ANNOUNCEMENT_ID(1)), 503, 'MODULE_NOT_INSTALLED');
    expectRefusal(await ack(app, token, W.ANNOUNCEMENT_ID(1)), 503, 'MODULE_NOT_INSTALLED');
    const sender = await counts(app, tokens.portal(people.hr), W.ANNOUNCEMENT_ID(1));
    expect(sender.status).toBe(503);
  });
});

describe('GET /api/ess/wall/announcements/{id}/counts and the sender\'s own list', () => {
  it('answers with the counts to the sender and HR, and refuses a reader', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_announcements = [W.announcementRow(w.people.hr.employee.id, 1)];
      w.tables.hr_ess_announcement_audience = [W.audienceRow(W.ANNOUNCEMENT_ID(1), w.people.faculty.employee.id)];
    } });
    expect((await counts(app, tokens.portal(people.hr), W.ANNOUNCEMENT_ID(1))).status).toBe(200);
    // Only HR moderates (decision 8): a super admin reads their own announcements' counts, not HR's.
    expectRefusal(await counts(app, tokens.portal(people.super_admin), W.ANNOUNCEMENT_ID(1)), 403, 'NOT_YOURS');
    expectRefusal(await counts(app, tokens.portal(people.faculty), W.ANNOUNCEMENT_ID(1)), 403, 'NOT_YOURS');
    expectRefusal(await counts(app, tokens.portal(people.hr), W.ANNOUNCEMENT_ID(9)), 404, 'NOT_FOUND');
  });

  it('lists only the caller\'s own announcements, drafts included', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_announcements = [
        W.announcementRow(w.people.hr.employee.id, 1, { created_at: '2026-10-15T05:00:00+00:00' }),
        W.announcementRow(w.people.ceo.employee.id, 2),
        W.announcementRow(w.people.hr.employee.id, 3, { created_at: '2026-10-16T05:00:00+00:00', published_at: null, publish_at: '2026-10-20T04:00:00+00:00' }),
      ];
    } });
    const res = await mine(app, tokens.portal(people.hr));
    expect(res.body.announcements.map((a) => a.id)).toEqual([W.ANNOUNCEMENT_ID(3), W.ANNOUNCEMENT_ID(1)]);
    const published = await mine(app, tokens.portal(people.hr), '?status=published');
    expect(published.body.announcements.map((a) => a.id)).toEqual([W.ANNOUNCEMENT_ID(1)]);
    expectRefusal(await mine(app, tokens.portal(people.faculty)), 403, 'NOT_AN_ANNOUNCER');
  });

  it('answers 503 before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    db.dropTable('hr_ess_announcements');
    expectRefusal(await mine(app, tokens.portal(people.hr)), 503, 'MODULE_NOT_INSTALLED');
  });
});
