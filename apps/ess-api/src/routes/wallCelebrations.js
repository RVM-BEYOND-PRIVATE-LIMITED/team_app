const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, requiredText, idParam, oneQueryValue, invalid } = require('../lib/validate');
const { istDay, istDayStart, addDays } = require('../lib/time');
const { NEW_JOINER_DAYS, OCCASIONS, isPromotionEvent } = require('../policy/wall');
const { notFound } = require('../lib/wallKit');
const { postView } = require('./wallViews');
const { isActive } = require('../policy/employment');
const { recordAfter } = require('../lib/audit');

/**
 * Task F6, celebrations: today's birthdays and work anniversaries, recent promotions, the new
 * joiners of the last 15 days, and a one-tap wish.
 *
 *   * **Birthdays** are DAY AND MONTH ONLY, never the year (the brief's rule, and why the year is
 *     not even stored in the reply). A birthday is hidden for anyone who opted out -- the opt-out
 *     is `hr_ess_celebration_optouts`, one row per person, and it is honoured here and nowhere
 *     else, so HR's personal-details screen is unchanged.
 *   * **Work anniversaries** come from `hr_employees.date_of_joining`, which HR already keeps.
 *   * **Promotions** come from the Scheduler's own HR activity trail: an EMPLOYEE_PROMOTED event,
 *     or an EMPLOYEE_UPDATED whose designation moved. The latest one per person inside the
 *     look-back window is shown. Only the event's date is read, never its values, so pay cannot
 *     reach the Wall.
 *   * **New joiners** are the people in their first 15 days.
 *   * **A wish** is a short feed post addressed to the person (kind 'wish'): one per person per
 *     occasion per year, so a birthday does not gather four hundred of them, and the card shows
 *     who has already wished.
 *
 * The date of birth comes from the 1B table, `hr_ess_personal_details.date_of_birth` (from the HR
 * database, KP 19 Oct). Nothing here reads any other personal field.
 */

/** The celebration cards as the app reads them: no year for a birthday, ever. */
const birthdayCard = (employee, dob) => ({
  employee: { id: employee.id, full_name: employee.full_name, employee_code: employee.employee_code ?? null, designation: employee.designation ?? null, branch_id: employee.branch_id ?? null },
  date_of_birth: { day: Number(dob.slice(8, 10)), month: Number(dob.slice(5, 7)) },
});

/** The day and month of a stored date, for the "is it today?" test, which the year never enters. */
const dayMonth = (day) => day.slice(5, 10);

/** GET /api/ess/wall/celebrations?days=30 — today's cards and what is coming (F6). */
function listCelebrations({ store, now }) {
  return asyncRoute(async (req, res) => {
    const raw = oneQueryValue(req.query.days);
    const days = raw === undefined || raw === null || raw === '' ? 30 : Number(raw);
    if (!Number.isInteger(days) || days < 1 || days > 90) throw invalid(MESSAGES.WALL_CELEBRATIONS);
    const today = istDay(now());
    const until = addDays(today, days);
    // Promotions are recent events: `days` looks back for them, not ahead.
    const from = addDays(today, -(days - 1));
    const [people, optouts] = await Promise.all([
      store.listAudienceEmployees(),
      store.listCelebrationOptouts(),
    ]);
    const optedOut = new Set(optouts.filter((o) => o.hidden !== false).map((o) => o.employee_id));
    const active = people.filter((e) => isActive(e, today));

    // The dates of birth for the birthdays, and the promotion events for the promotion cards.
    // Neither read touches a value that can carry pay.
    const [details, promotionEvents] = await Promise.all([
      store.listPersonalDetailsFor(active.map((e) => e.id)),
      store.listPromotionEventsFor(active.map((e) => e.id), istDayStart(from).toISOString()),
    ]);
    const byId = new Map(active.map((e) => [e.id, e]));
    const detailsById = new Map(details.map((d) => [d.employee_id, d]));

    const birthdays = [];
    const anniversaries = [];
    for (const person of active) {
      // A birthday needs to be visible, inside the window, and not opted out.
      const detail = detailsById.get(person.id);
      const dob = detail ? detail.date_of_birth : null;
      if (dob && !optedOut.has(person.id)) {
        const mark = inWindow(dayMonth(dob), today, until);
        if (mark) birthdays.push({ ...birthdayCard(person, dob), on: mark });
      }
      if (person.date_of_joining) {
        const mark = inWindow(dayMonth(person.date_of_joining), today, until);
        if (mark) {
          anniversaries.push({
            employee: card(person),
            date_of_joining: person.date_of_joining,
            // The year is never returned, but the number of years is what the card celebrates.
            years: Number(mark.slice(0, 4)) - Number(person.date_of_joining.slice(0, 4)),
            on: mark,
          });
        }
      }
    }
    // The opt-out answer, without naming anybody: "how many asked to be left off".
    const hiddenCount = [...optedOut].filter((id) => byId.has(id)).length;

    const newJoiners = active
      .filter((e) => e.date_of_joining && e.date_of_joining <= today && e.date_of_joining > addDays(today, -NEW_JOINER_DAYS))
      .map((e) => ({ employee: card(e), date_of_joining: e.date_of_joining, days: daysSince(e.date_of_joining, today) }));

    const promotions = promotionCards(promotionEvents, byId, from, today);

    // Who has already been wished, so a card can show it.
    const year = Number(today.slice(0, 4));
    const aboutIds = [...new Set([...birthdays, ...anniversaries, ...promotions].map((c) => c.employee.id))];
    const wishes = aboutIds.length ? await store.listWishesFor(aboutIds, year) : [];
    const wishedBy = new Map();
    for (const wish of wishes) {
      const key = `${wish.about_id}:${wish.occasion}`;
      if (!wishedBy.has(key)) wishedBy.set(key, []);
      wishedBy.get(key).push(wish.wisher_id);
    }
    const markWished = (cardOut, occasion) => ({
      ...cardOut,
      wished_by_me: (wishedBy.get(`${cardOut.employee.id}:${occasion}`) || []).includes(req.auth.employee.id),
      wish_count: (wishedBy.get(`${cardOut.employee.id}:${occasion}`) || []).length,
    });

    res.json({
      today,
      window_days: days,
      birthdays: birthdays.sort((a, b) => a.on.localeCompare(b.on)).map((c) => markWished(c, 'birthday')),
      anniversaries: anniversaries.sort((a, b) => a.on.localeCompare(b.on)).map((c) => markWished(c, 'anniversary')),
      new_joiners: newJoiners.sort((a, b) => b.date_of_joining.localeCompare(a.date_of_joining)),
      promotions: promotions.map((c) => markWished(c, 'promotion')),
      birthdays_hidden: hiddenCount,
    });
  });
}

/**
 * The latest promotion per active person inside the look-back window, from `from` to `today`
 * inclusive. The route reads only events since `from`, and this keeps the same boundary in one
 * place. Newest first, as the feed reads.
 */
function promotionCards(events, byId, from, today) {
  const latest = new Map();
  for (const event of events) {
    if (!isPromotionEvent(event) || !byId.has(event.entity_id)) continue;
    const on = istDay(new Date(event.occurred_at));
    if (on < from || on > today) continue;
    const current = latest.get(event.entity_id);
    if (!current || on > current.on) latest.set(event.entity_id, { employee: card(byId.get(event.entity_id)), on });
  }
  return [...latest.values()].sort((a, b) => b.on.localeCompare(a.on));
}

/** The day this year's mark falls on, if it is inside the window (leap days land on the 28th). */
function inWindow(dayMonthText, today, until) {
  const [month, day] = dayMonthText.split('-').map(Number);
  const thisYear = today.slice(0, 4);
  const candidate = realDay(thisYear, month, day);
  if (candidate >= today && candidate <= until) return candidate;
  const next = realDay(String(Number(thisYear) + 1), month, day);
  return next >= today && next <= until ? next : null;
}

/** 29 February in a year without one becomes the 28th (the same rule as time.js yearsBefore). */
function realDay(year, month, day) {
  const candidate = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  const parsed = new Date(`${candidate}T00:00:00Z`);
  if (!Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === candidate) return candidate;
  return `${year}-02-28`;
}

/** Whole days between two calendar days. */
const daysSince = (from, to) => Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / 86400000);

/** The card shape the two celebration lists share. */
const card = (employee) => ({
  id: employee.id,
  full_name: employee.full_name,
  employee_code: employee.employee_code ?? null,
  designation: employee.designation ?? null,
  branch_id: employee.branch_id ?? null,
});

/**
 * POST /api/ess/wall/wishes { employee_id, occasion, body } — a one-tap wish (F6).
 * The wish is a short feed post addressed to the person, and the hr_ess_wall_wishes row makes
 * "one each" a database rule rather than a wish of its own.
 */
function createWish({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { employee } = req.auth;
    const body = bodyWith(req, ['employee_id', 'occasion', 'body']);
    const aboutId = idParam(body.employee_id);
    if (aboutId === employee.id) throw invalid(MESSAGES.WALL_WISH_SELF);
    if (!OCCASIONS.includes(body.occasion)) throw invalid(MESSAGES.WALL_WISH_OCCASION);
    const text = requiredText(body.body, { min: 1, max: 200, message: MESSAGES.WALL_POST_BODY });
    const target = await store.getEmployeeById(aboutId);
    if (!target) throw notFound(MESSAGES.EMPLOYEE_NOT_FOUND);
    const today = istDay(now());
    const year = Number(today.slice(0, 4));
    const at = now().toISOString();
    const created = await store.createWallPost({
      employee_id: employee.id,
      kind: 'wish',
      scope: 'org',
      branch_id: null,
      body: text,
      occasion: body.occasion,
      about_employee_id: aboutId,
      created_at: at,
      updated_at: at,
    });
    const wish = await store.createWallWish({
      post_id: created.id, about_id: aboutId, wisher_id: employee.id, occasion: body.occasion, year,
    });
    if (!wish) {
      // One each: the row goes, so nothing half-made is left behind.
      await store.deleteWallPost(created.id, at);
      throw new HttpError(409, 'ALREADY_WISHED', MESSAGES.WALL_ALREADY_WISHED);
    }
    const fresh = await store.getWallPost(created.id);
    res.status(201).json({
      post: await postView(store, fresh, {
        me: employee.id,
        author: employee,
        about: await store.getEmployeeCard(aboutId),
        myReaction: null,
      }),
    });
  });
}

/** PUT /api/ess/me/celebration-optout { hidden } — "hide my birthday" (F6). */
function putOptout({ store, now }) {
  return asyncRoute(async (req, res) => {
    const body = bodyWith(req, ['hidden']);
    if (typeof body.hidden !== 'boolean') throw invalid(MESSAGES.WALL_CELEBRATIONS);
    const saved = await store.setCelebrationOptout(req.auth.employee.id, body.hidden, now().toISOString());
    await recordAfter(store, req, {
      action: 'celebrations.optout',
      targetEmployeeId: req.auth.employee.id,
      details: { hidden: body.hidden },
    });
    res.json({ celebrations: { hidden: saved.hidden === true } });
  });
}

/** GET /api/ess/me/celebration-optout — what the switch says; no row means it is on. */
function getOptout({ store }) {
  return asyncRoute(async (req, res) => {
    const row = await store.getCelebrationOptout(req.auth.employee.id);
    res.json({ celebrations: { hidden: Boolean(row && row.hidden !== false) } });
  });
}

module.exports = { listCelebrations, createWish, getOptout, putOptout };
