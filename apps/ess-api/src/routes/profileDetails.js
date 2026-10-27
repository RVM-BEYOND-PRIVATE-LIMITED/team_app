const { MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, optionalText, chars, invalid } = require('../lib/validate');
const { isCalendarDay } = require('../lib/time');
const { recordAfter } = require('../lib/audit');
const { profileDetailsView } = require('../lib/profileKit');

/**
 * Issue #31: the owner's About you card — about, likes, dislikes and a personal anniversary date.
 * Blood group stays editable through /me/personal and is shown here read-only. Null or an empty
 * string clears a field. Only the columns sent are written, so a save of one field cannot undo
 * another made since the form was opened.
 */

const TEXT_LIMITS = { about: 1000, likes: 500, dislikes: 500 };

function parseText(field, value) {
  const text = optionalText(value);
  if (text === undefined || (text !== null && chars(text) > TEXT_LIMITS[field])) {
    throw invalid(MESSAGES.PROFILE_DETAILS);
  }
  return text;
}

function parseAnniversary(value) {
  if (value === undefined || value === null || value === '') return null;
  if (!isCalendarDay(value)) throw invalid(MESSAGES.ANNIVERSARY_DATE);
  return value;
}

/** GET /api/ess/me/profile-details */
function getMyProfileDetails({ store }) {
  return asyncRoute(async (req, res) => {
    const employeeId = req.auth.employee.id;
    const [details, personal] = await Promise.all([
      store.getProfileDetails(employeeId),
      store.getPersonalDetails(employeeId),
    ]);
    res.json({ profile: profileDetailsView(details, personal) });
  });
}

/** PUT /api/ess/me/profile-details { about?, likes?, dislikes?, anniversary_date? } */
function putMyProfileDetails({ store, now }) {
  return asyncRoute(async (req, res) => {
    const body = bodyWith(req, ['about', 'likes', 'dislikes', 'anniversary_date']);
    if (!Object.keys(body).length) throw invalid(MESSAGES.NOTHING_TO_CHANGE);

    const employeeId = req.auth.employee.id;
    const fields = {};
    for (const field of ['about', 'likes', 'dislikes']) {
      if (body[field] !== undefined) fields[field] = parseText(field, body[field]);
    }
    if (body.anniversary_date !== undefined) fields.anniversary_date = parseAnniversary(body.anniversary_date);

    const stored = await store.getProfileDetails(employeeId);
    const changed = Object.keys(fields).filter((field) => (stored?.[field] ?? null) !== fields[field]);
    const saved = await store.saveProfileDetails({
      employee_id: employeeId,
      ...fields,
      updated_at: now().toISOString(),
      updated_by_user_id: req.auth.userId ?? null,
    });
    await recordAfter(store, req, {
      action: 'profile_details.changed',
      targetEmployeeId: employeeId,
      details: { fields: changed },
    });
    const personal = await store.getPersonalDetails(employeeId);
    res.json({ profile: profileDetailsView(saved, personal) });
  });
}

module.exports = { getMyProfileDetails, putMyProfileDetails };
