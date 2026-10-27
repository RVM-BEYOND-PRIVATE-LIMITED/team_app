const request = require('supertest');
const { buildApp, tokens } = require('./app');
const { call, get, put } = require('./wave6a');
const { uuid } = require('./fixtures');

/**
 * Wave 13 (issue #31): the colleague profile, the owner's About you card and work experience.
 * One entry per documented status of every route it adds. `GET /me/org` is unchanged except for
 * its additive `tree`, so its existing Wave 3 scenarios still cover it.
 */

const PROFILE_DETAILS = '/api/ess/me/profile-details';
const WORK_EXPERIENCE = '/api/ess/me/work-experience';
const COLLEAGUE = (id) => `/api/ess/directory/${id}`;
const NOT_AN_EMPLOYEE = uuid('e', 99);

const WORK = (w) => {
  w.tables.hr_ess_work_experience = [
    {
      id: '1a000000-0000-4000-8000-000000000001',
      employee_id: w.people.faculty.employee.id,
      company: 'RVM CAD',
      role_title: 'CAD Faculty',
      from_date: '2023-04-01',
      to_date: null,
      is_current: true,
      location: 'Faridabad',
      description: 'AutoCAD and 3D modelling.',
      is_visible: true,
      created_at: '2026-10-16T06:00:00+00:00',
      updated_at: '2026-10-16T06:00:00+00:00',
    },
    {
      id: '1a000000-0000-4000-8000-000000000002',
      employee_id: w.people.faculty.employee.id,
      company: 'ACME Ltd',
      role_title: 'Designer',
      from_date: '2020-06-01',
      to_date: '2023-03-31',
      is_current: false,
      location: 'Pune',
      description: 'Product drawings.',
      is_visible: false,
      created_at: '2026-10-16T06:00:00+00:00',
      updated_at: '2026-10-16T06:00:00+00:00',
    },
  ];
};

const SOCIAL = (w) => {
  w.tables.hr_ess_profile_details = [{
    employee_id: w.people.faculty.employee.id,
    about: 'I draw, teach AutoCAD and collect old maps.',
    likes: 'Sketching, music, long walks',
    dislikes: 'Late meetings',
    anniversary_date: '2018-02-14',
    updated_at: '2026-10-16T06:00:00+00:00',
    updated_by_user_id: w.people.faculty.user.id,
  }];
  w.tables.hr_ess_personal_details = [{
    employee_id: w.people.faculty.employee.id,
    date_of_birth: '1994-05-21',
    blood_group: 'B+',
    updated_at: '2026-10-16T06:00:00+00:00',
  }];
};

const PRAISE = (w) => {
  w.tables.hr_ess_wall_posts = [
    {
      id: '1b000000-0000-4000-8000-000000000001',
      employee_id: w.people.hr.employee.id,
      kind: 'praise',
      scope: 'org',
      body: 'Always helping the batch.',
      badge: 'mentor',
      about_employee_id: w.people.faculty.employee.id,
      attachments: [],
      mentions: [],
      reaction_counts: {},
      comment_count: 0,
      created_at: '2026-10-12T05:00:00+00:00',
      updated_at: '2026-10-12T05:00:00+00:00',
      hidden_at: null,
      deleted_at: null,
    },
    {
      id: '1b000000-0000-4000-8000-000000000002',
      employee_id: w.people.hr.employee.id,
      kind: 'praise',
      scope: 'org',
      body: 'A patient teacher.',
      badge: 'mentor',
      about_employee_id: w.people.faculty.employee.id,
      attachments: [],
      mentions: [],
      reaction_counts: {},
      comment_count: 0,
      created_at: '2026-10-15T05:00:00+00:00',
      updated_at: '2026-10-15T05:00:00+00:00',
      hidden_at: null,
      deleted_at: null,
    },
  ];
};

const ENTRY = (change = {}) => ({
  company: 'RVM CAD',
  role_title: 'CAD Faculty',
  from_date: '2023-04-01',
  is_current: true,
  location: 'Faridabad',
  description: 'AutoCAD and 3D modelling.',
  is_visible: true,
  ...change,
});

const noToken = (method, path, body) => async () => {
  const { app } = buildApp();
  const req = method === 'get' ? request(app).get(path) : request(app).put(path);
  return req.send(body === undefined ? {} : body);
};

const rateLimited = (who, send) => async () => {
  const world = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
  const token = who === 'attendance' ? tokens.attendance(world.people.attendance) : tokens.portal(world.people[who]);
  await send(world.app, token);
  return send(world.app, token);
};

const WAVE_13 = {
  'GET /api/ess/me/profile-details': [
    ['200, a filled card', call('faculty', get(PROFILE_DETAILS), { setup: SOCIAL })],
    ['200, no row yet', call('faculty', get(PROFILE_DETAILS))],
    ['401, no token', noToken('get', PROFILE_DETAILS)],
    ['403 NOT_LINKED, a desk login', call('desk', get(PROFILE_DETAILS))],
    ['429 RATE_LIMITED', rateLimited('faculty', (app, token) => get(PROFILE_DETAILS)(app, token))],
    ['503 MODULE_NOT_INSTALLED', call('faculty', get(PROFILE_DETAILS), { prepare: (w) => w.db.dropTable('hr_ess_profile_details') })],
  ],
  'PUT /api/ess/me/profile-details': [
    ['200, saved', call('faculty', put(PROFILE_DETAILS, { about: 'I draw.', likes: 'Music' }), { setup: SOCIAL })],
    ['200, cleared', call('faculty', put(PROFILE_DETAILS, { dislikes: null, anniversary_date: null }), { setup: SOCIAL })],
    ['400 VALIDATION_FAILED, nothing to change', call('faculty', put(PROFILE_DETAILS, {}))],
    ['400 VALIDATION_FAILED, an about over 1,000 characters', call('faculty', put(PROFILE_DETAILS, { about: 'x'.repeat(1001) }))],
    ['400 VALIDATION_FAILED, a date that is not a day', call('faculty', put(PROFILE_DETAILS, { anniversary_date: '2026-02-30' }))],
    ['401, no token', noToken('put', PROFILE_DETAILS, { about: 'Hello.' })],
    ['403 NOT_LINKED, a desk login', call('desk', put(PROFILE_DETAILS, { about: 'Hello.' }))],
    ['429 RATE_LIMITED', rateLimited('faculty', (app, token) => put(PROFILE_DETAILS, { about: 'Hello.' })(app, token))],
    ['503 MODULE_NOT_INSTALLED', call('faculty', put(PROFILE_DETAILS, { about: 'Hello.' }), { prepare: (w) => w.db.dropTable('hr_ess_profile_details') })],
  ],
  'GET /api/ess/me/work-experience': [
    ['200, my whole history', call('faculty', get(WORK_EXPERIENCE), { setup: WORK })],
    ['200, no entries', call('faculty', get(WORK_EXPERIENCE))],
    ['401, no token', noToken('get', WORK_EXPERIENCE)],
    ['403 NOT_LINKED, a desk login', call('desk', get(WORK_EXPERIENCE))],
    ['429 RATE_LIMITED', rateLimited('faculty', (app, token) => get(WORK_EXPERIENCE)(app, token))],
    ['503 MODULE_NOT_INSTALLED', call('faculty', get(WORK_EXPERIENCE), { prepare: (w) => w.db.dropTable('hr_ess_work_experience') })],
  ],
  'PUT /api/ess/me/work-experience': [
    ['200, replaced', call('faculty', put(WORK_EXPERIENCE, { entries: [ENTRY()] }))],
    ['200, cleared', call('faculty', put(WORK_EXPERIENCE, { entries: [] }), { setup: WORK })],
    ['400 VALIDATION_FAILED, more than 20 entries', call('faculty', put(WORK_EXPERIENCE, { entries: Array.from({ length: 21 }, () => ENTRY()) }))],
    ['400 VALIDATION_FAILED, a date that is not a day', call('faculty', put(WORK_EXPERIENCE, { entries: [ENTRY({ from_date: '2026-02-30', is_current: false })] }))],
    ['400 VALIDATION_FAILED, a current role with an end date', call('faculty', put(WORK_EXPERIENCE, { entries: [ENTRY({ to_date: '2026-10-01' })] }))],
    ['400 VALIDATION_FAILED, a location over 200 characters', call('faculty', put(WORK_EXPERIENCE, { entries: [ENTRY({ location: 'x'.repeat(201) })] }))],
    ['401, no token', noToken('put', WORK_EXPERIENCE, { entries: [ENTRY()] })],
    ['403 NOT_LINKED, a desk login', call('desk', put(WORK_EXPERIENCE, { entries: [ENTRY()] }))],
    ['429 RATE_LIMITED', rateLimited('faculty', (app, token) => put(WORK_EXPERIENCE, { entries: [ENTRY()] })(app, token))],
    ['503 MODULE_NOT_INSTALLED', call('faculty', put(WORK_EXPERIENCE, { entries: [ENTRY()] }), { prepare: (w) => w.db.dropTable('hr_ess_work_experience') })],
  ],
  'GET /api/ess/directory/{id}': [
    ['200, a colleague with HR looking on', call('hr', get(COLLEAGUE(uuid('e', 11))), { setup: (w) => { SOCIAL(w); WORK(w); PRAISE(w); } })],
    ['200, myself', call('faculty', get(COLLEAGUE(uuid('e', 11))), { setup: (w) => { SOCIAL(w); WORK(w); PRAISE(w); } })],
    ['200, a report sees no manager phone', call('attendance', get(COLLEAGUE(uuid('e', 6))))],
    ['400 VALIDATION_FAILED, not an id', call('faculty', get(COLLEAGUE('not-an-id')))],
    ['401, no token', noToken('get', COLLEAGUE(uuid('e', 11)))],
    ['403 NOT_LINKED, a desk login', call('desk', get(COLLEAGUE(uuid('e', 11))))],
    ['404 NOT_FOUND, an archived person', call('hr', get(COLLEAGUE(uuid('e', 11))), { setup: (w) => { w.people.faculty.employee.is_archived = true; } })],
    ['404 NOT_FOUND, an exited person', call('hr', get(COLLEAGUE(uuid('e', 11))), { setup: (w) => { w.people.faculty.employee.employment_status = 'exited'; } })],
    ['404 NOT_FOUND, nobody there', call('hr', get(COLLEAGUE(NOT_AN_EMPLOYEE)))],
    ['429 RATE_LIMITED', rateLimited('faculty', (app, token) => get(COLLEAGUE(uuid('e', 11)))(app, token))],
    ['503 MODULE_NOT_INSTALLED', call('faculty', get(COLLEAGUE(uuid('e', 11))), { prepare: (w) => w.db.dropTable('hr_ess_profile_details') })],
  ],
};

module.exports = { WAVE_13, WORK, SOCIAL, PRAISE, ENTRY, PROFILE_DETAILS, WORK_EXPERIENCE, COLLEAGUE };
