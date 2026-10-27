const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');

/** Issue #31: my About you card — free text and a personal anniversary, self only. */

const PATH = '/api/ess/me/profile-details';

const as = (app, person) => request(app).get(PATH).set(bearer(tokens.portal(person)));
const put = (app, person, body) => request(app).put(PATH).set(bearer(tokens.portal(person))).send(body);

describe('GET /api/ess/me/profile-details', () => {
  it('answers every field as null before I fill anything in', async () => {
    const { app, people } = buildApp();
    const res = await as(app, people.faculty);
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ profile: { about: null, likes: null, dislikes: null, anniversary_date: null, blood_group: null } });
  });

  it('reads the blood group from the personal-details table', async () => {
    const { app, people } = buildApp({
      setup: (w) => {
        w.tables.hr_ess_personal_details = [{ employee_id: w.people.faculty.employee.id, blood_group: 'AB-', updated_at: '2026-10-16T06:00:00+00:00' }];
      },
    });
    expect((await as(app, people.faculty)).body.profile.blood_group).toBe('AB-');
  });

  it('answers 401 with no token and 403 for the desk login', async () => {
    const { app, people } = buildApp();
    expectRefusal(await request(app).get(PATH), 401, 'NOT_AUTHENTICATED');
    expectRefusal(await request(app).get(PATH).set(bearer(tokens.portal(people.desk))), 403, 'NOT_LINKED');
  });

  it('answers 503 when the migration has not been applied', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    db.dropTable('hr_ess_profile_details');
    expectRefusal(await as(app, people.faculty), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('PUT /api/ess/me/profile-details', () => {
  it('saves the fields sent and returns the whole card', async () => {
    const { app, people, db } = buildApp({
      setup: (w) => {
        w.tables.hr_ess_personal_details = [{ employee_id: w.people.faculty.employee.id, blood_group: 'B+', updated_at: '2026-10-16T06:00:00+00:00' }];
      },
    });
    const res = await put(app, people.faculty, {
      about: 'I draw, teach AutoCAD and collect old maps.',
      likes: 'Sketching, music',
      dislikes: 'Late meetings',
      anniversary_date: '2018-02-14',
    });
    expect(res.status).toBe(200);
    expect(res.body.profile).toEqual({
      about: 'I draw, teach AutoCAD and collect old maps.',
      likes: 'Sketching, music',
      dislikes: 'Late meetings',
      anniversary_date: '2018-02-14',
      blood_group: 'B+',
    });
    expect(db.tables.hr_ess_profile_details).toHaveLength(1);
    expect(db.tables.hr_ess_profile_details[0].updated_by_user_id).toBe(people.faculty.user.id);
    // Field names only, never the words the person typed.
    const audit = db.tables.hr_ess_audit.find((a) => a.action === 'profile_details.changed');
    expect(audit.details).toEqual({ fields: ['about', 'likes', 'dislikes', 'anniversary_date'] });
    expect(JSON.stringify(audit)).not.toContain('Sketching');
  });

  it('clears a field with null or an empty string', async () => {
    const { app, people } = buildApp({
      setup: (w) => {
        w.tables.hr_ess_profile_details = [{
          employee_id: w.people.faculty.employee.id,
          about: 'Old about', likes: 'Old likes', dislikes: 'Old dislikes', anniversary_date: '2018-02-14',
          updated_at: '2026-10-16T06:00:00+00:00',
        }];
      },
    });
    const res = await put(app, people.faculty, { about: '', likes: null, anniversary_date: null });
    expect(res.status).toBe(200);
    expect(res.body.profile).toEqual({ about: null, likes: null, dislikes: 'Old dislikes', anniversary_date: null, blood_group: null });
  });

  it('is self only: a save by one person never touches another', async () => {
    const { app, people, db } = buildApp();
    await put(app, people.faculty, { about: 'Mine.' });
    await put(app, people.hr, { about: 'Hers.' });
    expect(db.tables.hr_ess_profile_details).toHaveLength(2);
    expect((await as(app, people.faculty)).body.profile.about).toBe('Mine.');
    expect((await as(app, people.hr)).body.profile.about).toBe('Hers.');
  });

  it.each([
    ['nothing at all', {}, MESSAGES.NOTHING_TO_CHANGE],
    ['an about over 1,000 characters', { about: 'x'.repeat(1001) }, MESSAGES.PROFILE_DETAILS],
    ['likes over 500 characters', { likes: 'x'.repeat(501) }, MESSAGES.PROFILE_DETAILS],
    ['dislikes over 500 characters', { dislikes: 'x'.repeat(501) }, MESSAGES.PROFILE_DETAILS],
    ['an anniversary that is not a day', { anniversary_date: '2026-02-30' }, MESSAGES.ANNIVERSARY_DATE],
    ['an anniversary that is not a date', { anniversary_date: '14 Feb 2018' }, MESSAGES.ANNIVERSARY_DATE],
  ])('refuses %s with 400', async (_label, body, message) => {
    const { app, people } = buildApp();
    expectInvalid(await put(app, people.faculty, body), message);
  });

  it('refuses a field it does not take', async () => {
    const { app, people } = buildApp();
    expectInvalid(await put(app, people.faculty, { blood_group: 'B+' }), MESSAGES.UNKNOWN_FIELD);
  });

  it('answers 401 with no token and 403 for the desk login', async () => {
    const { app, people } = buildApp();
    expectRefusal(await request(app).put(PATH).send({ about: 'Hello.' }), 401, 'NOT_AUTHENTICATED');
    expectRefusal(await request(app).put(PATH).set(bearer(tokens.portal(people.desk))).send({ about: 'Hello.' }), 403, 'NOT_LINKED');
  });

  it('answers 503 when the migration has not been applied', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    db.dropTable('hr_ess_profile_details');
    expectRefusal(await put(app, people.faculty, { about: 'Hello.' }), 503, 'MODULE_NOT_INSTALLED');
  });
});
