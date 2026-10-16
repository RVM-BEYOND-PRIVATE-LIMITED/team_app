# Build plan (STEP 2)

KP started the build on 16 Oct 2026 ("start the backend now"). The same day KP set the ground rule: **Team RVM changes nothing in Scheduler_Backend or Scheduler_frontend** ([ADR-0018](adr/0018-team-app-changes-nothing-in-the-scheduler.md)).

- Everything below is built in team_app.
- The Scheduler is used exactly as it is: its endpoints as a client, its database through the paths in [ADR-0020](adr/0020-approvals-through-the-override-function.md).
- Nothing is pushed, merged or deployed without KP's OK.

Task IDs refer to [02-reconciliation.md](02-reconciliation.md).

## Wave 1: the foundation (in progress)

**Branch:** `feat/ess-foundation` in team_app.

| What | Tasks |
| --- | --- |
| npm workspace scaffold | |
| Employee identity (`employeeAuth`), accepting the Scheduler's portal and attendance tokens | A1 |
| `GET /api/ess/health` | K2 |
| `GET /api/ess/me` | |
| `GET /api/ess/me/capabilities` | A4 |
| The OpenAPI contract, including the Scheduler's existing sign-in and punch endpoints | |
| CI on Node 20 and 24 | |
| A deploy workflow behind `ESS_DEPLOY_ENABLED` | K3 (Firebase key checks) |

**Next in Wave 1:** the deploy serves the ESS on its own subdomain ([ADR-0019](adr/0019-ess-on-its-own-subdomain.md)).
- It writes its own nginx file and gets a certificate with certbot.
- It enables the file only after `nginx -t` passes.
- It restarts only its own pm2 process.

**Stopped and removed on 16 Oct:** four Scheduler security branches, a login-page change and an nginx route in the Scheduler's deploy. The holes they would have fixed are still open ([02-reconciliation.md](02-reconciliation.md)).

## Wave 2: identity and the attendance extras

| Work | How, with no Scheduler change | Tasks |
| --- | --- | --- |
| Refreshable app session | Detailed below the table | A3 |
| One-field sign-in | An ESS resolver. A portal account found by email or employee code is asked for its username or login phone, because portal login accepts only those | A5 |
| Per-employee rate limits | ESS middleware, for ESS endpoints | A6 (ESS side) |
| Request to correct or delete my data | ESS table, plus HR's list | A8 |
| Shared desk logins kept out | An ESS list of shared logins, checked at sign-in exchange and by `employeeAuth` | A10 |
| `server_now`, the day's note and HR's remark | An ESS endpoint that reads the same rows the punch screen shows | B1 |
| Mocked location | Refused on the phone. Reported to an ESS table that HR can read | B14 |
| HR bulk phone reset, branch by branch | An ESS action for HR that writes the same device rows the Scheduler's own reset writes (KP to confirm) | B8 |
| Personal details (date of birth, blood group, address, emergency contact) | An ESS table keyed to `hr_employees.id` | E9 |

The refreshable session (A3) works like this:
1. The app exchanges a fresh Scheduler token for a rotating refresh token, bound to the install. Its hash is stored in `hr_ess_sessions`.
2. Short access tokens are minted in the Scheduler's existing formats, so the punch path accepts them unchanged.
3. The session is revoked when:
   - the attendance password changes (`sessions_valid_from`);
   - HR switches the login off;
   - the employee leaves.

## Wave 3: Phase 1 features

### Requests and leave (C)

- **Tables.** The request tables and their history are new `hr_ess_*` tables ([ADR-0021](adr/0021-migrations-new-tables-only.md)).
- **Writing the day.** An approval writes the official day through `hr_attendance_apply_override` ([ADR-0020](adr/0020-approvals-through-the-override-function.md)). Before the call, the ESS enforces the rules the Scheduler enforces around that function:
  - the statuses;
  - the future-day rule;
  - one CL a month;
  - the reach-back window and the cut-off on the 5th.

  After the call, it recomputes the month.
- **On duty.** The day is written as present, on the day itself.
- **Excuse a late.** Writes the same fields as HR's excuse.
- **Withdraw and cancel.** A pending request can be withdrawn. HR cancels an approved one by restoring the logged before-row.
- **Approver resolution.** The manager on the HR record, then HR. "HR" means the `hr` role for attendance and leave, never HR Executive.

### Inbox, notifications and push (D)

- the approvals Inbox;
- push devices in `hr_ess_devices`;
- notifications in `hr_ess_notifications`, with unread counts;
- the push worker in log-only mode ([ADR-0016](adr/0016-push-and-integrity-start-off.md));
- categories and quiet hours.

### Me and My Team (E)

- profile Summary and Job;
- the reporting chain, keeping people on notice with a chip;
- the directory, with the contact rule;
- team today and off this week, including the HoO's view (H4);
- photos as signed links.

## Wave 4: Phase 2 features

- the Wall (F1–F9);
- the Helpdesk (G1–G5);
- profile-change requests and documents (E3, E4);
- the ID card (E7);
- celebrations (F6);
- multi-level approvals (D4);
- short leave (by excusing the late it covers);
- light KPI reads (H5);
- the faculty "my day" read (H7).

The decisions listed below shape several of these.

## Out of scope: each needs a Scheduler change

These were in the gap report or found in STEP 1. They stay as they are unless KP decides to change the Scheduler separately.

- **Security:** the J1–J8 fixes and the other open holes. These include the phone-only password reset, the money writes, student tokens reaching staff data, the committed database dump, and portal access that survives leaving.
- **Sessions and limits:** portal "sign out everywhere" (A7) and per-employee limits on Scheduler endpoints (A6, K4).
- **Punch path:**
  - server-side mock refusal (B14);
  - batched pings (B15);
  - a device-id header (part of B8);
  - the purge job (K5, also dropped by [ADR-0015](adr/0015-no-automated-retention.md)).
- **Attendance bugs:**
  - the faculty-leave bug (C11);
  - the web org chart's notice-period fault (E11, web side);
  - the remarks endpoint's faults (B5);
  - the Admin Manager's branch-wide read (B16).
- **Role views:** H1–H3, and the short-leave rule inside `hr_attendance_recompute`.
- **Attendance-only staff:** priority tasks and the interview calendar for them, because both are tied to portal logins.
- **The web:** HR review queues and a Helpdesk tab inside the web HRMS (E5, G5 web side), since the web stays unchanged.

## Decisions still owed

1. [ADR-0017](adr/0017-repository-layout-and-tooling.md): folder layout, workspaces and Node version. The foundation already uses this layout; KP to confirm it.
2. **Faculty leave.** Does ESS leave replace `/api/am/leave` for faculty, or run alongside it?
3. **Short leave and half days.** Do planned early-leaving minutes protect a day from the 4-hour half-day rule?
4. **Mocked pings.** Are they reported to HR like mocked punches?
5. **Colleague contacts.** Does an employee also see their own managers' phone numbers?
6. **Cut-off.** Is the 5th itself open? Can a pending request for last month be decided after the cut-off?
7. **Phone reset.** Does the HR bulk phone reset write the device rows the Scheduler's reset writes?
8. **HR's web tools.** Where do HR review change requests and documents, and where do helpdesk agents work on the web? The brief put these in the web HRMS, which now stays unchanged. The options are the app itself, or a small web page served by team_app.
9. **Faculty marking.** Should the app offer class-attendance marking while the Scheduler's checks on it (J1) stay open?
10. **Infra register.** Should lab and facility helpdesk tickets also add a row to the Admin Manager's infra register? That writes a Scheduler table.
11. **The Scheduler's own holes and the committed dump.** These are outside this project, and KP's call.

## Migrations, in run order

None yet. Wave 1 needs no table. From Wave 2 on, every migration is listed here with its rollback script ([ADR-0021](adr/0021-migrations-new-tables-only.md)). KP applies each one by hand, and an agent checks it read-only afterwards.

## Risks

- **Token formats.**
  - The ESS verifies the Scheduler's tokens, and from A3 it also mints them, using the shared `JWT_SECRET`. If the Scheduler's signing code changes, the ESS breaks. The ESS tests copy that signing code, so a drift fails the tests first.
  - Rotating `JWT_SECRET` signs everyone out of both services.
- **Schema coupling.** The ESS reads Scheduler tables, so a Scheduler migration that renames a column breaks it. Keep the schema snapshot used by the tests current.
- **Shared nginx.** A broken team_app nginx file would block the Scheduler's deploys. The ESS deploy tests before enabling ([ADR-0019](adr/0019-ess-on-its-own-subdomain.md)).
- **Deploys before migrations.** Merges deploy before KP applies migrations, so new endpoints answer 503 until their tables exist ([ADR-0021](adr/0021-migrations-new-tables-only.md)).
- **Production state unconfirmed.** Whether the attendance migrations (`20261020000000` to `20261023000000`) and the one-CL index are applied in production is not confirmed. Check, read-only, before Wave 3 relies on them.
- **Open holes.** The Scheduler's holes stay open while the app ships. Whether to release anyway is KP's decision.
- **Another agent session.** It works in the Scheduler repositories. team_app work never touches them, and reads only from detached read-only copies.
