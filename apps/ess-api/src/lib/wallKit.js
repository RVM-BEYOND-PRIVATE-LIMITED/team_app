const crypto = require('crypto');
const { HttpError, MESSAGES } = require('./errors');
const { invalid, chars } = require('./validate');
const { badgeById, MAX_ATTACHMENTS, mentionCodes, POST_KINDS, SCOPES, canModerate } = require('../policy/wall');

/**
 * The helpers the Wall's routes share (tasks F1 to F9): attachments (base64 in, ESS bucket and
 * signed links out), @mentions resolved by employee code, the poll's own numbers, and the small
 * checks a form and its route agree on.
 *
 * The rule every read keeps: one query per kind of thing, never one per row. A feed page of 20
 * posts reads its authors, mentions and my own reactions in a handful of requests, not sixty.
 */

/** A row's attachments as stored: [{ path, name, content_type }], at most five, never a raw path back. */
const CONTENT_TYPES = Object.freeze({
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'application/pdf': 'pdf',
});
const MAX_FILE_BYTES = 1024 * 1024; // 1 MB decoded, what the app compresses to (F9)
const BASE64 = /^[A-Za-z0-9+/]+={0,2}$/;

/**
 * The attachments of one request: up to five files, each base64 with its content type. Every path
 * is the ESS's own, under `wall/...` or `announcement/...`, so the bucket's contents always say
 * what put them there.
 */
function attachmentsFrom(body, { folder, employeeId }) {
  const raw = body.attachments;
  if (raw === undefined || raw === null) return [];
  if (!Array.isArray(raw) || raw.length > MAX_ATTACHMENTS) throw invalid(MESSAGES.WALL_ATTACHMENTS);
  const out = [];
  for (const item of raw) {
    if (!item || typeof item !== 'object' || Array.isArray(item)) throw invalid(MESSAGES.WALL_ATTACHMENTS);
    const keys = Object.keys(item);
    if (keys.some((k) => !['data_base64', 'content_type', 'name'].includes(k))) throw invalid(MESSAGES.WALL_ATTACHMENTS);
    const data = item.data_base64;
    if (typeof data !== 'string' || chars(data) < 16 || chars(data) > 2_100_000 || !BASE64.test(data)) {
      throw invalid(MESSAGES.WALL_ATTACHMENTS);
    }
    const ext = CONTENT_TYPES[item.content_type];
    if (!ext) throw invalid(MESSAGES.WALL_ATTACHMENTS);
    const buffer = Buffer.from(data, 'base64');
    if (!buffer.length || buffer.length > MAX_FILE_BYTES) throw invalid(MESSAGES.WALL_ATTACHMENTS);
    const name = typeof item.name === 'string' ? item.name.trim().slice(0, 120) : null;
    out.push({
      buffer,
      content_type: item.content_type,
      name: name || null,
      path: `${folder}/${employeeId}/${crypto.randomUUID()}.${ext}`,
    });
  }
  return out;
}

/** Uploads each file and answers what the row stores. A file with no row left pointing at it is a cleanup job. */
async function storeAttachments(store, files) {
  const out = [];
  for (const file of files) {
    await store.uploadEssObject(file.path, file.buffer, file.content_type);
    out.push({ path: file.path, name: file.name, content_type: file.content_type });
  }
  return out;
}

/**
 * The @mentions a body carries: the employee codes in it, resolved to the staff who hold them.
 * A code that resolves to nobody is simply not a mention (a leaver, a typo, "@RVM" alone).
 */
async function resolveMentions(store, text, { exclude = null } = {}) {
  const codes = mentionCodes(text);
  if (!codes.length) return [];
  const people = await store.listEmployeeCardsByCodes(codes);
  const seen = new Set();
  const out = [];
  for (const person of people) {
    if (!person.id || person.id === exclude || seen.has(person.id)) continue;
    seen.add(person.id);
    out.push(person);
  }
  return out;
}

/** Every employee a set of rows refers to, read once: authors, subjects and mentions. */
async function peopleFor(store, rows) {
  const ids = new Set();
  for (const row of rows) {
    for (const id of [row.employee_id, row.about_employee_id, ...(row.mentions || [])]) if (id) ids.add(id);
  }
  const people = await store.listEmployeeCards([...ids]);
  return new Map(people.map((p) => [p.id, p]));
}

/** Whether this branch is one the caller may post on: their own, or none at all. */
function branchProblem(scope, branchId, myBranchId) {
  if (scope === 'org') return null;
  if (!myBranchId) return MESSAGES.WALL_WRONG_BRANCH;
  if (!branchId || branchId !== myBranchId) return MESSAGES.WALL_WRONG_BRANCH;
  return null;
}

/** The scope a request asks for, and its branch: the caller's own branch by default, or the organisation's. */
function scopeFrom(body, myBranchId) {
  const scope = body.scope === undefined || body.scope === null ? 'branch' : body.scope;
  if (!SCOPES.includes(scope)) throw invalid(MESSAGES.WALL_SCOPE);
  if (scope === 'org') {
    if (body.branch_id !== undefined && body.branch_id !== null) throw invalid(MESSAGES.UNKNOWN_FIELD);
    return { scope, branchId: null };
  }
  const branchId = body.branch_id === undefined || body.branch_id === null ? myBranchId : body.branch_id;
  const problem = branchProblem('branch', branchId, myBranchId);
  if (problem) throw invalid(problem);
  return { scope, branchId };
}

/**
 * The poll block of a post: its options with their counts, my own votes, and whether it is still
 * open. `day` is the IST today, so "closed" is the server's answer and never the phone's.
 */
function pollView(row, options, votes, myVotes, day) {
  const counts = new Map();
  for (const vote of votes) counts.set(vote.option_id, (counts.get(vote.option_id) || 0) + 1);
  return {
    multiple: row.poll_multiple === true,
    anonymous: row.poll_anonymous === true,
    closes_on: row.poll_closes_on,
    // Closed by its closing day passing, or by its author closing it early (F4).
    closed: row.poll_closed_at != null || String(row.poll_closes_on) < day,
    closed_at: row.poll_closed_at ?? null,
    options_locked: row.options_locked_at != null,
    total_votes: votes.length,
    my_option_ids: [...new Set(myVotes.map((v) => v.option_id))],
    options: (options || []).map((o) => ({
      id: o.id,
      label: o.label,
      position: o.position,
      votes: counts.get(o.id) || 0,
    })),
  };
}

/** The badge a praise carries, refused when it is not in the fixed catalogue (F3). */
function badgeFrom(value) {
  const badge = badgeById(value);
  if (!badge) throw invalid(MESSAGES.WALL_PRAISE_BADGE);
  return badge.id;
}

/** A post kind a request asks for, refused when it is not one of the four. */
function kindFrom(value) {
  if (!POST_KINDS.includes(value)) throw invalid(MESSAGES.WALL_POST_KIND);
  return value;
}

/** A 404 in the Wall's words. */
const notFound = (message) => new HttpError(404, 'NOT_FOUND', message);

/**
 * Whether this caller is HR, or the row's author: the two who may still read anything a hide
 * covered (F7). Nothing about whether the row is actually hidden.
 */
const privilegedOver = (auth, row) => Boolean(
  row && (row.employee_id === auth.employee.id || canModerate(auth.kind, auth.role)),
);

/**
 * Whether this caller still sees a hidden post or comment (F7): HR, or its author. Everybody else
 * is answered 404, exactly as for one that was never there, so a hide never becomes a leak.
 */
const seesHidden = (auth, row) => Boolean(row && row.hidden_at && privilegedOver(auth, row));

module.exports = {
  CONTENT_TYPES,
  MAX_FILE_BYTES,
  attachmentsFrom,
  storeAttachments,
  resolveMentions,
  peopleFor,
  branchProblem,
  scopeFrom,
  pollView,
  badgeFrom,
  kindFrom,
  notFound,
  privilegedOver,
  seesHidden,
};
