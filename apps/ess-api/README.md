# ESS API (`apps/ess-api`)

The Team RVM employee self-service API. It runs as its own pm2 process (`team-rvm-ess`, port 3740) on the Scheduler's server ([ADR-0005](../../docs/adr/0005-separate-ess-service.md)) and serves everything under `/api/ess`. It is reached on a host name of its own, `https://team-api.rvmcad.org/api/ess` ([ADR-0019](../../docs/adr/0019-ess-on-its-own-subdomain.md)), through an nginx file that the deploy writes from `deploy/nginx/` ([docs/05-deploy.md](../../docs/05-deploy.md)).

- **The Scheduler stays the system of record.** The ESS shares its Supabase database through the service key and reads the Scheduler's tables ([ADR-0003](../../docs/adr/0003-scheduler-is-system-of-record.md)). It writes its own `hr_ess_*` tables, and the Scheduler's attendance day only as the Scheduler's own code writes it: through `hr_attendance_apply_override` from the decision functions (ADR-0020), the late-excused fields HR's own excuse-late writes, the shift snapshot `ensureSnapshot` copies onto a day, and `hr_attendance_recompute`. Outside that flow it writes six Scheduler tables, each by one named method KP sanctioned: HR's bulk phone reset (`hr_attendance_devices`, `revokeActiveDevices`; KP, 16 Oct), the shift snapshot (`hr_staff_attendance`, `setDaySnapshot`), the photo pointer (`hr_employees`, `setEmployeePhoto`), H1 class marking (`student_attendance`, `saveClassAttendance`/`updateClassRemark`, and `pending_alerts`, `resolveAbsentRemarkAlerts`; KP, 22 Oct, decision 8), and the Admin Manager's register (`infra_tickets`, `createInfraTicket`/`closeInfraTicket`; KP, 22 Oct, decision 9). Never a delete ([ADR-0018](../../docs/adr/0018-team-app-changes-nothing-in-the-scheduler.md)).
- **One sign-in works for both.** The ESS accepts the tokens the Scheduler issues, the portal JWT and the attendance session ([ADR-0006](../../docs/adr/0006-app-calls-scheduler-directly.md)). It never relays calls to the Scheduler.
- **Stack:** JavaScript (CommonJS) on Express 4, zod, `@supabase/supabase-js`, vitest and supertest, ESLint ([ADR-0008](../../docs/adr/0008-javascript-express.md)). Runs on Node 20 or later.

## Scripts

Run from the repository root (`npm run lint`, `npm test`) or from this folder:

| Script | What it does |
| --- | --- |
| `npm start` | Starts the server (`src/server.js`), reading `apps/ess-api/.env` |
| `npm test` | Runs the vitest suite once. No database is needed: the tests run the real store over an in-memory client |
| `npm run lint` | ESLint, including `no-undef` and `no-unused-vars` |

`npm run test:migrations`, from the repository root, runs `db/migrations` against a throwaway Postgres in Docker (`db/test/run-migrations.js`).

`tests/contract.test.js` holds the ESS against `packages/contracts/openapi.yaml` (version **0.13.0**): the routes it serves must be exactly the contract's ESS operations, and every reply the tests provoke, success or refusal, must have a documented status, body, error code and headers. A field the contract does not name fails it too, so an endpoint change and its contract change go in the same PR ([ADR-0010](../../docs/adr/0010-openapi-contract-first.md)).

Set `SCHEDULER_BACKEND_DIR` to a Scheduler_Backend checkout to also run the drift checks. They compare `src/policy/roles.js` and `src/policy/hrPolicy.js` with the Scheduler's `config/roles.js` and `config/hrPolicy.js`, and the verbatim Scheduler code in `tests/helpers` with its source:

```bash
SCHEDULER_BACKEND_DIR=../Scheduler_Backend npm test
```

Without it those checks are skipped, and that includes CI, which cannot read the private Scheduler repository. Run them by hand whenever the Scheduler changes.

Set `ESS_MIGRATION_TEST=docker`, with Docker running, to also run `tests/migration.test.js`: it applies `db/migrations/20261101000000_hr_ess_sessions.sql` (twice) and its rollback to a throwaway `postgres:17-alpine` container, checks the constraints, the privileges and both functions as the service role, and removes the container. No port is opened and no real database is reached. `npm run test:migrations` at the root covers all thirty migrations more broadly. CI runs neither yet.

**The suite (25 Oct 2026, with the issue #15 follow-up):** 2,605 tests in 57 files, the contract included - 1,260 of those are contract checks, every route's every documented status provoked. The Wall's own tests are `wallPosts`, `wallComments`, `wallPraise`, `wallPolls`, `wallAnnouncements`, `wallCelebrations`, `wallModeration` and `wallJob`; the Helpdesk's are `helpdeskTickets`, `helpdeskQueue` and `helpdeskJob`, plus `helpdeskAssign` for the Phase 2C delta; Phase 2C's are `documents`, `changeRequests`, `bankDetails`, `idCard` and `documentsJob`; Phase 2D's are `leaders`, `approvalsChain`, `facultyDay` and `classMarking`, and WFH's is `wfh`, each covering its happy path, its validation, the role-denied and wrong-owner cases, and the 503s; `npm run test:migrations` applies all thirty migrations and their rollbacks twice against a throwaway Postgres and runs the Wall's, the Helpdesk's, Phase 2C's, Phase 2D's and WFH's row rules themselves. H1 needs no migration; WFH needs 29; promotion wishes need 30.

## Settings

`src/config.js` checks these at start-up. A missing or malformed value stops the process with a list of what is wrong, naming each variable and never printing its value. `.env.example` lists them with placeholders.

| Variable | Required | Meaning |
| --- | --- | --- |
| `PORT` | no, 3740 | Port to listen on. pm2 sets 3740 (`ecosystem.config.cjs`, the one place it is set) |
| `HOST` | no, `127.0.0.1` | Address to listen on. Loopback, because nginx on the same server is the only caller: point its `proxy_pass` at `http://127.0.0.1:3740`. Opening the port to the network would take tokens over plain HTTP and let a caller choose its own rate-limit bucket with a forged `X-Forwarded-For` |
| `JWT_SECRET` | **yes** | The Scheduler's own `JWT_SECRET`, byte for byte, at least 32 characters. Used to verify the Scheduler's tokens |
| `SUPABASE_URL` | **yes** | The Scheduler's Supabase project URL |
| `SUPABASE_SERVICE_KEY` | **yes** | Its service-role key |
| `ESS_ENABLED` | no, on | `false` switches every endpoint except `/api/ess/health` to 503 `MODULE_DISABLED` after a restart |
| `APP_VERSION` / `GIT_SHA` | no | The server version `/health` reports: `APP_VERSION`, else `GIT_SHA` (the deploy writes the commit), else the package version |
| `MIN_APP_VERSION` | no | Semver (`1.4.0`, `1.4.0+12`). An app below it must update. May not be above `LATEST_APP_VERSION` |
| `LATEST_APP_VERSION` | no | Semver. The newest app version, offered as an update |
| `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY_B64` | no | Push. Until all three are set, push stays log-only ([ADR-0016](../../docs/adr/0016-push-and-integrity-start-off.md)). The private key is the PEM, base64-encoded on one line |

Wave 2 adds no setting. Its numbers are in the code, each in one place, so a change is a reviewed commit:

| What | Value | Where |
| --- | --- | --- |
| Access token lifetime | 1 hour | `src/policy/sessions.js` |
| A kept sign-in | 90 days from its last refresh | `src/policy/sessions.js` |
| How fresh a sign-in must be to keep it | issued in the last 10 minutes, at most 60 seconds in the future | `src/policy/sessions.js` |
| A spent refresh token retried by the same install | 409 for 60 seconds, then reuse | `src/policy/sessions.js` |
| Refresh, and sign-out by refresh token | 120 in 15 minutes per address | `src/middleware/rateLimit.js` (`sessionPerIp`) |
| Keeping a sign-in | 10 in 15 minutes per employee | `exchangePerEmployee` |
| The sign-in resolver | 40 in 15 minutes per address, 10 per identifier | `signInPerIp`, `signInPerIdentifier` |
| Mocked-location reports | 30 a day per employee | `mockReports` |
| Open data requests | 5 per employee | `src/routes/dataRequests.js` |
| HR lists | 1,000 phones, 500 reports, 500 data requests; `truncated` says more were left out | `src/lib/store.js` `LIST_LIMITS` |
| The bulk reset's id list | 1 to 500 ids, a 32 kB body | `src/routes/devices.js`, `src/app.js` |
| Who may use HR's tools | personal details and data requests: hr, hr_executive, ceo, super_admin; phones and mocked-location reports: hr, ceo, super_admin | `src/policy/hrAccess.js` |

Phase 1C adds no setting either:

| What | Value | Where |
| --- | --- | --- |
| The monthly request limits | `hr_ess_request_limits`, seeded with KP's numbers and changed by HR through `PUT /api/ess/hr/request-limits/{type}` | `db/migrations/20261106000000_hr_ess_request_limits.sql`, `src/policy/requestLimits.js` |
| The cut-off | last month open while the IST day of month is 5 or less (decision 6's default; the 5th itself open) | `src/policy/requests.js` `lastMonthOpen`, and `extract(day …) > 5` in `db/migrations/20261106000004_hr_ess_request_functions.sql` |
| The on-duty morning job | once at boot, then hourly; one process only (fork mode) | `src/jobs/onDuty.js` |
| The half-day threshold for a fixed day | 240 minutes, the Scheduler's default | `src/policy/attendance.js` `HALF_DAY_MINUTES` |
| My lists | the last 100 requests | `src/lib/store.js` `LIST_LIMITS.myRequests` |
| The Inbox | at most 100 requests and 5 "who else is off" names per request | `src/lib/store.js` `LIST_LIMITS.inbox`, `src/routes/approvals.js` `CONTEXT_NAMES` |
| Work from home | HR's per-employee allowance, 1 to 31 days, 200 in the list; the allowance is the limit, not a request-limit row | `db/migrations/20261113000001_hr_ess_wfh_allowances.sql`, `src/routes/wfh.js`, `LIST_LIMITS.wfhAllowances` |

Phase 1D adds no setting either:

| What | Value | Where |
| --- | --- | --- |
| Push quiet hours | 21:00 to 08:00 IST: nothing is pushed, the rows wait for the morning | `src/policy/notifications.js` |
| The push worker | once at boot, then every minute; 50 notifications a batch; 3 attempts before a row is `skipped` | `src/jobs/push.js` |
| The priority-task window | 48 hours back, so a restart loses nothing; one notification per task and person | `src/jobs/push.js`, the task key in migration 12 |
| My notifications | the last 100 | `src/lib/store.js` `LIST_LIMITS.notifications` |
| FCM | real sends only when all three `FIREBASE_*` settings exist; the log otherwise | `src/lib/fcm.js`, `src/config.js` |

Phase 2A adds the Wall's own limits and windows:

| What | Value | Where |
| --- | --- | --- |
| Wall posts, praise, wishes and announcements | 60 a day per employee | `src/middleware/rateLimit.js` (`wallPosts`) |
| Comments and replies | 200 a day per employee | `wallComments` |
| Reactions | 60 a minute per employee | `wallReactions` |
| Photos and PDFs | up to 5 a file's request, each up to 1 MB decoded, in the ESS's own bucket (`ESS`) | `src/lib/wallKit.js`, `src/app.js` (`7mb` for a Wall body) |
| A post's or comment's edit window | 15 minutes from `created_at`, then `EDIT_WINDOW_CLOSED` | `src/policy/wall.js` |
| @mentions | `@RVM-011`: an `@` before an employee code, resolved to the staff who hold it | `src/policy/wall.js` `mentionCodes` |
| Praise badges | a fixed catalogue of 12 (KP, 19 Oct: not HR-editable), in one place | `src/policy/wall.js` `PRAISE_BADGES` |
| A poll | 2 to 10 options of up to 120 characters, one or many choices, optionally anonymous, closing within a year; the options freeze on the first vote | `src/policy/wall.js`, `src/routes/wallPolls.js` |
| Pinned announcements | up to 3 at a time | `src/policy/wall.js` `MAX_PINNED` |
| The Wall's feed, a thread, praise, announcements and reports | the last 20 posts a page (`?before=`), 50 comments a thread, 20 praise, 100 announcements, 100 reports | `src/lib/store.js` `LIST_LIMITS` |
| The Wall's clock | once at boot, then hourly: scheduled announcements, acknowledgement reminders inside 2 days of the close, polls closing | `src/jobs/wall.js` |
| Announcement email and push | log-only until RVM has a mail provider and the Firebase project (KP, 19 Oct) | `src/jobs/push.js`, the deploy log |
| Raised tickets | 20 a day per employee, on `POST /helpdesk/tickets` only | `src/middleware/rateLimit.js` (`helpdeskTickets`) |
| A Helpdesk raise's body | the same five files as a Wall post, each up to 1 MB decoded | `src/lib/wallKit.js`, `src/app.js` (`7mb` for a Helpdesk raise) |
| The Helpdesk's reads | 50 tickets in my list, 100 in a queue, 200 rows in a thread | `src/lib/store.js` `LIST_LIMITS` |
| The Helpdesk's clock | once at boot, then hourly: escalation of a past-due live ticket to its team, then the HoO, then the CEO | `src/jobs/helpdesk.js` |
| The infra register mirror | lab and facility tickets only; the hourly job retries skipped links and resolves a ticket whose register row was closed | `src/lib/infraMirror.js`, `src/jobs/infra.js` |

Phase 2C adds the documents', changes', bank's and card's own numbers:

| What | Value | Where |
| --- | --- | --- |
| Documents | up to 50 kept per person, each 1 byte to 5 MB decoded | `src/policy/documents.js`, `src/routes/documents.js` |
| Document uploads | 30 a day per employee | `src/middleware/rateLimit.js` (`documentsUploads`) |
| A document upload's body | 7 MB (`/api/ess/me/documents`) | `src/app.js` (`LARGE_JSON_BODIES`) |
| Open change requests | one per field per person, held by the database's partial unique index | `db/migrations/20261110000002_hr_ess_change_requests.sql` |
| The weekly reminder | once a week, one `documents` notification per person, naming the mandatory types they personally lack | `src/jobs/documents.js` |
| The ID card's verify link | HMAC-signed from `JWT_SECRET`, 90 days from minting | `src/lib/idCardKit.js` |
| ID card verifications | 30 a minute per address | `src/middleware/rateLimit.js` (`idCardVerify`) |

Phase 2D adds the leaders', faculty's and escalations' own numbers:

| What | Value | Where |
| --- | --- | --- |
| The escalation window | two IST days pending, one level a run, HR the fallback when the line runs out | `src/policy/approvals.js` `ESCALATE_AFTER_DAYS`, `src/jobs/approvals.js` |
| The escalation job | once at boot, then hourly; 500 pending requests a family a run | `src/jobs/approvals.js` |
| Short leave | 1 to 480 minutes a day; 180 minutes a month seeded in `hr_ess_request_limits` (HR can change it) | `src/routes/attendanceRequests.js`, migration 25 |
| A faculty day's window | this month or last month, as the attendance day read | `src/routes/facultyDay.js` |
| A class-marking day's window | the batch's start date to `min(batch.end_date, today IST)`; teaching roles lock after the first save | `src/policy/classMarking.js` |
| The leaders' overview | counts only; at most 1,000 pending requests are counted | `src/routes/leaders.js` |

H1 adds no setting: the six class-marking rules are policy constants in `src/policy/classMarking.js`.

## Endpoints

Everything is under `/api/ess`. Every reply is JSON and is sent with `Cache-Control: no-store`.

| Endpoint | Sign-in | Answer |
| --- | --- | --- |
| `GET /api/ess/health` | none | `{ ok, server_time, version, min_app_version, latest_app_version, db: "ok" \| "unavailable" }`. Always 200 while the process is up, even with the database unreachable. It stays up when `ESS_ENABLED=false` |
| `GET /api/ess/me` | portal JWT or attendance session | `{ employee: { id, full_name, employee_code, designation, employment_status, branch, department, manager }, login: { kind, role, user_id } }` |
| `GET /api/ess/me/capabilities` | portal JWT or attendance session | Tabs, sections, team, approvals, the request types with their monthly limits, Wall rights, push and integrity |
| `POST /api/ess/session` | a Scheduler token from a sign-in made in the last 10 minutes | Keeps the sign-in (task A3). Body `{ install_id, device_label? }`. 201 `{ session: { id, expires_at }, access_token, access_expires_at, refresh_token, login }` |
| `POST /api/ess/session/refresh` | none: `{ refresh_token, install_id }` | 200, the same shape: the next access and refresh token. A refusal is 401 `NOT_AUTHENTICATED` with `reason` |
| `POST /api/ess/session/sign-out` | the access token, or `{ refresh_token }` with no bearer | 204. Ends that sign-in |
| `GET /api/ess/sessions` | portal JWT or attendance session, or an access token from here | `{ sessions: [{ id, device_label, created_at, last_used_at, expires_at, current }] }`, the caller's own |
| `DELETE /api/ess/sessions/:id` | as above | 204, ending one of the caller's own; 404 for anything else |
| `POST /api/ess/sign-in/resolve` | none: `{ identifier }` | Which sign-in the one field holds (task A5): `{ kind: "portal", login_with: "as_typed", location_names }` (every branch, for every account), `{ kind: "portal", login_with: "username_or_phone" }`, `{ kind: "attendance", methods }` or `{ kind: "unknown" }` |
| `POST`, `GET /api/ess/me/data-requests` | either | File and list my requests to correct or delete my data (A8). At most 5 open |
| `GET /api/ess/hr/data-requests?status=`, `PATCH /api/ess/hr/data-requests/:id` | portal: hr, hr_executive, ceo, super_admin | HR's queue, and done or rejected with a note. Never one's own (409 `OWN_REQUEST`) |
| `GET`, `PUT /api/ess/me/personal` | either | My date of birth, blood group, address and emergency contact (E9). I change only the blood group and emergency contact; the rest is 403 `SENSITIVE_FIELD` |
| `GET`, `PUT /api/ess/hr/employees/:id/personal` | portal: hr, hr_executive, ceo, super_admin | Anybody's personal details, every field. Never one's own (409 `OWN_RECORD`). Every read and change goes to `hr_ess_audit`, and a read that cannot be recorded is refused |
| `GET /api/ess/attendance/day?date=` | either | `server_now`, my day as stored, its note, HR's remark and my remarks (B1); this month or last month |
| `POST /api/ess/attendance/mock-location` | either | Report a punch refused for a mocked location (B14); 30 a day per person |
| `GET /api/ess/hr/mock-location-reports?from=&to=&branch_id=` | portal: hr, ceo, super_admin | The reports, with whose each is |
| `GET /api/ess/hr/devices?branch_id=&status=`, `POST /api/ess/hr/devices/reset` | portal: hr, ceo, super_admin | Registered phones, and the bulk reset (B8): the Scheduler's own revoke update on every active phone of a branch or a list of people. The one direct write to a Scheduler table |
| `POST`, `GET /api/ess/attendance-requests` | either | My attendance requests (C1, C3): on duty, fix a day, excuse a late. `POST` files one (201; 400 the form; 409 `DUPLICATE_REQUEST`, `LIMIT_REACHED`, `REQUEST_CLOSED`); `GET` lists my own, newest first, at most 100 |
| `POST /api/ess/attendance-requests/{id}/withdraw` | either | Withdraw a pending one (C8): 200 with the request; somebody else's is 404; anything decided is 409 `REQUEST_NOT_PENDING` |
| `POST`, `GET /api/ess/leave-requests` | either | My leave requests (C2, C4): `cl` (one a month) or `lwp`, whole days. `POST` files one; `GET` lists my own |
| `POST /api/ess/leave-requests/{id}/withdraw` | either | Withdraw a pending leave request |
| `GET /api/ess/leave/balances?month=` | either | Allowed, used, pending and remaining for every type (C5), this month or last |
| `GET /api/ess/me/wfh` | either | My work-from-home allowance and this month (KP, 22 Oct): `{ month, enabled, monthly_limit_days, used, pending, remaining }`; without an allowance `enabled: false` and `remaining: 0` |
| `GET /api/ess/hr/wfh-allowances?q=` | portal: hr, ceo, super_admin | Who HR has enabled for WFH, newest change first, at most 200 (`truncated`), each joined to the employee card; `?q=` searches name or code. An employee without a row is absent |
| `PUT /api/ess/hr/wfh-allowances/{employeeId}` | portal: hr, ceo, super_admin | Enable, change or disable one employee's allowance: `{ enabled, monthly_limit_days, note? }` (1 to 31 days, note up to 300); audited as `wfh.allowance.changed` with the before/after numbers only |
| `GET /api/ess/approvals?status=` | either | The approvals Inbox (D1) and its counts: a manager sees their reports' pending requests; hr, ceo and super_admin see everybody's and may filter any status; each row carries the month's count, the limit, the day's late marks and who else is off |
| `POST /api/ess/approvals/{family}/{id}/decide` | either | Approve or reject (D1, H6); a rejection needs a reason. An approval writes the day through the Scheduler's override function, in one transaction with the status and history |
| `POST /api/ess/approvals/{family}/{id}/archive` | either | Clear a request from my Inbox without deciding it (204); per approver |
| `GET /api/ess/approvals/{family}/{id}/chain` | either | The reporting line the request waits on (D4): each level, why it is skipped, the first that may decide, `hr_fallback` |
| `POST /api/ess/hr/attendance-requests/{id}/cancel`, `/hr/leave-requests/{id}/cancel` | portal: hr, ceo, super_admin | Cancel an APPROVED request (C8) with a reason, restoring the day it wrote; audited |
| `GET /api/ess/hr/request-limits`, `PUT /api/ess/hr/request-limits/{type}` | portal: hr, ceo, super_admin | The monthly limits HR owns (C6); a change is audited |
| `POST /api/ess/push-devices`, `DELETE /api/ess/push-devices/{id}` | either | Register this phone's FCM token (D5), and revoke it on sign-out. One install, one row; the token is never sent back |
| `GET /api/ess/notifications` | either | My notifications, newest first, with the unread count (D6) |
| `POST /api/ess/notifications/{id}/read`, `POST /api/ess/notifications/read-all` | either | Mark one (idempotent) or all read |
| `GET /api/ess/notifications/settings`, `PUT /api/ess/notifications/settings` | either | The categories (`approvals`, `decisions`, `priority_tasks`, then the Wall's six, `helpdesk` and `documents`) and the quiet hours (D8) |
| `GET /api/ess/me/profile` | either | My Summary, Job, Personal and the safe Timeline, with a 300-second signed photo link (E1, E12, E10) |
| `GET /api/ess/me/faculty-day?date=` | portal, with a faculty record | The faculty "my day" (H7): today's sessions owned or covered, each marked or not, the remarks due, and the indicators card; counts only |
| `GET /api/ess/me/batches/{id}/roster?date=` | teaching roles, or the admin roles, for their batch or branch | The day's eligible students (H1): `id`, `full_name`, `admission_number`, `marked`, absent reason and follow-up, plus `already_marked` and `can_edit`; never a phone, password, fee or personal detail |
| `POST /api/ess/me/batches/{id}/attendance` | the same | Save the day (H1): `{ date, attendance: [{ student_id, present, absent_reason?, follow_up_comment? }] }`, answered with `counts`; a teaching role's day locks after the first save, admins may correct |
| `PATCH /api/ess/me/batches/{id}/attendance/{date}/remarks` | the same | Fill or change an absent student's reason (H1): `{ student_id, absent_reason, follow_up_comment? }`; present or unmarked is 409 `CLASS_NOT_ABSENT` |
| `GET /api/ess/leaders/overview` | ceo, super_admin | The organisation in counts (H5): headcount, today's states, off this week, the approval queue; never a name |
| `PUT /api/ess/me/photo` | either | Change my photo (base64, ≤1 MB, JPEG/PNG/WebP): the private bucket plus the record's pointer, audited (E10) |
| `GET /api/ess/me/org` | either | My chain to the CEO ("Reports to the CEO (not recorded)"), peers, direct reports and department, with the notice chip (E2, E11) |
| `GET /api/ess/directory` | either | Colleague search by name or code, filtered by branch or department; email to everyone, phone per the contact rule (E2, E8) |
| `GET /api/ess/team/today` | either | Team today for managers, the branch for a HoO (E6, H4) |
| `GET /api/ess/wall/settings` | either | The Wall's rules: who may post what, the fixed badge catalogue, the poll's shape, the audience scopes, the moderation roles, and `email.enabled: false` |
| `GET /api/ess/wall/posts` | either | The organisation's wall plus the caller's own branch's (or one with `?scope=`), newest first, 20 a page with `next_before` |
| `POST /api/ess/wall/posts` | either | A post or a poll: `{ kind?, body, scope?, branch_id?, attachments?, poll? }`. Mentions are resolved from `@RVM-011`; files go to the ESS bucket |
| `GET /api/ess/wall/posts/{id}` | either | One post with its comments and their one level of replies (50 a page) |
| `PATCH`, `DELETE /api/ess/wall/posts/{id}` | either | The author's own: an edit inside 15 minutes (then `edited: true`), or a delete that blanks the row and keeps the trail |
| `POST /api/ess/wall/posts/{id}/comments` | either | A comment, or a reply with `parent_id` (one level only) |
| `PATCH`, `DELETE /api/ess/wall/comments/{id}` | either | The author's own comment or reply, the same 15-minute edit window |
| `PUT`, `DELETE /api/ess/wall/posts/{id}/reaction` | either | One of the six (`like`, `love`, `laugh`, `clap`, `insightful`, `curious`), one per person; DELETE takes it off |
| `GET /api/ess/wall/posts/{id}/reactions` | either | Who reacted, grouped by reaction (`?reaction=` narrows it) |
| `PUT`, `DELETE`, `GET /api/ess/wall/comments/{id}/reaction(s)` | either | The same, one level in |
| `POST /api/ess/wall/praise` | either | Praise: `{ employee_id, badge, reason, scope?, attachments? }`; the badge is one of the fixed 12, and yourself is refused |
| `GET /api/ess/me/praise` | either | Praise for me (`?employee_id=` for somebody else's), newest first, with the badge catalogue |
| `GET /api/ess/wall/polls/{id}` | either | One poll with its options, their counts, and the caller's own votes |
| `POST`, `DELETE /api/ess/wall/polls/{id}/vote` | either | Vote (`{ option_ids: [...] }`) or take it back, while the poll is open |
| `POST /api/ess/wall/polls/{id}/options` | either | The author's own: one more option before the first vote |
| `POST /api/ess/wall/polls/{id}/close` | either | The author's own: close it early, keeping the day it was due on |
| `POST /api/ess/wall/announcements` | portal, HR/CEO/super admin | An announcement: `{ title, body, audience?, attachments?, needs_ack?, closes_on?, publish_at?, pinned? }`. Now or scheduled; the audience is resolved once, at publication |
| `GET /api/ess/wall/announcements` | either | What was sent to me, pinned first, with my own read and acknowledgement times |
| `GET /api/ess/wall/announcements/{id}` | either | One, if it reached me or I sent it (its sender also reads the counts) |
| `PATCH`, `DELETE /api/ess/wall/announcements/{id}` | portal, the sender | Edit (title, body or `pinned`) or take it down |
| `POST /api/ess/wall/announcements/{id}/read` | the audience | 204; the first open is what the sender's count records |
| `POST /api/ess/wall/announcements/{id}/ack` | the audience | The acknowledgement button, inside the closing day |
| `GET /api/ess/wall/announcements/{id}/counts` | the sender, or HR | `{ sent, read, acknowledged, not_acknowledged }` |
| `GET /api/ess/wall/hr/announcements` | portal, HR/CEO/super admin | My own announcements, drafts and scheduled ones included (`?status=`) |
| `GET /api/ess/wall/celebrations` | either | Birthdays (day and month only, never the year, hidden for anyone who opted out), work anniversaries and the last 15 days' joiners |
| `POST /api/ess/wall/wishes` | either | A one-tap wish: `{ employee_id, occasion, body }`, one per person per occasion per year |
| `GET`, `PUT /api/ess/me/celebration-optout` | either | Whether my birthday is left off the cards |
| `POST /api/ess/wall/posts/{id}/reports`, `/comments/{id}/reports` | either | Report something for HR's queue (`{ reason, detail? }`), once per person per thing |
| `GET /api/ess/wall/hr/reports` | portal, HR | HR's queue: still open by default, `?status=` for the rest |
| `POST /api/ess/wall/hr/reports/{id}/resolve` | portal, HR | Answer a report: `hidden` or `kept`, with a note |
| `GET /api/ess/wall/hr/moderation-log` | portal, HR | The moderation trail out of `hr_ess_audit`: hides, restores, deletions and answered reports |
| `POST`, `DELETE /api/ess/wall/posts/{id}/hide` | portal, HR | Hide a post with a reason (3 to 200 characters), or take the hide back |
| `POST`, `DELETE /api/ess/wall/comments/{id}/hide` | portal, HR | The same for a comment; its body blanks for everybody but HR and its author |
| `GET /api/ess/helpdesk/categories` | either | The category list and the rules document (G1): the six ticket categories and four flow links, the 7-day reopen window, the 1-5 rating, anonymous raising and attachments on |
| `POST /api/ess/helpdesk/tickets` | either | Raise a ticket (G2, 201): `{ category, subject, body, anonymous?, attachments? }`; 20 a day per person |
| `GET /api/ess/helpdesk/tickets?status=` | either | My tickets, newest first, 50, each with its "overdue by" |
| `GET /api/ess/helpdesk/tickets/{id}` | either | One ticket with its thread (G2): its raiser, its team and HR's oversight may read (never on a confidential one; a confidential read is audited first) |
| `POST /api/ess/helpdesk/tickets/{id}/comments` | raiser or the team | A comment, at any status; the team's first one is the first response |
| `POST /api/ess/helpdesk/tickets/{id}/withdraw` | the raiser | Take an open ticket back; anything else is 409 `HELPDESK_NOT_OPEN` |
| `POST /api/ess/helpdesk/tickets/{id}/reopen` | the raiser | Take a resolved or closed ticket back up, within 7 days; the deadlines start over |
| `POST /api/ess/helpdesk/tickets/{id}/close` | the raiser | Close it myself: a reason of 3 to 280 characters, an optional rating of 1 to 5 |
| `POST /api/ess/helpdesk/tickets/{id}/claim` | the team | Take the ticket (G5): names the assignee, counts as the first response, moves open to in progress; `assign` hands a live ticket to somebody else |
| `POST /api/ess/helpdesk/tickets/{id}/status` | the team | Move to `in_progress`, `on_hold` or `resolved`, where the lifecycle allows |
| `POST /api/ess/helpdesk/tickets/{id}/assign` | the team | Hand a live ticket to a named handler (KP 5): `{ employee_id, note? }`; the assignee must hold the category's queue role; sets `claimed_at` and the first response, moves open to in progress, and the history row in `hr_ess_helpdesk_assignments` keeps who pointed it there |
| `GET /api/ess/helpdesk/queue` | portal | The team's queue (G5): the tickets of my role's categories, `?status=` and `?category=`; an attendance session is 403 `PORTAL_LOGIN_REQUIRED` |
| `GET /api/ess/team/off-this-week` | either | Who is off this week: reports, else peers; names and days only (E6) |
| `GET, POST, DELETE /api/ess/me/documents` | either | My documents (E4): `POST` uploads one base64 (201; the fixed types, `others` with its remark; at most 50 kept, 30 a day), `GET` lists mine newest first, `DELETE` takes one of mine off |
| `GET /api/ess/hr/employees/{id}/documents` | portal: hr, hr_executive, ceo, super_admin | A person's documents for review (E5); identity rows are hidden from a reader who may not open them |
| `POST /api/ess/hr/employees/{id}/documents/{docId}/verify`, `/reject` | portal: hr, hr_executive, ceo, super_admin | Verify a document, or reject it with a reason of 3 to 500 characters; a reviewed one refuses a second answer (409 `DOCUMENT_REVIEWED`) |
| `POST, GET /api/ess/me/change-requests` | either | Ask for my date of birth, address or legal name to be corrected (E3): what the record shows, what it should, the reason; one open request per field (409 `CHANGE_ALREADY_OPEN`) |
| `GET /api/ess/hr/change-requests`, `POST /api/ess/hr/change-requests/{id}/decide` | portal: hr, ceo, super_admin | HR's queue, and the decision with its note - recorded only, never written to `hr_employees` |
| `GET, PUT /api/ess/me/bank-details` | either | My salary account (KP 3): saved only with `consent_name` typed (the save stamps `consent_given_at`); `GET` answers `{ bank_details: null }` while nothing is saved |
| `GET /api/ess/hr/employees/{id}/bank-details` | portal: hr, ceo, super_admin | The account masked to its last four digits; every read audited |
| `GET /api/ess/me/id-card` | either | My ID card (E7): the HR record's and personal details' name, photo, designation, branch, and its `verify_url` for the QR |
| `GET /api/ess/id-card/verify/{token}` | none | The QR's signed, expiring link (90 days): name, photo, designation, branch, "active employee". 401 `ID_CARD_BAD_TOKEN` for a bad, expired or archived-holder link |

The HR roles are in `src/policy/hrAccess.js`. An attendance session on an HR route is 403 `PORTAL_LOGIN_REQUIRED`; a portal login with another role is 403 `HR_ACCESS_DENIED` or `ATTENDANCE_OVERRIDE_DENIED`, the Scheduler's codes.

The capability rules are KP's decisions of 16 Oct 2026 ([docs/03-decisions.md](../../docs/03-decisions.md)), in `src/policy/capabilities.js`. The request types and limits are in `src/policy/requestLimits.js`, the one table the request endpoints will also use; WFH's limit is the employee's own allowance in `hr_ess_wfh_allowances` (KP, 22 Oct), so its capability row is `offered: true` with that limit only for an enabled employee. The contract is `packages/contracts/openapi.yaml` ([ADR-0010](../../docs/adr/0010-openapi-contract-first.md)), version 0.13.0: every route here is documented in it, and `tests/contract.test.js` provokes every status each route documents and holds the reply to it.

### Staying signed in (task A3)

The app trades a fresh Scheduler sign-in for a kept one, and from then on holds a one-hour access token and a refresh token ([docs/04-build-plan.md](../../docs/04-build-plan.md), Wave 2; KP, 16 Oct 2026). The access tokens are minted in the Scheduler's own two formats (`src/lib/accessTokens.js`), so the Scheduler's punch path and portal routes take them unchanged, with one more claim, `sid`, naming the ESS session. **Their `iat` is always the original sign-in's**: the Scheduler lets a code sign-in set the attendance password for 15 minutes after its `iat`, and ends every session older than a password change, so a fresh `iat` would defeat both. `tests/accessTokens.test.js` holds the minted tokens against verbatim copies of the Scheduler's `auth.js`, `punchAuth.js`, `readPunchSession` and the password gate.

A kept sign-in is a family of `hr_ess_sessions` rows, one per refresh token, keeping only an HMAC-SHA256 of the token under a key derived from `JWT_SECRET`, so rotating the secret ends kept sign-ins too. A refresh retires its row and adds the next one in one transaction (`hr_ess_session_rotate`), and a refresh token presented again is reuse, which ends the family, unless it comes from the same install within a minute (409 `REFRESH_IN_PROGRESS`). Every refresh re-checks the person as `employeeAuth` would. The sign-in ends, with the `reason` the refusal gives, on: sign-out (`signed_out`), reuse or another install (`reuse`), 90 days unused (`expired`), an attendance password set or reset, or a portal password change by any of the Scheduler's paths (the `password_changed_at` stamp, and a fingerprint of `users.password_hash` the database compares, `hr_ess_session_password_current`), since the sign-in (`password_changed`), HR switching the attendance login off (`login_off`), the employee leaving (`left`), and the login no longer linked or no longer staff (`unlinked`). A token carrying `sid` is refused by `employeeAuth` (401) as soon as its family has ended.

### One-field sign-in (task A5)

`src/policy/signIn.js` finds an identifier the way each of the Scheduler's sign-ins would (`tests/signIn.test.js` checks it against verbatim copies of both lookups), and answers only for logins the app can use: never the connector identity, a login linked to nobody, or somebody who has left. Nobody, or more than one person, is `{ kind: "unknown" }`, after the same database reads whatever the reason. Nothing identifying is returned.

### My data, my day and HR's tools (tasks A8, E9, B1, B14, B8)

- **Always the caller's own.** The self-service routes (`/me/...`, `/attendance/...`) take no employee id; a body field the route does not take is refused with 400, never ignored.
- **HR on somebody else's data.** Nobody resolves their own data request (409 `OWN_REQUEST`) or changes their own date of birth or address (409 `OWN_RECORD`).
- **The audit trail** (`hr_ess_audit`, `src/lib/audit.js`) records HR's reads and changes of personal details, data-request resolutions and phone resets, with ids, counts and reasons, never the personal data. A read is recorded before the reply and refused (503) if it cannot be; a change is made first and, if its row cannot be written, the entry goes to the pm2 log.
- **The phone reset** writes only `status`, `revoked_at`, `revoked_by`, `revoked_by_name` (the caller's username, as the Scheduler records it) and `revoke_reason`, only on rows still `active`, in slices of 150 ids.

### Requests, leave and approvals (tasks C1-C12, D1, H6)

- **The forms are the routes'.** `POST /attendance-requests` and `/leave-requests` validate the type, the day's window, the reason and the type's own fields; they check the duplicate and the month's counter before writing. The row goes in pending, with its 'filed' history row written by the database trigger.
- **The decision is the database's.** `POST /approvals/{family}/{id}/decide` resolves the approver (HR's roles, or the manager on the HR record, attendance sign-in included) and calls the family's function: it locks the request, re-checks everything, writes the day through `hr_attendance_apply_override` (or the late-excused fields, as HR's own excuse does), and writes the status and history in the same transaction. The route then copies the shift onto a fixed day (`ensureShiftSnapshot`) and re-counts the month (`hr_attendance_recompute`), the Scheduler controller's own order; both are best effort, so a decision that succeeded is never reported failed.
- **On duty ahead of time.** An approval for a future day writes nothing; the morning job (`src/jobs/onDuty.js`) writes it as present on the day itself, with `On duty: <place>` as the note. One process only; idempotent; failures go to the pm2 log and to `hr_ess_audit`.
- **The Inbox.** A manager's list is their direct reports' pending requests (an attendance sign-in may be a manager's); HR's roles see everybody's and may filter by any status. The context is computed in a handful of bounded reads: the month's count per kind, the day's late marks, and who else is off that day.
- **The limits** live in `hr_ess_request_limits`. `GET /ess/me/capabilities` falls back to the code's defaults before that migration; the request endpoints answer 503 until their own tables and the limits are there.
- **Work from home** (KP, 22 Oct) is a leave type with its own per-employee allowance instead of a request-limit row: `hr_ess_wfh_allowances`, one row per selected employee, set by HR (`PUT /ess/hr/wfh-allowances/{employeeId}`, audited) and read by the employee (`GET /ess/me/wfh`, the balances' `wfh` line and the capabilities' `wfh` row). A request is refused 409 `WFH_NOT_ALLOWED` without an enabled row and 409 `WFH_LIMIT` over the month; the decide function re-checks both under a lock and writes the day `present` with `Work from home: <reason>`, keeping the times it already records. The complete flow, the punch caveat and the future Scheduler handover are in [docs/10-wfh-flow.md](../../docs/10-wfh-flow.md).

### Notifications and push (tasks D2, D5-D8)

- **Every notification is an in-app row first**, in `hr_ess_notifications`: filing a request writes one for the approver (the manager on the HR record; HR when nobody is recorded), and a decision writes one for the employee. The Inbox reads them with the unread count; tapping marks one read.
- **The worker** (`src/jobs/push.js`) imports directly assigned priority tasks from the Scheduler's `priority_tasks` (read only; broadcast tasks are not imported) and delivers the queue: FCM when the three `FIREBASE_*` settings exist, the log otherwise. It holds everything between 21:00 and 08:00 IST, retries a failed send up to three times, and revokes a device FCM says belongs to no install.
- **Devices** (`hr_ess_push_devices`) register after sign-in; the token is never returned. Registering a token another row holds moves it and lifts its revocation; signing out revokes it.
- **Categories** (`approvals`, `decisions`, `priority_tasks`) can each be turned off; a turned-off category stays in the Inbox and stops the push. The quiet hours are shown, fixed for now.

### Me and My Team (tasks E1, E2, E6, E8, E10-E12)

- **The profile** reads the HR record, the 1B personal details and an allowlist of `hr_activity_events` (values never selected); pay, performance tags and background notes are never read. The photo is a 300-second signed link; `PUT /ess/me/photo` writes the app-compressed image to the private `documents` bucket and the record's pointer (the Scheduler's own columns), audits it, and leaves the old file for cleanup.
- **The org and directory** work from one read of the active staff (~107 rows): chain, peers, reports, department, search. The contact rule is one function (`policy/me.js`): email to everyone, phone to HR's roles and the manager chain above the person only.
- **Team today and Off this week** read the sheet's day rows; leave types and reasons are never selected. A HoO's view is their branch; a manager's is their reports; nobody's is empty.

### The Wall (tasks F1-F9)

- **The feed** (`hr_ess_wall_posts`, `hr_ess_wall_comments`) is the organisation's wall plus the caller's own branch's. Posts carry text, up to five photos or PDFs (base64 in, ESS bucket out, signed links back), `@RVM-011` mentions and the six reactions; the counts on the row are rewritten from the reaction and comment tables after every change, so the feed is one read. An author edits for 15 minutes and always deletes their own; a delete blanks the row so the trail and the thread keep their shape.
- **Praise** is a post of kind `praise` with one of the twelve fixed badges, a reason of up to 280 characters and an optional photo; it appears in the feed and in `GET /ess/me/praise`. Certificates are Phase 3. **KP to confirm:** this is the profile integration F3 asked for, built as its own read rather than folded into `GET /ess/me/profile`.
- **Polls** are posts of kind `poll`: 2 to 10 options, one or many choices, optionally anonymous (the vote rows keep the voter so a person's own choice can be shown back and not repeated, and no reply ever names them, HR's included), closing on a day. The first vote freezes the option set.
- **Announcements** (`hr_ess_announcements`, `hr_ess_announcement_audience`, `hr_ess_announcement_reads`) are HR's, the CEO's and super admins'. An audience of branches, departments, roles or people is resolved **once**, at publication, into one row per person — that is what makes the read and acknowledgement counts exact and the reminder honest. `publish_at` in the future schedules it; the Wall's job publishes it. Up to three pinned. Email and push are log-only until RVM has a provider.
- **Celebrations** read `hr_employees.date_of_joining` and the 1B `hr_ess_personal_details.date_of_birth`: **day and month only, never the year**, and nothing for anybody who opted out (`hr_ess_celebration_optouts` carries the switch; HR's personal-details screen is unchanged). A wish is a short feed post with an `hr_ess_wall_wishes` row that makes "one each" a database rule.
- **Moderation** (`hr_ess_wall_reports`): anybody reports a post or a comment, HR's queue shows it with the reporter's own words, and HR hides or restores with a reason. Every action goes to `hr_ess_audit` as `wall.post.hidden`, `wall.post.restored`, `wall.comment.hidden`, `wall.comment.restored`, `wall.post.deleted`, `wall.comment.deleted` or `wall.report.resolved`; a hidden thing is 404 for everybody but HR and its author.
- **The rules** are the code's, not a table (F8): `src/policy/wall.js` holds them and `GET /ess/wall/settings` hands the app the same numbers, so a form and its refusal cannot disagree. Everyone posts; only HR, the CEO and super admins announce; only HR moderates.
- **Notifications**: the Wall writes the in-app rows itself (a mention, a reply to my comment, praise, an announcement, the acknowledgement ask and its reminder, a poll closing) through `src/lib/wallNotify.js`; the Phase 1D push worker delivers them unchanged. Migration 16 extends the two category CHECKs with the six Wall categories (the comment in migration 12 said it would).

### The Helpdesk (tasks G1-G5)

- **The categories are fixed in code** (`src/policy/helpdesk.js`) and seeded by migration 17: the six ticket categories of the brief, plus four rows that link to the flows a ticket is not (leave, WFH, an attendance fix, an asset request). `GET /ess/helpdesk/categories` hands the raise form the same list the server refuses on, so form and server cannot disagree; raising on a link is 400 `HELPDESK_NOT_A_TICKET`. G1's HR-editable categories are not built; a change here is a reviewed code change and a migration re-run.
- **Routing is exact** (G5): a ticket lands in the queue of the roles its category names, and nowhere else - nobody inherits their way in, and a role no category names (the CEO's, most staff's) is answered an empty queue. **KP to confirm:** the lab has no desk role (IT and lab tickets go to the admin roles). **POSH** moved to the Internal Committee with Phase 2 (KP, 19 Oct): migration 23 names `internal_committee` the `posh` row's only queue role, and the queue stays empty until RVM appoints the committee and its logins carry that role.
- **The team's work** (G5): comment at any status, claim, or - since Phase 2C (KP, 19 Oct) - assign a live ticket to a named handler with `POST .../assign { employee_id, note? }`. The assignee must hold the category's own queue role (`HELPDESK_ASSIGNEE_ROLE`); assigning sets `claimed_at` and the first response, moves open to in progress, and writes the history row in `hr_ess_helpdesk_assignments`, so a reassign never overwrites who had it first; the event row says who pointed it there. Reassigning to the person who has it answers 200 and does nothing.
- **The lifecycle** (G2) is open, in progress, on hold where the category allows, resolved, closed, plus the raiser's own exits: withdraw while open, close from any live state with a reason of 3 to 280 characters and an optional rating of 1 to 5, and reopen within 7 days - which works the deadlines out again and resets the first response and the escalation. Nothing is deleted: every move is an `event` row in the thread, so the thread is the record. Comments are open at any status, to the raiser and the team.
- **The SLA** (G3) stores both deadlines, worked out at raise in the raiser's branch's working hours (09:00-17:30 IST, Monday to Saturday, plus the Scheduler's `hr_holidays`); every view carries "overdue by" in working minutes, and `src/jobs/helpdesk.js` escalates a past-due live ticket to its team, then the HoO, then the CEO, one notification per stage. **KP to confirm:** the targets are the build's defaults.
- **Confidentiality and anonymity** (G4): grievance and POSH are hidden from every list but their team's - HR's oversight does not reach them; an anonymous raise keeps the raiser in the record but out of the team's view (HR's own roles still see the name); and every read of a confidential ticket by anybody but its raiser is written to `hr_ess_audit` as `helpdesk.ticket.read` before the reply, refused if it cannot be recorded.
- **Notifications** go through `src/lib/helpdeskNotify.js` on the `helpdesk` category (migration 18): a raise tells the team, a claim, an assign and a status move tell the raiser and the assignee, a comment tells the other side, a reopen tells the assignee, the escalation tells its stage. Best effort, as everywhere: a failed write is logged, never raised.
- **The infra register mirror** (G6, decision 9, built 22 Oct): a lab or facility ticket also gets one summary row in the Admin Manager's `infra_tickets` - `it_lab` is audit type A, `facility` D; the issue is `HD-0001: subject`, the branch is mapped to `locations` by name, and an anonymous ticket carries no identity. The link is `hr_ess_infra_links` (migration 27). If the register cannot be written the ticket still goes through, the link says why, and `src/jobs/infra.js` retries hourly. Closing syncs both ways: the ESS closes the register row when the ticket resolves, closes or is withdrawn, and the job resolves the ticket when the Admin Manager closes the register row.

### My documents, profile changes, the bank details and the ID card (Phase 2C)

- **The types are fixed in code** (`src/policy/documents.js`) and seeded by migration 19: resume, identity, certificate, offer, joining, experience, exit and other, plus `others`, which must carry a remark of 3 to 500 characters saying what the file is (a database CHECK holds it too). `identity`, `offer` and `joining` are the mandatory ones the weekly job asks for; each is marked on its type row, so KP can turn one off with one UPDATE. No Aadhaar number is stored anywhere.
- **The upload is the person's own**: base64 in, the file to the ESS bucket's `documents/` path, the row pending. At most 50 documents a person keeps, 5 MB a file, 30 uploads a day; a delete takes one of the person's own off. HR verifies (`POST .../verify` with an empty body) or rejects with a reason of 3 to 500 characters; a reviewed document refuses a second answer (409 `DOCUMENT_REVIEWED`).
- **Identity documents are gated** (KP 2): only HR (the `hr` role), the CEO and super admins may open one; an HR Executive is 403 `DOCUMENT_IDENTITY_ROLE`. Every opening is audited with the record kept before it, and identity rows are dropped from HR's list responses for a reader who cannot open them.
- **A profile change is a request, not a write** (E3): the person files what the record shows and what it should read, with a reason of 5 to 1,000 characters; the database holds one open request per field per person. HR decides with a note - the ESS records the decision only and never writes `hr_employees` (ADR-0003); HR applies the change in the Scheduler by hand.
- **The bank details carry their consent** (KP 3): a save needs `consent: true`, the person's own `consent_name` and stamps `consent_given_at`. The account number is shown to everybody but its owner as `******` plus the last four digits, never appears in a list response, and every HR read is audited with the record kept before it - even a read that finds nothing.
- **The ID card's QR holds a signed link** (E7): `GET /api/ess/id-card/verify/{token}` takes no sign-in; the token is an HMAC (`src/lib/idCardKit.js`) that expires after 90 days and answers only the holder's name, photo, designation, branch and "active employee". A bad, expired or archived-holder link is 401 `ID_CARD_BAD_TOKEN`, and the route is limited to 30 verifications a minute per address.
- **The weekly reminder** (`src/jobs/documents.js`, the `documents` notification category from migration 24) goes to every person still missing a mandatory type, and names the types they personally lack - one held document does not hide the rest. A person can turn the category off like any other.

### Leader and faculty views, and the deeper approvals (Phase 2D)

- **The leaders' overview** (`src/routes/leaders.js`, H5) is for the CEO and super admins only, and answers counts: active headcount, today's attendance states, how many people are on leave this IST week, and the pending attendance and leave requests with the oldest one's age. No name, pay or performance value is selected, so none can leak.
- **The faculty "my day"** (`src/routes/facultyDay.js`, H7) resolves the caller's `users.faculty_id`; a login without one is 403 `NOT_FACULTY`. It reads the batches they own and the ones covered by a `faculty_substitutions` row whose range includes the day (other centres included, never branch-filtered), each with its times, centre, joined-student count and whether `student_attendance` holds a mark for that batch and date. The card adds today's and the month's marked-session percentages (expected sessions come from each batch's weekdays inside its own dates), the joined, not-on-hold student counts, and the remarks still due (`pending_alerts` of type `absent_remarks_missing`). Counts only: no student's name, phone or remarks are read.
- **The approval chain** (`src/routes/approvals.js`, `src/policy/approvals.js`, D4) walks the reporting line and says why a level is skipped (`same_person`, `not_active`, `on_leave`), who may decide now, and whether only HR's fallback is left. The hourly job (`src/jobs/approvals.js`) escalates a request pending past two IST days to the next unskipped level, once per person (the table's unique key), notifies them in the `approvals` category, and falls back to HR when the line is exhausted. Archiving clears a request from one approver's Inbox only.
- **Short leave** (C3) is a fourth attendance-request type counted in minutes (1 to 480 a day; 180 a month by default), approved through the same decide function; the approval excuses the late it covers, exactly as an excuse-late does, and HR's cancel restores the day. The monthly limit is a row in `hr_ess_request_limits`, so HR changes it with the limits endpoint.
- **Class marking** (`src/routes/classMarking.js`, `src/policy/classMarking.js`, H1, decision 8) is for teaching roles (`faculty`, `hod`) and the Scheduler's admin roles. It enforces the six rules the Scheduler's own marking lacks: the role, the branch (an admin's `hr_branches.name` mapped to `locations.name`; the CEO and super admins global), ownership or a covering `faculty_substitutions` row, the day window, the eligible roster (`joined_at`, `admissions.joined` unless no admissions row, not on hold), and the teaching lock. The save upserts `student_attendance` on its `(batch_id, student_id, date)` key and resolves `pending_alerts` of type `absent_remarks_missing` when a student is present or the reason is given with the save (the remark route does the same when a reason is filled later). The roster returns a student's name, admission number and mark only; the audit entries carry counts and the before/after reason, never a name.

### How sign-in is checked

`src/middleware/employeeAuth.js` (task A1) reads `Authorization: Bearer <token>`. It tries the attendance session first and then the portal JWT, as the Scheduler's `punchAuth` does, and verifies both with HS256 only (`src/lib/tokens.js`). It re-reads the employee on every request. The checks and their order are the Scheduler's `loadEmployee` and `sessionProblem` at `c28b9ca`, including the whole-second `sessions_valid_from` comparison. A portal token is resolved through `hr_employees.user_id`.

## Errors

Every refusal is `{ "error": "<message for staff>", "code": "UPPER_SNAKE" }`. **The app signs out on 401 only.**

| Status | Code | When |
| --- | --- | --- |
| 401 | `NOT_AUTHENTICATED` | No token; a bad signature; expired; the wrong algorithm; a deleted account or employee; an attendance session issued before its login's `sessions_valid_from`; a token the ESS minted whose sign-in has ended; a portal sign-in kept from before the password last changed. A refused refresh adds `reason`. Sent with `WWW-Authenticate: Bearer` |
| 403 | `NOT_AN_EMPLOYEE` | A valid token that is not a staff login: a student token, an admission-undertaking token, any other token signed with `JWT_SECRET`, or the connector account |
| 403 | `NOT_LINKED` | A portal login with no HR record (`hr_employees.user_id`) |
| 403 | `NOT_ACTIVE` | The employee has left: archived, exited, or past the last working day (IST) |
| 403 | `NO_ATTENDANCE_LOGIN` | An attendance session whose login is missing or switched off |
| 403 | `PASSWORD_CHANGE_REQUIRED` | An attendance session signed in with HR's first-time password, before the person chose their own |
| 403 | `SIGN_IN_NOT_FRESH` | Keeping a sign-in made more than 10 minutes ago |
| 403 | `PORTAL_LOGIN_REQUIRED`, `HR_ACCESS_DENIED`, `ATTENDANCE_OVERRIDE_DENIED`, `SENSITIVE_FIELD` | HR's tools refused to this sign-in or role; a self-service change HR must make |
| 403 | `NOT_FACULTY` | A login with no `users.faculty_id` asking for the faculty "my day" (H7) |
| 403 | `CLASS_ROLE_DENIED`, `CLASS_NOT_YOURS`, `CLASS_WINDOW` | Class marking (H1): a role outside teaching and the admin roles; another owner's batch or another branch; a day before the batch starts or after today |
| 403 | `NOT_AN_APPROVER` | A request that is not this sign-in's to decide or clear: neither HR's roles nor the person's manager on the HR record |
| 409 | `ALREADY_EXCHANGED` | Keeping a token the ESS minted itself, or a Scheduler sign-in already kept once |
| 409 | `REFRESH_IN_PROGRESS` | A refresh token traded in less than a minute ago, presented again by the same install: retry with the newest one |
| 409 | `OWN_REQUEST`, `OWN_RECORD`, `ALREADY_RESOLVED`, `TOO_MANY_OPEN_REQUESTS`, `RECORD_CHANGED` | HR acting on their own data; a request already answered; 5 open requests (counted by the database, too); personal details another save changed meanwhile so that half an emergency contact would be left |
| 409 | `DUPLICATE_REQUEST`, `LIMIT_REACHED`, `REQUEST_CLOSED`, `REQUEST_WINDOW`, `REQUEST_FUTURE`, `REQUEST_NOT_PENDING`, `ALREADY_DECIDED`, `NOT_LATE`, `TIMES_INCOMPLETE`, `DAY_LOCKED`, `CL_LIMIT`, `WFH_NOT_ALLOWED`, `WFH_LIMIT`, `CANNOT_CANCEL` | A request cannot move: the same type and day already waits; over the month's limit; last month past the cut-off, or a day before last month; a fix or an excuse for a day that has not happened; a withdraw of something decided; a second decision; an excuse of a day that is not late; a fix leaving no in or out time; a fix on a leave, week-off or holiday; a second CL in the month; WFH not enabled by HR, or the month's WFH allowance used up; a cancel of something not approved |
| 409 | `CLASS_ALREADY_MARKED`, `CLASS_NOT_ABSENT` | Class marking (H1): a teaching role saving a day already marked; a remark for a student who is present or not marked |
| 403 | `NOT_YOURS` | The Wall: somebody else's post or comment. Only its author edits or deletes it |
| 403 | `NOT_AN_ANNOUNCER`, `MODERATE_DENIED`, `NOT_IN_AUDIENCE` | The Wall: an announcement from a role outside HR, the CEO and super admins; a hide, the report queue or the moderation log from anybody but HR; an announcement that was not sent to this person |
| 409 | `EDIT_WINDOW_CLOSED`, `ALREADY_WISHED`, `POLL_CLOSED`, `POLL_OPTIONS_LOCKED`, `ALREADY_REPORTED`, `ALREADY_HIDDEN`, `NOT_HIDDEN`, `PIN_LIMIT`, `ACK_CLOSED` | The Wall cannot move as asked: past the 15 minutes; this year's wish is already there; the poll is closed or the option set is frozen; HR already has this person's report; a second hide or a restore of something not hidden; three announcements are pinned; the acknowledgement date has gone |
| 409 | `HELPDESK_NOT_OPEN`, `HELPDESK_NOT_LIVE`, `HELPDESK_ALREADY_CLAIMED`, `HELPDESK_TRANSITION`, `HELPDESK_NOT_CLOSED`, `HELPDESK_REOPEN_WINDOW` | The Helpdesk ticket cannot move as asked: a withdrawal of anything but an open ticket; a claim of a settled or withdrawn one, or one somebody else has already claimed; a close or status move the lifecycle refuses; a reopen of anything not resolved or closed, or past the 7 days |
| 403 | `HELPDESK_ASSIGNEE_ROLE` | An assign to somebody who does not hold the category's queue role |
| 403 | `DOCUMENT_IDENTITY_ROLE` | An identity document opened by somebody but HR (the `hr` role), the CEO and a super admin |
| 409 | `DOCUMENT_LIMIT`, `DOCUMENT_REVIEWED` | The person already holds 50 documents; a document HR has already verified or turned away |
| 409 | `CHANGE_ALREADY_OPEN` | A change request filed while another for the same field still waits |
| 401 | `ID_CARD_BAD_TOKEN` | A verify link that is not valid, has expired, or belongs to somebody who has left |
| 404 | `NOT_FOUND` | No such endpoint, or a method the endpoint does not take (OPTIONS included); a session that is not one of the caller's; or no such request, employee or branch |
| 404 | `EMPLOYEE_NOT_FOUND` | The WFH allowance save names an employee who is not on the record or has left |
| 404 | `BATCH_NOT_FOUND` | Class marking (H1): no batch has that id |
| 400 | `INVALID_JSON` | A request body that is not valid JSON |
| 400 | `BAD_INSTALL_ID`, `BAD_DEVICE_LABEL`, `BAD_IDENTIFIER` | A missing or malformed install id, phone name or sign-in identifier |
| 400 | `VALIDATION_FAILED`, `DAY_OUT_OF_RANGE` | A field, query or id the endpoint refuses; the message says which |
| 413 | `PAYLOAD_TOO_LARGE` | A JSON body over 16 kB (32 kB for the phone reset's id list, 2 MB for a photo, 7 MB for a Wall post, praise or announcement, or a Helpdesk raise) |
| 429 | `RATE_LIMITED` | Over 600 requests a minute from one address (before sign-in), or 120 a minute from one employee (after it). Tighter on the session and sign-in endpoints: 120 refreshes and sign-outs by refresh token in 15 minutes per address, 10 kept sign-ins in 15 minutes per employee, and 40 resolves in 15 minutes per address and 10 per identifier; 30 mocked-location reports a day per employee, 60 Wall posts and 200 comments a day, 60 reactions a minute, 20 raised tickets a day, 30 document uploads a day, and 30 ID-card verifications a minute per address (`src/middleware/rateLimit.js`). Sent with `Retry-After` |
| 503 | `UNAVAILABLE` | The database could not be reached. Never a 401 |
| 503 | `MODULE_NOT_INSTALLED` | A table, column or function the ESS needs is missing: the code is live before its migration ([ADR-0021](../../docs/adr/0021-migrations-new-tables-only.md)) |
| 503 | `MODULE_DISABLED` | `ESS_ENABLED=false` |
| 500 | `INTERNAL_ERROR` | Anything unexpected, including a write the database refused (a constraint the ESS's own checks should have caught). The detail goes to the pm2 log, never to the reply |

## Running it

`ecosystem.config.cjs` runs one instance in fork mode, named `team-rvm-ess`, with `PORT=3740`, listening on `127.0.0.1` (`HOST`). It must stay one instance: the rate limits are counted in memory, and the background jobs still to come must run once. The deploy is `.github/workflows/deploy-ess.yml` ([ADR-0011](../../docs/adr/0011-ci-merge-and-auto-deploy.md)). After the process answers, it runs `deploy/configure-nginx.sh` on the server. That script writes the ESS's own nginx file (`/etc/nginx/sites-available/team-rvm`), gets its certificate with certbot, and reloads nginx only when `nginx -t` passes for the whole server, putting the last good file back when it fails ([ADR-0019](../../docs/adr/0019-ess-on-its-own-subdomain.md)). The Scheduler's nginx files are never written ([ADR-0018](../../docs/adr/0018-team-app-changes-nothing-in-the-scheduler.md)). `deploy/test-nginx.sh` runs each case against a real nginx in a container; CI runs it on every push.

`@supabase/supabase-js` is held below 2.110, because 2.110 and later need Node 22 and the server's Node version is not confirmed ([ADR-0017](../../docs/adr/0017-repository-layout-and-tooling.md)). Lift the cap once the server runs Node 22 or later. The development tools (ESLint 10, vitest 4) need Node 20.19 or later.
