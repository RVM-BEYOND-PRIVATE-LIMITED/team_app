const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, idParam, invalid } = require('../lib/validate');
const { istDay } = require('../lib/time');
const { MAX_POLL_OPTIONS } = require('../policy/wall');
const { notFound, peopleFor, pollView } = require('../lib/wallKit');
const { postView } = require('./wallViews');

/**
 * Task F4, polls: a question with two to ten options, single or multiple choice, optionally
 * anonymous, closing on a date. A poll is created as a post (POST /api/ess/wall/posts with
 * kind 'poll', wallPosts.js); this file is what happens after it goes up:
 *
 *   * voting, while it is open;
 *   * adding an option, while nobody has voted yet (F4: "options locked after the first vote");
 *   * closing it by hand, before its date;
 *   * reading a closed poll's results, which is the ordinary feed read.
 *
 * Anonymous is absolute (F4: "nobody, HR included, can see who voted what"): the route never
 * returns a voter for an anonymous poll, whoever asks, and the store's vote rows keep the voter
 * only so that one person's own choices can be shown back to them and a vote cannot be repeated.
 */

/** The poll row behind a request, with the checks every route here shares. */
async function pollRow(store, id) {
  const row = await store.getWallPost(id);
  if (!row || row.deleted_at || row.kind !== 'poll') throw notFound(MESSAGES.WALL_POLL_NOT_POLL);
  return row;
}

/** The whole poll block as the app reads it after a change. */
async function pollBlock(store, row, employeeId, day) {
  const [options, votes, myVotes] = await Promise.all([
    store.listPollOptions(row.id),
    store.listPollVotes(row.id),
    store.listMyPollVotes(row.id, employeeId),
  ]);
  return pollView(row, options, votes, myVotes, day);
}

/** Whether the poll is still open: not closed early, and its closing day (inclusive) not gone. */
const isOpen = (row, day) => row.poll_closed_at == null && String(row.poll_closes_on) >= day;

/** POST /api/ess/wall/polls/{id}/vote { option_ids: [...] } — one or many, while it is open (F4). */
function votePoll({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    const body = bodyWith(req, ['option_ids']);
    const row = await pollRow(store, id);
    const day = istDay(now());
    if (!isOpen(row, day)) throw new HttpError(409, 'POLL_CLOSED', MESSAGES.WALL_POLL_CLOSED);

    const wanted = body.option_ids;
    if (!Array.isArray(wanted) || !wanted.length) throw invalid(MESSAGES.WALL_POLL_CHOICE);
    const ids = [...new Set(wanted.map((v) => idParam(v)))];
    if (!row.poll_multiple && ids.length > 1) throw invalid(MESSAGES.WALL_POLL_SINGLE);

    const options = await store.listPollOptions(id);
    const known = new Map(options.map((o) => [o.id, o]));
    for (const optionId of ids) {
      if (!known.has(optionId)) throw invalid(MESSAGES.WALL_POLL_OPTION_UNKNOWN);
    }

    const at = now().toISOString();
    const mine = await store.listMyPollVotes(id, employee.id);
    const have = new Set(mine.map((v) => v.option_id));
    // A single-choice poll is one row: the old choice goes as the new one arrives.
    if (!row.poll_multiple) {
      for (const vote of mine) {
        if (!ids.includes(vote.option_id)) await store.deletePollVote(id, employee.id);
      }
    }
    for (const optionId of ids) {
      if (have.has(optionId)) continue;
      await store.createPollVote({ post_id: id, option_id: optionId, voter_employee_id: employee.id, voted_at: at });
    }
    // F4: the first vote freezes the option set.
    await store.lockPollOptions(id, at);
    const fresh = await store.getWallPost(id);
    res.json({ poll: await pollBlock(store, fresh, employee.id, day), my_option_ids: ids });
  });
}

/** DELETE /api/ess/wall/polls/{id}/vote — takes my own vote back, while it is open (F4). */
function withdrawPollVote({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    bodyWith(req, []);
    const row = await pollRow(store, id);
    const day = istDay(now());
    if (!isOpen(row, day)) throw new HttpError(409, 'POLL_CLOSED', MESSAGES.WALL_POLL_CLOSED);
    await store.deletePollVote(id, employee.id);
    const fresh = await store.getWallPost(id);
    res.json({ poll: await pollBlock(store, fresh, employee.id, day), my_option_ids: [] });
  });
}

/** POST /api/ess/wall/polls/{id}/options { label } — the author's own, before the first vote (F4). */
function addPollOption({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    const body = bodyWith(req, ['label']);
    const label = requiredText(body.label, { min: 1, max: 120, message: MESSAGES.WALL_POLL_OPTIONS });
    const row = await pollRow(store, id);
    if (row.employee_id !== employee.id) throw new HttpError(403, 'NOT_YOURS', MESSAGES.WALL_OWN_POST);
    const day = istDay(now());
    if (!isOpen(row, day)) throw new HttpError(409, 'POLL_CLOSED', MESSAGES.WALL_POLL_CLOSED);
    if (row.options_locked_at) throw new HttpError(409, 'POLL_OPTIONS_LOCKED', MESSAGES.WALL_POLL_OPTIONS_LOCKED);
    const options = await store.listPollOptions(id);
    if (options.length >= MAX_POLL_OPTIONS) throw invalid(MESSAGES.WALL_POLL_OPTIONS);
    const position = options.reduce((m, o) => Math.max(m, o.position), -1) + 1;
    const created = await store.createPollOptions([{
      post_id: id, option_key: `o${position + 1}`, label, position,
    }]);
    const fresh = await store.getWallPost(id);
    res.status(201).json({
      option: { id: created[0].id, label: created[0].label, position: created[0].position, votes: 0 },
      poll: await pollBlock(store, fresh, employee.id, day),
    });
  });
}

/** POST /api/ess/wall/polls/{id}/close — the author's own, before the closing day (F4). */
function closePoll({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    bodyWith(req, []);
    const row = await pollRow(store, id);
    if (row.employee_id !== employee.id) throw new HttpError(403, 'NOT_YOURS', MESSAGES.WALL_OWN_POST);
    const day = istDay(now());
    const at = now().toISOString();
    // The stamp is the close; poll_closes_on keeps the day it was due on, so the card can say
    // "closed on the 16th, three days early".
    await store.updateWallPost(id, { poll_closed_at: at, updated_at: at });
    const fresh = await store.getWallPost(id);
    res.json({ poll: await pollBlock(store, fresh, employee.id, day) });
  });
}

/** GET /api/ess/wall/polls/{id} — the poll with its results, open or closed (F4). */
function getPoll({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const id = idParam(req.params.id);
    const row = await pollRow(store, id);
    const people = await peopleFor(store, [row]);
    res.json({
      post: await postView(store, row, {
        me: employee.id,
        author: people.get(row.employee_id) || null,
        about: people.get(row.about_employee_id) || null,
        mentioned: (row.mentions || []).map((x) => people.get(x)).filter(Boolean),
        myReaction: await store.getMyPostReaction(id, employee.id),
        poll: await pollBlock(store, row, employee.id, istDay(now())),
      }),
    });
  });
}

module.exports = { votePoll, withdrawPollVote, addPollOption, closePoll, getPoll };
