/**
 * The notification categories, the quiet hours and the shapes the app reads (tasks D6, D8).
 *
 * Categories are the Phase 1 events: an approval waiting for me, my request decided, and a
 * priority task assigned to me. The Wall's categories arrive with Phase 2 and extend the
 * migration's CHECK then.
 *
 * Nothing is pushed at night: 21:00 to 08:00 IST (Keka's behaviour, and the brief's "nothing is
 * pushed at night"). The in-app row is written at once regardless; only the phone stays quiet.
 */

const CATEGORIES = Object.freeze([
  'approvals', 'decisions', 'priority_tasks',
  // The Wall's own (Phase 2A, F8): a mention, a reply to my comment, praise, an announcement
  // that reached me, an acknowledgement it asks for (and the reminder), and a poll I voted in
  // that has closed.
  'mentions', 'replies', 'praise', 'announcements', 'acknowledgements', 'polls',
  // The Helpdesk's (Phase 2B, G2): a raise telling my team, a reply or a status telling the
  // raiser, and G3's escalations.
  'helpdesk',
  // My Documents' (Phase 2C, KP 1): a document HR has looked at, and the weekly reminder that
  // my mandatory documents are still missing.
  'documents',
  // The CRM's (team_app #59, TA-P-01): a callback the sales team promised, a call placed from
  // the web, a lead assigned to me, a follow-up due, and a sales alert.
  'crm_callback', 'crm_call', 'crm_lead_assigned', 'crm_followup', 'crm_alert',
]);

/**
 * The categories whose phone push cannot wait: a callback or a call placed from the web is the
 * sales team's promise to somebody, and it cannot sit until 08:00. They are always on, so
 * settingsView marks them locked and putSettings refuses to switch them off.
 */
const URGENT_CATEGORIES = Object.freeze(['crm_callback', 'crm_call']);

/** How each CRM category is named on screen. */
const CATEGORY_LABELS = Object.freeze({
  crm_callback: 'Callback',
  crm_call: 'Call from the web',
  crm_lead_assigned: 'Lead assigned',
  crm_followup: 'Follow-up due',
  crm_alert: 'Sales alert',
});

const QUIET_FROM = '21:00';
const QUIET_TO = '08:00';
const QUIET_FROM_HOUR = 21;
const QUIET_TO_HOUR = 8;

/** The IST hour of an instant, 0 to 23 (lib/time.js has the same +05:30 arithmetic). */
const istHour = (instant) => Number(new Date(instant.getTime() + 330 * 60 * 1000).toISOString().slice(11, 13));

/** Whether push must wait: 21:00 or later, or before 08:00, IST. */
const isQuietHours = (instant) => {
  const hour = istHour(instant);
  return hour >= QUIET_FROM_HOUR || hour < QUIET_TO_HOUR;
};

/** Staff wording for each request type, for a notification's body. */
const REQUEST_TYPE_LABELS = Object.freeze({
  on_duty: 'on duty',
  fix_a_day: 'a fix a day',
  excuse_late: 'a late arrival excused',
  short_leave: 'a short leave',
  cl: 'casual leave',
  lwp: 'leave without pay',
  wfh: 'work from home',
});

/** '2026-10-15' -> '15 Oct', as staff write a day. */
const dmy = (day) => new Date(`${day}T00:00:00Z`).toLocaleDateString('en-IN', { day: 'numeric', month: 'short', timeZone: 'UTC' });

/** One notification as the app reads it: never the push bookkeeping. */
const notificationView = (r) => ({
  id: r.id,
  category: r.category,
  priority: r.priority === 'urgent' ? 'urgent' : 'normal',
  title: r.title,
  body: r.body,
  data: r.data ?? {},
  read_at: r.read_at ?? null,
  created_at: r.created_at,
});

/** The settings document, with every category named: no row means everything on. */
function settingsView(row) {
  const disabled = new Set((row && row.disabled_categories) || []);
  return {
    categories: CATEGORIES.map((category) => {
      const locked = URGENT_CATEGORIES.includes(category);
      // A locked category is always on, whatever an older row may say.
      return { category, enabled: locked || !disabled.has(category), locked };
    }),
    quiet_hours: { from: QUIET_FROM, to: QUIET_TO },
  };
}

module.exports = {
  CATEGORIES,
  URGENT_CATEGORIES,
  CATEGORY_LABELS,
  QUIET_FROM,
  QUIET_TO,
  isQuietHours,
  istHour,
  REQUEST_TYPE_LABELS,
  dmy,
  notificationView,
  settingsView,
};
