const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');
const { NOW } = require('./helpers/constants');
const W = require('./helpers/wallFixtures');

/** Task F7: reports, HR's queue, hiding with a reason, and the moderation trail. */

const POSTS = '/api/ess/wall/posts';
const COMMENTS = '/api/ess/wall/comments';
const HR = '/api/ess/wall/hr';

const reportPost = (app, token, id, body) => request(app).post(`${POSTS}/${id}/reports`).set(bearer(token)).send(body);
const reportComment = (app, token, id, body) => request(app).post(`${COMMENTS}/${id}/reports`).set(bearer(token)).send(body);
const queue = (app, token, query = '') => request(app).get(`${HR}/reports${query}`).set(bearer(token));
const resolve = (app, token, id, body) => request(app).post(`${HR}/reports/${id}/resolve`).set(bearer(token)).send(body);
const hidePost = (app, token, id, body) => request(app).post(`${POSTS}/${id}/hide`).set(bearer(token)).send(body);
const restorePost = (app, token, id) => request(app).delete(`${POSTS}/${id}/hide`).set(bearer(token));
const hideComment = (app, token, id, body) => request(app).post(`${COMMENTS}/${id}/hide`).set(bearer(token)).send(body);
const restoreComment = (app, token, id) => request(app).delete(`${COMMENTS}/${id}/hide`).set(bearer(token));
const log = (app, token) => request(app).get(`${HR}/moderation-log`).set(bearer(token));

const withPost = (change = {}) => (w) => {
  w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1, change)];
};
const withComment = (change = {}) => (w) => {
  withPost()(w);
  w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1, change)];
};

describe('reporting', () => {
  it('puts a report on HR\'s queue, with the reporter and the thing reported', async () => {
    const { app, people, db } = buildApp({ setup: withPost() });
    const res = await reportPost(app, tokens.portal(people.hod), W.POST_ID(1), { reason: 'This is not for the wall.', detail: 'It names a student.' });
    expect(res.status).toBe(201);
    expect(res.body.report).toEqual({ post_id: W.POST_ID(1), status: 'open' });
    expect(db.tables.hr_ess_wall_reports[0]).toMatchObject({ reporter_id: people.hod.employee.id, post_id: W.POST_ID(1), status: 'open' });
    const hr = await queue(app, tokens.portal(people.hr));
    expect(hr.body.reports[0]).toMatchObject({
      target: 'post', post_id: W.POST_ID(1), reporter: { full_name: 'Test CAD HOD' },
      reason: 'This is not for the wall.', detail: 'It names a student.', status: 'open',
    });
    expect(hr.body.reports[0].target_preview).toBe('A note for the whole team.');
  });

  it('reports a comment too, and refuses a second report of the same thing', async () => {
    const { app, people, db } = buildApp({ setup: withComment() });
    const token = tokens.portal(people.faculty);
    expect((await reportComment(app, token, W.COMMENT_ID(1), { reason: 'Rude.' })).status).toBe(201);
    expectRefusal(await reportComment(app, token, W.COMMENT_ID(1), { reason: 'Still rude.' }), 409, 'ALREADY_REPORTED');
    expect(db.tables.hr_ess_wall_reports).toHaveLength(1);
    // Another person may still report the same thing, and the queue says which it is.
    expect((await reportComment(app, tokens.portal(people.hod), W.COMMENT_ID(1), { reason: 'Agreed.' })).status).toBe(201);
    const hr = await queue(app, tokens.portal(people.hr));
    expect(hr.body.reports).toHaveLength(2);
    expect(hr.body.reports[0]).toMatchObject({ target: 'comment', comment_id: W.COMMENT_ID(1) });
  });

  it('refuses a report with no reason, a reason over 280 characters, a long detail, and a thing that is not there', async () => {
    const { app, people } = buildApp({ setup: withPost() });
    const token = tokens.portal(people.hod);
    expectInvalid(await reportPost(app, token, W.POST_ID(1), { reason: 'hm' }), MESSAGES.WALL_REPORT_REASON);
    expectInvalid(await reportPost(app, token, W.POST_ID(1), { reason: 'x'.repeat(281) }), MESSAGES.WALL_REPORT_REASON);
    expectInvalid(await reportPost(app, token, W.POST_ID(1), { reason: 'Fine.', detail: 'x'.repeat(501) }), MESSAGES.WALL_REPORT_DETAIL);
    expectRefusal(await reportPost(app, token, W.POST_ID(9), { reason: 'Gone.' }), 404, 'NOT_FOUND');
    expectRefusal(await reportComment(app, token, W.COMMENT_ID(9), { reason: 'Gone.' }), 404, 'NOT_FOUND');
  });

  it('answers 503 MODULE_NOT_INSTALLED before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp({ setup: withPost() });
    db.dropTable('hr_ess_wall_reports');
    expectRefusal(await reportPost(app, tokens.portal(people.hod), W.POST_ID(1), { reason: 'Not for the wall.' }), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('HR\'s queue', () => {
  it('shows what is open by default, and any status with ?status=all', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      withPost()(w);
      w.tables.hr_ess_wall_reports = [
        W.reportRow(w.people.hod.employee.id, 1, { post_id: W.POST_ID(1), status: 'open' }),
        W.reportRow(w.people.admin.employee.id, 2, { post_id: W.POST_ID(1), status: 'kept', resolved_by_name: 'Test HR Manager', resolved_at: W.AT }),
      ];
    } });
    const open = await queue(app, tokens.portal(people.hr));
    expect(open.body.reports.map((r) => r.status)).toEqual(['open']);
    const all = await queue(app, tokens.portal(people.hr), '?status=all');
    expect(all.body.reports.map((r) => r.status).sort()).toEqual(['kept', 'open']);
    expectInvalid(await queue(app, tokens.portal(people.hr), '?status=maybe'), MESSAGES.WALL_MODERATION_QUEUE);
  });

  it('is HR\'s alone: the CEO reads nothing there', async () => {
    const { app, people } = buildApp({ setup: withPost() });
    expectRefusal(await queue(app, tokens.portal(people.ceo)), 403, 'MODERATE_DENIED');
    expectRefusal(await queue(app, tokens.portal(people.super_admin)), 403, 'MODERATE_DENIED');
    expectRefusal(await queue(app, tokens.attendance(people.attendance)), 403, 'MODERATE_DENIED');
    expectRefusal(await queue(app, tokens.portal(people.faculty)), 403, 'MODERATE_DENIED');
  });

  it('answers a report once, and answers 404 for one already answered', async () => {
    const { app, people, db } = buildApp({ setup: (w) => {
      withPost()(w);
      w.tables.hr_ess_wall_reports = [W.reportRow(w.people.hod.employee.id, 1, { post_id: W.POST_ID(1) })];
    } });
    const res = await resolve(app, tokens.portal(people.hr), W.REPORT_ID(1), { status: 'kept', note: 'Nothing wrong with it.' });
    expect(res.status).toBe(200);
    expect(res.body.report).toMatchObject({ status: 'kept', resolved_by_name: 'Test HR Manager', resolution_note: 'Nothing wrong with it.' });
    expect(db.tables.hr_ess_wall_reports[0].resolved_at).toBe(NOW.toISOString());
    expectRefusal(await resolve(app, tokens.portal(people.hr), W.REPORT_ID(1), { status: 'hidden' }), 404, 'NOT_FOUND');
    expectInvalid(await resolve(app, tokens.portal(people.hr), W.REPORT_ID(2), { status: 'burned' }), MESSAGES.WALL_MODERATION_QUEUE);
  });

  it('answers 503 before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp({ setup: withPost() });
    db.dropTable('hr_ess_wall_reports');
    expectRefusal(await queue(app, tokens.portal(people.hr)), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('hiding', () => {
  it('hides a post with a reason, takes it off the feed, and records it in the trail', async () => {
    const { app, people, db } = buildApp({ setup: withPost() });
    const res = await hidePost(app, tokens.portal(people.hr), W.POST_ID(1), { reason: 'Names a student.' });
    expect(res.status).toBe(200);
    expect(res.body.post).toEqual({ id: W.POST_ID(1), hidden: true, hidden_by_name: 'Test HR Manager', hide_reason: 'Names a student.' });
    expect(db.tables.hr_ess_wall_posts[0]).toMatchObject({ hidden_by_name: 'Test HR Manager', hide_reason: 'Names a student.' });
    expect(db.tables.hr_ess_wall_posts[0].hidden_at).toBe(NOW.toISOString());
    const feed = await request(app).get(POSTS).set(bearer(tokens.portal(people.hod)));
    expect(feed.body.posts).toEqual([]);
    const trail = await log(app, tokens.portal(people.hr));
    expect(trail.body.entries[0]).toMatchObject({
      action: 'wall.post.hidden', actor_name: 'Test HR Manager',
      target_employee_id: people.faculty.employee.id, details: { post_id: W.POST_ID(1), reason: 'Names a student.' },
    });
  });

  it('refuses a hide with no reason, too short a reason, and a second hide', async () => {
    const hidden = buildApp({ setup: withPost({ hidden_at: W.AT, hidden_by_name: 'Test HR Manager', hide_reason: 'Not for the wall' }) });
    expectRefusal(await hidePost(hidden.app, tokens.portal(hidden.people.hr), W.POST_ID(1), { reason: 'Again' }), 409, 'ALREADY_HIDDEN');
    const plain = buildApp({ setup: withPost() });
    const token = tokens.portal(plain.people.hr);
    expectInvalid(await hidePost(plain.app, token, W.POST_ID(1), { reason: 'no' }), MESSAGES.WALL_HIDE_REASON);
    expectInvalid(await hidePost(plain.app, token, W.POST_ID(1), { reason: 'x'.repeat(201) }), MESSAGES.WALL_HIDE_REASON);
  });

  it('is HR\'s alone', async () => {
    const { app, people } = buildApp({ setup: withComment() });
    for (const who of ['ceo', 'super_admin', 'hod', 'hr_executive']) {
      expectRefusal(await hidePost(app, tokens.portal(people[who]), W.POST_ID(1), { reason: 'Not for the wall' }), 403, 'MODERATE_DENIED');
      expectRefusal(await hideComment(app, tokens.portal(people[who]), W.COMMENT_ID(1), { reason: 'Not for the wall' }), 403, 'MODERATE_DENIED');
    }
    // The author's own delete is a different route and still theirs.
    expect((await request(app).delete(`${POSTS}/${W.POST_ID(1)}`).set(bearer(tokens.portal(people.faculty)))).status).toBe(204);
  });

  it('hides a comment, takes it out of the post\'s count, and restores it', async () => {
    const { app, people, db } = buildApp({ setup: withComment() });
    const res = await hideComment(app, tokens.portal(people.hr), W.COMMENT_ID(1), { reason: 'Rude.' });
    expect(res.status).toBe(200);
    expect(res.body.comment).toEqual({ id: W.COMMENT_ID(1), hidden: true, hidden_by_name: 'Test HR Manager', hide_reason: 'Rude.' });
    expect(db.tables.hr_ess_wall_posts[0].comment_count).toBe(0);
    const restored = await restoreComment(app, tokens.portal(people.hr), W.COMMENT_ID(1));
    expect(restored.body.comment).toEqual({ id: W.COMMENT_ID(1), hidden: false });
    expect(db.tables.hr_ess_wall_posts[0].comment_count).toBe(1);
    expect(db.tables.hr_ess_wall_comments[0].hidden_at).toBe(null);
    expectRefusal(await restoreComment(app, tokens.portal(people.hr), W.COMMENT_ID(1)), 409, 'NOT_HIDDEN');
  });

  it('restores a post, and refuses restoring one that is not hidden', async () => {
    const { app, people } = buildApp({ setup: withPost({ hidden_at: W.AT, hidden_by_name: 'Test HR Manager', hide_reason: 'Not for the wall' }) });
    expect((await restorePost(app, tokens.portal(people.hr), W.POST_ID(1))).body.post).toEqual({ id: W.POST_ID(1), hidden: false });
    expectRefusal(await restorePost(app, tokens.portal(people.hr), W.POST_ID(1)), 409, 'NOT_HIDDEN');
  });

  it('answers 404 for a thing that is not there or is deleted', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1, { deleted_at: W.AT })];
      w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1, { deleted_at: W.AT })];
    } });
    expectRefusal(await hidePost(app, tokens.portal(people.hr), W.POST_ID(1), { reason: 'Not for the wall' }), 404, 'NOT_FOUND');
    expectRefusal(await hideComment(app, tokens.portal(people.hr), W.COMMENT_ID(1), { reason: 'Not for the wall' }), 404, 'NOT_FOUND');
    expectRefusal(await restorePost(app, tokens.portal(people.hr), W.POST_ID(9)), 404, 'NOT_FOUND');
  });

  it('answers 503 MODULE_NOT_INSTALLED before the migration, for a hide and a restore', async () => {
    quietErrors();
    const { app, people, db } = buildApp({ setup: withPost() });
    db.dropTable('hr_ess_wall_posts');
    expectRefusal(await hidePost(app, tokens.portal(people.hr), W.POST_ID(1), { reason: 'Not for the wall' }), 503, 'MODULE_NOT_INSTALLED');
    expectRefusal(await restorePost(app, tokens.portal(people.hr), W.POST_ID(1)), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('the moderation log', () => {
  it('reads the hides, restores and resolved reports, newest first, and is HR\'s alone', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      withPost()(w);
      w.tables.hr_ess_audit = [
        { id: 'a7000000-0000-4000-8000-000000000001', at: W.AT, actor_name: 'Test HR Manager', action: 'wall.post.hidden', target_employee_id: w.people.faculty.employee.id, details: { post_id: W.POST_ID(1), reason: 'Not for the wall' } },
        { id: 'a7000000-0000-4000-8000-000000000002', at: '2026-10-16T06:00:00+00:00', actor_name: 'Test HR Manager', action: 'wall.report.resolved', target_employee_id: null, details: { report_id: W.REPORT_ID(1), status: 'kept' } },
        { id: 'a7000000-0000-4000-8000-000000000003', at: '2026-10-15T06:00:00+00:00', actor_name: 'Test HR Manager', action: 'devices.reset', target_employee_id: null, details: {} },
      ];
    } });
    const res = await log(app, tokens.portal(people.hr));
    expect(res.body.entries.map((e) => e.action)).toEqual(['wall.report.resolved', 'wall.post.hidden']);
    expectRefusal(await log(app, tokens.portal(people.ceo)), 403, 'MODERATE_DENIED');
    expectRefusal(await log(app, tokens.portal(people.faculty)), 403, 'MODERATE_DENIED');
  });

  it('answers 503 before the audit table is there', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    db.dropTable('hr_ess_audit');
    expectRefusal(await log(app, tokens.portal(people.hr)), 503, 'MODULE_NOT_INSTALLED');
  });
});
