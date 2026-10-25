# The backend, phase by phase

Every piece of backend work the Team RVM app still needs, in the order to build it, measured against the two input documents: the [app brief](inputs/team-rvm-app-brief-2026-10-15.pdf) and the [backend gap report](inputs/backend-gap-and-task-report-2026-10-16.pdf). The task IDs (A1 to K6) are the gap report's; [the table at the end](#every-gap-report-task-and-its-phase) maps all 105 of them.

The phases follow the brief's roadmap:
- Phase 0 is RVM's own set-up;
- Phase 1 is the attendance core that the one-branch pilot tests;
- Phase 2 is the community features;
- Phase 3 is the extras, which KP put outside this round ([ADR-0013](adr/0013-scope-phases-1-and-2.md)).

Phases 1 and 2 are split into parts small enough to build, review and ship one at a time.

**How each phase runs.** KP says "start phase …". It is built in team_app with tests for every endpoint (including the role-denied and wrong-owner cases), attacked by reviewers, fixed, and pushed to `main`, which deploys it. New tables come as migrations that KP applies by hand ([ADR-0021](adr/0021-migrations-new-tables-only.md)); until then their endpoints answer 503 `MODULE_NOT_INSTALLED`. Nothing in the Scheduler changes ([ADR-0018](adr/0018-team-app-changes-nothing-in-the-scheduler.md)).

**Where it stands (25 Oct 2026).** Phase 1A is live at `https://team-api.rvmcad.org`. **Phase 1B, 1C, 1D and 1E are live** (1E needed no migrations). **Phase 2A (the Wall), 2B (the Helpdesk) and 2C (documents, profile changes, bank details and the ID card) are built and deployed on 19 Oct.** **Phase 2D (leader and faculty views, approval chains, short leave) is built on 19 Oct**, and its last task, **H1 faculty class marking (decision 8), is built on 22 Oct**; its migrations 25-26 are applied and H1 needs no migration. **G6, the infra-register mirror (decision 9), is built on 22 Oct.** **Migrations 1 to 30 are applied** — 30 was applied by KP on 25 Oct 2026. The read-only check on 23 Oct 2026 (`.github/workflows/verify-migrations.yml`, run 39939895079) had found every table, column and seed through 29, including 28's Wall poll repair and 29's WFH allowance. The pilot gate is next.

| Phase | What it delivers | State |
| --- | --- | --- |
| [0](#phase-0-rvms-set-up) | RVM's own set-up: accounts, data, roles, policy | Runs alongside |
| [1A](#phase-1a-foundation) | Employee identity, capabilities, health, deploy | **Live, 16 Oct** |
| [1B](#phase-1b-staying-signed-in-one-field-sign-in-and-the-attendance-extras) | Staying signed in, one-field sign-in, attendance extras, personal details | **Live; migrations applied** |
| [1C](#phase-1c-requests-leave-and-approvals) | Requests, leave, balances, approvals, the limits, the on-duty job | **Built + deployed, 19 Oct** |
| [1D](#phase-1d-inbox-notifications-and-push) | Notifications, push, devices, priority tasks | **Built + deployed, 19 Oct** |
| [1E](#phase-1e-me-and-my-team) | Profile, reporting chain, directory, team today | **Built + deployed, 19 Oct; no migrations** |
| [2A](#phase-2a-wall) | The Wall | **Built + deployed; 13-16 applied** |
| [2B](#phase-2b-helpdesk) | The Helpdesk | **Built + deployed; 17-18 and 27 applied; G6 live** |
| [2C](#phase-2c-documents-profile-changes-and-the-id-card) | Documents, profile changes, ID card | **Built + deployed; 19-24 applied** |
| [2D](#phase-2d-leader-and-faculty-views-and-deeper-approvals) | Leader and faculty views, class marking, multi-level approvals, short leave | **Built + deployed, 19 Oct; H1 built 22 Oct; 25-26 applied** |
| [Pilot](#pilot-gate-one-branch-two-weeks) | One branch for two weeks, through Play closed testing | Next |
| [3](#phase-3-extras-not-in-this-round) | Extras | Not in this round |

The decisions each phase needs refer to [04-build-plan.md](04-build-plan.md#decisions-still-owed) by number. New questions for KP are written out in full.

## Phase 0: RVM's set-up

Not code. It runs alongside the build, and the pilot cannot start without it.

- **Accounts.**
  - A Google Play organisation account for RVM Beyond Pvt Ltd. It needs a D-U-N-S number, which takes weeks, and the pilot runs through Play closed testing, so start now.
  - A Firebase project. It turns push on (Phase 1D).
- **People and roles** (the brief's four things that must be true before launch):
  - every HOD and HoO on the right login role, and every HOD with a `hod_domains` row (task H8: I list the accounts, KP changes the roles);
  - every portal login linked to its HR record;
  - no shared desk logins (KP, 16 Oct: none are allowed).
- **HR data.**
  - The main phone and email checked for every employee.
  - Joining dates for the imported employees (the anniversary and new-joiner cards need them).
  - Date of birth, blood group, address and emergency contact, entered by HR once Phase 1B's personal-details table exists.
- **Policy.** An employee privacy and location policy as a web page, naming a grievance officer.
- **Logs.** Confirm that the server keeps the nginx and pm2 logs for `team-api.rvmcad.org` for at least 180 days (CERT-In). I check the rotation read-only; KP changes it if it is shorter.
- **Brand.** The master logo files, an "rvm TEAM" lockup and an app-icon mark; pages 9 and 10 of the guidelines fixed.

## Phase 1A: Foundation

**Live since 16 Oct 2026.**

- Employee identity: one check that accepts the Scheduler's portal token or attendance session and resolves the caller to their HR record (A1). It refuses a session still on HR's first-time password.
- `GET /api/ess/me` and `GET /api/ess/me/capabilities`: the tabs, sections and approver rights for the caller, read on every launch (A4).
- `GET /api/ess/health` with the minimum and latest app versions, so an update is never forced while someone is punching (K2).
- Per-employee and per-IP rate limits on every ESS endpoint (A6, K4).
- The ESS on its own host, `team-api.rvmcad.org`, with its own nginx file, certificate and 12 MB upload limit (K1, J7), deployed on every merge, with the `FIREBASE_*` checks (K3).
- The OpenAPI contract, including the Scheduler's sign-in and punch endpoints the app calls directly; CI; the read-only server check.

## Phase 1B: Staying signed in, one-field sign-in and the attendance extras

**Built and deployed; waiting for its migrations.** The brief's Phase 1. The rows marked *added after the current build* are the next small step.

| Work | Tasks |
| --- | --- |
| Staying signed in: a fresh sign-in is swapped for a rotating refresh token bound to the install; the ESS issues 1-hour tokens in the Scheduler's own formats, so the punch path accepts them; the sign-in lasts 90 days from its last use and ends on an attendance password change, when HR switches the login off, on exit, or on signing out | A3 |
| "Sign out everywhere" for the app's own sign-ins, and a portal password change ending them (*added after the current build*) | A3, A7 (app side) |
| One-field sign-in: phone, email, employee code or username finds the right login | A5 |
| Requests to correct or delete my data, with HR's list | A8 |
| The day read: `server_now`, the day's note and HR's remark | B1 |
| Mocked locations: refused on the phone, reported to HR | B14 |
| Tracking gaps (after a reboot, a killed app, a permission taken away): reported to HR as "tracking interrupted", never as absence (*added after the current build*) | B4 (app side) |
| The location disclosure: the app records that it was shown, with its version, before asking for location; the app shows it again when the version changes (*added after the current build*) | Brief: privacy |
| HR's bulk phone reset, branch by branch, writing the same device rows the Scheduler's own reset writes | B8 |
| Personal details: date of birth, blood group, address, emergency contact. HR enters every field (an HR endpoint, plus a CSV import KP runs); the employee changes only their blood group and emergency contact, because the brief makes date of birth and address sensitive (changes to those come as requests in 2C) | E9 |
| Desk logins: nothing more to build, because none are allowed and an unlinked login is already refused | A10 |

- **You first:**
  - confirm, read-only, that the attendance migrations `20261020000000` to `20261023000000` and the one-CL index are applied in production. B1 and B8 rely on them, and the pilot relies on B5 and B9 to B12;
  - decision 7 for HR's 1B tools (the data requests, the mocked-location and tracking-gap list, the bulk reset). Until it is made, they are HR sections in the app, shown through the capabilities.
- **You after:** apply the new migrations in the order given (sessions, data requests, personal details, mocked-location reports, audit, then the disclosures). I check them read-only.
- **Done when:**
  - the app stays signed in and refreshes, and "sign out everywhere" ends it on every phone within the hour;
  - one field signs anyone in;
  - the day shows its note and HR's remark;
  - a mocked punch and a tracking gap reach HR's list;
  - HR can reset a branch's phones and enter personal details;
  - the disclosure is recorded before the first location request.

## Phase 1C: Requests, leave and approvals

The brief's Phase 1, and its core. **Built 19 Oct 2026; waiting for migrations 6 to 10. WFH added 22 Oct needs migration 29.**

| Work | Tasks |
| --- | --- |
| Request tables with their history; the work mode kept in ESS tables | C1 |
| On duty, fix a day, excuse a late (WFH for selected employees, against HR's own allowance, from 22 Oct). A half day from the 3rd-late rule is cleared by excusing one of its lates; one from the 4-hour rule by fixing the day's times | C3 |
| CL and leave without pay | C2, C4 |
| Balances: allowed, used, remaining, pending included, shown on every form; a request over the limit refused in plain words | C5 |
| The limits KP set (on duty unlimited, fix a day 3, excuse a late 3, CL 1), in a table HR can change | C6 |
| One decision function per request type (`hr_ess_decide_<type>`, a team_app migration). In one transaction it locks the request, re-checks its status, the future-day rule, the one-CL rule and the cut-off, calls `hr_attendance_apply_override` (or excuses the late), and writes the request's status and history. The month is recomputed after. A second decision on the same request answers 409. The override locks the day against the Admin Manager's sheet | C7, C9 |
| The on-duty morning job: an on-duty day approved in advance is written on the morning of that day as present, with the place as its note, because the override would otherwise lock a future day (ADR-0020). It can be re-run safely, and failures are logged for HR | C3, C7 |
| Withdraw while pending; after approval only HR cancels, by restoring the logged day | C8 |
| Approver: the manager on the HR record, HR as fallback; HR, the CEO and super admins can decide any request, recorded as HR's; an HR Executive approves their own team | C10 |
| This month and last; closed at the cut-off on the 5th | C12 |
| The approvals Inbox: counts, context (how many of this kind this month, the late count, who else is off that day), decide with a comment, a reason required to reject, archive; HR's approval endpoints | D1, H6 |

**Built, in one place:** `apps/ess-api/src/routes/attendanceRequests.js`, `leaveRequests.js`,
`approvals.js`, `hrRequests.js`, the policy in `src/policy/requests.js` and `attendance.js`, and
`src/jobs/onDuty.js`; migrations 6 to 10. The seven SQL functions are the decision itself; the
routes validate the form, resolve the approver and re-count the month, in the Scheduler
controller's own order. **The two defaults the build had to choose** (both in
[04-build-plan.md](04-build-plan.md#phase-1c-requests-leave-and-approvals--built-19-oct-2026)):
the 5th itself is open for raising and deciding (decision 6), and leave is whole days in this
phase.

**Work from home (custom, KP 22 Oct 2026; built, migration 29).** WFH is offered only to the
employees HR selects. `hr_ess_wfh_allowances` holds one row per employee (`is_enabled`,
`monthly_limit_days` 1 to 31, HR's note); the allowance is the limit, never a generic
`hr_ess_request_limits` row. `wfh` is a leave type: the same requests table, Inbox, chain, decide,
withdraw and cancel. `PUT /api/ess/hr/wfh-allowances/{employeeId}` enables or disables it (HR, CEO
and super admins; audited as `wfh.allowance.changed` with the numbers only), `GET
/api/ess/hr/wfh-allowances?q=` lists who has it, and `GET /api/ess/me/wfh` answers the employee's
month. `POST /api/ess/leave-requests { type: 'wfh' }` is refused 409 `WFH_NOT_ALLOWED` without an
enabled row and 409 `WFH_LIMIT` when the month's approved and pending days fill it; the decide
function re-checks both under a lock and writes the day PRESENT with `Work from home: <reason>`,
keeping the times already recorded, through `hr_attendance_apply_override`. No punch is needed.
Full flow, caveat and Scheduler handover: [10-wfh-flow.md](10-wfh-flow.md).

- **You first:**
  - decision 2: does app leave replace the Admin Manager's faculty leave or run alongside it, and does a faculty member's approved app leave also update the faculty leave dates used for batch cover (that writes a Scheduler table)?
  - decision 6: the build's default is the 5th itself open (see above); change it now if payroll needs the 5th closed.
  - a limit for leave without pay (none is set; HR can set one through `PUT /api/ess/hr/request-limits/leave_lwp`);
  - the one-CL index confirmed in production (from 1B).
- **You after:** apply migrations 6 to 10, in the order in [05-deploy.md](05-deploy.md#migrations-to-apply). Until then every request endpoint answers 503 `MODULE_NOT_INSTALLED`.
- **Done when:**
  - an employee raises each request type, sees the counter, and withdraws one;
  - the approver decides from the Inbox;
  - the approved day appears in the Scheduler as an override, locked, with the month recomputed;
  - an on-duty day approved in advance shows as present on the day without a punch;
  - the limits and the cut-off hold, and two people deciding at once cannot both win.

## Phase 1D: Inbox, notifications and push

The brief's Phase 1. **Built 19 Oct 2026; waiting for migrations 11 and 12.**

| Work | Tasks |
| --- | --- |
| Phone registration for push | D5 |
| Notifications list and unread count | D6 |
| The push worker (log-only until the Firebase project exists) | D7 |
| Categories each person can turn off; nothing pushed at night | D8 |
| Push for approvals, decisions and priority tasks. Priority tasks exist in the Scheduler for portal logins of every role but the CEO; attendance-only staff have none (a Scheduler limit), so the capabilities hide that section from them | D1, D2 |
| Optional: interview reminders 24 hours before a round | Brief extra |

**Built, in one place:** `src/routes/pushDevices.js`, `src/routes/notifications.js`,
`src/lib/notify.js`, `src/lib/fcm.js`, `src/jobs/push.js` and `src/policy/notifications.js`;
migrations 11 and 12. What the build chose, for KP to confirm:
- quiet hours fixed at 21:00–08:00 IST (the app shows them; per-person hours are later);
- 3 push attempts, a minute apart, then the row is `skipped`;
- priority-task push for direct assignments only — the Scheduler's broadcast tasks need its own
  role rules, which stay as they are (the D2 gap);
- the three Phase 1 categories only; the Wall's categories extend the CHECK in Phase 2;
- interview reminders are not built (optional, and the Scheduler ties that calendar to portal
  logins).

- **You first:** the Firebase project and the three `FIREBASE_*` secrets (Phase 0). Without them everything works, but push is written to the log instead of being sent.
- **You after:** apply migrations 11 and 12, in order.
- **Done when:**
  - a decision or a priority task reaches the phone;
  - the Inbox shows it with its unread count;
  - a category turned off stays quiet.

## Phase 1E: Me and My Team

The brief's Phase 1. ## Phase 1E: Me and My Team

**Built and deployed 19 Oct 2026; no migrations needed.**

- **Profile:** Summary and Job from the HR record, Personal from 1B, the Timeline from HR events (an allowlist: joining, promotion, status, reporting line, designation and branch changes, increments as dates; HR remarks and event values are never read). Each Timeline item carries a stable machine `kind` alongside its unchanged `title` and date. Never pay, performance tags or background notes.
- **Photo:** short-lived signed links; the employee's own change goes through the ESS into the private bucket, audited. Old files are left for cleanup. **KP to confirm:** no HR approval is needed (the build's default).
- **Org and directory:** the chain up to the CEO with "Reports to the CEO (not recorded)", peers, direct reports, the department, and colleague search by name or code. Email to everyone; phone to HR's roles and the manager chain only (decision 5's default: a report does not see a manager's phone).
- **Team:** Team today for anyone with reports, the whole branch for a HoO (H4); Off this week on Home (reports, else peers). Names and days only, never the leave type or reason.
- **Not built:** the HOD's domain roster — the domain→faculty mapping lives in the HOD module; it goes with 2D's faculty views.

| Work | Tasks |
| --- | --- |
| Profile: Summary and Job; Personal (from 1B); Timeline from HR events. The designation comes from the HR record, never the login role. Never pay, HR remarks, performance tags or background notes | E1, E12 |
| The reporting chain up to the CEO ("Reports to the CEO (not recorded)" where nobody is), peers, direct reports, department, colleague search by name or code, filtered by branch or department | E2 |
| People on notice stay on the chain with a "Notice period" chip | E11 |
| Team today (all, not in yet, late, on leave) for anyone with reports; the HoO's view for the branch; an HOD's view for their domain roster | E6, H4 |
| Off this week on Home for everyone: their reports, or else the peers under the same manager, showing who is off but never the leave type or reason | E6 |
| The contact rule: email to everyone, phone to the manager chain and HR | E8 |
| Photos: the HR record's photo, through short-lived signed links. An employee's own photo change goes through the ESS, because attendance-only staff cannot reach the Scheduler's photo upload | E10 |

- **You first:**
  - decision 5: does an employee also see their own managers' phone numbers?
  - does an employee's own photo change need HR's approval?
- **Done when:** all 107 employees, the 41 attendance-only staff included, see their profile and their team.

## Pilot gate: one branch, two weeks

The brief's gate between Phase 1 and Phase 2. **Backend deliverables written 22 Oct 2026:**
[08-flutter-handover.md](08-flutter-handover.md) (hosts, sign-in, endpoints by screen, errors,
uploads) and [09-data-inventory.md](09-data-inventory.md) (the Play Data safety answers).

- **Backend:**
  - the Flutter handover note (base URLs, the sign-in flow, endpoints per screen, error codes) —
    **written**;
  - the contract complete for Phase 1 - **0.13.0**;
  - every Phase 1 migration applied — **yes**;
  - the pilot branch's phones reset — **RVM to do** with `POST /hr/devices/reset`;
  - a data inventory for Play's Data safety form — **written**;
  - a sign-in plan for the shared office IP — **written** in the handover (sign in on mobile data or
    in small groups; the app shows a 429 as "try again in a few minutes").
- **RVM:**
  - Phase 0's people, roles and policy done;
  - the request limits and the cut-off agreed;
  - the Play organisation account with a closed-testing track for the pilot branch, the Data safety form, the location declaration for the 2-minute pings, and the privacy policy URL plus a public link for data and deletion requests (A8) in the listing.
- **Passes when** every punch at that branch is saved for two weeks and HR's sheet matches the app. Only then do the other branches move, and HR resets their phones.

## Phase 2A: Wall

The brief's Phase 2.

| Work | Tasks |
| --- | --- |
| Posts on the organisation wall and one wall per branch: text, up to 5 photos or PDFs, @mentions, edit for 15 minutes (shown as edited), delete your own | F1 |
| Six reactions; comments with one level of replies; reactions on comments; who reacted | F2 |
| Praise with RVM's own badges (8 to 12, HR edits them), a reason of up to 280 characters, an optional photo and certificate PDF, shown on the receiver's profile | F3 |
| Polls, anonymous ones included; options fixed after the first vote | F4 |
| Staff announcements by branch, department, role or people, published now or scheduled, with a closing date, acknowledgement, read and acknowledgement counts for the sender, reminders to those who have not acknowledged, up to 3 pinned; sent by push and by email. New tables; the students' notices stay as they are | F5 |
| Birthdays (day and month only, hidden for anyone who opts out), anniversaries, recent promotions from the HR event trail, new joiners for 15 days, one-tap wishes (birthday, anniversary and promotion) | F6 |
| Reporting, moderation with a reason, and its log; who may post what | F7, F8 |
| Photos under 1 MB, stored in an ESS storage bucket | F9 |
| An ESS scheduler for scheduled announcements, acknowledgement reminders and polls closing | F4, F5 |

**Built 19 Oct 2026, in one place:** `src/routes/wallPosts.js`, `wallComments.js`,
`wallReactions.js`, `wallPraise.js`, `wallPolls.js`, `wallAnnouncements.js`,
`wallCelebrations.js`, `wallModeration.js`, `wallViews.js` and `wallSettings.js`, the rules in
`src/policy/wall.js`, the notification writers in `src/lib/wallNotify.js` and
`src/lib/wallAudience.js`, and the clock in `src/jobs/wall.js`; migrations 13 to 16. What the
build chose, for KP to confirm:
- **a post's default wall is the author's own branch** (`scope: 'org'` is explicit), and a branch
  post must be their own branch;
- **a praise cannot be given to yourself**;
- **praise on the receiver's profile** is `GET /api/ess/me/praise`, its own read, so the profile's
  shape is unchanged;
- **a birthday is day and month only** in every reply and hidden for anybody who opted out (the
  opt-out is its own table, `hr_ess_celebration_optouts`);
- **the twelve badges are fixed in code** (KP, 19 Oct), and a certificate PDF is Phase 3;
- **only HR moderates** (decision 8): only HR hides anything, reads the report queue and the
  moderation trail; an announcement's sender reads that announcement's own counts;
- **a hidden comment keeps its place in the thread with no words** for everybody but HR and its
  author;
- **the Wall's job** (`src/jobs/wall.js`, one process) publishes scheduled announcements, reminds
  those who have not acknowledged inside two days of the close, and tells a closed poll's voters;
- **announcement email and push are log-only** until RVM has a mail provider and the Firebase
  project.

The Wall's endpoints answer 503 `MODULE_NOT_INSTALLED` until migrations 13 to 15 are applied
(`GET /api/ess/wall/settings` is the code's own rules and needs no table); until migration 16 the
Wall's notifications are logged as failed writes, as push already is.

- **You first:**
  - the badge list (the build ships twelve; KP to change or add any);
  - an OK for a private storage bucket for the ESS's files in the same Supabase project (the build
    uses `ESS`, created by KP on 19 Oct);
  - the mail provider and sender address for staff announcements, as team_app secrets (the deploy
    would write and length-check them, as it does `FIREBASE_*`);
  - date of birth and joining date loaded for every employee.
- **Done when:** posts, praise, polls and announcements work end to end, with notifications from Phase 1D.

## Phase 2B: Helpdesk

The brief's Phase 2.

| Work | Tasks |
| --- | --- |
| Categories HR edits, each with its team, priority and response times | G1 |
| Tickets HD-0001 onwards: the category sets the priority and the assignee; thread, lifecycle, reopen within 7 days, rating, withdraw; nothing deleted | G2 |
| Response times in each branch's working hours; "Overdue by 3h"; escalation to the category head, the HoO, then the CEO | G3 |
| Confidential categories (grievances, POSH) and optional anonymity; every read logged | G4 |
| The agents' workspace on the phone; on the web where decision 7 says | G5 |
| Lab and facility tickets also added to the Admin Manager's infra register, if decision 9 says yes | G6 |
| Leave, attendance fixes and asset requests are not tickets: the category list links to those flows | Brief |

**Built 19 Oct 2026, in one place:** `src/routes/helpdeskCategories.js`, `helpdeskTickets.js`
and `helpdeskQueue.js`, the rules in `src/policy/helpdesk.js`, the shared views in
`src/lib/helpdeskKit.js`, the notification writers in `src/lib/helpdeskNotify.js` and the clock
in `src/jobs/helpdesk.js`; migrations 17 and 18. What the build chose, for KP to confirm:
- **the lab has no desk role and the Internal Committee has no login**, so IT and lab tickets
  route to the admin roles and POSH tickets to HR; the category list is fixed in code and seeded
  by the migration (G1's "HR edits them" is not built);
- **queue membership is exact** — a role no category names (the CEO's, most staff's) sees an
  empty queue, and a confidential category is seen only by the team it is routed to;
- **assign and reassign came with Phase 2C** (KP, 19 Oct 2026): `POST /api/ess/helpdesk/tickets/{id}/assign`
  hands a live ticket to a named handler, and can hand it on again; the assignee must hold the
  category's own queue role, the move is recorded in `hr_ess_helpdesk_assignments` and the ticket
  says who pointed it there (migration 22);
- **the infra-register mirror (G6, decision 9) is built on 22 Oct 2026**: an `it_lab` ticket adds
  audit type A and a `facility` ticket type D to the Admin Manager's `infra_tickets`, one summary
  row linked through `hr_ess_infra_links` (migration 27); anonymous tickets carry no identity;
  closing syncs both ways (the ESS closes the register row, and the hourly job resolves the ticket
  when the register row is closed);
- **the SLA targets are the build's defaults** and the working-hours calendar is a policy
  constant (09:00–17:30 IST, Monday to Saturday) plus the Scheduler's `hr_holidays`.

The Helpdesk's endpoints answer 503 `MODULE_NOT_INSTALLED` until migration 17 is applied; until
18 is applied its notifications are logged as failed writes, as push already is.

- **You first:**
  - decisions 7 (where HR and the agents work on the web: in the app, or a small web page served by team_app) and 9 (the infra register writes a Scheduler table);
  - an OK for the fixed category table and its SLA hours, as seeded by migration 17;
  - the escalation job running once (`src/jobs/helpdesk.js`, hourly at present).

- **Done when:** a raise reaches the right team's queue, is answered, moved and closed end to
  end; a past-due ticket escalates to the HoO and then the CEO; a confidential ticket is seen by
  nobody it should not be, with the audit trail to show for it.

## Phase 2C: Documents, profile changes and the ID card

The brief's Phase 2.

| Work | Tasks |
| --- | --- |
| Changes to date of birth, address and legal name as requests: HR sees the old and new values; the main phone and email stay HR's | E3 |
| Documents in new tables: HR-defined types (mandatory or not, "not applicable" allowed, verification needed or not); employee uploads from the camera or as a PDF into the ESS bucket, each pending, verified, or rejected with a reason; HR's existing documents shown read-only as verified, through 5-minute links, the storage path never returned. `hr_documents` is never altered | E4 |
| A weekly reminder to anyone still missing a mandatory document | E4 |
| Identity documents: no Aadhaar number is stored; the file is opened by the HR role only, every view is logged, HR deletes it when the purpose ends; no e-KYC | E4 |
| HR's review queues, where decision 7 says | E5 |
| The digital ID card from the HR record and the personal details. Its QR code, if wanted, holds a signed, expiring link that shows only the name, photo, designation, branch and "active employee" | E7 |

The letters folder belongs to Phase 3 ([ADR-0013](adr/0013-scope-phases-1-and-2.md)).

**Built 19 Oct 2026, in one place:** `src/routes/documents.js`, `changeRequests.js`,
`bankDetails.js` and `idCard.js`, the rules in `src/policy/documents.js`, the shared helpers in
`src/lib/documentsKit.js` and `src/lib/idCardKit.js`, the reminder in `src/jobs/documents.js`, and
the assign delta in `src/routes/helpdeskTickets.js`; migrations 19 to 24. What the build chose,
for KP to confirm:
- **the document types are fixed in code** (`src/policy/documents.js`, seeded by migration 19):
  resume, identity, certificate, offer, joining, experience, exit and other, plus an ESS-only
  `others` that must carry a free-text remark saying what the file is. Identity, offer and
  joining are the mandatory ones the weekly job asks for; no Aadhaar number is stored.
- **identity documents are gated** (KP 2): only HR (the `hr` role), the CEO and super admins may
  open one - an HR Executive is 403 `DOCUMENT_IDENTITY_ROLE` - and every opening is audited with
  the record kept before it. The role set lives in one place (`IDENTITY_ROLES`), and identity
  rows are dropped from HR's list responses for a reader who cannot open them.
- **bank details are collected with consent** (KP 3): the person types their own name and the
  save stamps `consent_given_at`. The account number is masked to everybody but its owner (the
  last four only), never appears in a list response, and every HR read is audited, even a read
  that finds nothing.
- **an approval of a profile change records the decision only** and never writes `hr_employees`
  (ADR-0003): HR applies the change in the Scheduler by hand; the request row is the paper
  trail, and the database holds one open request per field per person.
- **the weekly reminder names the types the person personally lacks** (`src/jobs/documents.js`,
  the `documents` notification category), so one held document does not hide the rest.
- **the ID card's QR holds a signed, expiring link** (90 days): `GET /api/ess/id-card/verify/{token}`
  is unauthenticated, rate-limited per address, and answers 401 `ID_CARD_BAD_TOKEN` for a bad or
  expired link or a card whose holder has left.
- **POSH routes to the Internal Committee** (`internal_committee`, migration 23): the queue stays
  empty until RVM appoints the committee and its logins carry that role.

- **You first:** the three questions the phase asked (the document types, who opens identity
  documents, whether bank details are collected) were answered by KP on 19 Oct
  ([03-decisions.md](03-decisions.md)).
- **You after:** apply migrations 19 to 24, in order ([05-deploy.md](05-deploy.md#migrations-to-apply)).
  Until 19 to 21 are applied the document, change-request and bank-details endpoints answer 503
  `MODULE_NOT_INSTALLED`; until 22 the assign endpoint does; until 24 the reminders are logged
  as failed writes.
- **Done when:** a person uploads each mandatory document, HR verifies or turns it away with a
  reason, and the weekly reminder reaches only those still missing one; a change request reaches
  HR's queue and its answer is recorded; a bank row carries its consent and shows only its last
  four digits to anybody but its owner; a card's QR link proves an employee without a sign-in.

## Phase 2D: Leader and faculty views and deeper approvals

The brief's Phase 2.

**Built and deployed 19 Oct 2026; H1 class marking built 22 Oct; migrations 25-26 applied.**

- **The leaders' overview (H5):** `GET /api/ess/leaders/overview` for the CEO and super admins — headcount, today's attendance states, who is off this week, and the approval queue with the oldest request's age. Counts only: no names, pay or performance ever leave the database.
- **The faculty "my day" (H7):** `GET /api/ess/me/faculty-day?date=` — today's sessions owned or covered through `faculty_substitutions` (other centres included), each with its times, centre, students and whether it is marked; the remarks still due (`pending_alerts` of type `absent_remarks_missing`); and the indicators card (today's and the month's marked-session percentages, joined/active students, sessions without attendance). Counts only, never a student's name, phone or remarks.
- **Faculty class marking (H1, decision 8, built 22 Oct):** `GET /api/ess/me/batches/{id}/roster?date=`, `POST /api/ess/me/batches/{id}/attendance` and `PATCH /api/ess/me/batches/{id}/attendance/{date}/remarks`. The Scheduler's six checks are enforced server-side: the role (`faculty`/`hod`, or the Scheduler's admin roles), the branch (mapped by branch name), ownership or a covering substitution, the day (batch start to today IST), roster membership and eligibility (`joined_at`, `admissions.joined` unless no admissions row, not on hold), and the lock a teaching role hits after the first save — admin roles may correct a day. A save upserts `student_attendance` on its own key, resolves the `absent_remarks_missing` alert when a student is present or the reason is given with the save, and the remark route resolves it when a reason is filled later; the audits are `class.attendance.marked` (counts only) and `class.remark.changed` (before/after reason). The roster returns a name, an admission number and the mark only. The two Scheduler writes are the sanctioned ones from decision 8; **no migration**.
- **Approval chains (D4):** `GET /api/ess/approvals/{family}/{id}/chain` shows the reporting line a request waits on, each level's skip reason (`same_person`, `not_active`, `on_leave`) and the first level that may decide; `POST .../archive` clears a request from one approver's Inbox without deciding it. An hourly job (`src/jobs/approvals.js`) escalates a request still pending after **two IST days** to the next unskipped level, one level a run, recorded once per person in `hr_ess_approval_escalations` and notified in the `approvals` category; HR is the fallback when the line is exhausted. **KP to confirm the two-day default** — it is the build's constant, not a database setting.
- **Short leave (C3):** an attendance request type of its own, counted in **minutes** (1 to 480, the day's cap), with a monthly limit of 180 minutes shown beside the other balances; approved through the same decision function. The Scheduler's own `hr_attendance_recompute` does not know the type, so the app works around it exactly as the docs say: the approval excuses the late it covers.
- **Not built:** the approval-chain rules per request type, which need KP's rule first.

| Work | Tasks |
| --- | --- |
| Light KPI cards for the CEO and super admins | H5 |
| The faculty "my day" read and the indicators card | H7 |
| Faculty class marking with the Scheduler's six checks | H1 (decision 8) |
| Multi-level approval chains with auto-skip and escalation | D4 |
| Short leave, by excusing the late it covers | C3 (Phase 2 type) |

- **You first:** decision 3 (do planned early-leaving minutes protect a day from the 4-hour half-day rule?). Decision 8 is answered: H1 is built.

## Phase 3: Extras (not in this round)

KP put these outside this round ([ADR-0013](adr/0013-scope-phases-1-and-2.md)); they are listed so nothing is lost.

- **Device trust, redesigned inside team_app.** The app sends a Play Integrity token and its Keystore public key to the ESS. The ESS refuses to issue or renew app sign-ins (A3) without a valid verdict (`MEETS_DEVICE_INTEGRITY`), and reports each verdict to HR, as it does mocked locations. Checking integrity inside the punch itself, or replacing the punch cookie with the Keystore key, would change the Scheduler and stays out of scope (K6, J9).
- Letters (the E4 letters folder) and company policies with acknowledgement.
- Assets in my custody, read from the Scheduler's asset data, with an acknowledgement. Raising an asset request: portal logins use the Scheduler's existing flow; for attendance-only staff it would write a Scheduler table, which needs a decision.
- Languages: the employee's language stored by the ESS; push, email and the ESS's messages sent in it (English, then Hindi, then Marathi and Gujarati).
- Pulse check-ins and surveys; optional holidays; a leave ledger.
- Later: approving from WhatsApp; several geofences per person (a Scheduler rule, so out of scope as it stands).

## Out of scope: each needs a Scheduler change

These stay as they are unless KP decides to change the Scheduler separately ([ADR-0018](adr/0018-team-app-changes-nothing-in-the-scheduler.md)). The app works around the ones it can.

- **Security fixes:** J1 to J6 (class marking checks, the roster's password hashes, batch and announcement writes, the phone-only reset, interviewer roles), `/api/dashboard`, the committed database dump, portal access after exit, student tokens' reach. Also `GET /api/users` and `GET /api/faculty` showing contacts to any signed-in token, so the contact rule (E8) holds only inside the app. See [02-reconciliation.md](02-reconciliation.md).
- **Sessions and limits:** portal "sign out everywhere" on the Scheduler itself (A7; the app's own sign-ins get it in 1B); the Scheduler's per-IP limits, shared by a whole office.
- **Punch path:**
  - batch pings (B15) and a device-id header (part of B8);
  - integrity or Keystore checks inside the punch, ping and challenge;
  - the Admin Manager's daily-sheet lock (B17; the app's approvals are locked by the override function).
- **Attendance-only staff:** priority tasks and the interview calendar, both tied to portal logins.
- **Bugs:**
  - approved faculty leave marked absent by the midnight job (C11);
  - the web org chart dropping people on notice (E11, web side);
  - the Admin Manager's branch-wide read (B16);
  - the remarks endpoint accepting a first-time-password session (B5; the app sends the person to choose a password first);
  - the short-leave rule inside `hr_attendance_recompute` (2D works around it by excusing the late).
- **Not built at all:** the ping purge and log retention job (K5): KP deletes old pings by hand ([ADR-0015](adr/0015-no-automated-retention.md)), never attendance records (kept 5 years) or logs younger than 180 days.

## Every gap-report task and its phase

"At c28b9ca" is what [02-reconciliation.md](02-reconciliation.md) found in the Scheduler's code on 15 Oct. The attendance migrations and the one-CL index were confirmed in production on 23 Oct (see [11-migration-status-2026-10-23.md](11-migration-status-2026-10-23.md)), so B5 and B9 to B12 are live, not provisional.

| Task | At c28b9ca | Phase | How |
| --- | --- | --- | --- |
| A1 | Update | 1A Foundation | employeeAuth: both Scheduler tokens resolved to hr_employees.id. Live |
| A2 | Available | Exists already | The Scheduler's attendance sign-in, unchanged (ADR-0004) |
| A3 | Missing | 1B Signed in and attendance extras | Refresh sessions: 1-hour tokens in the Scheduler's formats, 90-day sign-in |
| A4 | Missing | 1A Foundation | GET /api/ess/me/capabilities. Live |
| A5 | Missing | 1B Signed in and attendance extras | POST /api/ess/sign-in/resolve: one field finds the right login |
| A6 | Update | 1A Foundation | Per-employee and per-IP limits on every ESS endpoint. The Scheduler's own limiter is out of scope |
| A7 | Missing | Out of scope (Scheduler change) | On the Scheduler itself it needs a change; the app sign-ins get "sign out everywhere" in 1B |
| A8 | Missing | 1B Signed in and attendance extras | Requests to correct or delete my data, with HR's list |
| A9 | Update | Out of scope (Scheduler change) | Retiring the phone-only reset is a Scheduler change; the app never calls it |
| A10 | Missing | 1B Signed in and attendance extras | Nothing more to build: no desk logins are allowed (KP), and an unlinked login is refused |
| K1 | Missing | 1A Foundation | A 12 MB limit in the ESS's own nginx file. Live |
| K2 | Missing | 1A Foundation | GET /api/ess/health with the minimum and latest app versions. Live |
| K3 | Missing | 1A Foundation | FIREBASE_* written and length-checked by the deploy. Live |
| K4 | Update | 1A Foundation | Same as A6 |
| K6 | Missing | 3 Extras and device trust | Redesigned in team_app: integrity and a Keystore key gate the app sign-in (A3), not the punch. The Play listing part is at the pilot gate |
| B1 | Update | 1B Signed in and attendance extras | An ESS day read: server_now, the day's note and HR's remark |
| B2 | Verified | Exists already | Scheduler: the challenge |
| B3 | Verified | Exists already | Scheduler: the punch |
| B4 | Verified | Exists already | Scheduler: the ping |
| B5 | Verified | Exists already | Scheduler: day remarks (accepts a first-time-password session: out of scope) |
| B6 | Available | Exists already | Scheduler: geofence and exemption |
| B7 | Available | Exists already | Scheduler: the accuracy rule |
| B8 | Update | 1B Signed in and attendance extras | HR bulk phone reset writing the Scheduler's own device rows (KP: yes). The device-id header is out of scope |
| B9 | Available | Exists already | Scheduler: shifts, week-offs, holidays |
| B10 | Available | Exists already | Scheduler: the late and half-day engine |
| B11 | Available | Exists already | Scheduler: one session a day |
| B12 | Available | Exists already | Scheduler: the holiday list |
| B13 | Available | App only | The app sends a phone User-Agent |
| B14 | Missing | 1B Signed in and attendance extras | Refused on the phone, reported to HR in an ESS table |
| B15 | Missing | Out of scope (Scheduler change) | Batch pings need a Scheduler change; the purge part is K5 |
| B16 | Verified | Exists already | Scheduler: the leader board and controls |
| B17 | Update | Out of scope (Scheduler change) | The daily-sheet lock is Scheduler code; ESS approvals are locked by the override function (1C) |
| K5 | Missing | Not built (ADR-0015) | No purge job: KP deletes old pings by hand; the 180-day log floor is checked in Phase 0 |
| I | Update | 1B Signed in and attendance extras | New hr_ess_* tables, phase by phase, from 1B on (ADR-0021) |
| C1 | Missing | 1C Requests, leave and approvals | Request tables with history; the work mode lives in ESS tables |
| C2 | Update | 1C Requests, leave and approvals | CL and leave without pay through the ESS |
| C3 | Missing | 1C Requests, leave and approvals | On duty, fix a day, excuse a late (WFH for selected employees from 22 Oct, against HR's per-employee allowance; short leave in 2D) |
| C4 | Missing | 1C Requests, leave and approvals | Leave requests |
| C5 | Missing | 1C Requests, leave and approvals | Balances: allowed, used, remaining, pending included |
| C6 | Update | 1C Requests, leave and approvals | The limits table KP set, which HR can change |
| C7 | Missing | 1C Requests, leave and approvals | The day written through hr_attendance_apply_override, with the ESS's own checks (ADR-0020) |
| C8 | Missing | 1C Requests, leave and approvals | Withdraw while pending; HR cancels an approved one |
| C9 | Update | 1C Requests, leave and approvals | Comes with the override function, which locks the day |
| C10 | Missing | 1C Requests, leave and approvals | Manager on the HR record, HR fallback; HR Executive approves their own team |
| C11 | Update | Out of scope (Scheduler change) | The faculty-leave bug is Scheduler code; leave approved in the app writes the staff day itself |
| C12 | Missing | 1C Requests, leave and approvals | This month and last; cut-off on the 5th |
| D1 | Missing | 1C Requests, leave and approvals | The approvals Inbox: counts, decide with a comment, archive |
| D2 | Available | Exists already | Scheduler: for portal logins of every role but the CEO; attendance-only staff get none (out of scope); push in 1D |
| D3 | Available | Exists already | Scheduler: priority task remarks |
| D4 | Missing | 2D Leader views and deeper approvals | Multi-level approval chains, auto-skip, escalation |
| D5 | Missing | 1D Inbox, notifications and push | Phone registration for push |
| D6 | Missing | 1D Inbox, notifications and push | Notifications list and unread count |
| D7 | Missing | 1D Inbox, notifications and push | The push worker: log-only until the Firebase project exists |
| D8 | Missing | 1D Inbox, notifications and push | Categories with opt-outs; nothing pushed at night |
| E1 | Missing | 1E Me and My Team | Profile: Summary, Job, Personal (from 1B), never pay or HR remarks |
| E2 | Missing | 1E Me and My Team | Reporting chain to the CEO, peers, reports, department, directory search |
| E3 | Missing | 2C Documents, changes and ID card | Sensitive changes as requests: HR sees old and new values |
| E4 | Update | 2C Documents, changes and ID card | New ESS document tables; hr_documents read only; no Aadhaar number stored; letters folder in Phase 3 |
| E5 | Missing | 2C Documents, changes and ID card | HR's review queues, where decision 7 says |
| E6 | Missing | 1E Me and My Team | Team today and Off this week, for anyone with reports |
| E7 | Missing | 2C Documents, changes and ID card | Digital ID card |
| E8 | Missing | 1E Me and My Team | Contact rule: email to all, phone to the manager chain and HR (decision 5 on own managers) |
| E9 | Missing | 1B Signed in and attendance extras | Personal details in an ESS table keyed to hr_employees.id |
| E10 | Update | 1E Me and My Team | Photos through short-lived signed links |
| E11 | Update | 1E Me and My Team | Notice-period people stay on the chain with a chip in the app; the web org chart stays as it is |
| E12 | Update | 1E Me and My Team | Timeline from HR events, increments as dates only |
| F1 | Missing | 2A Wall | Posts |
| F2 | Missing | 2A Wall | Reactions and comments |
| F3 | Missing | 2A Wall | Praise and badges |
| F4 | Missing | 2A Wall | Polls |
| F5 | Missing | 2A Wall | Staff announcements in new ESS tables; student notices untouched |
| F6 | Missing | 2A Wall | Celebrations (needs date of birth from 1B) |
| F7 | Missing | 2A Wall | Moderation queue |
| F8 | Missing | 2A Wall | Wall settings |
| F9 | Missing | 2A Wall | Photos under 1 MB in an ESS storage bucket |
| G1 | Missing | 2B Helpdesk | Categories with routing, priority and response times |
| G2 | Missing | 2B Helpdesk | Tickets, thread and lifecycle, HD-0001 numbering |
| G3 | Missing | 2B Helpdesk | Response times in working hours, escalation to the HoO and the CEO |
| G4 | Missing | 2B Helpdesk | Confidential categories and anonymity, reads logged |
| G5 | Missing | 2B Helpdesk | Agent workspace on the phone; the web part per decision 7 |
| G6 | Update | 2B Helpdesk | BUILT 22 Oct (decision 9): lab/facility tickets mirror into `infra_tickets` (A/D), linked by `hr_ess_infra_links`; close-sync both ways |
| H1 | Update | 2D Leader views and deeper approvals | Class marking with the Scheduler's six checks; the sanctioned `student_attendance` and `pending_alerts` writes (decision 8) |
| H2 | Update | Out of scope (Scheduler change) | The roster reply is Scheduler code |
| H3 | Update | Out of scope (Scheduler change) | Interviewer roles are Scheduler code |
| H4 | Missing | 1E Me and My Team | HoO "my team today" for the branch |
| H5 | Update | 2D Leader views and deeper approvals | Light KPI reads in the ESS |
| H6 | Missing | 1C Requests, leave and approvals | HR's approval endpoints for the new request types |
| H7 | Update | 2D Leader views and deeper approvals | Faculty "my day" and the indicators card, read from the Scheduler |
| H8 | Ops | Phase 0 (RVM) | Re-role every HOD and HoO: I list the accounts, KP changes the roles |
| J1 | Update | Out of scope (Scheduler change) | Scheduler security fix |
| J2 | Update | Out of scope (Scheduler change) | Scheduler security fix |
| J3 | Update | Out of scope (Scheduler change) | Scheduler security fix |
| J4 | Update | Out of scope (Scheduler change) | Scheduler security fix |
| J5 | Update | Out of scope (Scheduler change) | Scheduler security fix (same as A9) |
| J6 | Update | Out of scope (Scheduler change) | Scheduler roles; the re-role itself is H8 |
| J7 | Missing | 1A Foundation | K1 and K2, in team_app. Live |
| J8 | Update | App only | The app signs out only on the real 401s; the Scheduler's own codes stay as they are |
| J9 | Missing | 3 Extras and device trust | Same as K6; checks inside the punch itself are out of scope |
| 70a | Available | Exists already | Fixed in the Scheduler (issue #70) |
| 70b | Available | Exists already | Fixed in the Scheduler (issue #70) |
| 70c | Available | Exists already | Fixed in the Scheduler (issue #70) |
| 70d | Available | Exists already | Fixed in the Scheduler (issue #70) |
| 70e | Available | Exists already | Fixed in the Scheduler (issue #70) |
| 70f | Available | Exists already | Fixed in the Scheduler (issue #70) |
| DASH | Update | Out of scope (Scheduler change) | /api/dashboard is Scheduler code |
