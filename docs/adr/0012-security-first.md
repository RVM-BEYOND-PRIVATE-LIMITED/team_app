# ADR-0012: Security rules for everything team_app builds

- Status: Accepted. Amended by [ADR-0018](0018-team-app-changes-nothing-in-the-scheduler.md) on 16 Oct 2026: the Scheduler fixes this ADR first put at the front of the work (section J) are out of scope. The rules for new routes stand.
- Date: 16 Oct 2026
- Decided by: KP
- Source: the developer's prompt of 16 Oct 2026, STEP 2 ("security fixes first (section J), then identity and session (A), then Phase 1 features, then the rest") and its security rules; KP's messages of 16 Oct 2026 keeping the Scheduler unchanged

## Decision

- **Order of work in team_app:**
  1. identity and session (section A);
  2. Phase 1;
  3. Phase 2.

  The section J fixes are changes to Scheduler code, so they are no longer part of this project ([ADR-0018](0018-team-app-changes-nothing-in-the-scheduler.md)).
- **Every new route** needs `auth` (or `employeeAuth`) plus a role or ownership check. Its tests include a role-denied case and a wrong-owner case.
  - Two kinds of route must work before sign-in: the sign-in resolver (A5) and the health and minimum-app-version endpoint (K2).
  - These two are rate-limited and reveal nothing about accounts.
- **Never returned:** password hashes, storage paths and full Aadhaar numbers.
- **401** is only for an absent or rejected token.

## The Scheduler's open holes

STEP 1 found these, listed in [02-reconciliation.md](../02-reconciliation.md) under "Security holes that are open today":
- a phone number is enough to reset a portal account's password;
- money writes with no role check;
- a branch admin can take over elevated accounts;
- student tokens reach staff data;
- leaving the company does not end portal access;
- a committed database dump.

They are live in the Scheduler and stay open, because fixing them means changing the Scheduler. KP decides whether and when to fix them, outside this project.

## Consequences

- **Releasing while the holes are open is KP's call.** The app adds no new hole, but it relies on Scheduler endpoints that still have them.
- **Play Integrity (J9)** is built but stays off until a Play project exists ([ADR-0016](0016-push-and-integrity-start-off.md)).
- **Faculty class marking in the app (Phase 2)** would run on `POST /api/attendance`, which has no server-side checks on who may mark which batch, or on which dates (J1). KP decides before Phase 2 whether the app offers it.
