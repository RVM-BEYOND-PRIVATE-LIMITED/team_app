# Team RVM: project summary

Updated 22 Oct 2026.

## What it is

Team RVM is RVM CAD's Android app for every employee, modelled on the Keka employee app. Attendance is at its core. It offers:
- punching in and out, under the same rules as the web;
- requests and approvals;
- an Inbox with push notifications;
- faculty class marking, with the Scheduler's own checks enforced server-side;
- a Wall: posts, reactions, praise, polls and announcements;
- a Helpdesk;
- Me and My Team.

The Scheduler (`scheduler.rvmcad.org`) stays the system of record. The app adds an employee self-service API, the ESS, for everything new.

## The ground rule

**Team RVM is its own app.** Nothing in Scheduler_Backend or Scheduler_frontend changes for it (KP, 16 Oct; [ADR-0018](adr/0018-team-app-changes-nothing-in-the-scheduler.md)). The Scheduler only supplies information and its existing endpoints, used as they are.

| Repository | Holds |
| --- | --- |
| **team_app** (this one, private) | Everything for Team RVM: the ESS backend, the Flutter app (set up by the mobile developer), the OpenAPI contract and these docs. The folder names (`apps/ess-api`, `apps/rvm_team_app`, `packages/contracts`) follow the layout proposed in [ADR-0017](adr/0017-repository-layout-and-tooling.md). |
| **Scheduler_Backend, Scheduler_frontend** | Unchanged. Used as a data source and through their existing endpoints. |

How the app works within that rule:
- **Existing features:** the app calls the Scheduler's existing endpoints directly. These are sign-in, punch, the calendar, holidays, priority tasks and the faculty views. One sign-in token works for both services ([ADR-0006](adr/0006-app-calls-scheduler-directly.md)).
- **New features:** they live in the ESS. It runs on its own subdomain on the same server ([ADR-0019](adr/0019-ess-on-its-own-subdomain.md)) and keeps its data in new `hr_ess_*` tables in the same database ([ADR-0021](adr/0021-migrations-new-tables-only.md)).
- **Approvals:** they write the official day through HR's existing override function ([ADR-0020](adr/0020-approvals-through-the-override-function.md)).

## What exists and what is missing

This is the STEP 1 check against `c28b9ca` (15 Oct). The full table is in [02-reconciliation.md](02-reconciliation.md).

### Attendance is built

These exist in the code at `c28b9ca`:
- sign-in for staff without a portal login (password, one-time code, HR's first-time password, lockout);
- punch with geofence, GPS accuracy, one phone per person, one session a day, shifts, the late and half-day rules, and the midnight close;
- holidays, employee remarks, and HR's board and controls.

B5 and B9–B12 are live in production only if migrations `20261020000000` to `20261023000000` have been applied, which is still to be confirmed.

### Everything Keka-like is missing

- the employee identity check, refresh tokens and capabilities (A);
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
- 53 missing, of which 52 will be built (K5, the purge job, is dropped by [ADR-0015](adr/0015-no-automated-retention.md));
- 1 operations step for RVM.

Items whose fix sits in Scheduler code are out of scope under the ground rule. [04-build-plan.md](04-build-plan.md) lists how team_app works around each one, or why it is left out.

## The Scheduler's open security holes

STEP 1 found holes the gap report missed, and others wider than it said (J1, J2, J5). They are open in production today:
- **Phone-number takeover.** A phone number is enough to reset any portal account without two-factor sign-in, and to lock the owner out of one that has it.
- **Unguarded money writes.** Approvals and payments on `/api/accounts` have no role check.
- **Branch-admin takeover.** A branch admin can take over elevated accounts in its branch.
- **Student tokens see too much.** Besides the attendance writes (J1) and roster hashes (J2), they reach `GET /api/students` and the batch replies with password hashes, admissions with phones and dues, and the alerts.
- **Leaving keeps access.** Nothing on exit touches the `users` row.
- **A committed dump.** `physical_dump_2026.sql` is still in Scheduler_Backend's current tree. It holds password hashes and Supabase sessions and refresh tokens.

Fixing any of them means changing the Scheduler, which this project doesn't do. They are written up in [02-reconciliation.md](02-reconciliation.md) for KP to handle separately if KP chooses.

## What RVM decided (16 Oct)

### How it is built

| Topic | Decision |
| --- | --- |
| Scheduler | Unchanged; information and existing endpoints only |
| Service | Separate, in JavaScript, on its own subdomain |
| Data | New `hr_ess_*` tables in the same database |
| Punching | Through the Scheduler's existing punch API |
| Approvals | Through HR's existing override function |
| Deploy and merging | Deploys on merge to `main`, behind a switch; both developers may merge |
| Scope | Phases 1 and 2 this round |
| Flutter app | The mobile developer sets it up |
| Push | Writes to the log until a Firebase project exists |
| Old pings and logs | No purge job; KP deletes them by hand |

### How the app behaves

| Topic | Decision |
| --- | --- |
| Approvals | The reporting manager, with HR as fallback. HR (the `hr` role), the CEO and super admins can decide any request. |
| Tabs | Admin, Admin Manager and Finance Admin get all five |
| Mocked location | Refused on the phone |
| Location tracking | Continues with the screen off while punched in, and stops at punch-out, shift end plus grace, or midnight |
| Monthly limits | No work from home; on duty unlimited; fix a day 3; excuse a late 3; short leave 180 minutes; CL 1 |
| Payroll cut-off | The 5th of the next month |
| Colleague contacts | Email visible to everyone; phone only to HR and the person's managers |
| Wall | Everyone posts |
| Sign-in | One field |
| Phones moving to the app | HR bulk reset, branch by branch |
| HR Executive | HR's powers without attendance or leave: approves documents, profile changes and HR helpdesk tickets, never attendance or leave requests |

The full record, with sources, is in [03-decisions.md](03-decisions.md) and [adr/](adr/README.md).

## Still open

- **Layout:** [ADR-0017](adr/0017-repository-layout-and-tooling.md) (folder layout, workspaces, Node version), and which Node version the server runs.
- **Decisions owed:** the points in [04-build-plan.md](04-build-plan.md#decisions-still-owed) (the phone reset, the HR Executive as manager, staying signed in, desk logins and faculty class marking were decided on 16 and 19 Oct). Open: faculty leave, short leave and half days, mocked pings, the contact rule, the cut-off edge cases, where HR reviews on the web, and the infra register (decision 9).
- **Leave without pay:** whether it has a monthly limit.
- **Production check (read-only):** confirm that the attendance migrations and the one-CL-a-month index are applied.
- **Brief re-export:** the fact-check corrections and the 16 Oct answers are in the live brief. KP re-exports it and replaces [the PDF in inputs/](inputs/).
- **Unconfirmed defaults:**
  - no offline punching;
  - no pay in the app;
  - Google Play from an organisation account;
  - brand colours on the punch button;
  - only HR, the CEO and super admins see the location trail;
  - shared desk logins can't use the app.

## Next steps

1. **Wave 1 and Wave 2 are live; Phases 1C to 1E are deployed; Phases 2A to 2D are built and deployed (19 Oct); H1 class marking and G6 the infra-register mirror are built (22 Oct).** The ESS has answered at `https://team-api.rvmcad.org` since 16 Oct, deployed on every merge to `main` ([05-deploy.md](05-deploy.md)). KP has applied migrations 13 to 26; **27, G6's link table, is the only migration still to apply** - until then the mirror is skipped and retried, and tickets are unaffected. The pilot gate is next; what is left is listed phase by phase in [06-backend-phases.md](06-backend-phases.md).
2. **Waves 2 to 4 are complete for the backend:** Phases 1C, 1D, 1E, 2A, 2B, 2C and 2D are built and deployed, all in team_app, with tests for every endpoint, including role-denied and wrong-owner cases; H1 class marking (decision 8) adds three routes over the Scheduler's own `student_attendance` and `pending_alerts` rows, and G6 (decision 9) mirrors lab and facility tickets into the Admin Manager's `infra_tickets`, linked by `hr_ess_infra_links`. What remains: apply the outstanding migrations, the pilot gate, and one open build decision (3, short leave and half days).
3. **Phase 0, from RVM, alongside the build:**
   - a Firebase project;
   - a Google Play organisation account (it needs a D-U-N-S number);
   - every HOD and HoO on the right role, and logins linked to HR records;
   - HR data: joining dates now, plus the main phone and email checked for every employee, then personal details once the screen exists;
   - a privacy and location policy that names a grievance officer;
   - the brand designer's master logo files.

## Where to find things

| File | What it covers |
| --- | --- |
| [01-inputs.md](01-inputs.md) | The brief, the gap report and the developer's prompt: what each says and what is out of date |
| [02-reconciliation.md](02-reconciliation.md) | Every task checked against the code, with file:line evidence |
| [03-decisions.md](03-decisions.md) | Product decisions and limits |
| [04-build-plan.md](04-build-plan.md) | The build: waves, out-of-scope items, decisions owed, risks |
| [05-deploy.md](05-deploy.md) | Deploying the ESS, step by step, and switching it off |
| [06-backend-phases.md](06-backend-phases.md) | The backend work left, phase by phase |
| [adr/](adr/README.md) | Architecture decisions |
| [inputs/](inputs/) | The original documents |
