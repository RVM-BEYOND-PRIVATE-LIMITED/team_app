const { istDay } = require('./time');
const { audienceSummary } = require('../policy/wall');
const { isActive } = require('../policy/employment');

/**
 * An announcement's audience (task F5), in one place because three callers need the same answer:
 * the create route (publish now), the Wall job (publish when a scheduled time arrives) and the
 * reminder. The audience is resolved ONCE, into one row per person, because a list recomputed on
 * every read could not say "who has not acknowledged yet".
 *
 * The audience object is the app's own shape (policy/wall.js audienceView): `{"all": true}`, or
 * any of branch_ids, department_ids, roles, employee_ids -- an OR of the people each names. Roles
 * are matched through the account link (`users.role`), which is what decision 8's "by role" means.
 */

/** Everybody an audience names, on strength today: leavers and archived records are left out. */
async function resolveAudience(store, audience) {
  const today = istDay(new Date());
  const people = (await store.listAudienceEmployees()).filter((e) => isActive(e, today));
  if (!audience || audience.all) return people;
  const roles = audience.roles || [];
  let byRole = null;
  if (roles.length) {
    const userIds = [...new Set(people.map((p) => p.user_id).filter(Boolean))];
    const accounts = await store.listUserRolesFor(userIds);
    const accountRole = new Map(accounts.map((a) => [a.id, a.role]));
    const wanted = new Set(roles);
    byRole = new Set(people.filter((p) => p.user_id && wanted.has(accountRole.get(p.user_id))).map((p) => p.id));
  }
  const wanted = {
    branch: new Set(audience.branch_ids || []),
    department: new Set(audience.department_ids || []),
    person: new Set(audience.employee_ids || []),
  };
  return people.filter((e) => (
    (byRole && byRole.has(e.id))
    || (wanted.branch.size && wanted.branch.has(e.branch_id))
    || (wanted.department.size && wanted.department.has(e.department_id))
    || wanted.person.has(e.id)
  ));
}

/** A staff-facing reading of an audience: "Everybody", "Branches: Faridabad" (F5). */
async function audienceLabel(store, audience) {
  if (!audience || audience.all) return 'Everybody';
  const lookups = { branches: {}, departments: {}, employees: {} };
  const [branches, departments] = await Promise.all([store.listAllBranches(), store.listAllDepartments()]);
  for (const b of branches) lookups.branches[b.id] = b.name;
  for (const d of departments) lookups.departments[d.id] = d.name;
  const people = await store.listEmployeeCards(audience.employee_ids || []);
  for (const p of people) lookups.employees[p.id] = p.full_name;
  return audienceSummary(audience, lookups);
}

/** One announcement's counts: how many it reached, how many read it, how many acknowledged (F5). */
async function countsOf(store, announcementId) {
  const [audience, reads] = await Promise.all([
    store.listAudienceRows(announcementId),
    store.listAnnouncementReads(announcementId),
  ]);
  const sent = new Set(audience.map((a) => a.employee_id));
  const read = reads.filter((r) => sent.has(r.employee_id));
  const acked = read.filter((r) => r.ack_at);
  return {
    sent: sent.size,
    read: read.length,
    acknowledged: acked.length,
    not_acknowledged: Math.max(0, sent.size - acked.length),
  };
}

/** Everybody in an announcement's audience who has not acknowledged it yet (F5's reminder). */
async function waitingOn(store, announcementId) {
  const [audience, reads] = await Promise.all([
    store.listAudienceRows(announcementId),
    store.listAnnouncementReads(announcementId),
  ]);
  const acked = new Set(reads.filter((r) => r.ack_at).map((r) => r.employee_id));
  return audience.map((a) => a.employee_id).filter((id) => !acked.has(id));
}

module.exports = { resolveAudience, audienceLabel, countsOf, waitingOn };
