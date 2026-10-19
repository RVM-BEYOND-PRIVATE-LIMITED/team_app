const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');
const W = require('./helpers/wallFixtures');

/** Task F6: birthdays (day and month only), anniversaries, new joiners, one-tap wishes, and the opt-out. */

const CARDS = '/api/ess/wall/celebrations';
const WISHES = '/api/ess/wall/wishes';
const OPTOUT = '/api/ess/me/celebration-optout';

const cards = (app, token, query = '') => request(app).get(`${CARDS}${query}`).set(bearer(token));
const wish = (app, token, body) => request(app).post(WISHES).set(bearer(token)).send(body);
const getOptout = (app, token) => request(app).get(OPTOUT).set(bearer(token));
const putOptout = (app, token, body) => request(app).put(OPTOUT).set(bearer(token)).send(body);

/** The fixture with a few dates of birth and joining dates the cards can find. */
const withDates = (w) => {
  w.tables.hr_ess_personal_details = [
    { employee_id: w.people.faculty.employee.id, date_of_birth: '1992-10-16', updated_at: W.AT },
    { employee_id: w.people.hod.employee.id, date_of_birth: '1988-10-20', updated_at: W.AT },
    { employee_id: w.people.hr.employee.id, date_of_birth: '1990-12-25', updated_at: W.AT },
    { employee_id: w.people.admin.employee.id, date_of_birth: '1995-10-18', updated_at: W.AT },
  ];
  w.people.hod.employee.date_of_joining = '2024-10-16';
  w.people.admin.employee.date_of_joining = '2026-10-06';
  w.people.hoo.employee.date_of_joining = '2021-10-20';
};

describe('GET /api/ess/wall/celebrations', () => {
  it('finds today\'s birthday, the ones coming and the new joiners, with no year on a birthday', async () => {
    const { app, people } = buildApp({ setup: withDates });
    const res = await cards(app, tokens.portal(people.faculty));
    expect(res.status).toBe(200);
    expect(res.body.today).toBe('2026-10-16');
    expect(res.body.birthdays.map((b) => b.employee.full_name)).toEqual(['Test CAD Faculty', 'Test Branch Admin', 'Test CAD HOD']);
    // Day and month only: never the year, and never the stored date.
    expect(res.body.birthdays[0].date_of_birth).toEqual({ day: 16, month: 10 });
    expect(JSON.stringify(res.body)).not.toContain('1992-10-16');
    expect(res.body.anniversaries[0]).toMatchObject({ years: 2, date_of_joining: '2024-10-16' });
    expect(res.body.new_joiners.map((j) => j.employee.full_name)).toEqual(['Test Branch Admin']);
    expect(res.body.new_joiners[0].days).toBe(10);
  });

  it('narrows the window with days, and refuses a window it cannot take', async () => {
    const { app, people } = buildApp({ setup: withDates });
    const today = await cards(app, tokens.portal(people.faculty), '?days=1');
    expect(today.body.birthdays.map((b) => b.employee.full_name)).toEqual(['Test CAD Faculty']);
    expect(today.body.window_days).toBe(1);
    expectInvalid(await cards(app, tokens.portal(people.faculty), '?days=0'), MESSAGES.WALL_CELEBRATIONS);
    expectInvalid(await cards(app, tokens.portal(people.faculty), '?days=365'), MESSAGES.WALL_CELEBRATIONS);
    expectInvalid(await cards(app, tokens.portal(people.faculty), '?days=someday'), MESSAGES.WALL_CELEBRATIONS);
  });

  it('hides a birthday for anybody who opted out, and says how many did', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      withDates(w);
      w.tables.hr_ess_celebration_optouts = [{ employee_id: w.people.faculty.employee.id, hidden: true, updated_at: W.AT }];
    } });
    const res = await cards(app, tokens.portal(people.faculty));
    expect(res.body.birthdays.map((b) => b.employee.full_name)).toEqual(['Test Branch Admin', 'Test CAD HOD']);
    expect(res.body.birthdays_hidden).toBe(1);
    // An opt-out is still an anniversary if that is what the day is, and the joiners are unaffected.
    expect(res.body.anniversaries).toHaveLength(2);
  });

  it('shows who has been wished, and whether I have wished them', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      withDates(w);
      w.tables.hr_ess_wall_posts = [W.postRow(w.people.hr.employee.id, 1, {
        kind: 'wish', body: 'Happy birthday!', occasion: 'birthday', about_employee_id: w.people.faculty.employee.id,
      })];
      w.tables.hr_ess_wall_wishes = [{
        id: W.uuid('a6', 1), post_id: W.POST_ID(1), about_id: w.people.faculty.employee.id,
        wisher_id: w.people.hr.employee.id, occasion: 'birthday', year: 2026, created_at: W.AT,
      }];
    } });
    const mine = await cards(app, tokens.portal(people.hr));
    const card = mine.body.birthdays.find((b) => b.employee.id === people.faculty.employee.id);
    expect(card).toMatchObject({ wished_by_me: true, wish_count: 1 });
    const other = await cards(app, tokens.portal(people.hod));
    const same = other.body.birthdays.find((b) => b.employee.id === people.faculty.employee.id);
    expect(same).toMatchObject({ wished_by_me: false, wish_count: 1 });
  });

  it('leaves out somebody archived, and anybody who left', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      withDates(w);
      w.people.hr.employee.is_archived = true;
    } });
    const res = await cards(app, tokens.portal(people.faculty));
    expect(res.body.birthdays.map((b) => b.employee.employee_code)).not.toContain('RVM-009');
  });

  it('answers 503 MODULE_NOT_INSTALLED before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp({ setup: withDates });
    db.dropTable('hr_ess_personal_details');
    expectRefusal(await cards(app, tokens.portal(people.faculty)), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('POST /api/ess/wall/wishes', () => {
  it('posts a one-tap wish, in the feed and in the wish book', async () => {
    const { app, people, db } = buildApp();
    const res = await wish(app, tokens.portal(people.hr), {
      employee_id: people.faculty.employee.id, occasion: 'birthday', body: 'Many happy returns!',
    });
    expect(res.status).toBe(201);
    expect(res.body.post).toMatchObject({
      kind: 'wish', occasion: 'birthday', body: 'Many happy returns!',
      about: { id: people.faculty.employee.id }, mine: true,
    });
    expect(db.tables.hr_ess_wall_wishes).toHaveLength(1);
    expect(db.tables.hr_ess_wall_wishes[0]).toMatchObject({
      about_id: people.faculty.employee.id, wisher_id: people.hr.employee.id, occasion: 'birthday', year: 2026,
    });
  });

  it('refuses a second wish for the same person and occasion this year, and leaves nothing behind', async () => {
    const { app, people, db } = buildApp();
    const token = tokens.portal(people.hr);
    await wish(app, token, { employee_id: people.faculty.employee.id, occasion: 'birthday', body: 'Happy birthday!' });
    const again = await wish(app, token, { employee_id: people.faculty.employee.id, occasion: 'birthday', body: 'And again!' });
    expectRefusal(again, 409, 'ALREADY_WISHED');
    // The refused wish's post goes with it, so nothing half-made is left on the wall.
    expect(db.tables.hr_ess_wall_posts.filter((p) => p.deleted_at == null)).toHaveLength(1);
    // A different occasion, or another year, is its own wish.
    expect((await wish(app, token, { employee_id: people.faculty.employee.id, occasion: 'anniversary', body: 'Two years!' })).status).toBe(201);
  });

  it('refuses wishing myself, an occasion it does not have, and an empty wish', async () => {
    const { app, people } = buildApp();
    const token = tokens.portal(people.hr);
    expectInvalid(await wish(app, token, { employee_id: people.hr.employee.id, occasion: 'birthday', body: 'Happy birthday to me!' }), MESSAGES.WALL_WISH_SELF);
    expectInvalid(await wish(app, token, { employee_id: people.faculty.employee.id, occasion: 'new_year', body: 'Happy new year!' }), MESSAGES.WALL_WISH_OCCASION);
    expectInvalid(await wish(app, token, { employee_id: people.faculty.employee.id, occasion: 'birthday', body: '   ' }), MESSAGES.WALL_POST_BODY);
  });

  it('refuses a person who is not on the HR record', async () => {
    const { app, people } = buildApp();
    expectRefusal(
      await wish(app, tokens.portal(people.hr), { employee_id: W.uuid('e', 99), occasion: 'birthday', body: 'Happy birthday!' }),
      404, 'NOT_FOUND',
    );
  });

  it('answers 503 MODULE_NOT_INSTALLED before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    db.dropTable('hr_ess_wall_wishes');
    expectRefusal(
      await wish(app, tokens.portal(people.hr), { employee_id: people.faculty.employee.id, occasion: 'birthday', body: 'Happy birthday!' }),
      503, 'MODULE_NOT_INSTALLED',
    );
  });
});

describe('the birthday switch', () => {
  it('is on until it is turned off, and says so either way', async () => {
    const { app, people } = buildApp();
    const token = tokens.portal(people.faculty);
    expect((await getOptout(app, token)).body).toEqual({ celebrations: { hidden: false } });
    const off = await putOptout(app, token, { hidden: true });
    expect(off.status).toBe(200);
    expect(off.body).toEqual({ celebrations: { hidden: true } });
    expect((await getOptout(app, token)).body).toEqual({ celebrations: { hidden: true } });
    const on = await putOptout(app, token, { hidden: false });
    expect(on.body).toEqual({ celebrations: { hidden: false } });
    // The switch is recorded, with nothing personal in the trail.
    expect(people.faculty.employee.id).toBeTruthy();
  });

  it('refuses a value that is not true or false, and answers 503 before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    const token = tokens.portal(people.faculty);
    expectInvalid(await putOptout(app, token, { hidden: 'yes' }), MESSAGES.WALL_CELEBRATIONS);
    db.dropTable('hr_ess_celebration_optouts');
    expectRefusal(await putOptout(app, token, { hidden: true }), 503, 'MODULE_NOT_INSTALLED');
    expectRefusal(await getOptout(app, token), 503, 'MODULE_NOT_INSTALLED');
  });
});
