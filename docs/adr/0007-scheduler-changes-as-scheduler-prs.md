# ADR-0007: Changes to existing Scheduler code ship as Scheduler PRs

- Status: Superseded by [ADR-0018](0018-team-app-changes-nothing-in-the-scheduler.md) (16 Oct 2026). Team RVM makes no Scheduler PRs. This ADR is kept as the record of where each fix would sit in the Scheduler's code.
- Date: 16 Oct 2026
- Decided by: KP
- Source: Follows from [ADR-0002](0002-monorepo-is-team-app.md), [ADR-0005](0005-separate-ess-service.md) and [ADR-0006](0006-app-calls-scheduler-directly.md)

## Context

Many gap-report tasks change code that exists only in Scheduler_Backend, for example:
- the security fixes;
- the punch and ping changes;
- the daily-sheet lock;
- new columns on `hr_employees` and `hr_staff_attendance`;
- the nginx block.

## Decision

- **Scheduler changes go to Scheduler_Backend.** Any work that edits its existing routes, controllers, jobs, middleware or tables goes there as normal PRs:
  - Branch from `origin/main` in a separate worktree, because another agent session works in that checkout.
  - Stage files by name.
  - Its CI (migration lint, then the tests on its Docker stack) must pass.
- **New-only work goes to team_app.** Work that only adds new endpoints and new tables goes in team_app.
- **Each task is labelled.** [02-reconciliation.md](../02-reconciliation.md) marks where each task lands.

## Which tasks these are

The STEP 1 check ([02-reconciliation.md](../02-reconciliation.md)) found three groups.

**Scheduler PRs only (25):**
- **Identity:** A6, A7, A9.
- **Attendance:** B1, B8, B14, B15, B17.
- **Requests:** C9, C11.
- **Profile:** E9.
- **Role views:** H1, H2, H3.
- **Security:** J1–J6, J8, and the /api/dashboard fix.
- **Infrastructure:** K1, K4, K5. K4 is the same work as A6, and K5 won't be built.

**Both repositories (19):**
- **Identity:** A5, A10.
- **Requests:** C1, C3, C7.
- **Inbox and push:** D6, D7.
- **Profile:** E4, E6, E8, E11.
- **Wall:** F9.
- **Helpdesk:** G6.
- **Role views:** H5, H7.
- **Data model:** I.
- **Security:** J7, J9.
- **Infrastructure:** K6.

**Not in the gap report, also Scheduler PRs:**
- the money-write role checks on `/api/accounts`;
- the `updateUser` target-role check;
- the `/api/alerts`, `/api/users`, `/api/faculty` and `/api/students` exposures;
- removing the legacy `/api/chat/:ticketId` routes;
- ending portal access at exit;
- the C11 faculty-leave bug, which is live today.

## Consequences

- A merge to Scheduler_Backend `main` deploys to production. So the Scheduler change ships before the ESS code that needs it.
- Before changing a Scheduler endpoint, check its other clients: the web, the flutterapps staff and student apps, and the student portal.
