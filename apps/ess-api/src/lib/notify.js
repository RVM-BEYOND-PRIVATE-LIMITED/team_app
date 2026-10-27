const { REQUEST_TYPE_LABELS, dmy } = require('../policy/notifications');

/**
 * The in-app notifications the ESS writes itself (tasks D6, D7): a request filed notifies its
 * approver, and a decision notifies the employee. Both are best effort -- a notification that
 * cannot be written never fails the request or the decision it is about, and the failure goes to
 * the pm2 log. The push worker (src/jobs/push.js) delivers them separately.
 *
 * The approver is C10's: the manager on the HR record, or HR when nobody is recorded. "HR" is the
 * people whose portal role is `hr`; a request with no manager therefore reaches every HR login,
 * which is what the fallback means. An HR Executive is not included in the fallback (their powers
 * exclude attendance and leave), though they may still see their own reports' requests.
 */

/** The employee ids that must hear about a new request: the manager, or HR when none is set. */
async function approverEmployeeIds(store, requester) {
  if (requester.manager_id) return [requester.manager_id];
  const userIds = (await store.listHrUserIds()) || [];
  if (!userIds.length) return [];
  const employees = await store.listEmployeesByUserIds(userIds.map((u) => u.id));
  return employees.map((e) => e.id);
}

/** '5 Nov' for one day, '5 Nov to 9 Nov' for a range, plus the half-day choice. */
const leaveWhen = (request) => {
  const end = request.end_day && request.end_day !== request.day ? ` to ${dmy(request.end_day)}` : '';
  const portion = request.portion === 'first_half' ? ' (first half)'
    : request.portion === 'second_half' ? ' (second half)' : '';
  return `${dmy(request.day)}${end}${portion}`;
};

/** 'New attendance request' to the approver. Never throws. */
async function notifyApprovers({ store, requester, request, family }) {
  try {
    const ids = await approverEmployeeIds(store, requester);
    const title = family === 'leave' ? 'New leave request' : 'New attendance request';
    const when = family === 'leave' ? leaveWhen(request) : dmy(request.day);
    const body = `${requester.full_name} asked for ${REQUEST_TYPE_LABELS[request.type] || request.type} on ${when}.`;
    for (const employeeId of ids) {
      if (!employeeId || employeeId === requester.id) continue;
      await store.createNotification({
        employee_id: employeeId,
        category: 'approvals',
        title,
        body,
        data: { request_id: request.id, request_family: family },
      });
    }
  } catch (e) {
    console.error(`[ess] notification for a new request failed: ${e && e.message ? e.message : e}`);
  }
}

/** 'Request approved' / 'Request rejected' to the employee. Never throws. */
async function notifyDecision({ store, request, family, approved, byName }) {
  try {
    const what = REQUEST_TYPE_LABELS[request.type] || request.type;
    const when = family === 'leave' ? leaveWhen(request) : dmy(request.day);
    await store.createNotification({
      employee_id: request.employee_id,
      category: 'decisions',
      title: approved ? 'Request approved' : 'Request rejected',
      body: `Your request for ${what} on ${when} was ${approved ? 'approved' : 'rejected'}${byName ? ` by ${byName}` : ''}.`,
      data: { request_id: request.id, request_family: family },
    });
  } catch (e) {
    console.error(`[ess] notification for a decision failed: ${e && e.message ? e.message : e}`);
  }
}

module.exports = { approverEmployeeIds, notifyApprovers, notifyDecision };
