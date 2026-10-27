const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');

/** Issue #31: one colleague's live profile, the contact rule, badges and visible experience. */

const path = (id) => `/api/ess/directory/${id}`;
const facultyId = (w) => w.people.faculty.employee.id;

const seed = (w) => {
  w.tables.hr_ess_personal_details = [{
    employee_id: facultyId(w),
    date_of_birth: '1994-05-21',
    blood_group: 'B+',
    updated_at: '2026-10-16T06:00:00+00:00',
  }];
  w.tables.hr_ess_profile_details = [{
    employee_id: facultyId(w),
    about: 'I draw, teach AutoCAD and collect old maps.',
    likes: 'Sketching, music',
    dislikes: 'Late meetings',
    anniversary_date: '2018-02-14',
    updated_at: '2026-10-16T06:00:00+00:00',
  }];
  w.tables.hr_ess_work_experience = [
    {
      id: '1a000000-0000-4000-8000-000000000001', employee_id: facultyId(w), company: 'RVM CAD',
      role_title: 'CAD Faculty', from_date: '2023-04-01', to_date: null, is_current: true,
      location: 'Faridabad', description: 'AutoCAD.', is_visible: true,
      created_at: '2026-10-16T06:00:00+00:00', updated_at: '2026-10-16T06:00:00+00:00',
    },
    {
      id: '1a000000-0000-4000-8000-000000000002', employee_id: facultyId(w), company: 'ACME Ltd',
      role_title: 'Designer', from_date: '2020-06-01', to_date: '2023-03-31', is_current: false,
      location: 'Pune', description: 'Product drawings.', is_visible: false,
      created_at: '2026-10-16T06:00:00+00:00', updated_at: '2026-10-16T06:00:00+00:00',
    },
  ];
  const praise = (id, badge, at, change = {}) => ({
    id, employee_id: w.people.hr.employee.id, kind: 'praise', scope: 'org', body: 'Thank you.',
    badge, about_employee_id: facultyId(w), attachments: [], mentions: [], reaction_counts: {}, comment_count: 0,
    created_at: at, updated_at: at, hidden_at: null, deleted_at: null, ...change,
  });
  w.tables.hr_ess_wall_posts = [
    praise('1b000000-0000-4000-8000-000000000001', 'mentor', '2026-10-12T05:00:00+00:00'),
    praise('1b000000-0000-4000-8000-000000000002', 'mentor', '2026-10-15T05:00:00+00:00'),
    praise('1b000000-0000-4000-8000-000000000003', 'knowledge_sharer', '2026-10-14T05:00:00+00:00'),
    praise('1b000000-0000-4000-8000-000000000004', 'mentor', '2026-10-16T05:00:00+00:00', { hidden_at: '2026-10-16T06:00:00+00:00' }),
    praise('1b000000-0000-4000-8000-000000000005', 'not_a_badge', '2026-10-16T05:00:00+00:00'),
  ];
};

const view = (app, viewer, targetId) => request(app).get(path(targetId)).set(bearer(tokens.portal(viewer)));
const as = (app, person) => view(app, person, person.employee.id);

describe('GET /api/ess/directory/{id}', () => {
  it('shows the live profile, badges and visible experience', async () => {
    const { app, people } = buildApp({ setup: seed });
    const res = await view(app, people.hr, people.faculty.employee.id);
    expect(res.status).toBe(200);
    expect(res.body.employee).toMatchObject({
      id: people.faculty.employee.id,
      full_name: 'Test CAD Faculty',
      employee_code: 'RVM-011',
      designation: 'CAD Faculty',
      department: { name: 'Technical Training' },
      branch: { name: 'Faridabad' },
      email: 'faculty@example.test',
      phone: '9710000011',
      employment_status: 'active',
      notice_period: false,
      date_of_joining: '2025-01-01',
      date_of_birth: '1994-05-21',
    });
    expect(res.body.employee.photo_url).toMatch(/^data:image\/jpeg;base64,/);
    expect(res.body.about).toBe('I draw, teach AutoCAD and collect old maps.');
    expect(res.body.likes).toBe('Sketching, music');
    expect(res.body.dislikes).toBe('Late meetings');
    expect(res.body.anniversary_date).toBe('2018-02-14');
    expect(res.body.blood_group).toBe('B+');
    expect(res.body.earned_badges).toEqual([
      { id: 'mentor', label: 'Mentor', for: 'people', count: 2, last_earned_at: '2026-10-15T05:00:00+00:00' },
      { id: 'knowledge_sharer', label: 'Always teaching', for: 'people', count: 1, last_earned_at: '2026-10-14T05:00:00+00:00' },
    ]);
    // The hidden entry is not on a colleague's view.
    expect(res.body.work_experience.map((e) => e.company)).toEqual(['RVM CAD']);
  });

  it('keeps the contact rule A: a report does not see a manager\'s phone', async () => {
    const { app, people } = buildApp();
    const report = await request(app).get(path(people.admin_manager.employee.id))
      .set(bearer(tokens.attendance(people.attendance)));
    expect(report.status).toBe(200);
    expect(report.body.employee.phone).toBe(null);

    const manager = await request(app).get(path(people.attendance.employee.id))
      .set(bearer(tokens.portal(people.admin_manager)));
    expect(manager.body.employee.phone).toBe('9710000050');
  });

  it('shows me my own phone, and HR everybody\'s', async () => {
    const { app, people } = buildApp();
    expect((await as(app, people.faculty)).body.employee.phone).toBe('9710000011');
    expect((await view(app, people.hr, people.faculty.employee.id)).body.employee.phone).toBe('9710000011');
  });

  it('is read live: a save on the owner\'s card shows on the next open', async () => {
    const { app, people } = buildApp();
    await request(app).put('/api/ess/me/profile-details')
      .set(bearer(tokens.portal(people.faculty))).send({ about: 'Fresh words.' });
    const res = await view(app, people.hr, people.faculty.employee.id);
    expect(res.body.about).toBe('Fresh words.');
  });

  it.each([
    ['an archived person', (w) => { w.people.faculty.employee.is_archived = true; }],
    ['an exited person', (w) => { w.people.faculty.employee.employment_status = 'exited'; }],
    ['a person past their exit day', (w) => { w.people.faculty.employee.date_of_exit = '2026-10-15'; }],
  ])('answers 404 for %s', async (_label, setup) => {
    const { app, people } = buildApp({ setup });
    expectRefusal(await view(app, people.hr, people.faculty.employee.id), 404, 'NOT_FOUND');
  });

  it('answers 404 for somebody who does not exist', async () => {
    const { app, people } = buildApp();
    expectRefusal(await request(app).get(path('8f000000-0000-4000-8000-000000000099'))
      .set(bearer(tokens.portal(people.hr))), 404, 'NOT_FOUND');
  });

  it('refuses an id that is not one with 400', async () => {
    const { app, people } = buildApp();
    expectInvalid(await request(app).get('/api/ess/directory/not-an-id')
      .set(bearer(tokens.portal(people.hr))), MESSAGES.INVALID_ID);
  });

  it('answers 401 with no token and 403 for the desk login', async () => {
    const { app, people } = buildApp();
    expectRefusal(await request(app).get(path(people.faculty.employee.id)), 401, 'NOT_AUTHENTICATED');
    expectRefusal(await request(app).get(path(people.faculty.employee.id))
      .set(bearer(tokens.portal(people.desk))), 403, 'NOT_LINKED');
  });

  it('answers 503 when the migration has not been applied', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    db.dropTable('hr_ess_profile_details');
    expectRefusal(await view(app, people.hr, people.faculty.employee.id), 503, 'MODULE_NOT_INSTALLED');
  });
});
