const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { TEACHING, FACULTY_ID } = require('./helpers/wave9');
const { uuid } = require('./helpers/fixtures');

/** Task H7 (Phase 2D): the faculty "my day" and the indicators card. */

const DAY = '/api/ess/me/faculty-day';

describe('GET /api/ess/me/faculty-day', () => {
  it('reads today: owned and covered sessions, marks, remarks due and the card', async () => {
    const { app, people } = buildApp({ setup: TEACHING });
    const res = await request(app).get(DAY).set(bearer(tokens.portal(people.faculty)));
    expect(res.status).toBe(200);
    expect(res.body.date).toBe('2026-10-16');
    expect(res.body.faculty_id).toBe(FACULTY_ID);
    expect(res.body.sessions.map((s) => s.name)).toEqual(['CAD Morning Batch', 'AutoCAD Evening Batch']);
    expect(res.body.sessions[0]).toMatchObject({ covered: false, marked: true, students: 2, start_time: '09:00:00', location_id: 1 });
    expect(res.body.sessions[1]).toMatchObject({ covered: true, marked: false, students: 1 });
    expect(res.body.pending_remarks).toBe(1);
    expect(res.body.indicators).toEqual({
      sessions_today: 2,
      marked_today: 1,
      today_percentage: 50,
      // Fridays of the month up to the 16th: the 2nd, the 9th and the 16th, for two batches.
      month_expected: 6,
      month_marked: 1,
      month_percentage: 17,
      // Three joined students, one of them on hold since the 10th; four links in all.
      active_students: 2,
      total_students: 4,
      sessions_without_attendance: 1,
    });
    expect(JSON.stringify(res.body)).not.toMatch(/student_id|student_name|remarks_|phone/);
  });

  it('a roster link without a joined admission is not counted', async () => {
    const SID = (n) => `9e000000-0000-4000-8000-${String(n).padStart(12, '0')}`;
    const { app, people } = buildApp({ setup: (w) => {
      TEACHING(w);
      w.tables.admissions = [
        { student_id: SID(1), joined: false },
        { student_id: SID(2), joined: true },
        { student_id: SID(4), joined: true },
      ];
    } });
    const res = await request(app).get(DAY).set(bearer(tokens.portal(people.faculty)));
    expect(res.status).toBe(200);
    expect(res.body.sessions[0].students).toBe(1);
    expect(res.body.indicators).toMatchObject({ active_students: 2, total_students: 4 });
  });

  it('a substitution that has ended leaves the batch out', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      TEACHING(w);
      w.tables.faculty_substitutions = [{
        id: uuid('8', 9), batch_id: '8d000000-0000-4000-8000-000000000002', original_faculty_id: uuid('f', 4),
        substitute_faculty_id: FACULTY_ID, start_date: '2026-10-01', end_date: '2026-10-10',
      }];
    } });
    const res = await request(app).get(DAY).set(bearer(tokens.portal(people.faculty)));
    expect(res.status).toBe(200);
    expect(res.body.sessions.map((s) => s.name)).toEqual(['CAD Morning Batch']);
    expect(res.body.indicators.month_expected).toBe(3);
  });

  it('an earlier day reads by its own weekday, and the window holds', async () => {
    const { app, people } = buildApp({ setup: TEACHING });
    const earlier = await request(app).get(`${DAY}?date=2026-10-09`).set(bearer(tokens.portal(people.faculty)));
    expect(earlier.status).toBe(200);
    expect(earlier.body.sessions.map((s) => s.name)).toEqual(['CAD Morning Batch', 'AutoCAD Evening Batch']);
    expect(earlier.body.sessions[0].marked).toBe(false);
    expect(earlier.body.indicators).toMatchObject({ sessions_today: 2, marked_today: 0, month_expected: 4, month_percentage: 0 });

    // August is outside the window: this month or last month only.
    const far = await request(app).get(`${DAY}?date=2026-08-07`).set(bearer(tokens.portal(people.faculty)));
    expect(far.status).toBe(400);
    expect(far.body.code).toBe('DAY_OUT_OF_RANGE');
  });

  it('a login with no faculty record is refused, an attendance session included', async () => {
    const { app, people } = buildApp({ setup: TEACHING });
    const hr = await request(app).get(DAY).set(bearer(tokens.portal(people.hr)));
    expect(hr.status).toBe(403);
    expect(hr.body.code).toBe('NOT_FACULTY');
    expect(hr.body.error).toBe(MESSAGES.NOT_FACULTY);
    const punch = await request(app).get(DAY).set(bearer(tokens.attendance(people.attendance)));
    expect(punch.status).toBe(403);
    expect(punch.body.code).toBe('NOT_FACULTY');
  });

  it('a malformed date is refused before anything is read', async () => {
    const { app, people } = buildApp({ setup: TEACHING });
    const res = await request(app).get(`${DAY}?date=16-10-2026`).set(bearer(tokens.portal(people.faculty)));
    expect(res.status).toBe(400);
    expect(res.body.code).toBe('VALIDATION_FAILED');
    expect(res.body.error).toBe(MESSAGES.DATE_FORMAT);
  });

  it('refuses a caller with no token, and answers 503 when the teaching tables cannot be read', async () => {
    const { app } = buildApp({ setup: TEACHING });
    const none = await request(app).get(DAY);
    expect(none.status).toBe(401);

    const world = buildApp({ setup: TEACHING });
    world.db.failWhen = (q) => (q.table === 'student_attendance' ? 'error' : null);
    const broken = await request(world.app).get(DAY).set(bearer(tokens.portal(world.people.faculty)));
    expect(broken.status).toBe(503);
  });
});
