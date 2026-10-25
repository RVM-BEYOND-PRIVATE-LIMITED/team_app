# Work from home: the complete flow

22 Oct 2026 · Built in `apps/ess-api`; migration 29. No Scheduler code or schema change.

KP decided that WFH is for **selected employees only**. HR enables it per employee and fixes that
employee's monthly limit in days; the allowance is the limit. WFH is a leave request, one whole day
per request, in the same approvals family as CL and LWP.

## The flow

1. **HR enables the employee and sets the limit.** `PUT /api/ess/hr/wfh-allowances/{employeeId}`
   with `{ enabled, monthly_limit_days, note? }`. The same route changes or disables it later. The
   roles are the attendance HR roles (`hr`, `ceo`, `super_admin`; an HR Executive is refused). The
   save is audited as `wfh.allowance.changed` with the before/after `enabled` and limit only, never
   the note or any personal data.
2. **The employee sees it.** `GET /api/ess/me/wfh` answers `{ month, enabled, monthly_limit_days,
   used, pending, remaining }`; the same allowance appears in the `wfh` row of
   `GET /api/ess/leave/balances`, and `GET /api/ess/me/capabilities` offers `wfh` with the
   employee's own limit. Without a row (or with `enabled: false`) the type is off.
3. **The employee requests a day.** `POST /api/ess/leave-requests { type: 'wfh', day, reason }`.
   The usual leave window holds (this month or last month, ahead allowed, whole days). The route
   counts the month's approved and pending WFH days and refuses with:
   - 409 `WFH_NOT_ALLOWED` — no row, or HR switched it off;
   - 409 `WFH_LIMIT` — the limit would be exceeded;
   - 409 `DUPLICATE_REQUEST` — the same day already waits.
4. **The chain approves.** `POST /api/ess/approvals/leave/{id}/decide`. The SQL function
   `hr_ess_decide_leave_request` re-reads the allowance under a row lock, counts the month's OTHER
   approved WFH days, and refuses with `wfh_not_allowed` or `wfh_limit` if another approval or HR's
   switch got there first. Nothing is written on a refusal.
5. **The day becomes present / WFH.** The approval calls the Scheduler's own
   `hr_attendance_apply_override(employee, day, branch, 'present', NULL, first_in, last_out,
   worked_minutes, 'Work from home: <reason>', decider_user, decider_name)`. The times the day
   already records are kept; `day_before` is stored exactly as leave stores it. The payroll sheet
   and the Admin Manager see a present day with the WFH note, and no punch is needed.
6. **Withdraw or cancel.** The employee may withdraw while pending. After approval only HR cancels
   (`POST /api/ess/hr/leave-requests/{id}/cancel`); the existing leave cancel restores `day_before`
   exactly — the row's status, leave type, note, source, times, worked minutes and marked-by fields
   — or deletes the row if the approval had created it.

## The punch caveat

The approved day is written present, but the **Scheduler's punch path is unchanged**. If the person
punches anyway, the Scheduler still applies the branch geofence and its normal punch rules; a punch
from home can be refused as outside the branch. The ESS does not send a punch and does not mark the
person as geofence-exempt. The day is already correctly present because of the approval, so a
refused punch changes nothing in the ESS's record — but the app should tell the employee not to
punch on an approved WFH day.

## Scheduler handover for a future geofence waiver

A full waiver would be a **Scheduler change**, so it is a documented follow-up and out of scope
under ADR-0018. The handover to whoever owns the Scheduler:

- The punch controller would need to consult an approved WFH day (or an exemption flag) before the
  geofence check, and allow the punch/auto-close as it does for `hr_employees.geofence_exempt`.
- The record to consult already exists in the ESS: `hr_ess_leave_requests` type `wfh`, status
  `approved`, day. A Scheduler-side read or a small table/view owned by the Scheduler would be the
  clean boundary; the ESS must not alter Scheduler tables.
- Until then, the approved day stands on its own: present with `Work from home: <reason>`, written
  through HR's sanctioned override, and restored by HR's cancel.

## Files

| What | Where |
| --- | --- |
| Allowance table and the WFH decide branch | `db/migrations/20261113000001_hr_ess_wfh_allowances.sql` (rollback in `db/rollbacks`) |
| HR's allowance routes, the employee's own reading | `apps/ess-api/src/routes/wfh.js` |
| The request type and the leave window | `apps/ess-api/src/routes/leaveRequests.js`, `src/policy/requests.js` |
| Store reads and writes | `apps/ess-api/src/lib/store.js` (`getWfhAllowance`, `listWfhAllowances`, `upsertWfhAllowance`, `countWfhDays`) |
| Contract | `packages/contracts/openapi.yaml` 0.13.0 |
| Tests | `apps/ess-api/tests/wfh.test.js`, `tests/helpers/wave11.js` |
