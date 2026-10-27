const { MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, optionalText, chars, requiredText, invalid, isPlainObject } = require('../lib/validate');
const { isCalendarDay } = require('../lib/time');
const { recordAfter } = require('../lib/audit');
const { workExperienceView } = require('../lib/profileKit');

/**
 * Issue #31: the owner's work history. The list is replaced as a whole, so the app can keep its
 * edits locally and send one Save; the database function does the delete and the insert in one
 * transaction. A hidden entry stays in the owner's list and is left out of the colleague profile.
 */

const MAX_ENTRIES = 20;
const ENTRY_FIELDS = ['id', 'company', 'role_title', 'from_date', 'to_date', 'is_current', 'location', 'description', 'is_visible'];

/** One entry from the request body, validated and trimmed; the id is never trusted. */
function parseEntry(raw) {
  if (!isPlainObject(raw) || Object.keys(raw).some((key) => !ENTRY_FIELDS.includes(key))) {
    throw invalid(MESSAGES.WORK_EXPERIENCE);
  }
  const company = requiredText(raw.company, { min: 1, max: 200, message: MESSAGES.WORK_EXPERIENCE });
  const roleTitle = requiredText(raw.role_title, { min: 1, max: 200, message: MESSAGES.WORK_EXPERIENCE });
  if (!isCalendarDay(raw.from_date)) throw invalid(MESSAGES.WORK_EXPERIENCE_DATE);
  const toDate = raw.to_date === undefined || raw.to_date === null || raw.to_date === ''
    ? null
    : raw.to_date;
  if (toDate !== null && !isCalendarDay(toDate)) throw invalid(MESSAGES.WORK_EXPERIENCE_DATE);
  if (toDate !== null && toDate < raw.from_date) throw invalid(MESSAGES.WORK_EXPERIENCE_DATE);

  const isCurrent = raw.is_current === undefined ? false : raw.is_current;
  if (typeof isCurrent !== 'boolean') throw invalid(MESSAGES.WORK_EXPERIENCE);
  if (isCurrent && toDate !== null) throw invalid(MESSAGES.WORK_EXPERIENCE_CURRENT);

  const isVisible = raw.is_visible === undefined ? true : raw.is_visible;
  if (typeof isVisible !== 'boolean') throw invalid(MESSAGES.WORK_EXPERIENCE);

  const location = optionalText(raw.location);
  if (location === undefined || (location !== null && chars(location) > 200)) throw invalid(MESSAGES.WORK_EXPERIENCE_TEXT);
  const description = optionalText(raw.description);
  if (description === undefined || (description !== null && chars(description) > 1000)) throw invalid(MESSAGES.WORK_EXPERIENCE_TEXT);

  return {
    company,
    role_title: roleTitle,
    from_date: raw.from_date,
    to_date: toDate,
    is_current: isCurrent,
    location,
    description,
    is_visible: isVisible,
  };
}

/** GET /api/ess/me/work-experience — my whole list, hidden entries included. */
function getMyWorkExperience({ store }) {
  return asyncRoute(async (req, res) => {
    const rows = await store.listWorkExperience(req.auth.employee.id);
    res.json({ entries: rows.map(workExperienceView) });
  });
}

/** PUT /api/ess/me/work-experience { entries: [...] } — replace my list. */
function putMyWorkExperience({ store }) {
  return asyncRoute(async (req, res) => {
    const body = bodyWith(req, ['entries']);
    if (!Array.isArray(body.entries) || body.entries.length > MAX_ENTRIES) {
      throw invalid(MESSAGES.WORK_EXPERIENCE);
    }
    const entries = body.entries.map(parseEntry);
    const saved = await store.replaceWorkExperience(req.auth.employee.id, entries);
    await recordAfter(store, req, {
      action: 'work_experience.changed',
      targetEmployeeId: req.auth.employee.id,
      details: { count: entries.length },
    });
    res.json({ entries: (saved || []).map(workExperienceView) });
  });
}

module.exports = { getMyWorkExperience, putMyWorkExperience, MAX_ENTRIES };
