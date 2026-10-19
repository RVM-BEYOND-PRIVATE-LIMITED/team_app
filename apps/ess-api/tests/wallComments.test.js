const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');
const { NOW } = require('./helpers/constants');
const W = require('./helpers/wallFixtures');

/** Tasks F2: comments with one level of replies, the six reactions, and who reacted. */

const POSTS = '/api/ess/wall/posts';
const COMMENTS = '/api/ess/wall/comments';

const comment = (app, token, id, body) => request(app).post(`${POSTS}/${id}/comments`).set(bearer(token)).send(body);
const editComment = (app, token, id, body) => request(app).patch(`${COMMENTS}/${id}`).set(bearer(token)).send(body);
const removeComment = (app, token, id) => request(app).delete(`${COMMENTS}/${id}`).set(bearer(token));
const reactPost = (app, token, id, body) => request(app).put(`${POSTS}/${id}/reaction`).set(bearer(token)).send(body);
const unreactPost = (app, token, id) => request(app).delete(`${POSTS}/${id}/reaction`).set(bearer(token));
const whoPost = (app, token, id, query = '') => request(app).get(`${POSTS}/${id}/reactions${query}`).set(bearer(token));
const reactComment = (app, token, id, body) => request(app).put(`${COMMENTS}/${id}/reaction`).set(bearer(token)).send(body);
const unreactComment = (app, token, id) => request(app).delete(`${COMMENTS}/${id}/reaction`).set(bearer(token));
const whoComment = (app, token, id, query = '') => request(app).get(`${COMMENTS}/${id}/reactions${query}`).set(bearer(token));

const withPost = (change = {}) => (w) => {
  w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1, change)];
};

describe('POST /api/ess/wall/posts/{id}/comments', () => {
  it('adds a comment and moves the post\'s count', async () => {
    const { app, people, db } = buildApp({ setup: withPost() });
    const res = await comment(app, tokens.portal(people.hr), W.POST_ID(1), { body: 'Great work.' });
    expect(res.status).toBe(201);
    expect(res.body.comment).toMatchObject({ post_id: W.POST_ID(1), parent_id: null, body: 'Great work.', mine: true, reply_count: 0, replies: [] });
    expect(res.body.comment.author).toMatchObject({ id: people.hr.employee.id });
    expect(db.tables.hr_ess_wall_posts[0].comment_count).toBe(1);
  });

  it('adds one level of replies and moves the parent\'s count', async () => {
    const { app, people, db } = buildApp({ setup: (w) => {
      withPost()(w);
      w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1)];
    } });
    const res = await comment(app, tokens.portal(people.faculty), W.POST_ID(1), { body: 'Thank you.', parent_id: W.COMMENT_ID(1) });
    expect(res.status).toBe(201);
    expect(res.body.comment.parent_id).toBe(W.COMMENT_ID(1));
    expect(db.tables.hr_ess_wall_comments.find((c) => c.id === W.COMMENT_ID(1)).reply_count).toBe(1);
    // The reply's author hears about it, and nobody hears about their own comment.
    expect(db.tables.hr_ess_notifications[0]).toMatchObject({ category: 'replies', employee_id: people.hr.employee.id });
  });

  it('refuses a reply to a reply, and a reply on another post', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      withPost()(w);
      w.tables.hr_ess_wall_posts.push(W.postRow(w.people.hr.employee.id, 2));
      w.tables.hr_ess_wall_comments = [
        W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1),
        W.commentRow(W.POST_ID(1), w.people.hod.employee.id, 2, { parent_id: W.COMMENT_ID(1) }),
        W.commentRow(W.POST_ID(2), w.people.hod.employee.id, 3),
      ];
    } });
    expectInvalid(
      await comment(app, tokens.portal(people.faculty), W.POST_ID(1), { body: 'A reply to a reply.', parent_id: W.COMMENT_ID(2) }),
      MESSAGES.WALL_REPLY_DEPTH,
    );
    expectInvalid(
      await comment(app, tokens.portal(people.faculty), W.POST_ID(1), { body: 'Wrong post.', parent_id: W.COMMENT_ID(3) }),
      MESSAGES.WALL_REPLY_OTHER_POST,
    );
  });

  it('refuses an empty body, a body over 1,000 characters, a bad parent id and a field it does not take', async () => {
    const { app, people } = buildApp({ setup: withPost() });
    const token = tokens.portal(people.faculty);
    expectInvalid(await comment(app, token, W.POST_ID(1), { body: '  ' }), MESSAGES.WALL_COMMENT_BODY);
    expectInvalid(await comment(app, token, W.POST_ID(1), { body: 'x'.repeat(1001) }), MESSAGES.WALL_COMMENT_BODY);
    expectInvalid(await comment(app, token, W.POST_ID(1), { body: 'Fine.', parent_id: 'nope' }), MESSAGES.INVALID_ID);
    expectInvalid(await comment(app, token, W.POST_ID(1), { body: 'Fine.', mood: 'happy' }), MESSAGES.UNKNOWN_FIELD);
  });

  it('answers 404 for a post that is not there, is deleted, or is hidden from me', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [
        W.postRow(w.people.faculty.employee.id, 1, { deleted_at: W.AT }),
        W.postRow(w.people.faculty.employee.id, 2, { hidden_at: W.AT, hidden_by_name: 'Test HR Manager', hide_reason: 'Not for the wall' }),
      ];
    } });
    const token = tokens.portal(people.hod);
    expectRefusal(await comment(app, token, W.POST_ID(1), { body: 'Hello.' }), 404, 'NOT_FOUND');
    expectRefusal(await comment(app, token, W.POST_ID(2), { body: 'Hello.' }), 404, 'NOT_FOUND');
    expectRefusal(await comment(app, token, W.POST_ID(9), { body: 'Hello.' }), 404, 'NOT_FOUND');
    // Its author may still comment on their own hidden post.
    const own = await comment(app, tokens.portal(people.faculty), W.POST_ID(2), { body: 'About my own post.' });
    expect(own.status).toBe(201);
  });

  it('answers 503 MODULE_NOT_INSTALLED before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp({ setup: withPost() });
    db.dropTable('hr_ess_wall_comments');
    expectRefusal(await comment(app, tokens.portal(people.faculty), W.POST_ID(1), { body: 'Hi.' }), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('PATCH and DELETE /api/ess/wall/comments/{id}', () => {
  it('edits my own comment inside the window and marks it edited', async () => {
    const { app, people, db } = buildApp({ setup: (w) => {
      withPost()(w);
      w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.faculty.employee.id, 1, { created_at: '2026-10-16T06:20:00+00:00' })];
    } });
    const res = await editComment(app, tokens.portal(people.faculty), W.COMMENT_ID(1), { body: 'Reworded.' });
    expect(res.status).toBe(200);
    expect(res.body.comment.body).toBe('Reworded.');
    expect(res.body.comment.edited).toBe(true);
    expect(db.tables.hr_ess_wall_comments[0].edited_at).toBe(NOW.toISOString());
  });

  it('refuses an edit after 15 minutes and somebody else\'s comment, and a delete that is not mine', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      withPost()(w);
      w.tables.hr_ess_wall_comments = [
        W.commentRow(W.POST_ID(1), w.people.faculty.employee.id, 1, { created_at: '2026-10-16T06:00:00+00:00' }),
        W.commentRow(W.POST_ID(1), w.people.hod.employee.id, 2),
      ];
    } });
    const faculty = tokens.portal(people.faculty);
    expectRefusal(await editComment(app, faculty, W.COMMENT_ID(1), { body: 'Later.' }), 409, 'EDIT_WINDOW_CLOSED');
    expectRefusal(await editComment(app, faculty, W.COMMENT_ID(2), { body: 'Not mine.' }), 403, 'NOT_YOURS');
    expectRefusal(await removeComment(app, faculty, W.COMMENT_ID(2)), 403, 'NOT_YOURS');
    expectRefusal(await editComment(app, faculty, W.COMMENT_ID(9), { body: 'Gone.' }), 404, 'NOT_FOUND');
  });

  it('deletes my own comment, blanks its row, and moves both counts', async () => {
    const { app, people, db } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1, { comment_count: 1 })];
      w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.faculty.employee.id, 1)];
    } });
    const res = await removeComment(app, tokens.portal(people.faculty), W.COMMENT_ID(1));
    expect(res.status).toBe(204);
    expect(db.tables.hr_ess_wall_comments[0].deleted_at).toBe(NOW.toISOString());
    expect(db.tables.hr_ess_wall_comments[0].body).toBe('(deleted)');
    expect(db.tables.hr_ess_wall_posts[0].comment_count).toBe(0);
    expect(db.tables.hr_ess_audit.map((a) => a.action)).toEqual(['wall.comment.deleted']);
  });

  it('answers 503 for both before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp({ setup: (w) => {
      withPost()(w);
      w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.faculty.employee.id, 1)];
    } });
    db.dropTable('hr_ess_wall_comments');
    expectRefusal(await editComment(app, tokens.portal(people.faculty), W.COMMENT_ID(1), { body: 'Hi.' }), 503, 'MODULE_NOT_INSTALLED');
    expectRefusal(await removeComment(app, tokens.portal(people.faculty), W.COMMENT_ID(1)), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('the six reactions', () => {
  it('records one reaction per person per post, and changes it on a second tap of another emoji', async () => {
    const { app, people, db } = buildApp({ setup: withPost() });
    const token = tokens.portal(people.hr);
    const first = await reactPost(app, token, W.POST_ID(1), { reaction: 'clap' });
    expect(first.status).toBe(200);
    expect(first.body).toEqual({ counts: { clap: 1 }, total: 1, my_reaction: 'clap' });
    const changed = await reactPost(app, token, W.POST_ID(1), { reaction: 'love' });
    expect(changed.body).toEqual({ counts: { love: 1 }, total: 1, my_reaction: 'love' });
    expect(db.tables.hr_ess_wall_reactions).toHaveLength(1);
    expect(db.tables.hr_ess_wall_posts[0].reaction_counts).toEqual({ love: 1 });
  });

  it('counts several people, shows who reacted, and lets one take theirs off', async () => {
    const { app, people, db } = buildApp({ setup: withPost() });
    await reactPost(app, tokens.portal(people.faculty), W.POST_ID(1), { reaction: 'clap' });
    await reactPost(app, tokens.portal(people.hod), W.POST_ID(1), { reaction: 'clap' });
    await reactPost(app, tokens.portal(people.hr), W.POST_ID(1), { reaction: 'curious' });
    const who = await whoPost(app, tokens.portal(people.faculty), W.POST_ID(1));
    expect(who.status).toBe(200);
    expect(who.body.total).toBe(3);
    expect(who.body.reactions).toEqual([
      expect.objectContaining({ reaction: 'clap', count: 2 }),
      expect.objectContaining({ reaction: 'curious', count: 1 }),
    ]);
    expect(who.body.reactions[0].people.map((p) => p.full_name).sort()).toEqual(['Test CAD Faculty', 'Test CAD HOD'].sort());
    const only = await whoPost(app, tokens.portal(people.faculty), W.POST_ID(1), '?reaction=curious');
    expect(only.body.reactions).toHaveLength(1);
    expect(only.body.reactions[0].reaction).toBe('curious');

    const off = await unreactPost(app, tokens.portal(people.hr), W.POST_ID(1));
    expect(off.body).toEqual({ counts: { clap: 2 }, total: 2, my_reaction: null });
    expect(db.tables.hr_ess_wall_reactions).toHaveLength(2);
  });

  it('refuses a reaction it does not have, on a post and on a comment', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      withPost()(w);
      w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1)];
    } });
    const token = tokens.portal(people.faculty);
    expectInvalid(await reactPost(app, token, W.POST_ID(1), { reaction: 'wow' }), MESSAGES.WALL_REACTION);
    expectInvalid(await reactComment(app, token, W.COMMENT_ID(1), { reaction: 'wow' }), MESSAGES.WALL_REACTION);
    expectInvalid(await whoPost(app, token, W.POST_ID(1), '?reaction=wow'), MESSAGES.WALL_REACTION);
  });

  it('reacts to a comment, keeps its own count, and shows who reacted', async () => {
    const { app, people, db } = buildApp({ setup: (w) => {
      withPost()(w);
      w.tables.hr_ess_wall_comments = [W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1)];
    } });
    const res = await reactComment(app, tokens.portal(people.faculty), W.COMMENT_ID(1), { reaction: 'insightful' });
    expect(res.body).toEqual({ counts: { insightful: 1 }, total: 1, my_reaction: 'insightful' });
    expect(db.tables.hr_ess_wall_comments[0].reaction_counts).toEqual({ insightful: 1 });
    const who = await whoComment(app, tokens.portal(people.hr), W.COMMENT_ID(1));
    expect(who.body.reactions[0].people[0].full_name).toBe('Test CAD Faculty');
    const off = await unreactComment(app, tokens.portal(people.faculty), W.COMMENT_ID(1));
    expect(off.body).toEqual({ counts: {}, total: 0, my_reaction: null });
  });

  it('leaves a hidden post out of reach: no reacting to what I cannot see', async () => {
    const { app, people } = buildApp({ setup: withPost({ hidden_at: W.AT, hidden_by_name: 'Test HR Manager', hide_reason: 'Not for the wall' }) });
    const token = tokens.portal(people.hod);
    expectRefusal(await reactPost(app, token, W.POST_ID(1), { reaction: 'like' }), 404, 'NOT_FOUND');
    expectRefusal(await unreactPost(app, token, W.POST_ID(1)), 404, 'NOT_FOUND');
    expectRefusal(await whoPost(app, token, W.POST_ID(1)), 404, 'NOT_FOUND');
    // HR may still moderate it, reactions included.
    const hr = await reactPost(app, tokens.portal(people.hr), W.POST_ID(1), { reaction: 'like' });
    expect(hr.status).toBe(200);
  });

  it('answers 404 for a post or comment that is not there, and 503 before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp({ setup: withPost() });
    const token = tokens.portal(people.faculty);
    expectRefusal(await reactPost(app, token, W.POST_ID(9), { reaction: 'like' }), 404, 'NOT_FOUND');
    expectRefusal(await reactComment(app, token, W.COMMENT_ID(9), { reaction: 'like' }), 404, 'NOT_FOUND');
    expectRefusal(await whoComment(app, token, W.COMMENT_ID(9)), 404, 'NOT_FOUND');
    db.dropTable('hr_ess_wall_reactions');
    expectRefusal(await reactPost(app, token, W.POST_ID(1), { reaction: 'like' }), 503, 'MODULE_NOT_INSTALLED');
  });
});
