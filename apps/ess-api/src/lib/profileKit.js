const { PRAISE_BADGES } = require('../policy/wall');

/**
 * Issue #31's shared profile shapes: one work-experience entry, the owner's social fields, and
 * the fixed praise badges a colleague has earned. The same objects are returned by the owner's
 * reads and the colleague profile, so the app has one shape to parse.
 */

/** One work-experience row as the app reads it. */
const workExperienceView = (row) => ({
  id: row.id,
  company: row.company,
  role_title: row.role_title,
  from_date: row.from_date,
  to_date: row.to_date ?? null,
  is_current: Boolean(row.is_current),
  location: row.location ?? null,
  description: row.description ?? null,
  is_visible: Boolean(row.is_visible),
});

/** The owner's About you card: blood group comes from the personal-details table. */
const profileDetailsView = (row, personal) => ({
  about: row?.about ?? null,
  likes: row?.likes ?? null,
  dislikes: row?.dislikes ?? null,
  anniversary_date: row?.anniversary_date ?? null,
  blood_group: personal?.blood_group ?? null,
});

/**
 * The fixed catalogue's badges this person has received, with a count and the latest stamp.
 * `for` is always 'people' on a colleague's profile (issue #31's contract); the catalogue's own
 * grouping stays in the praise picker.
 */
function earnedBadges(rows) {
  const byBadge = new Map();
  for (const row of rows) {
    if (!row || !row.badge) continue;
    const found = PRAISE_BADGES.find((badge) => badge.id === row.badge);
    if (!found) continue;
    const current = byBadge.get(row.badge) || { id: found.id, label: found.label, for: 'people', count: 0, last_earned_at: null };
    current.count += 1;
    const at = row.created_at ? Date.parse(row.created_at) : Number.NaN;
    const last = current.last_earned_at ? Date.parse(current.last_earned_at) : Number.NaN;
    if (!current.last_earned_at || (Number.isFinite(at) && (!Number.isFinite(last) || at > last))) {
      current.last_earned_at = row.created_at ?? current.last_earned_at;
    }
    byBadge.set(row.badge, current);
  }
  return [...byBadge.values()].sort((a, b) => b.count - a.count
    || (Date.parse(b.last_earned_at || '') || 0) - (Date.parse(a.last_earned_at || '') || 0)
    || a.label.localeCompare(b.label));
}

module.exports = { workExperienceView, profileDetailsView, earnedBadges };
