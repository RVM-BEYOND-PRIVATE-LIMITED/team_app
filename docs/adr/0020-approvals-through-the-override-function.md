# ADR-0020: Approvals write the official day through HR's override function

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's answer of 16 Oct 2026, "Yes, via HR's override"

## Context

The official attendance record is `hr_staff_attendance`, one row per employee per day. HR changes a day through `hr_attendance_apply_override` (migration `20261020000000`). That function:
- locks the day's row;
- writes it with source `override`, which locks it against the Admin Manager's daily sheet and later punches;
- stores the reason as the day's note;
- logs the before and after values in `hr_attendance_overrides`.

The function itself checks nothing about the day or the status. The Scheduler's override controller adds the checks around it:
- only the six statuses are allowed;
- only leave may be written for a future day;
- the one-CL-a-month check runs first;
- the month is recomputed afterwards.

## Decision

1. **Approved days go through the override function.** When a leave (CL or leave without pay), a fix-a-day or an on-duty request is approved, the ESS writes that day through `hr_attendance_apply_override` with the service key.
   - The approver is recorded by name.
   - `p_by` is the approver's `users.id` when they have a portal login, and null otherwise.
2. **The ESS makes the controller's checks itself before each call.**
   - the six statuses;
   - no future day except leave;
   - the one-CL-a-month rule;
   - the reach-back window and the cut-off on the 5th.

   After the call, it re-runs `hr_attendance_recompute` for the month, as the controller does.
3. **On-duty days.** An approved on-duty day is written as present, with a note naming the place. The person does not need to punch that day: waiving the geofence would be a Scheduler change.
   - A day that hasn't happened yet is written on the morning of that day by an ESS job, because the function would otherwise lock a future day.
4. **Excused lates.** Approving an excuse-a-late writes the same fields the Scheduler's own excuse-late action writes (`late_excused`, `late_excused_by`, `late_excused_reason`, `late_excused_at`), then re-runs `hr_attendance_recompute`.
5. **Cancelling.** HR cancelling an approved request restores the before-row kept in the override log, through the same function.
6. **History.** Every decision is also recorded in the ESS's own request history.

## Consequences

- **HR sees approvals where it already looks.** An approved day appears in HR's existing override history, with the request's reason as the note. The day is locked against the daily sheet, as the brief requires, and no new Scheduler screen is needed.
- **Unlinked approvers aren't named in the log.** Override rows reference `users.id`, so an approver without a portal login appears by name only.
- **The CL index may be missing.** If the one-CL-a-month index doesn't exist in production, the ESS serialises CL approvals per employee and month, so two approvals can't both pass.
- **Short leave (Phase 2)** excuses the late it covers. The rule "lateness inside the window is not counted" would need a change to `hr_attendance_recompute`, which is out of scope ([ADR-0018](0018-team-app-changes-nothing-in-the-scheduler.md)).
