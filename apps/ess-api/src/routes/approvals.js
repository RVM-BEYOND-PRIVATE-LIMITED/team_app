const { HttpError, MESSAGES, asyncRoute } = require('../lib/errors');
const { bodyWith, optionalText, chars, idParam, oneQueryValue, invalid } = require('../lib/validate');
const { istDay, monthBounds } = require('../lib/time');
const { LIST_LIMITS } = require('../lib/store');
const { effectiveLimit, requestType } = require('../policy/requestLimits');
const { isActive } = require('../policy/employment');
const { chainEntries, firstUnskipped, mayDecide, mayDecideLeave } = require('../policy/approvals');
const { canDecideAny, STATUSES, requestView, employeeCardView } = require('../policy/requests');
const { HALF_DAY_MINUTES, ensureShiftSnapshot, recomputeMonth } = require('../policy/attendance');
const { notifyDecision } = require('../lib/notify');

/**
 * Tasks D1 and H6, plus Phase 2D's D4: the approvals Inbox, the decision, the archive, and the
 * chain one request waits on.
 *
 * Who sees what (decision 1): a manager sees their own direct reports' pending requests, whatever
 * their login role; HR, the CEO and super admins (ATTENDANCE_OVERRIDE_ROLES) see everybody's, may
 * filter by any status, decide any request and later cancel an approved one. An attendance
 * session may be a manager's (the brief: "anyone with direct reports, whatever their login role"),
 * so the manager path accepts both sign-in kinds; the HR-wide path needs the portal role.
 *
 * Who decides (D4): the reporting line up from the requester, skipping a level that cannot decide
 * that day (the requester themselves, not on strength, or on leave), so the FIRST unskipped level
 * decides -- never a level below it. HR-wide keeps deciding anything, as always.
 *
 * The decide route calls the family's SQL function -- lock, re-check, write the day, write the
 * history, all in one transaction -- and then re-counts the month, with the shift snapshot first
 * for a fixed day, exactly as the Scheduler's own controller does after its override.
 */

/** How many "who else is off" names one request's context carries (the rest is a count). */
const CONTEXT_NAMES = 5;

const familyOf = (value) => (value === 'attendance' || value === 'leave' ? value : null);

/**
 * The requester's reporting line for one day's decision, as the decide, archive and chain views
 * all judge it: the directory for the chain, and the sheet for who is on leave that day.
 */
async function chainFor({ store, requester, day, today }) {
  const [people, offRows] = await Promise.all([
    store.listActiveEmployees(),
    store.listDaysOnLeave([day]),
  ]);
  const byId = new Map(people.map((e) => [e.id, e]));
  const offOnDay = new Set(offRows.map((d) => d.employee_id));
  return chainEntries(byId, requester, today, offOnDay);
}

/** The leave requests an Admin Manager, a super admin or HR's fallback may see now. */
async function leaveQueue(store, auth) {
  const pending = await store.listPendingLeaveRequests();
  if (!pending.length) return [];
  if (auth.role === 'super_admin') return pending.filter((r) => r.stage === 'final');

  const requesterIds = [...new Set(pending.map((r) => r.employee_id))];
  const cards = new Map((await Promise.all(requesterIds.map((id) => store.getEmployeeById(id))))
    .filter(Boolean).map((e) => [e.id, e]));

  if (auth.role === 'admin_manager') {
    const branch = auth.employee?.branch_id;
    return pending.filter((r) => r.stage === 'manager'
      && r.employee_id !== auth.employee.id
      && (r.admin_manager_employee_id
        ? r.admin_manager_employee_id === auth.employee.id
        : Boolean(branch && cards.get(r.employee_id)?.branch_id === branch)));
  }

  if (auth.role === 'hr') {
    const managers = await store.listLeaveAdminManagers();
    const withAdmin = new Set((managers || []).map((e) => e.branch_id));
    return pending.filter((r) => r.stage === 'manager'
      && r.employee_id !== auth.employee.id
      && !withAdmin.has(cards.get(r.employee_id)?.branch_id));
  }

  return [];
}

/** GET /api/ess/approvals?status=... */
function listApprovals({ store, now }) {
  return asyncRoute(async (req, res) => {
    const { kind, role, employee } = req.auth;
    const hrWide = canDecideAny(kind, role);
    const raw = oneQueryValue(req.query.status);
    const status = raw === undefined || raw === '' ? 'pending' : raw;
    if (![...STATUSES, 'all'].includes(status)) throw invalid(MESSAGES.APPROVAL_STATUS);
    /*
     * A manager may filter their OWN reports by any status, not only pending (issue #11): the
     * query below is already fenced to `reportIds`, so a wider status cannot widen the people.
     * The old refusal made the app hide the filters from managers; it is no longer needed.
     */
    const limits = await store.getRequestLimits();
    const today = istDay(now());

    let reportIds = null;
    if (!hrWide) {
      const reports = (await store.listDirectReports(employee.id)).filter((r) => isActive(r, today));
      reportIds = reports.map((r) => r.id);
    }

    const filter = status === 'all' ? null : status;
    const fetch = (family, wanted) => store.listRequestsForApprover({ family, employeeIds: reportIds, status: wanted });
    const leaveAll = await leaveQueue(store, req.auth);
    const shownLeave = status === 'pending' || status === 'all' ? leaveAll : [];
    const shownAttendance = await fetch('attendance', filter);
    const pendingAttendance = filter === 'pending'
      ? shownAttendance
      : await fetch('attendance', 'pending');
    const pendingLeave = leaveAll;

    // Archived requests stay out of the caller's Inbox (archiving is per approver, task D1).
    const archives = await store.listMyArchives(employee.id);
    const archived = new Set(archives.map((a) => `${a.family}:${a.request_id}`));
    const isArchived = (family, id) => archived.has(`${family}:${id}`);

    const merged = [
      ...shownAttendance.map((row) => ({ row, family: 'attendance' })),
      ...shownLeave.map((row) => ({ row, family: 'leave' })),
    ].filter((x) => !isArchived(x.family, x.row.id))
      .sort((a, b) => Date.parse(a.row.created_at) - Date.parse(b.row.created_at));
    const truncated = merged.length > LIST_LIMITS.inbox;
    const shown = merged.slice(0, LIST_LIMITS.inbox);

    const counts = {
      attendance: pendingAttendance.filter((r) => !isArchived('attendance', r.id)).length,
      leave: pendingLeave.filter((r) => !isArchived('leave', r.id)).length,
    };
    counts.total = counts.attendance + counts.leave;

    if (!shown.length) return res.json({ counts, requests: [], truncated });

    // The context each request carries: how much of this kind this month (minutes for a short
    // leave, count otherwise), the day's late marks, and who else is off that day (never the
    // leave's type or reason).
    const employeeIds = [...new Set(shown.map((x) => x.row.employee_id))];
    const days = [...new Set(shown.map((x) => x.row.day))];
    const months = [...new Set(shown.map((x) => x.row.day.slice(0, 7)))].sort();
    const from = `${months[0]}-01`;
    const to = monthBounds(`${months[months.length - 1]}-01`).to;
    const [attendanceCounts, leaveCounts, lateMarks, onLeave, leaveOnDays] = await Promise.all([
      store.listRequestCountsFor({ family: 'attendance', employeeIds, from, to }),
      store.listRequestCountsFor({ family: 'leave', employeeIds, from, to }),
      store.listDayLateMarks(days),
      store.listDaysOnLeave(days),
      store.listLeaveRequestsOnDays(days, ['pending', 'approved']),
    ]);

    // Short leave counts by minutes, every other type by requests (C3), so a short leave's
    // `type_this_month` is the minutes used and waiting against its 180-minute limit.
    const typeCounts = new Map();
    const addTypeCount = (family, rows) => {
      for (const r of rows) {
        if (r.status !== 'pending' && r.status !== 'approved') continue;
        const month = r.day.slice(0, 7);
        const leaveStep = Array.isArray(r.working_days) && r.working_days.length
          ? r.working_days.filter((d) => String(d).slice(0, 7) === month).length
          : Number(r.day_count ?? 1);
        const step = family === 'attendance' && r.type === 'short_leave'
          ? (r.minutes ?? 0)
          : family === 'leave' ? leaveStep : 1;
        const key = `${family}:${r.employee_id}:${r.type}:${r.day.slice(0, 7)}`;
        typeCounts.set(key, (typeCounts.get(key) || 0) + step);
      }
    };
    addTypeCount('attendance', attendanceCounts);
    addTypeCount('leave', leaveCounts);
    const lateMarksBy = new Map(lateMarks.map((d) => [`${d.employee_id}:${d.day}`, d]));

    const offByDay = new Map();
    const addOff = (day, employeeId) => {
      if (!offByDay.has(day)) offByDay.set(day, new Set());
      offByDay.get(day).add(employeeId);
    };
    for (const d of onLeave) addOff(d.day, d.employee_id);
    for (const r of leaveOnDays) addOff(r.day, r.employee_id);

    const cardIds = new Set(employeeIds);
    for (const ids of offByDay.values()) for (const id of ids) cardIds.add(id);
    const cards = new Map((await store.listEmployeeCards([...cardIds])).map((e) => [e.id, e]));

    const requests = shown.map(({ row, family }) => {
      const type = requestType(family === 'leave' ? `leave_${row.type}` : row.type);
      const key = `${family}:${row.employee_id}:${row.type}:${row.day.slice(0, 7)}`;
      const context = {
        type_this_month: typeCounts.get(key) || 0,
        month_limit: type ? effectiveLimit(type, limits) : null,
        late: null,
        others_off: { count: 0, names: [] },
      };
      if (family === 'attendance') {
        const mark = lateMarksBy.get(`${row.employee_id}:${row.day}`);
        if (mark) {
          context.late = {
            late_minutes: mark.late_minutes ?? null,
            late_count: mark.late_count ?? null,
            late_half_day: mark.late_half_day ?? false,
            late_excused: mark.late_excused ?? false,
          };
        }
      }
      const others = [...(offByDay.get(row.day) || [])].filter((id) => id !== row.employee_id);
      context.others_off = {
        count: others.length,
        names: others.slice(0, CONTEXT_NAMES).map((id) => (cards.get(id) ? cards.get(id).full_name : null)).filter(Boolean),
      };
      return { ...requestView(row, family, { employee: cards.get(row.employee_id) ?? null }), context };
    });
    res.json({ counts, requests, truncated });
  });
}

/** POST /api/ess/approvals/:family/:id/decide { decision: approve|reject, note? } */
function decideRequest({ store, now }) {
  return asyncRoute(async (req, res) => {
    const family = familyOf(req.params.family);
    if (!family) throw new HttpError(404, 'NOT_FOUND', MESSAGES.NOT_FOUND);
    const id = idParam(req.params.id);
    const body = bodyWith(req, ['decision', 'note', 'substitute_faculty_id', 'class_timing']);
    if (body.decision !== 'approve' && body.decision !== 'reject') throw invalid(MESSAGES.DECIDE_DECISION);
    const note = optionalText(body.note);
    if (note === undefined || (note && chars(note) > 1000)) throw invalid(MESSAGES.DECIDE_NOTE);
    if (body.decision === 'reject' && (!note || chars(note) < 3)) throw invalid(MESSAGES.DECIDE_REJECT_NOTE);

    const request = family === 'leave' ? await store.getLeaveRequest(id) : await store.getAttendanceRequest(id);
    if (!request) throw new HttpError(404, 'NOT_FOUND', MESSAGES.REQUEST_NOT_FOUND);
    const requester = await store.getEmployeeById(request.employee_id);
    const today = istDay(now());
    const entries = requester ? await chainFor({ store, requester, day: request.day, today }) : [];
    let allowed;
    if (family === 'leave') {
      const managers = requester ? await store.listLeaveAdminManagers() : [];
      const hasAdmin = Boolean(requester && (managers || []).some((e) => e.branch_id === requester.branch_id && e.id !== requester.id));
      allowed = mayDecideLeave({
        auth: req.auth, request, requesterBranchId: requester?.branch_id, branchHasAdminManager: hasAdmin,
      });
    } else {
      allowed = mayDecide({ auth: req.auth, entries });
    }
    if (!requester || !allowed) {
      const finalBlocked = family === 'leave' && request.stage === 'final';
      throw new HttpError(403, finalBlocked ? 'FINAL_APPROVAL_ONLY' : 'NOT_AN_APPROVER',
        finalBlocked ? MESSAGES.FINAL_APPROVAL_ONLY : MESSAGES.NOT_AN_APPROVER);
    }

    if (family === 'leave' && request.stage === 'manager') {
      let substituteId = optionalText(body.substitute_faculty_id) || null;
      let substituteName = null;
      const classTiming = optionalText(body.class_timing);
      if (body.decision === 'approve' && request.is_teaching) {
        if (!substituteId || !classTiming) {
          throw new HttpError(400, 'COVERAGE_REQUIRED',
            'Choose the substitute faculty and give the class timing before approving this teaching leave.');
        }
        const faculty = await store.listActiveFaculty();
        const match = (faculty || []).find((f) => f.id === substituteId);
        if (!match) throw new HttpError(400, 'BAD_SUBSTITUTE', 'That substitute faculty is not active.');
        substituteName = match.name;
      }
      const out = await store.decideLeaveAdmin({
        p_request_id: id,
        p_decider_employee_id: req.auth.employee.id,
        p_decider_user_id: req.auth.userId ?? null,
        p_decider_name: req.auth.employee.full_name,
        p_approve: body.decision === 'approve',
        p_note: note || null,
        p_substitute_faculty_id: body.decision === 'approve' && request.is_teaching ? substituteId : null,
        p_substitute_faculty_name: body.decision === 'approve' && request.is_teaching ? substituteName : null,
        p_class_timing: body.decision === 'approve' && request.is_teaching ? classTiming : null,
        p_now: now().toISOString(),
      });
      const outcome = out && out.outcome;
      if (outcome === 'not_found') throw new HttpError(404, 'NOT_FOUND', MESSAGES.REQUEST_NOT_FOUND);
      if (outcome === 'not_pending') throw new HttpError(409, 'ALREADY_DECIDED', MESSAGES.ALREADY_DECIDED);
      if (outcome === 'not_authorized') throw new HttpError(403, 'NOT_AN_APPROVER', MESSAGES.NOT_AN_APPROVER);
      if (outcome === 'coverage_required') {
        throw new HttpError(400, 'COVERAGE_REQUIRED',
          'Choose the substitute faculty and give the class timing before approving this teaching leave.');
      }
      if (outcome === 'note_required') throw invalid(MESSAGES.DECIDE_REJECT_NOTE);

      try {
        await store.createNotification({
          employee_id: request.employee_id,
          category: 'decisions',
          title: body.decision === 'approve' ? 'Admin Manager approved your leave' : 'Leave rejected',
          body: body.decision === 'approve'
            ? `The Admin Manager approved the leave from ${request.day}${request.end_day && request.end_day !== request.day ? ` to ${request.end_day}` : ''}. It now waits for super-admin final approval.`
            : `Your leave from ${request.day}${request.end_day && request.end_day !== request.day ? ` to ${request.end_day}` : ''} was rejected by ${req.auth.employee.full_name}.`,
          data: { request_id: id, request_family: 'leave' },
        });
        if (body.decision === 'approve') {
          const userIds = (await store.listFinalDeciderUserIds()).map((u) => u.id);
          const deciders = await store.listEmployeesByUserIds(userIds);
          for (const person of deciders) {
            if (person.id === req.auth.employee.id) continue;
            await store.createNotification({
              employee_id: person.id,
              category: 'approvals',
              title: 'Leave needs super-admin approval',
              body: `${requester.full_name}'s leave from ${request.day}${request.end_day && request.end_day !== request.day ? ` to ${request.end_day}` : ''} waits for final approval.`,
              data: { request_id: id, request_family: 'leave' },
            });
          }
        }
      } catch { /* best effort */ }

      const fresh = await store.getLeaveRequest(id);
      return res.json({ request: requestView(fresh, family, { employee: requester }), stage: body.decision === 'approve' ? 'final' : 'manager' });
    }

    const common = {
      p_request_id: id,
      p_decider_employee_id: req.auth.employee.id,
      p_decider_user_id: req.auth.userId ?? null,
      p_decider_name: req.auth.employee.full_name,
      p_approve: body.decision === 'approve',
      p_note: note,
      p_now: now().toISOString(),
    };
    const out = family === 'leave'
      ? await store.decideLeaveRequest(common)
      : await store.decideAttendanceRequest({ ...common, p_half_day_minutes: HALF_DAY_MINUTES });
    const outcome = out && out.outcome;
    if (outcome === 'not_found') throw new HttpError(404, 'NOT_FOUND', MESSAGES.REQUEST_NOT_FOUND);
    if (outcome === 'not_pending') throw new HttpError(409, 'ALREADY_DECIDED', MESSAGES.ALREADY_DECIDED);
    if (outcome === 'note_required') throw invalid(MESSAGES.DECIDE_REJECT_NOTE);
    if (outcome === 'too_old') throw new HttpError(409, 'REQUEST_WINDOW', MESSAGES.REQUEST_WINDOW);
    if (outcome === 'cutoff') throw new HttpError(409, 'REQUEST_CLOSED', MESSAGES.REQUEST_CLOSED);
    if (outcome === 'future') throw new HttpError(409, 'REQUEST_FUTURE', MESSAGES.REQUEST_FUTURE);
    if (outcome === 'not_late') throw new HttpError(409, 'NOT_LATE', MESSAGES.NOT_LATE);
    if (outcome === 'times_incomplete') throw new HttpError(409, 'TIMES_INCOMPLETE', MESSAGES.TIMES_INCOMPLETE);
    if (outcome === 'day_off') throw new HttpError(409, 'DAY_LOCKED', MESSAGES.DAY_LOCKED);
    if (outcome === 'no_working_days' || outcome === 'invalid_range') {
      throw new HttpError(409, 'DAY_OFF', MESSAGES.LEAVE_DAY_OFF);
    }
    if (outcome === 'cl_limit') throw new HttpError(409, 'CL_LIMIT', MESSAGES.CL_TAKEN);
    if (outcome === 'wfh_not_allowed') throw new HttpError(409, 'WFH_NOT_ALLOWED', MESSAGES.WFH_NOT_ALLOWED);
    if (outcome === 'wfh_limit') throw new HttpError(409, 'WFH_LIMIT', MESSAGES.WFH_LIMIT);

    // After a decision that wrote the day: the shift snapshot first for a fixed day (so the
    // month's judging sees it), then the recompute -- the controller's own order (124-126).
    if (outcome === 'approved' && out.day_written) {
      if (family === 'attendance' && request.type === 'fix_a_day') {
        await ensureShiftSnapshot({
          store,
          employeeId: request.employee_id,
          branchId: requester ? requester.branch_id : null,
          day: request.day,
        });
      }
      await recomputeMonth({ store, employeeId: request.employee_id, day: request.day, today: istDay(now()) });
    }

    const fresh = family === 'leave' ? await store.getLeaveRequest(id) : await store.getAttendanceRequest(id);
    // The employee hears the outcome (best effort; D6/D7).
    if (outcome === 'approved' || outcome === 'rejected') {
      await notifyDecision({
        store,
        request: fresh,
        family,
        approved: outcome === 'approved',
        byName: req.auth.employee.full_name,
      });
    }
    res.json({ request: requestView(fresh, family, { employee: requester }) });
  });
}

/** POST /api/ess/approvals/:family/:id/archive: clear it from MY Inbox, decide nothing. */
function archiveRequest({ store, now }) {
  return asyncRoute(async (req, res) => {
    const family = familyOf(req.params.family);
    if (!family) throw new HttpError(404, 'NOT_FOUND', MESSAGES.NOT_FOUND);
    const id = idParam(req.params.id);
    bodyWith(req, []);
    const request = family === 'leave' ? await store.getLeaveRequest(id) : await store.getAttendanceRequest(id);
    if (!request) throw new HttpError(404, 'NOT_FOUND', MESSAGES.REQUEST_NOT_FOUND);
    const requester = await store.getEmployeeById(request.employee_id);
    const entries = requester ? await chainFor({ store, requester, day: request.day, today: istDay(now()) }) : [];
    let allowed;
    if (family === 'leave') {
      const managers = requester ? await store.listLeaveAdminManagers() : [];
      const hasAdmin = Boolean(requester && (managers || []).some((e) => e.branch_id === requester.branch_id && e.id !== requester.id));
      allowed = mayDecideLeave({
        auth: req.auth, request, requesterBranchId: requester?.branch_id, branchHasAdminManager: hasAdmin,
      });
    } else {
      allowed = mayDecide({ auth: req.auth, entries });
    }
    if (!requester || !allowed) {
      throw new HttpError(403, 'NOT_AN_APPROVER', MESSAGES.NOT_AN_APPROVER);
    }
    await store.createArchive({ family, request_id: id, employee_id: req.auth.employee.id });
    res.status(204).end();
  });
}

/**
 * GET /api/ess/approvals/:family/:id/chain: the reporting line a request waits on, level by
 * level -- who may decide it now, why each level above is skipped, and whether the HR fallback
 * is all that is left. The requester may read their own request's chain; so may anybody on it,
 * and HR-wide as always. Anybody else is refused: a chain is the request's own routing.
 */
function requestChain({ store, now }) {
  return asyncRoute(async (req, res) => {
    const family = familyOf(req.params.family);
    if (!family) throw new HttpError(404, 'NOT_FOUND', MESSAGES.NOT_FOUND);
    const id = idParam(req.params.id);
    bodyWith(req, []);
    const request = family === 'leave' ? await store.getLeaveRequest(id) : await store.getAttendanceRequest(id);
    if (!request) throw new HttpError(404, 'NOT_FOUND', MESSAGES.REQUEST_NOT_FOUND);
    const requester = await store.getEmployeeById(request.employee_id);
    if (!requester) throw new HttpError(404, 'NOT_FOUND', MESSAGES.REQUEST_NOT_FOUND);
    const viewerId = req.auth.employee.id;

    if (family === 'leave') {
      const managers = await store.listLeaveAdminManagers();
      const inBranch = (managers || []).filter((e) => e.branch_id === requester.branch_id && e.id !== requester.id);
      const assigned = request.admin_manager_employee_id
        ? await store.getEmployeeById(request.admin_manager_employee_id) : null;
      const viewerOnBranch = req.auth.role === 'admin_manager'
        && (assigned ? assigned.id === viewerId : inBranch.some((e) => e.id === viewerId));
      const involved = requester.id === viewerId || viewerOnBranch
        || ['super_admin', 'hr', 'ceo'].includes(req.auth.role);
      if (!involved) throw new HttpError(403, 'NOT_AN_APPROVER', MESSAGES.NOT_AN_APPROVER);

      let chain = [];
      if (request.stage === 'manager') {
        const people = assigned ? [assigned] : inBranch;
        chain = people.filter(Boolean).map((e, i) => ({
          employee: employeeCardView(e), may_decide: i === 0, skipped: null,
        }));
      } else if (request.stage === 'final') {
        const users = await store.listFinalDeciderUserIds();
        const people = await store.listEmployeesByUserIds((users || []).map((u) => u.id));
        chain = people.map((e, i) => ({
          employee: employeeCardView(e), may_decide: i === 0, skipped: null,
        }));
      }
      return res.json({
        request: requestView(request, family, { employee: requester }),
        stage: request.stage ?? 'manager',
        chain,
        hr_fallback: request.stage === 'manager' && inBranch.length === 0,
      });
    }

    const entries = await chainFor({ store, requester, day: request.day, today: istDay(now()) });
    const involved = requester.id === viewerId
      || entries.some((e) => e.employee.id === viewerId)
      || canDecideAny(req.auth.kind, req.auth.role);
    if (!involved) throw new HttpError(403, 'NOT_AN_APPROVER', MESSAGES.NOT_AN_APPROVER);
    const first = firstUnskipped(entries);
    res.json({
      request: requestView(request, family, { employee: requester }),
      stage: request.stage ?? 'manager',
      chain: entries.map((e) => ({
        employee: employeeCardView(e.employee),
        may_decide: Boolean(first && first.employee.id === e.employee.id),
        skipped: e.skipped,
      })),
      hr_fallback: !first,
    });
  });
}

/** GET /api/ess/leave-approvers — super admin chooses one Admin Manager per branch. */
function listLeaveApprovers({ store }) {
  return asyncRoute(async (req, res) => {
    if (req.auth.role !== 'super_admin') {
      throw new HttpError(403, 'NOT_AN_APPROVER', MESSAGES.NOT_AN_APPROVER);
    }
    const [branches, managers] = await Promise.all([store.listAllBranches(), store.listLeaveAdminManagers()]);
    const settings = await Promise.all((branches || []).map((b) => store.getLeaveApprover(b.id)));
    const choice = new Map((settings || []).filter(Boolean).map((s) => [s.branch_id, s.employee_id]));
    res.json({
      branches: (branches || []).map((branch) => {
        const people = (managers || []).filter((e) => e.branch_id === branch.id);
        const chosen = people.find((e) => e.id === choice.get(branch.id)) || null;
        return {
          id: branch.id, name: branch.name,
          selected_employee_id: chosen?.id || null,
          selected_name: chosen?.full_name || null,
          admin_managers: people.map((e) => ({ id: e.id, full_name: e.full_name, employee_code: e.employee_code ?? null })),
        };
      }),
    });
  });
}

/** PUT /api/ess/leave-approvers/:branchId { employee_id } */
function setLeaveApprover({ store, now }) {
  return asyncRoute(async (req, res) => {
    if (req.auth.role !== 'super_admin') {
      throw new HttpError(403, 'NOT_AN_APPROVER', MESSAGES.NOT_AN_APPROVER);
    }
    const branchId = idParam(req.params.branchId);
    const body = bodyWith(req, ['employee_id']);
    const employeeId = idParam(body.employee_id);
    const managers = await store.listLeaveAdminManagers();
    const chosen = (managers || []).find((e) => e.id === employeeId && e.branch_id === branchId);
    if (!chosen) throw new HttpError(400, 'BAD_APPROVER', 'Choose an active Admin Manager at this branch.');
    await store.setLeaveApprover({
      branch_id: branchId,
      employee_id: employeeId,
      configured_by_user_id: req.auth.userId ?? null,
      configured_by_name: req.auth.employee?.full_name || null,
      updated_at: now().toISOString(),
    });
    const pending = await store.listPendingLeaveRequests();
    for (const row of pending.filter((r) => r.stage === 'manager')) {
      const requester = await store.getEmployeeById(row.employee_id);
      if (requester?.branch_id !== branchId) continue;
      await store.assignLeaveRequestApprover({ id: row.id, employeeId, name: chosen.full_name, at: now().toISOString() });
    }
    const out = await listLeaveApprovers({ store })(req, res);
    return out;
  });
}

/** GET /api/ess/leave-faculty?request_id= — substitute choices for the Admin Manager. */
function listLeaveFaculty({ store }) {
  return asyncRoute(async (req, res) => {
    if (!['super_admin', 'admin_manager', 'hr'].includes(req.auth.role)) {
      throw new HttpError(403, 'NOT_AN_APPROVER', MESSAGES.NOT_AN_APPROVER);
    }
    let branchId = req.auth.employee?.branch_id || null;
    const requestId = oneQueryValue(req.query.request_id);
    if (requestId) {
      const request = await store.getLeaveRequest(idParam(requestId));
      if (request) {
        const requester = await store.getEmployeeById(request.employee_id);
        branchId = requester?.branch_id || null;
        if (req.auth.role !== 'super_admin' && req.auth.role !== 'hr' && branchId !== req.auth.employee?.branch_id) {
          throw new HttpError(403, 'OTHER_BRANCH', MESSAGES.NOT_AN_APPROVER);
        }
      }
    }
    const [faculty, locations, branches] = await Promise.all([
      store.listActiveFaculty(), store.listLocations(), store.listAllBranches(),
    ]);
    const branch = (branches || []).find((b) => b.id === branchId);
    const location = branch ? (locations || []).find((l) => l.name === branch.name) : null;
    res.json({
      faculty: (faculty || [])
        .filter((f) => !location || f.location_id === location.id)
        .map((f) => ({ id: f.id, name: f.name })),
    });
  });
}

module.exports = {
  listApprovals, decideRequest, archiveRequest, requestChain,
  listLeaveApprovers, setLeaveApprover, listLeaveFaculty,
};
