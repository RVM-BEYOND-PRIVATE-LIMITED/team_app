# ADR-0018: Team RVM changes nothing in the Scheduler

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's messages of 16 Oct 2026, "this scheduler front end will stay as it is and scheduler backend will only help team app with information" and "this is exclusive team app, dont do anything to scheduler backend and schedular frontend"
- Supersedes: [ADR-0007](0007-scheduler-changes-as-scheduler-prs.md). Amends [ADR-0005](0005-separate-ess-service.md) (see [ADR-0019](0019-ess-on-its-own-subdomain.md)), [ADR-0009](0009-migrations.md) (see [ADR-0021](0021-migrations-new-tables-only.md)) and [ADR-0012](0012-security-first.md).

## Context

STEP 1 found 44 tasks whose fix sits in Scheduler code, so the first plan routed them through Scheduler PRs. The work had started:
- four Scheduler security branches;
- a login-page change;
- an nginx route for the new service.

KP stopped all of it. The branches were deleted, and the Scheduler repositories were left as they were.

## Decision

- **No changes to the Scheduler repositories.** Nothing in Scheduler_Backend or Scheduler_frontend changes for Team RVM: no code, branches, PRs, deploy or nginx edits, and no migration that alters a table the Scheduler owns.
- **The Scheduler is a data source and an unchanged service.**
  - The app calls the Scheduler's existing endpoints as they are: sign-in, punch, calendar, holidays, priority tasks and the faculty views.
  - The ESS reads the Scheduler's tables. It writes them only where a decision says so, and then only through the Scheduler's own database functions or the same rows the Scheduler's own HR tools write (see [ADR-0020](0020-approvals-through-the-override-function.md)).
- **Everything new is built in team_app.** If a need can only be met by changing the Scheduler, it is either redesigned in team_app or recorded as out of scope.

## Consequences

**The Scheduler's security holes stay open.** STEP 1 found them, and they are reported but not fixed. The list is in [02-reconciliation.md](../02-reconciliation.md), for KP to handle separately if KP chooses.

**Out of scope, because each needs a Scheduler change:**
- **Security:** the J1–J8 fixes and the other holes STEP 1 found, including retiring the old password reset (A9).
- **Sessions and limits:**
  - per-employee rate limits on Scheduler endpoints (A6, K4);
  - portal "sign out everywhere" (A7);
  - ending portal access when someone leaves.
- **Punch and ping:**
  - server-side refusal of mocked locations (B14);
  - batched pings (B15);
  - the device-id header (part of B8).
- **Attendance bugs and view fixes:**
  - the faculty-leave bug (C11);
  - the notice-period fix in the web org chart (E11);
  - H1–H3;
  - the short-leave rule inside `hr_attendance_recompute`.
- **Access for attendance-only staff:** priority tasks and the interview calendar, which are tied to portal logins.

**Redesigned inside team_app:**

| Need | How team_app meets it |
| --- | --- |
| The extras from B1: `server_now`, the day's note and HR's remark | The ESS reads them from the database and serves them itself |
| Personal details (date of birth, blood group, address, emergency contact; E9) | An ESS table keyed to `hr_employees.id`, not new `hr_employees` columns |
| Approvals | Through the override function ([ADR-0020](0020-approvals-through-the-override-function.md)) |
| HR's bulk phone reset | An ESS action for HR that writes the same device rows the Scheduler's own reset writes. KP to confirm. |
| Mocked locations | Refused on the phone; the app reports them to the ESS for HR |
| Short leave | Handled by excusing the late it covers |

**Faculty class attendance needs a decision first.** In the app (Phase 2), it would run on `POST /api/attendance`, which keeps its missing server-side checks (J1). KP decides before Phase 2 whether the app offers it.
