const request = require('supertest');
const { buildApp, tokens, bearer } = require('./app');
const W = require('./wallFixtures');

/**
 * Wave 6 (Phase 2A): the Wall's scenario table, one entry per documented status of every route
 * the Wall adds. tests/contract.test.js merges it with the earlier waves: the routes covered must
 * be exactly the routes the app serves, and every documented status must be provoked here.
 *
 * The scenarios are built from the same in-memory app and the same fixtures as the other waves
 * (tests/helpers/app.js buildApp, tests/helpers/wallFixtures.js), so a Wall request here is the
 * real route, the real store and the real contract check.
 */

const as = (people, who) => (who === 'attendance' ? tokens.attendance(people.attendance) : tokens.portal(people[who]));

/** One request in a world built with `options`, after `prepare` has changed it. */
const call = (who, send, { prepare, ...options } = {}) => async () => {
  const world = buildApp(options);
  // `prepare` runs after the app is built, so it sees the fake database: `tables` is
  // db.tables, the copy the routes actually read (the fixtures' shape, for a scenario's own eyes).
  if (prepare) prepare({ ...world, tables: world.db.tables });
  return send(world.app, as(world.people, who), world);
};

const get = (path) => (app, token) => request(app).get(path).set(bearer(token));
const post = (path, body) => (app, token) => request(app).post(path).set(bearer(token)).send(body === undefined ? {} : body);
const put = (path, body) => (app, token) => request(app).put(path).set(bearer(token)).send(body === undefined ? {} : body);
const patch = (path, body) => (app, token) => request(app).patch(path).set(bearer(token)).send(body === undefined ? {} : body);
const del = (path) => (app, token) => request(app).delete(path).set(bearer(token));

const drop = (table) => (w) => w.db.dropTable(table);

/** The wall's rows, as the migrations hold them. */
const WALL = (change = {}) => (w) => {
  w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1, change)];
};
const WALL_COMMENT = (change = {}) => (w) => {
  WALL()(w);
  w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1, change)];
};
const WALL_POLL = (change = {}, locked = false) => (w) => {
  w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1, {
    kind: 'poll', body: 'Where should the team lunch be?', poll_closes_on: '2026-11-01', options_locked_at: locked ? W.AT : null, ...change,
  })];
  w.tables.hr_ess_wall_poll_options = [W.optionRow(W.POST_ID(1), 1, 'Chaat', 0), W.optionRow(W.POST_ID(1), 2, 'Dosa', 1)];
};
const ANNOUNCEMENT = (change = {}) => (w) => {
  w.tables.hr_ess_announcements = [W.announcementRow(w.people.hr.employee.id, 1, change)];
  w.tables.hr_ess_announcement_audience = [W.audienceRow(W.ANNOUNCEMENT_ID(1), w.people.faculty.employee.id)];
  w.tables.hr_ess_announcement_reads = [];
};

/** The four refusals every route shares: no token, a desk login, a rate limit and a 503. */
const shared = (who, method, path, { body, table, seed } = {}) => [
  [`401, no token`, async () => {
    const { app } = buildApp();
    const send = method === 'get' ? request(app).get(path) : method === 'delete' ? request(app).delete(path) : method === 'post' ? request(app).post(path) : method === 'put' ? request(app).put(path) : request(app).patch(path);
    return send.send(body === undefined ? {} : body);
  }],
  [`403 NOT_LINKED, a desk login`, call('desk', (app, token) => {
    const req = method === 'get' ? request(app).get(path) : method === 'delete' ? request(app).delete(path) : method === 'post' ? request(app).post(path) : method === 'put' ? request(app).put(path) : request(app).patch(path);
    return req.set(bearer(token)).send(body === undefined ? {} : body);
  })],
  [`429 RATE_LIMITED`, async () => {
    const world = buildApp({ limits: { perEmployee: { windowMs: 60 * 1000, limit: 1 } } });
    const token = as(world.people, who);
    const send = () => {
      const req = method === 'get' ? request(world.app).get(path) : method === 'delete' ? request(world.app).delete(path) : method === 'post' ? request(world.app).post(path) : method === 'put' ? request(world.app).put(path) : request(world.app).patch(path);
      return req.set(bearer(token)).send(body === undefined ? {} : body);
    };
    await send();
    return send();
  }],
  table
    ? [`503 MODULE_NOT_INSTALLED`, call(who, (app, token) => {
      const req = method === 'get' ? request(app).get(path) : method === 'delete' ? request(app).delete(path) : method === 'post' ? request(app).post(path) : method === 'put' ? request(app).put(path) : request(app).patch(path);
      return req.set(bearer(token)).send(body === undefined ? {} : body);
    }, { prepare: (w) => { if (seed) seed(w); w.db.dropTable(table); } })]
    : [`503 UNAVAILABLE, the database away`, call(who, (app, token) => {
      const req = method === 'get' ? request(app).get(path) : method === 'delete' ? request(app).delete(path) : method === 'post' ? request(app).post(path) : method === 'put' ? request(app).put(path) : request(app).patch(path);
      return req.set(bearer(token)).send(body === undefined ? {} : body);
    }, { prepare: (w) => { w.db.outage = 'error'; } })],
];

/** A Wall 404: the thing is not there at all. */
const missing = (who, send) => call(who, send);

const WAVE_6 = {
  'GET /api/ess/wall/settings': [
    ['200, the rules', call('faculty', get('/api/ess/wall/settings'))],
    ...shared('faculty', 'get', '/api/ess/wall/settings'),
  ],
  'GET /api/ess/wall/posts': [
    ['200, a page', call('faculty', get('/api/ess/wall/posts'), { setup: WALL({ scope: 'org' }) })],
    ['400 VALIDATION_FAILED, a scope it does not take', call('faculty', get('/api/ess/wall/posts?scope=roof'))],
    ...shared('faculty', 'get', '/api/ess/wall/posts', { table: 'hr_ess_wall_posts' }),
  ],
  'POST /api/ess/wall/posts': [
    ['201, a post', call('faculty', post('/api/ess/wall/posts', { body: 'Batch 12 has cleared the CAD module.', scope: 'org' }))],
    ['400 VALIDATION_FAILED, an empty body', call('faculty', post('/api/ess/wall/posts', { body: '   ' }))],
    ...shared('faculty', 'post', '/api/ess/wall/posts', { body: { body: 'Hello.' }, table: 'hr_ess_wall_posts' }),
  ],
  'GET /api/ess/wall/posts/{id}': [
    ['200, a thread', call('faculty', get(`/api/ess/wall/posts/${W.POST_ID(1)}`), { setup: WALL() })],
    ['400 VALIDATION_FAILED, not an id', call('faculty', get('/api/ess/wall/posts/not-an-id'))],
    ['404 NOT_FOUND, no such post', missing('faculty', get(`/api/ess/wall/posts/${W.POST_ID(9)}`), { setup: WALL() })],
    ...shared('faculty', 'get', `/api/ess/wall/posts/${W.POST_ID(1)}`, { table: 'hr_ess_wall_comments', seed: WALL() }),
  ],
  'PATCH /api/ess/wall/posts/{id}': [
    ['200, mine, inside the window', call('faculty', patch(`/api/ess/wall/posts/${W.POST_ID(1)}`, { body: 'Corrected.' }), {
      setup: (w) => { WALL({ created_at: '2026-10-16T06:20:00+00:00' })(w); },
    })],
    ['400 VALIDATION_FAILED, nothing to change', call('faculty', patch(`/api/ess/wall/posts/${W.POST_ID(1)}`, {}), {
      setup: (w) => { WALL({ created_at: '2026-10-16T06:20:00+00:00' })(w); },
    })],
    ['403 NOT_YOURS, somebody else\'s', call('hod', patch(`/api/ess/wall/posts/${W.POST_ID(1)}`, { body: 'Not mine.' }), { setup: WALL() })],
    ['404 NOT_FOUND, no such post', call('faculty', patch(`/api/ess/wall/posts/${W.POST_ID(9)}`, { body: 'Gone.' }), { setup: WALL() })],
    ['409 EDIT_WINDOW_CLOSED', call('faculty', patch(`/api/ess/wall/posts/${W.POST_ID(1)}`, { body: 'Later.' }), {
      setup: (w) => { WALL({ created_at: '2026-10-16T06:00:00+00:00' })(w); },
    })],
    ...shared('faculty', 'patch', `/api/ess/wall/posts/${W.POST_ID(1)}`, { body: { body: 'Hello.' }, table: 'hr_ess_wall_posts' }),
  ],
  'DELETE /api/ess/wall/posts/{id}': [
    ['204, mine', call('faculty', del(`/api/ess/wall/posts/${W.POST_ID(1)}`), { setup: WALL() })],
    ['400 VALIDATION_FAILED, not an id', call('faculty', del('/api/ess/wall/posts/not-an-id'))],
    ['403 NOT_YOURS, somebody else\'s', call('hod', del(`/api/ess/wall/posts/${W.POST_ID(1)}`), { setup: WALL() })],
    ['404 NOT_FOUND, no such post', call('faculty', del(`/api/ess/wall/posts/${W.POST_ID(9)}`), { setup: WALL() })],
    ...shared('faculty', 'delete', `/api/ess/wall/posts/${W.POST_ID(1)}`, { table: 'hr_ess_wall_posts' }),
  ],
  'POST /api/ess/wall/posts/{id}/comments': [
    ['201, a comment', call('hr', post(`/api/ess/wall/posts/${W.POST_ID(1)}/comments`, { body: 'Well done.' }), { setup: WALL() })],
    ['400 VALIDATION_FAILED, an empty comment', call('hr', post(`/api/ess/wall/posts/${W.POST_ID(1)}/comments`, { body: '  ' }), { setup: WALL() })],
    ['404 NOT_FOUND, no such post', call('hr', post(`/api/ess/wall/posts/${W.POST_ID(9)}/comments`, { body: 'Hello.' }), { setup: WALL() })],
    ...shared('hr', 'post', `/api/ess/wall/posts/${W.POST_ID(1)}/comments`, { body: { body: 'Hello.' }, table: 'hr_ess_wall_comments', seed: WALL() }),
  ],
  'PATCH /api/ess/wall/comments/{id}': [
    ['200, mine, inside the window', call('hr', patch(`/api/ess/wall/comments/${W.COMMENT_ID(1)}`, { body: 'Reworded.' }), {
      setup: (w) => { WALL_COMMENT({ created_at: '2026-10-16T06:20:00+00:00' })(w); },
    })],
    ['400 VALIDATION_FAILED, nothing to change', call('hr', patch(`/api/ess/wall/comments/${W.COMMENT_ID(1)}`, {}), {
      setup: (w) => { WALL_COMMENT({ created_at: '2026-10-16T06:20:00+00:00' })(w); },
    })],
    ['403 NOT_YOURS, somebody else\'s', call('faculty', patch(`/api/ess/wall/comments/${W.COMMENT_ID(1)}`, { body: 'Not mine.' }), { setup: WALL_COMMENT() })],
    ['404 NOT_FOUND, no such comment', call('hr', patch(`/api/ess/wall/comments/${W.COMMENT_ID(9)}`, { body: 'Gone.' }), { setup: WALL_COMMENT() })],
    ['409 EDIT_WINDOW_CLOSED', call('hr', patch(`/api/ess/wall/comments/${W.COMMENT_ID(1)}`, { body: 'Later.' }), {
      setup: (w) => { WALL_COMMENT({ created_at: '2026-10-16T06:00:00+00:00' })(w); },
    })],
    ...shared('hr', 'patch', `/api/ess/wall/comments/${W.COMMENT_ID(1)}`, { body: { body: 'Hello.' }, table: 'hr_ess_wall_comments', seed: WALL() }),
  ],
  'DELETE /api/ess/wall/comments/{id}': [
    ['204, mine', call('hr', del(`/api/ess/wall/comments/${W.COMMENT_ID(1)}`), { setup: WALL_COMMENT() })],
    ['400 VALIDATION_FAILED, not an id', call('hr', del('/api/ess/wall/comments/not-an-id'))],
    ['403 NOT_YOURS, somebody else\'s', call('faculty', del(`/api/ess/wall/comments/${W.COMMENT_ID(1)}`), { setup: WALL_COMMENT() })],
    ['404 NOT_FOUND, no such comment', call('hr', del(`/api/ess/wall/comments/${W.COMMENT_ID(9)}`), { setup: WALL_COMMENT() })],
    ...shared('hr', 'delete', `/api/ess/wall/comments/${W.COMMENT_ID(1)}`, { table: 'hr_ess_wall_comments', seed: WALL() }),
  ],
  'PUT /api/ess/wall/posts/{id}/reaction': [
    ['200, clap', call('hr', put(`/api/ess/wall/posts/${W.POST_ID(1)}/reaction`, { reaction: 'clap' }), { setup: WALL() })],
    ['400 VALIDATION_FAILED, a reaction it does not have', call('hr', put(`/api/ess/wall/posts/${W.POST_ID(1)}/reaction`, { reaction: 'wow' }), { setup: WALL() })],
    ['404 NOT_FOUND, no such post', call('hr', put(`/api/ess/wall/posts/${W.POST_ID(9)}/reaction`, { reaction: 'clap' }), { setup: WALL() })],
    ...shared('hr', 'put', `/api/ess/wall/posts/${W.POST_ID(1)}/reaction`, { body: { reaction: 'clap' }, table: 'hr_ess_wall_reactions', seed: WALL() }),
  ],
  'DELETE /api/ess/wall/posts/{id}/reaction': [
    ['200, taken off', call('hr', del(`/api/ess/wall/posts/${W.POST_ID(1)}/reaction`), {
      setup: (w) => {
        WALL()(w);
        w.tables.hr_ess_wall_reactions = [W.reactionRow(w.people.hr.employee.id, 'clap', { post_id: W.POST_ID(1) })];
      },
    })],
    ['400 VALIDATION_FAILED, not an id', call('hr', del('/api/ess/wall/posts/not-an-id/reaction'))],
    ['404 NOT_FOUND, no such post', call('hr', del(`/api/ess/wall/posts/${W.POST_ID(9)}/reaction`), { setup: WALL() })],
    ...shared('hr', 'delete', `/api/ess/wall/posts/${W.POST_ID(1)}/reaction`, { table: 'hr_ess_wall_reactions', seed: WALL() }),
  ],
  'GET /api/ess/wall/posts/{id}/reactions': [
    ['200, who reacted', call('hr', get(`/api/ess/wall/posts/${W.POST_ID(1)}/reactions`), {
      setup: (w) => {
        WALL()(w);
        w.tables.hr_ess_wall_reactions = [W.reactionRow(w.people.hr.employee.id, 'clap', { post_id: W.POST_ID(1) })];
      },
    })],
    ['400 VALIDATION_FAILED, a reaction it does not have', call('hr', get(`/api/ess/wall/posts/${W.POST_ID(1)}/reactions?reaction=wow`), { setup: WALL() })],
    ['404 NOT_FOUND, no such post', call('hr', get(`/api/ess/wall/posts/${W.POST_ID(9)}/reactions`), { setup: WALL() })],
    ...shared('hr', 'get', `/api/ess/wall/posts/${W.POST_ID(1)}/reactions`, { table: 'hr_ess_wall_reactions', seed: WALL() }),
  ],
  'PUT /api/ess/wall/comments/{id}/reaction': [
    ['200, insightful', call('faculty', put(`/api/ess/wall/comments/${W.COMMENT_ID(1)}/reaction`, { reaction: 'insightful' }), { setup: WALL_COMMENT() })],
    ['400 VALIDATION_FAILED, a reaction it does not have', call('faculty', put(`/api/ess/wall/comments/${W.COMMENT_ID(1)}/reaction`, { reaction: 'wow' }), { setup: WALL_COMMENT() })],
    ['404 NOT_FOUND, no such comment', call('faculty', put(`/api/ess/wall/comments/${W.COMMENT_ID(9)}/reaction`, { reaction: 'like' }), { setup: WALL_COMMENT() })],
    ...shared('faculty', 'put', `/api/ess/wall/comments/${W.COMMENT_ID(1)}/reaction`, { body: { reaction: 'like' }, table: 'hr_ess_wall_reactions', seed: WALL_COMMENT() }),
  ],
  'DELETE /api/ess/wall/comments/{id}/reaction': [
    ['200, taken off', call('faculty', del(`/api/ess/wall/comments/${W.COMMENT_ID(1)}/reaction`), {
      setup: (w) => {
        WALL_COMMENT()(w);
        w.tables.hr_ess_wall_reactions = [W.reactionRow(w.people.faculty.employee.id, 'like', { comment_id: W.COMMENT_ID(1) })];
      },
    })],
    ['400 VALIDATION_FAILED, not an id', call('faculty', del('/api/ess/wall/comments/not-an-id/reaction'))],
    ['404 NOT_FOUND, no such comment', call('faculty', del(`/api/ess/wall/comments/${W.COMMENT_ID(9)}/reaction`), { setup: WALL_COMMENT() })],
    ...shared('faculty', 'delete', `/api/ess/wall/comments/${W.COMMENT_ID(1)}/reaction`, { table: 'hr_ess_wall_reactions', seed: WALL_COMMENT() }),
  ],
  'GET /api/ess/wall/comments/{id}/reactions': [
    ['200, who reacted', call('faculty', get(`/api/ess/wall/comments/${W.COMMENT_ID(1)}/reactions`), {
      setup: (w) => {
        WALL_COMMENT()(w);
        w.tables.hr_ess_wall_reactions = [W.reactionRow(w.people.hr.employee.id, 'like', { comment_id: W.COMMENT_ID(1) })];
      },
    })],
    ['400 VALIDATION_FAILED, a reaction it does not have', call('faculty', get(`/api/ess/wall/comments/${W.COMMENT_ID(1)}/reactions?reaction=wow`), { setup: WALL_COMMENT() })],
    ['404 NOT_FOUND, no such comment', call('faculty', get(`/api/ess/wall/comments/${W.COMMENT_ID(9)}/reactions`), { setup: WALL_COMMENT() })],
    ...shared('faculty', 'get', `/api/ess/wall/comments/${W.COMMENT_ID(1)}/reactions`, { table: 'hr_ess_wall_reactions', seed: WALL_COMMENT() }),
  ],
  'POST /api/ess/wall/praise': [
    ['201, a badge', call('hr', post('/api/ess/wall/praise', { employee_id: W.uuid('e', 11), badge: 'mentor', reason: 'Always helping the batch.' }))],
    ['400 VALIDATION_FAILED, a badge that is not RVM\'s', call('hr', post('/api/ess/wall/praise', { employee_id: W.uuid('e', 11), badge: 'employee_of_the_month', reason: 'Well done.' }))],
    ['404 NOT_FOUND, nobody to praise', call('hr', post('/api/ess/wall/praise', { employee_id: W.uuid('e', 99), badge: 'mentor', reason: 'Well done.' }))],
    ...shared('hr', 'post', '/api/ess/wall/praise', { body: { employee_id: W.uuid('e', 11), badge: 'mentor', reason: 'Well done.' }, table: 'hr_ess_wall_posts' }),
  ],
  'GET /api/ess/me/praise': [
    ['200, my own', call('faculty', get('/api/ess/me/praise'), {
      setup: (w) => {
        w.tables.hr_ess_wall_posts = [W.postRow(w.people.hr.employee.id, 1, { kind: 'praise', body: 'Always helping.', badge: 'mentor', about_employee_id: w.people.faculty.employee.id })];
      },
    })],
    ['400 VALIDATION_FAILED, an employee_id that is not one', call('faculty', get('/api/ess/me/praise?employee_id=nope'))],
    ...shared('faculty', 'get', '/api/ess/me/praise', { table: 'hr_ess_wall_posts' }),
  ],
  'GET /api/ess/wall/polls/{id}': [
    ['200, a poll', call('faculty', get(`/api/ess/wall/polls/${W.POST_ID(1)}`), { setup: WALL_POLL() })],
    ['400 VALIDATION_FAILED, not an id', call('faculty', get('/api/ess/wall/polls/not-an-id'))],
    ['404 NOT_FOUND, no such poll', call('faculty', get(`/api/ess/wall/polls/${W.POST_ID(9)}`), { setup: WALL_POLL() })],
    ...shared('faculty', 'get', `/api/ess/wall/polls/${W.POST_ID(1)}`, { table: 'hr_ess_wall_poll_options', seed: WALL_POLL() }),
  ],
  'POST /api/ess/wall/polls/{id}/vote': [
    ['200, a choice', call('hr', post(`/api/ess/wall/polls/${W.POST_ID(1)}/vote`, { option_ids: [W.OPTION_ID(1)] }), { setup: WALL_POLL() })],
    ['400 VALIDATION_FAILED, no choice', call('hr', post(`/api/ess/wall/polls/${W.POST_ID(1)}/vote`, { option_ids: [] }), { setup: WALL_POLL() })],
    ['404 NOT_FOUND, no such poll', call('hr', post(`/api/ess/wall/polls/${W.POST_ID(9)}/vote`, { option_ids: [W.OPTION_ID(1)] }), { setup: WALL_POLL() })],
    ['409 POLL_CLOSED', call('hr', post(`/api/ess/wall/polls/${W.POST_ID(1)}/vote`, { option_ids: [W.OPTION_ID(1)] }), { setup: WALL_POLL({ poll_closes_on: '2026-10-15' }) })],
    ...shared('hr', 'post', `/api/ess/wall/polls/${W.POST_ID(1)}/vote`, { body: { option_ids: [W.OPTION_ID(1)] }, table: 'hr_ess_wall_poll_votes', seed: WALL_POLL() }),
  ],
  'DELETE /api/ess/wall/polls/{id}/vote': [
    ['200, taken back', call('hr', del(`/api/ess/wall/polls/${W.POST_ID(1)}/vote`), { setup: WALL_POLL() })],
    ['400 VALIDATION_FAILED, not an id', call('hr', del('/api/ess/wall/polls/not-an-id/vote'))],
    ['404 NOT_FOUND, no such poll', call('hr', del(`/api/ess/wall/polls/${W.POST_ID(9)}/vote`), { setup: WALL_POLL() })],
    ['409 POLL_CLOSED', call('hr', del(`/api/ess/wall/polls/${W.POST_ID(1)}/vote`), { setup: WALL_POLL({ poll_closes_on: '2026-10-15' }) })],
    ...shared('hr', 'delete', `/api/ess/wall/polls/${W.POST_ID(1)}/vote`, { table: 'hr_ess_wall_poll_votes', seed: WALL_POLL() }),
  ],
  'POST /api/ess/wall/polls/{id}/options': [
    ['201, one more', call('faculty', post(`/api/ess/wall/polls/${W.POST_ID(1)}/options`, { label: 'Idli' }), { setup: WALL_POLL() })],
    ['400 VALIDATION_FAILED, an empty label', call('faculty', post(`/api/ess/wall/polls/${W.POST_ID(1)}/options`, { label: '  ' }), { setup: WALL_POLL() })],
    ['403 NOT_YOURS, somebody else\'s poll', call('hr', post(`/api/ess/wall/polls/${W.POST_ID(1)}/options`, { label: 'Idli' }), { setup: WALL_POLL() })],
    ['404 NOT_FOUND, no such poll', call('faculty', post(`/api/ess/wall/polls/${W.POST_ID(9)}/options`, { label: 'Idli' }), { setup: WALL_POLL() })],
    ['409 POLL_OPTIONS_LOCKED', call('faculty', post(`/api/ess/wall/polls/${W.POST_ID(1)}/options`, { label: 'Idli' }), { setup: WALL_POLL({}, true) })],
    ...shared('faculty', 'post', `/api/ess/wall/polls/${W.POST_ID(1)}/options`, { body: { label: 'Idli' }, table: 'hr_ess_wall_poll_options', seed: WALL_POLL() }),
  ],
  'POST /api/ess/wall/polls/{id}/close': [
    ['200, closed', call('faculty', post(`/api/ess/wall/polls/${W.POST_ID(1)}/close`), { setup: WALL_POLL() })],
    ['400 VALIDATION_FAILED, not an id', call('faculty', post('/api/ess/wall/polls/not-an-id/close'))],
    ['403 NOT_YOURS, somebody else\'s poll', call('hr', post(`/api/ess/wall/polls/${W.POST_ID(1)}/close`), { setup: WALL_POLL() })],
    ['404 NOT_FOUND, no such poll', call('faculty', post(`/api/ess/wall/polls/${W.POST_ID(9)}/close`), { setup: WALL_POLL() })],
    ...shared('faculty', 'post', `/api/ess/wall/polls/${W.POST_ID(1)}/close`, { table: 'hr_ess_wall_poll_options', seed: WALL_POLL() }),
  ],
};

module.exports = { WAVE_6, WALL, WALL_COMMENT, WALL_POLL, ANNOUNCEMENT, call, get, post, put, patch, del, drop, as, missing, shared };
