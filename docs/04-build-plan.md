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

### Phase 1D: Inbox, notifications and push — built 19 Oct 2026

The brief's Phase 1. Built and tested; waiting for migrations 11 and 12.

| Work | How | Tasks | State |
| --- | --- | --- | --- |
| Phone registration | `POST /api/ess/push-devices` and `DELETE /…/{id}`: one install is one row; registering a token another row holds moves it to the caller and lifts any revocation. The token is never sent back | D5 | Built |
| The notifications Inbox | `hr_ess_notifications`: the ESS writes a row for its own events; `GET /api/ess/notifications` lists the caller's own with the unread count; `POST /…/{id}/read` and `/read-all` mark them | D6 | Built |
| The push worker | `src/jobs/push.js`, once at boot then every minute: FCM HTTP v1 with a service-account JWT when the three `FIREBASE_*` settings exist, the log otherwise (ADR-0016). Nothing is pushed 21:00–08:00 IST. A failed send is retried each minute, 3 attempts at most; a token FCM says belongs to no install is revoked | D7, D8 | Built |
| Categories and their events | Filing a request notifies the approver (the manager on the HR record, HR when nobody is recorded); a decision notifies the employee. Each category can be turned off through `GET`/`PUT /api/ess/notifications/settings` | D6, D8 | Built |
| Priority tasks | A task assigned to one person in the Scheduler's `priority_tasks` becomes a `priority_tasks` notification once (48-hour window, one per task and person). Broadcast tasks (`assigned_to` NULL) are NOT pushed: their recipients are the Scheduler's admin set, resolved in its own code, and changing that is a Scheduler change (D2) | D2 | Built, direct assignments |
| Interview reminders | The optional extra | Brief | Not built (optional; the interview calendar is tied to portal logins in the Scheduler) |

**What the build chose, for KP to confirm:**
- **Quiet hours are fixed** at 21:00–08:00 IST; the app's settings show them but do not change them in this phase. The in-app row is always written at once.
- **A notification is attempted on every live phone** the person has; success on one is enough. After 3 failed attempts the row is marked skipped, so a dead phone cannot jam the queue.
- **The categories are Phase 1's three** (`approvals`, `decisions`, `priority_tasks`); the Wall's (mentions, replies, praise, announcements, acknowledgement reminders, polls) extend the migration's CHECK in Phase 2.
- **Priority-task push covers direct assignments only.** The Scheduler's broadcast tasks need its own role rules, which stay as they are.

**Tests:** 84 new endpoint and worker tests (devices, notifications, read state, settings, the worker's log-only and FCM paths, retries, quiet hours, token revocation, priority-task import) and 7 new contract operations with every documented status; the full suite is 1,492 tests. The migration suite covers migrations 11 and 12, their rollbacks, their CHECKs and the cascade.

**You first:** the Firebase project and the three `FIREBASE_*` secrets (Phase 0). Without them everything works, but push is a log line.
**You after:** apply migrations 11 and 12 ([05-deploy.md](05-deploy.md#migrations-to-apply)). Until then the notification, settings and device endpoints answer 503; filing and deciding still work, without notifications.
**Done when:** a decision or a priority task reaches the phone; the Inbox shows it with its unread count; a category turned off stays quiet.

### Phase 1E: Me and My Team — built 19 Oct 2026, live

| Work | How | Tasks | State |
| --- | --- | --- | --- |
| Profile | `GET /api/ess/me/profile`: Summary, Job, Personal (1B) and the Timeline — an allowlist of employee events, values and HR remarks never read. Pay, performance tags and background notes are never selected | E1, E12 | Built |
| Photo | 300-second signed links; `PUT /api/ess/me/photo` stores the app-compressed image in the private `documents` bucket and updates the record's photo pointer (the Scheduler's own columns), audited. Old file left for cleanup; no HR approval (KP to confirm) | E10 | Built |
| Org | `GET /api/ess/me/org`: chain to the CEO ("Reports to the CEO (not recorded)"), peers, direct reports, department; people on notice keep the chip | E2, E11 | Built |
| Directory | `GET /api/ess/directory`: name/code search, branch and department filters; email to everyone, phone to HR and the manager chain only (decision 5's default: a report does not see a manager's phone) | E2, E8 | Built |
| Team | `GET /api/ess/team/today` (reports, or the HoO's whole branch) and `/team/off-this-week` (reports, else peers; names and days only) | E6, H4 | Built |

**No migrations.** 1E reads the Scheduler's records; the only write is the photo pointer on `hr_employees` (documented in the store, same columns as the Scheduler's own setPhoto).
**Not built:** the HOD domain roster — the domain→faculty mapping lives in the HOD module, not on the HR record; it goes with 2D's faculty views. HODs still see their reports.
**Tests:** 41 new endpoint tests and the contract at 0.5.0 (533 contract checks); the full suite is 1,569.

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
- the faculty "my day" read (H7);
- faculty class marking (H1, decision 8).

### Phase 2A: the Wall — built 19 Oct 2026

The brief's Phase 2 community features, built to this plan, tested, and waiting for its migrations
(13 to 16 below). Everything is in `apps/ess-api` and `db/migrations/20261108000000` to
`20261108000004`.

| Work | How, with no Scheduler change | Tasks | State |
| --- | --- | --- | --- |
| Posts on the organisation wall and one per branch | `hr_ess_wall_posts`: text, up to 5 photos or PDFs (base64 in, the ESS's own bucket `ESS` out, 300-second signed links back), `@RVM-011` mentions, the author's edit inside 15 minutes (`edited: true`) and always-available delete | F1, F9 | Built |
| Six reactions, comments and one level of replies | `hr_ess_wall_reactions` (one per person per post AND per comment), `hr_ess_wall_comments` (`parent_id`, never a reply of a reply), the counts on the rows rewritten from the tables | F2 | Built |
| Praise with RVM's badges | `hr_ess_wall_posts` kind `praise`: one of twelve **fixed** badges (KP, 19 Oct: the catalogue ships in code), a reason of up to 280 characters, an optional photo; `GET /api/ess/me/praise` is the receiver's own read. Certificates are Phase 3 | F3 | Built |
| Polls | kind `poll` with `hr_ess_wall_poll_options` and `hr_ess_wall_poll_votes`: 2 to 10 options, one or many choices, anonymous (nobody, HR included, sees who voted what), a closing day, the option set frozen by the first vote | F4 | Built |
| Staff announcements | `hr_ess_announcements` plus the resolved audience and the read state in their own tables: audience by branch, department, role or named people, now or scheduled, a closing date, acknowledgement, read and acknowledgement counts for the sender, up to 3 pinned. Email and push are log-only. **The Scheduler's student notices are not touched** | F5 | Built |
| Celebrations | Birthdays from `hr_ess_personal_details.date_of_birth` (**day and month only, never the year**, hidden for anybody who opts out), work anniversaries and new joiners from `hr_employees.date_of_joining`, and a one-tap wish (a short feed post; one per person per occasion per year) | F6 | Built |
| Moderation | `hr_ess_wall_reports`: anybody reports, HR's queue and the hide/restore routes with a reason (3 to 200 characters), every action in `hr_ess_audit` as `wall.post.hidden` and its neighbours | F7 | Built |
| Wall settings | `GET /api/ess/wall/settings`: the rules in `src/policy/wall.js` (everyone posts, only HR/CEO/super admins announce, only HR moderates) with the badge catalogue | F8 | Built |
| The Wall's clock | `src/jobs/wall.js`, one process: scheduled announcements, acknowledgement reminders inside two days of the close, polls closing (and the voters told) | F4, F5 | Built |
| The Wall's notification categories | Migration 16 extends the CHECKs on `hr_ess_notifications.category` and `hr_ess_notification_settings.disabled_categories` with `mentions`, `replies`, `praise`, `announcements`, `acknowledgements` and `polls`, as migration 12's comment said Phase 2 would | F8 | Built |

**What the build had to choose, for KP to confirm:**
- **A post's default wall is the author's own branch**, not the organisation's: `scope: 'org'` is
  explicit. A branch post is refused for any branch but the author's own.
- **A praise is refused for yourself** ("Praise goes to somebody else"), which F3 does not say and
  the build had to decide.
- **Praise on the profile** is `GET /api/ess/me/praise` rather than part of
  `GET /api/ess/me/profile`, so the profile's shape does not change.
- **A birthday is day and month only** in every reply; the opt-out is its own table, so HR's
  personal-details screen is untouched.
- **Announcement counts are "sent / read / acknowledged"**, resolved once at publication into one
  row per person; a reader of an announcement that was not sent to them is 403 `NOT_IN_AUDIENCE`.
- **Only HR moderates and reads the report queue** (`MODERATE_ROLES`); the CEO and super admins
  read the trail of their own announcements' counts only. Decision 8 said "HR can hide anything".
- **A hidden comment keeps its place with no words** for everybody but HR and its author; a hidden
  post is 404 for everybody but its author and HR.
- **The Wall's own rate limits**: 60 posts and 200 comments a day per employee, 60 reactions a
  minute.

**Tests:** the suite is 2,069 (41 files), the contract at 0.6.0 with 903 contract checks (every
route's every documented status provoked, Wave 6 included); the Wall's own files are
`wallPosts`, `wallComments`, `wallPraise`, `wallPolls`, `wallAnnouncements`,
`wallCelebrations`, `wallModeration` and `wallJob`. `npm run test:migrations` applies all
sixteen migrations and their rollbacks twice and runs the Wall's row rules themselves.

**You after:** apply migrations 13 to 16, in order ([05-deploy.md](05-deploy.md#migrations-to-apply)).
Until 13 to 15 are applied the Wall's endpoints answer 503 `MODULE_NOT_INSTALLED` except
`GET /api/ess/wall/settings`, which is the code's own rules; until 16 is applied the Wall's
notifications are logged as failed writes and nothing else changes.

**Done when:** posts, praise, polls and announcements work end to end, with notifications from
Phase 1D; a mention, a reply and praise each reach the phone's Inbox; an announcement's counts
match who read and acknowledged it; and HR can hide anything with a reason, with the trail to show
for it.

The decisions listed below shape several of these.

### Phase 2B: the Helpdesk — built 19 Oct 2026

The brief's helpdesk, built to this plan, tested, and waiting for its migrations (17 and 18
below). Everything is in `apps/ess-api` and `db/migrations/20261109000001` and `20261109000002`.

| Work | How, with no Scheduler change | Tasks | State |
| --- | --- | --- | --- |
| The category list and the rules document | `hr_ess_helpdesk_categories`: the brief's six ticket categories and the four links to flows that are not tickets (leave, WFH, an attendance fix, an asset request), each with its queue roles, priority, SLA hours and flags; `GET /api/ess/helpdesk/categories` hands the raise form the same list the server refuses on | G1 | Built |
| Tickets HD-0001 onwards | `hr_ess_helpdesk_tickets`: raise with base64 attachments (as the Wall's), my list, one ticket with its thread; the lifecycle of open, in progress, on hold (where the category allows), resolved, closed and withdrawn; the raiser withdraws an open ticket and closes a settled one with a reason and an optional rating of 1 to 5; reopen within 7 days resets the SLA; nothing is deleted — every move is an `event` row in the thread | G2 | Built |
| Response times and escalation | The two deadlines are worked out at raise in the raiser's branch's working hours (09:00–17:30 IST, Monday to Saturday, plus `hr_holidays`) and stored, so the job judges them against the clock; each view carries "overdue by" in working minutes; `src/jobs/helpdesk.js` escalates a past-due ticket to its team, then the HoO, then the CEO | G3 | Built |
| Confidential categories and anonymity | Grievance and POSH are confidential: never in HR oversight's lists, seen only by their team; an anonymous raise hides the raiser from the team (the record keeps them); every read of a confidential ticket by anybody but its raiser is written to `hr_ess_audit` first, and a failed audit refuses the read | G4 | Built |
| The agents' workspace | `GET /api/ess/helpdesk/queue` (portal sign-ins only): the tickets of the categories the caller's own role serves, exact membership, with `?status=` and `?category=`; comment, claim (which names the assignee and counts as the first response) and the status moves | G5 | Built |
| The non-ticket links | The category list marks them `is_ticket: false` with their `flow`; raising on one is refused | Brief | Built |

**What the build had to choose, for KP to confirm:**
- **The lab has no desk role and the Internal Committee has no login**, so IT and lab tickets go
  to the admin roles and POSH tickets to HR (the category table is fixed in code and seeded by
  migration 17; HR's own category-editing is not built).
- **Queue membership is exact** — a role no category names (the CEO's, most staff's) is answered
  an empty queue, not a refusal, and confidential categories are hidden from every list but their
  team's.
- **A claim is the only way a ticket gets an assignee unless the team assigns it**: assign and
  reassign came with Phase 2C (KP, 19 Oct), and the infra-register mirror came on 22 Oct (G6,
  decision 9): `it_lab` -> audit type A and `facility` -> D get one summary row in the Admin
  Manager's `infra_tickets`, linked through `hr_ess_infra_links` (migration 27), with anonymous
  tickets carrying no identity and closing syncing both ways.
- **The SLA targets are the build's defaults** (IT and facility 8 and 48 working hours; HR
  documents and payroll 24 and 72; grievance 12 and 48; POSH 12 and 72), for KP to confirm.
- **The working-hours calendar is a policy constant** (`src/policy/helpdesk.js`) plus the
  `hr_holidays` the Scheduler keeps, so a change to RVM's hours is a reviewed code change.
- **A raise is limited to 20 tickets a day per employee** (the Helpdesk's own bucket, like the
  Wall's), and comments are not limited beyond the ESS-wide limits.

**Tests:** the suite is 2,198 (45 files), the contract at 0.7.0 with 1,002 contract checks (every
route's every documented status provoked, Wave 7 included); the Helpdesk's own files are
`helpdeskTickets`, `helpdeskQueue` and `helpdeskJob`. `npm run test:migrations` applies all
eighteen migrations and their rollbacks twice and runs the Helpdesk's row rules themselves.

**You after:** apply migrations 17 and 18, in order ([05-deploy.md](05-deploy.md#migrations-to-apply)).
Until 17 is applied every Helpdesk endpoint answers 503 `MODULE_NOT_INSTALLED`; until 18 is
applied the Helpdesk's notifications are logged as failed writes and nothing else changes.

**Done when:** a raise reaches the right team's queue and is answered, moved and closed end to
end, with the deadlines, the "overdue by" and the escalations to prove the SLA works; a
confidential ticket is seen by nobody it should not be, with the audit trail to show for it.

### Phase 2C: documents, profile changes and the ID card — built 19 Oct 2026

The brief's documents, profile changes and ID card, built to this plan and waiting for its
migrations (19 to 24 below). Everything is in `apps/ess-api` and
`db/migrations/20261110000001` to `20261110000006`. The Helpdesk's assign-and-reassign delta
(KP, 19 Oct) came with it and waits for migration 22.

| Work | How, with no Scheduler change | Tasks | State |
| --- | --- | --- | --- |
| My documents | `hr_ess_documents` behind `POST/GET/DELETE /api/ess/me/documents`: the fixed types (resume, identity, certificate, offer, joining, experience, exit, other, plus `others` with its required remark), base64 in, the ESS bucket out (`documents/`), at most 50 a person, 30 uploads a day, each row pending until HR answers | E4 | Built |
| HR's review | `GET /api/ess/hr/employees/{id}/documents`, and `POST .../documents/{docId}/verify` and `/reject` (a rejection says why, 3 to 500 characters); a reviewed document refuses a second answer with 409 `DOCUMENT_REVIEWED`; delete is a plain 204, no status check | E4, E5 | Built |
| Identity documents gated | Only hr, ceo and super_admin may open one (`src/policy/documents.js` `IDENTITY_ROLES`, the one place the rule lives); an HR Executive is 403 `DOCUMENT_IDENTITY_ROLE`; every opening is audited with the record kept before it; identity rows are dropped from list responses for a reader who cannot open them; no Aadhaar number is stored | E4 | Built |
| The weekly reminder | `src/jobs/documents.js`, weekly: one `documents` notification per person still missing a mandatory type, naming the types they personally lack (one held document does not hide the rest); migration 24 adds the category | E4 | Built |
| Profile changes as requests | `hr_ess_change_requests` behind `POST/GET /api/ess/me/change-requests` and `GET /api/ess/hr/change-requests`, `POST .../{id}/decide`: the three fields (date of birth, address, legal name), old and new value, one open request per field per person (the database refuses the second); the decision is recorded only, never written to `hr_employees` | E3 | Built |
| Bank details | `hr_ess_bank_details` behind `GET/PUT /api/ess/me/bank-details` and HR's `GET /api/ess/hr/employees/{id}/bank-details`: one row per person, saved only with the consent name typed and stamped; masked to everybody but its owner (the last four); never in a list response; every HR read audited | KP 3 | Built |
| The ID card | `GET /api/ess/me/id-card` (the card from the HR record and the personal details) and `GET /api/ess/id-card/verify/{token}`: an unauthenticated, HMAC-signed, 90-day verify link in the QR, answering only name, photo, designation, branch and "active employee"; 401 `ID_CARD_BAD_TOKEN` for a bad, expired or archived-holder link; 30 verifies a minute per address | E7 | Built |
| Assign and reassign | `POST /api/ess/helpdesk/tickets/{id}/assign` (`{ employee_id, note? }`): live tickets only; the assignee must hold the category's queue role (`HELPDESK_ASSIGNEE_ROLE`); sets `claimed_at`, the first response, open to in progress; the history row lands in `hr_ess_helpdesk_assignments` (migration 22); POSH's queue moves to `internal_committee` (migration 23) | KP 5, KP 6 | Built |

**What the build had to choose, for KP to confirm:**
- **the document types are fixed in code** and seeded by migration 19, mandatory ones marked on
  the type row (`identity`, `offer`, `joining`) so KP can turn one off with one UPDATE;
- **`others` is the ESS's own escape hatch** and must say what the file is (a remark of 3 to 500
  characters, held by a database CHECK too);
- **bank details are HR-read-only**: HR sees the masked number with an audit entry, never the
  whole row;
- **the verify link's 90 days and its 30-a-minute limit are policy constants**
  (`src/lib/idCardKit.js`, `src/middleware/rateLimit.js`), for KP to confirm.

**Tests:** the suite is 2,401 in 50 files, the contract at 0.8.0 with 1,152 contract checks
(every route's every documented status provoked, Wave 8 included). Phase 2C's own files are
`documents`, `changeRequests`, `bankDetails`, `idCard`, `helpdeskAssign` and `documentsJob`.
`npm run test:migrations` applies all twenty-four migrations and their rollbacks twice and runs
the new tables' row rules themselves (unknown types, the `others` remark, the one-open request,
the bank shapes, the cascades).

**You after:** apply migrations 19 to 24, in order ([05-deploy.md](05-deploy.md#migrations-to-apply)).
Until 19 to 21 are applied the document, change-request and bank-details endpoints answer 503
`MODULE_NOT_INSTALLED`; until 22 the assign endpoint does; until 24 the reminders are logged as
failed writes.

**Done when:** a person uploads each mandatory document, HR verifies or turns it away with a
reason, and the weekly reminder reaches only those still missing one; a change request reaches
HR's queue and its answer is recorded; a bank row carries its consent and shows only its last
four digits to anybody but its owner; a card's QR link proves an employee without a sign-in.

### Phase 2D: leader and faculty views and deeper approvals — built 19 Oct 2026

The brief's Phase 2 close: the light KPI cards, the faculty "my day", the approval chains and
short leave, built to this plan and deployed. Everything is in `apps/ess-api`; migrations 25-26
carry the two database changes.

| Work | How, with no Scheduler change | Tasks | State |
| --- | --- | --- | --- |
| The leaders' overview | `GET /api/ess/leaders/overview` for the CEO and super admins: headcount, today's attendance states, who is off this week, and the approval queue with the oldest request's age. Counts only -- no names, pay or performance | H5 | Built |
| The faculty "my day" | `GET /api/ess/me/faculty-day?date=`: today's sessions owned or covered through `faculty_substitutions` (other centres included), with times, centre, students and a `marked` flag; the unresolved `absent_remarks_missing` alerts; the indicators card (today's and the month's marked-session percentages, joined/active students, sessions without attendance). Counts only | H7 | Built |
| Approval chains | `GET /api/ess/approvals/{family}/{id}/chain` (each level, its skip reason and the first that may decide; `hr_fallback` when none can) and `POST .../archive` (clear one approver's Inbox without deciding). An hourly job escalates a request pending past the window to the next level, records it and notifies | D4 | Built |
| Short leave | A fourth attendance-request type, counted in minutes: 1 to 480 a day, 180 a month by default (seeded in `hr_ess_request_limits`). An approval excuses the late it covers, exactly as an excuse-late does; HR's cancel restores it | C3 | Built |
| Class marking | `GET /api/ess/me/batches/{id}/roster?date=`, `POST .../attendance` and `PATCH .../attendance/{date}/remarks` (decision 8, 19 Oct): the Scheduler's six checks enforced server-side (role, branch, ownership or substitution, date window, roster eligibility, the teaching lock). The save upserts `student_attendance` and resolves `pending_alerts`, the two sanctioned writes; admin roles may correct a day | H1 | Built |

**What the build had to choose, for KP to confirm:**
- **the escalation window is two IST days**, one level a run, HR the fallback when the line is
  exhausted -- a policy constant in `src/policy/approvals.js` and the job, not a database setting;
- **short leave's monthly limit is 180 minutes**, seeded with the other limits so HR can change it
  with the limits endpoint;
- **the month's percentage** counts each batch's weekdays inside its own start and end dates, up
  to the asked day, against the days marked in `student_attendance` -- the Scheduler report's rule,
  without its branch filter (a substitution batch is never branch-filtered there either);
- **the HOD domain roster is still not built**: the domain-to-faculty mapping lives in the HOD
  module, not on the HR record (see Phase 1E);
- **the class-marking lock closes the day's marks, not its reasons**: a teaching role may fill an
  absent student's remark after the first save; the remark route changes no mark, and an admin
  role may correct the marks too.

**Tests:** the suite is 2,518 in 55 files, the contract at 0.10.0 with 1,218 contract checks
(Waves 9 and 10 included). Phase 2D's own files are `leaders`, `approvalsChain`, `facultyDay`,
`classMarking` and `approvals` (the policy and the job); `tests/classMarking.test.js` covers the
roster for an owner, a covering substitute and an admin, the role, branch, ownership, window,
roster and lock refusals, the alert resolution, the remark rules and the no-leak reply.
`npm run test:migrations` applies all twenty-seven migrations and their rollbacks twice.

**You after:** apply migrations 13 to 16 (the Wall's) and 27 (the infra link); 25-26 are applied.
Until 13-16 are applied every Wall endpoint but its settings answers 503 `MODULE_NOT_INSTALLED`;
until 27, the register mirror is skipped and retried, and tickets are unaffected.

**Done when:** the CEO sees the organisation in numbers with no name in the reply; a faculty
member sees today's batches -- including the one they cover -- with what is marked and what is
not; a request older than two days climbs one level and the person told can see the chain; a
short leave is counted in minutes and excuses the late it covers.

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
- **Role views:** H2-H3, and the short-leave rule inside `hr_attendance_recompute`.
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
8. **Faculty marking — decided 22 Oct.** Should the app offer class-attendance marking while the Scheduler's checks on it (J1) stay open? **Decided:** yes, to [07-plan-decisions-8-and-9.md](07-plan-decisions-8-and-9.md) — three ESS routes, the Scheduler's six checks enforced server-side, and the sanctioned writes to `student_attendance` (upsert and remark update) and `pending_alerts` (resolve). Built in Phase 2D above.
9. **Infra register — decided 22 Oct.** Should lab and facility helpdesk tickets also add a row to the Admin Manager's infra register? **Decided:** yes, to [07-plan-decisions-8-and-9.md](07-plan-decisions-8-and-9.md) — an `hr_ess_infra_links` table, a summary `infra_tickets` row on raise, and close-sync both ways without a Scheduler change. The sanctioned writes are the `infra_tickets` insert and close. Built in Phase 2B above.
10. **The Scheduler's own holes and the committed dump.** These are outside this project, and KP's call.

Decided on 16 Oct and recorded in [03-decisions.md](03-decisions.md): the phone reset (yes, the same device rows), an HR Executive who manages people (approves their own team, as a manager), staying signed in (1 hour and 90 days), and desk logins (none allowed).

## Migrations, in run order

Every migration is listed here with its rollback script ([ADR-0021](adr/0021-migrations-new-tables-only.md)). Each creates only new `hr_ess_*` objects, is safe to run twice, and turns row-level security on with no policy, so only the service role (the ESS) reaches its rows. None alters a Scheduler table. KP applies each one by hand, in this order, in the Supabase SQL editor, and an agent checks it read-only afterwards ([05-deploy.md](05-deploy.md#migrations-to-apply)). **KP has applied 17 to 26; 13 to 16 (the Wall's) and 27 (G6's link table) are still to be applied.**

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
| 11 | [`20261107000000_hr_ess_push_devices.sql`](../db/migrations/20261107000000_hr_ess_push_devices.sql) | [`20261107000000_hr_ess_push_devices.sql`](../db/rollbacks/20261107000000_hr_ess_push_devices.sql): drops the table | `hr_ess_push_devices`: one row per FCM token, unique, with the phone's label and install id, the last time it was seen and its revocation; the employee's deletion cascades it | D5: the device endpoints answer 503; pushes stop |
| 12 | [`20261107000001_hr_ess_notifications.sql`](../db/migrations/20261107000001_hr_ess_notifications.sql) | [`20261107000001_hr_ess_notifications.sql`](../db/rollbacks/20261107000001_hr_ess_notifications.sql): drops the settings table, then the notifications table | `hr_ess_notifications` (category, title, body, `data` ids, read time, push bookkeeping with its both-ways CHECK; the unique key that makes one priority-task notification per person) and `hr_ess_notification_settings` (`disabled_categories`, checked against the three categories). Four indexes (person, unread, pending, the task key) | D6, D8: the notification and settings endpoints answer 503; the push job's own writes to it log and retry |
| 13 | [`20261108000001_hr_ess_wall_posts.sql`](../db/migrations/20261108000001_hr_ess_wall_posts.sql) | [`20261108000001_hr_ess_wall_posts.sql`](../db/rollbacks/20261108000001_hr_ess_wall_posts.sql): drops the wish book, the mentions, the reactions, the votes, the options, the comments and the posts | The feed: `hr_ess_wall_posts` (kind post/praise/wish/poll, scope org/branch, body, up to five attachments, mentions, the badge, the occasion, the poll's shape, the counters, `edited_at`, HR's hide with its reason, the author's `deleted_at`) with its shape CHECKs; `hr_ess_wall_comments` (one level of replies, its own reactions and hide); `hr_ess_wall_poll_options` and `hr_ess_wall_poll_votes`; `hr_ess_wall_reactions` (one per person per post or comment, two partial unique indexes); `hr_ess_wall_mentions`; `hr_ess_wall_wishes` (one per person per occasion per year). Eleven indexes | F1-F4, F6, F9: every Wall endpoint but `GET /api/ess/wall/settings` answers 503 |
| 14 | [`20261108000002_hr_ess_wall_reports.sql`](../db/migrations/20261108000002_hr_ess_wall_reports.sql) | [`20261108000002_hr_ess_wall_reports.sql`](../db/rollbacks/20261108000002_hr_ess_wall_reports.sql): drops the report queue and the opt-out table | `hr_ess_wall_reports` (post or comment, the reporter's own words, the status and HR's answer; one report per person per thing) and `hr_ess_celebration_optouts` (the birthday switch; no row means it is on). Five indexes | F6, F7: the report, queue, resolve, hide and celebration-opt-out endpoints answer 503 |
| 15 | [`20261108000003_hr_ess_announcements.sql`](../db/migrations/20261108000003_hr_ess_announcements.sql) | [`20261108000003_hr_ess_announcements.sql`](../db/rollbacks/20261108000003_hr_ess_announcements.sql): drops the read state, the audience and the announcements | `hr_ess_announcements` (title, body, up to five attachments, the audience object, `publish_at` and `published_at`, `needs_ack` with its closing date, `pinned`, the sender's counts, `reminded_at`) with its CHECKs; `hr_ess_announcement_audience` (one row per person, resolved at publication); `hr_ess_announcement_reads` (read and acknowledged times). Six indexes | F5: the announcement endpoints answer 503; the Wall's job logs and waits |
| 16 | [`20261108000004_hr_ess_notification_categories.sql`](../db/migrations/20261108000004_hr_ess_notification_categories.sql) | [`20261108000004_hr_ess_notification_categories.sql`](../db/rollbacks/20261108000004_hr_ess_notification_categories.sql): puts both CHECKs back to the three Phase 1 categories (and needs the Wall's notification rows deleted first; the rollback file says how) | Two CHECKs only, nothing else: `hr_ess_notifications.category` and `hr_ess_notification_settings.disabled_categories` take `mentions`, `replies`, `praise`, `announcements`, `acknowledgements` and `polls`, as migration 12's comment said Phase 2 would | F8: the Wall's notifications are logged as failed writes; the app's settings screen still shows the Phase 1 categories |
| 17 | [`20261109000001_hr_ess_helpdesk.sql`](../db/migrations/20261109000001_hr_ess_helpdesk.sql) | [`20261109000001_hr_ess_helpdesk.sql`](../db/rollbacks/20261109000001_hr_ess_helpdesk.sql): drops the messages, the tickets and the categories, then the ref sequence | The Helpdesk: `hr_ess_helpdesk_categories` (the six ticket categories and the four flow links, each with its queue roles, `confidential`, `allows_hold`, priority and SLA hours, seeded by `ON CONFLICT DO NOTHING` so a re-run changes nothing); `hr_ess_helpdesk_tickets` (`ref` `HD-0001` onwards from `hr_ess_helpdesk_ticket_ref_seq`, the raiser kept even on an anonymous ticket, the raiser's branch for the calendar, the two stored deadlines, the escalation level, and the state CHECK: a closed ticket knows when and why, a rating only stands on a closed one, an assignee has a claim stamp); `hr_ess_helpdesk_messages` (the thread: a comment has words, an `event` row has a name). Five indexes (the raiser's list, the job's two active walks, the category, the thread) | G1-G5: every Helpdesk endpoint, `GET /api/ess/helpdesk/categories` included, answers 503 `MODULE_NOT_INSTALLED` |
| 18 | [`20261109000002_hr_ess_notification_categories.sql`](../db/migrations/20261109000002_hr_ess_notification_categories.sql) | [`20261109000002_hr_ess_notification_categories.sql`](../db/rollbacks/20261109000002_hr_ess_notification_categories.sql): puts both CHECKs back to the nine categories before it (only while the tables are still there, as 16's rollback does) | Two CHECKs only, nothing else: `hr_ess_notifications.category` and `hr_ess_notification_settings.disabled_categories` take `helpdesk` as well, as migration 16 did for the Wall's six | G2, G3: the Helpdesk's notifications are logged as failed writes; a raise, a reply and an escalation reach nobody |
| 19 | [`20261110000001_hr_ess_documents.sql`](../db/migrations/20261110000001_hr_ess_documents.sql) | [`20261110000001_hr_ess_documents.sql`](../db/rollbacks/20261110000001_hr_ess_documents.sql): drops the documents, then the types | My Documents: `hr_ess_document_types` (the nine types fixed in code and seeded by `ON CONFLICT DO NOTHING`, the mandatory ones marked on the row) and `hr_ess_documents` (the file's name, the bucket path, the content type, 1 byte to 5 MB, the remark `others` requires, status pending/verified/rejected with its review CHECK: a verified one knows when, a rejected one says why). One index (the person's list, newest first) | E4: every document endpoint answers 503 `MODULE_NOT_INSTALLED` |
| 20 | [`20261110000002_hr_ess_change_requests.sql`](../db/migrations/20261110000002_hr_ess_change_requests.sql) | [`20261110000002_hr_ess_change_requests.sql`](../db/rollbacks/20261110000002_hr_ess_change_requests.sql): drops the table | `hr_ess_change_requests`: the field (`date_of_birth`, `address` or `legal_name`), what the record shows now and what it should, the reason, and the decision fields matching the status; a partial unique index (`hr_ess_change_requests_open_field_key`) holds one open request per field per person, so an answered one makes room for the next. Two indexes | E3: the change-request endpoints answer 503 |
| 21 | [`20261110000003_hr_ess_bank_details.sql`](../db/migrations/20261110000003_hr_ess_bank_details.sql) | [`20261110000003_hr_ess_bank_details.sql`](../db/rollbacks/20261110000003_hr_ess_bank_details.sql): drops the table | `hr_ess_bank_details`: one row per person (its primary key), the bank and branch, an account number of 8 to 18 digits, an IFSC of four letters, a zero and six more, and the consent the entry needs (`consent_given_at` NOT NULL, `consent_name`) | KP 3: the bank-details endpoints answer 503 |
| 22 | [`20261110000004_hr_ess_helpdesk_assignment.sql`](../db/migrations/20261110000004_hr_ess_helpdesk_assignment.sql) | [`20261110000004_hr_ess_helpdesk_assignment.sql`](../db/rollbacks/20261110000004_hr_ess_helpdesk_assignment.sql): drops the assignments table, then the three columns (only while the tickets table is still there, as 18's rollback does) | Additive only: three columns on `hr_ess_helpdesk_tickets` (`assigned_by_employee_id`, `assigned_by_name`, `assigned_at`) and the history `hr_ess_helpdesk_assignments` (one row per assignment, who it went to, who had it before, who pointed it there, and the reassignment's note). One index (the ticket's history, oldest first) | KP 5: the assign endpoint answers 503; a claim stays the only way to take a ticket |
| 23 | [`20261110000005_hr_ess_posh_queue.sql`](../db/migrations/20261110000005_hr_ess_posh_queue.sql) | [`20261110000005_hr_ess_posh_queue.sql`](../db/rollbacks/20261110000005_hr_ess_posh_queue.sql): moves the POSH row back to HR and puts the narrower CHECK back (only while the table is still there) | One non-additive touch on an `hr_ess_*` table: the queue-roles CHECK is widened to admit `internal_committee` and the seeded `posh` row's queue is moved to it. Nothing outside `hr_ess_helpdesk_categories` changes | KP 6: nothing waits on it; the POSH queue stays empty until RVM appoints the committee |
| 24 | [`20261110000006_hr_ess_notification_documents.sql`](../db/migrations/20261110000006_hr_ess_notification_documents.sql) | [`20261110000006_hr_ess_notification_documents.sql`](../db/rollbacks/20261110000006_hr_ess_notification_documents.sql): puts both CHECKs back to the ten categories before it (only while the tables are still there) | Two CHECKs only, nothing else: `hr_ess_notifications.category` and `hr_ess_notification_settings.disabled_categories` take `documents` as well, as migration 18 did for `helpdesk` | E4: the weekly missing-documents reminder is logged as a failed write; a person cannot turn it off |
| 25 | [`20261111000001_hr_ess_short_leave.sql`](../db/migrations/20261111000001_hr_ess_short_leave.sql) | [`20261111000001_hr_ess_short_leave.sql`](../db/rollbacks/20261111000001_hr_ess_short_leave.sql): puts the three-type CHECKs back, drops the minutes column, and re-creates the decide and cancel functions as migration 10 first wrote them (only while the table is still there) | The ESS's own request table, additively: the type CHECK admits `short_leave`; a `minutes` column (whole minutes 1 to 480) with the shape CHECK extended so only a short leave carries minutes; the decide and cancel functions re-created, the short-leave branch writing the day exactly as an excuse-late does | C3: a short-leave request is refused (503 `MODULE_NOT_INSTALLED`); the other types work |
| 26 | [`20261111000002_hr_ess_approval_escalations.sql`](../db/migrations/20261111000002_hr_ess_approval_escalations.sql) | [`20261111000002_hr_ess_approval_escalations.sql`](../db/rollbacks/20261111000002_hr_ess_approval_escalations.sql): drops the table | `hr_ess_approval_escalations`: one row per level told -- the family, the request (no foreign key, so the trail outlives it), who it came from and who it went to, the reason and the time; unique on (family, request, person), so a level is escalated once | D4: the chain view still works from the line; the escalation job logs and stops escalating |
| 27 | [`20261112000001_hr_ess_infra_links.sql`](../db/migrations/20261112000001_hr_ess_infra_links.sql) | [`20261112000001_hr_ess_infra_links.sql`](../db/rollbacks/20261112000001_hr_ess_infra_links.sql): drops the table | `hr_ess_infra_links`: one row per helpdesk ticket (unique) linking it to the Admin Manager's `infra_tickets` summary (unique when set), with `state` `linked` or `skipped`, the skip reason and the last sync time; a linked row must carry the register id and a skipped one must not; cascades with its ticket; an index on the register id | G6: the mirror is skipped and retried by the hourly job; tickets themselves are unaffected |

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
- **The Scheduler writes the ESS may make.** Each is one named store method, doing exactly what
  the Scheduler's own code does, never a delete and never another column:
  - HR's bulk phone reset (B8) updates `hr_attendance_devices` exactly as the Scheduler's own
    reset does (`attendanceAdminController.js:280-293`), only for rows still `active`, in slices
    of 150 ids, and never with an empty id list. The slices are separate requests with no
    transaction around them: if one fails, the phones already reset stay reset, are recorded in
    `hr_ess_audit` (or the server log) marked `incomplete`, and the reply is 503, so HR sends the
    same reset again for the rest.
  - The shift snapshot writes the three shift columns `ensureSnapshot` copies onto a day.
  - The employee's photo pointer writes only the photo columns the Scheduler's `setPhoto` writes.
  - Class marking (H1, decision 8) upserts `student_attendance` on its own
    `(batch_id, student_id, date)` key and updates that row's absent reason and follow-up; it
    resolves `pending_alerts` rows of type `absent_remarks_missing` with `is_resolved`,
    `resolved_at` and `resolved_by` only. `tests/store.test.js` allows exactly these five tables
    and asserts the number of write sites, so a later change cannot widen them quietly.
  If the Scheduler changes any of these paths, change the matching method to match.
- **Kept sign-ins after a rollback.** Rolling back `hr_ess_sessions` makes every access token the ESS minted answer 503 on the ESS (not 401), so the app does not sign out by itself; on the Scheduler those tokens last out their hour.
- **Production state unconfirmed.** Whether the attendance migrations (`20261020000000` to `20261023000000`) and the one-CL index are applied in production is not confirmed. Check, read-only, before Wave 3 relies on them.
- **Open holes.** The Scheduler's holes stay open while the app ships. Whether to release anyway is KP's decision.
- **The on-duty job runs inside the ESS process.** One instance only (`ecosystem.config.cjs`, fork mode), as for the rate limits; the SQL it calls is idempotent (a written day no longer matches), so a restart or a second manual run changes nothing. Its failures go to the pm2 log and to `hr_ess_audit` as `on_duty.failed`, best effort.
- **The limits are load-bearing for the request endpoints.** They read `hr_ess_request_limits` and answer 503 until migration 6 is applied; `GET /api/ess/me/capabilities`, the app's launch call, falls back to the code's defaults instead of failing.
- **Another agent session.** It works in the Scheduler repositories. team_app work never touches them, and reads only from detached read-only copies.
