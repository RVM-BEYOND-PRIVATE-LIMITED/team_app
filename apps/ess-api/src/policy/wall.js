const { ROLES } = require('./roles');
const { ANNOUNCE_ROLES, MODERATE_ROLES } = require('./capabilities');

/**
 * The Wall's product rules in one place (tasks F1 to F9; KP, 16 Oct 2026, decision 8, and
 * 19 Oct 2026). The routes enforce them and `GET /api/ess/wall/settings` (F8) hands the app the
 * same numbers, so a form and its refusal can never disagree.
 *
 * Decision 8 as KP worded it: "Everyone can post, comment, react, praise and run polls. Only HR,
 * the CEO and super admins post announcements. HR can hide anything, with a reason." The three
 * role sets are `src/policy/capabilities.js`'s (ANNOUNCE_ROLES, MODERATE_ROLES), reused here
 * rather than copied, so the capability document and the Wall cannot drift apart.
 *
 * The praise badges are FIXED (KP, 19 Oct): "the catalogue ships in code", not a table HR edits.
 * A badge in a request that is not one of these is refused.
 */

/** F1: how long the author may still edit their own post or comment. */
const EDIT_WINDOW_MINUTES = 15;

/** F6: "new joiners in their first 15 days". */
const NEW_JOINER_DAYS = 15;

/** F1: "up to 5 photos or PDFs". */
const MAX_ATTACHMENTS = 5;

/** F3: "a reason of up to 280 characters". */
const PRAISE_MAX_CHARS = 280;

/** F4: "a question with two to ten options" is the build's reading; the brief says at least two. */
const MIN_POLL_OPTIONS = 2;
const MAX_POLL_OPTIONS = 10;

/** F4: how far ahead a poll may close. A year is more than any poll on a staff wall needs. */
const MAX_POLL_DAYS = 365;

/** F5: "up to 3 pinned" (the brief). */
const MAX_PINNED = 3;

/** The six reactions (F2), in the order the app shows them. */
const REACTIONS = Object.freeze(['like', 'love', 'laugh', 'clap', 'insightful', 'curious']);

/** The four kinds of feed row (F1 to F4, F6). */
const POST_KINDS = Object.freeze(['post', 'praise', 'wish', 'poll']);

/** The two wall scopes: everybody, or one branch (F1: "the organisation wall and one wall per branch"). */
const SCOPES = Object.freeze(['org', 'branch']);

/** The two occasions a one-tap wish covers (F6). */
const OCCASIONS = Object.freeze(['birthday', 'anniversary']);

/**
 * F3: RVM's badges, fixed. `for` says what the badge is about, which the app uses to group the
 * picker; the id is what a request sends and the label is what staff read.
 */
const PRAISE_BADGES = Object.freeze([
  Object.freeze({ id: 'student_first', label: 'Student first', for: 'teaching' }),
  Object.freeze({ id: 'placement_star', label: 'Placement star', for: 'placement' }),
  Object.freeze({ id: 'team_player', label: 'Team player', for: 'teamwork' }),
  Object.freeze({ id: 'lab_guardian', label: 'Lab guardian', for: 'care' }),
  Object.freeze({ id: 'extra_mile', label: 'Going the extra mile', for: 'effort' }),
  Object.freeze({ id: 'mentor', label: 'Mentor', for: 'people' }),
  Object.freeze({ id: 'problem_solver', label: 'Problem solver', for: 'effort' }),
  Object.freeze({ id: 'customer_voice', label: 'Voice of the customer', for: 'outreach' }),
  Object.freeze({ id: 'quality_champion', label: 'Quality champion', for: 'quality' }),
  Object.freeze({ id: 'knowledge_sharer', label: 'Always teaching', for: 'people' }),
  Object.freeze({ id: 'reliable_hand', label: 'A hand you can count on', for: 'teamwork' }),
  Object.freeze({ id: 'above_and_beyond', label: 'Above and beyond', for: 'effort' }),
]);

const badgeById = (id) => PRAISE_BADGES.find((b) => b.id === id) || null;

const badgeView = (b) => ({ id: b.id, label: b.label, for: b.for });

/**
 * Who posts announcements, and who moderates anything: decision 8's roles, taken from the
 * capability rules rather than restated (src/policy/capabilities.js ANNOUNCE_ROLES,
 * MODERATE_ROLES). A role added to the Scheduler later gets neither until somebody decides.
 */

/** Whether this sign-in may post announcements (portal roles only, per decision 8). */
const canAnnounce = (kind, role) => kind === 'portal' && ANNOUNCE_ROLES.has(role);

/** Whether this sign-in may hide anything, and read the report queue (HR only, decision 8). */
const canModerate = (kind, role) => kind === 'portal' && MODERATE_ROLES.has(role);

/** Whether this sign-in may read the moderation log. HR's own roles, plus the CEO's read view. */
const LOG_READ_ROLES = new Set([ROLES.HR, ROLES.CEO, ROLES.SUPER_ADMIN]);

/** The manager roles the audience picker offers. All of them, for HR to address by role. */
const AUDIENCE_ROLES = Object.freeze(
  Object.values(ROLES).filter((r) => r !== ROLES.STUDENT && r !== ROLES.BOT_READONLY),
);

/**
 * The announcement audience as the app sends it (F5). Absent or `{"all": true}` means everybody;
 * any list present is an OR of the people it names. Returns null when it is not an object of the
 * shapes below, which the route refuses.
 */
function audienceView(raw) {
  if (raw === undefined || raw === null) return { all: true };
  if (typeof raw !== 'object' || Array.isArray(raw)) return null;
  const keys = Object.keys(raw);
  const allowed = ['all', 'branch_ids', 'department_ids', 'roles', 'employee_ids'];
  if (keys.some((k) => !allowed.includes(k))) return null;
  if (raw.all === true) {
    if (keys.some((k) => k !== 'all')) return null;
    return { all: true };
  }
  const out = {};
  for (const key of ['branch_ids', 'department_ids', 'employee_ids']) {
    if (raw[key] === undefined) continue;
    if (!Array.isArray(raw[key]) || raw[key].some((v) => typeof v !== 'string')) return null;
    out[key] = [...new Set(raw[key])];
  }
  if (raw.roles !== undefined) {
    if (!Array.isArray(raw.roles) || raw.roles.some((r) => !AUDIENCE_ROLES.includes(r))) return null;
    out.roles = [...new Set(raw.roles)];
  }
  return Object.keys(out).length ? out : { all: true };
}

/** Every person id an audience resolves to, out of the employee cards the route reads (F5). */
function audienceEmployeeIds(audience, employees) {
  if (!audience || audience.all) return employees.map((e) => e.id);
  const out = new Set();
  for (const [key, field] of [['branch_ids', 'branch_id'], ['department_ids', 'department_id'], ['employee_ids', 'id']]) {
    const wanted = new Set(audience[key] || []);
    if (!wanted.size) continue;
    for (const e of employees) if (wanted.has(e[field])) out.add(e.id);
  }
  if ((audience.roles || []).length) {
    const roles = new Set(audience.roles);
    for (const e of employees) if (roles.has(e.role)) out.add(e.id);
  }
  return [...out];
}

/** A short, staff-facing reading of an audience, for an announcement's own list (F5). */
function audienceSummary(audience, lookups = {}) {
  if (!audience || audience.all) return 'Everybody';
  const parts = [];
  const names = (ids, table) => (ids || []).map((id) => (lookups[table] || {})[id] || 'one branch').join(', ');
  if ((audience.branch_ids || []).length) parts.push(`Branches: ${names(audience.branch_ids, 'branches')}`);
  if ((audience.department_ids || []).length) parts.push(`Departments: ${names(audience.department_ids, 'departments')}`);
  if ((audience.roles || []).length) parts.push(`Roles: ${audience.roles.join(', ')}`);
  if ((audience.employee_ids || []).length) {
    const people = (lookups.employees || {});
    parts.push(`People: ${audience.employee_ids.map((id) => people[id] || 'one person').join(', ')}`);
  }
  return parts.length ? parts.join('; ') : 'Everybody';
}

/**
 * The @mentions a body carries, by employee code: '@RVM-011'. Employee codes are the one handle
 * every staff member has and HR keeps unique, and the app's picker inserts exactly this form. A
 * code that is not there is ignored (a mention of a leaver is not an error).
 */
const MENTION_RE = /@([A-Za-z]{2,4}-[A-Za-z0-9]{1,12})\b/g;

function mentionCodes(text) {
  const out = new Set();
  for (const m of String(text || '').matchAll(MENTION_RE)) out.add(m[1].toUpperCase());
  return [...out];
}

/** F1/F2: whether this post or comment was written so recently that its author may still edit it. */
const withinEditWindow = (createdAt, now) =>
  Date.parse(createdAt) + EDIT_WINDOW_MINUTES * 60 * 1000 > now.getTime();

/** F4: a poll is open until its closing day, and its options are locked once somebody has voted. */
const pollOpenOn = (pollClosesOn, day) => Boolean(pollClosesOn) && String(pollClosesOn) <= day;

/** F8: the rules document. The app renders its forms from this, so both sides agree. */
function wallSettings() {
  return {
    post: {
      everyone: true,
      max_attachments: MAX_ATTACHMENTS,
      max_body: 2000,
      edit_window_minutes: EDIT_WINDOW_MINUTES,
      mentions: 'employee_code',
      scopes: [...SCOPES],
    },
    comment: { everyone: true, max_body: 1000, reply_depth: 1, edit_window_minutes: EDIT_WINDOW_MINUTES },
    reactions: [...REACTIONS],
    praise: {
      badges: PRAISE_BADGES.map(badgeView),
      max_reason: PRAISE_MAX_CHARS,
      photo: true,
      certificate: false,
    },
    poll: {
      min_options: MIN_POLL_OPTIONS,
      max_options: MAX_POLL_OPTIONS,
      max_option_chars: 120,
      multiple: true,
      anonymous: true,
      closes_within_days: MAX_POLL_DAYS,
    },
    announcement: {
      everyone: false,
      roles: [...ANNOUNCE_ROLES],
      max_attachments: MAX_ATTACHMENTS,
      max_pinned: MAX_PINNED,
      audience: { scopes: ['all', 'branch_ids', 'department_ids', 'roles', 'employee_ids'], roles: [...AUDIENCE_ROLES] },
      acknowledgement: true,
      scheduled: true,
    },
    moderation: { roles: [...MODERATE_ROLES], reasons: true, reports: true },
    celebrations: { enabled: true, opt_out: true, new_joiner_days: NEW_JOINER_DAYS },
    email: { enabled: false },
  };
}

module.exports = {
  EDIT_WINDOW_MINUTES,
  MAX_ATTACHMENTS,
  PRAISE_MAX_CHARS,
  MIN_POLL_OPTIONS,
  MAX_POLL_OPTIONS,
  MAX_POLL_DAYS,
  MAX_PINNED,
  NEW_JOINER_DAYS,
  REACTIONS,
  POST_KINDS,
  SCOPES,
  OCCASIONS,
  PRAISE_BADGES,
  AUDIENCE_ROLES,
  LOG_READ_ROLES,
  ANNOUNCE_ROLES,
  MODERATE_ROLES,
  badgeById,
  badgeView,
  canAnnounce,
  canModerate,
  audienceView,
  audienceEmployeeIds,
  audienceSummary,
  mentionCodes,
  withinEditWindow,
  pollOpenOn,
  wallSettings,
};
