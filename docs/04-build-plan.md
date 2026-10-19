# Build plan (STEP 2)

KP started the build on 16 Oct 2026 ("start the backend now"). The same day KP set the ground rule: **Team RVM changes nothing in Scheduler_Backend or Scheduler_frontend** ([ADR-0018](adr/0018-team-app-changes-nothing-in-the-scheduler.md)).

- Everything below is built in team_app.
- The Scheduler is used exactly as it is: its endpoints as a client, its database through the paths in [ADR-0020](adr/0020-approvals-through-the-override-function.md).
- Finished work is pushed to `main` as it passes its lint and tests (KP, 16 Oct). Turning on deploys (`ESS_DEPLOY_ENABLED`) and running migrations still wait for KP's OK.

Task IDs refer to [02-reconciliation.md](02-reconciliation.md). [06-backend-phases.md](06-backend-phases.md) puts the same work in the order KP runs it, phase by phase (Wave 1 is phase 1A, Wave 2 is 1B, Wave 3 is 1C to 1E, Wave 4 is 2A to 2D).

## Wave 1: the foundation (on `main`, 16 Oct)

**Branch:** `feat/ess-foundation` in team_app, pushed to `main`.

| What | Tasks |
| --- | --- |
| npm workspace scaffold | |
| Employee identity (`employeeAuth`), accepting the Scheduler's portal and attendance tokens | A1 |
| `GET /api/ess/health` | K2 |
| `GET /api/ess/me` | |
| `GET /api/ess/me/capabilities` | A4 |
| The OpenAPI contract, including the Scheduler's existing sign-in and punch endpoints | |
| CI on Node 20 and 24, with the contract lint, shellcheck and the nginx cases | |
| A deploy workflow behind `ESS_DEPLOY_ENABLED` | K3 (Firebase key checks) |
| The ESS on `team-api.rvmcad.org`, with its own nginx file and certificate ([ADR-0019](adr/0019-ess-on-its-own-subdomain.md)) | K1 (its upload limit) |
| A read-only server check, run by hand | |

**Still to do for Wave 1:** KP runs the server check, then turns on `ESS_DEPLOY_ENABLED` for the first deploy ([05-deploy.md](05-deploy.md)).

**Stopped and removed on 16 Oct:** four Scheduler security branches, a login-page change and an nginx route in the Scheduler's deploy. The holes they would have fixed are still open ([02-reconciliation.md](02-reconciliation.md)).

## Wave 2: identity and the attendance extras (built, 16 Oct)

**Branch:** `feat/ess-wave2` in team_app, merged from `wave2/sessions` (A3, A5) and `wave2/data` (A8, E9, B1, B14, B8). Not pushed. Every endpoint is in the contract (version 0.2.1) and answers 503 `MODULE_NOT_INSTALLED` until its migration is applied ([Migrations, in run order](#migrations-in-run-order)).

**A rule for every ESS endpoint:** `employeeAuth` refuses an attendance session still on HR's first-time password with 403 `PASSWORD_CHANGE_REQUIRED`, as the Scheduler's challenge, punch and ping do (since 16 Oct, after the pre-deploy review). HR can give a whole batch one first-time password, and the employee code is on the ID card, so such a session proves nothing about who holds the phone. The app sends the person to the Scheduler's "Choose your own password" first.

| Work | How, with no Scheduler change | Tasks | State |
| --- | --- | --- | --- |
| Refreshable app session | Detailed below the table | A3 | Built: `POST /api/ess/session`, `/session/refresh`, `/session/sign-out`, `GET /api/ess/sessions`, `DELETE /api/ess/sessions/:id` |
| One-field sign-in | An ESS resolver. A portal account found by email or employee code is asked for its username or login phone, because portal login accepts only those | A5 | Built: `POST /api/ess/sign-in/resolve` |
| Per-employee rate limits | ESS middleware, for ESS endpoints | A6 (ESS side) | Built (Wave 1), with tighter buckets on the session, sign-in and report endpoints |
| Request to correct or delete my data | ESS table, plus HR's list | A8 | Built: `POST`, `GET /api/ess/me/data-requests`; `GET /api/ess/hr/data-requests`, `PATCH /api/ess/hr/data-requests/:id` |
| Shared desk logins kept out | Nothing to build. KP, 16 Oct: no desk logins are allowed at all, so there is no list to keep. A portal login with no linked HR record is already refused (403 `NOT_LINKED`) | A10 | Nothing to build |
| `server_now`, the day's note and HR's remark | An ESS endpoint that reads the same rows the punch screen shows | B1 | Built: `GET /api/ess/attendance/day` |
| Mocked location | Refused on the phone. Reported to an ESS table that HR can read (punches only; pings still open) | B14 | Built: `POST /api/ess/attendance/mock-location`, `GET /api/ess/hr/mock-location-reports` |
| HR bulk phone reset, branch by branch | An ESS action for HR that writes the same device rows the Scheduler's own reset writes (KP, 16 Oct: yes) | B8 | Built: `GET /api/ess/hr/devices`, `POST /api/ess/hr/devices/reset` |
| Personal details (date of birth, blood group, address, emergency contact) | An ESS table keyed to `hr_employees.id` | E9 | Built: `GET`, `PUT /api/ess/me/personal`; `GET`, `PUT /api/ess/hr/employees/:id/personal` |

**For KP to confirm, from the build:**
- A portal password change ends a kept sign-in (in the list below).
- Refresh tokens are kept as an HMAC under a key derived from `JWT_SECRET`, not a plain hash, so rotating the secret ends kept sign-ins as the documented rule says.
- The one-field sign-in answers `unknown` for a desk login, a leaver's login and a non-staff account, and `{ kind: "attendance", methods: [] }` for a person whose attendance login is off or missing.
- Personal details and data requests are for `hr`, `hr_executive` and `super_admin`. The Scheduler's own HR set also has the CEO (`config/hrPolicy.js:25-30`); the ESS leaves the CEO out because these are the most personal fields held. One line in `src/policy/hrAccess.js` adds the CEO.
- An employee sees the note on their own day (`hr_staff_attendance.note`), which can hold HR's override reason (02-reconciliation.md, B1).

The refreshable session (A3) works like this (KP, 16 Oct: access tokens last 1 hour, the sign-in 90 days from its last use):
1. The app exchanges a fresh Scheduler token (signed in within the last 10 minutes) for a rotating refresh token, bound to the install. Its hash is stored in `hr_ess_sessions`.
2. Short access tokens are minted in the Scheduler's existing formats, so the punch path accepts them unchanged.
3. Every minted token carries the ORIGINAL sign-in's time as its `iat`, never the time it was minted. The Scheduler lets a code sign-in set the attendance password for 15 minutes after its `iat`, and ends sessions older than a password change; a fresh `iat` would defeat both.
4. The session is revoked when:
   - the attendance password changes (`sessions_valid_from`);
   - HR switches the login off;
   - the employee leaves;
   - the person signs out, or a used refresh token is presented again (all of that sign-in's tokens end).
   - Added in the build, for KP to confirm: the portal password changes, by any of the Scheduler's five ways. Only two of them stamp `users.password_changed_at` (the profile page's change and forgot-password: `profileController.js:271-274`, `authSecurityController.js:176-179`); an admin's reset in User Management, `POST /users/change-password` and the legacy `POST /users/reset-password` write `password_hash` alone (`userController.js:1022-1031`, `1313-1318`, `1231-1236`). So the ESS checks both: the stamp, and a fingerprint (SHA-256) of `users.password_hash` that the database takes when the sign-in is kept and compares at every refresh, without the hash or the fingerprint ever leaving it. The Scheduler never checks either, so without this a portal password somebody else learned would stay good for as long as they kept refreshing, after its owner changed it. The one change it cannot see is one made by those three paths in the ten minutes between a sign-in and its trade.
5. One Scheduler sign-in is kept once. A second trade of the same token, by anybody, is 409 `ALREADY_EXCHANGED`, so a copy of a fresh token cannot start a second 90-day sign-in beside the app's (the review of 16 Oct).

## Wave 3: Phase 1 features

### Phase 1C: requests, leave and approvals — built 19 Oct 2026

The brief's Phase 1 core and the largest single piece of the ESS. Built to this plan, tested, and
waiting for its migrations (6 to 10 below). Everything is in `apps/ess-api` and
`db/migrations/20261106000000` to `20261106000004`.

| Work | How, with no Scheduler change | Tasks | State |
| --- | --- | --- | --- |
| Request tables and their history | `hr_ess_attendance_requests` (on duty, fix a day, excuse a late) and `hr_ess_leave_requests` (CL, LWP), each with a history table; a 'filed' row is written by the database trigger as the request goes in | C1 | Built |
| Filing, listing, withdrawing | `POST`/`GET /api/ess/attendance-requests` and `/leave-requests`; `POST /…/{id}/withdraw` (pending only; somebody else's is 404) | C1–C4, C8 | Built |
| The month's counter | `GET /api/ess/leave/balances` — allowed, used, pending and remaining per type, for this month or last; each create checks it before the row goes in (409 `LIMIT_REACHED`) | C5 | Built |
| The limits HR owns | `hr_ess_request_limits`, seeded with KP's numbers, read by every form and editable through `GET`/`PUT /api/ess/hr/request-limits` (`hr`, CEO, super admins; HR Executive excluded). A `PUT` is audited | C6 | Built |
| One decision function per family | `hr_ess_decide_attendance_request` and `hr_ess_decide_leave_request`: lock the request, re-check its status, the window, the future-day rule, the cut-off and the one-CL rule, write the day through `hr_attendance_apply_override` (or excuse the late in place), write status and history — one transaction. A second decision is 409 `ALREADY_DECIDED` | C7, C9 | Built |
| The on-duty morning job | `hr_ess_on_duty_apply`, called by `src/jobs/onDuty.js` at boot and hourly: an approved on_duty day with no row yet is written present, note `On duty: <place>`, on the day itself; idempotent, failures logged for HR (pm2 + `hr_ess_audit` as `on_duty.failed`) | C3, C7 | Built |
| Cancel after approval | `POST /api/ess/hr/attendance-requests/{id}/cancel` and `/hr/leave-requests/{id}/cancel`: only an approved request, HR's roles only; the day is restored from the row kept before the approval (or removed when the approval created it); audited | C8 | Built |
| Approver and Inbox | `GET /api/ess/approvals`: a manager sees their direct reports' pending requests (attendance sign-in included); HR/CEO/super admins see everybody's and may filter any status. Each row carries the month's count for its kind, the limit, the day's late marks and who else is off that day. `POST /api/ess/approvals/{family}/{id}/decide` (a rejection needs a reason), `…/archive` clears it for one approver | C10, D1, H6 | Built |

**What the build had to choose, for KP to confirm:**
- **Decision 6 (the cut-off).** The build's default: the 5th itself is open, for raising and for deciding; last month closes on the 6th. One function (`lastMonthOpen`, `src/policy/requests.js`) and the same `extract(day …) > 5` in the decision migration hold it. Change both together.
- **On duty needs no punch** (ADR-0020): an approval writes the day present with the place as its note; the day's existing punch times, if any, are kept. A future day is written by the morning job, never at approval time.
- **Leave is whole days in this phase.** A half-day CL needs a rule change in the Scheduler's day model; it is not offered.
- **LWP has no limit** until KP sets one; the HR limits endpoint can set one at any time.
- **An HR Executive is a manager, not an HR decider:** they see and decide their own reports' requests, and cannot cancel, change limits or see everybody's. That is the 16 Oct decision ("HR's powers without attendance or leave").
- **The archive is per approver** (`hr_ess_request_archives`): one manager clearing a request never hides it from HR.

**Tests:** the ESS suite is 1,408 tests (69 new endpoint tests for these routes, the Inbox, the
job and the limits; 435 contract checks, every route's every documented status provoked); the
migration suite `npm run test:migrations` applies the ten migrations and their rollbacks twice
against a throwaway Postgres and runs the decision functions themselves (approve, reject,
withdraw, cancel, the CL rule, the cut-off, the job).

**You after:** apply migrations 6 to 10, in order ([05-deploy.md](05-deploy.md#migrations-to-apply)). Until then every request endpoint answers 503 `MODULE_NOT_INSTALLED`; the app's launch call falls back to the code's own limits.

**Done when:** an employee files each type, sees the counter and withdraws one; the manager decides from the Inbox; the approved day appears in the Scheduler as an override, locked; an on-duty day approved ahead shows present on the day without a punch; the limits and the cut-off hold; two people deciding at once cannot both win.

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
6. **Cut-off.** Is the 5th itself open? Can a pending request for last month be decided after the cut-off? The 1C build's default, while this is open: the 5th itself is open, for raising and for deciding; last month closes on the 6th. One function (`lastMonthOpen`, `src/policy/requests.js`) and the matching `extract(day …) > 5` in migration 10 hold it; change both together.
7. **HR's web tools.** Where do HR review change requests and documents, and where do helpdesk agents work on the web? The brief put these in the web HRMS, which now stays unchanged. The options are the app itself, or a small web page served by team_app.
8. **Faculty marking.** Should the app offer class-attendance marking while the Scheduler's checks on it (J1) stay open?
9. **Infra register.** Should lab and facility helpdesk tickets also add a row to the Admin Manager's infra register? That writes a Scheduler table.
10. **The Scheduler's own holes and the committed dump.** These are outside this project, and KP's call.

Decided on 16 Oct and recorded in [03-decisions.md](03-decisions.md): the phone reset (yes, the same device rows), an HR Executive who manages people (approves their own team, as a manager), staying signed in (1 hour and 90 days), and desk logins (none allowed).

## Migrations, in run order

Every migration is listed here with its rollback script ([ADR-0021](adr/0021-migrations-new-tables-only.md)). Each creates only new `hr_ess_*` objects, is safe to run twice, and turns row-level security on with no policy, so only the service role (the ESS) reaches its rows. None alters a Scheduler table. KP applies each one by hand, in this order, in the Supabase SQL editor, and an agent checks it read-only afterwards ([05-deploy.md](05-deploy.md#migrations-to-apply)). None of them is applied yet.

| # | Migration (`db/migrations`) | Rollback (`db/rollbacks`) | Creates | Until it is applied |
| --- | --- | --- | --- | --- |
| 1 | [`20261101000000_hr_ess_sessions.sql`](../db/migrations/20261101000000_hr_ess_sessions.sql) | [`20261101000000_hr_ess_sessions.sql`](../db/rollbacks/20261101000000_hr_ess_sessions.sql): drops the three session functions, the table (with its trigger), then the trigger's function and the fingerprint helper | `hr_ess_sessions`: one row per refresh token, keeping only a keyed hash of it, and for a portal sign-in a fingerprint of the password it was kept with; foreign keys to `hr_employees` and `users` (cascade); CHECKs on the login kind, the install id, the label, the hashes and the dates. Indexes `hr_ess_sessions_family_idx`, `hr_ess_sessions_live_family_key` (unique: one live row per sign-in), `hr_ess_sessions_sign_in_key` (unique: one trade per Scheduler sign-in) and `hr_ess_sessions_live_employee_idx`. Functions `hr_ess_session_rotate`, `hr_ess_session_revoke` and `hr_ess_session_password_current`, the helper `hr_ess_password_fingerprint`, and the trigger `hr_ess_sessions_bind_password` (SECURITY INVOKER, `search_path` pinned, a lock per sign-in). Table and functions granted to `service_role` only, revoked from `anon` and `authenticated` | A3: the five session endpoints answer 503 `MODULE_NOT_INSTALLED`. Scheduler tokens keep working on every other endpoint |
| 2 | [`20261105000000_hr_ess_audit.sql`](../db/migrations/20261105000000_hr_ess_audit.sql) | [`20261105000000_hr_ess_audit.sql`](../db/rollbacks/20261105000000_hr_ess_audit.sql): drops the table | `hr_ess_audit`: who did what to whose data (HR's phone resets, data-request resolutions, and reads and changes of personal details). The actor by id (foreign keys, set null when the row goes) and by name; the target employee with no foreign key, so the trail outlives the record; `details` a JSON object of ids, counts and reasons, never personal data. Three indexes (by time, by target, by actor) | B8 and A8 still act, and the entry goes to the server log. E9: HR's read of somebody's personal details is refused (503), because a read must be recorded first |
| 3 | [`20261105000001_hr_ess_data_requests.sql`](../db/migrations/20261105000001_hr_ess_data_requests.sql) | [`20261105000001_hr_ess_data_requests.sql`](../db/rollbacks/20261105000001_hr_ess_data_requests.sql): drops the table, then its trigger's function | `hr_ess_data_requests`: kind `correct` or `delete`, details of 1 to 2,000 characters, status `open`, `done` or `rejected`, and HR's answer; a row is either fully open or fully resolved. Cascades with the employee. Two indexes (HR's queue, each person's list). The trigger `hr_ess_data_requests_open_limit` holds five open requests per person, counted under a lock per person, so requests sent at once cannot pass it | A8: the four data-request endpoints answer 503 |
| 4 | [`20261105000002_hr_ess_personal_details.sql`](../db/migrations/20261105000002_hr_ess_personal_details.sql) | [`20261105000002_hr_ess_personal_details.sql`](../db/rollbacks/20261105000002_hr_ess_personal_details.sql): drops the table | `hr_ess_personal_details`: one row per employee (its primary key, cascading); date of birth from 1940, the eight blood groups, address with a 6-digit PIN, and the emergency contact (a 10-digit Indian mobile, a name and a phone together) | E9: the four personal-details endpoints answer 503 |
| 5 | [`20261105000003_hr_ess_mock_location_reports.sql`](../db/migrations/20261105000003_hr_ess_mock_location_reports.sql) | [`20261105000003_hr_ess_mock_location_reports.sql`](../db/rollbacks/20261105000003_hr_ess_mock_location_reports.sql): drops the table | `hr_ess_mock_location_reports`: kind `punch` only, the mocked fix (both coordinates or neither, in range), accuracy, the phone's clock and app details, and the branch at the time (set null if the branch goes). Cascades with the employee. Three indexes (by time, by branch, by employee) | B14: both mocked-location endpoints answer 503 |
| 6 | [`20261106000000_hr_ess_request_limits.sql`](../db/migrations/20261106000000_hr_ess_request_limits.sql) | [`20261106000000_hr_ess_request_limits.sql`](../db/rollbacks/20261106000000_hr_ess_request_limits.sql): drops the table | `hr_ess_request_limits`: one row per type (the seven in the policy table), `limit_count` or `limit_minutes` for the number and NULL for no limit, seeded with KP's numbers by `ON CONFLICT DO NOTHING` so a re-run never puts back a number HR changed, and who changed it last | C6: the request endpoints and the balances answer 503; `GET /api/ess/me/capabilities` falls back to the code's defaults rather than failing |
| 7 | [`20261106000001_hr_ess_attendance_requests.sql`](../db/migrations/20261106000001_hr_ess_attendance_requests.sql) | [`20261106000001_hr_ess_attendance_requests.sql`](../db/rollbacks/20261106000001_hr_ess_attendance_requests.sql): drops the history, the request table, the trigger and its function | `hr_ess_attendance_requests` (on duty, fix a day, excuse a late; each type's own fields; the decision fields matching the status; the day kept before an approval for HR's cancel) and `hr_ess_attendance_request_history`, with the `filed` trigger. Three indexes (person, status, approved on-duty by day) | C1, C3: the attendance request endpoints answer 503 |
| 8 | [`20261106000002_hr_ess_leave_requests.sql`](../db/migrations/20261106000002_hr_ess_leave_requests.sql) | [`20261106000002_hr_ess_leave_requests.sql`](../db/rollbacks/20261106000002_hr_ess_leave_requests.sql): drops the history, the leave-request table, the trigger and its function | `hr_ess_leave_requests` (CL, LWP; whole days; the same decision fields as attendance) and `hr_ess_leave_request_history`, with the `filed` trigger. Three indexes | C2, C4: the leave endpoints and the balances answer 503 |
| 9 | [`20261106000003_hr_ess_request_archives.sql`](../db/migrations/20261106000003_hr_ess_request_archives.sql) | [`20261106000003_hr_ess_request_archives.sql`](../db/rollbacks/20261106000003_hr_ess_request_archives.sql): drops the table | `hr_ess_request_archives`: one row per (family, request, approver), so clearing the Inbox is per approver; unique on the three; the employee's deletion cascades it | D1: archiving answers 503; the Inbox works without it |
| 10 | [`20261106000004_hr_ess_request_functions.sql`](../db/migrations/20261106000004_hr_ess_request_functions.sql) | [`20261106000004_hr_ess_request_functions.sql`](../db/rollbacks/20261106000004_hr_ess_request_functions.sql): drops the seven functions | `hr_ess_decide_attendance_request`, `hr_ess_decide_leave_request`, `hr_ess_withdraw_attendance_request`, `hr_ess_withdraw_leave_request`, `hr_ess_cancel_attendance_request`, `hr_ess_cancel_leave_request`, `hr_ess_on_duty_apply`: each locks the request, re-checks the status, the window, the future-day rule, the cut-off and the one-CL rule, writes the day through the Scheduler's own `hr_attendance_apply_override` (or excuses the late in place), writes the history, and answers an `outcome` the routes map to refusals. Service role only | C7, C8, D1, H6: the decide, withdraw, cancel and archive (archive needs only 9) endpoints answer 503; `hr_ess_on_duty_apply` missing stops the job with a logged line, not the server |

None depends on another, but apply them in this order all the same: it is the order they were tested in. Rolling one back deletes its rows; roll back in reverse order. After rolling back 1, the tokens the ESS minted answer 503, not 401, so the app does not sign out by itself: staff sign out and sign in again (the rollback file says so).

B1 (`GET /api/ess/attendance/day`) and B8 (the phone list and reset) need no migration of their own: they read the Scheduler's tables from `20261015000004` to `20261023000000`, which are still to be confirmed in production, and answer 503 `MODULE_NOT_INSTALLED` while a table or column is missing.

Tested on a throwaway `postgres:17-alpine` in Docker, never on a real database:
- `npm run test:migrations` (`db/test/run-migrations.js`) applies all five twice over a stub of the Scheduler tables they point at, checks row-level security, no policies, the constraints and the cascades, rolls them back twice in reverse, and checks that no Scheduler table changed.
- `ESS_MIGRATION_TEST=docker npx vitest --run tests/migration.test.js` (in `apps/ess-api`) checks number 1 in more depth: Supabase-like roles and grants, both functions as the service role, and a failed rotate leaving the old row live.
- CI runs neither yet.

## Risks

- **Token formats.**
  - The ESS verifies the Scheduler's tokens, and from A3 it also mints them, using the shared `JWT_SECRET`. If the Scheduler's signing code changes, the ESS answers 401 `NOT_AUTHENTICATED` to the new tokens and the app signs those people out. The ESS tests hold a verbatim copy of that code, but CI cannot read the Scheduler repository, so the copy is compared with the Scheduler only when someone runs `SCHEDULER_BACKEND_DIR=../Scheduler_Backend npm test --workspace apps/ess-api` by hand. Run it whenever the Scheduler changes.
  - Rotating `JWT_SECRET` signs everyone out of both services, kept sign-ins (A3) included: their refresh tokens are hashed under a key derived from it, so none matches afterwards.
- **Schema coupling.** The ESS reads Scheduler tables, so a Scheduler migration that renames a column breaks it. The tests' column list (`SCHEMA` in `apps/ess-api/tests/helpers/fakeSupabase.js`) is kept by hand, and nothing compares it with the Scheduler's migrations, so update it with every Scheduler migration that touches a table the ESS reads.
- **Shared nginx.** A broken team_app nginx file would block the Scheduler's deploys. The ESS deploy tests before reloading, puts the last good file back on a failure, and CI runs every case against nginx 1.18 and 1.24 ([ADR-0019](adr/0019-ess-on-its-own-subdomain.md)). Deleting the ESS certificate while its file is enabled would also break `nginx -t`, so [05-deploy.md](05-deploy.md) takes the host off nginx first.
- **The deploy secrets reach every branch.** On GitHub Free a repository's secrets cannot be limited to `main`. Today only the three organisation admins can push, and they hold the same secrets in Scheduler_Backend; [05-deploy.md](05-deploy.md) lists the steps before anyone else gets write access.
- **Deploys before migrations.** Merges deploy before KP applies migrations, so new endpoints answer 503 until their tables exist ([ADR-0021](adr/0021-migrations-new-tables-only.md)).
- **The one Scheduler write.** HR's bulk phone reset (B8) updates `hr_attendance_devices` exactly as the Scheduler's own reset does (`attendanceAdminController.js:280-293`), only for rows still `active`, in slices of 150 ids, and never with an empty id list. The slices are separate requests with no transaction around them: if one fails, the phones already reset stay reset, are recorded in `hr_ess_audit` (or the server log) marked `incomplete`, and the reply is 503, so HR sends the same reset again for the rest. If the Scheduler changes its reset, change this one to match.
- **Kept sign-ins after a rollback.** Rolling back `hr_ess_sessions` makes every access token the ESS minted answer 503 on the ESS (not 401), so the app does not sign out by itself; on the Scheduler those tokens last out their hour.
- **Production state unconfirmed.** Whether the attendance migrations (`20261020000000` to `20261023000000`) and the one-CL index are applied in production is not confirmed. Check, read-only, before Wave 3 relies on them.
- **Open holes.** The Scheduler's holes stay open while the app ships. Whether to release anyway is KP's decision.
- **The on-duty job runs inside the ESS process.** One instance only (`ecosystem.config.cjs`, fork mode), as for the rate limits; the SQL it calls is idempotent (a written day no longer matches), so a restart or a second manual run changes nothing. Its failures go to the pm2 log and to `hr_ess_audit` as `on_duty.failed`, best effort.
- **The limits are load-bearing for the request endpoints.** They read `hr_ess_request_limits` and answer 503 until migration 6 is applied; `GET /api/ess/me/capabilities`, the app's launch call, falls back to the code's defaults instead of failing.
- **Another agent session.** It works in the Scheduler repositories. team_app work never touches them, and reads only from detached read-only copies.
