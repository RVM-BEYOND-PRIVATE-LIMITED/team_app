# Team RVM: project summary

Updated 16 Oct 2026.

## What it is

Team RVM is RVM CAD's Android app for every employee, modelled on the Keka employee app. It offers:
- punch in and out under the same rules as the web;
- requests and approvals;
- an Inbox with push notifications;
- a Wall: posts, reactions, praise, polls and announcements;
- a Helpdesk;
- Me and My Team.

The Scheduler (`scheduler.rvmcad.org`) stays the system of record. The app adds an employee self-service API (the ESS, at `/api/ess`) for everything new.

## Where the code lives

| Repository | Holds |
| --- | --- |
| **team_app** (this one, private) | The new backend `apps/ess-api` (separate service at `/api/ess`), the Flutter app `apps/rvm_team_app` (set up by the mobile developer), the OpenAPI contract and these docs |
| **Scheduler_Backend** | Every change to existing Scheduler code: security fixes, sign-in, punch and ping, new columns on existing tables, the nginx route for `/api/ess` |

The app calls the Scheduler directly for what already exists: sign-in, punch, calendar, holidays, priority tasks and the faculty views. It calls `/api/ess` for everything new, and one sign-in token works for both. See [ADR-0002](adr/0002-monorepo-is-team-app.md) to [ADR-0007](adr/0007-scheduler-changes-as-scheduler-prs.md).

## What exists and what is missing

This is the STEP 1 check against `c28b9ca` (15 Oct); the full table is in [02-reconciliation.md](02-reconciliation.md).

### Attendance is built

These already exist:
- sign-in for staff without a portal login (password, one-time code, HR's first-time password, lockout);
- punch with geofence, GPS accuracy, one phone per person, one session a day, shifts, the late and half-day rules and the midnight close;
- holidays, employee remarks, and HR's board and controls.

Still needed for the app:
- `server_now`, the day's note and HR's remark on the employee's own read (B1);
- a device-id header for native clients (B8);
- mocked-location refusal (B14);
- batched pings (B15);
- a lock for approved request days (B17).

### Everything Keka-like is missing

- the employee identity middleware, refresh tokens and capabilities (A);
- requests and leave (C);
- the approvals Inbox and push (D);
- self-service profile and My Team (E);
- the Wall (F);
- the Helpdesk (G).

### In numbers

105 items:
- 16 available;
- 5 verified;
- 30 to update;
- 53 to build;
- 1 operations step for RVM.

44 of them need Scheduler PRs: 25 only there, and 19 in both repositories.

## Security comes first

The check found holes the gap report missed. They are open in production today:
- **Phone-number takeover:** a phone number is enough to take over a portal account.
- **Committed password hashes:** a database dump with password hashes is committed to Scheduler_Backend.
- **Unguarded money writes:** approvals and payments on `/api/accounts` have no role check.
- **Branch-admin takeover:** a branch admin can take over elevated accounts in its branch.
- **Student tokens see too much:** they reach attendance writes and other students' password hashes.

[ADR-0012](adr/0012-security-first.md) fixes these first, before any Team RVM endpoint ships. Details are in [02-reconciliation.md](02-reconciliation.md).

## What RVM decided (16 Oct)

### How it is built

| Topic | Decision |
| --- | --- |
| Service | Separate service in JavaScript |
| Deploy and merging | Deploys automatically on merge to `main`; both developers may merge |
| Scope | Phases 1 and 2 this round |
| Existing features | The app calls the Scheduler directly |
| Flutter app | The mobile developer sets it up |
| Push | Writes to the log until a Firebase project exists |
| Old pings and logs | No purge job; KP deletes them by hand |

### How the app behaves

| Topic | Decision |
| --- | --- |
| Approvals | The reporting manager, with HR as fallback; HR, the CEO and super admins can decide any request |
| Tabs | Admin, Admin Manager and Finance Admin get all five |
| Mocked location | Refused |
| Location tracking | Continues with the screen off while punched in |
| Monthly limits | No work from home; on duty unlimited; fix a day 3; excuse a late 3; short leave 180 minutes; CL 1 |
| Payroll cut-off | The 5th of the next month |
| Colleague contacts | Email visible to everyone; phone only to the manager chain and HR |
| Wall | Everyone posts |
| Sign-in | One field |
| Phones moving to the app | HR bulk reset, branch by branch |
| HR Executive | HR's powers without attendance |

The full record, with sources, is in [03-decisions.md](03-decisions.md) and [adr/](adr/README.md).

## Still open

- **Proposals:** [ADR-0009](adr/0009-migrations.md) (where migrations live) and [ADR-0017](adr/0017-repository-layout-and-tooling.md) (folder layout and Node version).
- **Server:** which Node version the server runs.
- **Leave without pay:** whether it has a monthly limit.
- **The committed dump:** whether to remove `physical_dump_2026.sql` from Scheduler_Backend's history. That needs a force-push.
- **Production check (read-only):** confirm the attendance migrations `20261020000000` to `20261023000000` and the one-CL-a-month index are applied.
- **Brief re-export:** the live brief now has the fact-check corrections and the 16 Oct answers. Replace [the PDF in inputs/](inputs/).
- **Unconfirmed defaults:**
  - no offline punching;
  - no pay in the app;
  - Google Play from an organisation account;
  - brand colours on the punch button.

## Next steps

1. **STEP 2: the plan and the OpenAPI contract** (`packages/contracts/openapi.yaml`). The work order is security (J and the newly found holes), then identity (A), then Phase 1, then Phase 2. The plan also covers migrations with rollbacks and the risks. KP approves it before any code is written.
2. **STEP 3: the build.** Scheduler PRs ship first wherever the ESS depends on them. Every endpoint gets tests, including role-denied and wrong-owner cases.
3. **Phase 0, from RVM, alongside the build:**
   - a Firebase project;
   - a Google Play organisation account (needs a D-U-N-S number);
   - every HOD and HoO on the right role, and logins linked to HR records;
   - HR data: joining dates now, then date of birth, blood group and emergency contact once those fields exist;
   - a privacy and location policy with a named grievance officer;
   - the brand designer's master logo files.

## Where to find things

| File | What it covers |
| --- | --- |
| [01-inputs.md](01-inputs.md) | The brief, the gap report and the developer's prompt: what each says and what is out of date |
| [02-reconciliation.md](02-reconciliation.md) | Every task checked against the code, with file:line evidence |
| [03-decisions.md](03-decisions.md) | Product decisions and limits |
| [adr/](adr/README.md) | Architecture decisions |
| [inputs/](inputs/) | The original documents |
