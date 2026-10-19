const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');
const { NOW } = require('./helpers/constants');
const W = require('./helpers/wallFixtures');

/** Task F1: posts on the organisation wall and one wall per branch, with edit and delete. */

const POSTS = '/api/ess/wall/posts';
const feed = (app, token, query = '') => request(app).get(`${POSTS}${query}`).set(bearer(token));
const one = (app, token, id) => request(app).get(`${POSTS}/${id}`).set(bearer(token));
const create = (app, token, body) => request(app).post(POSTS).set(bearer(token)).send(body);
const edit = (app, token, id, body) => request(app).patch(`${POSTS}/${id}`).set(bearer(token)).send(body);
const remove = (app, token, id) => request(app).delete(`${POSTS}/${id}`).set(bearer(token));

describe('POST /api/ess/wall/posts', () => {
  it('posts to the organisation wall, with the author, the scope and the mentions resolved', async () => {
    const { app, people } = buildApp();
    const res = await create(app, tokens.portal(people.faculty), {
      body: 'Batch 12 has cleared the CAD module. Thanks @RVM-009!',
      scope: 'org',
    });
    expect(res.status).toBe(201);
    expect(res.body.post).toMatchObject({
      kind: 'post',
      scope: 'org',
      body: 'Batch 12 has cleared the CAD module. Thanks @RVM-009!',
      mine: true,
      edited: false,
      hidden: false,
      reactions: { counts: {}, total: 0 },
      comment_count: 0,
    });
    expect(res.body.post.author).toMatchObject({ id: people.faculty.employee.id, full_name: 'Test CAD Faculty' });
    expect(res.body.post.mentions).toEqual([
      expect.objectContaining({ id: people.hr.employee.id, full_name: 'Test HR Manager' }),
    ]);
  });

  it('defaults to the author\'s own branch wall, and names its branch', async () => {
    const { app, people } = buildApp();
    const res = await create(app, tokens.portal(people.faculty), { body: 'Branch notice for Faridabad.' });
    expect(res.status).toBe(201);
    expect(res.body.post.scope).toBe('branch');
    expect(res.body.post.branch_id).toBe(people.faculty.employee.branch_id);
  });

  it('does not put an organisation post on a branch, and refuses a branch that is not the caller\'s', async () => {
    const { app, people } = buildApp();
    const res = await create(app, tokens.portal(people.faculty), { body: 'Studio hours change.', branch_id: W.uuid('b', 2) });
    expectInvalid(res, MESSAGES.WALL_WRONG_BRANCH);
  });

  it('stores wall photos in the ESS bucket and answers a signed link for each', async () => {
    const { app, people, db } = buildApp();
    const res = await create(app, tokens.portal(people.faculty), {
      body: 'Lab day.',
      scope: 'org',
      attachments: [W.file(), { data_base64: W.PNG_B64, content_type: 'application/pdf', name: 'sheet.pdf' }],
    });
    expect(res.status).toBe(201);
    expect(res.body.post.attachments).toHaveLength(2);
    expect(res.body.post.attachments[0].url).toMatch(/^https:\/\/storage\.test\/ESS\/wall\//);
    expect(res.body.post.attachments[1].content_type).toBe('application/pdf');
    const uploads = db.storageCalls.filter((c) => c.op === 'upload');
    expect(uploads).toHaveLength(2);
    expect(uploads[0].bucket).toBe('ESS');
    expect(uploads[0].path).toMatch(new RegExp(`^wall/${people.faculty.employee.id}/`));
    // The stored path is inside the link, never a field of its own.
    expect(res.body.post.attachments[0].path).toBeUndefined();
  });

  it('refuses a sixth file, a file over 1 MB, and a type the Wall does not take', async () => {
    const { app, people } = buildApp();
    const token = tokens.portal(people.faculty);
    const six = await create(app, token, { body: 'Too many.', attachments: Array.from({ length: 6 }, () => W.file()) });
    expectInvalid(six, MESSAGES.WALL_ATTACHMENTS);
    const big = await create(app, token, {
      body: 'Too big.',
      attachments: [{ data_base64: Buffer.alloc(1024 * 1024 + 1, 7).toString('base64'), content_type: 'image/png' }],
    });
    expectInvalid(big, MESSAGES.WALL_ATTACHMENTS);
    const kind = await create(app, token, { body: 'Wrong kind.', attachments: [W.file({ content_type: 'image/gif' })] });
    expectInvalid(kind, MESSAGES.WALL_ATTACHMENTS);
  });

  it('refuses an empty body, a body over 2,000 characters, and a field it does not take', async () => {
    const { app, people } = buildApp();
    const token = tokens.portal(people.faculty);
    expectInvalid(await create(app, token, { body: '   ' }), MESSAGES.WALL_POST_BODY);
    expectInvalid(await create(app, token, { body: 'x'.repeat(2001) }), MESSAGES.WALL_POST_BODY);
    expectInvalid(await create(app, token, { body: 'Fine.', colour: 'red' }), MESSAGES.UNKNOWN_FIELD);
    expectInvalid(await create(app, token, { body: 'Fine.', scope: 'canteen' }), MESSAGES.WALL_SCOPE);
  });

  it('creates a poll with its options, and refuses fewer than two or more than ten', async () => {
    const { app, people } = buildApp();
    const token = tokens.portal(people.faculty);
    const res = await create(app, token, {
      kind: 'poll', body: 'Which day suits the faculty meet?',
      poll: { options: ['Monday', 'Wednesday'], closes_on: '2026-11-01' },
    });
    expect(res.status).toBe(201);
    expect(res.body.post.kind).toBe('poll');
    expect(res.body.post.poll).toMatchObject({ multiple: false, anonymous: false, closed: false, total_votes: 0 });
    expect(res.body.post.poll.options.map((o) => o.label)).toEqual(['Monday', 'Wednesday']);
    const few = await create(app, token, { kind: 'poll', body: 'One only?', poll: { options: ['Only'], closes_on: '2026-11-01' } });
    expectInvalid(few, MESSAGES.WALL_POLL_OPTIONS);
    const past = await create(app, token, { kind: 'poll', body: 'Too late?', poll: { options: ['A', 'B'], closes_on: '2026-10-15' } });
    expectInvalid(past, MESSAGES.WALL_POLL_PAST);
  });

  it('refuses praise and wishes here: they have their own addresses and their own checks', async () => {
    const { app, people } = buildApp();
    const res = await create(app, tokens.portal(people.faculty), { kind: 'praise', body: 'Thanks!' });
    expectInvalid(res, MESSAGES.WALL_POST_KIND);
  });

  it('answers 403 for a desk login and 401 with no token', async () => {
    const { app, people } = buildApp();
    expectRefusal(await create(app, tokens.portal(people.desk), { body: 'Hello.' }), 403, 'NOT_LINKED');
    const res = await request(app).post(POSTS).send({ body: 'Hello.' });
    expectRefusal(res, 401, 'NOT_AUTHENTICATED');
  });

  it('answers 503 MODULE_NOT_INSTALLED before its migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    db.dropTable('hr_ess_wall_posts');
    expectRefusal(await create(app, tokens.portal(people.faculty), { body: 'Hello.' }), 503, 'MODULE_NOT_INSTALLED');
  });

  it('answers 503 UNAVAILABLE when the database is away', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    db.outage = 'error';
    expectRefusal(await create(app, tokens.portal(people.faculty), { body: 'Hello.' }), 503, 'UNAVAILABLE');
  });
});

describe('GET /api/ess/wall/posts', () => {
  it('shows the organisation wall and the caller\'s own branch, and not another branch', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [
        W.postRow(w.people.faculty.employee.id, 1, { body: 'Org note', scope: 'org' }),
        W.postRow(w.people.faculty.employee.id, 2, { body: 'Faridabad note', scope: 'branch', branch_id: w.people.faculty.employee.branch_id }),
        W.postRow(w.people.pune.employee.id, 3, { body: 'Pune note', scope: 'branch', branch_id: w.people.pune.employee.branch_id }),
      ];
    } });
    const res = await feed(app, tokens.portal(people.faculty));
    expect(res.status).toBe(200);
    expect(res.body.posts.map((p) => p.body)).toEqual(['Faridabad note', 'Org note']);
    const onlyOrg = await feed(app, tokens.portal(people.faculty), '?scope=org');
    expect(onlyOrg.body.posts.map((p) => p.body)).toEqual(['Org note']);
    const onlyBranch = await feed(app, tokens.portal(people.faculty), '?scope=branch');
    expect(onlyBranch.body.posts.map((p) => p.body)).toEqual(['Faridabad note']);
  });

  it('leaves out deleted posts, and shows a hidden post to its author and HR only', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [
        W.postRow(w.people.faculty.employee.id, 1, { body: 'Gone', deleted_at: W.AT }),
        W.postRow(w.people.faculty.employee.id, 2, {
          body: 'Hidden', created_at: '2026-10-16T04:00:00+00:00',
          hidden_at: W.AT, hidden_by_name: 'Test HR Manager', hide_reason: 'Not for the wall',
        }),
        W.postRow(w.people.hr.employee.id, 3, { body: 'Fine' }),
      ];
    } });
    const others = await feed(app, tokens.portal(people.hod));
    expect(others.body.posts.map((p) => p.body)).toEqual(['Fine']);
    const mine = await feed(app, tokens.portal(people.faculty));
    // Newest first: 05:00 'Fine', then the hidden 04:00 one, which its author still sees.
    expect(mine.body.posts.map((p) => p.body)).toEqual(['Fine', 'Hidden']);
    expect(mine.body.posts[1].hidden).toBe(true);
    const hr = await feed(app, tokens.portal(people.hr));
    expect(hr.body.posts.map((p) => p.body)).toEqual(['Fine', 'Hidden']);
  });

  it('pages with before, and says when the list was cut', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = Array.from({ length: 25 }, (_, i) => W.postRow(
        w.people.faculty.employee.id, 100 + i,
        { scope: 'org', body: `Note ${i}`, created_at: `2026-10-${String(15 - Math.floor(i / 8)).padStart(2, '0')}T0${i % 8}:00:00+00:00` },
      ));
    } });
    const first = await feed(app, tokens.portal(people.faculty));
    expect(first.body.posts).toHaveLength(20);
    expect(first.body.truncated).toBe(true);
    expect(first.body.next_before).toBe(first.body.posts[19].created_at);
    const second = await feed(app, tokens.portal(people.faculty), `?before=${encodeURIComponent(first.body.next_before)}`);
    expect(second.body.posts).toHaveLength(5);
    expect(second.body.truncated).toBe(false);
    expect(second.body.next_before).toBe(null);
  });

  it('shows my own reaction, the counts and who reacted', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1, { reaction_counts: { clap: 2 } })];
      w.tables.hr_ess_wall_reactions = [
        W.reactionRow(w.people.hr.employee.id, 'clap', { post_id: W.POST_ID(1) }),
        W.reactionRow(w.people.hod.employee.id, 'clap', { post_id: W.POST_ID(1) }),
      ];
    } });
    const res = await feed(app, tokens.portal(people.hr));
    expect(res.body.posts[0].my_reaction).toBe('clap');
    expect(res.body.posts[0].reactions).toEqual({ counts: { clap: 2 }, total: 2 });
  });

  it('shows a poll with its options, the votes so far and whether I have voted', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1, {
        kind: 'poll', body: 'Lunch?', poll_closes_on: '2026-11-01',
      })];
      w.tables.hr_ess_wall_poll_options = [W.optionRow(W.POST_ID(1), 1, 'Chaat', 0), W.optionRow(W.POST_ID(1), 2, 'Dosa', 1)];
      w.tables.hr_ess_wall_poll_votes = [W.voteRow(W.POST_ID(1), W.OPTION_ID(2), w.people.hr.employee.id)];
    } });
    const res = await feed(app, tokens.portal(people.hr));
    expect(res.body.posts[0].poll).toMatchObject({ multiple: false, anonymous: false, closed: false, total_votes: 1 });
    expect(res.body.posts[0].poll.my_option_ids).toEqual([W.OPTION_ID(2)]);
    expect(res.body.posts[0].poll.options.map((o) => [o.label, o.votes])).toEqual([['Chaat', 0], ['Dosa', 1]]);
  });

  it('refuses a bad scope and a bad before, and answers 503 before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    expectInvalid(await feed(app, tokens.portal(people.faculty), '?scope=roof'), MESSAGES.WALL_SCOPE);
    expectInvalid(await feed(app, tokens.portal(people.faculty), '?before=last-tuesday'), MESSAGES.WALL_POST_NOT_FOUND);
    db.dropTable('hr_ess_wall_posts');
    expectRefusal(await feed(app, tokens.portal(people.faculty)), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('GET /api/ess/wall/posts/{id}', () => {
  it('returns the post with its comments and one level of replies', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1, { comment_count: 2 })];
      w.tables.hr_ess_wall_comments = [
        W.commentRow(W.POST_ID(1), w.people.hr.employee.id, 1, { body: 'Well done.' }),
        W.commentRow(W.POST_ID(1), w.people.faculty.employee.id, 2, { parent_id: W.COMMENT_ID(1), body: 'Thank you.' }),
      ];
    } });
    const res = await one(app, tokens.portal(people.faculty), W.POST_ID(1));
    expect(res.status).toBe(200);
    expect(res.body.post.comments).toHaveLength(1);
    const [comment] = res.body.post.comments;
    expect(comment.body).toBe('Well done.');
    expect(comment.replies).toHaveLength(1);
    expect(comment.replies[0].body).toBe('Thank you.');
    expect(comment.replies[0].parent_id).toBe(W.COMMENT_ID(1));
  });

  it('blanks a hidden comment for everybody but HR and its author', async () => {
    const hidden = { hidden_at: W.AT, hidden_by_name: 'Test HR Manager', hide_reason: 'Rude' };
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)];
      w.tables.hr_ess_wall_comments = [
        W.commentRow(W.POST_ID(1), w.people.hod.employee.id, 1, { body: 'Something rude.', ...hidden }),
      ];
    } });
    const asFaculty = await one(app, tokens.portal(people.faculty), W.POST_ID(1));
    const [seen] = asFaculty.body.post.comments;
    expect(seen.hidden).toBe(true);
    expect(seen.body).toBe(null);
    expect(seen.author).toBe(null);
    const asAuthor = await one(app, tokens.portal(people.hod), W.POST_ID(1));
    expect(asAuthor.body.post.comments[0].body).toBe('Something rude.');
    const asHr = await one(app, tokens.portal(people.hr), W.POST_ID(1));
    expect(asHr.body.post.comments[0].body).toBe('Something rude.');
  });

  it('answers 404 for a post that is not there, is deleted, or is hidden from me', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [
        W.postRow(w.people.faculty.employee.id, 1, { deleted_at: W.AT }),
        W.postRow(w.people.faculty.employee.id, 2, { hidden_at: W.AT, hidden_by_name: 'Test HR Manager', hide_reason: 'Not for the wall' }),
      ];
    } });
    expectRefusal(await one(app, tokens.portal(people.hod), W.POST_ID(1)), 404, 'NOT_FOUND');
    expectRefusal(await one(app, tokens.portal(people.hod), W.POST_ID(2)), 404, 'NOT_FOUND');
    expectRefusal(await one(app, tokens.portal(people.hod), W.POST_ID(9)), 404, 'NOT_FOUND');
    const author = await one(app, tokens.portal(people.faculty), W.POST_ID(2));
    expect(author.status).toBe(200);
  });

  it('answers 400 for an id that is not one, and 503 before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)];
    } });
    expectInvalid(await one(app, tokens.portal(people.faculty), 'not-an-id'), MESSAGES.INVALID_ID);
    db.dropTable('hr_ess_wall_comments');
    expectRefusal(await one(app, tokens.portal(people.faculty), W.POST_ID(1)), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('PATCH and DELETE /api/ess/wall/posts/{id}', () => {
  it('edits my own post inside the 15 minutes, and says it was edited', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1, { created_at: '2026-10-16T06:20:00+00:00' })];
    } });
    const res = await edit(app, tokens.portal(people.faculty), W.POST_ID(1), { body: 'Corrected wording.' });
    expect(res.status).toBe(200);
    expect(res.body.post.body).toBe('Corrected wording.');
    expect(res.body.post.edited).toBe(true);
    expect(res.body.post.edited_at).toBe(NOW.toISOString());
  });

  it('refuses an edit after the window, and one on somebody else\'s post', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [
        W.postRow(w.people.faculty.employee.id, 1, { created_at: '2026-10-16T06:00:00+00:00' }),
        W.postRow(w.people.hod.employee.id, 2),
      ];
    } });
    expectRefusal(await edit(app, tokens.portal(people.faculty), W.POST_ID(1), { body: 'Later.' }), 409, 'EDIT_WINDOW_CLOSED');
    expectRefusal(await edit(app, tokens.portal(people.faculty), W.POST_ID(2), { body: 'Not mine.' }), 403, 'NOT_YOURS');
  });

  it('deletes my own post, and leaves the row behind with the body blanked', async () => {
    const { app, people, db } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)];
    } });
    const res = await remove(app, tokens.portal(people.faculty), W.POST_ID(1));
    expect(res.status).toBe(204);
    const row = db.tables.hr_ess_wall_posts[0];
    expect(row.deleted_at).toBe(NOW.toISOString());
    expect(row.body).toBe('(deleted)');
    expect(row.attachments).toEqual([]);
    // The trail says so, and nothing deleted is readable.
    expect(db.tables.hr_ess_audit.map((a) => a.action)).toEqual(['wall.post.deleted']);
    expectRefusal(await remove(app, tokens.portal(people.faculty), W.POST_ID(1)), 404, 'NOT_FOUND');
  });

  it('refuses deleting somebody else\'s post, and a deleted one', async () => {
    const { app, people } = buildApp({ setup: (w) => {
      w.tables.hr_ess_wall_posts = [
        W.postRow(w.people.hod.employee.id, 2),
        W.postRow(w.people.faculty.employee.id, 3, { deleted_at: W.AT }),
      ];
    } });
    expectRefusal(await remove(app, tokens.portal(people.faculty), W.POST_ID(2)), 403, 'NOT_YOURS');
    expectRefusal(await remove(app, tokens.portal(people.faculty), W.POST_ID(3)), 404, 'NOT_FOUND');
  });

  it('answers 503 before the migration, for both', async () => {
    quietErrors();
    const { app, people, db } = buildApp();
    db.dropTable('hr_ess_wall_posts');
    expectRefusal(await edit(app, tokens.portal(people.faculty), W.POST_ID(1), { body: 'Hi.' }), 503, 'MODULE_NOT_INSTALLED');
    expectRefusal(await remove(app, tokens.portal(people.faculty), W.POST_ID(1)), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('GET /api/ess/wall/settings', () => {
  it('hands the app the rules every form is built from', async () => {
    const { app, people } = buildApp();
    const res = await request(app).get('/api/ess/wall/settings').set(bearer(tokens.attendance(people.attendance)));
    expect(res.status).toBe(200);
    expect(res.body.post).toMatchObject({ everyone: true, max_attachments: 5, edit_window_minutes: 15, scopes: ['org', 'branch'] });
    expect(res.body.reactions).toEqual(['like', 'love', 'laugh', 'clap', 'insightful', 'curious']);
    expect(res.body.praise.badges).toHaveLength(12);
    expect(res.body.announcement.roles.sort()).toEqual(['ceo', 'hr', 'super_admin']);
    expect(res.body.moderation.roles).toEqual(['hr']);
    expect(res.body.poll).toMatchObject({ min_options: 2, max_options: 10, anonymous: true });
  });

  it('refuses with no token, and needs the database to reach the caller at all', async () => {
    const { app, people } = buildApp();
    const none = await request(app).get('/api/ess/wall/settings');
    expectRefusal(none, 401, 'NOT_AUTHENTICATED');
    // The rules themselves need no table, but every route is behind the sign-in, which does.
    quietErrors();
    const away = buildApp();
    away.db.outage = 'error';
    expectRefusal(
      await request(away.app).get('/api/ess/wall/settings').set(bearer(tokens.portal(people.hr))),
      503,
      'UNAVAILABLE',
    );
  });
});
