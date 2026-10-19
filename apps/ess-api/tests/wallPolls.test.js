const request = require('supertest');
const { buildApp, tokens, bearer } = require('./helpers/app');
const { MESSAGES } = require('../src/lib/errors');
const { expectRefusal, expectInvalid, quietErrors } = require('./helpers/expect');
const W = require('./helpers/wallFixtures');

/** Task F4: polls — voting, one or many, anonymous, options locked, closing. */

const POLLS = '/api/ess/wall/polls';
const POSTS = '/api/ess/wall/posts';

const show = (app, token, id) => request(app).get(`${POLLS}/${id}`).set(bearer(token));
const vote = (app, token, id, body) => request(app).post(`${POLLS}/${id}/vote`).set(bearer(token)).send(body);
const unvote = (app, token, id) => request(app).delete(`${POLLS}/${id}/vote`).set(bearer(token));
const addOption = (app, token, id, body) => request(app).post(`${POLLS}/${id}/options`).set(bearer(token)).send(body);
const close = (app, token, id) => request(app).post(`${POLLS}/${id}/close`).set(bearer(token));

/** A poll of two options, by the faculty member, closing in November. */
const withPoll = (change = {}, options = ['Chaat', 'Dosa'], votes = []) => (w) => {
  w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1, {
    kind: 'poll', body: 'Where should the team lunch be?', poll_closes_on: '2026-11-01', ...change,
  })];
  w.tables.hr_ess_wall_poll_options = options.map((label, i) => W.optionRow(W.POST_ID(1), i + 1, label, i));
  w.tables.hr_ess_wall_poll_votes = votes;
};

describe('POST /api/ess/wall/polls/{id}/vote', () => {
  it('records a single choice, locks the options and shows the results', async () => {
    const { app, people, db } = buildApp({ setup: withPoll() });
    const res = await vote(app, tokens.portal(people.hr), W.POST_ID(1), { option_ids: [W.OPTION_ID(1)] });
    expect(res.status).toBe(200);
    expect(res.body.poll).toMatchObject({ total_votes: 1, my_option_ids: [W.OPTION_ID(1)], options_locked: true, closed: false });
    expect(res.body.poll.options.map((o) => [o.label, o.votes])).toEqual([['Chaat', 1], ['Dosa', 0]]);
    expect(db.tables.hr_ess_wall_poll_votes).toHaveLength(1);
  });

  it('changes a single choice instead of adding a second one', async () => {
    const { app, people, db } = buildApp({ setup: withPoll() });
    const token = tokens.portal(people.hr);
    await vote(app, token, W.POST_ID(1), { option_ids: [W.OPTION_ID(1)] });
    const res = await vote(app, token, W.POST_ID(1), { option_ids: [W.OPTION_ID(2)] });
    expect(res.body.poll.my_option_ids).toEqual([W.OPTION_ID(2)]);
    expect(db.tables.hr_ess_wall_poll_votes).toHaveLength(1);
    expect(db.tables.hr_ess_wall_poll_votes[0].option_id).toBe(W.OPTION_ID(2));
  });

  it('records every choice of a multiple-choice poll, and takes one back', async () => {
    const { app, people, db } = buildApp({ setup: withPoll({ poll_multiple: true }) });
    const token = tokens.portal(people.hr);
    const res = await vote(app, token, W.POST_ID(1), { option_ids: [W.OPTION_ID(1), W.OPTION_ID(2)] });
    expect(res.body.poll.my_option_ids.sort()).toEqual([W.OPTION_ID(1), W.OPTION_ID(2)].sort());
    expect(db.tables.hr_ess_wall_poll_votes).toHaveLength(2);
    const withdrawn = await unvote(app, token, W.POST_ID(1));
    expect(withdrawn.status).toBe(200);
    expect(withdrawn.body.my_option_ids).toEqual([]);
    expect(db.tables.hr_ess_wall_poll_votes).toHaveLength(0);
  });

  it('counts several voters, and never says who voted in an anonymous poll', async () => {
    const { app, people } = buildApp({ setup: withPoll({ poll_anonymous: true }) });
    await vote(app, tokens.portal(people.hr), W.POST_ID(1), { option_ids: [W.OPTION_ID(1)] });
    await vote(app, tokens.portal(people.hod), W.POST_ID(1), { option_ids: [W.OPTION_ID(1)] });
    const res = await show(app, tokens.portal(people.hr), W.POST_ID(1));
    expect(res.body.post.poll.anonymous).toBe(true);
    expect(res.body.post.poll.options[0].votes).toBe(2);
    // Nothing in the reply names a voter, HR's own read included.
    const text = JSON.stringify(res.body);
    expect(text).not.toContain(people.hod.employee.id);
    expect(text).not.toContain(people.hr.employee.id);
  });

  it('refuses a second choice on a single-choice poll, an unknown option, and no choice at all', async () => {
    const { app, people } = buildApp({ setup: withPoll() });
    const token = tokens.portal(people.hr);
    expectInvalid(await vote(app, token, W.POST_ID(1), { option_ids: [W.OPTION_ID(1), W.OPTION_ID(2)] }), MESSAGES.WALL_POLL_SINGLE);
    expectInvalid(await vote(app, token, W.POST_ID(1), { option_ids: [W.OPTION_ID(9)] }), MESSAGES.WALL_POLL_OPTION_UNKNOWN);
    expectInvalid(await vote(app, token, W.POST_ID(1), { option_ids: [] }), MESSAGES.WALL_POLL_CHOICE);
    expectInvalid(await vote(app, token, W.POST_ID(1), {}), MESSAGES.WALL_POLL_CHOICE);
  });

  it('refuses a vote on a closed poll, and one on a post that is not a poll', async () => {
    const closed = buildApp({ setup: withPoll({ poll_closes_on: '2026-10-15' }) });
    expectRefusal(
      await vote(closed.app, tokens.portal(closed.people.hr), W.POST_ID(1), { option_ids: [W.OPTION_ID(1)] }),
      409, 'POLL_CLOSED',
    );
    const notPoll = buildApp({ setup: (w) => { w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)]; } });
    expectRefusal(await vote(notPoll.app, tokens.portal(notPoll.people.hr), W.POST_ID(1), { option_ids: [W.OPTION_ID(1)] }), 404, 'NOT_FOUND');
  });

  it('answers 503 MODULE_NOT_INSTALLED before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp({ setup: withPoll() });
    db.dropTable('hr_ess_wall_poll_votes');
    expectRefusal(await vote(app, tokens.portal(people.hr), W.POST_ID(1), { option_ids: [W.OPTION_ID(1)] }), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('POST /api/ess/wall/polls/{id}/options', () => {
  it('lets the author add one before the first vote', async () => {
    const { app, people } = buildApp({ setup: withPoll() });
    const res = await addOption(app, tokens.portal(people.faculty), W.POST_ID(1), { label: 'Idli' });
    expect(res.status).toBe(201);
    expect(res.body.option).toMatchObject({ label: 'Idli', votes: 0 });
    expect(res.body.poll.options.map((o) => o.label)).toEqual(['Chaat', 'Dosa', 'Idli']);
  });

  it('refuses it once somebody has voted, and when somebody else asks', async () => {
    const voted = buildApp({ setup: withPoll({ options_locked_at: W.AT }) });
    expectRefusal(
      await addOption(voted.app, tokens.portal(voted.people.faculty), W.POST_ID(1), { label: 'Idli' }),
      409, 'POLL_OPTIONS_LOCKED',
    );
    const plain = buildApp({ setup: withPoll() });
    expectRefusal(
      await addOption(plain.app, tokens.portal(plain.people.hr), W.POST_ID(1), { label: 'Idli' }),
      403, 'NOT_YOURS',
    );
  });

  it('refuses an eleventh option and an empty label', async () => {
    const { app, people } = buildApp({ setup: withPoll({}, ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j']) });
    expectInvalid(await addOption(app, tokens.portal(people.faculty), W.POST_ID(1), { label: 'Eleventh' }), MESSAGES.WALL_POLL_OPTIONS);
  });
});

describe('POST /api/ess/wall/polls/{id}/close and GET the poll', () => {
  it('closes a poll by hand, and then nothing can be added or changed', async () => {
    const { app, people, db } = buildApp({ setup: withPoll() });
    const res = await close(app, tokens.portal(people.faculty), W.POST_ID(1));
    expect(res.status).toBe(200);
    expect(res.body.poll.closed).toBe(true);
    expect(res.body.poll.closed_at).toBe('2026-10-16T06:30:00.000Z');
    // The closing day it was due on is kept, so the card can say it closed early.
    expect(db.tables.hr_ess_wall_posts[0].poll_closes_on).toBe('2026-11-01');
    expectRefusal(await vote(app, tokens.portal(people.hr), W.POST_ID(1), { option_ids: [W.OPTION_ID(1)] }), 409, 'POLL_CLOSED');
    expectRefusal(await addOption(app, tokens.portal(people.faculty), W.POST_ID(1), { label: 'Late' }), 409, 'POLL_CLOSED');
  });

  it('refuses closing somebody else\'s poll', async () => {
    const { app, people } = buildApp({ setup: withPoll() });
    expectRefusal(await close(app, tokens.portal(people.hr), W.POST_ID(1)), 403, 'NOT_YOURS');
  });

  it('shows a poll with its results, and answers 404 for a post that is not one', async () => {
    const { app, people } = buildApp({ setup: withPoll({}, ['Chaat', 'Dosa'], [W.voteRow(W.POST_ID(1), W.OPTION_ID(2), W.uuid('e', 9))]) });
    const res = await show(app, tokens.portal(people.faculty), W.POST_ID(1));
    expect(res.status).toBe(200);
    expect(res.body.post.poll.total_votes).toBe(1);
    expect(res.body.post.poll.options[1].votes).toBe(1);
    expect(res.body.post.poll.my_option_ids).toEqual([]);
    const notPoll = buildApp({ setup: (w) => { w.tables.hr_ess_wall_posts = [W.postRow(w.people.faculty.employee.id, 1)]; } });
    expectRefusal(await show(notPoll.app, tokens.portal(notPoll.people.hr), W.POST_ID(1)), 404, 'NOT_FOUND');
    expectInvalid(await show(notPoll.app, tokens.portal(notPoll.people.hr), 'nope'), MESSAGES.INVALID_ID);
  });

  it('answers 503 for a read and a close before the migration', async () => {
    quietErrors();
    const { app, people, db } = buildApp({ setup: withPoll() });
    db.dropTable('hr_ess_wall_poll_options');
    expectRefusal(await show(app, tokens.portal(people.hr), W.POST_ID(1)), 503, 'MODULE_NOT_INSTALLED');
    expectRefusal(await close(app, tokens.portal(people.faculty), W.POST_ID(1)), 503, 'MODULE_NOT_INSTALLED');
  });
});

describe('the poll a post creates', () => {
  it('refuses more than ten options and a closing day over a year away', async () => {
    const { app, people } = buildApp();
    const token = tokens.portal(people.faculty);
    const many = await request(app).post(POSTS).set(bearer(token)).send({
      kind: 'poll', body: 'Too many?',
      poll: { options: ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k'], closes_on: '2026-11-01' },
    });
    expectInvalid(many, MESSAGES.WALL_POLL_OPTIONS);
    const far = await request(app).post(POSTS).set(bearer(token)).send({
      kind: 'poll', body: 'Too far?', poll: { options: ['a', 'b'], closes_on: '2028-01-01' },
    });
    expectInvalid(far, MESSAGES.WALL_POLL_CLOSES);
    const noShape = await request(app).post(POSTS).set(bearer(token)).send({ kind: 'poll', body: 'No options?' });
    expectInvalid(noShape, MESSAGES.WALL_POLL_OPTIONS);
    const notPoll = await request(app).post(POSTS).set(bearer(token)).send({ body: 'Plain.', poll: { options: ['a', 'b'], closes_on: '2026-11-01' } });
    expectInvalid(notPoll, MESSAGES.UNKNOWN_FIELD);
  });
});
