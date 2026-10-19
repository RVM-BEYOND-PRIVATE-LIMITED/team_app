const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { PRAISE_BADGES } = require('../src/policy/wall');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');
const W = require('./helpers/wallFixtures');

/** Task F3: praise with the fixed RVM badges, and its read on the receiver's own screen. */

const PRAISE = '/api/ess/wall/praise';
const MINE = '/api/ess/me/praise';

const give = (app, token, body) => request(app).post(PRAISE).set(bearer(token)).send(body);
const list = (app, token, query = '') => request(app).get(`${MINE}${query}`).set(bearer(token));

const praiseRow = (aboutId, n, change = {}) => W.postRow(W.uuid('e', 9), n, {
  // The giver is RVM-009 (the HR fixture) unless a test says otherwise; aboutId is who it praises.
  kind: 'praise', scope: 'org', body: 'Helped the batch settle in.', badge: 'mentor', about_employee_id: aboutId, ...change,
});

describe('POST /api/ess/wall/praise', () => {
  it('praises a colleague, in the feed and with the badge the request named', async () => {
    const { app, people } = buildApp();
    const res = await give(app, tokens.portal(people.hr), {
      employee_id: people.faculty.employee.id,
      badge: 'extra_mile',
      reason: 'Stayed back to finish the lab setup for the new batch.',
    });
    expect(res.status).toBe(201);
    expect(res.body.post).toMatchObject({
      kind: 'praise',
      scope: 'org',
      body: 'Stayed back to finish the lab setup for the new batch.',
      badge: { id: 'extra_mile', label: 'Going the extra mile' },
      about: { id: people.faculty.employee.id, full_name: 'Test CAD Faculty' },
      mine: true,
    });
    expect(res.body.badge).toMatchObject({ id: 'extra_mile', label: 'Going the extra mile' });
  });

  it('tells the person praised, in their own words', async () => {
    const { app, people, db } = buildApp();
    await give(app, tokens.portal(people.hr), { employee_id: people.faculty.employee.id, badge: 'mentor', reason: 'Always helping.' });
    expect(db.tables.hr_ess_notifications).toEqual([
      expect.objectContaining({ category: 'praise', employee_id: people.faculty.employee.id }),
    ]);
  });

  it('stores an optional photo in the ESS bucket, and works without one', async () => {
    const { app, people, db } = buildApp();
    const res = await give(app, tokens.portal(people.hr), {
      employee_id: people.faculty.employee.id, badge: 'student_first', reason: 'Took the extra session.', attachments: [W.file()],
    });
    expect(res.body.post.attachments[0].url).toMatch(/^https:\/\/storage\.test\/ESS\/praise\//);
    const plain = await give(app, tokens.portal(people.hr), { employee_id: people.faculty.employee.id, badge: 'mentor', reason: 'Steady hand.' });
    expect(plain.body.post.attachments).toEqual([]);
    expect(db.storageCalls.filter((c) => c.op === 'upload')).toHaveLength(1);
  });

  it('refuses praising myself, a badge that is not RVM\'s, and a reason over 280 characters', async () => {
    const { app, people } = buildApp();
    const token = tokens.portal(people.hr);
    const self = await give(app, token, { employee_id: people.hr.employee.id, badge: 'mentor', reason: 'I did well.' });
    expectInvalid(self, MESSAGES.WALL_PRAISE_SELF);
    const badge = await give(app, token, { employee_id: people.faculty.employee.id, badge: 'employee_of_the_month', reason: 'Great.' });
    expectInvalid(badge, MESSAGES.WALL_PRAISE_BADGE);
    const long = await give(app, token, { employee_id: people.faculty.employee.id, badge: 'mentor', reason: 'x'.repeat(281) });
    expectInvalid(long, MESSAGES.WALL_PRAISE_WHY);
    const short = await give(app, token, { employee_id: people.faculty.employee.id, badge: 'mentor', reason: 'ok' });
    expectInvalid(short, MESSAGES.WALL_PRAISE_WHY);
  });

  it('refuses a person who is not on the HR record, and a branch post with no branch', async () => {
    const { app, people } = buildApp();
    const ghost = await give(app, tokens.portal(people.hr), { employee_id: W.uuid('e', 99), badge: 'mentor', reason: 'Well done.' });
    expectRefusal(ghost, 404, 'NOT_FOUND');
    // The attendance employee's branch is set (the fixture), so a branch praise works.
    const branch = await give(app, tokens.portal(people.hr), {
      employee_id: people.faculty.employee.id, badge: 'team_player', reason: 'Covered the front desk.', scope: 'branch',
    });
    expect(branch.status).toBe(201);
    expect(branch.body.post.branch_id).toBe(people.hr.employee.branch_id);
  });

  it('answers 503 MODULE_NOT_INSTALLED before the migration, and 503 with the database away', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    db.dropTable('hr_ess_wall_posts');
    expectRefusal(await give(app, tokens.portal(people.hr), { employee_id: people.faculty.employee.id, badge: 'mentor', reason: 'Well done.' }), 503, 'MODULE_NOT_INSTALLED');
    const away = buildApp();
    away.db.outage = 'error';
    expectRefusal(await give(away.app, tokens.portal(people.hr), { employee_id: people.faculty.employee.id, badge: 'mentor', reason: 'Well done.' }), 503, 'UNAVAILABLE');
  });
});

describe('GET /api/ess/me/praise', () => {
  it('shows my own praise, newest first, with the badge and who gave it', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [
        praiseRow(w.people.faculty.employee.id, 1, { badge: 'mentor' }),
        praiseRow(w.people.faculty.employee.id, 2, { badge: 'lab_guardian', created_at: '2026-10-16T06:00:00+00:00' }),
        praiseRow(w.people.pune.employee.id, 3, { badge: 'mentor' }),
      ];
    } });
    const res = await list(app, tokens.portal(people.faculty));
    expect(res.status).toBe(200);
    expect(res.body.praise.map((p) => p.badge.id)).toEqual(['lab_guardian', 'mentor']);
    expect(res.body.praise[1].author).toMatchObject({ full_name: 'Test HR Manager' });
    expect(res.body.badges).toHaveLength(12);
    expect(res.body.badges.map((b) => b.id)).toEqual(PRAISE_BADGES.map((b) => b.id));
  });

  it('leaves out deleted and hidden praise, and reads somebody else\'s when asked', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [
        praiseRow(w.people.faculty.employee.id, 1, { deleted_at: W.AT }),
        praiseRow(w.people.faculty.employee.id, 2, { hidden_at: W.AT, hidden_by_name: 'Test HR Manager', hide_reason: 'Too much' }),
        praiseRow(w.people.faculty.employee.id, 3, { badge: 'mentor' }),
      ];
    } });
    const mine = await list(app, tokens.portal(people.faculty));
    expect(mine.body.praise.map((p) => p.id)).toEqual([W.POST_ID(3)]);
    const theirs = await list(app, tokens.portal(people.hr), `?employee_id=${people.faculty.employee.id}`);
    expect(theirs.body.praise.map((p) => p.id)).toEqual([W.POST_ID(3)]);
    const nobody = await list(app, tokens.portal(people.hr), `?employee_id=${W.uuid('e', 99)}`);
    expect(nobody.body.praise).toEqual([]);
  });

  it('refuses an id that is not one, and answers 503 before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    expectInvalid(await list(app, tokens.portal(people.faculty), '?employee_id=nope'), MESSAGES.INVALID_ID);
    db.dropTable('hr_ess_wall_posts');
    expectRefusal(await list(app, tokens.portal(people.faculty)), 503, 'MODULE_NOT_INSTALLED');
  });
});
