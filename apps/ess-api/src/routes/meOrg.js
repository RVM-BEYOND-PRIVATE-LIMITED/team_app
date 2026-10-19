const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { oneQueryValue, chars, isUuid, invalid } = require('../lib/validate');
const { istDay } = require('../lib/time');
const { chainOf } = require('../policy/me');
const { contactContext } = require('../lib/contactCards');

/**
 * Tasks E2, E8 and E11: the reporting chain up to the CEO, peers, direct reports, the
 * department, and the colleague directory. Every card carries the email (E8: email to
 * everyone) and the phone only where the rule allows it (HR, or a manager above the person).
 * People serving notice stay on every list with the `notice_period` chip (E11).
 */

const DIRECTORY_LIMIT = 50;
const QUERY_MAX = 60;

const ref = (d) => (d ? { id: d.id, name: d.name } : null);

/** GET /api/ess/me/org */
function myOrg({ store }) {
  return asyncRoute(async (req, res) => {
    const { employee, role } = req.auth;
    const today = istDay(new Date());
    const ctx = await contactContext({ store, viewer: employee, role, today });
    const chain = chainOf(ctx.byId, employee.id);

    // "Reports to the CEO (not recorded)": the top of the chain has no manager recorded and is
    // not the CEO's own account. The web org chart adopts these people under the CEO; the app
    // says so instead of inventing a manager.
    let reportsToCeoNotRecorded = false;
    const top = chain[chain.length - 1];
    if (top && !top.manager_id) {
      const roles = top.user_id ? await store.listUserRolesFor([top.user_id]) : [];
      reportsToCeoNotRecorded = !(roles[0] && roles[0].role === 'ceo');
    }

    const peers = ctx.people.filter((e) => ctx.onStrength(e) && e.id !== employee.id
      && employee.manager_id && e.manager_id === employee.manager_id);
    const reports = ctx.people.filter((e) => ctx.onStrength(e) && e.manager_id === employee.id);
    const department = employee.department_id ? ctx.deptById.get(employee.department_id) : null;
    const departmentPeople = department
      ? ctx.people.filter((e) => ctx.onStrength(e) && e.department_id === department.id && e.id !== employee.id)
      : [];

    res.json({
      manager_chain: chain.map(ctx.card),
      reports_to_ceo_not_recorded: reportsToCeoNotRecorded,
      peers: peers.sort(ctx.byName).map(ctx.card),
      direct_reports: {
        count: reports.length,
        people: reports.sort(ctx.byName).map(ctx.card),
      },
      department: department ? { ...ref(department), people: departmentPeople.sort(ctx.byName).map(ctx.card) } : null,
    });
  });
}

/** GET /api/ess/directory?q=&branch_id=&department_id= */
function directory({ store }) {
  return asyncRoute(async (req, res) => {
    const { employee, role } = req.auth;
    const queryRaw = oneQueryValue(req.query.q);
    if (queryRaw !== undefined && (queryRaw === null || chars(queryRaw) > QUERY_MAX)) {
      throw invalid(MESSAGES.DIRECTORY_QUERY);
    }
    const branchRaw = oneQueryValue(req.query.branch_id);
    if (branchRaw !== undefined && (branchRaw === null || !isUuid(branchRaw))) throw invalid(MESSAGES.BRANCH_ID);
    const departmentRaw = oneQueryValue(req.query.department_id);
    if (departmentRaw !== undefined && (departmentRaw === null || !isUuid(departmentRaw))) {
      throw invalid(MESSAGES.DEPARTMENT_ID);
    }

    const today = istDay(new Date());
    const ctx = await contactContext({ store, viewer: employee, role, today });
    if (branchRaw !== undefined && !ctx.branchById.has(branchRaw.toLowerCase())) {
      throw new HttpError(404, 'NOT_FOUND', MESSAGES.BRANCH_NOT_FOUND);
    }
    if (departmentRaw !== undefined && !ctx.deptById.has(departmentRaw.toLowerCase())) {
      throw new HttpError(404, 'NOT_FOUND', MESSAGES.DEPARTMENT_NOT_FOUND);
    }

    const needle = queryRaw === undefined || queryRaw === '' ? null : queryRaw.toLowerCase();
    const matches = ctx.people.filter((e) => {
      if (!ctx.onStrength(e) || e.id === employee.id) return false;
      if (branchRaw !== undefined && e.branch_id !== branchRaw.toLowerCase()) return false;
      if (departmentRaw !== undefined && e.department_id !== departmentRaw.toLowerCase()) return false;
      if (!needle) return true;
      return String(e.full_name || '').toLowerCase().includes(needle)
        || String(e.employee_code || '').toLowerCase().includes(needle);
    });

    matches.sort(ctx.byName);
    const truncated = matches.length > DIRECTORY_LIMIT;
    res.json({ people: matches.slice(0, DIRECTORY_LIMIT).map(ctx.card), truncated });
  });
}

module.exports = { myOrg, directory, DIRECTORY_LIMIT };
