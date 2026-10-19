const { buildApp, tokens, bearer } = require('./app');
const request = require('supertest');
const W = require('./wallFixtures');

/** The Wall's remaining routes in the Wave 6 table (announcements, celebrations, moderation). */

const as = (people, who) => (who === 'attendance' ? tokens.attendance(people.attendance) : tokens.portal(people[who]));

const call = (who, send, { prepare, ...options } = {}) => async () => {
  const world = buildApp(options);
  // `prepare` runs after the app is built, so it sees the fake database: `tables` is
  // db.tables, the copy the routes actually read (the fixtures' shape, for a scenario's own eyes).
  if (prepare) prepare({ ...world, tables: world.db.tables });
  return send(world.app, as(world.people, who), world);
};
const mk = (method, path) => (app, token, body) => {
  const r = method === 'get' ? request(app).get(path)
    : method === 'delete' ? request(app).delete(path)
      : method === 'post' ? request(app).post(path)
        : method === 'put' ? request(app).put(path) : request(app).patch(path);
  return r.set(bearer(token)).send(body === undefined ? {} : body);
};
const get = (path) => (app, token) => request(app).get(path).set(bearer(token));
const post = (path, body) => (app, token) => request(app).post(path).set(bearer(token)).send(body === undefined ? {} : body);
const put = (path, body) => (app, token) => request(app).put(path).set(bearer(token)).send(body === undefined ? {} : body);
const patch = (path, body) => (app, token) => request(app).patch(path).set(bearer(token)).send(body === undefined ? {} : body);
const del = (path) => (app, token) => request(app).delete(path).set(bearer(token));


const ANNOUNCEMENT = (change = {}) => (w) => {
  w.tables.hr_ess_announcements = [W.announcementRow(w.people.hr.employee.id, 1, change)];
  w.tables.hr_ess_announcement_audience = [W.audienceRow(W.ANNOUNCEMENT_ID(1), w.people.faculty.employee.id)];
  w.tables.hr_ess_announcement_reads = [];
};
const REPORT = (change = {}) => (w) => {
  w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)];
  w.tables.hr_ess_wall_reports = [W.reportRow(w.people.hod.employee.id, 1, { post_id: W.POST_ID(1), ...change })];
};
const HIDDEN_POST = (w) => { w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1, { hidden_at: W.AT, hidden_by_name: 'Test HR Manager', hide_reason: 'Not for the wall' })]; };
const HIDDEN_COMMENT = (w) => {
  w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)];
  w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1, { hidden_at: W.AT, hidden_by_name: 'Test HR Manager', hide_reason: 'Rude' })];
};

/**
 * The shared refusals. `shared` mirrors the helper in wave6a.js; it is repeated here so the two
 * halves of the table can be read on their own.
 */
const shared = (who, method, path, { body, table, seed } = {}) => {
  const send = (app, token) => {
    const r = method === 'get' ? request(app).get(path)
      : method === 'delete' ? request(app).delete(path)
        : method === 'post' ? request(app).post(path)
          : method === 'put' ? request(app).put(path) : request(app).patch(path);
    if (token) r.set(bearer(token));
    return body === undefined ? r : r.send(body);
  };
  return [
    ['401, no token', async () => send(buildApp().app)],
    ['403 NOT_LINKED, a desk login', call('desk', (app, token) => send(app, token))],
    ['429 RATE_LIMITED', async () => {
      const world = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
      const token = as(world.people, who);
      await send(world.app, token);
      return send(world.app, token);
    }],
    table
      ? ['503 MODULE_NOT_INSTALLED', call(who, (app, token) => send(app, token), { prepare: (w) => { if (seed) seed(w); w.db.dropTable(table); } })]
      : ['503 UNAVAILABLE, the database away', call(who, (app, token) => send(app, token), { prepare: (w) => { w.db.outage = 'error'; } })],
  ];
};

const WAVE_6B = {
  'POST /api/ess/wall/announcements': [
    ['201, an announcement', call('hr', post('/api/ess/wall/announcements', { title: 'Diwali holiday', body: 'The office is closed on 8 November.' }))],
    ['400 VALIDATION_FAILED, no title', call('hr', post('/api/ess/wall/announcements', { title: 'Hi', body: 'The office is closed.' }))],
    ['403 NOT_AN_ANNOUNCER, a faculty member', call('faculty', post('/api/ess/wall/announcements', { title: 'Holiday', body: 'The office is closed.' }))],
    ['409 PIN_LIMIT', call('hr', post('/api/ess/wall/announcements', { title: 'Holiday', body: 'The office is closed.', pinned: true }), {
      setup: (w) => { w.tables.hr_ess_announcements = [1, 2, 3].map((n) => W.announcementRow(w.people.hr.employee.id, n, { pinned: true })); },
    })],
    ...shared('hr', 'post', '/api/ess/wall/announcements', { body: { title: 'Holiday', body: 'The office is closed.' }, table: 'hr_ess_announcements' }),
  ],
  'GET /api/ess/wall/announcements': [
    ['200, mine', call('faculty', get('/api/ess/wall/announcements'), { setup: ANNOUNCEMENT() })],
    ...shared('faculty', 'get', '/api/ess/wall/announcements', { table: 'hr_ess_announcements', seed: ANNOUNCEMENT() }),
  ],
  'GET /api/ess/wall/hr/announcements': [
    ['200, my own list', call('hr', get('/api/ess/wall/hr/announcements'), { setup: ANNOUNCEMENT() })],
    ['400 VALIDATION_FAILED, a status it does not take', call('hr', get('/api/ess/wall/hr/announcements?status=lost'), { setup: ANNOUNCEMENT() })],
    ...shared('hr', 'get', '/api/ess/wall/hr/announcements', { table: 'hr_ess_announcements', seed: ANNOUNCEMENT() }),
  ],
  'GET /api/ess/wall/announcements/{id}': [
    ['200, one it reached', call('faculty', get(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}`), { setup: ANNOUNCEMENT() })],
    ['400 VALIDATION_FAILED, not an id', call('faculty', get('/api/ess/wall/announcements/not-an-id'))],
    ['404 NOT_FOUND, not sent to me', call('hod', get(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}`), { setup: ANNOUNCEMENT() })],
    ...shared('faculty', 'get', `/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}`, { table: 'hr_ess_announcement_audience', seed: (w) => { w.tables.hr_ess_announcements = [W.announcementRow(w.people.hr.employee.id, 1)]; w.tables.hr_ess_announcement_audience = [W.audienceRow(W.ANNOUNCEMENT_ID(1), w.people.faculty.employee.id)]; } }),
  ],
  'PATCH /api/ess/wall/announcements/{id}': [
    ['200, the sender\'s own', call('hr', patch(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}`, { title: 'Diwali holiday (dates confirmed)' }), { setup: ANNOUNCEMENT() })],
    ['400 VALIDATION_FAILED, nothing to change', call('hr', patch(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}`, {}), { setup: ANNOUNCEMENT() })],
    ['403 NOT_YOURS', call('ceo', patch(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}`, { title: 'Mine now' }), { setup: ANNOUNCEMENT() })],
    ['404 NOT_FOUND, no such announcement', call('hr', patch(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(9)}`, { title: 'Gone' }), { setup: ANNOUNCEMENT() })],
    ['409 PIN_LIMIT', call('hr', patch(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}`, { pinned: true }), {
      setup: (w) => { ANNOUNCEMENT()(w); w.tables.hr_ess_announcements.push(...[2, 3, 4].map((n) => W.announcementRow(w.people.hr.employee.id, n, { pinned: true }))); },
    })],
    ...shared('hr', 'patch', `/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}`, { body: { title: 'Holiday again' }, table: 'hr_ess_announcements', seed: ANNOUNCEMENT() }),
  ],
  'DELETE /api/ess/wall/announcements/{id}': [
    ['204, the sender\'s own', call('hr', del(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}`), { setup: ANNOUNCEMENT() })],
    ['400 VALIDATION_FAILED, not an id', call('hr', del('/api/ess/wall/announcements/not-an-id'))],
    ['403 NOT_YOURS', call('faculty', del(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}`), { setup: ANNOUNCEMENT() })],
    ['404 NOT_FOUND, no such announcement', call('hr', del(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(9)}`), { setup: ANNOUNCEMENT() })],
    ...shared('hr', 'delete', `/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}`, { table: 'hr_ess_announcements', seed: ANNOUNCEMENT() }),
  ],
  'POST /api/ess/wall/announcements/{id}/read': [
    ['204, read', call('faculty', post(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}/read`), { setup: ANNOUNCEMENT() })],
    ['400 VALIDATION_FAILED, not an id', call('faculty', post('/api/ess/wall/announcements/not-an-id/read'))],
    ['403 NOT_IN_AUDIENCE', call('hod', post(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}/read`), { setup: ANNOUNCEMENT() })],
    ['404 NOT_FOUND, no such announcement', call('faculty', post(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(9)}/read`), { setup: ANNOUNCEMENT() })],
    ...shared('faculty', 'post', `/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}/read`, { table: 'hr_ess_announcement_reads', seed: ANNOUNCEMENT() }),
  ],
  'POST /api/ess/wall/announcements/{id}/ack': [
    ['200, acknowledged', call('faculty', post(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}/ack`), { setup: ANNOUNCEMENT({ needs_ack: true, closes_on: '2026-11-05' }) })],
    ['400 VALIDATION_FAILED, no acknowledgement asked for', call('faculty', post(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}/ack`), { setup: ANNOUNCEMENT() })],
    ['403 NOT_IN_AUDIENCE', call('hod', post(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}/ack`), { setup: ANNOUNCEMENT({ needs_ack: true, closes_on: '2026-11-05' }) })],
    ['404 NOT_FOUND, no such announcement', call('faculty', post(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(9)}/ack`), { setup: ANNOUNCEMENT({ needs_ack: true, closes_on: '2026-11-05' }) })],
    ['409 ACK_CLOSED', call('faculty', post(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}/ack`), { setup: ANNOUNCEMENT({ needs_ack: true, closes_on: '2026-10-01' }) })],
    ...shared('faculty', 'post', `/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}/ack`, { table: 'hr_ess_announcement_reads', seed: ANNOUNCEMENT({ needs_ack: true, closes_on: '2026-11-05' }) }),
  ],
  'GET /api/ess/wall/announcements/{id}/counts': [
    ['200, the sender\'s counts', call('hr', get(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}/counts`), { setup: ANNOUNCEMENT() })],
    ['400 VALIDATION_FAILED, not an id', call('hr', get('/api/ess/wall/announcements/not-an-id/counts'))],
    ['403 NOT_YOURS, a reader', call('faculty', get(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}/counts`), { setup: ANNOUNCEMENT() })],
    ['404 NOT_FOUND, no such announcement', call('hr', get(`/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(9)}/counts`), { setup: ANNOUNCEMENT() })],
    ...shared('hr', 'get', `/api/ess/wall/announcements/${W.ANNOUNCEMENT_ID(1)}/counts`, { table: 'hr_ess_announcement_audience', seed: (w) => { w.tables.hr_ess_announcements = [W.announcementRow(w.people.hr.employee.id, 1)]; w.tables.hr_ess_announcement_audience = [W.audienceRow(W.ANNOUNCEMENT_ID(1), w.people.faculty.employee.id)]; } }),
  ],
  'GET /api/ess/wall/celebrations': [
    ['200, the cards', call('faculty', get('/api/ess/wall/celebrations'), {
      setup: (w) => {
        w.tables.hr_ess_personal_details = [{ employee_id: w.people.faculty.employee.id, date_of_birth: '1992-10-16', updated_at: W.AT }];
      },
    })],
    ['400 VALIDATION_FAILED, a window it cannot take', call('faculty', get('/api/ess/wall/celebrations?days=365'))],
    ...shared('faculty', 'get', '/api/ess/wall/celebrations', { table: 'hr_ess_personal_details', seed: (w) => { w.tables.hr_ess_personal_details = [{ employee_id: w.people.faculty.employee.id, date_of_birth: '1992-10-16', updated_at: W.AT }]; } }),
  ],
  'POST /api/ess/wall/wishes': [
    ['201, a wish', call('hr', post('/api/ess/wall/wishes', { employee_id: W.uuid('e', 11), occasion: 'birthday', body: 'Many happy returns!' }))],
    ['400 VALIDATION_FAILED, an occasion it does not have', call('hr', post('/api/ess/wall/wishes', { employee_id: W.uuid('e', 11), occasion: 'new_year', body: 'Happy new year!' }))],
    ['404 NOT_FOUND, nobody to wish', call('hr', post('/api/ess/wall/wishes', { employee_id: W.uuid('e', 99), occasion: 'birthday', body: 'Many happy returns!' }))],
    ['409 ALREADY_WISHED', call('hr', post('/api/ess/wall/wishes', { employee_id: W.uuid('e', 11), occasion: 'birthday', body: 'And again!' }), {
      setup: (w) => {
        w.tables.hr_ess_wall_wishes = [{
          id: W.uuid('a6', 1), post_id: W.POST_ID(1), about_id: w.people.faculty.employee.id,
          wisher_id: w.people.hr.employee.id, occasion: 'birthday', year: 2026, created_at: W.AT,
        }];
      },
    })],
    ...shared('hr', 'post', '/api/ess/wall/wishes', { body: { employee_id: W.uuid('e', 11), occasion: 'birthday', body: 'Many happy returns!' }, table: 'hr_ess_wall_wishes' }),
  ],
  'GET /api/ess/me/celebration-optout': [
    ['200, the switch', call('faculty', get('/api/ess/me/celebration-optout'))],
    ...shared('faculty', 'get', '/api/ess/me/celebration-optout', { table: 'hr_ess_celebration_optouts' }),
  ],
  'PUT /api/ess/me/celebration-optout': [
    ['200, hidden', call('faculty', put('/api/ess/me/celebration-optout', { hidden: true }))],
    ['400 VALIDATION_FAILED, not a boolean', call('faculty', put('/api/ess/me/celebration-optout', { hidden: 'yes' }))],
    ...shared('faculty', 'put', '/api/ess/me/celebration-optout', { body: { hidden: true }, table: 'hr_ess_celebration_optouts' }),
  ],
  'POST /api/ess/wall/posts/{id}/reports': [
    ['201, reported', call('hod', post(`/api/ess/wall/posts/${W.POST_ID(1)}/reports`, { reason: 'This is not for the wall.' }), { setup: (w) => { w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)]; } })],
    ['400 VALIDATION_FAILED, no reason', call('hod', post(`/api/ess/wall/posts/${W.POST_ID(1)}/reports`, { reason: 'hm' }), { setup: (w) => { w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)]; } })],
    ['404 NOT_FOUND, no such post', call('hod', post(`/api/ess/wall/posts/${W.POST_ID(9)}/reports`, { reason: 'Not for the wall.' }))],
    ['409 ALREADY_REPORTED', call('hod', post(`/api/ess/wall/posts/${W.POST_ID(1)}/reports`, { reason: 'Again.' }), { setup: REPORT() })],
    ...shared('hod', 'post', `/api/ess/wall/posts/${W.POST_ID(1)}/reports`, { body: { reason: 'Not for the wall.' }, table: 'hr_ess_wall_reports', seed: (w) => { w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)]; } }),
  ],
  'POST /api/ess/wall/comments/{id}/reports': [
    ['201, reported', call('faculty', post(`/api/ess/wall/comments/${W.COMMENT_ID(1)}/reports`, { reason: 'This is rude.' }), {
      setup: (w) => {
        w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)];
        w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1)];
      },
    })],
    ['400 VALIDATION_FAILED, no reason', call('faculty', post(`/api/ess/wall/comments/${W.COMMENT_ID(1)}/reports`, { reason: 'hm' }), {
      setup: (w) => {
        w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)];
        w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1)];
      },
    })],
    ['404 NOT_FOUND, no such comment', call('faculty', post(`/api/ess/wall/comments/${W.COMMENT_ID(9)}/reports`, { reason: 'Rude.' }))],
    ['409 ALREADY_REPORTED', call('faculty', post(`/api/ess/wall/comments/${W.COMMENT_ID(1)}/reports`, { reason: 'Still rude.' }), {
      setup: (w) => {
        w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)];
        w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1)];
        w.tables.hr_ess_wall_reports = [W.reportRow(w.people.faculty.employee.id, 1, { comment_id: W.COMMENT_ID(1) })];
      },
    })],
    ...shared('faculty', 'post', `/api/ess/wall/comments/${W.COMMENT_ID(1)}/reports`, { body: { reason: 'Rude.' }, table: 'hr_ess_wall_reports', seed: (w) => { w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)]; w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1)]; } }),
  ],
  'GET /api/ess/wall/hr/reports': [
    ['200, the queue', call('hr', get('/api/ess/wall/hr/reports'), { setup: REPORT() })],
    ['400 VALIDATION_FAILED, a status it does not take', call('hr', get('/api/ess/wall/hr/reports?status=maybe'), { setup: REPORT() })],
    ['403 MODERATE_DENIED, a faculty member', call('faculty', get('/api/ess/wall/hr/reports'))],
    ...shared('hr', 'get', '/api/ess/wall/hr/reports', { table: 'hr_ess_wall_reports', seed: REPORT() }),
  ],
  'POST /api/ess/wall/hr/reports/{id}/resolve': [
    ['200, kept', call('hr', post(`/api/ess/wall/hr/reports/${W.REPORT_ID(1)}/resolve`, { status: 'kept', note: 'Nothing wrong with it.' }), { setup: REPORT() })],
    ['400 VALIDATION_FAILED, a status it does not take', call('hr', post(`/api/ess/wall/hr/reports/${W.REPORT_ID(1)}/resolve`, { status: 'burned' }), { setup: REPORT() })],
    ['403 MODERATE_DENIED, a faculty member', call('faculty', post(`/api/ess/wall/hr/reports/${W.REPORT_ID(1)}/resolve`, { status: 'kept' }), { setup: REPORT() })],
    ['404 NOT_FOUND, already answered', call('hr', post(`/api/ess/wall/hr/reports/${W.REPORT_ID(1)}/resolve`, { status: 'hidden' }), { setup: REPORT({ status: 'kept', resolved_by_name: 'Test HR Manager', resolved_at: W.AT }) })],
    ...shared('hr', 'post', `/api/ess/wall/hr/reports/${W.REPORT_ID(1)}/resolve`, { body: { status: 'kept' }, table: 'hr_ess_wall_reports', seed: REPORT() }),
  ],
  'GET /api/ess/wall/hr/moderation-log': [
    ['200, the trail', call('hr', get('/api/ess/wall/hr/moderation-log'), {
      setup: (w) => {
        w.tables.hr_ess_audit = [{ id: W.uuid('a7', 1), at: W.AT, actor_name: 'Test HR Manager', action: 'wall.post.hidden', target_employee_id: w.people.faculty.employee.id, details: { post_id: W.POST_ID(1), reason: 'Not for the wall' } }];
      },
    })],
    ['403 MODERATE_DENIED, a faculty member', call('faculty', get('/api/ess/wall/hr/moderation-log'))],
    ...shared('hr', 'get', '/api/ess/wall/hr/moderation-log', { table: 'hr_ess_audit' }),
  ],
  'POST /api/ess/wall/posts/{id}/hide': [
    ['200, hidden', call('hr', post(`/api/ess/wall/posts/${W.POST_ID(1)}/hide`, { reason: 'Names a student.' }), { setup: (w) => { w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)]; } })],
    ['400 VALIDATION_FAILED, no reason', call('hr', post(`/api/ess/wall/posts/${W.POST_ID(1)}/hide`, { reason: 'no' }), { setup: (w) => { w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)]; } })],
    ['403 MODERATE_DENIED, a faculty member', call('faculty', post(`/api/ess/wall/posts/${W.POST_ID(1)}/hide`, { reason: 'Not for the wall.' }), { setup: (w) => { w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)]; } })],
    ['404 NOT_FOUND, no such post', call('hr', post(`/api/ess/wall/posts/${W.POST_ID(9)}/hide`, { reason: 'Not for the wall.' }))],
    ['409 ALREADY_HIDDEN', call('hr', post(`/api/ess/wall/posts/${W.POST_ID(1)}/hide`, { reason: 'Again.' }), { setup: HIDDEN_POST })],
    ...shared('hr', 'post', `/api/ess/wall/posts/${W.POST_ID(1)}/hide`, { body: { reason: 'Not for the wall.' }, table: 'hr_ess_wall_posts', seed: (w) => { w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)]; } }),
  ],
  'DELETE /api/ess/wall/posts/{id}/hide': [
    ['200, restored', call('hr', del(`/api/ess/wall/posts/${W.POST_ID(1)}/hide`), { setup: HIDDEN_POST })],
    ['400 VALIDATION_FAILED, not an id', call('hr', del('/api/ess/wall/posts/not-an-id/hide'))],
    ['403 MODERATE_DENIED, a faculty member', call('faculty', del(`/api/ess/wall/posts/${W.POST_ID(1)}/hide`), { setup: HIDDEN_POST })],
    ['404 NOT_FOUND, no such post', call('hr', del(`/api/ess/wall/posts/${W.POST_ID(9)}/hide`))],
    ['409 NOT_HIDDEN', call('hr', del(`/api/ess/wall/posts/${W.POST_ID(1)}/hide`), { setup: (w) => { w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)]; } })],
    ...shared('hr', 'delete', `/api/ess/wall/posts/${W.POST_ID(1)}/hide`, { table: 'hr_ess_wall_posts', seed: HIDDEN_POST }),
  ],
  'POST /api/ess/wall/comments/{id}/hide': [
    ['200, hidden', call('hr', post(`/api/ess/wall/comments/${W.COMMENT_ID(1)}/hide`, { reason: 'Rude.' }), {
      setup: (w) => {
        w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)];
        w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1)];
      },
    })],
    ['400 VALIDATION_FAILED, no reason', call('hr', post(`/api/ess/wall/comments/${W.COMMENT_ID(1)}/hide`, { reason: 'no' }), {
      setup: (w) => {
        w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)];
        w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1)];
      },
    })],
    ['403 MODERATE_DENIED, a faculty member', call('faculty', post(`/api/ess/wall/comments/${W.COMMENT_ID(1)}/hide`, { reason: 'Rude.' }), {
      setup: (w) => {
        w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)];
        w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1)];
      },
    })],
    ['404 NOT_FOUND, no such comment', call('hr', post(`/api/ess/wall/comments/${W.COMMENT_ID(9)}/hide`, { reason: 'Rude.' }))],
    ['409 ALREADY_HIDDEN', call('hr', post(`/api/ess/wall/comments/${W.COMMENT_ID(1)}/hide`, { reason: 'Again.' }), { setup: HIDDEN_COMMENT })],
    ...shared('hr', 'post', `/api/ess/wall/comments/${W.COMMENT_ID(1)}/hide`, { body: { reason: 'Rude.' }, table: 'hr_ess_wall_comments', seed: (w) => { w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)]; w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1)]; } }),
  ],
  'DELETE /api/ess/wall/comments/{id}/hide': [
    ['200, restored', call('hr', del(`/api/ess/wall/comments/${W.COMMENT_ID(1)}/hide`), { setup: HIDDEN_COMMENT })],
    ['400 VALIDATION_FAILED, not an id', call('hr', del('/api/ess/wall/comments/not-an-id/hide'))],
    ['403 MODERATE_DENIED, a faculty member', call('faculty', del(`/api/ess/wall/comments/${W.COMMENT_ID(1)}/hide`), { setup: HIDDEN_COMMENT })],
    ['404 NOT_FOUND, no such comment', call('hr', del(`/api/ess/wall/comments/${W.COMMENT_ID(9)}/hide`))],
    ['409 NOT_HIDDEN', call('hr', del(`/api/ess/wall/comments/${W.COMMENT_ID(1)}/hide`), {
      setup: (w) => {
        w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)];
        w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1)];
      },
    })],
    ...shared('hr', 'delete', `/api/ess/wall/comments/${W.COMMENT_ID(1)}/hide`, { table: 'hr_ess_wall_comments', seed: HIDDEN_COMMENT }),
  ],
};

module.exports = { WAVE_6B, ANNOUNCEMENT, REPORT, HIDDEN_POST, HIDDEN_COMMENT, mk };
