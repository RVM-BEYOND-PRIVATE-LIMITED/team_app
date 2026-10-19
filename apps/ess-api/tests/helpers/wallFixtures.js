const crypto = require('crypto');

/**
 * The Wall's own fixtures for the Phase 2A tests (tasks F1 to F9): a post, a comment, rows of each
 * kind, and the wall photos a request may carry. Fixed ids, so a failing test is easy to read.
 *
 * The rows are written as db/migrations/20261108000001-3 declare them, defaults included, so a
 * route under test reads the same shapes the database would hand it.
 */

/** 'a1', 7 -> a1000000-0000-4000-8000-000000000007: a valid uuid, and easy to read in a failure. */
const uuid = (prefix, n) => `${prefix.padEnd(8, '0').slice(0, 8)}-0000-4000-8000-${String(n).padStart(12, '0')}`;

const POST_ID = (n) => uuid('a1', n);
const COMMENT_ID = (n) => uuid('a2', n);
const OPTION_ID = (n) => uuid('a3', n);
const REPORT_ID = (n) => uuid('a4', n);
const ANNOUNCEMENT_ID = (n) => uuid('a5', n);

const AT = '2026-10-16T05:00:00+00:00';

/** One hr_ess_wall_posts row, of any kind, as the table holds it. */
function postRow(employeeId, n, change = {}) {
  const base = {
    id: POST_ID(n),
    employee_id: employeeId,
    kind: 'post',
    scope: 'org',
    branch_id: null,
    body: 'A note for the whole team.',
    attachments: [],
    mentions: [],
    badge: null,
    occasion: null,
    about_employee_id: null,
    poll_multiple: false,
    poll_anonymous: false,
    poll_closes_on: null,
    options_locked_at: null,
    poll_closed_at: null,
    reaction_counts: {},
    comment_count: 0,
    edited_at: null,
    created_at: AT,
    updated_at: AT,
    hidden_at: null,
    hidden_by_user_id: null,
    hidden_by_name: null,
    hide_reason: null,
    deleted_at: null,
    ...change,
  };
  return base;
}

/** One hr_ess_wall_comments row. */
function commentRow(postId, employeeId, n, change = {}) {
  return {
    id: COMMENT_ID(n),
    post_id: postId,
    employee_id: employeeId,
    parent_id: null,
    body: 'Well said.',
    mentions: [],
    reaction_counts: {},
    reply_count: 0,
    edited_at: null,
    created_at: AT,
    updated_at: AT,
    hidden_at: null,
    hidden_by_user_id: null,
    hidden_by_name: null,
    hide_reason: null,
    deleted_at: null,
    ...change,
  };
}

/** One hr_ess_wall_poll_options row. */
const optionRow = (postId, n, label, position, change = {}) => ({
  id: OPTION_ID(n),
  post_id: postId,
  option_key: `o${position + 1}`,
  label,
  position,
  created_at: AT,
  ...change,
});

/** One hr_ess_wall_poll_votes row. */
const voteRow = (postId, optionId, voterId, change = {}) => ({
  id: crypto.randomUUID(),
  post_id: postId,
  option_id: optionId,
  voter_employee_id: voterId,
  voted_at: AT,
  ...change,
});

/** One hr_ess_wall_reactions row, on a post or on a comment. */
const reactionRow = (employeeId, reaction, change = {}) => ({
  id: crypto.randomUUID(),
  post_id: null,
  comment_id: null,
  employee_id: employeeId,
  reaction,
  created_at: AT,
  ...change,
});

/** One hr_ess_announcements row, published unless told otherwise. */
function announcementRow(employeeId, n, change = {}) {
  return {
    id: ANNOUNCEMENT_ID(n),
    employee_id: employeeId,
    title: 'Office closed on Monday',
    body: 'The branch is closed for the local holiday; attendance is not expected.',
    attachments: [],
    audience: { all: true },
    publish_at: AT,
    published_at: AT,
    needs_ack: false,
    closes_on: null,
    pinned: false,
    read_count: 0,
    ack_count: 0,
    reminded_at: null,
    created_at: AT,
    updated_at: AT,
    edited_at: null,
    deleted_at: null,
    ...change,
  };
}

const audienceRow = (announcementId, employeeId, change = {}) => ({
  id: crypto.randomUUID(),
  announcement_id: announcementId,
  employee_id: employeeId,
  added_at: AT,
  ...change,
});

const readRow = (announcementId, employeeId, change = {}) => ({
  id: crypto.randomUUID(),
  announcement_id: announcementId,
  employee_id: employeeId,
  read_at: AT,
  ack_at: null,
  ...change,
});

const reportRow = (reporterId, n, change = {}) => ({
  id: REPORT_ID(n),
  reporter_id: reporterId,
  post_id: null,
  comment_id: null,
  reason: 'This does not belong on the wall.',
  detail: null,
  status: 'open',
  resolved_by_user_id: null,
  resolved_by_name: null,
  resolved_at: null,
  resolution_note: null,
  created_at: AT,
  ...change,
});

/** A real 1x1 PNG, base64: the smallest picture a request may carry (the Wall's E10 test's own). */
const PNG_B64 = Buffer.from(
  '89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c4890000000d4944415478da63fcffff3f030005fe02fea72d1e4b0000000049454e44ae426082',
  'hex',
).toString('base64');

/** A file as a request sends it: base64, its type, and a name. */
const file = (change = {}) => ({ data_base64: PNG_B64, content_type: 'image/png', name: 'photo.png', ...change });

module.exports = {
  uuid,
  POST_ID,
  COMMENT_ID,
  OPTION_ID,
  REPORT_ID,
  ANNOUNCEMENT_ID,
  AT,
  postRow,
  commentRow,
  optionRow,
  voteRow,
  reactionRow,
  announcementRow,
  audienceRow,
  readRow,
  reportRow,
  PNG_B64,
  file,
};
