# The gap report checked against the current backend (STEP 1)

This is STEP 1 of the developer's prompt. Every gap-report task (A1–K6) was checked against the backend as it is today. So were the six issue #70 items the prompt names, and the brief's `/api/dashboard` claim.

**What was checked:**
- **Backend:** Scheduler_Backend `c28b9ca` (`origin/main`, 15 Oct 2026).
- **Web:** Scheduler_frontend `cd35abd`.
- **Flutter apps:** flutterapps `4712b91`.

**How it was checked:**
- **Read-only.** Nothing was run, no database was queried, and no secrets were read.
- **Readers.** Five agents each read one group of tasks.
- **Checkers.** Five more tried to refute every status and correct the evidence.
- **Corrections.** Every correction from the checkers is applied below.

Checked on 16 Oct 2026. Every claim cites file:line evidence ([status table](#status-table), [evidence](#evidence-item-by-item)).

**Since 16 Oct, Team RVM changes nothing in the Scheduler** ([ADR-0018](adr/0018-team-app-changes-nothing-in-the-scheduler.md)). This page records what the code is, including the Scheduler's own faults. It is not a list of work to do in the Scheduler. [04-build-plan.md](04-build-plan.md) says which items team_app builds, which it works around, and which are out of scope.

## The answer in numbers

105 items in all.

| Now | Count | IDs |
| --- | --- | --- |
| AVAILABLE: built, nothing to do | 16 | A2; B6, B7, B9–B13; D2, D3; the six issue #70 items |
| VERIFY-PASSED: the brief said live, and it is | 5 | B2, B3, B4, B5, B16 |
| UPDATE: part of it exists, and something must change or be added | 30 | A1, A6, A9; B1, B8, B17; C2, C6, C9, C11; E4, E10, E11, E12; G6; H1, H2, H3, H5, H7; I; J1–J6, J8, the /api/dashboard claim; K4 |
| MISSING: to build | 53 | A3, A4, A5, A7, A8, A10; B14, B15; C1, C3, C4, C5, C7, C8, C10, C12; D1, D4–D8; E1, E2, E3, E5–E9; F1–F9; G1–G5; H4, H6; J7, J9; K1, K2, K3, K5, K6 |
| OPS: RVM's own step | 1 | H8 |

K5 is missing but won't be built ([ADR-0015](adr/0015-no-automated-retention.md)).

The gap report checked `d2595e4`, which is 97 commits older. Since then the attendance work has been built.
- In section B, it marked 11 items MISSING:
  - Seven exist as written: B6, B7 and B9–B13.
  - Two exist in part: B8 and B17.
  - Only B14 (mocked location) and B15 (batched pings) are really missing.
- A2 (attendance sign-in) and D2–D3 (priority tasks) are done.

Everything that makes the app Keka-like is still to build: requests, the Inbox, push, self-service profile, the Wall and the Helpdesk.

| Where the fix sits (as seen at STEP 1) | Count | IDs |
| --- | --- | --- |
| Scheduler code: out of scope since ADR-0018 | 24 | A6, A7, A9; B1, B8, B14, B15, B17; C9, C11; E9; H1, H2, H3; J1–J6, J8, the /api/dashboard claim; K1, K4 |
| Scheduler code plus team_app: built in team_app where possible ([04-build-plan.md](04-build-plan.md)) | 19 | A5, A10; C1, C3, C7; D6, D7; E4, E6, E8, E11; F9; G6; H5, H7; I; J7, J9; K6 |
| team_app (new endpoints and tables) | 39 | A1, A3, A4, A8; C2, C4, C5, C6, C8, C10, C12; D1, D4, D5, D8; E1, E2, E3, E5, E7, E10, E12; F1–F8; G1–G5; H4, H6; K2, K3 |
| Nothing to build | 20 | A2; B2–B7, B9–B12, B16; D2, D3; the six issue #70 items |
| The app only / RVM operations | 2 | B13 (send a phone User-Agent) / H8 (re-role HODs and HoOs; the backend side lists the accounts for KP and changes no role) |
| Not built | 1 | K5 ([ADR-0015](adr/0015-no-automated-retention.md)) |

Several IDs describe the same work, so the counts overstate it:

| Same work | Overlap |
| --- | --- |
| K4 and A6 | identical |
| J5 and A9 | the same reset-password endpoint |
| J2 and H2 | the roster reply |
| J1 and H1 | J1 is part of H1 |
| J6 | H3 plus the H8 re-role |
| J7 | K1 plus K2 |
| J9 and K6 | they overlap |
| C9 and B17 | the daily-sheet lock |
| K3 and D7 | K3 is part of D7 |
| B15 and K5 | the purge part of B15 is K5 |

B5 and B16 passed their gap-report checks but carry the live bugs listed below.

## Read this first: what the gap report missed

### Security holes in the Scheduler that are open today

These are live in production, independent of the app. The gap report missed some and understated others (J1, J2, J5). Fixing them means changing the Scheduler, which this project doesn't do ([ADR-0018](adr/0018-team-app-changes-nothing-in-the-scheduler.md)). They are recorded here for KP.

1. **A phone number is enough to take over any portal account without two-factor sign-in, and to lock the owner out of one that has it.**
   - `POST /api/users/reset-password` sets a new password for the account whose phone number the caller types. No code is needed. It answers 409 only when two accounts share the number.
   - `GET /api/users` gives every login's phone number at a branch to any signed-in token, including a student's.
   - A student token needs only an admission number and a phone (A9, J5 and the identity findings in the appendix).
2. **A database dump with password hashes is committed to Scheduler_Backend.**
   - `physical_dump_2026.sql` (19.4 MB, added 4 Apr 2026) is still in the current tree, not only in the history. It holds the April users table (usernames, phone numbers, password hashes), Supabase auth sessions and refresh tokens, students, payments and receipts.
   - Deleting it, rewriting history, and revoking what it exposed are KP's decisions, outside this project.
3. **Money writes have no role check.**
   - `PATCH /api/accounts/admissions/:id/approve` lets any signed-in token approve any branch's pending admission, at an amount taken from the request.
   - `POST /api/accounts/payments` lets a faculty token record a receipt.
4. **A plain branch admin can take over elevated accounts in its branch.** `updateUser`, `assignRole` and `deleteUser` check the new role and the branch, never the target's current role.
5. **Student and staff data is open to student tokens.**
   - `POST /api/attendance` writes any batch and date (J1).
   - The marking roster, `GET /api/students` and the batch create and update replies return whole student rows, `password_hash` included (J2, wider than reported).
   - `/api/dashboard` and `GET /api/accounts/admissions` return the branch's admissions, with phones and dues.
   - `/api/alerts` can be read and resolved.
   - Anyone at a branch can post to `/api/announcements`, and anyone can delete any announcement (J4).
   - Any token can create, edit and delete batches (J3).
   - Any branch token can read any faculty member's attendance report.
   - `GET /api/faculty` returns faculty phones and leave reasons.
6. **Leaving the company does not end portal access.** Nothing on exit touches the `users` row, and `auth` never reads `hr_employees`.
7. **Smaller items:**
   - The login and code limiters can probably be skipped with a doubled slash in the path (inferred from the code, not tried).
   - The unused legacy `/api/chat/:ticketId` routes let any token read or post any ticket's old thread.
   - Under the shared first-time password, a colleague can claim someone's attendance login first (KP was told on 15 Oct).

### Live bugs found on the way

None of these is app work, but each one hurts today. Each is in Scheduler code, so it is out of scope for this project.

- **Faculty on approved leave are marked absent by the midnight job,** wherever migration `20261022000000` is applied (C11).
- **People on notice period disappear** from HR's daily sheet, the Live view, the org chart and the alerts. The HR dashboard counts them as already exited, yet they can still punch (E11).
- **Leaving before punching out costs a half day, and only an HR override can fix it.**
  - The geofence also applies to punch-out, so someone who has already left cannot punch out. The day then closes as a "No punch-out" half day.
  - No employee can ask for a correction today, which makes "fix a day" the most urgent request type. Team RVM builds it ([04-build-plan.md](04-build-plan.md)).
- **The remarks endpoint accepts a session still on HR's first-time password.** Its 503 also names the wrong migration (B5).
- **The one-CL-a-month index may not exist.** Its migration skips it, with only a NOTICE, if anyone already had two CLs in a month. Check production.
- **HR's two leave counters disagree on a blank leave type** (C5).
- **The student portal's Reopen button probably gets 403.** This would follow from the ticket hardening of 12 Oct. The portal copy checked is from 17 Jul, so confirm on the live portal.
- **The Admin Manager's attendance read is not limited to their branch** (B16).
- **HR's attendance admin actions and reads of the location trail write nothing to the audit trail.**

### Production state to confirm (read-only)

When its migration is missing, the code at `c28b9ca` switches the feature off silently. Before treating B5 and B9–B12 as live in production, confirm two things:
- migrations `20261020000000` to `20261023000000` are applied;
- the one-CL-a-month index exists.

### Corrections to the gap report

- **H3 is not AVAILABLE.** `hod_placement` is in no server interview role set. It reaches its own rounds only when its login is linked to an HR record whose ladder role, or failing that its designation, matches the leader pattern (HOD, a head, CEO, COO, CTO or HR).
- **D2 and D3 already exist.** Priority tasks v2 shipped on 29 Sep. The citations have moved.
- **J8 undercounts.** It says about 40; the code has 49 places that answer a 401 that isn't about the session: 43 for a missing branch, 4 for a wrong current password, 2 for sign-in failures. These are places in the code, not endpoints. "Please authenticate" is also sent during a database outage, so check again before signing anyone out.
- **The punch body uses `latitude` and `longitude`, not `lat` and `lng` (B3).** A note longer than 200 characters is cut, not refused.
- **Line numbers have moved:**
  - `READ_ONLY_ROLES` is `config/roles.js:109`;
  - the batch routes are `routes/batches.js:19-21`;
  - the roster selects are `controllers/attendanceController.js:214,219`;
  - `resetPassword` starts at `controllers/userController.js:1175`;
  - the 64-hour expiry is `controllers/authSecurityController.js:30`.

### What the native app must do on the existing punch path

- **Send a phone User-Agent and keep the `rvm_att_dev` cookie in a persistent jar.** The flutterapps HTTP client does neither today, so out of the box every punch is refused (B8, B13).
- **Read the limits from `GET /api/hr/my-attendance`** (`rules.max_accuracy_m`); don't hard-code them.
- **Re-read `GET /my-attendance` when a ping answers 204.** A 204 can mean four different things, so that read decides whether to stop tracking (B4).
- **Sign out only on the right 401.** That means a 401 with "No token provided" or "Please authenticate", or code `NOT_AUTHENTICATED`. Recheck once before signing out (J8).

## Status table

How to read the columns:

- **Gap report** is the status the report gave at d2595e4.
- **Now** is the status at c28b9ca, after an independent check.
- **Fix sits in** is where the change would be made, as seen when STEP 1 ran. Since [ADR-0018](adr/0018-team-app-changes-nothing-in-the-scheduler.md) (16 Oct), nothing in the Scheduler changes. So an item marked "Scheduler code" is out of scope, unless [04-build-plan.md](04-build-plan.md) rebuilds it inside team_app.

Each ID links to its evidence below.

### A. Identity, sign-in and session

| ID | Task | Gap report | Now | Fix sits in |
| --- | --- | --- | --- | --- |
| [A1](#item-a1) | Employee identity middleware (generalise punchAuth): portal token or attendance session -> hr_employees.id | MISSING | UPDATE | team_app |
| [A2](#item-a2) | Attendance-login sign-in (HRMS): password-login, otp/request, otp/verify, password; temporary:true; 5 -> 15 min lockout | MISSING | AVAILABLE | Nothing to build |
| [A3](#item-a3) | Refreshable app session: short access token + rotating hashed refresh token, install-bound, revoked on password change / HR disable / exit (access tokens minted in the Scheduler's existing formats, ADR-0006) | MISSING | MISSING | team_app |
| [A4](#item-a4) | GET /api/ess/me/capabilities (tabs, sections, approver rights) | MISSING | MISSING | team_app |
| [A5](#item-a5) | Single-field sign-in resolver (one identifier -> portal or attendance login) | MISSING (optional) | MISSING | Scheduler code + team_app |
| [A6](#item-a6) | Per-employee rate limiting, not per office IP | UPDATE | UPDATE | Scheduler code |
| [A7](#item-a7) | Sign out everywhere + refuse old tokens after a password change (portal logins) | MISSING | MISSING | Scheduler code |
| [A8](#item-a8) | Request account/data deletion form routed to HR | MISSING | MISSING | team_app |
| [A9](#item-a9) | Retire POST /api/users/reset-password (username + phone, no code) | UPDATE | UPDATE | Scheduler code |
| [A10](#item-a10) | Block shared desk logins (fbd.admin etc.) from holding a PIN, biometric or registered phone | MISSING | MISSING | Scheduler code + team_app |

### B. Attendance punch

| ID | Task | Gap report | Now | Fix sits in |
| --- | --- | --- | --- | --- |
| [B1](#item-b1) | GET /api/hr/my-attendance?month= with server_now, the day's note and HR remark in the employee's own rows | VERIFY: the brief says it is live, including server_now, the day's note and HR's remark... | UPDATE | Scheduler code |
| [B2](#item-b2) | GET /api/hr/my-attendance/challenge: valid 2 minutes, single use | VERIFY: the brief says it is live (2-minute challenge, single use) | VERIFY-PASSED | Nothing to build |
| [B3](#item-b3) | POST /api/hr/my-attendance/punch with its full refusal set | VERIFY: brief lists body (kind, nonce, lat, lng, accuracy_m, client_at, note &lt;=200) and... | VERIFY-PASSED | Nothing to build |
| [B4](#item-b4) | POST /api/hr/my-attendance/ping every 2 minutes while punched in | VERIFY: the brief says it is live | VERIFY-PASSED | Nothing to build |
| [B5](#item-b5) | PUT /api/hr/my-attendance/remarks (this month + last) | VERIFY: the brief says it is live | VERIFY-PASSED | Nothing to build |
| [B6](#item-b6) | Geofence per branch (150 m default) + HR field-staff exemption | MISSING | AVAILABLE | Nothing to build |
| [B7](#item-b7) | GPS accuracy rule &lt;= 100 m (rules.max_accuracy_m) | MISSING | AVAILABLE | Nothing to build |
| [B8](#item-b8) | One phone per person: first punch registers, HR reset, device-id header alternative to the rvm_att_dev cookie, Keystore key later | MISSING | UPDATE | Scheduler code |
| [B9](#item-b9) | Shifts (start/end, grace), week-offs, holidays per branch | MISSING | AVAILABLE | Nothing to build |
| [B10](#item-b10) | Late/half-day engine: grace, every 3rd late = half day, under 4 h = half day, early exit no grace, 00:05 IST close, no overtime | MISSING | AVAILABLE | Nothing to build |
| [B11](#item-b11) | One session per day; punch-in reopens at midnight IST (DAY_DONE) | MISSING | AVAILABLE | Nothing to build |
| [B12](#item-b12) | Holiday list (this month + next 12 within 120 days, per branch) | MISSING | AVAILABLE | Nothing to build |
| [B13](#item-b13) | Phone User-Agent enforcement (NOT_MOBILE for default OkHttp/Dart agents) | MISSING | AVAILABLE | App only |
| [B14](#item-b14) | is_mock flag on punch and ping (KP, 16 Oct: refuse a mocked punch; done on the phone, ADR-0018) | MISSING | MISSING | Scheduler code |
| [B15](#item-b15) | Batch ping upload with capture times (offline queue); the ping purge job is not built (ADR-0015) | MISSING | MISSING | Scheduler code |
| [B16](#item-b16) | Leader/HR attendance board and controls with exact guarding role sets | VERIFY: the brief says it is live | VERIFY-PASSED | Nothing to build |
| [B17](#item-b17) | HR daily-sheet lock against an approved/overridden day (Admin Manager daily sheet) | MISSING | UPDATE | Scheduler code |

### C. Requests, leave and approvals

| ID | Task | Gap report | Now | Fix sits in |
| --- | --- | --- | --- | --- |
| [C1](#item-c1) | Attendance request tables + history + work_mode (office/WFH/on duty) on the daily record | MISSING | MISSING | Scheduler code + team_app |
| [C2](#item-c2) | Employee leave (CL one a month, leave without pay) | MISSING | UPDATE | team_app |
| [C3](#item-c3) | Attendance requests (on duty, fix a day, excuse a late, short leave; WFH is not offered) with monthly quota counters - POST/GET /api/ess/attendance-requests | MISSING | MISSING | Scheduler code + team_app |
| [C4](#item-c4) | Leave requests - POST/GET /api/ess/leave-requests | MISSING | MISSING | team_app |
| [C5](#item-c5) | Leave balances - GET /api/ess/leave/balances | MISSING | MISSING | team_app |
| [C6](#item-c6) | Monthly limits config (KP, 16 Oct: no WFH; on duty no limit; fix a day 3; excuse a late 3; short leave 180 min; CL 1) | MISSING | UPDATE | team_app |
| [C7](#item-c7) | One DB function per request type that decides and writes the day in one transaction, modelled on hr_attendance_apply_override | MISSING | MISSING | Scheduler code + team_app |
| [C8](#item-c8) | Withdraw a pending request; after approval only HR can cancel | MISSING | MISSING | team_app |
| [C9](#item-c9) | Lock an approved day against the Admin Manager daily sheet, like an override | MISSING | UPDATE | Scheduler code |
| [C10](#item-c10) | Approver resolution: reporting manager (hr_employees.manager_id), HR fallback; HR/CEO/super admin can decide any | MISSING | MISSING | team_app |
| [C11](#item-c11) | Faculty approved leave also reaches staff attendance, so the midnight job does not mark those days absent | UPDATE | UPDATE | Scheduler code |
| [C12](#item-c12) | Reach-back window (this month + last) and the monthly payroll cut-off | MISSING | MISSING | team_app |

### D. Inbox, notifications and push

| ID | Task | Gap report | Now | Fix sits in |
| --- | --- | --- | --- | --- |
| [D1](#item-d1) | Approvals inbox and decide - GET /api/ess/approvals; POST /api/ess/approvals/:type/:id/decide | MISSING | MISSING | team_app |
| [D2](#item-d2) | Priority tasks visible to every role except the CEO (portal logins only: tasks are keyed to users.id, so attendance-only staff get none; changing that is a Scheduler change) | UPDATE | AVAILABLE | Nothing to build |
| [D3](#item-d3) | Priority task remarks endpoint (POST /:id/remarks) | MISSING | AVAILABLE | Nothing to build |
| [D4](#item-d4) | Multi-level approval chains with auto-skip and escalation (Phase 2) | MISSING | MISSING | team_app |
| [D5](#item-d5) | FCM device registration (POST /api/ess/devices) | MISSING | MISSING | team_app |
| [D6](#item-d6) | Notifications list + unread count (GET /api/ess/notifications) | MISSING | MISSING | Scheduler code + team_app |
| [D7](#item-d7) | Push worker on Firebase + FIREBASE_\* secrets with a length check | MISSING | MISSING | Scheduler code + team_app |
| [D8](#item-d8) | Notification categories with opt-outs and quiet hours | MISSING | MISSING | team_app |

### E. Me and My Team

| ID | Task | Gap report | Now | Fix sits in |
| --- | --- | --- | --- | --- |
| [E1](#item-e1) | Self profile (Summary / Timeline / Personal / Job), never pay or HR remarks | MISSING | MISSING | team_app |
| [E2](#item-e2) | My org chain, department, colleague directory (search by name/code, filter by branch/department) | MISSING | MISSING | team_app |
| [E3](#item-e3) | Sensitive change requests (old + new values -> HR approval) | MISSING | MISSING | team_app |
| [E4](#item-e4) | Employee documents: upload (camera/PDF), verification status, letters folder, 5-min signed link, strip storage path, masked Aadhaar | UPDATE | UPDATE | Scheduler code + team_app |
| [E5](#item-e5) | HR review queues (change requests, document verification) inside the web HRMS | MISSING | MISSING | team_app |
| [E6](#item-e6) | Team today (All / Not in yet / Late / WFH / On leave) and Off this week for anyone with reports | MISSING | MISSING | Scheduler code + team_app |
| [E7](#item-e7) | Digital ID card (photo, name, code, designation, branch, blood group, emergency contact) | MISSING | MISSING | team_app |
| [E8](#item-e8) | Colleague contact visibility rule (email/phone) | MISSING/DECISION | MISSING | Scheduler code + team_app |
| [E9](#item-e9) | hr_employees columns date_of_birth, blood_group, address, emergency_contact | MISSING | MISSING | Scheduler code |
| [E10](#item-e10) | Expose the employee photo to self/team views | UPDATE | UPDATE | team_app |
| [E11](#item-e11) | Keep notice-period people on the chain with a 'Notice period' chip (the web org chart drops them) | UPDATE | UPDATE | Scheduler code + team_app |
| [E12](#item-e12) | Timeline from HR events (joining, confirmation, changes, increments as dates only) | UPDATE | UPDATE | team_app |

### F. Wall

| ID | Task | Gap report | Now | Fix sits in |
| --- | --- | --- | --- | --- |
| [F1](#item-f1) | Wall posts (text, &lt;=5 photos/PDFs, @mentions, wall choice), edit 15 min, delete | MISSING | MISSING | team_app |
| [F2](#item-f2) | Six reactions + comments (one level of replies) + reactions on comments + who reacted | MISSING | MISSING | team_app |
| [F3](#item-f3) | Praise with RVM badges (8-12, HR-editable), reason &lt;=280, optional photo + certificate PDF | MISSING | MISSING | team_app |
| [F4](#item-f4) | Polls (>=2 options, single/multi, anonymous, closing date, options locked after the first vote) | MISSING | MISSING | team_app |
| [F5](#item-f5) | Staff announcements: audience, schedule, closing date, push + email, read/ack counts, pin &lt;=3 | UPDATE | MISSING | team_app |
| [F6](#item-f6) | Celebrations (birthdays day+month only, anniversaries, new joiners &lt;=15 days, one-tap wish, hide own birthday) | MISSING (needs DOB) | MISSING | team_app |
| [F7](#item-f7) | Moderation: report post/comment -> HR queue; hide/delete with reason; logged | MISSING | MISSING | team_app |
| [F8](#item-f8) | Wall settings: who may post what | MISSING | MISSING | team_app |
| [F9](#item-f9) | Compress photos &lt; 1 MB and store on the server | MISSING | MISSING | Scheduler code + team_app |

### G. Helpdesk

| ID | Task | Gap report | Now | Fix sits in |
| --- | --- | --- | --- | --- |
| [G1](#item-g1) | Helpdesk categories (HR-editable) with routing target, priority and SLA | MISSING | MISSING | team_app |
| [G2](#item-g2) | Tickets + thread + lifecycle (Open / In progress / On hold / Resolved / Closed), reopen &lt;=7 d, rating 1-5, withdraw, HD-0001 | MISSING | MISSING | team_app |
| [G3](#item-g3) | Response-time targets in working hours per branch, 'Overdue by 3h', escalation (category head -> HoO -> CEO) | MISSING | MISSING | team_app |
| [G4](#item-g4) | Confidential categories and optional anonymity | MISSING | MISSING | team_app |
| [G5](#item-g5) | Agent workspace (phone + web queue, filters, bulk close, saved replies, reports) | MISSING | MISSING | team_app |
| [G6](#item-g6) | Mirror lab/facility tickets into infra_tickets so the Admin Manager register stays complete | UPDATE | UPDATE | Scheduler code + team_app |

### H. Role views

| ID | Task | Gap report | Now | Fix sits in |
| --- | --- | --- | --- | --- |
| [H1](#item-h1) | Server-side checks on marking class attendance (caller owns the batch, date window, lock after first save, refuse student tokens) | UPDATE | UPDATE | Scheduler code |
| [H2](#item-h2) | Trim the marking roster reply (full students rows incl. password hashes) | UPDATE | UPDATE | Scheduler code |
| [H3](#item-h3) | hod_placement as an interviewer, and whether it can see its own interview calendar | AVAILABLE/VERIFY (roles.js:9, migration 20260914000001) | UPDATE | Scheduler code |
| [H4](#item-h4) | HoO 'my team today' attendance view | MISSING | MISSING | team_app |
| [H5](#item-h5) | Light KPI endpoints (CEO dashboard refuses super admins and runs full scans) | MISSING | UPDATE | Scheduler code + team_app |
| [H6](#item-h6) | HR approval endpoints for the new request types | MISSING (depends on C) | MISSING | team_app |
| [H7](#item-h7) | Faculty 'my day' endpoint aware of substitutions + indicators card data | UPDATE | UPDATE | Scheduler code + team_app |
| [H8](#item-h8) | Re-role every HOD and HoO before launch (RVM operations; the backend side lists the accounts for KP, read-only, and changes no role) | OPS | OPS | RVM operations |

### I. Data model

| ID | Task | Gap report | Now | Fix sits in |
| --- | --- | --- | --- | --- |
| [I](#item-i) | Data model: indicative tables, columns and functions mapped to what exists at c28b9ca | Indicative data model (attendance, punches, challenges, pings, devices, shifts,...) | UPDATE | Scheduler code + team_app |

### J. Security before launch, and the issue #70 list

| ID | Task | Gap report | Now | Fix sits in |
| --- | --- | --- | --- | --- |
| [J1](#item-j1) | POST /api/attendance accepts any signed-in token (student included) for any batch and date | OPEN (attendanceRoutes.js:43) | UPDATE | Scheduler code |
| [J2](#item-j2) | Marking roster returns full student rows incl. password hashes | OPEN | UPDATE | Scheduler code |
| [J3](#item-j3) | Batch create/edit/delete have no role check | OPEN (routes/batches.js:9-11) | UPDATE | Scheduler code |
| [J4](#item-j4) | Announcement create/delete have no role check | OPEN (routes/announcements.js:13-14) | UPDATE | Scheduler code |
| [J5](#item-j5) | Unsafe POST /api/users/reset-password (username + phone, no code) still registered | OPEN (routes/user.js:28) | UPDATE | Scheduler code |
| [J6](#item-j6) | hod_placement as interviewer; HOD/HoO on the right role | PART | UPDATE | Scheduler code |
| [J7](#item-j7) | nginx upload limit + health and minimum-app-version endpoint | OPEN | MISSING | Scheduler code + team_app |
| [J8](#item-j8) | 401 semantics: sign out only when the session is really over | SERVER+CLIENT | UPDATE | Scheduler code |
| [J9](#item-j9) | Play Integrity verification server-side | OPEN | MISSING | Scheduler code + team_app |
| [70a](#item-70a) | /api/activities without auth | Issue #70 leftover | AVAILABLE | Nothing to build |
| [70b](#item-70b) | Public course writes (/api/courses) | Issue #70 leftover | AVAILABLE | Nothing to build |
| [70c](#item-70c) | Public intake list (GET /api/intakes) | Issue #70 leftover | AVAILABLE | Nothing to build |
| [70d](#item-70d) | Public /api/chat | Issue #70 leftover | AVAILABLE | Nothing to build |
| [70e](#item-70e) | ensureFacultyId with a blank email | Issue #70 leftover | AVAILABLE | Nothing to build |
| [70f](#item-70f) | Missing /api/intakes/by-phone | Issue #70 leftover | AVAILABLE | Nothing to build |
| [DASH](#item-dash) | Brief: '/api/dashboard shows branch fee totals to faculty' (who can call it) | Brief claim (no report id) | UPDATE | Scheduler code |

### K. Infrastructure

| ID | Task | Gap report | Now | Fix sits in |
| --- | --- | --- | --- | --- |
| [K1](#item-k1) | nginx upload limit above the 1 MB default (written by deploy.yml) | MISSING | MISSING | Scheduler code |
| [K2](#item-k2) | Health + minimum-app-version endpoint | MISSING | MISSING | team_app |
| [K3](#item-k3) | FIREBASE_\* secrets in the deploy workflow with a length check | MISSING | MISSING | team_app |
| [K4](#item-k4) | Per-employee rate limiting (same as A6) | UPDATE | UPDATE | Scheduler code |
| [K5](#item-k5) | Ping purge job (retention) + 180-day access-log retention (not built: KP deletes by hand, ADR-0015) | MISSING | MISSING (not built, ADR-0015) | Scheduler code |
| [K6](#item-k6) | Play Integrity / Keystore key verification server-side; device binding id | MISSING | MISSING | Scheduler code + team_app |

## Evidence, item by item

Paths are relative to Scheduler_Backend at c28b9ca unless marked [frontend] (Scheduler_frontend cd35abd) or [flutterapps] (4712b91). "Check" is the second agent's verdict on the first agent's reading.

### A. Identity, sign-in and session (evidence)

<a id="item-a1"></a>
#### A1: Employee identity middleware (generalise punchAuth): portal token or attendance session -> hr_employees.id

- Gap report: MISSING
- Now: **UPDATE**; the fix sits in: team_app
- What exists: Both token kinds are already accepted (punchAuth) and resolved to an active hr_employees row with exit and attendance-login checks on every request (loadEmployee), but only inside the punch controller and only on /api/hr/my-attendance/\*.
- What remains: A reusable employeeAuth middleware that runs punchAuth, refuses student tokens, resolves and attaches req.employee / req.employeeId, applies isActive + sessionProblem in the middleware instead of per controller, answers unlinked portal logins with 403 NOT_LINKED, and can be mounted on a new /api/ess router outside the HR module switch. It must also accept whatever access token A3 mints.
- Notes: Can be a new file composing the exported loadEmployee/sessionProblem/readPunchSession with no change to existing routes; moving loadEmployee out of the controller into a service would be an optional refactor of existing code. A disabled attendance login is answered 403 NO_ATTENDANCE_LOGIN, not 401, because the status check runs before the epoch check (services/attendanceAccounts.js:43-51).
- Check: confirmed: Every cited line checks out. punchAuth.js:21-34 accepts a punch session (or hands the token to auth) and resolves no employee. It is mounted only on the six /my-attendance routes (routes/hr.js:198-203), behind the HR switch at :66-74. loadEmployee (attendancePunchController.js:101-129, exported at :618) does the resolution, with NOT_LINKED/NOT_ACTIVE and sessionProblem (attendanceAccounts.js:39-53; the status check runs before the epoch check, so the 403 note is right). auth.js:19-43 admits student tokens; students.id is a uuid (schema.sql:107), so a student lands on NOT_LINKED. hr_employees.user_id has a partial unique index (20260910000000:65-66). interviewsController.js:471,1203 and candidatesController.js:1498 each resolve the caller ad hoc. Pairing UPDATE with new-self-contained is fair: part of the logic exists and new code completes it. One caveat on the note: ADR-0005 (team_app/docs/adr/0005-separate-ess-service.md, KP 16 Oct) makes the ESS a separate pm2 process in team_app. It therefore cannot require loadEmployee, sessionProblem or readPunchSession in-process and must re-implement them: the punch key is sha256hex('rvm-punch-session:'+JWT_SECRET), HS256, aud rvm-punch (services/attendancePunch.js:209-239). It must also re-implement auth.js's faculty_id lookup path (auth.js:50-66) and, once A7 exists, the portal revocation epoch.
- Evidence:
  - middleware/punchAuth.js:21-34 - accepts a punch-only session (sets req.user=null, req.userType=null, req.punchEmployeeId, req.punchSession) or hands any other token to auth; it resolves no employee and does not check the attendance login
  - routes/hr.js:198-203 - punchAuth is mounted only on the six /api/hr/my-attendance routes, and those sit behind the HR module switch at routes/hr.js:66-74
  - controllers/hr/attendancePunchController.js:101-129 - loadEmployee does the resolution: hr_employees by punchEmployeeId, or by user_id = req.user.id; 403 NOT_LINKED / NOT_ACTIVE; runs sessionProblem for punch sessions; exported at :618
  - services/attendanceAccounts.js:39-53 - sessionProblem: missing or disabled login -> 403 NO_ATTENDANCE_LOGIN; session issued before sessions_valid_from -> 401 NOT_AUTHENTICATED
  - middleware/auth.js:19-43 - auth admits student tokens, so punchAuth lets a student through to the controller
  - supabase/migrations/20260910000000_hr_employee_user_link.sql:60-66 - hr_employees.user_id is unique where not null, so portal -> employee is at most one row
  - controllers/interviewsController.js:471,1203 and controllers/hr/candidatesController.js:1498 - other controllers resolve the caller to hr_employees ad hoc; there is no shared helper

<a id="item-a2"></a>
#### A2: Attendance-login sign-in (HRMS): password-login, otp/request, otp/verify, password; temporary:true; 5 -> 15 min lockout

- Gap report: MISSING
- Now: **AVAILABLE**; the fix sits in: Nothing to build
- What exists: The whole attendance sign-in as written, including first-time HR passwords (#83), temporary flag, forced own-password before punching, 5-wrong 15-minute lock and session revocation on password set/reset/disable.
- What remains: nothing
- Notes: Shipped after the audited d2595e4 (#76/#77/#83). App caveats: an employee with a portal login gets 403 HAS_PORTAL_LOGIN (attendanceOtpController.js:163-172) and HR cannot create an attendance login for them (attendanceAccountsController.js:133-135); an OTP session can punch even while HR's password is still in force (passwordChangeDue checks only method 'pw', attendancePunchController.js:190-195), so drive the forced screen from GET must_set_password, not from the sign-in temporary flag; all three sign-in routes share one 40-per-15-min per-IP bucket; HR_MODULE_ENABLED=false switches sign-in off (routes/hr.js:66-74).
- Check: confirmed: Verified: routes/hr.js:193-198 under /api/hr (server.js:162); MAX_PASSWORD_ATTEMPTS 5 and LOCK_MINUTES 15 (attendanceOtpController.js:380-381); a 429 LOCKED check, a compare-and-set claim before bcrypt, and a 15-minute lock on the 5th miss (410-435); temporary flags on password-login (441-448) and otp/verify (316-324); the /password rules and the sessions_valid_from bump (340-378); the forced change for pw sessions (attendancePunchController.js:190-197, 212-214, 293, 323, 593); the columns at 20261021000000:23-46. PR #83 (cbe9129) added no migration. Two nuances that do not change the status. HAS_PORTAL_LOGIN is returned only when the employee has no ACTIVE attendance login (attendanceOtpController.js:165-168). PUT /my-attendance/remarks (attendancePunchController.js:564-565) skips passwordChangeDue, so a session still on HR's password can write remarks.
- Evidence:
  - routes/hr.js:193-198 - POST /my-attendance/otp/request, /otp/verify, /password-login (punchCodeLimiter, no token) and /password (punchAuth) are mounted; /api/hr mounted at server.js:162
  - controllers/hr/attendanceOtpController.js:380-381 - MAX_PASSWORD_ATTEMPTS = 5, LOCK_MINUTES = 15
  - controllers/hr/attendanceOtpController.js:410-435 - lock check (429 LOCKED), attempt claimed by compare-and-set before bcrypt, 5th wrong sets locked_until = now + 15 min
  - controllers/hr/attendanceOtpController.js:441-448 - password-login 201 {token, expires_in_days:30, employee, password_set:true, temporary: !password_set_at}
  - controllers/hr/attendanceOtpController.js:316-324 - otp/verify 201 {token, expires_in_days, employee, password_set, temporary}
  - controllers/hr/attendanceOtpController.js:340-378 - /password allowed from a fresh (15 min) otp session or a pw session still on HR's password; refuses WEAK_PASSWORD / SAME_AS_HR_PASSWORD; bumps sessions_valid_from; returns a fresh token
  - controllers/hr/attendancePunchController.js:190-197,212-214 - pw session on HR's password: GET returns must_set_password, challenge/punch answer 403 PASSWORD_CHANGE_REQUIRED
  - supabase/migrations/20261021000000_hr_attendance_accounts.sql:23-46 - failed_attempts, locked_until, sessions_valid_from, password_set_at columns

<a id="item-a3"></a>
#### A3: Refreshable app session: short access token + rotating hashed refresh token, install-bound, revoked on password change / HR disable / exit (access tokens minted in the Scheduler's existing formats, ADR-0006)

- Gap report: MISSING; 64-hour JWT, no refresh (authSecurityController.js:29); model on lib/mcp/oauth.js refresh tokens
- Now: **MISSING**; the fix sits in: team_app
- What exists: Two non-refreshable bearer tokens (64h portal JWT, 30-day punch session), an MCP-only rotating refresh implementation, an attendance revocation epoch, and an unused users.password_changed_at column.
- What remains: New table (token_hash, family_id, subject user|employee, user_id, employee_id, install_id, created/last_used/expires/consumed/revoked) plus POST exchange (fresh sign-in token -> access + refresh bound to install id), POST refresh (atomic compare-and-set rotation, replay revokes the family), POST sign-out; refresh-time revocation checks: users row exists and password unchanged (e.g. fingerprint of password_hash), hr_attendance_accounts status and sessions_valid_from, hr_employees active.
- Notes: Self-contained only if: the app exchanges a fresh token from today's sign-in endpoints at a new endpoint (with an iat freshness window, else a stolen 64h token can mint a refresh family), access tokens are minted in today's portal/punch formats with a short expiry (auth.js and punchAuth then accept them unchanged), and revocation is checked at refresh time. Changing the login handlers or adding a new token kind makes it 'both'. Mint punch-format tokens as m:'pw' only: an 'otp' token counts as a fresh code sign-in for 15 min from iat and may set the password (attendanceOtpController.js:345-346). Do not copy oauth.js's consume step verbatim (race). Portal JWTs have no aud/iss and auth.js:14 checks only the signature.
- Check: confirmed: Verified: the 64h portal JWT (userController.js:512; authSecurityController.js:30). The 30-day punch session is minted only at otp/verify, /password and password-login (attendanceOtpController.js:317,377,442). No sign-in surface has a refresh, session or logout route, and auditContext.js:60-63 says there is no session table. The MCP refresh tokens are bot-only and rotate (oauth.js:223-251, routes/mcp.js:204-215, migration :44-55), and the consume step is unguarded (oauth.js:248-249). No other refresh, install or session table exists in any migration. Two citation nits. First, the cited attendanceAccountsController.js:70-81,294-303 show only HR set and disable; the reset bump is at 281-291 and the employee's own set at attendanceOtpController.js:366-374. Second, users.password_changed_at is not 'unused': profileController.js:271-274 and authSecurityController.js:176-179 stamp it, and GET /api/me returns it (profileController.js:58). It is unused only for revocation. Worth adding to the exchange endpoint: refuse student tokens (userController.js:797-801) and other JWT_SECRET-signed tokens such as the admission undertaking token (utils/admissionUndertakingToken.js:8-12), because auth.js-style verification checks only the signature.
- Evidence:
  - controllers/userController.js:498-512 - portal login signs the JWT with JWT_SECRET, expiresIn 64h; no refresh token issued
  - controllers/authSecurityController.js:20-31 - tokenFor (login/verify) mints the same 64h token; expiresIn is on line 30 at c28b9ca, not 29
  - services/attendancePunch.js:205,220-224 - punch-only session is 30 days, minted only at sign-in or password set
  - routes/user.js:25-38, routes/me.js:23-41, routes/hr.js:193-203 - no refresh, session list or logout route on any sign-in surface
  - middleware/auditContext.js:60-63 - code states there is no server-side session table
  - lib/mcp/oauth.js:223-251 and supabase/migrations/20261014000000_mcp_connector.sql:44-55 - the only refresh tokens are the MCP bot's (sha256-hashed, 30 days, rotate, replay revokes all of that bot's tokens), keyed to bot_user_id
  - lib/mcp/oauth.js:235-251 - consumeRefreshToken selects, then marks consumed by id without a consumed_at IS NULL guard: two parallel refreshes with one token both succeed
  - services/attendanceAccounts.js:39-53 and controllers/hr/attendanceAccountsController.js:70-81,294-303 - attendance logins already have a revocation epoch (sessions_valid_from) bumped by HR set/reset/disable and own password set
  - controllers/hr/attendancePunchController.js:89-90,113 - exit refuses punch sessions on every request; middleware/auth.js:68-100 never reads hr_employees, so exit does not stop a portal token

<a id="item-a4"></a>
#### A4: GET /api/ess/me/capabilities (tabs, sections, approver rights)

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: The role sets to compute from; no endpoint serving capabilities.
- What remains: A new GET /api/ess/me/capabilities behind employeeAuth (A1), returning tabs, sections and approver rights. Tabs and sections come from users.role for portal callers; decision 3 (03-decisions.md:15) gives admin, admin_manager and accounts_admin all five tabs and no Work section. Punch-session callers get the employee tabs KP settles for attendance-only staff, who are meant to use the new ESS features too (decision 8, 03-decisions.md:20). Approver rights come from the reporting line: direct reports via hr_employees.manager_id, with HR as the fallback (decision 1). Role rules sit on top: hr, ceo and super_admin may decide any request, and hr_executive only documents, profile changes and helpdesk (03-decisions.md:50). Derive the role parts from config/roles.js and config/hrPolicy.js (mirrored in client/lib/roles.ts) so the app, web and server cannot drift.
- Decided on 16 Oct: Admin, Admin Manager and Finance Admin get all five tabs. HR Executive approves documents, profile changes and HR helpdesk tickets only, never attendance or leave.
- Notes: Depends on A1. Derive it from config/roles.js + config/hrPolicy.js (mirrored in the web's client/lib/roles.ts) so app, web and server cannot drift.
- Check: corrected: Status and landing are confirmed. what_remains is corrected because approver rights cannot come from users.role alone: KP's decision 1 makes the approver the reporting manager on hr_employees.manager_id, and the HR Executive rule narrows what that role approves. Two evidence fixes. /api/me is auth-only, and students pass auth too, so 'portal-only' is wrong. The existing /api/interviews/capabilities is now named so nobody mistakes it for this task.
- Evidence:
  - server.js:127-201 - full mount list; no /api/ess
  - controllers/profileController.js:43-76 - GET /api/me returns the account (role, location_id, contact, 2FA, photo), not tabs, sections or approver rights; routes/me.js:23 puts it behind auth, which admits portal users AND student tokens (middleware/auth.js:19-43) and refuses punch sessions
  - routes/interviews.js:49 with controllers/interviewsController.js:1566-1580 - GET /api/interviews/capabilities: a module-only precedent returning four role booleans from hrPolicy sets, not the app capability document
  - config/roles.js:4-22,28-56 and config/hrPolicy.js:25-85 - the role and HR/attendance role sets a capability document would derive from
  - supabase/migrations/20260826000001_hrms_tables.sql:89 - hr_employees.manager_id, the reporting line that decides who approves (team_app/docs/03-decisions.md:13, decision 1)
  - controllers/hr/attendancePunchController.js:244-287 - GET /my-attendance is the only self-description a punch session can read

<a id="item-a5"></a>
#### A5: Single-field sign-in resolver (one identifier -> portal or attendance login)

- Gap report: MISSING (optional)
- Now: **MISSING**; the fix sits in: Scheduler code + team_app
- What exists: Two separate doors with different identifier sets and no endpoint that tells them apart.
- What remains: A new public resolver (e.g. POST /api/ess/auth/resolve {identifier}) that says which door applies and what it needs. Portal: whether a branch picker is needed. Attendance: password or code. It must handle one identifier that matches both a users row and another person's hr_employees row, and carry per-IP and per-identifier limits on the route itself. Decision 4 also needs the Scheduler's login() to accept users.email and a linked employee's employee code or HR-record phone (resolved via hr_employees.user_id), because login matches only username or users.phone_number today. Returning the username to the app instead would reveal more than login does (ADR-0004).
- Decided on 16 Oct: One sign-in field. Portal login matches only the username or users.phone_number, and changing login() is out of scope (ADR-0018). So the ESS resolver tells the app to ask for the username or login phone when the field holds a portal account's email or employee code.
- Notes: Dropping the branch picker would mean changing login (existing code). The resolver is an existence oracle for portal usernames, which forgot-password was written to avoid; the attendance OTP request already confirms existence by design (attendanceOtpController.js:31-37). One phone can be both a users.phone_number (e.g. a desk login) and another person's hr_employees.phone, so it must handle two answers.
- Check: corrected: No resolver route exists anywhere, so MISSING is confirmed. The reader's plan says which door, but misses that the portal door cannot accept three of the four identifiers decision 4 promises (email, employee code, HR phone) for linked employees. That pushes existing login() code into scope, so lands_in becomes 'both'. It stays new-self-contained only if KP accepts a 'sign in with your username or phone' fallback for portal accounts found by email or code. The note also needs a fix: the resolver is not a new kind of existence oracle. Portal login (404 vs 401) and attendance password-login (HAS_PORTAL_LOGIN and the others, before the password check) already reveal existence. The resolver only needs limits at least as strong as theirs.
- Evidence:
  - controllers/userController.js:307-321 - portal login requires username, password and locationName; an unknown branch gets 404 'Location not found.'
  - controllers/userController.js:271-279 - the typed identifier is matched exactly against users.username or users.phone_number only: not users.email, not hr_employees.employee_code, not an HR-record phone
  - controllers/userController.js:296-305 - the branch tiebreak when several accounts share an identifier
  - controllers/userController.js:352-363,426-454 - login already answers 404 'User not found' for an unknown identifier and 401 'Invalid password' for a known one, so it is already an existence oracle, bounded only by loginLimiter
  - controllers/hr/attendanceOtpController.js:93-104,118-126,132-156 - attendance identifiers: main phone or email for a code, plus employee code for the password
  - controllers/hr/attendanceOtpController.js:398-409 with 146-153,163-172 - password-login maps only NOT_FOUND to WRONG_CREDENTIALS; AMBIGUOUS, NOT_ACTIVE, NOT_MAIN_PHONE, HAS_PORTAL_LOGIN, NO_ATTENDANCE_LOGIN and PASSWORD_NOT_SET all answer before any password check
  - controllers/authSecurityController.js:109-115 - forgot-password answers the same for unknown accounts
  - team_app/docs/03-decisions.md:16 and team_app/docs/adr/0004-sign-in-unchanged.md:27,34 - one field takes phone, email, employee code or username; the resolver must not reveal more than the login endpoints already do

<a id="item-a6"></a>
#### A6: Per-employee rate limiting, not per office IP

- Gap report: UPDATE; current limiter is global/IP in server.js; a branch shares one office IP; 300 req/min
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: Per-IP limiters only, in-process memory store (no store option set anywhere), reset on every pm2 restart.
- What remains: Key authenticated traffic on the token subject (users.id or employee id; the keyGenerator must verify or decode the bearer because apiLimiter runs before auth), keep IP only for anonymous calls, re-key sign-in limiters on IP + identifier (or skip successful requests), attach the new limiters per route.
- Notes: Today the 21st portal sign-in from one office IP in 15 minutes is refused, and an OTP sign-in costs 2 of the 40 punch sign-in slots, so about 20 attendance-only people per office IP per 15 minutes. Prefix mounts are skippable (see extra findings). Same work as K4.
- Check: confirmed: Verified: apiLimiter is 60 s / 300 (server.js:80-86,125). loginLimiter is 15 min / 20, prefix-mounted (60-66,119), so login/verify shares it and successes count. One otpLimiter instance sits on six prefixes (72-78,120-124). punchCodeLimiter is one 40-per-15-min instance on three routes (punchCodeLimiter.js:19-26; routes/hr.js:193-197). No keyGenerator or store is set anywhere, so the store is in-memory. trust proxy is 1 (server.js:100), fed by nginx's X-Forwarded-For (deploy.yml:347). Versions: Express 4.22.1 and express-rate-limit 8.5.1 (package-lock.json:1922,1968). One nit: 'the only per-employee caps are the OTP issue caps' leaves out the attendance password lockout (attendanceOtpController.js:380-381,410-435), which is per account; that does not change the gap. ADR-0006 keeps punch and sign-in traffic on the Scheduler, so re-keying these limiters is change-existing-scheduler-code.
- Evidence:
  - server.js:80-86,125 - apiLimiter 60 s / 300, no keyGenerator (req.ip), mounted on all of /api including the punch routes
  - server.js:60-66,119 - loginLimiter 15 min / 20 per IP, prefix-mounted on /api/users/login so /login/verify shares it; successes count
  - server.js:72-78,120-124 - one otpLimiter instance (15 min / 10 per IP) shared by forgot-password(+confirm), me/email|phone|two-factor/request and the public admissions undertaking OTP
  - server.js:100 - trust proxy 1; req.ip is the address nginx appends (.github/workflows/deploy.yml:347)
  - middleware/punchCodeLimiter.js:19-26 and routes/hr.js:193-197 - one 15 min / 40 per-IP bucket across otp/request, otp/verify and password-login
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:234-262 - the only per-employee caps are the OTP issue caps in the database

<a id="item-a7"></a>
#### A7: Sign out everywhere + refuse old tokens after a password change (portal logins)

- Gap report: MISSING; attendance logins already have sessions_valid_from; portal does not
- Now: **MISSING**; the fix sits in: Scheduler code
- What exists: A password_changed_at column stamped by 2 of the 5 password-write paths and checked by nothing.
- What remains: A portal revocation epoch (reuse password_changed_at or add users.sessions_valid_from), stamped by all five password writes and by a new POST /api/me/sign-out-everywhere, compared with token iat in auth.js (whole seconds), and fresh tokens returned by the password-change endpoints so the caller stays signed in.
- Notes: auth.js already loads users.\* on every request (auth.js:60-65), so the check costs no extra query. Exiting an employee never writes users, so this (or A3) is also what would end a portal login at exit.
- Check: confirmed: Verified: auth.js:14-100 checks only the signature and that the row exists. The :1335 comment says the old token stays valid. password_changed_at is at 20260909000000:49. Only profileController.js:271-274 and authSecurityController.js:176-179 stamp it. The other three writes (userController.js:1313-1318, 1233-1236, 1022-1026) do not; a grep of password_hash writes finds exactly these five paths, plus the two account creations. auth.logout is registered (auditPolicy.js:145), emitted nowhere, and has no route. One addition: ADR-0006 (team_app/docs/adr/0006:27) has the ESS accept portal JWTs too, so the same iat-vs-epoch check must also run in the A1 middleware.
- Evidence:
  - middleware/auth.js:14-100 - verifies the signature and that the users row exists; no iat vs password_changed_at or epoch check
  - controllers/userController.js:1335 - change-password comment: the existing token stays valid
  - supabase/migrations/20260909000000_user_profile_security.sql:49 - users.password_changed_at exists
  - controllers/profileController.js:271-274 and controllers/authSecurityController.js:176-179 - only /api/me/password and forgot-password/confirm stamp password_changed_at
  - controllers/userController.js:1313-1318, 1230-1236, 1022-1026 - change-password, legacy reset and admin updateUser write password_hash without stamping it
  - config/auditPolicy.js:145 - an 'auth.logout' audit action is registered but nothing emits it; no logout route in routes/user.js or routes/me.js
  - services/attendanceAccounts.js:46-51 - the attendance equivalent portal lacks

<a id="item-a8"></a>
#### A8: Request account/data deletion form routed to HR

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Nothing.
- What remains: A new table (requester employee_id/user_id, kind deletion|correction, note, status, handled_by, timestamps), a POST behind employeeAuth so both token kinds work, an HR list/resolve tab in the web HRMS page, and a public web URL for Play's deletion link.
- Notes: Brief p.33 words it as 'Request correction or deletion of my data' in Me, routed to HR. The public web page is client work.
- Check: corrected: Status and landing are confirmed. One evidence line is corrected: it said attendance-only staff have 'no self-service endpoint at all'. In fact they have /api/hr/my-attendance/\* (password, remarks, punch). What they lack is any endpoint for an account or data request.
- Evidence:
  - repo-wide grep (backend and web) for deletion, erasure or data requests finds nothing; the only 'correction requests' are the inventory register's (controllers/inventoryEditRequestsController.js; supabase/migrations/20260805000004_inventory_edit_requests.sql)
  - routes/user.js:84 with controllers/userController.js:830-954 and utils/userPurge.js:98-104 - only an admin hard delete of a users row exists
  - routes/me.js:23 - /api/me sits behind auth, which rejects punch sessions (they are signed with a derived key, services/attendancePunch.js:209-213); attendance-only staff's only self-service is /api/hr/my-attendance (routes/hr.js:198-203: the punch screen, remarks, password), with nothing for a data or deletion request

<a id="item-a9"></a>
#### A9: Retire POST /api/users/reset-password (username + phone, no code)

- Gap report: UPDATE; still registered at routes/user.js:28, handler userController.js:953
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: The weak route with two live callers; the OTP replacement /api/users/forgot-password (+/confirm) exists (routes/user.js:34-35).
- What remains: Remove the route and handler (or answer 410), repoint the web Login button to /forgot-password, and replace staff_app's dialog. Give accounts without a verified email a way back: forgot-password needs email_verified_at (authSecurityController.js:149), so offer an SMS code to users.phone_number or an admin reset (PATCH /api/users/update/:userId already takes a password). Treat it as urgent: a phone number alone takes an account over today.
- Notes: Web and flutterapps must change with or before the backend (they are live consumers). The committed DB dump (extra findings) holds usernames and phones, exactly this route's inputs.
- Check: corrected: Status and landing are confirmed. The severity was understated: the route needs one value, not a username plus a phone. Its username field also matches phone_number, so the same phone typed twice is enough. A precision fix too: the handler does write an audit row (1248-1256). What it skips is the user_security_events row and the password_changed_at stamp.
- Evidence:
  - routes/user.js:27-28 - still registered, public, no code
  - controllers/userController.js:1175-1274 - the handler; the report's :953 is stale (resetPassword began there at d2595e4; :953 now closes deleteUser)
  - controllers/userController.js:1201-1202,1213-1214 - the typed username goes unquoted into .or(username.eq.X,phone_number.eq.X) and is ANDed with phone_number = the typed phone. Typing the phone number into both fields therefore matches on phone alone: an account's users.phone_number is enough to set its password (some accounts store a first name there, supabase/migrations/20260910000000_hr_employee_user_link.sql:82-84). The unquoted value is also the PostgREST grammar injection the login fix at :263-279 describes (inferred from the filter, not executed)
  - controllers/userController.js:1230-1236,1248-1256 - writes password_hash only: no password_changed_at stamp and no user_security_events row; it does record an anonymous audit event, auth.password.reset_legacy
  - server.js:119-125 - only the 300/min apiLimiter covers it
  - Scheduler_frontend client/pages/Login.tsx:173-208,349-356 - the web Login 'Forgot password?' button still posts here; the OTP page (client/App.tsx:88,135) is linked from nowhere in client/
  - flutterapps packages/data/lib/src/datasources/staff_auth_remote_data_source.dart:36-48, users_remote_data_source.dart:47-49, apps/staff_app/lib/features/login_screen.dart:168,208, contracts/scheduler.openapi.yaml:71 - staff_app's login dialog calls it

<a id="item-a10"></a>
#### A10: Block shared desk logins (fbd.admin etc.) from holding a PIN, biometric or registered phone

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: Scheduler code + team_app
- What exists: Accidental partial protection only: unlinked desk logins cannot punch or register a phone.
- What remains: An account flag (e.g. users.is_shared or a shared-login table) or policy, enforced where the app gets a long-lived session (A3 refuses to issue), at phone registration in punch, and at HR linking (PATCH /api/hr/employees/:id/account refuses a shared login).
- Notes: The brief's 14 unlinked desk logins (14 Oct) is database state and cannot be verified from code.
- Check: confirmed: Verified: users has no shared or desk flag (20260909000000:40-49), and no migration adds one. 'desk' appears only in comments (20260910000000:9,44; userController.js:618), so 'grep finds nothing' is loose wording, but the conclusion holds. Unlinked logins stop at NOT_LINKED (attendancePunchController.js:101-112,206), before phone registration (371-378,440-452). setAccount (peopleController.js:103-162) checks only that the account exists and is not linked elsewhere. Login issues a 64h token to any account (userController.js:498-512). 03-decisions.md:54 records 'Shared desk logins can't use the app' as the brief's default. A1's NOT_LINKED rule plus A3 refusing such logins would deliver most of that; the flag (or an HR-linking check) is what stops a linked desk login. 'both' fits the flag approach.
- Evidence:
  - supabase/migrations/20260909000000_user_profile_security.sql:40-49 - users has no shared/desk flag; grep for is_shared, desk or kiosk finds nothing
  - controllers/hr/attendancePunchController.js:101-112,206 - an unlinked login gets linked:false / 403 NOT_LINKED, so it never reaches phone registration (:371-378, :440-452)
  - controllers/hr/peopleController.js:103-162 - HR can link any users row to an employee with no shared-login check; once linked, that login punches and registers a phone as the person
  - controllers/userController.js:498-512 - portal login issues a 64h token to any account, desk logins included; PIN and biometric are client-side

### B. Attendance punch (evidence)

<a id="item-b1"></a>
#### B1: GET /api/hr/my-attendance?month= with server_now, the day's note and HR remark in the employee's own rows

- Gap report: VERIFY: the brief says it is live, including server_now, the day's note and HR's remark on the employee's own day rows
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: The endpoint is live. It returns today (punches, live worked_minutes, kind, holiday, status, late/early minutes, late_count, late_half_day, late_excused), the month's day rows, the shift, week-offs, the month's holidays and upcoming ones, the employee's own remarks, the device verdict (this_phone / has_registered_phone / registered_at) and rules.max_accuracy_m / mobile_only.
- What remains: Add server_now (an ISO timestamp) to the body. Add note to MY_DAY_COLUMNS: it holds the override reason, 'No punch', 'No punch-out', the holiday name or the sheet note. Add HR's remark for the month from hr_attendance_remarks, either per day or as hr_remarks[] with updated_by_name and updated_at. RVM should decide whether override reasons written for HR may be shown to the employee.
- Notes: This is a small edit to attendancePunchController.me. No migration is needed, because the column and the table already exist. Node sends an HTTP Date header by default, but that is framework behaviour, not repo code, and nothing in the body carries the time. An invalid month such as 2026-13 is not range-checked and surfaces as a 500.
- Check: confirmed: Confirmed. routes/hr.js:199 is mounted behind punchAuth, and server.js:162 mounts /api/hr. The day-row columns (attendancePunchController.js:178-179) leave out note. That column exists (20261015000004_hr_staff_attendance.sql:22) and holds the override reason (20261020000000:318-322), past-day sheet reasons (staffAttendanceController.js:376), 'No punch-out' (attendanceSettle.js:83) and 'No punch' or the holiday name (attendanceSettle.js:149). The body (244-287) has no server_now and never reads hr_attendance_remarks. The only readers of that table are staffAttendanceController.js:184 and attendanceShiftsController.js:461 (git grep). The 2026-13 claim holds: monthBounds gives '2026-13-01', Postgres rejects that date, and handle() answers 500 'Failed to load your attendance.' through moduleErrors.js:28-38. Two minor points: today.punches (266) also drops each punch's own note, and GET /challenge's expires_at is server time + 120 s, which could stand in for a server clock but is not server_now.
- Evidence:
  - routes/hr.js:199 - GET /my-attendance is mounted behind punchAuth; the router is mounted at /api/hr (server.js:162)
  - controllers/hr/attendancePunchController.js:178-179 - the day rows select only day, status, leave_type, source, first_in, last_out, worked_minutes plus the late/early/shift columns. There is no note column
  - controllers/hr/attendancePunchController.js:244-287 - the response keys are linked, employee, branch, shift, week_off_days, holidays, upcoming_holidays, my_remarks, today, device, rules, month and days. There is no server_now and no HR remark
  - controllers/hr/attendancePunchController.js:238 + services/attendanceRules.js:128-147 - my_remarks is the employee's OWN remark (hr_attendance_employee_remarks), not HR's
  - controllers/hr/staffAttendanceController.js:179-194 + controllers/hr/attendanceShiftsController.js:461-463 - hr_attendance_remarks (HR's remark) is read only by HR endpoints
  - controllers/hr/attendancePunchController.js:206,212-215 - variants {linked:false} and {must_set_password:true}; month accepts any YYYY-MM and defaults to the current IST month

<a id="item-b2"></a>
#### B2: GET /api/hr/my-attendance/challenge: valid 2 minutes, single use

- Gap report: VERIFY: the brief says it is live (2-minute challenge, single use)
- Now: **VERIFY-PASSED**; the fix sits in: Nothing to build
- What exists: A stateless signed challenge that lasts 120 s and is bound to one employee. It is single use per ACCEPTED punch, through the nonce_hash lookup plus the UNIQUE index.
- What remains: nothing
- Notes: 'Single use' means one accepted punch. A refused attempt does not use the nonce up, so the same nonce can be resent within its 120 s, for example after ACCURACY_LOW. After a lost 201, a resend gets 409 CHALLENGE_REUSED, which means the punch is already recorded: the client should reload GET, not retry. Errors: 401 with no code (portal auth), 401 NOT_AUTHENTICATED, 403 NOT_LINKED (an error here, unlike on GET), 403 NOT_ACTIVE, 403 NO_ATTENDANCE_LOGIN, 403 PASSWORD_CHANGE_REQUIRED, 503 MODULE_DISABLED / MODULE_NOT_INSTALLED, 500 'Failed to start the punch.'. Issuing a challenge checks neither the User-Agent nor the device. The key is derived from JWT_SECRET.
- Check: confirmed: Every cited line checks out: routes/hr.js:200; controller 291-296, 383-391, 351-353 vs 459-461; attendancePunch.js:23, 104-135, 141; migration 20261020000000:120-122; test 257-259. Single use means one accepted punch. A race on the UNIQUE nonce_hash insert is turned into CHALLENGE_REUSED at 307-309, because the auto-named constraint matches /nonce/. A refused attempt does not use the nonce up, as the reader says.
- Evidence:
  - routes/hr.js:200 - GET /my-attendance/challenge is mounted behind punchAuth
  - controllers/hr/attendancePunchController.js:291-296 - loadEmployee, then PASSWORD_CHANGE_REQUIRED, then Cache-Control: no-store, then issueChallenge
  - services/attendancePunch.js:23 - CHALLENGE_TTL_MS = 2 \* 60 \* 1000
  - services/attendancePunch.js:104-112 - an HMAC-SHA256 over {e: employee, x: expiry, r: random}, returned as {nonce, expires_at}
  - services/attendancePunch.js:121-135 - exactly two parts, timing-safe signature check, bound to the employee (otherwise CHALLENGE_INVALID), expiry (CHALLENGE_EXPIRED)
  - controllers/hr/attendancePunchController.js:385-391 - a nonce hash already on a punch gives 409 CHALLENGE_REUSED
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:120-122 - nonce_hash text UNIQUE on hr_attendance_punches
  - controllers/hr/attendancePunchController.js:351-353 vs 459-461 - refused rows store no nonce_hash; only the accepted punch does
  - tests/integration/hrAttendancePunch.test.js:257-259 - a replay is answered CHALLENGE_REUSED

<a id="item-b3"></a>
#### B3: POST /api/hr/my-attendance/punch with its full refusal set

- Gap report: VERIFY: brief lists body (kind, nonce, lat, lng, accuracy_m, client_at, note &lt;=200) and errors CHALLENGE_REUSED/EXPIRED, OUTSIDE_GEOFENCE, ACCURACY_LOW, DEVICE_\*, DAY_DONE/ALREADY_IN/NOT_IN, PASSWORD_CHANGE_REQUIRED, BRANCH_NOT_CONFIGURED/NOT_LINKED
- Now: **VERIFY-PASSED**; the fix sits in: Nothing to build
- What exists: The endpoint is live and checks in this order: auth, linked/active/session, password change, kind, phone UA, device, challenge, location/accuracy, geofence, in/out alternation. Accepted punches return 201 {kind, at (server time), distance_m, inside_geofence, flags[], device_registered, today{worked_minutes, punched_in, status, late_minutes, early_exit_minutes, late_count, late_half_day}}, plus Set-Cookie rvm_att_dev on the first registration.
- What remains: nothing
- Notes: EVERY reply the punch path can give (\* = stored as a refused attempt in hr_attendance_punches before the reply). Before the controller: 429 with no code (global limiter); 503 MODULE_DISABLED; 401 'No token provided' / 'Please authenticate' with no code; malformed JSON gets a 400 from Express's default handler as HTML, not JSON, because server.js has no app-level error handler (inference about framework behaviour). loadEmployee: 401 NOT_AUTHENTICATED (3 messages); 403 NOT_LINKED; 403 NOT_ACTIVE; 403 NO_ATTENDANCE_LOGIN (2 messages). Then: 403 PASSWORD_CHANGE_REQUIRED; 400 VALIDATION_FAILED; 403 NOT_MOBILE\*; 403 DEVICE_OTHER_EMPLOYEE\* (flag shared_device); 403 DEVICE_REVOKED\* (flag revoked_device); 403 DEVICE_NOT_REGISTERED\*, or 409 DEVICE_NOT_REGISTERED\* on a registration race; 400 CHALLENGE_MISSING\*; 400 CHALLENGE_INVALID\*; 400 CHALLENGE_EXPIRED\*; 409 CHALLENGE_REUSED\* (lookup or insert race); 422 LOCATION_MISSING\*; 422 ACCURACY_LOW\* +accuracy_m; 422 BRANCH_NOT_CONFIGURED\* (no branch or no coordinates; skipped for geofence_exempt staff); 422 OUTSIDE_GEOFENCE\* +distance_m,radius_m; 409 ALREADY_IN\*; 409 DAY_DONE\*; 409 NOT_IN\*; 503 MODULE_NOT_INSTALLED (names 20261020000000 or 20261021000000); generic 409 HR_RULE_VIOLATION / 409 DUPLICATE / 404 NOT_FOUND only on unexpected DB errors; 500 with no code. Brief corrections: the coordinate fields are latitude/longitude, not lat/lng (a client sending lat/lng gets 422 LOCATION_MISSING); a note longer than 200 characters is cut, not refused; an invalid client_at is stored as null, never refused. Flags that never refuse: new_device, suspicious_accuracy (accuracy 0), exempt_outside, off_network, possible_proxy. A client should sign out only on 401 'No token provided', 401 'Please authenticate' or 401 NOT_AUTHENTICATED.
- Check: confirmed: Every refusal and line in the evidence checks out, and the order matches 321-421. One point in the notes is misattributed. The brief already says 'kind, nonce, latitude, longitude, accuracy_m, client_at' (doc-export-after.md:158, and the pre-fact-check doc-export.md:158). 'lat, lng' comes from the gap report's paraphrase, not from the brief. The malformed-JSON inference is sound: express.json() runs at app level (server.js:103) and there is no app-level error handler. The router's handler at routes/hr.js:493 never sees errors raised before the router.
- Evidence:
  - routes/hr.js:201 - POST /my-attendance/punch behind punchAuth
  - server.js:80-86,125 - global /api limiter of 300 requests a minute per IP: 429 {error:'Too many requests. Please slow down.'} with no code
  - routes/hr.js:66-74 - 503 MODULE_DISABLED when HR_MODULE_ENABLED is false
  - middleware/punchAuth.js:21-34 + middleware/auth.js:10-12,102-105 - any token that is not a punch session goes to auth: 401 {error:'No token provided'} or 401 {error:'Please authenticate'}, with no code
  - controllers/hr/attendancePunchController.js:101-119 - 401 NOT_AUTHENTICATED ('Please sign in.' / 'Please sign in again.'), 403 NOT_LINKED, 403 NOT_ACTIVE, and the punch-session check
  - services/attendanceAccounts.js:39-53 - 403 NO_ATTENDANCE_LOGIN (no login, or login turned off); 401 NOT_AUTHENTICATED 'Your password was changed. Please sign in again.'
  - controllers/hr/attendancePunchController.js:323-326 - 403 PASSWORD_CHANGE_REQUIRED; 400 VALIDATION_FAILED for kind; note trimmed and silently cut to 200 characters
  - controllers/hr/attendancePunchController.js:351-378 - each refusal is stored, then answered; 403 NOT_MOBILE, 403 DEVICE_OTHER_EMPLOYEE, 403 DEVICE_REVOKED, 403 DEVICE_NOT_REGISTERED
  - controllers/hr/attendancePunchController.js:383-397 - 400 CHALLENGE_MISSING / CHALLENGE_INVALID / CHALLENGE_EXPIRED; 409 CHALLENGE_REUSED; 422 LOCATION_MISSING; 422 ACCURACY_LOW (+accuracy_m)
  - controllers/hr/attendancePunchController.js:399-421 - 422 BRANCH_NOT_CONFIGURED; 422 OUTSIDE_GEOFENCE (+distance_m, radius_m); 409 ALREADY_IN / DAY_DONE / NOT_IN
  - controllers/hr/attendancePunchController.js:441-467 - 409 DEVICE_NOT_REGISTERED when two first registrations race; 409 CHALLENGE_REUSED when a UNIQUE(nonce_hash) insert races
  - controllers/hr/attendancePunchController.js:37-47 + controllers/hr/_shared.js:135-154 + utils/moduleErrors.js:28-38 - 503 MODULE_NOT_INSTALLED (+module, migration); generic 409 HR_RULE_VIOLATION / 409 DUPLICATE / 404 NOT_FOUND; 500 {error:'Failed to record the punch.'} with no code
  - services/attendancePunch.js:144-153 - the body fields are latitude, longitude and accuracy_m (not lat/lng); accuracy_m is required and must be >= 0
  - tests/integration/hrAttendancePunch.test.js:148-150,229,257-259 - NOT_MOBILE is stored as refused; DAY_DONE and CHALLENGE_REUSED are tested

<a id="item-b4"></a>
#### B4: POST /api/hr/my-attendance/ping every 2 minutes while punched in

- Gap report: VERIFY: the brief says it is live; it asks what the ping answers when the day is closed, the phone is revoked or pings come too fast
- Now: **VERIFY-PASSED**; the fix sits in: Nothing to build
- What exists: Single-fix pings, accepted only from the registered phone while the person is punched in today, at most one per 60 s by server time.
- What remains: nothing
- Decided on 16 Oct: Tracking continues with the screen off while punched in, from a foreground service. It stops at punch-out, at shift end plus grace, or at midnight IST.
- Notes: Answers. Day closed (punched out, never punched in, or after IST midnight): 204. Phone revoked (also someone else's phone, or no or unknown cookie): 204, never 403. Pings too fast (under 60 s since the last STORED ping): 204, never 429. Session on HR's first-time password: 204. The only 429 is the shared /api limiter (300 requests a minute per IP, with no code). 400 LOCATION_MISSING comes only after those checks pass. Auth and identity errors are the same as for GET (401 with no code, 401 NOT_AUTHENTICATED, 403 NOT_LINKED / NOT_ACTIVE / NO_ATTENDANCE_LOGIN, 503, 500 'Failed to record location.'). There is no User-Agent check, no accuracy limit and no client timestamp, and nothing is ever deleted. Because 204 covers four different cases, a native tracker has to re-read GET /my-attendance (device.this_phone, today.punched_in) to know when to stop.
- Check: confirmed: Confirmed. The handler (591-612) answers 204 at 593, 595, 598 and 605, 400 at 600, and 201 at 611. identifyDevice (156-167) gives a non-'own' verdict for a revoked phone, someone else's phone and an unknown phone. PING_MIN_INTERVAL_MS is 60 s (attendancePunch.js:26). The frontend's PunchPanel.tsx:36,135 sends every 2 minutes. One wording slip: identity errors are 'the same as for GET' except NOT_LINKED, which GET turns into {linked:false} (206) while ping returns it as a 403. The notes' list already shows 403.
- Evidence:
  - routes/hr.js:202 - POST /my-attendance/ping behind punchAuth
  - controllers/hr/attendancePunchController.js:591-612 - 204 when a password change is due (593), when the phone is not 'own' (594-595), when the person is not punched in today (597-598), or when the last stored ping was under 60 s ago (602-605); 400 LOCATION_MISSING (599-600); otherwise insert and 201 {ok:true} (607-611)
  - controllers/hr/attendancePunchController.js:156-167 - a revoked phone, someone else's phone and a missing/unknown cookie all give a verdict other than 'own'
  - services/attendancePunch.js:26 - PING_MIN_INTERVAL_MS = 60 s, measured on the server clock
  - server.js:80-86,125 - the only 429 is the global /api limiter, with no code
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:131-144 - each ping stores employee, device, day, server 'at', lat, lng, accuracy and ip
  - [frontend cd35abd] client/components/attendance/PunchPanel.tsx:36 - PING_EVERY_MS = 2 \* 60 \* 1000: the 2-minute cadence belongs to the client

<a id="item-b5"></a>
#### B5: PUT /api/hr/my-attendance/remarks (this month + last)

- Gap report: VERIFY: the brief says it is live
- Now: **VERIFY-PASSED**; the fix sits in: Nothing to build
- What exists: Each employee can add, change or delete one remark per day, for any day from the 1st of last calendar month up to today. HR sees it beside HR's remark (staff-attendance employee_remarks, history employee_remarks).
- What remains: nothing
- Notes: There are two small defects; fixing them is optional and would touch attendancePunchController.js / attendanceRules.js. (1) A session signed in with HR's first-time password can write remarks without setting a password, unlike challenge, punch and ping. (2) The MODULE_NOT_INSTALLED 503 names the wrong migration. The remark changes nothing about the day itself.
- Check: confirmed: Confirmed: routes/hr.js:203, controller 564-588 and migration 20261023000000:12-19. The controller allows days from the 1st of last month to today (monthBounds/addDays), refuses over 500 characters, deletes on empty text and upserts on employee_id,day. Both defects are real. myRemarks never calls passwordChangeDue, and its 503 names RULES_MIGRATION, 20261022000000 (attendanceRules.js:25,31-39).
- Evidence:
  - routes/hr.js:203 - PUT /my-attendance/remarks behind punchAuth
  - controllers/hr/attendancePunchController.js:564-588 - checks the day is YYYY-MM-DD; DAY_OUT_OF_RANGE (400) unless the day falls between the 1st of last month and today; 400 VALIDATION_FAILED over 500 characters; empty text deletes and returns {day, remarks:null}; otherwise upsert on (employee_id, day) and return {day, remarks, updated_at}
  - supabase/migrations/20261023000000_hr_attendance_employee_remarks.sql:12-19 - hr_attendance_employee_remarks, UNIQUE(employee_id, day), 1-500 characters, kept apart from HR's remark
  - controllers/hr/attendancePunchController.js:293,323,593 vs 564-588 - challenge, punch and ping check passwordChangeDue; remarks does not
  - services/attendanceRules.js:25,31-39 - the 503 that remarks raises names 20261022000000_hr_attendance_shifts.sql, although the table comes from 20261023000000

<a id="item-b6"></a>
#### B6: Geofence per branch (150 m default) + HR field-staff exemption

- Gap report: MISSING
- Now: **AVAILABLE**; the fix sits in: Nothing to build
- What exists: A per-branch point and radius (default 150 m, 25-2000), office IPs (flag only), a per-employee field-staff exemption, and the HR, CEO and super admin endpoints to set them.
- What remains: nothing
- Notes: The radius check applies to punch-OUT as well, so someone who has already left cannot punch out, and the day closes at 00:05 as a 'No punch-out' half day. GPS accuracy is not subtracted from the distance. The exemption is set per employee, not per branch. OPS check (not verifiable read-only): every branch needs its coordinates set in HR › Attendance › Branch locations, or every non-exempt punch is refused with BRANCH_NOT_CONFIGURED.
- Check: confirmed: Confirmed: the radius column defaults to 150 with a CHECK of 25-2000, and the exempt flag exists (20261020000000:37-59). The haversine check (controller 399-413) applies to 'in' and 'out' alike. The admin endpoints (attendanceAdminController.js:306-369) sit behind canOverride (routes/hr.js:206, 213-216). GET returns radius_m, configured and geofence_exempt (246-251).
- Evidence:
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:37-48 - hr_branches gains latitude, longitude, geofence_radius_m integer NOT NULL DEFAULT 150 with CHECK 25-2000, and office_ips
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:57-59 - hr_employees.geofence_exempt boolean DEFAULT false (field staff)
  - controllers/hr/attendancePunchController.js:399-413 - haversine distance, inside when distance &lt;= radius; an exempt employee skips BRANCH_NOT_CONFIGURED and OUTSIDE_GEOFENCE, and a punch outside the branch is flagged exempt_outside
  - controllers/hr/attendanceAdminController.js:306-343 - PATCH geofence: lat/lng (both or neither), radius_m 25-2000, up to 20 office_ips
  - controllers/hr/attendanceAdminController.js:346-369 - PATCH an employee's geofence-exempt flag, and GET the exempt list
  - routes/hr.js:213-216 - branches, geofence, exempt and setExempt behind ATTENDANCE_OVERRIDE_ROLES
  - controllers/hr/attendancePunchController.js:246-251 - GET returns branch radius_m and configured, and employee.geofence_exempt

<a id="item-b7"></a>
#### B7: GPS accuracy rule &lt;= 100 m (rules.max_accuracy_m)

- Gap report: MISSING
- Now: **AVAILABLE**; the fix sits in: Nothing to build
- What exists: The server refuses fixes worse than 100 m and publishes the limit as rules.max_accuracy_m.
- What remains: nothing
- Notes: The limit is one global env value, not set per branch. Pings have no accuracy limit (controller:599-611). The server compares accuracy_m exactly as sent and does no platform scaling, so the client should read the limit from rules.max_accuracy_m and not hard-code it.
- Check: confirmed: Confirmed: MAX_ACCURACY_M is an env value defaulting to 100 (attendancePunch.js:17). The comparison is a strict '>', so exactly 100 passes (395). accuracy_m is required and must be >= 0 (151), zero is flagged (397), and GET publishes rules.max_accuracy_m (284). Pings have no upper limit (599-611).
- Evidence:
  - services/attendancePunch.js:17 - MAX_ACCURACY_M = Number(ATTENDANCE_MAX_ACCURACY_M || 100)
  - services/attendancePunch.js:144-153 - accuracy_m is required and must be >= 0, otherwise LOCATION_MISSING
  - controllers/hr/attendancePunchController.js:395 - accuracy above the limit gives 422 ACCURACY_LOW with accuracy_m in the body (exactly 100 passes)
  - controllers/hr/attendancePunchController.js:397 - accuracy of 0 is accepted but flagged suspicious_accuracy
  - controllers/hr/attendancePunchController.js:284 - GET returns rules: {max_accuracy_m, mobile_only}

<a id="item-b8"></a>
#### B8: One phone per person: first punch registers, HR reset, device-id header alternative to the rvm_att_dev cookie, Keystore key later

- Gap report: MISSING
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: Device binding with a cookie token: the first accepted punch registers the phone; one active phone per employee; a token can never belong to two people; HR can reset a phone with a reason; a reset token is refused for good (DEVICE_REVOKED); GET reports the device verdict.
- What remains: (1) Accept the device token in a request header (for example X-RVM-Device) as an alternative to the cookie, in readCookie/identifyDevice, which serve GET, punch, ping and the sign-in code request, and return a newly issued token in the 201 body or a response header for native clients. (2) Later, add a Keystore public key on hr_attendance_devices (a new column) and have the device sign the challenge. (3) Plan the rollout for phones already registered from a browser: an HR bulk reset or a transfer flow.
- Decided on 16 Oct: Phones move from the browser to the app by an HR bulk reset, branch by branch. Only a one-at-a-time reset exists today. The ESS adds an HR action that writes the same device rows the Scheduler's own reset writes (KP to confirm). A device-id header is out of scope (ADR-0018), so the app keeps the cookie.
- Notes: Without a header, a native app must persist the cookie and never clear it on logout. With the flutterapps HTTP stack as it is, the token would be lost after the first punch, and every later punch would get 403 DEVICE_NOT_REGISTERED. Staff who registered a browser will get DEVICE_NOT_REGISTERED in the app until HR resets them (controller:371-373). 'A reset phone never re-registers' depends on the token alone, so wiping the app data re-registers the phone. A header token behaves the same way; only a hardware-backed key changes that.
- Check: confirmed: Confirmed. readCookie reads only req.headers.cookie (attendancePunch.js:55-67), and identifyDevice uses nothing else (157). The token goes out only in Set-Cookie (452, 80-90), and the 201 carries only device_registered (482). hr_attendance_devices has no key or platform column (20261020000000:77-90). HR resets one phone at a time, with a reason (attendanceAdminController.js:280-293). The sign-in code limiter uses the same device verdict (attendanceOtpController.js:195-198). The flutterapps Scheduler Dio has no CookieManager (dio_factory.dart:29-42). The gap and the landing are right.
- Evidence:
  - services/attendancePunch.js:38-40,55-67 - the device token is read ONLY from the Cookie header (rvm_att_dev, which must match ^[A-Za-z0-9_-]{20,200}$)
  - services/attendancePunch.js:80-90 - Set-Cookie with HttpOnly, Path=/api/hr/my-attendance, Max-Age of 5 years, SameSite=Strict, and Secure over HTTPS
  - controllers/hr/attendancePunchController.js:156-167 - identifyDevice uses the cookie only, giving the verdicts own / other / revoked / unknown
  - controllers/hr/attendancePunchController.js:371-378,441-452 - the first ACCEPTED punch registers the phone, and the token goes out only in Set-Cookie
  - controllers/hr/attendancePunchController.js:476-484 - the punch response carries device_registered as a boolean, never the token
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:77-93 - hr_attendance_devices: token_hash UNIQUE, one active device per employee (partial unique index), no public-key or platform column
  - controllers/hr/attendanceAdminController.js:280-293 + routes/hr.js:211-212 - HR, the CEO or a super admin resets a phone, with a required reason
  - controllers/hr/attendancePunchController.js:150-154 - a revoked token never re-registers, but clearing the cookie makes the phone 'unknown' again
  - controllers/hr/attendanceOtpController.js:195-198 - the sign-in code limits per requester are keyed on the same cookie
  - [flutterapps 4712b91] packages/core_network/lib/src/dio_factory.dart:29-42 - the Scheduler Dio has no CookieManager; only the jobPortal Dio has one (:44-58)

<a id="item-b9"></a>
#### B9: Shifts (start/end, grace), week-offs, holidays per branch

- Gap report: MISSING
- Now: **AVAILABLE**; the fix sits in: Nothing to build
- What exists: Shifts with start, end and grace; per-person shift and week-off assignment; holidays for one branch or for all branches; the HR, CEO and super admin endpoints to manage them.
- What remains: nothing
- Notes: Shifts and week-offs are assigned per employee (in bulk), not per branch; there is no default shift for a branch. Shifts must end on the day they start. The day row keeps a copy of the shift it was judged by. This depends on migration 20261022000000 being applied: without it the code answers 503 or returns empty lists (attendanceRules.js:25-39,87-126).
- Check: confirmed: Confirmed against 20261022000000:57-103, routes/hr.js:221-227, attendanceShiftsController.js:39-64, 118-163, 190-243 and 253-306, and attendanceRules.js:150-166. 'Per branch' is true of holidays only. Shifts and week-offs are set per person, in bulk, and the brief never asks for branch shifts, so AVAILABLE stands.
- Evidence:
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:57-77 - hr_shifts: start_time, end_time, grace_minutes DEFAULT 15 with CHECK 0-180, end_time > start_time, live names unique
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:80-88 - hr_employees.shift_id, shift_since, and week_off_days smallint[] DEFAULT {0} limited to 0..6
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:91-103 - hr_holidays (day, name, branch_id; NULL = every branch), unique per day and branch
  - routes/hr.js:221-227 - shifts list/create/update/delete, shift-assignments, holidays add/remove, behind ATTENDANCE_OVERRIDE_ROLES
  - controllers/hr/attendanceShiftsController.js:39-64,118-163 - shift validation (grace 15 by default, 0-180, same-day only); editing a shift re-judges today only
  - controllers/hr/attendanceShiftsController.js:190-243 - bulk assignment of up to 500 people, at most 3 week-offs, shift_since set on the first assignment
  - controllers/hr/attendanceShiftsController.js:253-306 - adding or removing a holiday for a past day converts the nightly job's absent rows to holiday and back
  - services/attendanceRules.js:150-166 - a branch's own holiday wins; dayKind is no_shift, holiday, week_off or working

<a id="item-b10"></a>
#### B10: Late/half-day engine: grace, every 3rd late = half day, under 4 h = half day, early exit no grace, 00:05 IST close, no overtime

- Gap report: MISSING
- Now: **AVAILABLE**; the fix sits in: Nothing to build
- What exists: All the rules sit in one SQL function, hr_attendance_recompute, re-run for the whole month after every punch, sheet marking, override, excused late and shift change. The nightly settle and auto-fill run at 00:05 IST, with a retry and a catch-up on boot. There is no overtime.
- What remains: nothing
- Notes: Only people on a shift are judged late or early. The 3rd-late rule and the under-4-hour rule change the STATUS only on self_punch rows: sheet and override rows keep HR's status but are still counted and flagged. Excused lates do not count. The auto-fill covers staff with no shift only from 2026-10-15 (attendanceSettle.js:100,124), and shift staff from their shift_since. Each run covers the last three days (D-1 to D-3). The rules are a no-op until migration 20261022000000 is applied.
- Check: confirmed: Confirmed. The recompute function (20261022000000:238-269) holds the rules: late only past grace, early exit with no grace, a count per calendar month, n%3=0 makes a half day, and a closed self_punch day under p_half_day_minutes is a half day. HALF_DAY_MINUTES is 240 (attendancePunch.js:20) and is passed to the RPC (attendanceRules.js:224-229). The settle and auto-fill are in attendanceSettle.js:51-97 and 116-163. The crons run at 18:35 and 23:00 UTC (scheduledJobs.js:710-719), with a boot catch-up (server.js:232-234). git grep for 'overtime' finds only the comment at attendanceShiftsController.js:334 and a test asserting there is none (hrAttendanceShifts.test.js:385-396).
- Evidence:
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:238-242 - late = whole minutes from the shift start to first_in, recorded only when greater than grace_minutes
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:244-249 - early exit = minutes from last_out to the shift end when greater than 0, with no grace
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:251-258 - lates that are not excused, on present or half-day rows, are numbered within the calendar month; when n % 3 = 0 the day gets late_half_day
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:260-269 - on self_punch rows the status becomes half_day for a 3rd late, or once the day is closed with worked &lt; p_half_day_minutes
  - services/attendancePunch.js:20 + services/attendanceRules.js:221-231 - HALF_DAY_MINUTES (env, default 240) is passed to the recompute RPC after every change
  - services/attendanceSettle.js:51-97 - days left open are settled on completed in/out pairs only, with the note 'No punch-out'
  - services/attendanceSettle.js:116-163 - holiday, week_off or absent ('No punch') rows, source 'auto', for everyone employed with no row; existing rows are never overwritten
  - scheduledJobs.js:710-719 - cron 35 18 \* \* \* UTC (00:05 IST) and a retry at 0 23 \* \* \* UTC (04:30 IST)
  - server.js:232-234 - a catch-up run 30 s after every start
  - controllers/hr/attendanceShiftsController.js:334 - 'No overtime' (RVM); a grep finds no overtime field anywhere

<a id="item-b11"></a>
#### B11: One session per day; punch-in reopens at midnight IST (DAY_DONE)

- Gap report: MISSING
- Now: **AVAILABLE**; the fix sits in: Nothing to build
- What exists: After a punch-out the day is done; the next punch-in is accepted after IST midnight by server clock.
- What remains: nothing
- Notes: Someone still punched in at midnight leaves that day open. It is settled at 00:05 as 'No punch-out' (counting completed pairs only), and the new day starts NOT_IN, so an 'out' gets NOT_IN. The client must reload at IST midnight. A stale comment at 20261022000000:70-71 still says the day turns at 04:00.
- Check: confirmed: Confirmed: DAY_CUTOFF_HOURS is 0 (attendancePunch.js:171-185); ALREADY_IN, DAY_DONE and NOT_IN are at 418-421; GET reports done and punched_in (259-265); the tests are at the cited lines. The stale 04:00 comment at 20261022000000:70-71 is real.
- Evidence:
  - services/attendancePunch.js:171-185 - the attendance day is the IST calendar date; DAY_CUTOFF_HOURS = 0
  - controllers/hr/attendancePunchController.js:415-421 - 409 ALREADY_IN; 409 DAY_DONE for an 'in' after today's 'out'; 409 NOT_IN
  - controllers/hr/attendancePunchController.js:259-265 - GET today.punched_in, done and last_out
  - tests/integration/hrAttendanceDay.test.js:118 + tests/integration/hrAttendancePunch.test.js:229 - DAY_DONE is tested

<a id="item-b12"></a>
#### B12: Holiday list (this month + next 12 within 120 days, per branch)

- Gap report: MISSING
- Now: **AVAILABLE**; the fix sits in: Nothing to build
- What exists: GET /my-attendance already returns the requested month's holidays and up to 12 upcoming ones within 120 days, filtered to the employee's branch plus all-branch holidays.
- What remains: nothing
- Notes: upcoming_holidays includes today. If one day has both an all-branch and an own-branch holiday, both appear in the lists. The lists are empty until 20261022000000 is applied.
- Check: confirmed: Confirmed: holidaysBetween(day, day+120), filtered to the own branch or all branches and cut to 12 (230-237), is returned at 256-257. holidaysBetween orders by day (attendanceRules.js:118-126).
- Evidence:
  - controllers/hr/attendancePunchController.js:230-237 - the month's holidays and the upcoming ones (today to today+120, own branch or all branches, first 12)
  - controllers/hr/attendancePunchController.js:256-257 - the response carries holidays[{day,name}] for the month and upcoming_holidays[{day,name}]
  - services/attendanceRules.js:118-126,149-153 - the holiday read, where a branch's own holiday wins for a day
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:91-103 - hr_holidays has a branch_id

<a id="item-b13"></a>
#### B13: Phone User-Agent enforcement (NOT_MOBILE for default OkHttp/Dart agents)

- Gap report: MISSING
- Now: **AVAILABLE**; the fix sits in: App only
- What exists: The server already refuses any punch whose User-Agent names no phone. The defaults 'Dart/x.y (dart:io)' and 'okhttp/x.y' match none of the alternatives and get 403 NOT_MOBILE.
- What remains: Backend: nothing. The client must send a User-Agent containing 'Android' (or 'Mobile').
- Notes: The check runs only on POST /punch, not on GET, /challenge or /ping. It is a speed bump, since any client can set the header. Setting ATTENDANCE_MOBILE_ONLY=false switches it off.
- Check: confirmed: Confirmed. MOBILE_UA and the default-on switch are at attendancePunch.js:34-36. The refusal is stored before the reply (357, through reject at 351-354) and is tested at 148-150. 'Dart/x (dart:io)' and 'okhttp/x' match none of the alternatives. git grep finds no User-Agent setting anywhere in flutterapps. client-only is the right landing because the backend needs nothing.
- Evidence:
  - services/attendancePunch.js:34-36 - ATTENDANCE_MOBILE_ONLY is on by default; the UA must match /Android|iPhone|iPad|iPod|Mobile/i
  - controllers/hr/attendancePunchController.js:329,357 - 403 NOT_MOBILE, stored as a refused attempt
  - tests/integration/hrAttendancePunch.test.js:148-150 - NOT_MOBILE is refused and logged
  - [flutterapps 4712b91] packages/core_network/lib/src/dio_factory.dart:29-42 - the existing Scheduler Dio sets no User-Agent

<a id="item-b14"></a>
#### B14: is_mock flag on punch and ping (KP, 16 Oct: refuse a mocked punch; done on the phone, ADR-0018)

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: Scheduler code
- What exists: Nothing receives a mock signal. The punch flags column (text[]) could carry a new flag without a migration.
- What remains: Accept is_mock on punch and ping. On punch, either refuse with a new stored reject code (for example 422 MOCK_LOCATION) or add a 'mock_location' flag. On ping, add an is_mock column (ALTER hr_attendance_pings), or drop or flag mock fixes. A flagged punch already shows in /attendance-admin/punches?only=flagged; the web needs a label for it ([frontend] client/lib/services/attendance.ts:463-471). RVM decides between refusing and flagging.
- Decided on 16 Oct: Refuse a mocked punch. The Scheduler's punch API can't take a mock flag without a change (ADR-0018), so the app refuses on the phone and reports the attempt to the ESS for HR.
- Notes: This touches the existing punch and ping controllers and the existing pings table, so it is Scheduler work, not a self-contained service.
- Check: confirmed: git grep for is_mock, isMock, mock_location and mocked finds nothing in backend code. readFix (144-153) reads only the three fields. The pings table (131-141) has no flag column. The existing flags never refuse (396-397, 423-438). change-existing is right.
- Evidence:
  - services/attendancePunch.js:144-153 - readFix reads only latitude, longitude and accuracy_m
  - controllers/hr/attendancePunchController.js:396-397,423-438 - the only anti-spoof signals are flags that never refuse: suspicious_accuracy (accuracy 0), off_network, possible_proxy (same IP within 3 m in 2 minutes)
  - controllers/hr/attendancePunchController.js:607-609 - the ping insert stores no mock or flag field
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:131-141 - hr_attendance_pings has no is_mock or flags column
  - grep of the backend for is_mock|isMock|mock_location - no hits outside tests

<a id="item-b15"></a>
#### B15: Batch ping upload with capture times (offline queue); the ping purge job is not built (ADR-0015)

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: Scheduler code
- What exists: Live single pings only. A flushed queue would keep one point (60 s throttle), and points sent after midnight are dropped (punched-in-today check).
- What remains: Add POST /api/hr/my-attendance/pings (under the existing punchAuth router). It takes a bounded batch of [{latitude, longitude, accuracy_m, captured_at, is_mock?}]. Each captured_at must fall inside that day's open session and not ahead of server time. Dedupe on (employee_id, captured_at) and apply the 60 s throttle on captured_at. ALTER hr_attendance_pings to add captured_at with a unique index, and make HR's trail (attendanceAdminController.trail) order by it. Add a purge cron in scheduledJobs.js with the K5 retention period.
- Decided on 16 Oct: Offline punching stays off in the first version. The purge part is dropped: KP deletes old pings by hand (ADR-0015).
- Notes: The new route should sit under /my-attendance, so it inherits punchAuth and the cookie Path=/api/hr/my-attendance if it reuses the device cookie. The table change and the cron are edits to existing Scheduler code.
- Check: corrected: MISSING is right. lands_in is corrected from 'both': no piece of this is self-contained. The batch route writes the existing hr_attendance_pings table and needs a new column and unique index on it. HR's existing trail endpoint must change to use captured_at. The purge is a job in scheduledJobs.js. Every part edits existing Scheduler tables, controllers or jobs.
- Evidence:
  - routes/hr.js:199-203 - only the single-fix POST /my-attendance/ping exists; git grep for captured_at or /pings finds nothing
  - controllers/hr/attendancePunchController.js:591-612 - one fix per call, stamped with server time, a 60 s throttle on the server clock (602-605), accepted only while punched in today (597-598)
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:131-144 - hr_attendance_pings.at DEFAULT now(); no captured_at, no idempotency key, no flag column
  - controllers/hr/attendanceAdminController.js:244-246 - HR's trail reads pings ordered by the server 'at', so it would also need to read captured_at
  - controllers/hr/attendancePunchController.js:602,607 + controllers/hr/attendanceAdminController.js:245 - the only code that reads or inserts pings; nothing deletes them
  - scheduledJobs.js:691-811 - no purge job is registered

<a id="item-b16"></a>
#### B16: Leader/HR attendance board and controls with exact guarding role sets

- Gap report: VERIFY: the brief says it is live; asks for the exact role set guarding each route
- Now: **VERIFY-PASSED**; the fix sits in: Nothing to build
- What exists: Exact guards: GET /api/hr/staff-attendance = {hr, admin_manager, ceo, super_admin}. POST /attendance-admin/override, POST /attendance-admin/excuse-late, POST /attendance-admin/devices/:id/revoke, GET /attendance-admin/punches (including ?only=flagged and ?only=rejected) and GET /attendance-admin/history = {hr, ceo, super_admin}. The same three hold /trail, /devices, /overrides, /summary, shifts, holidays and geofences. Attendance logins are {hr, super_admin} (hrPolicy.js:82-85).
- What remains: nothing
- Notes: Every one of these routes needs a portal token; a punch-only session gets 401. Roles left out by exact match: hr_executive, admin, hoo, hod, hod_placement, accounts_admin, faculty. Caveats: (1) an admin_manager can READ every branch through GET /staff-attendance (rows, HR remarks, employees' own remarks, CL days), because only marking and remarks are branch-fenced. (2) No attendance view is scoped to a manager or team: nothing in the attendance code uses hr_employees.manager_id (grep), so a 'My Team' view for HOD, HoO or reporting managers needs a new endpoint.
- Check: confirmed: Confirmed. canAttend = HR_ATTENDANCE_ROLES {hr, admin_manager, ceo, super_admin} (routes/hr.js:176-181; hrPolicy.js:49-54). canOverride = {hr, ceo, super_admin} (routes/hr.js:206-229; hrPolicy.js:68-72). Logins are {hr, super_admin} (232-238; 82-85). The role values were checked in config/roles.js:4-22. allowRoles is an exact match (14-33). A punch session fails auth.js:14 and gets 401 'Please authenticate'. The brief's leaders row lists GET /staff-attendance under 'HR, CEO, super admin'; the code also admits admin_manager, and with no branch fence on read (staffAttendanceController.js:60-176).
- Evidence:
  - routes/hr.js:176,178 - GET /staff-attendance = auth + allowRoles(HR_ATTENDANCE_ROLES); refused with 403 HR_ATTENDANCE_DENIED
  - config/hrPolicy.js:49-54 - HR_ATTENDANCE_ROLES = hr, admin_manager, ceo, super_admin
  - routes/hr.js:206-212,218,228 - override, overrides, punches, trail, devices, devices/:id/revoke, excuse-late and history = auth + allowRoles(ATTENDANCE_OVERRIDE_ROLES); refused with 403 ATTENDANCE_OVERRIDE_DENIED
  - config/hrPolicy.js:68-72 - ATTENDANCE_OVERRIDE_ROLES = hr, ceo, super_admin
  - config/hrPolicy.js:21-30 - hr_executive is in HR_ROLES but deliberately left out of all three attendance sets
  - middleware/allowRoles.js:14-33 - exact role match with no inheritance; a refusal is audited as authz.denied
  - controllers/hr/attendanceAdminController.js:200-237 - punches?only=flagged returns rejected or flagged rows; ?only=rejected; summary counts accepted, rejected and flagged
  - controllers/hr/attendanceAdminController.js:51-169,280-293 - override (locks the day, reason >= 5 characters), excuse-late (reason, no lock), device revoke (reason)
  - controllers/hr/attendanceShiftsController.js:432-536 - history: one person's month with rows, remarks, every punch attempt and overrides
  - controllers/hr/staffAttendanceController.js:60-176 - the read has no branchFence; the fence is applied only in remarks (232-236) and mark (292-302)

<a id="item-b17"></a>
#### B17: HR daily-sheet lock against an approved/overridden day (Admin Manager daily sheet)

- Gap report: MISSING
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: An overridden day is locked against the daily sheet, later punches and the nightly job.
- What remains: No approved-request day exists yet, and the lock covers only source='override' rows. When approvals are built, choose one. (a) Write approved days as 'override'. They inherit the lock with no change, but later punches no longer update the row, which the brief rules out for WFH and on-duty days. (b) Add a source such as 'request'. Extend hr_staff_attendance_source_chk (20261022000000:125-127) and the sheet's lock test (staffAttendanceController.js:350) so the Admin Manager's sheet answers OVERRIDE_LOCKED for it too. The punch roll-up, the settle job and the auto-fill already treat such a row correctly. The lock lives in application code only; consider a DB trigger if more writers appear.
- Notes: The lock is keyed on source='override' and enforced in application code only; there is no DB trigger. No approved requests exist yet. When attendance or leave requests are built, approving one should write through hr_attendance_apply_override so the day inherits the lock. A new source value such as 'request' would need the CHECK at 20261022000000:125-127 and the checks above extended. A separate service writing hr_staff_attendance directly would bypass the lock.
- Check: corrected: Downgraded from AVAILABLE. The override lock is real, but it is keyed on source='override' alone. The brief (Requests and approvals) says approvals go through a NEW function because an override 'freezes the row against later punches, so it cannot carry WFH or on-duty days'. The same section says 'An approved day is locked against the Admin Manager's daily sheet, like an override'. A day locked against the sheet but still open to punches needs a source value that the CHECK refuses today. Today's sheet would overwrite such a row and relabel it manual (370-381). So existing code must change before approved days are locked.
- Evidence:
  - controllers/hr/staffAttendanceController.js:350-357 - the sheet's lock test is before?.source === 'override' and nothing else: the same status is skipped (kept_overrides), a different one gives 409 OVERRIDE_LOCKED
  - controllers/hr/staffAttendanceController.js:370-381 - any other row is overwritten by the sheet and relabelled 'manual' when its status changes
  - controllers/hr/staffAttendanceController.js:358-369 - the SHEET_STALE guard
  - controllers/hr/staffAttendanceController.js:268-277,292-302 - past days need HR_ROLES and a reason; an admin_manager marks only today, for their own branch
  - controllers/hr/attendancePunchController.js:507-511 - an 'override' row ignores later punches (only logged), so it cannot collect punch times for a WFH or on-duty day
  - controllers/hr/attendancePunchController.js:522-531 - a non-self_punch row of any other source keeps its status and gains the punch times
  - services/attendanceSettle.js:79-87,154-156 - settle touches only self_punch rows; the auto-fill never overwrites
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:290-341 - hr_attendance_apply_override writes source='override' and the before/after log in one transaction
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:125-127 - the source CHECK allows only manual, self_punch, override and auto; there is no value for an approved request
  - routes/hr.js:183-203 - no employee request or approval route exists

### C. Requests, leave and approvals (evidence)

<a id="item-c1"></a>
#### C1: Attendance request tables + history + work_mode (office/WFH/on duty) on the daily record

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: Scheduler code + team_app
- What exists: The daily record hr_staff_attendance (one row per employee per day: status, leave_type, note, source, punch times, shift snapshot, late/early fields) and the HR override log. No request tables, no request history, no work mode.
- What remains: New attendance-request table(s) (type, day(s), times or minutes, reason, status pending/approved/rejected/withdrawn/cancelled, resolved approver, decided by/at, quota month) and a request-history table, with requester, approver and actor keyed on hr_employees.id (hr_round_reschedule_requests' dual employee/user keys are the in-repo precedent). Add work_mode (office/wfh/on_duty, default office) to hr_staff_attendance and return it from GET /my-attendance (MY_DAY_COLUMNS), the HR sheet read, history and summary. The brief settles the punching question: WFH 'punching works outside the geofence and location is still recorded' and on duty 'the geofence is waived that day', so the existing punch controller (attendancePunchController.js:408-413) needs a day-level waiver read from the approved request or work_mode.
- Decided on 16 Oct: Work from home is not offered. The work_mode column and the geofence waiver would change Scheduler tables and code, which is out of scope (ADR-0018). So approved days are written through hr_attendance_apply_override: an on-duty day as present, needing no punch (ADR-0020). The request tables are new hr_ess_\* tables (ADR-0021).
- Notes: Model WFH/on duty as work_mode on a 'present' row, not as new statuses: recompute counts lates only on present/half_day (20261022000000_hr_attendance_shifts.sql:251) and every counter and colour map keys on the six statuses. Decide whether WFH/on-duty days are punched at all; if yes, the existing punch controller needs a day-level geofence exemption.
- Check: corrected: MISSING and both hold: grep finds no request table, history or work_mode. Fixed the day-row citation: line 177 is a comment, MY_DAY_COLUMNS is line 178, and the rule columns on 179 are also returned (223), so the employee already sees late/early fields. Added hr_round_reschedule_requests as a closer precedent than inventory history. The note's open question ('decide whether WFH/on-duty days are punched') is answered by the brief, which makes the punch-controller change a requirement and supports 'both'.
- Evidence:
  - supabase/migrations/20261015000004_hr_staff_attendance.sql:13-28 - hr_staff_attendance columns; status CHECK (18-20) allows only present/absent/half_day/leave/week_off/holiday; no work_mode
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:105-127 - later columns (shift snapshot, late/early, late_excused) and source CHECK manual/self_punch/override/auto; still no work_mode
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:146-162 - hr_attendance_overrides (before/after jsonb, reason) is the only per-day change history for staff attendance; no staff-attendance controller calls recordAudit and the sheet writes no event (controllers/hr/staffAttendanceController.js:424-427)
  - supabase/migrations/20260923000000_inventory_requests.sql:209-223 - inventory_request_history (status event, actor, remarks, metadata); its actor_id references users(id) at 215
  - supabase/migrations/20260913000000_hr_interview_postponement.sql:30-63 - hr_round_reschedule_requests, the closest existing request table: requester keyed on BOTH hr_employees (47) and users (48), status pending/approved/declined/withdrawn (52-53), decided_by/decided_at, decision_note
  - controllers/hr/attendancePunchController.js:177-179,223 - the employee's day rows are MY_DAY_COLUMNS (178: day, status, leave_type, source, first_in, last_out, worked_minutes) plus MY_RULE_COLUMNS (179: late/early, late_count, late_half_day, late_excused, shift times); no note, no work_mode
  - controllers/hr/attendancePunchController.js:399-413 - outside the radius a punch is refused OUTSIDE_GEOFENCE (or BRANCH_NOT_CONFIGURED) unless hr_employees.geofence_exempt, a permanent per-person flag (20261020000000_hr_attendance_punch.sql:57-59)
  - repo-wide search of controllers, services, routes, config and supabase/migrations - no work_mode, wfh, on_duty, short-leave or attendance-request table or column

<a id="item-c2"></a>
#### C2: Employee leave (CL one a month, leave without pay)

- Gap report: MISSING; leave_requests exists but is the Admin-Manager -> faculty flow (leaveController.js), not self-service CL/LWP
- Now: **UPDATE**; the fix sits in: team_app
- What exists: CL and LWP exist only as HR-recorded days: hr_staff_attendance.status='leave' with leave_type 'cl' or 'lwp'. HR/CEO/super admin record them by Override (any day, future days only for leave); HR and the Admin Manager by the daily sheet (today; past days HR with a reason). One CL a month is enforced in app code in both paths (Rules.clTaken + CL_PER_MONTH = 1) and backed by a conditional unique index. The faculty leave_requests flow (planned/emergency, AM then HoO) is unchanged and never writes hr_staff_attendance.
- What remains: The employee self-service side: a leave request (CL or LWP, one or many days, split per day and per month), pending CL counted against the one-a-month rule (clTaken sees only recorded rows), and approval writing the days through the existing CL rule and index (C4, C5, C7). Decide whether ESS leave replaces /api/am/leave for faculty or feeds it.
- Notes: Reuse Rules.CL_PER_MONTH, clTaken and isClIndexClash so the app and the HR sheet cannot disagree. No half-day leave exists (a day is either leave or half_day). A blank type is stored as 'leave', which the HR dashboard counts as unpaid (controllers/hr/attendanceShiftsController.js:379) but the history does not count as lwp (attendanceShiftsController.js:522-523).
- Check: confirmed: Opened every cited line. CL/LWP (attendanceRules.js:48-59) and CL_PER_MONTH = 1 exist only for HR-recorded days: the override (attendanceAdminController.js:46-60,96-102,117-119) and the sheet (staffAttendanceController.js:260-261,346-347,389-403,415-417) each run clTaken before writing, backed by the conditional unique index (20261022000000:129-146). leave_requests (20260804000003:78-109) is the admin-filed faculty ledger (planned/emergency, routes/amOps.js:19,80-84; leaveController.js:57-78) and never writes hr_staff_attendance. Nothing employee-facing exists. UPDATE with new-self-contained is consistent provided the pending-CL count and the approval write live in new code; the sheet lock is C9's change. The 'leave' vs lwp counter mismatch (attendanceShiftsController.js:379 vs 522-523) is real.
- Evidence:
  - supabase/migrations/20260804000003_admin_manager_ops.sql:78-109 - leave_requests: faculty_id NOT NULL -> faculty, leave_type CHECK planned/emergency (no CL/LWP), statuses pending/am_approved/approved/rejected/cancelled
  - routes/amOps.js:19,80-84 - GET/POST /api/am/leave, PATCH /leave/:id, PATCH /leave/:id/decide behind auth + requireRole(ADMIN)
  - controllers/leaveController.js:57-78 - an admin-level user applies on behalf of a faculty_id taken from the body, branch-scoped; no self-service
  - services/attendanceRules.js:41-59 - LEAVE_TYPES cl/lwp, CL_PER_MONTH = 1, leaveTypeOf (blank -> 'leave'; free text kept)
  - services/attendanceRules.js:233-263 - clTaken counts recorded CL rows in the month; clRefusal = 409 CL_LIMIT; isClIndexClash maps the unique-index error
  - controllers/hr/attendanceAdminController.js:46-60,96-102,117-119 - HR override records leave (a future day only for status leave) and refuses a second CL
  - controllers/hr/staffAttendanceController.js:260-261,346-347,389-403,415-417 - daily sheet records leave cl/lwp (today; past days HR-only with reason; never future) and refuses a second CL
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:129-146 - unique index uq_hr_staff_attendance_one_cl_a_month WHERE status='leave' AND leave_type='cl', created only if nobody already has two CLs in a month

<a id="item-c3"></a>
#### C3: Attendance requests (on duty, fix a day, excuse a late, short leave; WFH is not offered) with monthly quota counters - POST/GET /api/ess/attendance-requests

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: Scheduler code + team_app
- What exists: HR-only equivalents of two of the five types (Override for fix a day, Excuse-late). No employee request API, no WFH/on-duty concept, no short-leave model, no request quota counters (the only monthly counters are recompute's late numbering and CL).
- What remains: New ESS endpoints and tables for the five types with per-type validation; quota counters per employee per month counting pending + approved; decision functions (C7). Changes to existing code: a day-level geofence waiver in the punch controller for approved WFH/on-duty days (the brief requires punching on those days); for short leave (Phase 2 in the brief, 'lateness inside the window is not counted') hr_attendance_recompute must skip lateness inside an approved window, and whether early-leaving minutes protect against the 240-minute half day still needs a rule. Employee-requested excuses need provenance (request id) beside late_excused so the 2-a-month quota can tell them from HR's, and quota checks must use the current late numbering (recompute renumbers, 20261022000000:171-196). WFH/on duty need work_mode (C1).
- Decided on 16 Oct: Offered types: on duty (no limit), fix a day (3 a month), excuse a late (3 a month) and short leave (180 minutes a month, Phase 2). Work from home is not offered.
- Notes: An employee-requested excuse and HR's excuse write the same late_excused flag; add provenance (request id) or the 'excuse a late 2/month' quota cannot tell them apart. Excusing a late renumbers later lates (20261022000000_hr_attendance_shifts.sql:171-196), so quota checks must use the current numbering.
- Check: corrected: MISSING and both hold. Corrected one overstated line: override and excuse-late are the only TIME and late corrections, but the daily sheet also corrects a day's status (routes/hr.js:179), including for the Admin Manager today. The brief defines short leave, so it is not undefined, and implementing it changes an existing SQL function; the brief also makes the WFH/on-duty geofence waiver a requirement on the existing punch controller.
- Evidence:
  - server.js:127-201 - no /api/ess mount; routes/ has no ESS router
  - routes/hr.js:205-218 - time corrections and late excuses are HR-only: POST /attendance-admin/override and /excuse-late behind ATTENDANCE_OVERRIDE_ROLES
  - routes/hr.js:176,179; controllers/hr/staffAttendanceController.js:258-302,370-381 - the daily sheet also corrects a day, but only its STATUS (Admin Manager: today, own branch; HR/CEO/super admin: past days with a reason), never its times
  - controllers/hr/attendanceAdminController.js:51-129 - override is HR's 'fix a day' (status + HH:MM times; merged times and worked minutes at 83-94; ensureSnapshot/recompute after at 122-124)
  - controllers/hr/attendanceAdminController.js:131-169 - excuse-late sets late_excused/by/reason/at, re-counts the month, does not lock; 409 NOT_LATE
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:111-123,237-269 - late_excused exists; lateness counts for any first_in beyond grace (237-258) with no notion of an approved window; no early-exit excuse; early exits change status only through the 240-minute rule on self_punch rows (260-269)
  - controllers/hr/attendancePunchController.js:408-421 - no day-level geofence waiver (only the permanent geofence_exempt) and one session a day (DAY_DONE), so an accidental punch-out's times are fixable only by HR override
  - services/attendanceSettle.js:73-91 - a forgotten punch-out is settled at 00:05 on completed pairs only (with one session a day that is 0 minutes, so half_day) with note 'No punch-out'

<a id="item-c4"></a>
#### C4: Leave requests - POST/GET /api/ess/leave-requests

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Nothing employee-facing. /api/am/leave is an admin ledger for faculty.
- What remains: New POST/GET /api/ess/leave-requests on a new employee leave table: caller resolved to hr_employees, CL/LWP with the one-CL rule, withdraw (C8), decision through D1/C7.
- Notes: Needs the ESS identity middleware first: punch-only sessions are accepted only on /my-attendance (middleware/punchAuth.js:17-34).
- Check: confirmed: No /api/ess mount (server.js:127-201) and no ESS router. The only leave-request table is leave_requests (faculty_id NOT NULL, planned/emergency), filed by an admin-level user for a faculty_id from the body (leaveController.js:57-122; routes/amOps.js:19,80-84). punchAuth (middleware/punchAuth.js:17-34) is the only place a punch session is accepted, and loadEmployee (attendancePunchController.js:101-112) is the caller-to-employee pattern. MISSING and new-self-contained hold (plus the one-line server.js mount).
- Evidence:
  - server.js:127-201 - no /api/ess mount
  - routes/amOps.js:80-84 - the only leave endpoints are /api/am/leave (admin-level, faculty only)
  - controllers/leaveController.js:57-122 - applyForLeave requires faculty_id and leave_type planned|emergency; nobody applies for themself
  - controllers/hr/attendancePunchController.js:101-112 - the pattern for resolving the caller to their HR record (punch session employee id or hr_employees.user_id)

<a id="item-c5"></a>
#### C5: Leave balances - GET /api/ess/leave/balances

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: HR-side counters of CL used against one allowed per month. No employee balance endpoint, no accrual or carry-forward table.
- What remains: New endpoint: per-month CL remaining (1 minus recorded minus pending), LWP taken, and request-quota usage (C6). With no accrual in the code, a 'balance' is this month's allowance unless RVM decides otherwise.
- Notes: HR's two counters disagree on 'leave'/free-text rows (dashboard: unpaid; history: neither cl nor lwp). Settle one rule first, or the app and HR will show different numbers.
- Check: confirmed: No employee balance endpoint. The only counters are HR's: history summary with cl_allowed = Rules.CL_PER_MONTH (attendanceShiftsController.js:517-534), dashboard paid vs unpaid (365-379), the sheet's cl_days (staffAttendanceController.js:136-145,172), all behind HR roles (routes/hr.js:176-178,228-229). grep finds no accrual, entitlement or carry-forward logic, and amPolicy holds only faculty-leave approval rules. Minor nit: MY_DAY_COLUMNS is line 178, not 177. MISSING and new-self-contained hold.
- Evidence:
  - controllers/hr/attendanceShiftsController.js:512-533 - HR history summary counts leave, cl, lwp and returns cl_allowed = Rules.CL_PER_MONTH
  - controllers/hr/attendanceShiftsController.js:365-379 - HR dashboard counts paid_leave (cl) vs unpaid_leave (every other leave type)
  - controllers/hr/staffAttendanceController.js:136-145,172 - the sheet returns cl_days already taken in the month per person
  - routes/hr.js:228-229 - history and summary are behind canOverride (hr, ceo, super_admin)
  - controllers/hr/attendancePunchController.js:177 - GET /my-attendance day rows carry status and leave_type, so the employee sees their own leave days but no balance

<a id="item-c6"></a>
#### C6: Monthly limits config (KP, 16 Oct: no WFH; on duty no limit; fix a day 3; excuse a late 3; short leave 180 min; CL 1)

- Gap report: MISSING
- Now: **UPDATE**; the fix sits in: team_app
- What exists: Only CL = 1 a month, as Rules.CL_PER_MONTH.
- What remains: Add the five request limits (WFH 2, on duty 4, fix a day 3, excuse a late 2, short leave 120 minutes) as named config, or as an HR-editable settings row since the brief labels them 'Limit HR sets', reading CL from Rules.CL_PER_MONTH so there is one source of truth. CL stays fixed at 1 because the unique index enforces it. The five numbers are still an open RVM decision.
- Decided on 16 Oct: Limits per month: on duty no limit; fix a day 3; excuse a late 3; short leave 180 minutes; CL 1; work from home not offered.
- Notes: The numbers are still an open RVM decision in the brief (Decisions: 'Monthly request limits ... Confirm or change the numbers ... Open'; Phase 0: 'Request limits per month and the payroll cut-off date agreed').
- Check: corrected: Status and lands_in hold. Fixed the hrPolicy.js line: it said the file 'holds role sets only', but lines 18-85 are the role sets inside a 1617-line policy file with many other constants. The conclusion (no request limits anywhere) is right.
- Evidence:
  - services/attendanceRules.js:43-49 - CL_PER_MONTH = 1 (RVM 2026-10-14), a constant used by the sheet and the override
  - services/attendanceRules.js:256-260 - the CL refusal message reads CL_PER_MONTH
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:129-146 - the database backstop is a unique index that hard-codes one CL a month (created only when nobody already has two)
  - config/hrPolicy.js:18-85 - the HR and attendance role sets; the rest of this 1617-line file holds event names, employment/BGV statuses, pipeline stages and upload limits (1256-1261), and a grep of it for leave/limit/quota/per-month finds no request limit
  - repo search of config, services, controllers, routes and supabase/migrations - no WFH, on-duty, fix-a-day, excuse-a-late or short-leave limit anywhere

<a id="item-c7"></a>
#### C7: One DB function per request type that decides and writes the day in one transaction, modelled on hr_attendance_apply_override

- Gap report: MISSING; hr_attendance_apply_override not in that checkout
- Now: **MISSING**; the fix sits in: Scheduler code + team_app
- What exists: hr_attendance_apply_override exists at c28b9ca (migration 20261020000000, from #76) and writes one day plus its log atomically. The SQL function itself would write a FUTURE day and any status the table allows; the 'future days only for leave' and six-status rules exist only in the HTTP controller. A WFH/on-duty status cannot be written at all (controller list and table CHECK).
- What remains: Per-type SQL functions (leave, WFH/on duty, fix a day, excuse a late, short leave, and cancel) that in one transaction lock the request, check it is pending and the caller may decide, check the monthly quota/CL, write hr_staff_attendance (with work_mode), keep the before-row for reversal, write request history and PERFORM hr_attendance_recompute. The controller's guards must be re-implemented inside SQL.
- Decided on 16 Oct: Approvals go through the existing hr_attendance_apply_override (ADR-0020). The ESS enforces the statuses, the future-day rule, one CL a month, the reach-back window and the cut-off, then recomputes the month. No new Scheduler function is added.
- Notes: Reusing the override function as is would stamp every approval source 'override' (later punches on that day are only logged: attendancePunchController.js:511), replace the day's note with the reason, and list approvals in HR's override history (attendanceAdminController.js:171-192). A distinct source value needs the source CHECK widened (20261022000000_hr_attendance_shifts.sql:125-127), hence 'both'.
- Check: confirmed: hr_attendance_apply_override exists (20261020000000:282-341): FOR UPDATE, upsert with source 'override' and note = p_reason, before/after into hr_attendance_overrides, no day or status check; service_role only (349-366). The six-status list and future-only-for-leave rule are in the controller (attendanceAdminController.js:15,57-60); the table CHECK refuses other statuses (20261015000004:18-20); the CL check runs before and ensureSnapshot/recompute after the RPC, outside its transaction (96-128); recompute is plpgsql with a transaction-scoped advisory lock (20261022000000:197-286). No per-type decision function exists. Both holds: new functions plus a widened source CHECK and work_mode on an existing table.
- Evidence:
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:282-341 - hr_attendance_apply_override(p_employee_id uuid, p_day date, p_branch_id uuid, p_status text, p_leave_type text, p_first_in timestamptz, p_last_out timestamptz, p_worked_minutes integer, p_reason text, p_by uuid, p_by_name text) RETURNS jsonb: SELECT ... FOR UPDATE, upsert with source 'override' and note = p_reason, append before/after to hr_attendance_overrides; the body has no day or status check
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:349-366 - EXECUTE revoked from PUBLIC/anon/authenticated, granted to service_role only
  - controllers/hr/attendanceAdminController.js:15 - const STATUSES = ['present', 'absent', 'half_day', 'leave', 'week_off', 'holiday'];
  - controllers/hr/attendanceAdminController.js:57-60 - if (!STATUSES.includes(status)) return bad(...); if (day > A.istDay() && status !== 'leave') { return bad(res, 'Only leave can be recorded for a day that has not happened yet.'); }
  - supabase/migrations/20261015000004_hr_staff_attendance.sql:18-20 - status CHECK IN ('present','absent','half_day','leave','week_off','holiday') refuses 'wfh'/'on_duty' at the database
  - controllers/hr/attendanceAdminController.js:96-102,104-128 - the CL check runs in the app before the RPC; ensureSnapshot and recompute run after it, outside its transaction
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:197-286 - hr_attendance_recompute(uuid[], date, date, integer) is plpgsql with a per-employee-month advisory lock, so a new function can PERFORM it in the same transaction

<a id="item-c8"></a>
#### C8: Withdraw a pending request; after approval only HR can cancel

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: No attendance or leave request to withdraw. Withdraw/cancel patterns exist in inventory requests; faculty leave has an unreachable 'cancelled' status.
- What remains: Requester withdraw while pending (race-safe, as inventoryRequestsController.js:985-996 does); an HR-only cancel of an approved request that restores the pre-approval day and re-runs recompute in the same transaction; history rows for both. Restoring needs the before-row stored at approval, as the override stores it; cancelling an approved CL must free that month's CL. Use ATTENDANCE_OVERRIDE_ROLES (or hr alone), not HR_ROLES, which includes hr_executive.
- Notes: Restoring needs the before-row stored at approval time, as the override stores it. Cancelling an approved CL must free that month's CL. Use role hr (plus CEO/super admin if RVM wants), not HR_ROLES, which includes hr_executive (config/hrPolicy.js:25-30).
- Check: corrected: MISSING and new-self-contained hold. Corrected 'no route sets it': PATCH /api/admin-records/leave_requests/:id can set status to 'cancelled' for a super admin or the CEO, though no workflow does and faculty.leave_\* would not be cleared. Added the reschedule-request table, which has the same unused 'withdrawn' state.
- Evidence:
  - controllers/inventoryRequestsController.js:963-1004 - existing pattern: the raiser withdraws while pending, an approver may stop it, conditional update .eq('status', r.status) with 409 RACED, history row written
  - supabase/migrations/20260804000003_admin_manager_ops.sql:93-94 - leave_requests allows 'cancelled', but no workflow route sets it; it is reachable only as a raw status edit by a super admin or the CEO through the data manager (routes/adminRecords.js:18,27; config/managedRecords.js:41-47 lists status as editable), which leaves faculty.leave_\* untouched
  - controllers/leaveController.js:178-180 - decideLeave only refuses an already cancelled request; routes/amOps.js:80-84 has no cancel route
  - supabase/migrations/20260913000000_hr_interview_postponement.sql:52-53 - hr_round_reschedule_requests also has a 'withdrawn' status that no route sets (routes/interviews.js:51-52,70)
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:337-338 - the override log keeps the before-row, the model for restoring a day when an approved request is cancelled

<a id="item-c9"></a>
#### C9: Lock an approved day against the Admin Manager daily sheet, like an override

- Gap report: MISSING
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: The lock is hr_staff_attendance.source = 'override'. The daily sheet refuses to change such a row (OVERRIDE_LOCKED), punches only log, settle and auto-submit skip it, and only another override changes it.
- What remains: Request-approved days have no source of their own. Writing them as 'override' locks them but files them as HR overrides (override history, note = reason) and keeps punch times off the row, which does not fit WFH/on-duty days the brief says are punched. A new source such as 'request' needs: the source CHECK widened (20261022000000:125-127); the sheet lock extended to it (staffAttendanceController.js:350-357); the forced snapshot refresh to skip it (attendanceRules.js:201); a per-type rule at the punch roll-up (attendancePunchController.js:511): lock leave and fix-a-day rows, but on WFH/on-duty days keep the status and record the times (the existing non-override path at 513-531 already does that); a decision on whether nightly settle (attendanceSettle.js:79-87, self_punch only) closes a request day left punched in; and a web label. Excuse-late deliberately does not lock.
- Decided on 16 Oct: Covered by writing approved days through the override function: source override already locks the day against the daily sheet (ADR-0020).
- Notes: Excuse-late deliberately does not lock (attendanceAdminController.js:131-138); decide per request type whether an approval locks the day.
- Check: corrected: UPDATE and change-existing hold. Two refinements. 'Only another override changes it' is true for status and times, but excuse-late (no source check) and recompute still rewrite an override row's late fields. And the suggestion to treat a new source like 'override' at attendancePunchController.js:511 would keep punch times off WFH/on-duty days; nightly settle is a further touchpoint the reader did not list.
- Evidence:
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:27-33,317-335 - source 'override' = set by HR/CEO/SA, only they may change it; the function always writes source 'override'
  - controllers/hr/staffAttendanceController.js:304-357,381 - the sheet reads each row's source; an override row re-saved with the same status is skipped (kept_overrides), a different status gets 409 OVERRIDE_LOCKED; otherwise a status change relabels the row 'manual'
  - controllers/hr/attendancePunchController.js:487-536 - a punch on an override day is only logged (511); on any other non-self_punch row the status is kept and the punch times are written (513-531)
  - services/attendanceSettle.js:79-87,154-156 - nightly settle updates only self_punch rows; the auto fill never overwrites an existing row
  - services/attendanceRules.js:193-201 - a forced shift-snapshot refresh skips override rows
  - controllers/hr/attendanceAdminController.js:149-163 - excuse-late updates late_excused on the row whatever its source, override rows included
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:125-127,260-279 - source CHECK manual/self_punch/override/auto; recompute keeps the status of any non-self_punch row but rewrites its late/early/late_count/late_half_day

<a id="item-c10"></a>
#### C10: Approver resolution: reporting manager (hr_employees.manager_id), HR fallback; HR/CEO/super admin can decide any

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: The reporting line (manager_id, cycle-safe) and the 'decide any' role set (ATTENDANCE_OVERRIDE_ROLES). No code resolves an approver from manager_id.
- What remains: A resolver: approver = the requester's current manager_id when that person is active and can sign in (linked portal login, or an attendance-only login, which unlinked people can hold: attendanceOtpController.js:164-167), else HR (role hr); HR/CEO/super admin may decide any; no self-approval. Because the lifecycle, sweep and dismissal functions re-parent reports silently, resolve at read/decide time (or re-resolve on a schedule) rather than trusting an approver stored at submit; hooking those functions instead would change existing code.
- Decided on 16 Oct: The reporting manager decides, HR is the fallback, and HR, the CEO and super admins may decide any request. HR Executive does not decide attendance or leave requests.
- Notes: A manager who is attendance-only can approve only once the ESS identity accepts punch sessions beyond /my-attendance (middleware/punchAuth.js:17-34). An unlinked portal manager is invisible to the resolver until HR links the login.
- Check: corrected: MISSING and new-self-contained hold. The evidence line was wrong twice: the manager route is routes/hr.js:122 (119 is PATCH /employees/:id), and manager_id does not change only through it. It is set on create and convert, and four database functions re-parent reports when a manager leaves. That shapes how the resolver must work.
- Evidence:
  - supabase/migrations/20260826000001_hrms_tables.sql:89,128,150-193 - hr_employees.manager_id (self-FK), not own manager, trigger refuses reporting cycles
  - routes/hr.js:120-122; controllers/hr/employeesController.js:1155-1170,820-826 - an explicit move goes through PATCH /employees/:id/manager -> hr_move_employee; PATCH /employees/:id refuses manager_id (USE_MANAGER_ENDPOINT)
  - controllers/hr/employeesController.js:87-99; controllers/hr/candidatesController.js:1276 - manager_id is also set on create and on candidate convert
  - supabase/migrations/20260917000000_hr_employment_lifecycle.sql:276-299,425-448; supabase/migrations/20261015000005_hr_dismissal_letter.sql:161-170 - when a manager is archived, exits, is dismissed or their notice period ends, their reports are re-parented automatically to the leaver's own manager (or a chosen target)
  - controllers/hr/orgChartController.js:77-112 - roots have no manager; orphans point at a manager who is archived, has left or is filtered out
  - config/hrPolicy.js:21-23,68-72 - ATTENDANCE_OVERRIDE_ROLES = hr, ceo, super_admin; hr_executive deliberately excluded
  - controllers/hr/attendancePunchController.js:101-112 - caller -> employee by punch-session employee id or hr_employees.user_id
  - supabase/migrations/20260910000000_hr_employee_user_link.sql:21-32,60-66 - hr_employees.user_id link; the backfill linked only certain pairs and left 'the majority' NULL for HR to link
  - controllers/inventoryRequestsController.js:976 - approver logic in the code is role-based (P.isApprover), never manager-based

<a id="item-c11"></a>
#### C11: Faculty approved leave also reaches staff attendance, so the midnight job does not mark those days absent

- Gap report: UPDATE; leaveController.js mirrors to faculty.leave_\*
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: Approval mirrors to faculty.leave_\* only. For a faculty member with an hr_employees row who is on approved /api/am/leave today and is neither punched nor marked, the next 00:05 IST run writes that day 'absent' / 'No punch' / source 'auto' (unless a holiday or week-off), and it stays until HR corrects it on the sheet with a reason or by Override.
- What remains: On approval (including emergency leave approved after the fact), write the leave days into hr_staff_attendance for the linked employee (status leave, CL or LWP per the CL rule), replacing 'auto' rows but never 'override' rows; or make fillInDay mark approved leave_requests days as leave. Needs the faculty -> users.faculty_id -> hr_employees.user_id join, which fails for unlinked faculty.
- Notes: This is live now, not only for the app: since 2026-10-15 every employed person not on a shift is auto-filled (if 20261022000000 is applied in production). leave_requests.leave_type is planned/emergency, so mapping to CL vs LWP is a policy call.
- Check: confirmed: Opened all cited lines. Approval writes only faculty.leave_\* (leaveController.js:150-156,255-257). fillInDay reads only hr_employees, hr_staff_attendance and hr_holidays and inserts absent/'No punch'/auto/'Automatic' for anyone employed with no row (attendanceSettle.js:116-152), unshifted staff from ALL_STAFF_FROM 2026-10-15 (99-100,123-129). The crons run at 00:05 and 04:30 IST plus 30 s after boot for D-1..D-3 (scheduledJobs.js:710-719; server.js:232-234; attendanceSettle.js:37-49). The insert is dropped before 20261022000000 (157-160). hr_employees has no faculty_id; the only join is users.faculty_id (schema.sql:125) -> hr_employees.user_id. UPDATE and change-existing hold.
- Evidence:
  - controllers/leaveController.js:150-156,255-257 - on final approval only faculty.leave_start_date/leave_end_date/leave_reason are written (one range, overwritten by the next approval); hr_staff_attendance is never written
  - services/attendanceSettle.js:116-152 - fillInDay reads only hr_employees, hr_staff_attendance and hr_holidays; an employed person with no row on a working day gets status 'absent', note 'No punch', source 'auto', marked by 'Automatic'
  - services/attendanceSettle.js:99-100,123-129 - covered from shift_since if on a shift, otherwise from ALL_STAFF_FROM = '2026-10-15'
  - services/attendanceSettle.js:37-49; scheduledJobs.js:710-719; server.js:232-234 - runs 00:05 and 04:30 IST and 30 s after every start, for D-1..D-3
  - services/attendanceSettle.js:157-160 - before migration 20261022000000 (which allows source 'auto') the insert fails and nothing is written
  - scheduledJobs.js:67-77 - only the faculty class-attendance snapshot honours faculty.leave_\* (a different job)
  - schema.sql:125; supabase/migrations/20260910000000_hr_employee_user_link.sql:60-66 - the only path from a faculty record to its HR record is users.faculty_id -> hr_employees.user_id
  - controllers/hr/staffAttendanceController.js:260-261 - the Admin Manager cannot pre-mark future leave on the sheet

<a id="item-c12"></a>
#### C12: Reach-back window (this month + last) and the monthly payroll cut-off

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: A this-month-plus-last window for employee remarks only. No payroll cut-off concept anywhere.
- What remains: Validate request days against this month + last (reuse the remark window logic) and a configurable payroll cut-off day after which last month closes to requests; RVM to pick the day.
- Decided on 16 Oct: The payroll cut-off is the 5th of the next month: last month stays open to requests until then.
- Notes: If the cut-off must also freeze HR's sheet and Override for a closed month, that changes existing code (staffAttendanceController.js:258-277, attendanceAdminController.js:51-60).
- Check: confirmed: The only employee-side reach-back rule is the remarks window (attendancePunchController.js:570-574). The sheet and override have no lower bound (staffAttendanceController.js:258-277; attendanceAdminController.js:51-60). grep finds no payroll cut-off anywhere ('Payroll is handled by consultants', 20261015000004:11). The only monthly lock is the HOD skill matrix (hodController.js:733-740). MISSING and new-self-contained hold.
- Evidence:
  - controllers/hr/attendancePunchController.js:570-574 - the only reach-back rule: employee remarks limited to this month or last, up to today (400 DAY_OUT_OF_RANGE)
  - controllers/hr/staffAttendanceController.js:258-277 - HR may change any past day with a reason; no lower bound
  - controllers/hr/attendanceAdminController.js:51-60 - override has no lower bound on the day
  - supabase/migrations/20261015000004_hr_staff_attendance.sql:11 - 'Payroll is handled by consultants: no salary math reads this table.'
  - controllers/hodController.js:733-740 - precedent of a monthly lock day (previous month editable until the 10th)

### D. Inbox, notifications and push (evidence)

<a id="item-d1"></a>
#### D1: Approvals inbox and decide - GET /api/ess/approvals; POST /api/ess/approvals/:type/:id/decide

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Three per-module decide paths (faculty leave, interview reschedules, inventory requests). No cross-module inbox.
- What remains: New inbox listing requests where the caller is the resolved approver (C10) or holds ATTENDANCE_OVERRIDE_ROLES, with counts, and a decide endpoint per type calling the C7 functions. Decide which existing queues also appear: the brief's HoO list names asset requests, faculty leave over 2 days or touching the 1st, interview reschedules and the final hiring decision, each with its own decide endpoint today.
- Notes: The existing faculty-leave decide is PATCH, the brief's new one is POST. Record decisions in the audit trail the way the guards do (middleware/allowRoles.js:21-29).
- Check: corrected: Status and lands_in hold: no cross-module inbox exists. But 'three per-module decide paths' undercounts. The HoO hiring decision (which the brief lists among the HoO's approvals) and admissions, adjustments, inventory edit requests and certificates also have approve/decide endpoints.
- Evidence:
  - server.js:127-201 - no /api/ess mount
  - routes/amOps.js:84 - faculty leave decide is PATCH /api/am/leave/:id/decide (admin-level)
  - routes/interviews.js:51-52 - interview reschedules: GET /reschedules and POST /reschedules/:requestId/decide
  - routes/inventoryRequests.js:37,45-46; controllers/inventoryRequestsController.js:330-336,365,441-444,526 - inventory has its own role-driven approval queue (?queue=approval) with pending_my_approval
  - routes/hod.js:33-37,80 - the HoO's final hiring decision, PATCH /api/hod/interviews/:id/decision, which the brief puts in the HoO's one approvals list
  - routes/accountsRoutes.js:49,52,74-75; routes/inventory.js:84-85; routes/studentCertificates.js:56 - further per-module approve/reject paths (admissions, payment adjustments, inventory edit requests, certificates)

<a id="item-d2"></a>
#### D2: Priority tasks visible to every role except the CEO (portal logins only: tasks are keyed to users.id, so attendance-only staff get none; changing that is a Scheduler change)

- Gap report: UPDATE; read guard requireRole(ADMIN) at routes/priorityTasks.js:17; recipients limited to admin_manager/admin at reportingPolicy.js:69
- Now: **AVAILABLE**; the fix sits in: Nothing to build
- What exists: Every portal role except the CEO can be set a task by name (CEO/super admin may name all of them; the HoO may name faculty, hod, admin, admin_manager at their own centre). A broadcast reaches admin_manager and admin. Every participant role (all but student and bot_readonly; the CEO reads an always-empty inbox) uses the bell, opens tasks, moves their own with a remark of 3+ characters, adds remarks and acks. Only the CEO or a super admin closes or re-raises.
- What remains: nothing
- Notes: Attendance-only staff (no users row) cannot receive tasks: assigned_to is a users FK, createTask and the recipient list read users, and their punch session is refused on /api/priority-tasks. If the Team app must give them tasks, that is new work: create users rows with a minimal role (TASK_ASSIGNEE_ROLES derives from ROLES, so it would join automatically) or add an employee-keyed assignee and accept the ESS identity here. The app must call these routes with the portal JWT.
- Check: confirmed: At c28b9ca the inbox, open, move, remark and ack routes are behind allowRoles(PARTICIPANTS) (routes/priorityTasks.js:20-25,44,52-55), a real exact-role guard (allowRoles.js:14-33). TASK_ASSIGNEE_ROLES is derived as every role except ceo, student and bot_readonly (reportingPolicy.js:24-27), so hr_executive is included. CEO/super admin may name all of them (101-105), and createTask checks the target's users row (priorityTasksController.js:420-456). The brief itself scopes priority tasks to portal logins, so the attendance-only gap does not make this UPDATE. The report's UPDATE came from the pre-29-Sep v1 guard.
- Evidence:
  - routes/priorityTasks.js:20-25,44,52-55 - inbox, open, move, remarks, ack behind auth + allowRoles(TASK_ASSIGN_ROLES + TASK_ASSIGNEE_ROLES), code NOT_A_TASK_PARTICIPANT
  - middleware/allowRoles.js:14-33 - exact-role guard: 401 with no role, 403 when the role is not in the set
  - config/reportingPolicy.js:16-27 - TASK_ASSIGNEE_ROLES = every ROLES value except ceo, student, bot_readonly (derived, so hr_executive is included)
  - config/reportingPolicy.js:84,91,101-105,107-115 - setters CEO/super admin/HoO; closers CEO/super admin; CEO and super admin may name any assignee role; HoO only faculty, hod, admin, admin_manager; broadcasts reach admin_manager and admin only
  - controllers/priorityTasksController.js:63-70,420-456 - addressedToMe = named, or broadcast for broadcast roles; HoO kept to own centre; a named recipient must be a users row the sender may name
  - supabase/migrations/20260814000001_reporting_discipline_and_priority_tasks.sql:39 - priority_tasks.assigned_to REFERENCES users(id)
  - middleware/punchAuth.js:17-34; services/attendancePunch.js:194-212; middleware/auth.js:14,102-105 - punch-only sessions use a key derived from JWT_SECRET and are refused by auth on every route except /my-attendance

<a id="item-d3"></a>
#### D3: Priority task remarks endpoint (POST /:id/remarks)

- Gap report: MISSING
- Now: **AVAILABLE**; the fix sits in: Nothing to build
- What exists: POST /api/priority-tasks/:id/remarks is live and adds to the task's append-only thread.
- What remains: nothing
- Notes: Plain remarks have no minimum length; the 3-character minimum applies only to status moves (controllers/priorityTasksController.js:521-530). Requires the portal JWT.
- Check: confirmed: POST /api/priority-tasks/:id/remarks is mounted (server.js:158) and guarded (routes/priorityTasks.js:54). addRemark (priorityTasksController.js:607-628) loads the task (404/403 via loadTask 218-232), refuses closed or withdrawn tasks with 409 (refuseFinal 51-54), checks canRemark (utils/priorityTaskAccess.js:81-83), requires a body of at most 2000 characters, and appends to priority_task_remarks (189-215; 20260929000000:72). AVAILABLE, nothing to do.
- Evidence:
  - server.js:158 - /api/priority-tasks is mounted
  - routes/priorityTasks.js:54 - router.post('/:id/remarks', readAccess, c.addRemark)
  - controllers/priorityTasksController.js:607-628 - loads the task (403 if not visible), 409 when closed or withdrawn, 403 unless canRemark, body (or remark) required, at most 2000 characters, 201 with the full thread
  - controllers/priorityTasksController.js:189-215 - appends to priority_task_remarks and bumps remark_count/last_activity so others see it as unread
  - utils/priorityTaskAccess.js:81-83 - canRemark: the recipient or whoever runs the task, until closed or withdrawn
  - supabase/migrations/20260929000000_priority_task_threads.sql:72-75 - priority_task_remarks table

<a id="item-d4"></a>
#### D4: Multi-level approval chains with auto-skip and escalation (Phase 2)

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: One hard-coded two-step chain (faculty leave) and flag-only escalation jobs.
- What remains: Configurable chains per request type, auto-skip (absent, on leave, same person, no login) and time-based escalation that re-routes and notifies.
- Notes: RVM removed multi-step approval from inventory requests on 2026-10-08; confirm appetite before building Phase 2 chains.
- Check: confirmed: Faculty leave's AM -> HoO step (leaveController.js:223-246) is the only enforced chain. The HOD verdict and the HoO hiring decision are separate fields, and the decision is deliberately not blocked on the verdict (hodController.js:1305,1356-1358). The escalation jobs only set flags (scheduledJobs.js:297-366); the interview hold expiry (398-406) turns stale holds into rejections without re-routing. inventory_request_approvals (20260923000000:184) is left over from the retired 3-step flow (20261008000000:1-15). MISSING and new-self-contained hold.
- Evidence:
  - controllers/leaveController.js:223-246 - the only multi-step approval: faculty leave AM -> HoO when over 2 days or near the salary credit day
  - supabase/migrations/20261008000000_simple_requests.sql:1-15 - inventory requests were cut from three steps to one on RVM's instruction (2026-10-08)
  - scheduledJobs.js:297-362 - escalation jobs only set an escalated flag on pending_alerts and infra_tickets; nothing re-routes or skips

<a id="item-d5"></a>
#### D5: FCM device registration (POST /api/ess/devices)

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Nothing for push. The only device table is the punch binding.
- What remains: New push-token table keyed on hr_employees.id plus an installation id (token, platform, app version, last seen, revoked) and POST/DELETE /api/ess/devices; revoke on sign-out, exit and HR disable.
- Notes: Ops: a Firebase project and Android app registration are needed; none exists in any repo. Keep push tokens separate from hr_attendance_devices to avoid confusing them with the punch binding.
- Check: confirmed: No push dependency in package.json (20-37). No Firebase/FCM code or google-services file in the backend, web frontend or flutterapps (grep; the one hit is base64 inside a design preview). hr_attendance_devices (20261020000000:73-93) is the punch cookie binding. No /api/ess. MISSING and new-self-contained hold (revocation on exit or disable can be checked at send time).
- Evidence:
  - package.json:20-37 - no firebase-admin or other push dependency
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:73-93 - hr_attendance_devices is the punch phone binding (sha256 of the rvm_att_dev cookie), not push tokens
  - server.js:127-201 - no /api/ess route
  - repo search of backend, web frontend and flutterapps - no FCM/Firebase code, no google-services.json, no push-token table

<a id="item-d6"></a>
#### D6: Notifications list + unread count (GET /api/ess/notifications)

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: Scheduler code + team_app
- What exists: No hr_notifications or general notification table. Three bells: the priority-task bell (with real unread receipts), the HR alerts bell (computed, HR roles only) and pending_alerts (student remark alerts for branch staff). Outbound channels are email (interview mails, HR digest, custom email worker) and SMS codes.
- What remains: New notification table keyed on hr_employees.id (category, title, body, deep link, read_at), GET /api/ess/notifications with an unread count and mark-read, and writers on request submitted/decided (new code). Task-event entries, which the reader's scope includes, need hooks in the existing priority-task controller (createTask, addToThread, close/reraise) or a trigger on priority_tasks/priority_task_remarks; the only new-only alternative is to merge /api/priority-tasks/inbox into the list at read time.
- Notes: Do not reuse /api/alerts as a notification source: it checks only location, not role (see extra findings). Folding priority-task events into the new list avoids a second polling loop.
- Check: corrected: MISSING holds. lands_in corrected to both: the reader's own what_remains includes writers for task events, and no event hook exists in the priority-task code, so that part edits existing code. Also noted that admin_notifications comes from a real migration, not only the backup dump.
- Evidence:
  - routes/priorityTasks.js:44; controllers/priorityTasksController.js:259-290 - task bell: GET /api/priority-tasks/inbox returns tasks, unread and outstanding
  - supabase/migrations/20260814000001_reporting_discipline_and_priority_tasks.sql:62-68; supabase/migrations/20260929000000_priority_task_threads.sql:60-67 - priority_task_reads (read_at, last_read_at) drive unread; keyed on users(id)
  - controllers/priorityTasksController.js:189-215 - a task event is written only to priority_task_remarks and the task's counters; nothing emits a notification, so task-event entries need a hook here or a trigger on these tables
  - frontend:client/components/PriorityTaskBell.tsx:30,53-70 - the web polls the inbox every 120 s
  - routes/hr.js:89-95; controllers/hr/alertsController.js:7-31 - HR alerts computed on read (GET /api/hr/alerts), resolutions stored in hr_alert_resolutions; shown only in the HR workspace (frontend:client/pages/HrWorkspace.tsx:209-210)
  - routes/alertsRoutes.js:10-17; supabase/migrations/20260507000000_features_red_flag_followup_alerts.sql:67-85 - pending_alerts for missing student absence remarks (GET /api/alerts/pending)
  - scheduledJobs.js:535-565 - HR alert digest goes by email
  - supabase/migrations/20251215134244_remote_schema.sql:520-526 (also public_schema_backup.sql:1298-1305) - legacy admin_notifications (application_id, student_id, message, is_read) is created by a migration; no backend or web code reads it

<a id="item-d7"></a>
#### D7: Push worker on Firebase + FIREBASE_\* secrets with a length check

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: Scheduler code + team_app
- What exists: No push worker and no Firebase secrets. Patterns to copy exist: the deploy-time secret checks and the in-process email worker.
- What remains: Push outbox table + in-process worker sending through FCM HTTP v1, started from server.js; FIREBASE_\* lines in the deploy heredoc plus a length/format check step; console mode (log, do not send) when the keys are blank, matching the SMS convention.
- Decided on 16 Oct: No Firebase project yet: the worker writes messages to the log until the FIREBASE_\* keys exist (ADR-0016). It runs inside the ESS, so its secrets go in team_app's deploy job.
- Notes: Ops: create the Firebase project and service account. Store the service-account key base64-encoded on one line (see the heredoc finding).
- Check: confirmed: No Firebase SDK (package.json:20-37) and no FIREBASE_\* line in the heredoc (deploy.yml:73-161; grep for firebase finds nothing). The MCP length check (204-218) and the SMS console-mode warning (220-241) are the patterns to copy. The in-process email worker with a SKIP LOCKED queue starts at server.js:254-263 (20260922130001:7,66). Both holds: new worker and outbox, plus edits to deploy.yml and server.js, and Firebase ops.
- Evidence:
  - package.json:20-37 - no Firebase SDK
  - .github/workflows/deploy.yml:71-161 - secrets are written into .env by an unquoted heredoc; no FIREBASE_\* line
  - .github/workflows/deploy.yml:204-218 - existing secret length-check pattern (MCP secrets at least 32 characters, ::error::)
  - .github/workflows/deploy.yml:220-241 - SMS check with the console-mode warning when the key is blank
  - server.js:254-263; supabase/migrations/20260922130001_email_module_rpcs.sql:7 - in-process email worker with a Postgres queue claimed FOR UPDATE SKIP LOCKED, the model for a push outbox worker

<a id="item-d8"></a>
#### D8: Notification categories with opt-outs and quiet hours

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Nothing.
- What remains: Per-employee preferences per category (with some categories not opt-out-able, e.g. approvals assigned to me) and quiet hours applied by the push worker, which keeps the in-app list unchanged.
- Notes: Compute quiet hours in IST, like all day logic in the code (services/attendancePunch.js:171-185).
- Check: confirmed: grep finds no notification categories, preferences, opt-outs, quiet hours or suppression lists in code or migrations. Mail is deliberately transactional with no unsubscribe (config/mailBrand.js:82-85). MISSING and new-self-contained hold.
- Evidence:
  - repo search of controllers, services, config, routes and supabase/migrations - no notification categories, preferences, opt-outs or quiet hours
  - config/mailBrand.js:82-85 - mail is treated as transactional with deliberately no unsubscribe

### E. Me and My Team (evidence)

<a id="item-e1"></a>
#### E1: Self profile (Summary / Timeline / Personal / Job), never pay or HR remarks

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Every read of the HR record is limited to the four HR roles (hr, hr_executive, ceo, super_admin), with pay under the same four through its own guard. What employees can read about themselves: GET /api/hr/my-attendance (name, code, geofence flag, branch, shift, week-offs, holidays, attendance days), GET /api/me (login account, no HR data) and their own interview rounds. The Job data is all there in hr_employees: designation, role_id to the hr_roles ladder, department, branch, manager, date_of_joining, seniority, employment_status and shift. Pay is in hr_employee_compensation and remarks in hr_employee_remarks, both in separate guarded tables.
- What remains: New self endpoints (for example GET /api/hr/me/profile) behind punchAuth with no allowRoles (allowRoles returns 401 for punch sessions). Resolve the caller the way loadEmployee does (punch employee id, else hr_employees.user_id = req.user.id). Re-read the record on every call and refuse NOT_LINKED, NOT_ACTIVE and PASSWORD_CHANGE_REQUIRED. Whitelist columns, leaving out performance_tag, bgv_\*, archive_\*, legacy_\*, attribution, user_id and increment_date. Resolve department, branch, role, manager and status labels on the server, since /lookups is HR-only. Sign the photo. Take the Timeline from E12 and the Personal section from E9.
- Notes: The Personal section is blocked on E9 and the Timeline on E12. Routes mounted inside routes/hr.js inherit the HR kill switch. Punch-only tokens are designed to open only /my-attendance (services/attendancePunch.js:190-199), so serving attendance-only staff here is a deliberate policy widening. date_of_joining was empty on every migrated row (controllers/hr/dashboardController.js:124-126), so tenure may be blank until HR backfills it.
- Check: confirmed: Checked routes/hr.js:53-55,66-74,193-203 (the three guards, the kill switch, and /my-attendance behind punchAuth only), middleware/allowRoles.js:14-31 (a real 401/403 with an audit row), punchAuth.js:21-34, attendancePunchController.js:92,101-129,244-257 and profileController.js:43-62,72-76 (GET /api/me returns the login row only). I searched every router for me/my/self/profile paths. Only /api/me, /api/hr/my-attendance, /api/interviews/mine/upcoming and /api/hod/my-domains exist, and none returns the HR job or personal record, so MISSING stands. Two nuances that do not change it. (1) 'The only self read' is loose: other own-row reads exist (interviewsController.js:471,1203; candidatesController.js:1498; services/senderIdentity.js:72-76), but none returns HR fields to the employee. (2) GET /api/users (routes/user.js:69, auth only) gives every login at a branch its own and its colleagues' full_name and designation (userController.js:626-651), but no department, manager, joining date or personal data, and nothing for punch-only staff. New punchAuth endpoints should also refuse userType 'student' outright, because punchAuth falls through to auth and auth admits student tokens (middleware/auth.js:19-42).
- Evidence:
  - routes/hr.js:53-55 - canRead / canWrite / canSeePay = auth + allowRoles(HR_ROLES / HR_WRITE_ROLES / HR_COMP_ROLES), codes HR_ACCESS_DENIED / HR_READ_ONLY / HR_COMP_DENIED
  - config/hrPolicy.js:25-41 - HR_ROLES = HR_WRITE_ROLES = {hr, hr_executive, ceo, super_admin}
  - config/hrPolicy.js:111-116,128-130 - HR_COMP_ROLES = the same four; HR_COMP_DELETE_ROLES = {super_admin}
  - config/hrPolicy.js:49-54,68-72,82-85 - HR_ATTENDANCE_ROLES {hr, admin_manager, ceo, super_admin}; ATTENDANCE_OVERRIDE_ROLES {hr, ceo, super_admin}; ATTENDANCE_ACCOUNT_ROLES {hr, super_admin}
  - routes/hr.js:98,113-122,149,159,244-247,262-292,466-474,487-490 - lookups, org-chart, employees, employees/:id, exits, exit, checklist, remarks, compensation, increment-date, activity, documents: all behind canRead/canWrite/canSeePay
  - middleware/allowRoles.js:14-31 - a real guard: 401 with no userType, 403 plus an audit row when the role is not in the set
  - routes/hr.js:66-74 - HR_MODULE_ENABLED=false returns 503 MODULE_DISABLED on every /api/hr route, my-attendance included
  - routes/hr.js:193-203 + middleware/punchAuth.js:21-34 - /my-attendance/\* is the only /api/hr surface with no role check (portal JWT or punch-only session)
  - controllers/hr/attendancePunchController.js:92,101-129,244-257 - the only self read of hr_employees: employee {id, full_name, employee_code, geofence_exempt}, plus branch, shift, week_off_days and holidays
  - routes/me.js:23-25 + controllers/profileController.js:43-62,72-76 - GET /api/me returns the users login row only (username, role, login phone/email, 2FA, self photo); no HR data
  - controllers/hr/employeesController.js:72-84 - the HR SELECT carries performance_tag, bgv_note, archive_reason, legacy_\*, referred/recruited_by and source_candidate_id, so a self view must whitelist columns rather than wrap it
  - controllers/interviewsController.js:1198-1209 - /api/interviews/mine/upcoming reads its own hr_employees row (id, full_name) only to filter the caller's own interview rounds

<a id="item-e2"></a>
#### E2: My org chain, department, colleague directory (search by name/code, filter by branch/department)

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: All the data (the manager_id graph, department, branch, employee code) plus HR-only search and filters. There is no read for non-HR users.
- What remains: New punchAuth endpoints: (1) the chain, walking manager_id over live rows (is_archived = false, so notice-period people stay) and flagging an inferred top; (2) a department view derived from people and ladder rank, since departments are flat; (3) a directory with q (name or code) and branch/department filters returning a redacted person shape (contact fields per E8) with photos signed in one batch. Build it on hr_employees, not on GET /api/users, which is a branch login list that already leaks contact fields (E8).
- Decided on 16 Oct: Work email is visible to every colleague; a phone number only to that person's manager chain and HR.
- Notes: Do not reuse orgChartController.hasLeft, which hides notice-period people (see E11). The web hangs parentless people under the CEO card on the client only (Scheduler_frontend client/components/hr/OrgChart.tsx:58,311-322), so the app must decide how to label an unrecorded top of chain.
- Check: corrected: Status and lands_in stand, but two evidence claims are wrong. 'There is no read for non-HR users' and 'the only other people picker' (priority-task /recipients) are false. GET /api/users (routes/user.js:69) has no role gate and returns the caller's branch logins with HR full_name and designation, plus login phone and email (userController.js:558-575,626-651). It is still not the requested directory: no search, no department filter, no chain or photos, portal accounts only, the caller's own branch only. So MISSING holds.
- Evidence:
  - routes/hr.js:109-116 - /people, /accounts, /org-chart and /employees are all canRead (HR_ROLES only)
  - controllers/hr/employeesController.js:172-237 - the HR list supports q (ilike on full_name, designation and employee_code) plus department_id, branch_id and manager_id filters
  - controllers/hr/orgChartController.js:25-29,63-78 - flat nodes with no code, email, phone or photo; roots = rows with no manager_id; the client builds the tree
  - supabase/migrations/20260826000001_hrms_tables.sql:52-70 - hr_departments is flat: no parent_id and no head column (no ALTER TABLE hr_departments in any migration)
  - supabase/migrations/20260826000001_hrms_tables.sql:82-89 - hr_employees.manager_id adjacency list with department_id and branch_id foreign keys
  - routes/user.js:69 + controllers/userController.js:558-575,626-651 - the one non-HR people read: GET /api/users has auth and no role gate, and lists the portal logins at the caller's own branch with full_name and designation joined from hr_employees.user_id (plus phone_number and email). No name/code search, no department filter, no manager or photo, no punch-only staff, and a 401 for no-branch roles such as hr (571-573)
  - routes/priorityTasks.js:48 - the priority-task /recipients picker is limited to the assign roles

<a id="item-e3"></a>
#### E3: Sensitive change requests (old + new values -> HR approval)

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Nothing for HR-record change requests. A reusable request/approve pattern (inventory_edit_requests) and the validators exist.
- What remains: A new table (employee_id, field, old_value, new_value, reason, attachment, status, reviewer, decided_at). Self create, list and withdraw endpoints behind punchAuth. An HR decide endpoint that applies the change with the same validation as PATCH /employees/:id (phoneConflict; manager changes via hr_move_employee) and records an event with the employee as actor.
- Notes: A phone or email change moves a person's attendance sign-in identity, so approval must re-check uniqueness and should notify both the old and the new contact. Logging into hr_activity_events needs its entity_type CHECK widened and the actor fixed (see extra findings). The HR queue is E5.
- Check: confirmed: I searched routes, controllers, services and migrations for change_request, edit_request, profile_change and amend. Only inventory_edit_requests (HoO corrections, inventoryEditRequestsController.js:7-19) matches. The /api/me email and phone changes write users only (me.js:31-41; profileController.js:115-130 and the request/confirm handlers). Verified: attendanceOtpController.js:115-156 (identifiers), hrPhones.js:88-121, and routes/hr.js:119,122. The HR area also has a second request-then-HR-decides precedent, interview postponements (routes/interviews.js:51-52,70; 20260913000000_hr_interview_postponement.sql). new-self-contained is right, unless the log goes into hr_activity_events: that needs its entity_type CHECK widened (20260926000000_email_custom_variables.sql:136-144).
- Evidence:
  - routes/hr.js:1-504 - no change-request route anywhere in the HR router; a search of routes, controllers and migrations for change_request/profile_change finds nothing for HR records
  - routes/me.js:31-41 + controllers/profileController.js:7-30,115-130 - /api/me email and phone changes edit the users login only (password, then an OTP to the new value), never hr_employees
  - controllers/hr/attendanceOtpController.js:115-156 - the main phone, email and employee code on hr_employees are the sign-in identifiers for attendance-only logins
  - services/hrPhones.js:88-121 - findPhoneOwner / phoneConflict: the one-phone-per-live-employee rule an approval must re-check
  - controllers/inventoryEditRequestsController.js:7-19 - an existing request -> review -> apply pattern that stores the old value, the requested value and what was written (HoO reviews inventory corrections)
  - routes/hr.js:119,122 - HR edits via PATCH /employees/:id (canWrite); the manager changes only via PATCH /employees/:id/manager

<a id="item-e4"></a>
#### E4: Employee documents: upload (camera/PDF), verification status, letters folder, 5-min signed link, strip storage path, masked Aadhaar

- Gap report: UPDATE; hr_documents exists; HR uploads only, no verification, returns storage path
- Now: **UPDATE**; the fix sits in: Scheduler code + team_app
- What exists: HR-only upload, list and delete into the private bucket, with 5-minute signed URLs (that part already meets the task). The letter types (offer, joining, experience, exit) exist as doc_type values. Camera image types and PDF are accepted, judged by the declared MIME type.
- What remains: Self list, upload and delete endpoints (punchAuth, owner forced to the caller, a self-allowed doc_type subset). New columns: uploaded_by_employee_id, review_status (pending/verified/rejected, with HR uploads defaulting to verified), reviewed_by/_name/_at and review_note. Leave storage_path out of self responses and sign on tap rather than on every list. A letters view is a doc_type filter. Masked Aadhaar is impossible today: no Aadhaar number field exists anywhere, only the 'identity' doc_type. Check, then raise, the nginx body limit for phone photos.
- Notes: The web client never reads storage_path (no match in Scheduler_frontend client), so it could also be dropped from the HR list safely. A self-upload by a punch-only caller would record uploaded_by null with the name 'unknown' unless the new uploader column is used.
- Check: confirmed: Verified: the hr_documents columns (hrms_tables.sql:500-518), with no ALTER TABLE hr_documents in any later migration; the private bucket (20260804000006_attachments.sql:38-42); the doc types, limits and 300 s TTL (hrPolicy.js:1251-1289); the HR-only routes and multer error handler (routes/hr.js:77-84,487-490,493-502); the list, which returns storage_path and signs every row (documentsController.js:45-68); the uploader taken from req.user with an 'unknown' fallback (105-106); and the hard delete (136-162). No employee table has an Aadhaar or ID-number field; those fields exist only on student intake. The web never reads storage_path (no match in ro-fe). deploy.yml sets no client_max_body_size (340-350); whether nginx.conf sets one is unverified. 'both' is right: new self endpoints, plus ALTERs to hr_documents, a change to the HR upload's default status, and deploy.yml.
- Evidence:
  - supabase/migrations/20260826000001_hrms_tables.sql:500-518 - hr_documents columns: id, owner_type (employee|candidate), owner_id (no FK), doc_type CHECK (resume, identity, certificate, offer, joining, experience, exit, other), file_name, storage_path UNIQUE, mime_type, size_bytes, note, uploaded_by -> users, uploaded_by_name, created_at. No review, verification or expiry column, and no later ALTER adds one
  - supabase/migrations/20260804000006_attachments.sql:38-42 - bucket 'documents' created private (public=false); size and type limits are left to multer
  - config/hrPolicy.js:1251-1253,1259-1289 - DOCUMENT_TYPES; UPLOAD: 10 MB per file, 10 files, MIME pdf/jpeg/png/webp/heic/heif/msword/x-msword/docx, BUCKET 'documents', SIGNED_URL_TTL_SECONDS 300
  - routes/hr.js:77-84,487-490,493-502 - multer memoryStorage with those limits; GET /documents canRead, POST and DELETE canWrite; 413 FILE_TOO_LARGE / TOO_MANY_FILES, 400 UPLOAD_REJECTED
  - controllers/hr/documentsController.js:45-68 - the list requires owner_type and owner_id, selects storage_path and returns it beside a 300 s signed url, signing every row on each list call
  - controllers/hr/documentsController.js:86-114 - path hr/{owner_type}/{owner_id}/{uuid}_{name}; uploaded_by = req.user?.id, name falls back to 'unknown'
  - controllers/hr/documentsController.js:136-162 - hard delete (row, then blob); a DOCUMENT_DELETED event survives
  - .github/workflows/deploy.yml:340-350 - the nginx /api/ location sets no client_max_body_size

<a id="item-e5"></a>
#### E5: HR review queues (change requests, document verification) inside the web HRMS

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Nothing. The HR alerts bell and the HRMS tab framework are possible places to put it.
- What remains: Queue endpoints (pending change requests, pending documents) with approve/reject and a reason, for HR_WRITE_ROLES. A tab inside the HRMS page (RVM rule: module views stay tabs inside the module). Optionally, a new alert kind or count. Needs the E3 table and the E4 review columns first.
- Decided on 16 Oct: HR Executive may approve documents and profile changes. Where HR reviews them is open: the web HRMS stays unchanged (ADR-0018), so the choice is the app or a small web page served by team_app.
- Notes: Needs the E3 table and the E4 review columns first. The web tab is Scheduler_frontend work (client/lib/hr/tabs.ts and client/pages/HrWorkspace.tsx). Decide whether hr_executive may approve; the brief recommends yes for documents and profile changes.
- Check: corrected: Status and lands_in stand. One evidence line was misdescribed: EmployeeDrawer.tsx contains no 'joining-verification' text. Its only 'verif' matches are the background-verification (BGV) section (853-867) and an 'unverified' pay-amount label (1604). I verified the routes, tabs.ts and the alert kinds.
- Evidence:
  - routes/hr.js:476-490 - the documents routes are resumes, list, upload and delete; no review or decide endpoint exists
  - Scheduler_frontend client/lib/hr/tabs.ts:28-44 - the HRMS tabs are dashboard, organisation, employees, hiring, attendance, activity and settings; there is no review queue
  - controllers/hr/alertsController.js:61-95 - the HR alert kinds (performance_review, bond_ending, bgv_not_started, bgv_result_due, increment_due, exit_details_missing, portal_login_missing, joining_confirmation) include no change-request or document-review kind
  - Scheduler_frontend client/components/hr/EmployeeDrawer.tsx:853-867,1604 - the only 'verif' text is the background-verification (BGV) section and an 'unverified' label on an ambiguous pay amount; there is no document review_status UI

<a id="item-e6"></a>
#### E6: Team today (All / Not in yet / Late / WFH / On leave) and Off this week for anyone with reports

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: Scheduler code + team_app
- What exists: All the raw inputs: punches, day rows with late fields, shifts, week-offs and holidays, plus a branch/day read limited to HR and the Admin Manager. The manager graph is in hr_employees.manager_id. Nothing is scoped to a manager.
- What remains: A new endpoint for any caller with direct or indirect reports, resolved through manager_id over live rows (notice period included) rather than login role. It returns today's buckets (All / Not in yet / Late / On leave, plus WFH if adopted) and Off this week. 'On leave' and 'Off this week' can already use future hr_staff_attendance rows with status 'leave', which HR records ahead through the override, plus projected week-offs and holidays. For teaching staff, approved faculty leave_requests can be bridged through users.faculty_id and hr_employees.user_id. What does not exist is an employee-raised leave request for HR employees, which is a separate module. WFH needs a new status (the hr_staff_attendance CHECK, punch geofence handling and the settle job) or must be dropped. Do not copy activeEmployees' date_of_exit filter.
- Notes: Do not copy activeEmployees' date_of_exit filter, or a manager's notice-period reports vanish. No login carries 'hod', so gate by the org chart. Without WFH this is new-self-contained only. geofence_exempt (20261020000000_hr_attendance_punch.sql:58-59) is a permanent per-person flag for field staff, not a daily WFH.
- Check: corrected: Status and lands_in stand, but the claim 'a future day cannot be marked, so no planned leave exists anywhere' is wrong. Only the daily sheet refuses future days. The HR override accepts future 'leave' (attendanceAdminController.js:46-60), its SQL function has no date check, and the web exposes this as 'Record leave' (AttendanceHistory.tsx:141-161). Faculty also have a planned/emergency leave workflow (leave_requests, /api/am/leave). So On leave and Off this week can show leave that HR recorded ahead, not only days already marked. Confirmed: no WFH, the read has no manager scope and no branch fence, the date_of_exit roster filter, and the shift, week-off and holiday inputs.
- Evidence:
  - routes/hr.js:176-181 - staff-attendance read and mark only for HR_ATTENDANCE_ROLES {hr, admin_manager, ceo, super_admin}
  - controllers/hr/staffAttendanceController.js:60-95 - the read filters on branch_id, employee_id, from and to; no manager_id scope and no branch fence on read (branchFence at 201-209 is used only by remarks 232-236 and mark 292-302)
  - controllers/hr/staffAttendanceController.js:32-40,154 - the roster ('people') drops anyone with any date_of_exit, so notice-period staff disappear
  - supabase/migrations/20261015000004_hr_staff_attendance.sql:18-20 - statuses present, absent, half_day, leave, week_off, holiday; no WFH
  - controllers/hr/staffAttendanceController.js:258-261 - the daily sheet refuses a future day
  - routes/hr.js:207 + controllers/hr/attendanceAdminController.js:46-60 - but the HR override (hr, ceo, super_admin) accepts a FUTURE day for status 'leave' ('Leave can be recorded AHEAD -- a planned CL'); the SQL writer has no date check (supabase/migrations/20261020000000_hr_attendance_punch.sql:290-341)
  - Scheduler_frontend client/components/hr/attendance/AttendanceHistory.tsx:18,141-161 - the web offers 'Record leave' on future days
  - supabase/migrations/20260804000003_admin_manager_ops.sql:78-109 + routes/amOps.js:80-84 + controllers/leaveController.js:10-22 - faculty leave_requests (planned/emergency, start/end dates, pending/am_approved/approved), keyed on faculty_id and location_id, admin-level only; approval also writes faculty.leave_\*
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:57-73,80-83,91-103 - shifts with grace minutes, per-employee week_off_days, per-branch holidays: the inputs for 'Not in yet', 'Late' and 'Off this week'
  - Scheduler_frontend client/components/hr/attendance/LiveAttendance.tsx:57,76 - the web Live view's buckets are computed in the browser from GET /staff-attendance people

<a id="item-e7"></a>
#### E7: Digital ID card (photo, name, code, designation, branch, blood group, emergency contact)

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Name, code, designation, branch and the HR photo exist, but no endpoint shows them to the employee.
- What remains: A self ID-card endpoint (or a block in /me/profile) with a signed photo (E10), plus the E9 columns (blood_group, emergency contact). Optionally a QR/verify link.
- Notes: Blocked on E9 and E10. The code on the card doubles as a sign-in identifier; that is low risk on its own because a password or OTP is still needed.
- Check: confirmed: hr_employees has no blood group or emergency contact (hrms_tables.sql:82-131), and no migration adds one. Verified: photo_path is a private path (20260830000001_hr_employee_photo.sql:25-31), hr_branches.name (hrms_tables.sql:39-48), and attendanceOtpController.js:115-124, which confirms the code is the ID-card identifier and also a sign-in key. No ID-card endpoint exists anywhere. For the optional QR, a qrcode dependency is already installed (package.json:34) and used for certificate verification (studentCertificatesController.js:2).
- Evidence:
  - supabase/migrations/20260826000001_hrms_tables.sql:82-131 - hr_employees has full_name, employee_code, designation and branch_id; no blood group or emergency contact
  - supabase/migrations/20260830000001_hr_employee_photo.sql:25-31 - photo_path in the private bucket, served only as signed URLs
  - supabase/migrations/20260826000001_hrms_tables.sql:39-48 - hr_branches.name for the branch line
  - controllers/hr/attendanceOtpController.js:115-124 - the employee code is described as what a person reads off their ID card, and it is also an attendance sign-in identifier

<a id="item-e8"></a>
#### E8: Colleague contact visibility rule (email/phone)

- Gap report: MISSING/DECISION
- Now: **MISSING**; the fix sits in: Scheduler code + team_app
- What exists: Contact data exists, visible to HR only.
- What remains: An RVM decision first (for example: email visible to colleagues; phone only to self, the manager chain and HR). Then one server-side policy constant, applied in the E2, E6 and E7 responses. The decision must also cover two existing routes that already show contacts beyond HR: GET /api/users (login phone and email to every signed-in token at the branch, students included) and GET /api/faculty (faculty email, phone and leave reason). Either role-gate them or drop the contact fields for non-admin callers; otherwise any portal or student token can bypass the app's rule.
- Decided on 16 Oct: Work email is visible to every colleague; a phone number only to that person's manager chain and HR.
- Notes: A decision is needed before any code. Showing a phone or email reveals a person's sign-in identifier; sign-in still needs a password or OTP.
- Check: corrected: Status stands, because no colleague-visibility policy exists. But 'Contact data exists, visible to HR only' is true only of the HR-record contacts. Login phone and email already reach every signed-in token at a branch through GET /api/users, whose only guard is auth, and student tokens pass auth with a location. GET /api/faculty exposes faculty email and phone the same way. Whatever rule RVM picks must decide whether these existing routes follow it, so the work is both new code and a change to existing routes.
- Evidence:
  - supabase/migrations/20260826000001_hrms_tables.sql:91-92 - email and phone on hr_employees
  - supabase/migrations/20260916000000_hr_employee_additional_phones.sql:40-48 - additional_phones added
  - controllers/hr/employeesController.js:72-84 + routes/hr.js:116-118 - the HR-record contacts (email, phone, additional_phones) are served only to HR_ROLES through canRead
  - routes/user.js:69 + controllers/userController.js:558-575,641-651 - GET /api/users has auth only: any signed-in token with a branch (student and faculty tokens included, middleware/auth.js:19-42) receives every login at that branch with phone_number and email, plus full_name and designation from the linked hr_employees row
  - routes/faculty.js:18 + controllers/facultyController.js:42-60 - GET /api/faculty has auth only and returns faculty email, phone_number and leave dates/reason for the caller's branch
  - config/auditPolicy.js:84-85 + controllers/profileController.js:23-26 - users.phone_number and users.email are portal login identifiers and the destination for one-time codes
  - controllers/hr/attendanceOtpController.js:128-156 - the hr_employees main phone, email and employee code are the attendance-only sign-in identifiers
  - config/hrPolicy.js:25-41 - the only access sets are role sets; there is no colleague-visibility policy constant

<a id="item-e9"></a>
#### E9: hr_employees columns date_of_birth, blood_group, address, emergency_contact

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: Scheduler code
- What exists: None of the four columns exists.
- What remains: A migration adding date_of_birth (date), blood_group (CHECK list), current and permanent address, and emergency contact name, relation and phone. Add them to WRITABLE and SELECT (or a separate personal read), add the HR drawer fields, decide readers (self plus HR) and keep them out of colleague views. Consider excluding them from AUDITED or redacting them.
- Decided on 16 Oct: Personal details go in an ESS table keyed to hr_employees.id, because hr_employees must not be altered (ADR-0018, ADR-0021).
- Notes: Apply the migration before deploying any code that selects the columns, because the backend deploys first and migrations are applied by hand afterwards. Add blood_group and emergency fields to WITHHOLD_VALUE_KEYS if they should be withheld. F6 birthdays depend on date_of_birth.
- Check: confirmed: No migration gives hr_employees a date_of_birth, blood group, address or emergency column; the only date_of_birth is admission_intakes (20260514000000_schema_gaps.sql:78). The SELECT has no 42703 fallback (employeesController.js:62-71), AUDITED is every WRITABLE key (163-166), and the deploy workflow lints migrations but never applies them (deploy.yml:36-38). One refinement to the notes. WITHHOLD_VALUE_KEYS (auditPolicy.js:89-94) masks values only when an event is written to audit_events (applyFieldPolicy, 347-365). HR edits go to hr_activity_events, and the CEO audit view shows those before/after values verbatim (controllers/ceo/auditReadController.js:124-147,186). Adding the new names to WITHHOLD_VALUE_KEYS would therefore not protect them; they must be kept out of AUDITED, or redacted in fromHrEvent.
- Evidence:
  - supabase/migrations/20260826000001_hrms_tables.sql:82-131 - the base columns; none of the four
  - supabase/migrations (every ALTER TABLE public.hr_employees: photo, bond, increment_date, bgv, role_id, user_id, referral, additional_phones, lifecycle, phone_digits, bgv_started_on, geofence_exempt, shift/week_off) - none adds them; the only date_of_birth in the schema is admission_intakes at 20260514000000_schema_gaps.sql:78
  - config/auditPolicy.js:89-94 - the CEO audit trail already withholds the values of date_of_birth, permanent_address, current_address, aadhaar and others; blood_group and emergency contact are not listed
  - controllers/hr/employeesController.js:62-71,72-84 - the SELECT deliberately has no 42703 fallback, so adding columns there before the migration is applied breaks every employee read
  - controllers/hr/employeesController.js:163-166 - AUDITED = every WRITABLE key, so new PII fields would be copied into hr_activity_events before/after

<a id="item-e10"></a>
#### E10: Expose the employee photo to self/team views

- Gap report: UPDATE; photo storage exists (a 20260830 migration)
- Now: **UPDATE**; the fix sits in: team_app
- What exists: Two photo stores in the same private bucket. The HR photo is readable only by HR roles (Employees list); the self photo only by its owner. Colleagues see neither, and punch-only staff can set neither.
- What remains: Pick the canonical photo (HR record or users). Sign it in the new self, team, directory and ID-card responses by reusing signPhotos. Optionally add a self-upload path for punch-only staff, with HR approval if wanted.
- Notes: Signed URLs last 300 s, so fetch them at render time and never cache them. Merging the two stores would touch /api/me/photo (existing code).
- Check: confirmed: Verified: the photo columns (20260830000001:25-31); the HR upload (routes/hr.js:166-167; employeesController.js:1617-1674, images only); batch signing on the list (251, 310-330), with the org chart not using it; GET /employees/:id returning photo_path without a photo_url (510-606); and the separate users.photo_path, served only by GET /api/me (me.js:14-29; profileController.js:43-62,80-104). Neither photo reaches colleagues, and GET /api/users does not select photo_path. UPDATE and new-self-contained are right if the HR photo is made canonical.
- Evidence:
  - supabase/migrations/20260830000001_hr_employee_photo.sql:25-31 - hr_employees.photo_path / photo_updated_at / photo_updated_by: a path in the private 'documents' bucket, never a URL
  - routes/hr.js:166-167 + controllers/hr/employeesController.js:1617-1674 - HR (HR_WRITE_ROLES) uploads to hr/employee/{id}/photo/{uuid}_{name}; image/\* only, through the 10 MB HR multer
  - controllers/hr/employeesController.js:251,296-330 - the Employees list signs photos in one batch (300 s); signPhotos is exported, but the org chart does not use it
  - controllers/hr/employeesController.js:510-606 - GET /employees/:id returns photo_path with no signed photo_url
  - controllers/hr/orgChartController.js:25-29 - the org-chart SELECT has no photo
  - routes/me.js:14-29 + controllers/profileController.js:43-62,80-104 - a separate self photo on users.photo_path (users/{id}/photo/, 5 MB, JPEG/PNG/WebP/HEIC), readable only by its owner through GET /api/me

<a id="item-e11"></a>
#### E11: Keep notice-period people on the chain with a 'Notice period' chip (the web org chart drops them)

- Gap report: UPDATE
- Now: **UPDATE**; the fix sits in: Scheduler code + team_app
- What exists: How the chart treats each status today:
- active: shown
- notice_period: hidden, though the person is still live and punching
- fired / terminated: archived immediately, so hidden
- exited: hidden
- legacy resigned / probation / confirmed: shown unless a date_of_exit is set

No node shows a status chip.
- What remains: App chain endpoint: filter on is_archived only and return on_notice plus the last working day for the chip. Web: change hasLeft to archived/exited (or date_of_exit &lt; today) and draw the chip. Apply the same fix to the staff-attendance roster.
- Notes: Changing hasLeft also changes 'my manager' for their reports. The dashboard and alerts share the rule (controllers/hr/dashboardController.js:122; controllers/hr/alertsController.js:254-256).
- Check: confirmed: hasLeft is 'exited' OR any date_of_exit (orgChartController.js:42), applied after is_archived=false (59-68), and the reports of a leaver become manager_left orphans (99-104). hr_set_employment_status sets date_of_exit to the last working day and keeps is_archived false when that day is in the future. It archives fired and terminated at once, and clears date_of_exit on active (20261015000005_hr_dismissal_letter.sql:73-108,179-189). Also verified: the status vocabulary and labels (hrPolicy.js:663-673,710-719), the web banner (OrgChart.tsx:61-64 and about 310-320) and the same rule in the attendance roster (staffAttendanceController.js:32-40). 'both' is right: a new app endpoint, plus edits to hasLeft and to the roster filter.
- Evidence:
  - controllers/hr/orgChartController.js:42 - hasLeft = employment_status 'exited' OR any date_of_exit
  - controllers/hr/orgChartController.js:59-68 - default view: is_archived=false, then hasLeft rows are dropped; include_archived=true returns everyone, archived included
  - controllers/hr/orgChartController.js:99-104 - their reports become orphans with reason 'manager_left'
  - supabase/migrations/20261015000005_hr_dismissal_letter.sql:73-86,179-189 - notice_period sets date_of_exit = LWD and keeps is_archived false (it archives at once only if the LWD has passed); fired and terminated archive immediately; active clears date_of_exit
  - config/hrPolicy.js:663-673,710-719 - statuses: active, notice_period, fired, terminated (selectable), exited (system), probation/confirmed/resigned (legacy, carried by no row); labels include 'Notice period'
  - Scheduler_frontend client/components/hr/OrgChart.tsx:61-64,311-322 - the web tells HR that the reports of someone on notice have a manager who 'has left the company'
  - controllers/hr/staffAttendanceController.js:32-40 - the same any-date_of_exit rule drops them from HR's daily-sheet and Live roster

<a id="item-e12"></a>
#### E12: Timeline from HR events (joining, confirmation, changes, increments as dates only)

- Gap report: UPDATE; hr_activity_events read
- Now: **UPDATE**; the fix sits in: team_app
- What exists: The raw HR trail (HR-only) and the dates a timeline needs: date_of_joining, the promotion, manager, code and status events, and revision dates.
- What remains: A curated self timeline endpoint showing joining (date_of_joining), promotions and designation changes, manager changes, increments as dates only (effective_from / increment_date, with no amounts and no increment_percent), and notice or exit. It must leave out remarks, document notes, actor names and COMPENSATION_VIEWED. 'Confirmation' needs an RVM decision, because no field or event exists for it.
- Notes: It has to query two entities (employee and compensation). Migrated history carries no dates, so early timelines will be sparse.
- Check: confirmed: Verified. forEntity is HR_ROLES-only and returns up to 500 raw events with before/after (activityController.js:357-375), and redaction strips pay keys only (hrRedaction.js:62-100). The SQL functions file the promotion, manager-change and code events against 'employee' (20260905000000:172; 20260826000002:76; 20260904000000:277). COMPENSATION_RECORDED is filed under 'compensation' with effective_from and increment_percent in its metadata (compensationController.js:289-300). The NULL effective_from on migrated rows is stated in a code comment (771-773). No probation-confirmation event or field exists ('confirmed' is a legacy status, hrPolicy.js:668-669). CANDIDATE_JOINING_CONFIRMED (hrPolicy.js:445-450) does exist on the candidate record, reachable through hr_employees.source_candidate_id, and could date the joining entry.
- Evidence:
  - routes/hr.js:466-474 + controllers/hr/activityController.js:357-375 - GET /api/hr/activity/:entityType/:entityId (canRead, HR_ROLES only) returns up to 500 raw events with before/after
  - services/hrRedaction.js:62-100 - only pay keys are stripped, and only for readers outside HR_COMP_ROLES; notes, actor names and remark events are not curated
  - supabase/migrations/20260826000001_hrms_tables.sql:463-481 - hr_activity_events columns (event_type, entity_type, entity_id, actor_\*, before, after, changed_keys, metadata, note, occurred_at)
  - config/hrPolicy.js:383-439 - event types include EMPLOYEE_CREATED, EMPLOYEE_STATUS_CHANGED, EMPLOYEE_MANAGER_CHANGED, EMPLOYEE_CODE_ISSUED/ASSIGNED, EMPLOYEE_PROMOTED and COMPENSATION_RECORDED; there is no confirmation event
  - supabase/migrations/20260905000000_hr_promotion_on_revision.sql:172; 20260826000002_hrms_rpcs.sql:76; 20260904000000_hr_employee_codes.sql:277 - the promotion, manager-change and code events are written by SQL functions against entity 'employee'
  - controllers/hr/compensationController.js:289-300 - COMPENSATION_RECORDED is filed under entity 'compensation' with id = employee id; its metadata carries effective_from and increment_percent
  - supabase/migrations/20260826000001_hrms_tables.sql:214-227 + controllers/hr/compensationController.js:771-773 - revisions carry effective_from and increment_date, but effective_from is NULL on all 113 migrated rows
  - config/hrPolicy.js:668-669 - 'confirmed' is a legacy status that no row carries

### F. Wall (evidence)

<a id="item-f1"></a>
#### F1: Wall posts (text, &lt;=5 photos/PDFs, @mentions, wall choice), edit 15 min, delete

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Nothing beyond the upload and storage patterns.
- What remains: New tables (posts, up to 5 attachments, mentions, wall/channel) and endpoints (create, edit within 15 minutes, delete), keyed on hr_employees.id so attendance-only staff can take part. Media handling per F9.
- Notes: Depends on F8 (who may post) and F9 (media). Push for @mentions needs new FCM infrastructure; none exists.
- Check: confirmed: server.js:7-52,127-201 imports and mounts no wall, feed or post router. Searching routes, controllers, services, lib and every migration finds no wall, post, praise, poll, reaction or mention table or code. express.json() uses its default limit (server.js:103), and package.json:20-37 has no push or image-processing library.
- Evidence:
  - server.js:7-52,127-201 - no wall, feed or post router is imported or mounted
  - (search) routes, controllers, services and supabase/migrations contain no wall, feed, praise, poll, reaction or mention code or table
  - package.json:20-37 - no push or image-processing dependency
  - server.js:103 - express.json() with the default 100 kb body limit, so attachments must be multipart
  - routes/hr.js:77-84 and routes/attachments.js:14-21 - existing multer and private-bucket patterns to copy

<a id="item-f2"></a>
#### F2: Six reactions + comments (one level of replies) + reactions on comments + who reacted

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Nothing for this. The thread and receipt patterns key on users, so they exclude punch-only staff.
- What remains: Tables for reactions (6 types, unique per person per target, posts and comments), comments with parent_id (one level), and a who-reacted list endpoint, all keyed on hr_employees.id.
- Notes: Ships with F1.
- Check: confirmed: There is no reaction or comment model for staff content. The existing threads (priority_task_remarks at 20260929000000:72-83, ticket_chats, hr_employee_remarks) and read receipts (priority_task_reads at 20260814000001:62-68) key on users or on a parent record, never on hr_employees.id.
- Evidence:
  - (search) no reaction or comment tables or routes for staff content
  - supabase/migrations/20260929000000_priority_task_threads.sql:72-83 - the only thread pattern (priority_task_remarks), keyed on users(id)
  - supabase/migrations/20260814000001_reporting_discipline_and_priority_tasks.sql:62-68 - per-user read receipts (priority_task_reads), also keyed on users(id)

<a id="item-f3"></a>
#### F3: Praise with RVM badges (8-12, HR-editable), reason &lt;=280, optional photo + certificate PDF

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Nothing for praise. A PDF generator exists.
- What remains: A badges table (8-12 rows, HR CRUD), praise posts (giver, receiver(s), badge, reason &lt;=280, optional photo), and a certificate PDF, either generated with pdfkit or uploaded.
- Notes: Uses the F1 post model and F9 media.
- Check: confirmed: No badge or praise table or route exists. HR-editable lookups cover only branches and departments (lookupsController.js:43-62). A pdfkit certificate renderer exists (utils/certificatePdf.js:31,60; package.json:32), used by studentCertificatesController.
- Evidence:
  - (search) no badge or praise table or route
  - controllers/hr/lookupsController.js:43-62 - HR-editable lookups exist only for branches and departments (a pattern to copy)
  - utils/certificatePdf.js + package.json:32 - a pdfkit certificate generator (used for student certificates) that could render a praise certificate

<a id="item-f4"></a>
#### F4: Polls (>=2 options, single/multi, anonymous, closing date, options locked after the first vote)

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Nothing.
- What remains: Tables for polls, options and votes (single or multi choice, an anonymous flag, closes_at), with a guard or trigger that locks options after the first vote, and results that hide voters when the poll is anonymous.
- Check: confirmed: Searched routes, controllers, services and migrations for poll, option and vote: no poll model exists anywhere.
- Evidence:
  - (search) no poll, option or vote tables or routes in routes, controllers or supabase/migrations

<a id="item-f5"></a>
#### F5: Staff announcements: audience, schedule, closing date, push + email, read/ack counts, pin &lt;=3

- Gap report: UPDATE; the existing announcements table is student/batch scope only (title, message, scope, batch_id)
- Now: **MISSING**; the fix sits in: team_app
- What exists: A student/batch notice feed consumed by the web (admin roles), flutterapps staff_app and the student portal. It has no author, audience, schedule, expiry, pin, or read/ack tracking. Email infrastructure exists; push does not.
- What remains: New staff-announcement tables: audience rules by branch, department, ladder or portal role, and named people; author; publish_at and closes_at; pinned (at most 3); reads and acks keyed on hr_employees.id. Endpoints, a scheduling cron, email fan-out (utils/mailer or the email queue) and push (new FCM infrastructure). Keep all of it off /api/announcements and the announcements table.
- Notes: The report's UPDATE framing is misleading. Reusing the table would show staff notices to students on the student portal (same location filter), the scope CHECK refuses new values, and staff_app would render them as 'unknown'. Separately, the existing route needs a role gate (change-existing; see extra findings). For 'role' audiences, decide between the ladder role (hr_roles) and the portal role (users.role via user_id).
- Check: confirmed: Verified the announcements table: title, message, scope ('all','batch') and batch_id (remote_schema.sql:612-622), plus location_id (20260514000000:33-34; 20260530000003:103). The routes check auth only (announcements.js:12-14). GET is filtered by location, POST is open to any caller with a location, and DELETE removes any id (announcementController.js:4-84). Consumers verified: the web (Announcements.tsx:111-122,161,195; App.tsx:497-506), staff_app (announcements_remote_data_source.dart:16-30; parsers.dart:167-179 maps unknown scopes to 'unknown'), and the student portal (api.ts:52-62). MISSING is the better label than UPDATE, because reusing the table would show staff notices to students in the same branch and the scope CHECK refuses new values. Email audience filters already exist (services/email/recipients.js:56-67). The priority-task bell, with read receipts and branch broadcast (priorityTasksController.js:8-23,62-69), is a further pattern, but it is a task workflow keyed on users.id.
- Evidence:
  - supabase/migrations/20251215134244_remote_schema.sql:615-624 - announcements: id, title NOT NULL, message NOT NULL, scope NOT NULL CHECK ('all','batch'), batch_id, created_at, and a scope_batch_consistency CHECK
  - supabase/migrations/20260514000000_schema_gaps.sql:33-34 + 20260530000003_missing_fkeys.sql:103 - location_id integer, FK to locations. No author, audience, expiry, pin or read columns
  - routes/announcements.js:12-14 + middleware/auth.js:19-42 - GET, POST and DELETE behind auth only, and auth admits student tokens with req.locationId set
  - controllers/announcementController.js:4-32 - GET is filtered to the caller's location; no-location roles (hr, hr_executive) get 401
  - controllers/announcementController.js:34-69,71-84 - POST lets any caller with a location (student, faculty) insert for their branch; DELETE lets any caller remove any id, with no role or branch check
  - Scheduler_frontend client/pages/Announcements.tsx:111-122,161,195 + client/App.tsx:497-506 + client/components/Layout.tsx:229 - the web page (ADMIN_LEVEL in the UI only) does GET, POST and DELETE
  - flutterapps packages/data/lib/src/datasources/announcements_remote_data_source.dart:16-30 + packages/data/lib/src/parsers.dart:167-179 - staff_app does GET, POST and DELETE; any scope other than all/batch parses to 'unknown'
  - flutterapps apps/student_app/lib/injection.dart:92-101 - student_app's home reads JobPortal announcements; its Scheduler data source (packages/data/lib/src/datasources/scheduler_remote_data_source.dart:13-14) is dormant
  - RVM_STUDENT_PORTAL client/services/api.ts:13-14,52-62,230-240 - the student portal GETs /api/announcements with a student token and expects {id, title, message, created_at, scope, batch_id, batch{name}}
  - .github/workflows/deploy.yml:470-476 - student.rvmcad.org proxies /api/ to the same backend
  - package.json:20-37 - no FCM or web-push library
  - services/email/recipients.js:56-67 + utils/mailer.js - email fan-out and audience filters (department_ids, branch_ids, role_ids, designations, employment_statuses, manager_id) already exist

<a id="item-f6"></a>
#### F6: Celebrations (birthdays day+month only, anniversaries, new joiners &lt;=15 days, one-tap wish, hide own birthday)

- Gap report: MISSING (needs DOB)
- Now: **MISSING**; the fix sits in: team_app
- What exists: Joining dates (possibly sparse) and an HR-only new-joiner filter. No DOB, no celebrations endpoint, no wish mechanism.
- What remains: The DOB column (E9) and a self 'hide my birthday' preference. A celebrations endpoint: birthdays by day and month only, anniversaries from date_of_joining, joiners within 15 days, live people only. A one-tap wish built on the F1/F2 models.
- Notes: Blocked on E9 and on HR backfilling date_of_joining. Filter on is_archived, as in E11.
- Check: confirmed: There is no date of birth (see E9). date_of_joining is nullable and was left unset at migration (hrms_tables.sql:94-97; dashboardController.js:119-129), and the joined_within_days filter is HR-only (employeesController.js:196-199,230). No celebration or wish code exists in the backend or the web.
- Evidence:
  - supabase/migrations/20260826000001_hrms_tables.sql:82-131 - no date_of_birth on hr_employees (see E9)
  - supabase/migrations/20260826000001_hrms_tables.sql:94-97 - date_of_joining is nullable and was left NULL at migration ('HR fills them in over time')
  - controllers/hr/dashboardController.js:119-126 - new joiners are computed from date_of_joining, with a note that migrated rows had none
  - controllers/hr/employeesController.js:196-199,230 - a joined_within_days filter exists, HR-only

<a id="item-f7"></a>
#### F7: Moderation: report post/comment -> HR queue; hide/delete with reason; logged

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Audit infrastructure only.
- What remains: Report table, HR queue endpoints, hide/delete with a reason, and logging of each action.
- Notes: Ships with F1 and F2. Decide whether hr_executive moderates.
- Check: confirmed: No report or moderation table or route exists. recordAudit writes audit_events (services/audit.js:270-313) but accepts only registered action names (P.assertKnownAction at 271), so moderation actions need entries in config/auditPolicy.js or their own log table. Logging in hr_activity_events would need its CHECK widened (20260926000000:136-144).
- Evidence:
  - (search) no report or moderation tables or routes
  - services/audit.js:270-313 - recordAudit writes the platform audit_events trail, which moderation actions could use
  - supabase/migrations/20260926000000_email_custom_variables.sql:140-144 - hr_activity_events' entity_type CHECK would need widening if moderation logged there

<a id="item-f8"></a>
#### F8: Wall settings: who may post what

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Nothing.
- What remains: A settings table, or policy plus an HR UI: which walls exist, who may post, who may announce or praise, and whether attachments are allowed.
- Decided on 16 Oct: Everyone may post, comment, react, praise and run polls; announcements only by HR, the CEO and super admins.
- Check: confirmed: No wall settings table or route exists. Access policy throughout the codebase is code constants (hrPolicy.js:25-41).
- Evidence:
  - (search) no wall settings table or route
  - config/hrPolicy.js:25-41 - access policy in this codebase is code constants, not HR-editable settings

<a id="item-f9"></a>
#### F9: Compress photos &lt; 1 MB and store on the server

- Gap report: MISSING; needs the nginx upload limit raised
- Now: **MISSING**; the fix sits in: Scheduler code + team_app
- What exists: Uploads go through backend multer (in memory) into Supabase Storage. There is no compression, no wall-media store and no local-disk storage.
- What remains: Client-side compression in Flutter to under 1 MB. A new wall-media upload endpoint (one file per request, or a raised limit) with a decision between signed and public delivery. Raise client_max_body_size in deploy.yml itself, because a manual edit on the VPS is overwritten by the next deploy.
- Notes: client_max_body_size caps the whole request body, so five photos under 1 MB each in one multipart request still exceed a 1 MB limit. Server-side recompression would need a new dependency such as sharp. Feed images in the private bucket need batch signing (createSignedUrls, as in signPhotos).
- Check: confirmed: There is no sharp or jimp (package.json:20-37). All eight multer instances use memoryStorage (routes/attachments.js:14-21, hr.js:77-84, intake.js:28-32, inventoryRequests.js:55-60, me.js:14-21; controllers/accountsController.js:11-15, admissionUndertakingController.js:5-8, intakeController.js:12-16). Buckets verified: documents (private), identification (public, getPublicUrl) and certificates (60 s TTL); no code uses the legacy resumes bucket policies. deploy.yml rewrites the vhost on every run with no client_max_body_size. Caveat: intakeController.js:12-16 allows 15 MB 'for high-res IDs', so nginx.conf may already accept bodies over 1 MB in production. Confirm with nginx -T before sizing the change.
- Evidence:
  - package.json:20-37 - no image-processing library (no sharp or jimp)
  - supabase/migrations/20260804000006_attachments.sql:38-42 - private 'documents' bucket, shared by HR documents and photos, users photos, bills and inventory quotations
  - controllers/intakeController.js:338 + controllers/accountsController.js:347 - public 'identification' bucket (student intake, getPublicUrl)
  - controllers/studentCertificatesController.js:14-15 - 'certificates' bucket (env CERTIFICATE_BUCKET), 60 s signed URLs
  - supabase/migrations/20251215134244_remote_schema.sql:2387-2423 - storage policies for a legacy 'resumes' bucket that no code uses
  - routes/hr.js:77-84 - 10 MB x 10 files, HR MIME list
  - routes/me.js:14-21 - 5 MB x 1 file, images only
  - routes/attachments.js:14-21 - 10 MB x 10 files, PDF and images
  - routes/intake.js:28-32 - 10 MB x 10 files
  - routes/inventoryRequests.js:55-60 + config/inventoryRequestPolicy.js:248-249 - 10 MB x 10 files
  - controllers/intakeController.js:12-16, controllers/admissionUndertakingController.js:5-8, controllers/accountsController.js:11-15 - 15 MB / 15 MB / 10 MB. Every multer instance in the codebase uses memoryStorage
  - .github/workflows/deploy.yml:322-350 - the deploy rewrites the nginx vhost on every run, and the /api/ block has no client_max_body_size (nginx's 1 MB default applies unless nginx.conf sets one)

### G. Helpdesk (evidence)

<a id="item-g1"></a>
#### G1: Helpdesk categories (HR-editable) with routing target, priority and SLA

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Nothing.
- What remains: A categories table (name, routing target such as a role, person or department head, default priority, SLA hours, confidential flag, infra audit_type mapping) with HR CRUD.
- Notes: Routing to the HoO must bridge hr_branches to Scheduler locations by name (see extra findings).
- Check: confirmed: No helpdesk router is mounted (server.js:127-201). Student-ticket categories are distinct free-text values (ticketManagementController.js:357-370). HR lookups cover only branches and departments, and the infra audit_type is a fixed A-D CHECK (20260804000003:118-120).
- Evidence:
  - server.js:127-201 - no helpdesk router is mounted
  - controllers/ticketManagementController.js:357-370 - student-ticket 'categories' are just the distinct free-text values already on rows; there is no category table
  - controllers/hr/lookupsController.js:43-62 - HR-editable lookups cover only branches and departments
  - supabase/migrations/20260804000003_admin_manager_ops.sql:118-120 - infra audit_type is a fixed A-D CHECK

<a id="item-g2"></a>
#### G2: Tickets + thread + lifecycle (Open / In progress / On hold / Resolved / Closed), reopen &lt;=7 d, rating 1-5, withdraw, HD-0001

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Student-support tickets only (student to admin). Nothing for employees.
- What remains: New tables (for example hd_tickets with a serial rendered HD-0001, hd_ticket_messages, hd_ticket_events) with a 5-state lifecycle, reopen within 7 days, a 1-5 rating and withdraw, under a new mount keyed on hr_employees.id.
- Notes: Avoid the table names tickets and ticket_chats, the enum types ticket_status and ticket_priority, and the /api/tickets path. student_app's support tickets live on the JobPortal (flutterapps packages/data/lib/src/datasources/support_remote_data_source.dart:22-25), not on this backend.
- Check: confirmed: Verified: the enums and the tickets and ticket_chats tables (remote_schema.sql:73-90,1080-1092,1796-1802; 20260514000000:29-31,108-115); the /api/tickets routes and the 5c82086 access rules (ticketManagementController.js:18-37,43-55,280-282,307-311,325-341); and the IR-0001 numbering pattern (inventoryRequestsController.js:43; 20260923000000:56). Add two names to the avoid list: the legacy /api/chat/:ticketId router (server.js:142; chatRoutes.js:12-17) and its 'messages' table (remote_schema.sql:979-987). That route checks auth only, with no ticket-access check (chatController.js:10-114), so any token can read or post to any ticket's legacy thread. A staff post also moves an Open ticket to In Progress (send_admin_reply_and_update_status, remote_schema.sql:443-446). No client calls it.
- Evidence:
  - supabase/migrations/20251215134244_remote_schema.sql:73-90 - enum types ticket_priority (Low, Medium, High) and ticket_status (Open, In Progress, Resolved)
  - supabase/migrations/20251215134244_remote_schema.sql:1080-1092,1796-1802 - tickets: id, title, description, status, priority, category text, student_id -> students, assignee_id -> users, created_at, updated_at
  - supabase/migrations/20260514000000_schema_gaps.sql:29-31,108-115 - tickets.location_id and resolved_at; ticket_chats (ticket_id, message, sender_user_id, sender_student_id, created_at)
  - server.js:141 + routes/ticketManagementRoutes.js:19-55 - /api/tickets: list, create, categories, admins, get, patch, delete, reopen, chat
  - controllers/ticketManagementController.js:18-37,43-55 - a student sees their own tickets; admin-level staff see their branch; everyone else gets 403; create requires student_id
  - controllers/ticketManagementController.js:280-282,307-311,325-341 - reopen is admin-only with no time window; delete is super_admin only; assignees are role 'admin' only
  - Scheduler_frontend client/lib/services/api.ts (7 /api/tickets calls) + client/components/Layout.tsx:282; flutterapps packages/data/lib/src/datasources/tickets_remote_data_source.dart:12-83; RVM_STUDENT_PORTAL client/services/api.ts:248-320 - three live consumers
  - controllers/inventoryRequestsController.js:43 + supabase/migrations/20260923000000_inventory_requests.sql:56 - the serial + padStart(4) pattern behind IR-0001, reusable for HD-0001

<a id="item-g3"></a>
#### G3: Response-time targets in working hours per branch, 'Overdue by 3h', escalation (category head -> HoO -> CEO)

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Day-count escalation flags and a per-branch holiday list. No business-hours SLA.
- What remains: A per-branch working-hours calendar (reusing hr_holidays), a business-hours SLA calculator, overdue labels, and an escalation cron (category head -> HoO -> CEO) with notifications.
- Notes: Registering the cron is a one-line addition to scheduledJobs.js. The HoO sits on Scheduler locations while employees sit on hr_branches (see extra findings).
- Check: confirmed: Infra escalation sets escalated and escalated_at and only writes to the console (scheduledJobs.js:342-367; cron at 735-738). Alert escalation is flag-only too (297-334). No table holds branch working hours: shifts are assigned per employee and holidays per branch (20261022000000:57-73,91-103).
- Evidence:
  - scheduledJobs.js:342-367,734-738 - the only ticket escalation is a day-count flag (infra open more than 7 days, 08:30 IST), with no notification
  - scheduledJobs.js:293-334 - alert escalation is also flag-only
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:57-73,91-103 - shifts are per employee and holidays per branch; no table holds branch working hours
  - config/roles.js:4-22,79-89 - hoo (branch-scoped through users.location_id) and ceo are portal roles

<a id="item-g4"></a>
#### G4: Confidential categories and optional anonymity

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Nothing.
- What remains: A confidential flag on categories that limits visibility to named handlers, optional anonymity (the raiser hidden from agents but kept for audit) and logging that respects it.
- Check: confirmed: No confidential or anonymous flag exists anywhere. Every admin-level user sees all of a branch's tickets (ticketManagementController.js:134-146), and HR events always carry the actor's name and role (hrms_tables.sql:472-474).
- Evidence:
  - (search) no confidentiality or anonymity flags anywhere
  - controllers/ticketManagementController.js:136-146 - the existing ticket model shows every branch ticket to any admin-level user, the opposite of what confidential needs
  - supabase/migrations/20260826000001_hrms_tables.sql:472-474 - HR event rows always store the actor id, name and role

<a id="item-g5"></a>
#### G5: Agent workspace (phone + web queue, filters, bulk close, saved replies, reports)

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Patterns only, in the student-ticket controller.
- What remains: Agent queue endpoints with filters, bulk close, saved replies (table plus CRUD) and report aggregates, plus phone and web screens.
- Notes: Includes client work in the app and the web.
- Check: confirmed: The student-ticket list, filters and counts (ticketManagementController.js:102-203) and the auto-assign on first reply (410-428) are patterns only. No saved replies, bulk actions or ticket reports exist.
- Evidence:
  - controllers/ticketManagementController.js:102-203 - the student-ticket list (filters, counts, pagination) is a pattern to copy
  - controllers/ticketManagementController.js:410-428 - auto-assign on first reply is also a pattern
  - (search) no saved replies, bulk actions or ticket reports

<a id="item-g6"></a>
#### G6: Mirror lab/facility tickets into infra_tickets so the Admin Manager register stays complete

- Gap report: UPDATE; infra_tickets exists
- Now: **UPDATE**; the fix sits in: Scheduler code + team_app
- What exists: A branch infra register owned by admin-level roles, with A-D categories, open/closed status and a 7-day escalation flag. Faculty, HR, hod and punch-only staff cannot write to it.
- What remains: A mirror service that maps helpdesk lab/facility categories to audit_type, maps hr_branches to locations by name, sets raised_by null for punch-only raisers (name in owner or issue), and stores the link (a new column on infra_tickets or a link table). Closing must sync both ways (hook closeInfraTicket or reconcile), and RVM must decide whether an Admin Manager closing the register entry resolves the helpdesk ticket.
- Notes: infra_tickets has no in-progress state and no thread, so the helpdesk stays the system of record and the register gets a summary row.
- Check: confirmed: Verified: the infra_tickets schema (20260804000003:113-130); the routes, behind requireRole(ADMIN), which really rejects non-admin roles (routes/amOps.js:19,66-69; middleware/requireRole.js); the create, close and list code (amOpsController.js:23-35,533-612); the escalation flag; the attachments (attachmentsController.js:47-50); the Data Manager entry (managedRecords.js:48-52); and the MCP read (opsTickets.js:59-73). The mirror needs a link column or table on infra_tickets plus a hook in closeInfraTicket, so 'both' is right.
- Evidence:
  - supabase/migrations/20260804000003_admin_manager_ops.sql:111-130 - infra_tickets: id, location_id integer NOT NULL -> locations, ticket_no serial, raised_on, audit_type CHECK A|B|C|D (A IT & PCs, B machines/tools/material, C books/brochures/certificates, D facility/maintenance/AMC), issue NOT NULL, owner text, deadline, status open|closed, closed_on, escalated, escalated_at, raised_by -> users (nullable), created_at
  - routes/amOps.js:19,66-69 - list, create and close behind auth + requireRole(ADMIN): admin, admin_manager, hoo, accounts_admin, super_admin, ceo
  - controllers/amOpsController.js:24-37,533-559 - create in the caller's branch (global roles must pass location_id); issue and audit_type required
  - controllers/amOpsController.js:561-583 - close only (status closed, closed_on), same branch unless global
  - controllers/amOpsController.js:586-612 - list returns the newest 400 with days_open and overdue (more than 7 days)
  - config/amPolicy.js:24-25 + scheduledJobs.js:342-367,734-738 - daily at 08:30 IST, open tickets older than 7 days get escalated=true; the job only logs and sends no notification
  - controllers/attachmentsController.js:47-50 - bill attachments on infra_ticket for admin-level roles
  - config/managedRecords.js:48-52 + routes/adminRecords.js:18-28 - super admin (and the CEO by inheritance) can edit or delete rows in the Data Manager
  - lib/mcp/tools/opsTickets.js:54-80 - the MCP get_infra_tickets tool reads the table

### H. Role views (evidence)

<a id="item-h1"></a>
#### H1: Server-side checks on marking class attendance (caller owns the batch, date window, lock after first save, refuse student tokens)

- Gap report: UPDATE; POST /api/attendance only auth + denyWrite (attendanceRoutes.js:43); denyWrite is a no-op
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: A working upsert endpoint used by both clients (FE client/lib/services/api.ts saveAttendance; flutterapps packages/data/lib/src/datasources/attendance_remote_data_source.dart:20-34), with one audit event per save. None of the four checks exists on the server.
- What remains: Before or inside addOrUpdateAttendance: (1) refuse userType 'student', and any role that does not teach or administer (hr, hr_executive, hod_placement); (2) require the batch to be in the caller's branch unless isSuperAdmin; (3) for faculty/hod, require batches.faculty_id = req.user.faculty_id, or a faculty_substitutions row covering that date with substitute_faculty_id = the caller; (4) require a valid YYYY-MM-DD date inside batch start..min(end, today IST), with no future dates; (5) require every student_id to be on batch_students for the batch; (6) answer 409 when a teaching role re-saves a batch+date that already has rows, while admin roles may still correct it. Optionally store marked_by per row. Use 403/409 with codes, never 401.
- Notes: The sibling write PATCH /api/attendance/remarks (attendanceRoutes.js:107) has a branch fence but no role check. A student token at the branch can write absence remarks, and they are recorded as 'Admin' because students have no username (attendanceController.js:1119-1123,1168-1186). The Flutter staff app also marks attendance, so any new refusal codes must be handled there.
- Check: confirmed: I opened every cited line. server.js:139 mounts the router and attendanceRoutes.js:43 guards POST / with auth + denyWrite only. denyWrite.js:13 tests READ_ONLY_ROLES, which is new Set() (roles.js:109). auth.js:19-43 admits student tokens and sets req.locationId (40). attendanceController.js:124-145 upserts body rows with no role, branch, batch, roster or date check. The only other code that writes student_attendance is the remarks update (1180-1190). Four migrations touch the table (20251215134244, 20260507000000, 20260507000002:52 RLS enable, 20260804000007) and none adds a trigger or lock; db.js:4-7 uses the service key. The web lock is client-only: BatchTable.tsx:591-593 (alreadySaved) and 822-826, shown only for isFaculty. Note: the remarks branch fence (1168-1177) also lets the write through when the batch row is missing, because the test is `if (batch && ...)`. UPDATE and change-existing-scheduler-code are both correct.
- Evidence:
  - routes/attendanceRoutes.js:43 - POST / is auth + denyWrite only
  - middleware/denyWrite.js:12-19 + config/roles.js:105-109 - denyWrite refuses only READ_ONLY_ROLES, which is an empty Set, so it never refuses anyone
  - middleware/auth.js:19-43 - a student token is accepted and given req.locationId from students.location_id
  - controllers/attendanceController.js:124-145 - addOrUpdateAttendance builds rows straight from body batchId/date/attendance[] and upserts on (batch_id, student_id, date). It checks no role, no branch, no batch ownership or substitution, no batch_students membership and no date range, and an existing day is simply overwritten
  - controllers/attendanceController.js:176-188 - the only control is one audit event per marking
  - FE client/components/BatchTable.tsx:591,822-826 - the 'Attendance already saved for this date. Only admin can modify it.' lock exists only in the browser
  - db.js:4-7 - the backend uses the service key, so RLS on student_attendance (20260507000002_security_hardening.sql:52) does not apply; no trigger or lock exists in supabase/migrations

<a id="item-h2"></a>
#### H2: Trim the marking roster reply (full students rows incl. password hashes)

- Gap report: UPDATE; selects students(\*, is_on_hold) incl. password hashes at attendanceController.js:186,191
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: The roster endpoint, returning full student rows to any signed-in caller for any batch.
- What remains: Replace both embeds with an explicit column list, e.g. students(id, name, admission_number, phone_number, is_on_hold). Add the H1 scope check to this read: branch, own or covered batch for teaching roles, and refuse students. Apply the same trimming to the sibling reads named in extra_findings.
- Notes: The column trim is safe for both known clients. Students' own job-portal sign-in runs on a separate backend (flutterapps packages/core_network/lib/src/api_environment.dart:9-28), so whatever students.password_hash holds is exposed here.
- Check: confirmed: Lines 214 and 219 embed students(\*, is_on_hold). The rows go into the reply through `...rec` (282) and `student: link.student` (299). students.password_hash is at public_schema_backup.sql:1791, inside the table at 1775-1797. GET /batch/:batchId/daily (attendanceRoutes.js:51; controller 196-221) has no branch check at all, so any token can read any batch, including another centre's. The clients read only name, admission_number and phone_number (parsers.dart:1110-1126; AttendanceDialog.tsx:607,617; also BatchTable.tsx:961-962). The server itself reads student.is_on_hold at 256. So the proposed column list (id, name, admission_number, phone_number, is_on_hold) is safe. The other reads cited in this controller (938, 1306, 1458) already use explicit columns.
- Evidence:
  - controllers/attendanceController.js:211-221 - the roster still selects '\*, student:students(\*, is_on_hold)' (214) and 'student_id, joined_at, student:students(\*, is_on_hold)' (219); the report's 186/191 have moved
  - controllers/attendanceController.js:279-309 - the nested student object goes into the reply unchanged
  - public_schema_backup.sql:1775-1797 - students carries password_hash (1791), profile_data, resume_url, defaulter_reason and other private columns
  - routes/attendanceRoutes.js:51 + controllers/attendanceController.js:196-221 - GET /batch/:batchId/daily is auth-only, with no branch or ownership check: any token, students included, can read any batch's roster
  - flutterapps packages/data/lib/src/parsers.dart:1110-1126 - the app reads only student.name, admission_number and phone_number
  - FE client/components/AttendanceDialog.tsx:607,617 - the web reads student.name and admission_number

<a id="item-h3"></a>
#### H3: hod_placement as an interviewer, and whether it can see its own interview calendar

- Gap report: AVAILABLE/VERIFY (roles.js:9, migration 20260914000001)
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: The role is in the enum, in roles.js and in the web routing. The 24-hour banner GET /api/interviews/mine/upcoming works for any linked login (interviewsController.js:1198-1243).
- What remains: Add ROLES.HOD_PLACEMENT to INTERVIEWER_ROLES (hrPolicy.js:236), so it can be named and gets its own diary by role. RVM must decide whether it should see every interview ('hod_placement' in SEES_EVERY_INTERVIEW, interviewsController.js:117) and whether it may decide reschedules (INTERVIEW_RESCHEDULE_DECIDE_ROLES). Its login must also be linked through hr_employees.user_id.
- Notes: Direct answer: a hod_placement login cannot see an interview calendar by virtue of its role. Without a linked employee whose label matches LEADER_ROLE_PATTERN it gets 403, even though the web lands it on /interviews.
- Check: confirmed: A backend-wide grep finds hod_placement only in roles.js:9,51,117, userController.js:686 and the enum migration (20260914000001:4). No server policy set names it: INTERVIEWER_ROLES (hrPolicy.js:236-243), SEES_EVERY_INTERVIEW (interviewsController.js:117), the edit, delete, reschedule-decide, stats and candidate-mail sets (140-144, 162-166, 176-182, 198-201, 295-299). viewerScope (127-136) falls back to eligiblePeople('interviewer') (hrPeople.js:60-65,182-185). That needs an unarchived hr_employees row linked by user_id, whose account role is in the set or whose label matches LEADER_ROLE_PATTERN (hrPolicy.js:258). Otherwise list() returns 403 INTERVIEWS_ACCESS_DENIED (298-306). roundsController.js:86-92 uses the same isEligible gate. The web routes the role to /interviews (App.tsx:113-114; roles.ts:406-415,524). UPDATE and change-existing are correct.
- Evidence:
  - config/roles.js:9,49-51 - the role exists and inherits nothing; a comment says it 'owns the interview calendar only'
  - supabase/migrations/20260914000001_hod_placement_role.sql:4 - adds the enum value and nothing else
  - config/hrPolicy.js:236-243 - INTERVIEWER_ROLES = super_admin, ceo, hoo, hod, hr, hr_executive; hod_placement is absent
  - controllers/interviewsController.js:117 - SEES_EVERY_INTERVIEW = hr, hr_executive, ceo, super_admin, hoo; hod_placement is absent
  - controllers/interviewsController.js:127-136,298-306 - any other caller gets in only if eligiblePeople('interviewer') lists the employee linked to their login; otherwise 403 INTERVIEWS_ACCESS_DENIED
  - services/hrPeople.js:60-65,182-185 + config/hrPolicy.js:258 - eligibility is an account role in INTERVIEWER_ROLES, OR an org-chart label matching /hod|ceo|coo|cto|head|hr/. So hod_placement qualifies only through a linked hr_employees row labelled e.g. 'National Placement Head', and then sees only its own rounds
  - controllers/hr/roundsController.js:86-92 - HR cannot book a hod_placement person as interviewer unless that same check passes
  - config/hrPolicy.js:140-144,162-166,176-182,198-201,295-299 - hod_placement is not in the edit, remove, reschedule-decide, stats or candidate-mail sets
  - FE client/App.tsx:113-114 + client/lib/roles.ts:406-415,524 - the web sends hod_placement straight to /interviews

<a id="item-h4"></a>
#### H4: HoO 'my team today' attendance view

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: The data needed: hr_staff_attendance rows with first_in, late and leave status, the shift rules, hr_employees.manager_id, and the user_id link.
- What remains: A new read endpoint, e.g. GET /api/hr/my-team/today. It resolves the caller's employee through hr_employees.user_id, takes their manager_id descendants (or, for the HoO, their branch), and returns today's status, first_in, late, leave and not-punched for each person. Gate it to hoo (and optionally hod and admin_manager), with the scope enforced on the server.
- Notes: The route is additive: one new line in routes/hr.js or its own mount. Do not reuse staffAttendance.read as it stands, because it is not fenced.
- Check: confirmed: I searched routes, controllers and services for my-team, team, reportees, direct-report, team-today and manager_id. The only manager_id uses are HR-workspace reads behind HR_ROLES: employeesController.js:73,176,227,518-527 and orgChartController. HR_ATTENDANCE_ROLES (hrPolicy.js:49-54) excludes hoo, so /api/hr/staff-attendance\* (hr.js:176-181) refuses the HoO. The override, punch log, history and summary routes (hr.js:206-229) are HR, CEO and super admin only. amOpsController and the other non-HR controllers never read hr_staff_attendance. staffAttendanceController.read (60-95) accepts any branch_id and returns everyone when none is given; only remarks and mark use branchFence (201-209, 232-236, 292-302). MISSING and new-self-contained are correct.
- Evidence:
  - config/hrPolicy.js:49-54 - HR_ATTENDANCE_ROLES = hr, admin_manager, ceo, super_admin; there is no hoo
  - routes/hr.js:176-181 - /api/hr/staff-attendance, the only 'who is in today' read, uses that set, so a HoO gets 403 HR_ATTENDANCE_DENIED
  - routes/hr.js:206-229 + config/hrPolicy.js:68-72 - the punch log, history and summary views are hr, ceo and super_admin only
  - routes/hr.js:53,109-124 - the org chart and manager links are readable only under HR_ROLES
  - controllers/hr/employeesController.js:73,176,227 - hr_employees.manager_id exists, and hr_employees.user_id links a login to the org chart
  - controllers/hr/staffAttendanceController.js:60-95 vs 201-209,232,292 - the existing read takes any branch_id, and with none it returns every active employee; the branch fence is applied only to mark and remarks

<a id="item-h5"></a>
#### H5: Light KPI endpoints (CEO dashboard refuses super admins and runs full scans)

- Gap report: MISSING
- Now: **UPDATE**; the fix sits in: Scheduler code + team_app
- What exists: A cached, cheap operational KPI read (/api/dashboard/overview) and a cheap today % read. The finance KPIs exist only in the heavy, CEO-only /api/ceo/dashboard.
- What remains: Add one role-gated light KPI read for the app's leader cards. Give it the guard collectionRateAccess already uses (routes/ceo.js:58-65): exactly ceo, super_admin and hoo, with the HoO pinned to its branch, so students and faculty are refused. Read the finance figures from stored data rather than the 8 live scans: branch_period_metrics already holds revenue_collected, billed_due and outstanding per branch per week/month (nightly), and dashboard_snapshots holds the operational KPIs (hourly). 'Predicted' (unpaid installments due in a window) and today's collected amount are in neither store, so add them to the hourly snapshot payload or compute them with one indexed query. Optionally put the same gate on /api/dashboard/overview, which today serves any branch token, students included. Confirm that 20261019000000 is applied in production.
- Notes: Check that 20261019000000 has been applied in production before the app relies on /overview.
- Check: corrected: Status UPDATE and lands_in both still hold, but what_exists is wrong: finance KPIs do NOT exist only in the CEO-only /api/ceo/dashboard. The reader missed two existing sources that change how the task is built. (1) /api/ceo/collection-rate-intelligence already admits exactly CEO, super admin and HoO-pinned-to-branch, but it is heavy and unpaged. (2) The nightly branch_period_metrics rollup already stores collected, billed and outstanding per branch, readable today only by the CEO. Evidence and what_remains are corrected to include them.
- Evidence:
  - routes/ceo.js:25,72 + config/roles.js:28-30 - /api/ceo/dashboard is auth + requireRole(CEO); super_admin does not inherit ceo, so requireRole.js:34 answers 403
  - controllers/ceoDashboardController.js:60-126 - every call runs 8 paged fetchAllFiltered scans (admissions, all batches, payments, tickets, v_follow_up_task_list, faculty, unpaid installments twice)
  - routes/ceo.js:58-65,95 + controllers/ceoDashboardController.js:361-407 - GET /api/ceo/collection-rate-intelligence ALREADY has the exact gate the task wants: allowRoles {ceo, super_admin, hoo}, with the HoO pinned to its own branch and the location param ignored (370-378). It returns finance KPIs
  - utils/collectionRate.js:58-90,223-244 - those finance KPIs (30-day totalReceiptsAmount, billedInPeriod, expectedRevenueBenchmark, revenueGap, per-centre rates) come from 8 live queries per call, with no .range paging, so they are subject to the 1000-row cap noted at ceoDashboardController.js:55-59
  - supabase/migrations/20260804000009_branch_period_metrics.sql:1-5,30-75 + services/branchRollupService.js:112-135 + scheduledJobs.js:746-752 - a NIGHTLY rollup already stores per-branch revenue_collected and billed_due (flow) and outstanding (position) per week and month
  - controllers/ceoReportingController.js:133-137,205-209 + routes/ceo.js:128,137 - that rollup is a cheap indexed read, but only through the ceoOnly /api/ceo/trend and /api/ceo/period-report routes
  - routes/dashboardRoutes.js:15-19 + controllers/dashboardController.js:389-421 + services/dashboardSnapshotService.js:66-126 + scheduledJobs.js:805 - new since d2595e4 (absent from git show d2595e4:routes/dashboardRoutes.js): an hourly snapshot read with operational KPIs only, no finance
  - controllers/dashboardController.js:397,405-406 - teaching roles get available:false, branchless roles get 401 'Location context missing.', and there is no role gate, so a student token gets its branch snapshot
  - supabase/migrations/20261019000000_dashboard_snapshots.sql:25 - the snapshot table; until it is applied the endpoint answers available:false (dashboardSnapshotService.js:37-40)
  - controllers/attendanceController.js:1815-1860 - GET /api/attendance/today-summary is a cheap today % (auth only, branch-scoped)

<a id="item-h6"></a>
#### H6: HR approval endpoints for the new request types

- Gap report: MISSING (depends on C)
- Now: **MISSING**; the fix sits in: team_app
- What exists: Nothing for the new request types.
- What remains: Once C defines the types: request tables keyed to hr_employees.id, and approve/reject endpoints for HR (and HR Executive, if RVM agrees) behind allowRoles, with audit events. An inbox listing for the approver is also needed.
- Decided on 16 Oct: HR Executive is left out of attendance and leave approvals.
- Notes: About 41 attendance-only employees have no users row, and their punch-only session works only on /api/hr/my-attendance/\* (middleware/punchAuth.js:21-34). Request-raising endpoints for them must accept that session, or a new one.
- Check: confirmed: routes/hr.js has no employee-raised request routes. HR's own day actions are override (207) and excuse-late (218); the employee's own write is PUT /my-attendance/remarks (203), which is a note, not a request (hr_attendance_employee_remarks has no status column; 20261023000000:12-19). I listed every CREATE TABLE in 20261014000000..20261023000000: MCP OAuth, branch-ops, joining checklist, staff attendance, punch devices/punches/pings/overrides/otp, attendance accounts, shifts/holidays/remarks, employee remarks. None is a request table. leave_requests is keyed to faculty_id (20260804000003:78-109) and decided under requireRole(ADMIN) (amOps.js:19,81-84), which HR cannot pass because it inherits nothing (roles.js:43). MISSING and new-self-contained are right: approvals can call the existing override path rather than editing it. The '41 employees with no users row' figure cannot be checked from code. A 2026-10-14 memory note records 65 of 107 live employees with a linked login, so about 42 are unlinked, which is consistent. punchAuth.js:21-34 is confirmed.
- Evidence:
  - routes/hr.js:87-490 - no endpoints for requests raised by employees; HR's only attendance actions are its own overrides and excuse-late (207,218)
  - routes/amOps.js:19,81-84 + controllers/leaveController.js:159-265 - the only leave approval is faculty leave, filed and decided by branch admin-level roles, with the HoO for more than 2 days (182); HR is not involved
  - supabase/migrations/20260804000003_admin_manager_ops.sql:78-108 - leave_requests is keyed to faculty_id, not hr_employees
  - supabase/migrations/20261014\*..20261023\* - the October migrations add punch, accounts, shifts and remarks tables, but no request tables
  - routes/interviews.js:51-52; routes/inventoryRequests.js:45-46 - the existing approval flows (interview reschedules, asset requests) are not HR request types

<a id="item-h7"></a>
#### H7: Faculty 'my day' endpoint aware of substitutions + indicators card data

- Gap report: UPDATE; /api/attendance/reports/faculty/:id exists
- Now: **UPDATE**; the fix sits in: Scheduler code + team_app
- What exists: Building blocks: the substitution-aware faculty report (month health, today %, unmarked dates per batch), today's substitution-aware batch list, and the per-faculty student counts.
- What remains: One endpoint, e.g. GET /api/faculty/me/day?date=, that resolves req.user.faculty_id. It returns: today's sessions from days_of_week/schedule and start/end time, owned or covered through faculty_substitutions (other centres included); a marked flag per session; the pending-remarks count; and an indicators block (month attendance health %, today %, active and total students, sessions with no attendance). Also add a self-or-admin check to /reports/faculty/:facultyId.
- Notes: The faculty indicators on the web are assembled from the four separate calls above, each with its own scope rules.
- Check: confirmed: All cited lines check out. The faculty report (attendanceController.js:505-727) is substitution-aware. Its only scope is the branch filter at 524-530, even though the route comment (attendanceRoutes.js:79-83) promises a faculty check. Substitution batches (539) are not branch-filtered at all. getAllBatches applies today's covers but is branch-scoped (47-49, 88-90) and filters teaching roles at 140-143. GET /substitution/temporary is admin-only (substitution.js:22). The facultyController cites (466-534, 536-571) are accurate, and batches carry days_of_week, schedule, start_time and end_time (public_schema_backup.sql:1474-1490). One building block the reader did not list: GET /api/free-slots. freeSlotsController.js:20-26 forces a teaching caller to its own faculty_id, and 52-66 loads batches with days_of_week and times plus that range's faculty_substitutions. So weekday, time and substitution logic already exists, though branch-scoped. Status and lands_in are unchanged.
- Evidence:
  - routes/attendanceRoutes.js:84 + controllers/attendanceController.js:505-727 - the faculty report exists and is substitution-aware: per-batch expected and marked sessions, attendance % and missing_attendance_dates (683-705, 709-722)
  - routes/attendanceRoutes.js:79-83 vs controllers/attendanceController.js:524-530 - the route comment promises 'the specific faculty via controller logic', but there is only a branch filter; any branch token, students included, can read any faculty's report
  - controllers/batchesController.js:82-92,116-143 - GET /api/batches applies today's substitutions and filters to the effective faculty for teaching roles, but it is branch-scoped (47-49,88-90), so a cover at another centre is invisible, and it does not filter by weekday or time
  - routes/substitution.js:22 - the substitution list is admin-only, so faculty cannot see future covers
  - controllers/attendanceController.js:1815-1860 - today-summary is branch-wide, not per faculty
  - controllers/facultyController.js:466-534,536-571 - active-students is a branch list with one row per faculty; total-students/:faculty_id counts every batch ever, ignores substitutions and has no caller scope

<a id="item-h8"></a>
#### H8: Re-role every HOD and HoO before launch (RVM operations; the backend side lists the accounts for KP, read-only, and changes no role)

- Gap report: OPS
- Now: **OPS**; the fix sits in: RVM operations
- What exists: All the role-gated code is in place. It needs the right role values on the accounts.
- What remains: RVM, through a super admin in User Management: every HOD gets role 'hod', a department (CAD, CAM, PLC or Interior) and a linked faculty record; every HoO gets role 'hoo' with its branch set; each is linked to its hr_employees row (user_id). Re-count first.
- Notes: The code comments still say no account holds 'hod' (routes/interviews.js:18-20; config/hrPolicy.js:229-231; services/hrPeople.js:25-30; FE client/lib/roles.ts:396-400). RVM's own notes record 5 hod, 2 hoo and 1 hod_placement accounts as of 2026-09-15. That is not verifiable read-only here, so part of this may already be done.
- Check: confirmed: The cited code is accurate: FD_ROLES, FD_WRITE_ROLES and DOMAIN_BOUND_ROLES (facultyDevPolicy.js:20-36,71) behind allowRoles (hod.js:27-47); NO_DOMAIN_ASSIGNED via resolveDomain (hodController.js:118-126), used by almost every handler; syncHodDomain (userController.js:28-49); teaching resolution by faculty_id (roles.js:136; auth.js:50-57; userController.js:507-510,733-738); the exact-hoo sets (reportingPolicy.js:70,84,136; remarksLogPolicy.js:20-24; inventoryRequestPolicy.js:50; routes/ceo.js:58-65); ELEVATED_ROLES guards (userController.js:699-701,986-988; roles.js:124-133); the user_id link need (interviewsController.js:127-136,1202-1209). The 'no account holds hod' comments are still in the code. The counts of 5 hod, 2 hoo and 1 hod_placement, and Sandeep's missing hod_domains row, come from RVM's memory note (account_link_and_interviews_sep2026.md:20-22) and are not verifiable read-only. ops-only is correct.
- Evidence:
  - config/facultyDevPolicy.js:20-36,71 + routes/hod.js:27-47 - Faculty Development opens and fills only for the exact role 'hod' (allowRoles, no inheritance)
  - controllers/hodController.js:118-126 - a 'hod' without a hod_domains row gets 403 NO_DOMAIN_ASSIGNED on every read; controllers/userController.js:28-49 writes hod_domains when the role changes
  - config/roles.js:136 + middleware/auth.js:50-57 + controllers/userController.js:507-510,733-738 - hod is a teaching role resolved by users.faculty_id; assigning it links or creates the faculty record
  - config/hrPolicy.js:236-243 - only 'hod' and 'hoo' make someone an interviewer by account
  - controllers/interviewsController.js:117; config/hrPolicy.js:176-182; config/facultyDevPolicy.js:43-47,87-91; routes/ceo.js:58-65; config/reportingPolicy.js:70,84,136; config/remarksLogPolicy.js:22; config/inventoryRequestPolicy.js:50 - every HoO view needs the exact role 'hoo'
  - config/roles.js:83-89,103 - hoo is branch-scoped (not in SEES_ALL_LOCATIONS) and needs users.location_id
  - controllers/userController.js:699-701,986-988 + config/roles.js:124-133 - hod and hoo are elevated, so only a super admin or the CEO can assign them
  - controllers/interviewsController.js:127-136,1202-1209 - the interview diary and the 24h banner also need hr_employees.user_id to be linked

### I. Data model (evidence)

<a id="item-i"></a>
#### I: Data model: indicative tables, columns and functions mapped to what exists at c28b9ca

- Gap report: Indicative data model (attendance, punches, challenges, pings, devices, shifts, holidays, requests, leave, refresh tokens, notifications, wall, praise, polls, announcements, helpdesk, change requests; profile, work_mode, document, geofence and desk-flag columns; per-request functions and the midnight close)
- Now: **UPDATE**; the fix sits in: Scheduler code + team_app
- What exists: The attendance core exists: hr_staff_attendance plus hr_attendance_punches/pings/devices/overrides/otp_codes/accounts/remarks/employee_remarks, hr_shifts and hr_holidays, with the functions hr_attendance_apply_override, hr_attendance_recompute and hr_attendance_otp_issue. None of the ESS tables beyond attendance exist.
- What remains: New tables: attendance and leave/WFH/profile-change requests with history, leave balances, ESS notifications and push device tokens, wall/praise/polls, announcements with acks, celebrations, and the helpdesk. New columns on existing tables: hr_employees date_of_birth, blood_group, address and emergency contact; hr_staff_attendance work_mode (plus a status/CHECK decision); hr_documents verification status and flags; a shared-desk flag on users. One decision-and-write SQL function per request type, modelled on hr_attendance_apply_override.
- Notes: Mapping (indicative -> real (migration) or NONE):
attendance (employee daily) -> hr_staff_attendance (20261015000004_hr_staff_attendance.sql:13-28). source, first_in, last_out and worked_minutes come from 20261020000000_hr_attendance_punch.sql:62-71. shift_id, shift_start, shift_end, grace_minutes, late_minutes, early_exit_minutes, late_count, late_half_day, late_excused\* and source 'auto' come from 20261022000000_hr_attendance_shifts.sql:106-127. The table is shared with the HR daily sheet. note holds the override reason, 'No punch', 'No punch-out' or the holiday name.
attendance_punches -> hr_attendance_punches (20261020000000:98-128; note from 20261022000000:163-169). Every attempt is kept, refused ones included.
attendance_challenges -> NONE. The nonce is stateless HMAC (services/attendancePunch.js:104-141); the replay guard is hr_attendance_punches.nonce_hash UNIQUE (20261020000000:122).
attendance_pings -> hr_attendance_pings (20261020000000:131-144). No captured_at, is_mock or flags, and no purge.
employee_devices -> hr_attendance_devices (20261020000000:77-93). Stores the sha256 of the rvm_att_dev token, one active per employee. No platform, app version, public key or push token.
shifts -> hr_shifts (20261022000000:57-77).
shift_assignments -> NONE as a table. Assignments are hr_employees.shift_id plus shift_since (20261022000000:80-83), written by POST /attendance-admin/shift-assignments. The day's shift is copied onto hr_staff_attendance.shift_\* (20261022000000:106-110). No assignment history.
week-offs -> hr_employees.week_off_days smallint[] DEFAULT {0} (20261022000000:83-88).
holidays (per branch) -> hr_holidays (20261022000000:91-103); branch_id NULL means every branch.
attendance_requests + history -> NONE. The nearest is hr_attendance_overrides, an append-only before/after log of HR overrides (20261020000000:149-162). A pattern to copy is inventory_requests with inventory_request_approvals and inventory_request_history (20260923000000_inventory_requests.sql:53,184,209).
leave_requests_ess / balances (or extend leave_requests) -> NONE. leave_requests (20260804000003_admin_manager_ops.sql:78-109) is the faculty leave ledger: faculty_id and location_id are NOT NULL, leave_type is planned|emergency, and approval is by the AM/HoO. Extending it means altering a live faculty table. Staff leave today is hr_staff_attendance status 'leave' with leave_type cl|lwp. One CL a month is enforced by uq_hr_staff_attendance_one_cl_a_month (20261022000000:129-146) and an app check (services/attendanceRules.js:48-49,237-263). No balances table.
refresh_tokens -> NONE for employees. The portal JWT lasts 64 h (controllers/userController.js:512) and the punch session 30 days (services/attendancePunch.js:205,220-224). mcp_oauth_refresh_tokens (20261014000000_mcp_connector.sql:44) belongs to the MCP connector only.
ess_notifications -> NONE. Not reusable: pending_alerts (20260507000000_features_red_flag_followup_alerts.sql:67-80, student absence alerts), priority_task_reads (20260814000001_reporting_discipline_and_priority_tasks.sql:62-68, read receipts for the priority-task bell), admin_notifications (20251215134244_remote_schema.sql:520-527, student job applications).
device_tokens -> NONE (no FCM or push code in the backend).
wall_posts, wall_comments, wall_reactions -> NONE.
praise, badges -> NONE.
polls, poll_options, poll_votes -> NONE.
ess_announcements + acks -> NONE. announcements (20251215134244_remote_schema.sql:615-624; routes/announcements.js) is student or batch-scoped (scope all|batch) and has no acks.
celebrations -> NONE. Birthdays need hr_employees.date_of_birth, which does not exist. Work anniversaries could use hr_employees.date_of_joining (20260826000001_hrms_tables.sql:96).
helpdesk_categories, helpdesk_tickets, messages, ratings -> NONE for staff. tickets and messages (20251215134244_remote_schema.sql:1080-1091 and 979-986) and ticket_chats (20260514000000_schema_gaps.sql:108) are student support. infra_tickets (20260804000003:113-130) is for branch infrastructure. No ratings exist anywhere.
ess_change_requests -> NONE. HR edits records through PATCH /api/hr/employees/:id; /api/me changes only the users row (routes/me.js:25-41).
COLUMNS:
hr_employees date_of_birth / blood_group / address / emergency_contact -> NONE. hr_employees (20260826000001:82-131) plus every later ADD COLUMN has photo, bond, increment_date, bgv_\*, role_id, user_id, referral, additional_phones, phone_digits, geofence_exempt, shift_\* and week_off_days only. date_of_birth exists only on admission_intakes (20260514000000:78).
daily record work_mode -> NONE. There is no column, and the status CHECK has no WFH or on-duty value (20261015000004:18-20).
hr_documents verification status and type flags -> NONE. hr_documents (20260826000001:500-515) has doc_type resume|identity|certificate|offer|joining|experience|exit|other and a note, with no verified/status/employee-visible/mandatory columns. Only the person-level hr_employees.bgv_status exists (20260903000002_hr_bgv.sql:91-92).
branch geofence radius -> hr_branches.geofence_radius_m integer DEFAULT 150 with CHECK 25-2000, plus latitude, longitude and office_ips (20261020000000:37-55).
field-staff exemption -> hr_employees.geofence_exempt boolean (20261020000000:57-59), set per employee, not per branch.
account shared-desk flag -> NONE. users gained email, email_verified_at, photo, two_factor_enabled and password_changed_at (20260909000000_user_profile_security.sql:41-49). Desk logins are simply users with no hr_employees.user_id link; GET /my-attendance answers them {linked:false}.
ALSO REAL, NOT IN THE REPORT: hr_attendance_overrides (20261020000000:149-162), hr_attendance_otp_codes (20261020000000:169-194), hr_attendance_accounts (20261021000000:23-46), hr_attendance_remarks for HR's remark (20261022000000:151-160), hr_attendance_employee_remarks for the employee's remark (20261023000000:12-19). Every one is RLS deny-all and reachable with the service key only.
DB FUNCTIONS:
one decision-and-write function per request type -> only hr_attendance_apply_override(p_employee_id, p_day, p_branch_id, p_status, p_leave_type, p_first_in, p_last_out, p_worked_minutes, p_reason, p_by, p_by_name) (20261020000000:290-341). It row-locks the day, upserts it as source 'override' and writes the before/after log in one transaction. There are no request functions. Other attendance functions: hr_attendance_recompute (20261022000000:197-286) and hr_attendance_otp_issue (20261020000000:211-280).
the midnight close -> NONE in SQL. It is Node code, services/attendanceSettle.js:37-163, run by cron at 18:35 and 23:00 UTC (scheduledJobs.js:710-719) and 30 s after boot (server.js:232-234). It calls hr_attendance_recompute.
- Check: confirmed: I spot-checked the mapping against the migrations. hr_employees (20260826000001:82-131) plus every later ALTER has no DOB, blood group, address or emergency contact; date_of_birth exists only on admission_intakes (20260514000000:71,78). hr_documents is at 500-515, and leave_requests is keyed on faculty (20260804000003:78-109). announcements, messages and tickets are student-scoped (remote_schema 615-624, 979-986, 1080-1091). The JWT lasts 64 h (userController.js:512). git grep finds no FCM or push code, and no wall, helpdesk or work_mode schema. One nit in the notes: 'No ratings exist anywhere' is not literal, because HOD monthly reviews carry ratings jsonb (20260804000004_hod_module.sql:40). There is no helpdesk or ticket rating, which is what matters here.
- Evidence:
  - supabase/migrations/20261015000004_hr_staff_attendance.sql:13-28 - hr_staff_attendance, the daily record, UNIQUE(employee_id, day)
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:37-71,77-162,290-341 - branch geofence columns, geofence_exempt, source and times, devices, punches, pings, overrides, apply_override
  - supabase/migrations/20261021000000_hr_attendance_accounts.sql:23-46 - attendance-only logins
  - supabase/migrations/20261022000000_hr_attendance_shifts.sql:57-160,197-286 - shifts, shift and week-off columns, holidays, rule columns, the one-CL index, HR remarks, recompute
  - supabase/migrations/20261023000000_hr_attendance_employee_remarks.sql:12-19 - employee remarks
  - supabase/migrations/20260826000001_hrms_tables.sql:82-131,500-515 - hr_employees has no DOB, blood group, address or emergency contact; hr_documents has doc_type only, no verification
  - supabase/migrations/20260804000003_admin_manager_ops.sql:78-109 - leave_requests is keyed on faculty
  - supabase/migrations/20251215134244_remote_schema.sql:615-624,979-986,1080-1091 - announcements, messages and tickets are student-facing
  - services/attendanceSettle.js:37-163 + scheduledJobs.js:710-719 - the midnight close runs in Node, not SQL

### J. Security before launch, and the issue #70 list (evidence)

<a id="item-j1"></a>
#### J1: POST /api/attendance accepts any signed-in token (student included) for any batch and date

- Gap report: OPEN (attendanceRoutes.js:43; denyWrite empty at roles.js:94)
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: Still open, exactly as reported.
- What remains: Same as H1. A minimum fix is staffOnly (middleware/staffOnly.js) plus a branch and ownership check in the controller.
- Notes: The student login is not covered by loginLimiter (server.js:119 covers /api/users/login only), so a token is cheap to get for anyone who knows a student's admission number and phone.
- Check: confirmed: This is the same code path as H1 (attendanceRoutes.js:43; roles.js:109; auth.js:19-43; attendanceController.js:124-145). The report's 'roles.js:94' was READ_ONLY_ROLES at d2595e4; it is now line 109, per git show. studentLogin (userController.js:783-801) signs a 7-day JWT from admission_number + phone_number alone. loginLimiter is mounted only on the /api/users/login prefix (server.js:119), so /api/users/auth/student/login gets only the 300/min apiLimiter (125). UPDATE and change-existing are correct.
- Evidence:
  - routes/attendanceRoutes.js:43 - still auth + denyWrite only
  - config/roles.js:105-109 - READ_ONLY_ROLES = new Set() (the report's line 94 has moved)
  - middleware/auth.js:19-43 - student tokens pass auth
  - controllers/attendanceController.js:124-145 - no role, branch, batch, student or date check before the upsert
  - routes/user.js:38 + controllers/userController.js:783-801 - a 7-day student token is minted from admission_number + phone_number, with no password and no OTP

<a id="item-j2"></a>
#### J2: Marking roster returns full student rows incl. password hashes

- Gap report: OPEN
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: Still open, and wider than reported.
- What remains: Explicit column lists in all four places, plus the H2 scope check on the roster.
- Notes: Before trimming GET /api/students, check which fields its web and Flutter consumers read.
- Check: confirmed: All four places are confirmed. The roster: attendanceController.js:214,219. GET /api/students: routes/students.js:22 is auth-only, studentsController.js:26 allows up to 1000 rows a page, select('\*') at 63-73, spread at 113-114. Batch create and update: batchesController.js:265 and 505 select students:batch_students(students(\*)), returned at 510/523 and on the create path. password_hash is public_schema_backup.sql:1791. GET /api/batches/:id/students is not a fifth leak: it is branch-fenced (654-656) and returns explicit fields (707-730).
- Evidence:
  - controllers/attendanceController.js:214,219 - students(\*, is_on_hold) in both roster selects
  - public_schema_backup.sql:1791 - students.password_hash
  - controllers/studentsController.js:63-73,113-114 + routes/students.js:22 - GET /api/students also spreads the full select('\*') row, for up to 1000 students per page, to any branch token
  - controllers/batchesController.js:263-270,505-523 - POST and PUT /api/batches reply with students:batch_students(students(\*))

<a id="item-j3"></a>
#### J3: Batch create/edit/delete have no role check

- Gap report: OPEN (routes/batches.js:9-11)
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: Still open.
- What remains: Add requireRole(ROLES.ADMIN), or an exact allowlist such as ENROLL_ROLES, to routes/batches.js:19-21. Add a branch check on the target batch in update and delete, and apply the cross-branch ownership rule to the studentIds sent with create and update.
- Notes: The Flutter staff app exposes create and edit to faculty (flutterapps packages/data/lib/src/datasources/batches_remote_data_source.dart:42-48), so it must hide them once the server refuses.
- Check: confirmed: routes/batches.js:19-21 is auth + denyWrite only; the mount adds only auth (server.js:129); git show d2595e4 had these routes at 9-11. createBatch needs only req.locationId (159-163) and inserts at the caller's branch (233-243). updateBatch checks only req.locationId (302-306), then updates by id (494-506) without checking the target batch's branch. deleteBatch (539-583) deletes by id with no role or branch check and clears joined (556-565). Roster inserts on create (249-260) and update (470-481) bypass enrollGuard, which routes/batches.js applies only to /options, /:id/students and /:id/student-search (12, 18, 23-24). Better evidence for the Flutter note: staff_permissions.dart:112-119 gives faculty canWrite:true, and batches_screen.dart:63,324-325 shows the create button and the Edit and Delete items whenever canWrite is set.
- Evidence:
  - routes/batches.js:19-21 - POST /, PUT /:id and DELETE /:id are auth + denyWrite only (moved from 9-11)
  - controllers/batchesController.js:159-163,233-243 - createBatch requires only req.locationId, which students and faculty have, and creates the batch at the caller's branch
  - controllers/batchesController.js:302-306,494-506 - updateBatch checks only that req.locationId is set, then updates by id with no check of the batch's branch
  - controllers/batchesController.js:539-583 - deleteBatch has no role and no branch check: it deletes any batch by id and clears 'joined' for its students (556-565)
  - controllers/batchesController.js:250-261,470-481 vs routes/batches.js:12,23 - create and update insert any studentIds into batch_students without the ENROLL_ROLES guard that POST /:id/students uses

<a id="item-j4"></a>
#### J4: Announcement create/delete have no role check

- Gap report: OPEN (routes/announcements.js:13-14)
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: Still open.
- What remains: Add an admin-level gate (requireRole(ADMIN) or an allowlist) on POST and DELETE. Scope the delete to the caller's branch unless isSuperAdmin, validate that batch_id belongs to the branch, and let branchless global roles pass a location_id.
- Notes: The Flutter app exposes create and delete (flutterapps packages/data/lib/src/datasources/announcements_remote_data_source.dart:23-29).
- Check: confirmed: routes/announcements.js:13-14 is auth only, and server.js:140 adds no auth at the mount. createAnnouncement (34-69) needs only req.locationId (401 for a branchless CEO or super admin at 35-37) and inserts body batch_id unchecked (50). deleteAnnouncement (71-84) deletes any id with no role or branch check. The Flutter data source (announcements_remote_data_source.dart:23-29) exposes both.
- Evidence:
  - routes/announcements.js:13-14 - POST and DELETE are auth only
  - controllers/announcementController.js:34-69 - create needs only req.locationId, which students and faculty have; batch_id is not checked against the branch; a CEO or super admin with no branch gets 401
  - controllers/announcementController.js:71-84 - delete removes any announcement by id, with no role and no branch check

<a id="item-j5"></a>
#### J5: Unsafe POST /api/users/reset-password (username + phone, no code) still registered

- Gap report: OPEN (routes/user.js:28)
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: Still open, and weaker than described: knowing a phone number is enough.
- What remains: Remove the route, or require an OTP to the account's verified phone or email. Move the web Login page and the Flutter staff app to /api/users/forgot-password[/confirm], and add an SMS-code variant for staff who have no verified email. Optionally reject tokens issued before password_changed_at in auth.
- Notes: Accounts with 2FA on still need the emailed code to sign in (userController.js:467), but their password can still be changed, which locks the owner out. The removal also needs client changes.
- Check: confirmed: routes/user.js:27-28 is public. server.js:119-125 applies only apiLimiter to it; otpLimiter covers /api/users/forgot-password, loginLimiter covers /api/users/login. resetPassword (userController.js:1175-1238) interpolates username unquoted into .or() at 1201 and 1213, with .eq('phone_number', P) at 1202/1214. So username=P matches any account whose phone is P, and 1230-1236 writes the new hash with no code. Login accepts the phone as identifier (271-279). GET /api/users (user.js:69; userController.js:558,569-575) hands phone_number and role to any branch token. auth.js has no password_changed_at check, and tokens last 64h (512). Both clients still call the route (Login.tsx:185; staff_auth_remote_data_source.dart:43; also users_remote_data_source.dart:47-49). The strong reset exists (authSecurityController.js:146-196). Extra: the legacy reset (1233-1236) and /api/users/change-password (1315-1318) never set users.password_changed_at. Only authSecurityController.js:177-179 and profileController.js:272-274 do, so a future revocation check keyed on that column must also fix these two paths.
- Evidence:
  - routes/user.js:27-28 - still public
  - server.js:119-125 - it is under neither otpLimiter nor loginLimiter, only the 300/min apiLimiter
  - controllers/userController.js:1175-1238 - it matches .or(username.eq.X,phone_number.eq.X) plus .eq(phone_number,P), then writes a new password_hash with no code
  - controllers/userController.js:1201,1213 - X is interpolated unquoted (login quotes it at 271-279). Sending the phone number in both fields matches any account with that phone, so no username is needed
  - routes/user.js:69 + controllers/userController.js:558,569-575 - GET /api/users gives every account's phone_number at the caller's branch to any token, students included
  - middleware/auth.js:6-106 - there is no password_changed_at check, so existing 64h tokens survive any reset
  - FE client/pages/Login.tsx:185; flutterapps packages/data/lib/src/datasources/staff_auth_remote_data_source.dart:43 - both clients still call it
  - controllers/authSecurityController.js:146-196 - the strong email-code reset already exists

<a id="item-j6"></a>
#### J6: hod_placement as interviewer; HOD/HoO on the right role

- Gap report: PART
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: The HOD and HoO code paths are complete. hod_placement is wired on the web, but the server never names it.
- What remains: Code: add HOD_PLACEMENT to INTERVIEWER_ROLES, and to SEES_EVERY_INTERVIEW and the reschedule-decide set if RVM agrees. Ops: H8 (re-role HODs and HoOs, set hod_domains, link hr_employees.user_id).
- Notes: The code part is small. The rest is the H8 operations step.
- Check: confirmed: The same verification as H3 and H8 applies: hrPolicy.js:236-243, interviewsController.js:117,127-136, roundsController.js:86-92, facultyDevPolicy.js:20-47,71,87-91 and userController.js:699-701 all show what is claimed. The code part is adding HOD_PLACEMENT to the interview sets in config/hrPolicy.js and the controller; the rest is the H8 ops step. change-existing-scheduler-code is right for the code part.
- Evidence:
  - config/hrPolicy.js:236-243 - hod_placement is not in INTERVIEWER_ROLES
  - controllers/interviewsController.js:117,127-136 - and not in SEES_EVERY_INTERVIEW; it gets access only through the org-chart label rule
  - controllers/hr/roundsController.js:86-92 - HR cannot book it as interviewer by role
  - config/facultyDevPolicy.js:20-47,71,87-91 - HOD and HoO screens need the exact roles 'hod' and 'hoo'
  - controllers/userController.js:699-701 - only a super admin or the CEO can assign them

<a id="item-j7"></a>
#### J7: nginx upload limit + health and minimum-app-version endpoint

- Gap report: OPEN
- Now: **MISSING**; the fix sits in: Scheduler code + team_app
- What exists: Nothing. The nginx side cannot be seen from the repo.
- What remains: Code: add GET /api/health (JSON, no auth, a quick database ping such as the MCP health tool's head count on locations) and GET /api/app/min-version returning {min_version, latest_version, force_update} from config or env, both mounted before the SPA catch-all at server.js:212. Repo infra: add client_max_body_size (for example 25m, at least the largest multipart the app sends) to the /api/ location blocks in .github/workflows/deploy.yml: the scheduler vhost at 340-350, plus the student vhost at 470-477 and 510-517 if the portal uploads. Optionally add error_page handlers there so nginx's 413, 502 and 504 on /api come back as JSON the app can detect. Editing nginx on the VPS alone does not stick: the next push to main overwrites it. Ops: check whether the VPS's /etc/nginx/nginx.conf already sets a global client_max_body_size.
- Notes: The nginx limit is an operations step on the VPS. If it is still the 1 MB default, uploads over 1 MB fail with an nginx HTML 413 before they reach Node.
- Check: corrected: The health and min-version gap is real, so MISSING stands. But the evidence line 'there is no nginx config and no client_max_body_size in Scheduler_Backend' is wrong. The vhost is written by .github/workflows/deploy.yml on every push to main, and its /api/ block sets no body limit. So the nginx part is a change to an existing file in the repo, not a VPS-only operations step, and lands_in becomes both.
- Evidence:
  - server.js:127-201 - no /api/health, version or minimum-app-version route is mounted
  - server.js:204-220 - any unknown GET, /api/health included, falls to app.get('\*') at 212 and gets index.html with 200, or the 404 text at 217 when the build is missing
  - lib/mcp/tools/shared.js:4-6 - the only 'health' is the MCP connector tool, not an HTTP endpoint
  - CORRECTION - .github/workflows/deploy.yml:3-6,53-57 - the deploy job runs on every push to main. The nginx config DOES live in the repo (ripgrep skips the hidden .github folder by default)
  - CORRECTION - .github/workflows/deploy.yml:312-323,411-413,540-545 - each deploy rewrites /etc/nginx/sites-available/scheduler from the heredoc and reloads nginx, so a hand edit on the VPS is overwritten by the next push to main
  - CORRECTION - .github/workflows/deploy.yml:340-350 - the scheduler vhost's `location /api/` sets no client_max_body_size (the student vhost's /api/ blocks at 470-477 and 510-517 likewise), so nginx's 1 MB default applies unless the VPS's global nginx.conf overrides it, which the repo does not show
  - routes/hr.js:77-84 + config/hrPolicy.js:1259-1261; routes/intake.js:29-32; routes/attachments.js:16; controllers/accountsController.js:14 - multer accepts 10 MB per file and up to 10 files per request
  - controllers/admissionUndertakingController.js:5-8; controllers/intakeController.js:15 - 15 MB per file for undertakings and intakes
  - server.js:103 - express.json() uses the default 100 kb JSON limit

<a id="item-j8"></a>
#### J8: 401 semantics: sign out only when the session is really over

- Gap report: SERVER+CLIENT; ~40 endpoints reuse 401 for other reasons
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: Count at c28b9ca: 49 app-facing 401 sites are NOT token rejections. That is 43 'no branch' sites, 4 wrong-current-password sites and 2 sign-in credential failures, plus 3 non-app ones. Only these mean the session is over: 'No token provided', 'Please authenticate' (no code) and code NOT_AUTHENTICATED (punch sessions only).
- What remains: Server: turn the 43 branch-context 401s into 403 with a code (e.g. NO_BRANCH_CONTEXT), and the 4 wrong-password 401s into 400/403 with a code (WRONG_PASSWORD). Add code NOT_AUTHENTICATED (or TOKEN_EXPIRED/TOKEN_INVALID) to auth.js's two 401s, and answer 503 rather than 401 when the user lookup fails for a database reason. Client: sign out only on that code (or those exact messages), never on any 401.
- Notes: The report's '~40' undercounts: the figure is 49. Eleven of the branch-context sites are unconditional and hit a CEO or super admin whose row has no branch: announcementController.js:36; batchesController.js:162,305; skillsController.js:29; studentsController.js:164; substitutionController.js:22,211,396; suggestionController.js:25; facultyController.js:96 and admissionController.js:189 unless body.location_id is sent. HR and HR Executive (no branch) hit the rest. The client half of the fix is client-only work.
- Check: confirmed: I recounted every 401 site with a backend grep, excluding tests: 60 in total. That is 8 session-over sites (auth.js:11,104; requireRole.js:9; allowRoles.js:16; staffOnly.js:7; attendancePunchController.js:105,110; attendanceAccounts.js:50), 43 no-branch, 4 wrong-current-password (profileController.js:126,251,270; userController.js:1310), 2 sign-in failures (453, 795) and 3 non-app (mcp.js:48,183; webhooksController.js:136). Every file and line in the reader's lists matches, and the 11 unconditional no-branch sites (no isSuperAdmin escape) check out. OtpError never uses 401 (otp.js:37-44). The HR and email handlers forward an upstream 401 only when expose===true (hr/_shared.js:128-141; email/_shared.js:50-52). Both clients sign out on any 401 (me.ts:25-28 + AuthContext.tsx:82-92; bearer_auth_interceptor.dart:6-7,30-32). Nuance: an expired or invalid punch-only token makes readPunchSession return null (services/attendancePunch.js:230-239). punchAuth.js:33 then hands it to auth, which answers 401 'Please authenticate' with no code, not NOT_AUTHENTICATED. The sign-out rule must treat both as session over, or auth.js's 401s must gain a code.
- Evidence:
  - SESSION OVER: middleware/auth.js:10-12 - 401 {error:'No token provided'} (no code)
  - SESSION OVER: middleware/auth.js:102-105 - 401 {error:'Please authenticate'} (no code) for any exception in auth: an expired or bad JWT, a punch-only token sent to a portal route, or the user or student not found. It is ALSO sent on a database error or a duplicate faculty_id row (.single() at 20-28 and 50-72)
  - SESSION OVER: middleware/requireRole.js:8-10; middleware/allowRoles.js:15-17; middleware/staffOnly.js:6-8 - 401 'Please authenticate', reached only when auth did not run
  - SESSION OVER: controllers/hr/attendancePunchController.js:105,110 - 401 code NOT_AUTHENTICATED, 'Please sign in.' and 'Please sign in again.'
  - SESSION OVER: services/attendanceAccounts.js:49-51, raised at controllers/hr/attendancePunchController.js:116-118 - 401 NOT_AUTHENTICATED 'Your password was changed. Please sign in again.'
  - NOT SESSION (no branch): controllers/attendanceController.js:528,866,898,1829,1988 - 'Location context missing.'
  - NOT SESSION (no branch): controllers/batchAllotmentController.js:61(sent at 187),220,706,766,810 - 'Location context missing.'
  - NOT SESSION (no branch): controllers/batchesController.js:33,162,305,808 - 'Authentication required with location[ context].'
  - NOT SESSION (no branch): controllers/facultyController.js:38,96,485,589,667 - 'Authentication required with location.' / 'Location missing.' / 'Location context missing.'
  - NOT SESSION (no branch): controllers/substitutionController.js:22,161,211,396 - 'Authentication required with location.'
  - NOT SESSION (no branch): controllers/admissionController.js:29,189,666 - 'Location context missing.' / 'Authentication failed.' (189)
  - NOT SESSION (no branch): controllers/ticketManagementController.js:107,334,358 - 'Authentication required with location.' / 'Location required.'
  - NOT SESSION (no branch): controllers/alertsController.js:61,239; controllers/accountsController.js:52; controllers/dashboardController.js:406; controllers/userController.js:572 - 'Location context missing.'
  - NOT SESSION (no branch): controllers/announcementController.js:10,36; controllers/activityController.js:9; controllers/freeSlotsController.js:10; controllers/skillsController.js:9,29; controllers/suggestionController.js:25; controllers/studentsController.js:21,164 - 'Authentication required[ with location].'
  - NOT SESSION (wrong current password while signed in): controllers/profileController.js:126,251,270; controllers/userController.js:1310 - 'Wrong password.' / 'Current password is incorrect.'
  - NOT SESSION (bad credentials at sign-in): controllers/userController.js:453 'Invalid password', 795 'Invalid credentials.'
  - NOT APP TRAFFIC: routes/mcp.js:48,183 (MCP OAuth invalid_token / invalid_client); controllers/email/webhooksController.js:136 (ZeptoMail webhook key)
  - controllers/hr/_shared.js:128-141; controllers/email/_shared.js:50-52 - an upstream provider's 401 (for example ZeptoMail) is NOT passed to clients unless expose===true
  - CLIENTS: FE client/lib/services/me.ts:24-27 + client/hooks/AuthContext.tsx:82-90 - the web logs out on any 401, so a wrong current password logs the user out; flutterapps packages/core_network/lib/src/interceptors/bearer_auth_interceptor.dart:6-7,30-32 - the app treats every 401 as session over

<a id="item-j9"></a>
#### J9: Play Integrity verification server-side

- Gap report: OPEN
- Now: **MISSING**; the fix sits in: Scheduler code + team_app
- What exists: Nothing.
- What remains: A server module that verifies Play Integrity tokens (decode through Google's API with a service account, check the package name, certificate digest, nonce or requestHash and app and device verdicts). It needs a flag so it runs log-only until the keys exist, and it must be hooked into punch-session issuance and/or the punch and challenge endpoints.
- Decided on 16 Oct: No Play project yet: verification is built behind a switch that stays off (ADR-0016).
- Notes: Following the console-mode convention, it should log instead of enforcing until the Firebase/Play project and keys exist.
- Check: confirmed: A code-wide search for integrity, attest, safetynet, devicecheck, app check and googleapis (excluding node_modules) finds only services/audit.js:230 (integrity_chain_hash) and a test name. The only device trust is the mobile User-Agent regex, 'a speed bump, not a wall' (services/attendancePunch.js:28-36), plus the rvm_att_dev cookie (39). The punch reads the UA at attendancePunchController.js:329 and refuses NOT_MOBILE at 357. Enforcement means editing the existing punch and challenge or session issuance, so both is right.
- Evidence:
  - grep for integrity|attest|safetynet|devicecheck|app check across server.js, routes, controllers, middleware, services, utils, lib and config - only services/audit.js:230 (integrity_chain_hash, unrelated)
  - .env.example - no Play Integrity or Google service-account setting
  - services/attendancePunch.js:28-39 - the only device trust is a mobile User-Agent regex ('a speed bump, not a wall') and the rvm_att_dev cookie
  - controllers/hr/attendancePunchController.js:329,357 - the punch refuses NOT_MOBILE on the User-Agent alone

<a id="item-70a"></a>
#### 70a: /api/activities without auth

- Gap report: Issue #70 leftover
- Now: **AVAILABLE**; the fix sits in: Nothing to build
- What exists: Fixed.
- What remains: nothing
- Notes: A student token can still read its branch's last 10 activity lines; this is low risk.
- Check: confirmed: server.js:133 mounts the router without auth, but routes/activity.js:7 applies auth. activityController.js:8-22 scopes to req.locationId unless isSuperAdmin and returns 10 rows. Commit 8ec22fd (2026-09-26) exists in the history.
- Evidence:
  - routes/activity.js:6-7 - GET / is now auth + getActivities (commit 8ec22fd, 2026-09-26)
  - controllers/activityController.js:8-22 - scoped to req.locationId unless isSuperAdmin; returns the last 10 rows

<a id="item-70b"></a>
#### 70b: Public course writes (/api/courses)

- Gap report: Issue #70 leftover
- Now: **AVAILABLE**; the fix sits in: Nothing to build
- What exists: Fixed in 8ec22fd.
- What remains: nothing
- Notes: requireRole(ADMIN) admits every admin-level role (admin, admin_manager, hoo, accounts_admin, super_admin, ceo).
- Check: confirmed: courseRoutes.js:18-20 puts auth + requireRole(ROLES.ADMIN) on POST, PUT and DELETE. Reads at 16-17 are public by design (comment 14-15), and server.js:143 adds no auth. requireRole(ADMIN) admits every role that inherits admin (roles.js:28-37).
- Evidence:
  - routes/courseRoutes.js:18-20 - POST, PUT and DELETE are auth + requireRole(ROLES.ADMIN)
  - routes/courseRoutes.js:14-17 - reads stay public by design, for the admission and undertaking forms

<a id="item-70c"></a>
#### 70c: Public intake list (GET /api/intakes)

- Gap report: Issue #70 leftover
- Now: **AVAILABLE**; the fix sits in: Nothing to build
- What exists: Fixed (64530d5 and e5bfbd8).
- What remains: nothing
- Notes: Remaining gap: listIntakes returns every branch's intakes with select('\*'), ID numbers and addresses included, to any staff role, faculty and HR included (controllers/intakeController.js:459-485). The tokenless grace is meant to be removed once the logs show no use.
- Check: confirmed: intake.js:80-85 is auth + staffOnly + listIntakes, and staffOnly.js:9-11 answers students with 403. intakeAccess.js:27-53 requires the token or a staff Bearer, with the grace at 45-49 (intakeGrace.js:24 defaults to 60 minutes). The note is accurate: listIntakes (intakeController.js:459-490) returns select('\*') for every branch, with no location filter, to any non-student token, HR and faculty included.
- Evidence:
  - routes/intake.js:79-85 - GET / is auth + staffOnly + listIntakes
  - middleware/staffOnly.js:5-13 - refuses student tokens with 403
  - middleware/intakeAccess.js:27-53 - upload and finalize need the per-intake token or a staff Bearer, with a temporary tokenless grace (utils/intakeGrace.js:1-26, 60 minutes by default)

<a id="item-70d"></a>
#### 70d: Public /api/chat

- Gap report: Issue #70 leftover
- Now: **AVAILABLE**; the fix sits in: Nothing to build
- What exists: No longer public.
- What remains: nothing
- Notes: Remaining gap: there is no ticket-ownership check. Any token can read or post any ticket's legacy messages (controllers/chatController.js:10-58,67-85), while the newer /api/tickets/:id/chat does check (controllers/ticketManagementController.js:20-37,458-463).
- Check: confirmed: chatRoutes.js:12,17 now require auth, and the sender is taken from the token (chatController.js:14-17). The note is accurate: sendMessage and getMessages (10-64, 67-90+) never check that the ticket belongs to the caller. fetchAccessibleTicket (ticketManagementController.js:20-37), used by getChatMessages (458-463), does check.
- Evidence:
  - routes/chatRoutes.js:12,17 - POST and GET /:ticketId now require auth (8ec22fd)
  - controllers/chatController.js:14-17 - the sender is taken from the token

<a id="item-70e"></a>
#### 70e: ensureFacultyId with a blank email

- Gap report: Issue #70 leftover
- Now: **AVAILABLE**; the fix sits in: Nothing to build
- What exists: Fixed in 8ec22fd.
- What remains: nothing
- Notes: A sibling remains: POST /api/faculty inserts the body email as given (controllers/facultyController.js:99,133-141), and the web sends whatever was typed (FE client/hooks/useFacultyData.ts:63-70). A blank field can still hit the same '' clash.
- Check: confirmed: ensureFacultyId (userController.js:143-170) inserts email: null at 159, with the explanation at 137-142. Migration 20260915000002:5-6 drops NOT NULL. The sibling in the note is real: createFaculty takes the body email (facultyController.js:99) and inserts it as given (133-141), and the web form sends data.email unchanged (useFacultyData.ts:63-70).
- Evidence:
  - controllers/userController.js:137-170 - ensureFacultyId now inserts email: null (159); the comment explains the unique (email, location_id) clash
  - supabase/migrations/20260915000002_faculty_email_nullable.sql:5-6 - faculty.email is nullable

<a id="item-70f"></a>
#### 70f: Missing /api/intakes/by-phone

- Gap report: Issue #70 leftover
- Now: **AVAILABLE**; the fix sits in: Nothing to build
- What exists: Present (64530d5 and e5bfbd8).
- What remains: nothing
- Notes: GET /api/admissions/by-phone/:phone stays public but returns only a mode and undertaking_completed (routes/admissionRoutes.js:42-47; controllers/admissionController.js:578-598).
- Check: confirmed: intake.js:41-44 registers GET /by-phone/:phone before the /:id routes. intakeStatusByPhone (intakeController.js:386 onward) answers only {exists, status, submitted, approved}, or NO_APPLICATION. admissionRoutes.js:47 (comment 42-46) and admissionController.js:578-598 return only the mode and undertaking_completed.
- Evidence:
  - routes/intake.js:39-44 - GET /by-phone/:phone is registered before the /:id routes
  - controllers/intakeController.js:372-451 - it answers status only ({exists, status, submitted, approved}), always 200, never names or ids

<a id="item-dash"></a>
#### DASH: Brief: '/api/dashboard shows branch fee totals to faculty' (who can call it)

- Gap report: Brief claim (no report id)
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: The claim is true and understated. Any branch token gets the full branch admissions list and fee totals: faculty, HOD and students alike.
- What remains: Gate GET /api/dashboard to admin-level roles (requireRole(ADMIN) or an exact allowlist). If the staff app's faculty dashboard needs numbers, give teaching roles a separate, teaching-scoped, non-financial reply.
- Notes: Gating it does not affect the web, which already restricts the page, but the Flutter staff app's faculty dashboard must change.
- Check: confirmed: server.js:145 and dashboardRoutes.js:7 apply auth only. getDashboardData requires only a branch (dashboardController.js:5,18-20), and a branchless HR account gets 403. Student and faculty tokens carry one (auth.js:40,98). The reply is admissions.\* with the student's name and phone, payments, installments and remaining_due (25-35, 94-110), plus totalCollected and totalOutstanding (140-159). The web shows the page only to ADMIN_LEVEL_WITH_ACCOUNTS (App.tsx:553-561); AdmissionDashboard.tsx:157 is the only web caller. The Flutter staff app calls it (dashboard_remote_data_source.dart:14-15) and gives faculty a dashboard destination (staff_permissions.dart:112-117). A sibling with the same exposure: GET /api/accounts/admissions (accountsRoutes.js:26; accountsController.js:21-53) is also auth-only and branch-scoped, and returns each admission's student name, phone, totals and remaining_due to any branch token.
- Evidence:
  - server.js:145 + routes/dashboardRoutes.js:7 - GET /api/dashboard is auth only
  - controllers/dashboardController.js:4-20 - the only requirement is a branch: req.locationId or req.user.location_id; branchless HR gets 403
  - middleware/auth.js:40,98 - student and faculty tokens both carry a branch
  - controllers/dashboardController.js:25-35,94-110 - it returns every admission at the branch: admissions.\* with the student's name, phone, payments, installments and remaining_due
  - controllers/dashboardController.js:140-159 - plus metrics totalCollected and totalOutstanding
  - FE client/App.tsx:553-561 - the web shows this page only to ADMIN_LEVEL_WITH_ACCOUNTS; flutterapps packages/data/lib/src/datasources/dashboard_remote_data_source.dart:14-15 - the staff app calls it for its dashboard

### K. Infrastructure (evidence)

<a id="item-k1"></a>
#### K1: nginx upload limit above the 1 MB default (written by deploy.yml)

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: Scheduler code
- What exists: Nothing in the repo; the http-level value in the VPS nginx.conf is unknown.
- What remains: Add client_max_body_size (e.g. 12m, or larger only on upload paths) to the /api/ location in deploy.yml, and to the student vhost if it uploads; confirm with nginx -T on the VPS.
- Decided on 16 Oct: The ESS sets its own upload limit in its own nginx block (ADR-0019). The Scheduler's /api/ limit stays as it is (ADR-0018).
- Notes: Until then any body over 1 MB likely gets nginx's HTML 413 before multer (inferred from nginx defaults). Ops step: check the VPS http{} block.
- Check: confirmed: deploy.yml sets no client_max_body_size anywhere: not in the scheduler vhost (323-411), its /api/ location (340-350) or the student vhosts (453-533). `git log -S client_max_body_size --all` is empty. Multer allows 10 MB x 10 files (hrPolicy.js:1259-1260; routes/hr.js:79), 5 MB for the photo (routes/me.js:16), and 15 MB in intakeController.js:15 and admissionUndertakingController.js:7. express.json() keeps its 100 kB default (server.js:103). ADR-0005:23-26 also puts the /api/ess location block, with its upload limit, in this same Scheduler deploy.yml, so change-existing-scheduler-code is right. Whether the VPS http{} block already raises the limit is still an ops check.
- Evidence:
  - .github/workflows/deploy.yml:323-411 - the scheduler vhost, including location /api/ at 340-350, sets no client_max_body_size; the student vhost (453-533) neither; git log -S finds no commit that ever set it
  - config/hrPolicy.js:1259-1261 - multer accepts 10 MB per file, 10 files
  - routes/me.js:14-16 - profile photo limit 5 MB
  - server.js:103 - express.json() with the default body limit (100 kB)

<a id="item-k2"></a>
#### K2: Health + minimum-app-version endpoint

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Nothing the app can call.
- What remains: A public GET under /api (nginx proxies only /api/) returning {ok, server_time, version/sha, min_app_version, latest_app_version, features}, with MIN_APP_VERSION / APP_VERSION added to the deploy heredoc.
- Decided on 16 Oct: Built in the ESS (team_app), on its own subdomain (ADR-0019).
- Notes: GET /api/health today answers 200 with the SPA's HTML, so a client that trusts the status code would read it as healthy.
- Check: confirmed: server.js:127-201 mounts no health or version route. GET /api/health matches no GET in mcpRoutes (routes/mcp.js), passes express.static and reaches the SPA catch-all (server.js:208-220), which answers 200 with HTML. The MCP 'health' tool (lib/mcp/tools/shared.js:4-19) is bot-only. GET /api/ceo/audit/health (routes/ceo.js:169) is the CEO's audit-ingestion panel, not an app health check, so it does not meet the task. APP_VERSION is read at services/audit.js:220 and lib/mcp/server.js:104 but never written by deploy.yml. Under ADR-0005 the endpoint lives in the ESS (/api/ess/...), with its version values in team_app's deploy env, so new-self-contained holds.
- Evidence:
  - server.js:127-201 - no health or version route; grep finds none
  - server.js:204-220 - an unknown GET under /api falls to express.static and the SPA catch-all: 200 index.html (404 text if the build is missing)
  - lib/mcp/tools/shared.js:4-19 - a 'health' tool exists only inside the MCP connector (bot OAuth on /mcp)
  - services/audit.js:220 and lib/mcp/server.js:104 - APP_VERSION is read with default '1.0.0' but the deploy heredoc (.github/workflows/deploy.yml:73-161) never writes it

<a id="item-k3"></a>
#### K3: FIREBASE_\* secrets in the deploy workflow with a length check

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: team_app
- What exists: Nothing.
- What remains: In team_app's ESS deploy job: write FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL and FIREBASE_PRIVATE_KEY_B64 (base64, one line) into .env without the Scheduler's unquoted-heredoc expansion (quote the delimiter or use printf). Add a 'Check the push configuration' step that prints lengths and says push is log-only while they are empty, and add firebase-admin to apps/ess-api. Ops: create the Firebase project and the team_app repository secrets.
- Decided on 16 Oct: Built in team_app's own deploy job (ADR-0005, ADR-0011).
- Notes: Ops prerequisite matches the user's question 14 (Firebase project and Play org account). Until keys exist, push should log like SMS console mode.
- Check: corrected: MISSING is confirmed. lands_in is corrected: the gap report assumed the Scheduler's workflow, but push is a new feature, and the accepted ESS design runs the push worker inside the ESS with its own deploy job and FIREBASE_\* check. No existing Scheduler code changes. Two evidence fixes: the './github' path typo, and the MCP check step is not lengths-only.
- Evidence:
  - .github/workflows/deploy.yml:73-161 - the Scheduler's .env heredoc writes Supabase, JWT, mail, SMS, HR, certificate, email-module and MCP values; no FIREBASE or FCM
  - .github/workflows/deploy.yml:204-241 - the MCP and SMS check steps, the pattern to copy; they print lengths, but the MCP step also prints the client id itself (:217)
  - .github/workflows/deploy.yml:73 - unquoted heredoc (&lt;&lt; EOF): $ and backticks in a secret are shell-expanded, and a multi-line PEM breaks the one-line .env
  - package.json:20-36 - no firebase-admin or other push dependency; grep for firebase, fcm or push tokens finds nothing in the backend
  - team_app/docs/adr/0005-separate-ess-service.md:30 and team_app/docs/adr/0011-ci-merge-and-auto-deploy.md:16-17 - the push worker runs inside the ESS, and the ESS's own deploy job writes .env from team_app secrets with a FIREBASE_\* length check (follows from KP's 16 Oct answers: separate service; /api/ess is for new features)

<a id="item-k4"></a>
#### K4: Per-employee rate limiting (same as A6)

- Gap report: UPDATE
- Now: **UPDATE**; the fix sits in: Scheduler code
- What exists: Per-IP limiters only (see A6).
- What remains: As A6: subject-keyed limiter for authenticated calls, IP + identifier for sign-in, route-level attachment.
- Notes: Duplicate of A6; build once.
- Check: confirmed: Same evidence and same work as A6, verified there (server.js:60-86,119-125; punchCodeLimiter.js:19-26). It is a duplicate, so build it once.
- Evidence:
  - server.js:80-86,125 - apiLimiter 60 s / 300 per IP on all /api
  - server.js:60-66,119 - loginLimiter 15 min / 20 per IP
  - server.js:72-78,120-124 - one shared otpLimiter 15 min / 10 per IP
  - middleware/punchCodeLimiter.js:19-26 - punch sign-in 15 min / 40 per IP

<a id="item-k5"></a>
#### K5: Ping purge job (retention) + 180-day access-log retention (not built: KP deletes by hand, ADR-0015)

- Gap report: MISSING
- Now: **MISSING (not built, ADR-0015)**; the fix sits in: Scheduler code
- What exists: Nothing. Pings, punch attempts and the DB logs grow forever, and nginx log retention is whatever the VPS's own log rotation does, outside the repo.
- What remains: (1) A purge job: a SQL function plus a node-cron registration in scheduledJobs.js beside the attendance jobs (710-719). It deletes hr_attendance_pings older than the chosen period. Decide the same for the latitude, longitude, ip and user_agent columns of hr_attendance_punches, while keeping the attendance records themselves for 5 years. (2) Access-log retention. The DB logs (audit_events, audit_access_log, user_security_events, ops_bot_call_log) are never deleted today. That meets a 'keep at least 180 days / one year' minimum by default, but nothing deletes them after the period; add purges if RVM sets a maximum. The nginx and pm2 logs are an OPS step on the VPS: confirm logrotate keeps at least the chosen period, since the repo sets nothing. (3) Optionally, record HR reads of location (GET /attendance-admin/trail and /punches) in audit_access_log or audit_events. RVM chooses the period.
- Decided on 16 Oct: Not built. KP deletes old pings and logs by hand (ADR-0015).
- Notes: The period is RVM's decision. The report says 180 days; the earlier compliance note recommends one year from May 2027 (DPDP Rules). Those are legal points that cannot be checked in code. Retention here means both keeping logs at least that long and deleting them afterwards, and the repo does neither.
- Check: corrected: MISSING is right. lands_in is corrected from 'both': every code piece edits existing Scheduler jobs, tables or controllers (a cron in scheduledJobs.js, deletes from existing tables, optional audit calls in attendanceAdminController.js). Nothing is self-contained, and the nginx/pm2 part is OPS. The scheduler vhost runs 323-411, not 323-399. Precision: 'the repo does neither' is half true. DB logs are kept forever, so the minimum is met by default; what is missing is deletion and a web-server log policy.
- Evidence:
  - scheduledJobs.js:691-811 - none of the registered cron jobs purges or applies retention; git grep finds no purge script in scripts/ or migrations
  - controllers/hr/attendancePunchController.js:602,607 + controllers/hr/attendanceAdminController.js:245 - hr_attendance_pings is only inserted and selected, never deleted
  - config/auditPolicy.js:258 - 'audit.retention.purged' is registered as an action name, but no job implements it
  - supabase/migrations/20261016000000_audit_events.sql:58-138,187-206 - audit_events (actor_ip, actor_user_agent at 86-87) and audit_access_log, with no retention
  - supabase/migrations/20260909000000_user_profile_security.sql:102-115 - user_security_events (ip, user_agent), with no retention
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:98-123 - every punch attempt keeps ip, UA and location, with no retention
  - controllers/hr/attendanceAdminController.js:1-5,240-253 - reading a person's location trail writes no audit or access record
  - [backend] .github/workflows/deploy.yml:323-411 - the scheduler nginx vhost written on every deploy has no access_log or rotation directive (none anywhere in the file)

<a id="item-k6"></a>
#### K6: Play Integrity / Keystore key verification server-side; device binding id

- Gap report: MISSING
- Now: **MISSING**; the fix sits in: Scheduler code + team_app
- What exists: Cookie-based one-phone binding; a native app can replay the cookie value in its own Cookie header (readCookie parses req.headers.cookie) with no backend change.
- What remains: Accept an install id and a registered Keystore public key (new columns or table), verify a Keystore-signed punch or a Play Integrity token (nonce bound to the punch challenge, MEETS_DEVICE_INTEGRITY) on punch and ping, store verdicts as flags, and a migration path for people already bound through a browser cookie.
- Decided on 16 Oct: No Play project yet: verification is built behind a switch that stays off (ADR-0016).
- Notes: Needs Google Cloud/Play Console setup and a service-account secret (deploy heredoc again). Play Integrity stays off until keys exist (user's question 14).
- Check: confirmed: Verified: the phone's identity comes only from the rvm_att_dev cookie (attendancePunch.js:54-67), which the server mints and sets HttpOnly with Path=/api/hr/my-attendance (69-90). Device verdicts and first-punch registration key on its hash (attendancePunchController.js:156-167,369-378,440-452), and the OTP requester identity reuses it (attendanceOtpController.js:195-198). hr_attendance_devices holds only token_hash, user_agent and bound_ip (20261020000000:77-93). No integrity, attestation, keystore or public-key code exists anywhere. Verification belongs in the existing punch and ping handlers (ADR-0007:19) and needs new columns or a table, so 'both' is right. ADR-0016:17 keeps it behind an off switch until a Play project exists. Related: HR can revoke devices only one at a time (routes/hr.js:212), which matters for decision 11's bulk reset.
- Evidence:
  - services/attendancePunch.js:54-67 - the phone's identity is read only from the rvm_att_dev cookie (20-200 base64url chars)
  - services/attendancePunch.js:69-90 - the server mints that token and sends it once via Set-Cookie (HttpOnly, Path=/api/hr/my-attendance)
  - controllers/hr/attendancePunchController.js:156-167,369-378,440-452 - identifyDevice verdicts and first-punch registration keyed on the cookie hash
  - controllers/hr/attendanceOtpController.js:195-198 - the OTP requester identity uses the same cookie
  - supabase/migrations/20261020000000_hr_attendance_punch.sql:77-93 - hr_attendance_devices holds token_hash, user_agent, bound_ip: no install id, public key or attestation fields
  - grep for integrity/attestation/keystore - nothing server-side

## Appendix: cross-cutting findings, as checked

Each reader listed what the task list misses; each checker confirmed, corrected or refuted those findings. Both lists are kept as written.

### Identity and platform (A, K)

Found by the reader:

- REPORT portal JWT: payload {userId: users.id, role, locationId: users.location_id, username, locationName (the branch typed at login; at login/verify the client-echoed location_name, unvalidated), isSuperAdmin: role in ceo|super_admin|accounts_admin} plus id = users.faculty_id for faculty and hod; jsonwebtoken default HS256 over JWT_SECRET, iat+exp, expiresIn 64h, no aud/iss/sub/jti, no refresh. Evidence: controllers/userController.js:498-512; controllers/authSecurityController.js:20-31,60,80; config/roles.js:83-89,136. auth.js re-reads role and location from the DB each request (middleware/auth.js:80-98), so claims are advisory. A third kind, the student token {id, role:'student', name, location_id}, 7 days, JWT_SECRET (userController.js:797-801), is also accepted by auth.js:19-43.
- REPORT punch-only session: payload {k:'punch', e:&lt;hr_employees.id uuid>, m:'otp'|'pw'} + iat/exp, audience 'rvm-punch', HS256 over sha256hex('rvm-punch-session:' + JWT_SECRET), expiresIn 30d. readPunchSession requires HS256, aud rvm-punch, k==='punch', e a UUID, and returns {employeeId, method, issuedAt: iat\*1000}. Usable only while issuedAt >= sessions_valid_from (whole seconds) and the login is active; /password needs an otp session under 15 minutes old or a pw session still on HR's password. Evidence: services/attendancePunch.js:205-242,266; services/attendanceAccounts.js:39-53; controllers/hr/attendanceOtpController.js:345-354.
- REPORT 401 answers: middleware/auth.js:8-12 missing or empty header -> 401 {error:'No token provided'}; auth.js:102-105 any verify failure (bad signature including a punch session, expired, malformed, missing secret) or user/student not found -> 401 {error:'Please authenticate'}; neither has a code. Only the literal 'Bearer ' is stripped (auth.js:8), so 'bearer x' fails. middleware/punchAuth.js:21-34 never answers itself: a valid punch session calls next(), anything else goes to auth (same two 401s). Later, in the punch controller: 401 NOT_AUTHENTICATED 'Please sign in.' (attendancePunchController.js:105), 'Please sign in again.' when the session's employee row is gone (:110), 'Your password was changed. Please sign in again.' (services/attendanceAccounts.js:49-51); a missing or disabled attendance login is 403 NO_ATTENDANCE_LOGIN (attendanceAccounts.js:40-45) and an exited employee 403 NOT_ACTIVE (attendancePunchController.js:113). allowRoles and staffOnly also answer 401 'Please authenticate' (allowRoles.js:15-17, staffOnly.js:6-8). App sign-out rule: 401 with those two messages or code NOT_AUTHENTICATED, plus 403 NO_ATTENDANCE_LOGIN; never on other 401s.
- REPORT rate limiters in server.js (express-rate-limit 8.5.1, package-lock.json:1967-1969): loginLimiter windowMs 15 min, max 20, default key req.ip, message 'Too many login attempts. Please try again in 15 minutes.', mounted /api/users/login (covers /login/verify) - server.js:60-66,119. otpLimiter 15 min, max 10, default key, 'Too many code requests. Wait fifteen minutes and try again.', one instance (one bucket per IP) on /api/users/forgot-password (+/confirm), /api/me/email/request, /api/me/phone/request, /api/me/two-factor/request, /api/admissions/undertaking-otp/request - server.js:72-78,120-124. apiLimiter 60 s, max 300, default key, 'Too many requests. Please slow down.', all of /api - server.js:80-86,125. None sets keyGenerator, skip or store (memory store, reset on restart); 429 bodies carry no code; trust proxy 1 (server.js:100). Outside server.js: punchCodeLimiter 15 min / 40 per IP, code RATE_LIMITED, off under NODE_ENV=test (middleware/punchCodeLimiter.js:19-26); mcpLimiter 60 s / 60 (routes/mcp.js:30-36); sendLimiter 60 s / 10 (routes/email.js:60-66,111); exportLimiter 1 h / 5 (routes/ceo.js:42-48,181). The v8 default key also masks IPv6 to /56 (library default; node_modules not in the worktree, not verified).
- Prefix-mounted limiters can probably be skipped with a doubled slash (INFERRED, not executed): server.js:119-124 attaches loginLimiter and otpLimiter by path prefix, and the codebase itself says a prefix mount is skipped by '//' while the router still reaches the handler (middleware/punchCodeLimiter.js:7-11). nginx proxy_pass without a URI forwards the raw URI (.github/workflows/deploy.yml:341). So /api/users//login and /api/users//forgot-password likely reach their handlers under only the 300/min apiLimiter, and portal login has no per-account lockout (userController.js:426-454 just answers 401 'Invalid password'). Any re-keyed limiter (A6/K4) should be attached per route, or the URL normalised first.
- Committed database dump with credential material: physical_dump_2026.sql (19.4 MB, tracked since f00be35, 2026-04-04) has INSERT INTO public.users (id, username, phone_number, password_hash, role, ...) at line 240 and INSERTs into auth.users (encrypted_password), auth.sessions and auth.refresh_tokens at lines 46, 78 and 137, plus students, payments and receipts. Anyone with repo read access holds every April username + phone pair, which is all POST /api/users/reset-password needs, plus offline-crackable bcrypt hashes. This makes A9 urgent; if any app still uses Supabase Auth on this project, treat those refresh tokens as compromised; removing the file from history is an ops task. (Only column headers were looked at.)
- Legacy reset injection (A9): controllers/userController.js:1201,1213 interpolate the raw username into .or(`username.eq.${username},phone_number.eq.${username}`); login fixed exactly this by quoting (userController.js:263-279). A 'username' containing a comma can likely add an always-true condition, leaving the phone number as the only check (INFERRED from PostgREST or= grammar, not executed).
- Shared first-time password risk: bulk create can give one HR password to every new attendance login (controllers/hr/attendanceAccountsController.js:207-243; one hash for all at :225), password sign-in accepts an employee code (attendanceOtpController.js:118-126), and a pw session still on HR's password may set a new password (attendanceOtpController.js:346-351). Anyone who knows the shared default and a colleague's code can sign in first, choose that colleague's password and, with a second phone, register it as the colleague's phone. The server does not enforce the brief's advice to prefer 'Get a code' for the first sign-in.
- Exit does not end portal access: auth.js (middleware/auth.js:14-100) never reads hr_employees, and no exit code writes users (no users update/delete in controllers/hr/exitController.js, scheduledJobs.js or services; the only migration UPDATE of users is a location cleanup at supabase/migrations/20260530000003_missing_fkeys.sql:89). An exited employee keeps signing in and using every portal route; only /my-attendance refuses them (attendancePunchController.js:113). A3's 'revoked on exit' needs a refresh-time check and A7 or an exit hook for existing tokens.
- Two parallel portal change-password endpoints: POST /api/users/change-password (routes/user.js:49; userController.js:1285-1341) takes 6 characters, does not stamp password_changed_at and writes no user_security_events row, while POST /api/me/password (profileController.js:260-279) takes 8, stamps it and records the event. Align or retire the first before building A7.
- The report's model for A3 has a race: lib/mcp/oauth.js:235-251 reads the refresh row and then marks it consumed by id without a consumed_at IS NULL guard, so parallel reuse is not detected; family revocation is 'every token of that bot' (:240-243) and nothing binds to an install. The compare-and-set used for OTP attempts (attendanceOtpController.js:290-295) is the pattern to copy.
- The report is stale for this group: A1 and A2 were true MISSING at d2595e4 but git diff d2595e4..c28b9ca adds middleware/punchAuth.js (+34), middleware/punchCodeLimiter.js (+26), services/attendancePunch.js (+301), services/attendanceAccounts.js (+71), controllers/hr/attendanceOtpController.js (+449) and attendancePunchController.js (+618). Line references moved: the 64h expiresIn is authSecurityController.js:30 (not 29), and resetPassword is userController.js:1175 (953 now closes deleteUser). Limiter config itself is unchanged since d2595e4 except one more otpLimiter mount (server.js:124).

Checked:

- Portal JWT payload: CONFIRMED. userController.js:498-512 and authSecurityController.js:20-31 sign {userId, role, locationId, username, locationName, isSuperAdmin} with JWT_SECRET for 64h, adding id=faculty_id for TEACHING_ROLES (roles.js:136); there is no aud, iss, sub or jti. SEES_ALL_LOCATIONS is ceo, super_admin and accounts_admin (roles.js:83-89). login/verify echoes the client's location_name without validating it (authSecurityController.js:60,80). The student token is at userController.js:797-801. One nuance: the role claim is not wholly advisory. auth.js uses it to choose the lookup (the student table, or users.faculty_id for faculty and hod, auth.js:19-66); RBAC and location do come from the DB row (80-98).
- Punch-only session: CONFIRMED. attendancePunch.js:205-239 shows the payload (k, e, m), aud rvm-punch, HS256, the key sha256hex('rvm-punch-session:'+JWT_SECRET) and 30 days. readPunchSession checks k and that e is a UUID, and returns issuedAt as iat\*1000. sessionCutoff uses whole seconds (:266), sessionProblem is at attendanceAccounts.js:39-53, and the /password window and HR-password rule are at attendanceOtpController.js:345-354.
- 401 answers: CONFIRMED, with one addition. auth.js also answers 401 'Please authenticate' when the users or students lookup itself errors (auth.js:20-28 and 68-72 throw into 102-105). A Supabase outage therefore looks exactly like a bad token, and the proposed app sign-out rule would sign everyone out during one; the app should re-check before signing out. A 'Bearer ' header with no token gives 'No token provided'. The rest checks out: auth.js:8-12, punchAuth.js:21-34, attendancePunchController.js:105,110,113, attendanceAccounts.js:40-51, allowRoles.js:15-17 and staffOnly.js:6-8. handle() passes exposed 401/403 codes through (controllers/hr/_shared.js:117-140).
- Rate limiters: CONFIRMED. server.js:60-86,100,119-125; express-rate-limit 8.5.1 (package-lock.json:1967-1968). None of the server.js limiters sets keyGenerator, skip or store, and their 429 bodies carry no code. punchCodeLimiter.js:19-26 has code RATE_LIMITED and skips under NODE_ENV=test. mcpLimiter (routes/mcp.js:30-36) guards /mcp/register, /mcp/token and /mcp. sendLimiter (routes/email.js:60-66,111) does carry a code, SEND_RATE_LIMITED. exportLimiter is at routes/ceo.js:42-48,181. The IPv6 /56 default stays unverified, since node_modules is not in the worktree.
- Doubled-slash limiter bypass: CONFIRMED as an inference (not executed). Express is 4.22.1 (package-lock.json:1921-1922). app.use('/api/users/login', loginLimiter) cannot match '/api/users//login', while app.use('/api/users', userRoutes) consumes '/api/users/' and hands the router '/login'. nginx's proxy_pass with no URI (deploy.yml:341) forwards the client's URI unchanged, and the codebase itself documents the trap (punchCodeLimiter.js:7-11). Portal login has no per-account lockout (userController.js:426-454); 'auth.login.throttled' is registered (auditPolicy.js:144) and emitted nowhere.
- Committed DB dump: CONFIRMED (only headers were inspected). physical_dump_2026.sql is tracked, 19,418,417 bytes, added in f00be35 on 2026-04-04. Its INSERT headers are auth.users with encrypted_password at line 46, auth.sessions at 78, auth.refresh_tokens at 137, and public.users (id, username, phone_number, password_hash, role, faculty_id, created_at, location_id) at 240. INSERTs for students, payments and receipts are present. It is worse than stated: per the A9 correction the legacy reset needs only the phone number, and the dump holds it for every April account.
- Legacy reset injection: CONFIRMED, and understated. userController.js:1201 and 1213 interpolate the raw value into .or(), but no injection is needed. The same .or() matches phone_number.eq.&lt;the typed username>, ANDed with phone_number = the typed phone (1202, 1214). Entering an account's phone number in both fields resets it, with a 409 only when two accounts share that value. This is inferred from the filter, not executed.
- Shared first-time password risk: CONFIRMED. bulkCreate uses one hash for everyone when a common password is given (attendanceAccountsController.js:220-225,232). password-login accepts an employee code (attendanceOtpController.js:118-126). A pw session still on HR's password may set a new one (346-351). The first accepted punch from an unregistered phone registers that phone (attendancePunchController.js:371-378,440-452). Nothing on the server forces 'Get a code' first.
- Exit does not end portal access: CONFIRMED. auth.js never reads hr_employees. Nothing in controllers/hr, services or scheduledJobs.js updates or deletes users; from('users') appears there only as reads (hrPeople.js:129, hrPipeline.js:78, interviewNotify.js:87). The only migration UPDATE of users is 20260530000003_missing_fkeys.sql:89. Only the punch routes refuse an exited employee (attendancePunchController.js:89-90,113).
- Two change-password endpoints: CONFIRMED. routes/user.js:49 leads to userController.js:1285-1341: 6 characters, no password_changed_at and no user_security_events row, though it does write the audit row auth.password.changed (1326-1333). /api/me/password (profileController.js:260-279) requires 8 characters, stamps password_changed_at and records password_changed.
- MCP refresh race: CONFIRMED. consumeRefreshToken reads the row, then updates it by id with no .is('consumed_at', null) guard (oauth.js:235-251). Family revocation means every token of the bot (240-243), and nothing binds a token to an install. consumeAuthCode has the same unguarded consume (211-221). The OTP compare-and-set (attendanceOtpController.js:290-295) is the right pattern to copy.
- Report staleness: CONFIRMED. There are 97 commits in d2595e4..c28b9ca, and the six files add +34, +26, +301, +71, +449 and +618 lines (1,499 in all). At d2595e4 the 64h expiresIn was at authSecurityController.js:29 and resetPassword began at userController.js:953. Limiter windows and maxima are unchanged; the only new mount is server.js:124.

### Attendance and data model (B, I, K5)

Found by the reader:

- The report's MISSING verdicts are mostly stale for this group. Of the 11 items it marked MISSING, 8 already exist at c28b9ca: B6, B7, B9, B10, B11, B12, B13 and B17. B8 exists in part: cookie binding and HR reset exist, but the header and Keystore do not. Only B14 (is_mock), B15 (batch pings and purge) and K5 (retention) are truly missing. Evidence: supabase/migrations/20261020000000_hr_attendance_punch.sql, supabase/migrations/20261022000000_hr_attendance_shifts.sql, services/attendanceSettle.js:37-163, scheduledJobs.js:710-719.
- The brief has the field names wrong. The punch and ping bodies use latitude and longitude, not lat and lng (services/attendancePunch.js:144-153; the web sends {latitude, longitude, accuracy_m}: [frontend] client/lib/services/attendance.ts:116,143-147). A client sending lat/lng gets 422 LOCATION_MISSING on punch, stored as a refused attempt, and 400 on ping. A note over 200 characters is cut silently, not refused (controllers/hr/attendancePunchController.js:326).
- A ping answers 204 in four different cases and never 403 or 429. The cases are: HR-password session, phone not 'own' (including revoked), not punched in today, and under 60 s since the last stored ping (controllers/hr/attendancePunchController.js:593-605). A native tracker cannot tell being throttled from 'not your phone' or 'day closed'. It has to re-read GET /my-attendance (device.this_phone, today.punched_in) to know when to stop. The only 429 comes from the global /api limiter, which carries no code (server.js:80-86,125).
- Native clients break as things stand. The existing flutterapps Scheduler HTTP client has no CookieManager and no User-Agent override ([flutterapps 4712b91] packages/core_network/lib/src/dio_factory.dart:29-42). Out of the box every punch gets 403 NOT_MOBILE. Once the UA is fixed, the first punch registers a cookie that is then lost, and every later punch gets 403 DEVICE_NOT_REGISTERED (services/attendancePunch.js:34-36,55-67; controllers/hr/attendancePunchController.js:371-373). Phones already registered from a browser are also locked out of the app until HR resets them (controllers/hr/attendanceAdminController.js:280-293). Rollout needs an HR bulk reset or a transfer flow.
- GET /api/hr/staff-attendance has no branch fence on read. An admin_manager can read every branch's rows, HR remarks, employees' own remarks and CL days. The branch fence exists only on marking and remarks (controllers/hr/staffAttendanceController.js:60-176 never calls branchFence; the fence is at 201-209, 232-236 and 292-302). This matters if the app's leader view reuses this endpoint for Admin Managers.
- No attendance view is scoped to a manager or team. Every leader view is role-scoped (config/hrPolicy.js:49-72), and nothing in the attendance controllers or services uses hr_employees.manager_id (grep: no hits). The app's 'My Team' for HOD, HoO or reporting managers therefore needs a new endpoint.
- Attendance admin actions and location reads are not in the audit trail. attendanceAdminController.js and attendanceShiftsController.js import no audit service (lines 1-6), so geofence and exemption changes, phone resets, shift and holiday edits, and reads of the location trail or punch log write no audit_events or audit_access_log row. Only allowRoles refusals are audited (middleware/allowRoles.js:18-30). Overrides do keep their own append-only log (20261020000000:149-162), and a revoked phone keeps revoked_by and its reason on the device row. This matters for K5 and for DPDP, because location data has no access log.
- Code at c28b9ca does not prove the features are live. Shifts, holidays, late rules, the auto-fill and employee remarks switch off silently when migrations 20261022000000 or 20261023000000 are missing: reads fall back to empty, recompute becomes a no-op, and the auto-fill writes nothing (services/attendanceRules.js:20-39,87-126,221-231; services/attendanceSettle.js:119-121,157-160). Project notes say these migrations were applied by hand after deploy, or were still pending. Confirm read-only (the PostgREST OpenAPI listing) before treating B5 or B9-B12 as live in production.
- The remarks endpoint skips the first-time-password rule (controllers/hr/attendancePunchController.js:564-588; compare 293, 323 and 593). HR can give a whole batch one common first-time password (controllers/hr/attendanceAccountsController.js:202-242), and password sign-in accepts an employee code (controllers/hr/attendanceOtpController.js:134-140). So anyone who knows a colleague's code can write remarks on that colleague's days without setting a password. The same endpoint's 503 names 20261022000000 instead of 20261023000000 (services/attendanceRules.js:25,31-39).
- The punch-out geofence plus the missing correction path makes regularisation urgent. OUTSIDE_GEOFENCE applies to punch-out too (controllers/hr/attendancePunchController.js:399-413), so someone who leaves before punching out cannot punch out. The day then becomes a 'No punch-out' half day at 00:05 (services/attendanceSettle.js:73-91). An accidental punch-out ends the day with DAY_DONE (controller:420). No employee request API exists (routes/hr.js:183-203), so only an HR override fixes any of these. Attendance regularisation requests deserve higher priority than the report gives them.
- A separate team_app backend is not self-contained at the edge or in the data. nginx proxies all of /api/ to the Scheduler on :3000, and deploy.yml rewrites the vhost on every deploy ([backend] .github/workflows/deploy.yml:322-350), so /api/ess needs a location block added by a Scheduler PR. Every attendance table is RLS deny-all and reachable with the service key only (20261020000000:368-383; 20261022000000:303-311). A second service would therefore need the service-role key and would have to reimplement the guards, the recompute call and the source='override' lock. Any approval that writes a day changes existing Scheduler data and cannot be 'new-self-contained'.
- The 41 off-portal staff can reach only /my-attendance. Their punch-only session is signed with a key derived from JWT_SECRET, and auth.js verifies against JWT_SECRET itself, so every other route refuses it (middleware/punchAuth.js:4-20; services/attendancePunch.js:187-204; middleware/auth.js:14). The attendance endpoints in this group work for them, but any ESS endpoint outside /my-attendance (requests, leave, profile, documents) needs an auth path that accepts these staff.

Checked:

- 1 (stale MISSING verdicts) - CORRECTED: the report marked 12 items in this group MISSING (B6-B15, B17, K5), not 11. At c28b9ca, 7 exist as written (B6, B7, B9, B10, B11, B12, B13). 2 exist in part: B8 has no device header or Keystore key, and B17's lock covers only source='override', not a future approved-request source. 3 are absent (B14, B15, K5).
- 2 (brief field names) - PARTLY REFUTED: the brief does not have them wrong. doc-export-after.md:158 and the pre-fact-check doc-export.md:158 both say 'kind, nonce, latitude, longitude, accuracy_m, client_at'; 'lat, lng' is the gap report's paraphrase. The code facts are confirmed. readFix reads latitude and longitude (attendancePunch.js:144-153), and the web sends them (attendance.ts:116,143-147). lat/lng gets a stored 422 LOCATION_MISSING (controller 394), after the UA, device and challenge checks. On ping it gets 400 only after the 204 checks (599-600). The note is cut at 200 characters (326).
- 3 (ping 204s) - CONFIRMED with one precision: the four 204 cases (593, 595, 598, 605) and the limiter being the only 429 (server.js:80-86,125) are right. 'Never 403' holds only for the device, day and throttle cases. The same ping can still 403 with NOT_LINKED, NOT_ACTIVE or NO_ATTENDANCE_LOGIN from loadEmployee (592; 101-119; attendanceAccounts.js:39-45).
- 4 (native clients break) - CONFIRMED: the Scheduler Dio has no CookieManager and no User-Agent (dio_factory.dart:29-42); git grep finds no user-agent setting in flutterapps. The Dart default UA fails MOBILE_UA (attendancePunch.js:35). Without the cookie the phone is 'unknown' while a device is active, which gives DEVICE_NOT_REGISTERED (371-373). The only reset is one at a time (attendanceAdminController.js:280-293).
- 5 (no branch fence on read) - CONFIRMED: read (staffAttendanceController.js:60-176) accepts any branch_id or employee_id and never calls branchFence. The fence exists only at 201-209, 232-236 and 292-302. HR_ATTENDANCE_ROLES includes admin_manager (hrPolicy.js:49-54).
- 6 (no team-scoped view) - CONFIRMED: git grep for manager_id in controllers/hr/attendance\*.js, staffAttendanceController.js and services/attendance\*.js returns nothing. Every attendance route is guarded by a role set only (routes/hr.js:176, 206, 232).
- 7 (admin actions not audited) - CONFIRMED: git grep finds no recordAudit or audit import in attendanceAdminController, attendanceShiftsController, attendanceAccountsController, staffAttendanceController or attendancePunchController. allowRoles audits only refusals (allowRoles.js:18-30). Overrides keep their own log (20261020000000:149-162), and revokes keep revoked_by and revoke_reason (attendanceAdminController.js:284-289).
- 8 (code does not prove live) - CONFIRMED as a caution: the fallbacks are real (attendanceRules.js:20-39, 87-126, 221-231; attendanceSettle.js:56-61, 119-121, 157-160). The project notes contradict each other. team_app_oct2026.md line 15 says 20261023000000 was NOT applied, line 13 says the remarks migration was applied, and line 17 says 20261022000000/1 were not applied at deploy. A read-only production check is still needed.
- 9 (remarks skip first-time-password rule) - CONFIRMED and understated: myRemarks (564-588) never calls passwordChangeDue. bulkCreate can give everyone one common password (attendanceAccountsController.js:220-233), and password-login accepts an employee code (attendanceOtpController.js:118-126,137-141). Worse, the same HR-password session may SET the password (attendanceOtpController.js:346-351). Anyone who knows the shared first-time password and a colleague's code can take over that colleague's attendance login before the colleague changes it. If the colleague has no registered phone yet, a second browser or device of theirs becomes the colleague's phone on the first punch. Recovery is 'Get a code' or an HR reset.
- 10 (regularisation urgent) - CONFIRMED: OUTSIDE_GEOFENCE applies to both kinds (controller 408-410). Settle closes open days on completed pairs with 'No punch-out' (attendanceSettle.js:73-91), and recompute makes a closed day under 240 minutes a half day (20261022000000:260-269). DAY_DONE is at 420. routes/hr.js:183-203 has no request route. The employee's only other action is a remark, which changes nothing.
- 11 (separate backend not self-contained) - CONFIRMED: deploy.yml:322-350 writes the /api/ -> :3000 location with tee on every deploy, and the vhost runs to 411. Every attendance table is RLS deny-all (20261020000000:368-383; 20261022000000:303-311; 20261021000000:49-51; 20261023000000:21-23). The lock and the recompute call live in Scheduler code (staffAttendanceController.js:350; attendanceRules.js:221-231).
- 12 (off-portal staff reach only /my-attendance) - CONFIRMED for the mechanism: punchAuth.js:21-34; the key is derived as sha256('rvm-punch-session:'+JWT_SECRET), with audience rvm-punch (attendancePunch.js:209-239); auth.js:14 verifies with JWT_SECRET itself; git grep finds no jwt.decode anywhere. The '41' comes from the brief and the notes, not from the code. punchAuth is an ordinary middleware that new ESS routes could reuse.

### Requests and inbox (C, D)

Found by the reader:

- C11 is a live production problem, not only an app gap: since ALL_STAFF_FROM = 2026-10-15 the nightly fill-in writes 'absent' / 'No punch' for every employed hr_employees row with no day row, and approved faculty leave (/api/am/leave) never writes hr_staff_attendance, so faculty on approved leave are being auto-marked absent wherever migration 20261022000000 is applied. Evidence: services/attendanceSettle.js:99-100,116-152,157-160; controllers/leaveController.js:150-156,255-257.
- hr_attendance_apply_override is not a safe building block as is: the SQL has no day or status guard (the six-status list and 'future only for leave' live only in controllers/hr/attendanceAdminController.js:15,57-60), it hard-codes source 'override' and note = reason, logs into hr_attendance_overrides, and recompute runs after it, outside its transaction (attendanceAdminController.js:122-124). Evidence: supabase/migrations/20261020000000_hr_attendance_punch.sql:290-341.
- The one-CL-a-month unique index may be missing in production: 20261022000000 creates it only if nobody already has two CLs in a month, otherwise it skips with just a NOTICE. Concurrent approvals would then rely on the app check alone; verify with a read-only pg_indexes query. Evidence: supabase/migrations/20261022000000_hr_attendance_shifts.sql:129-146.
- Code ships ahead of hand-applied migrations: missing columns or functions switch the rules off rather than fail (services/attendanceRules.js:20-39) and settle skips (services/attendanceSettle.js:56-60,157-160). Before ESS functions call hr_attendance_recompute or rely on source 'auto' or the CL index, confirm 20261020000000 through 20261023000000 are applied in production.
- WFH and on-duty approvals collide with the punch path: away from the branch every punch is refused OUTSIDE_GEOFENCE unless the person is permanently geofence_exempt. The task list does not say whether those days are punched; if they are, the existing punch controller needs a day-level exemption. Evidence: controllers/hr/attendancePunchController.js:399-413; supabase/migrations/20261020000000_hr_attendance_punch.sql:57-59.
- 'Short leave 120 min' has no data model: only late_excused exists; early exits have no excuse flag and matter only through the 240-minute half-day rule on self_punch rows. Its meaning must be defined before C3, C6 and C7. Evidence: supabase/migrations/20261022000000_hr_attendance_shifts.sql:111-123,260-269; services/attendancePunch.js:20.
- Attendance-only staff (no users row) are outside every existing feature in this group: priority_tasks.assigned_to and request-history actor columns reference users(id), and their punch session works only on /my-attendance. New ESS tables should key actors, approvers and recipients on hr_employees.id, and the ESS identity middleware is a prerequisite for C3-C12 and D1-D8. Evidence: supabase/migrations/20260814000001_reporting_discipline_and_priority_tasks.sql:39; supabase/migrations/20260923000000_inventory_requests.sql:215; middleware/punchAuth.js:17-34; services/attendancePunch.js:194-212.
- The report's D2 citations are stale: at c28b9ca routes/priorityTasks.js:17 is a comment and the guard is allowRoles(PARTICIPANTS) at 20-25; config/reportingPolicy.js:69 is the COMPLIANCE_VIEW_ROLES comment, and named recipients come from TASK_NAMEABLE_BY (101-105). Only broadcasts are still limited to admin_manager/admin (107-115), by RVM's design.
- /api/alerts/\* has no role check: GET /pending, POST /:id/resolve and POST /bulk-resolve use auth plus a location match only, so any signed-in token at a branch (auth admits student tokens with their location_id) can read other students' names and admission numbers in pending alerts and mark them resolved. Evidence: routes/alertsRoutes.js:10-17; controllers/alertsController.js:17-63,174-205,218-240; middleware/auth.js:19-42.
- Deploy writes .env through an unquoted heredoc and the check steps read single lines: a multi-line Firebase service-account private key would break .env, and any '$' or backtick in a secret is shell-expanded. Store FIREBASE credentials base64-encoded on one line, and add both the heredoc line and a check; a secret set in GitHub but not in the heredoc never reaches the server (the FAST2SMS precedent). Evidence: .github/workflows/deploy.yml:71-73,98-101,128-135,161,169.
- Two leave systems would coexist for faculty: /api/am/leave (an admin applies for a faculty_id, planned/emergency, AM then HoO) and the planned ESS CL/LWP. The task list does not decide which one faculty use, and syncFacultyLeaveColumns keeps only the last approved range on faculty. Evidence: routes/amOps.js:80-84; controllers/leaveController.js:57-122,150-156,223-246.
- HR's own counters disagree on non-CL leave: a blank leave type is stored as 'leave', which the dashboard counts as unpaid while the history counts only 'lwp' as lwp. Balances (C5) must pick one rule. Evidence: services/attendanceRules.js:52-59; controllers/hr/attendanceShiftsController.js:379,522-523.
- Use ATTENDANCE_OVERRIDE_ROLES (hr, ceo, super_admin) for 'decide any' and 'HR cancels'. HR_ROLES and HR_WRITE_ROLES include hr_executive, which RVM excluded from attendance, and the recommendation is that HR Executive does not decide leave or attendance requests. Evidence: config/hrPolicy.js:21-41,68-72.
- C10 depends on login links and branch names: the user-link backfill left most HR records unlinked for HR to finish, and an Admin Manager's branch is matched to hr_branches by name only. If 'the branch Admin Manager' becomes an approver option, that name match is the only link. Evidence: supabase/migrations/20260910000000_hr_employee_user_link.sql:21-32; controllers/hr/staffAttendanceController.js:196-209.
- Even 'new-self-contained' items need a one-line edit to server.js to mount /api/ess (all routers are mounted at server.js:127-201).

Checked:

- 1 (C11 is a live production problem): CONFIRMED, with a caveat. leaveController.js:150-156,255-257 writes only faculty.leave_\*. attendanceSettle.js:99-100,116-152 inserts absent/'No punch'/auto for every employed hr_employees row with no day row (unshifted staff from 2026-10-15), and 157-160 drops the insert until 20261022000000 allows 'auto'. It happens only when nobody marked that day as leave on the sheet or by override, and only on working days.
- 2 (hr_attendance_apply_override is not a safe building block): CONFIRMED. 20261020000000_hr_attendance_punch.sql:290-341 has no day or status check, hard-codes source 'override' and note = p_reason, and logs to hr_attendance_overrides. The guards live in attendanceAdminController.js:15,57-60, and ensureSnapshot/recompute are separate calls at 122-124. Also: overridden_by (156) and hr_staff_attendance.marked_by (20261015000004:23) reference users(id), so an attendance-only approver could be recorded only by name.
- 3 (one-CL index may be missing in production): CONFIRMED. 20261022000000_hr_attendance_shifts.sql:132-146 skips the index with only a NOTICE when anyone already has two CLs in a month, and Rules.clTaken is a read-then-write check that two concurrent approvals could both pass.
- 4 (code ships ahead of hand-applied migrations): CONFIRMED. attendanceRules.js:20-39,221-231 turn the rules off on a missing table, column or function; attendanceSettle.js:56-60,157-160 skip. Migrations 20261020000000, 20261021000000, 20261022000000, 20261022000001 and 20261023000000 are all in the repo and applied by hand.
- 5 (WFH/on-duty collide with the punch path): CONFIRMED on the collision: attendancePunchController.js:399-413 refuses OUTSIDE_GEOFENCE or BRANCH_NOT_CONFIGURED unless the permanent geofence_exempt is set. REFUTED on 'the task list does not say whether those days are punched': the brief's request table says WFH 'punching works outside the geofence and location is still recorded' and on duty 'the geofence is waived that day'. A day-level waiver in the existing punch controller is therefore required, not optional.
- 6 (short leave has no data model): CONFIRMED that no field exists (only late_excused, 20261022000000:111-123). PARTLY REFUTED on 'its meaning must be defined': the brief defines it as planned late coming or early leaving, 120 minutes a month, with 'lateness inside the window is not counted', and puts it in Phase 2. Still undefined: whether early-leaving minutes protect against the 240-minute half day (260-269). The lateness rule itself needs a change to hr_attendance_recompute (237-258).
- 7 (attendance-only staff are outside every existing feature; ESS identity is a prerequisite for C3-C12 and D1-D8): PARTLY REFUTED. The FK facts hold: priority_tasks.assigned_to (20260814000001:39) and inventory_request_history.actor_id (20260923000000:215) reference users, and punchAuth.js:17-34 admits punch sessions only on /my-attendance. But HR's override and sheet key on hr_employees and the faculty ledger on faculty, so HR (or an admin, for a faculty row) can already record leave for people with no users row; only self-service is closed. C6, C9, C11 and D7 do not need the identity middleware. An employee-keyed precedent exists: hr_round_reschedule_requests.requested_by_employee_id (20260913000000:47-48).
- 8 (the report's D2 citations are stale): CONFIRMED. routes/priorityTasks.js:17 is a comment and the guard is allowRoles(PARTICIPANTS) at 20-25; config/reportingPolicy.js:69 is the COMPLIANCE_VIEW_ROLES comment; named recipients come from TASK_NAMEABLE_BY (101-105); broadcasts stay admin_manager/admin (107-115).
- 9 (/api/alerts has no role check): CONFIRMED. server.js:176 adds only auth and routes/alertsRoutes.js:11-17 add nothing. alertsController.js:56-63, 191-193 and 238-241 filter by location only, and the pending list returns student name and admission_number (42). auth.js:19-42 passes a student token with its location_id, so a student can read and resolve their branch's alerts.
- 10 (deploy heredoc and multi-line secrets): CONFIRMED. deploy.yml:73 is an unquoted 'cat > .env &lt;&lt; EOF', so bash expands any '$' or backtick in a substituted secret, and every check reads one line with sed (169, 178, 186, 232). The FAST2SMS precedent of secrets set in GitHub but never written into the heredoc is recorded at 96-101 and 132.
- 11 (two leave systems would coexist for faculty): CONFIRMED. /api/am/leave (routes/amOps.js:80-84; leaveController.js:57-122, AM -> HoO at 223-246) and the planned ESS leave would coexist, and syncFacultyLeaveColumns overwrites a single range (150-156). The brief does not resolve it either: its HoO view maps faculty-leave approvals to PATCH /api/am/leave/:id/decide, while ESS leave goes to the reporting manager.
- 12 (HR counters disagree on non-CL leave): CONFIRMED. leaveTypeOf stores a blank type as 'leave' (attendanceRules.js:52-59). The dashboard counts it as unpaid (attendanceShiftsController.js:379) and codes it LWP (312), while the history counts lwp only for leave_type 'lwp' (522-523).
- 13 (use ATTENDANCE_OVERRIDE_ROLES for decide-any and HR cancel): CONFIRMED as code facts. hr_executive is in HR_ROLES and HR_WRITE_ROLES (hrPolicy.js:25-41) and excluded from ATTENDANCE_OVERRIDE_ROLES (68-72). Note that the sheet's past-day check uses P.HR_ROLES (staffAttendanceController.js:269), so reusing that check in ESS code would let hr_executive through.
- 14 (C10 depends on login links and branch names): CONFIRMED. The backfill left most rows unlinked (20260910000000:21-32), and branchFence matches branches by name with ilike (staffAttendanceController.js:196-209). Nuance: an unlinked manager can still sign in through an attendance-only login, since HAS_PORTAL_LOGIN keys only on hr_employees.user_id (attendanceOtpController.js:164-167), once the ESS identity accepts punch sessions.
- 15 (new-self-contained items still need a server.js mount): CONFIRMED. Every router is mounted in server.js:127-201 and none is /api/ess. The D7 push worker would also start from server.js, next to the email worker (254-263).

### Me, Wall and Helpdesk (E, F, G)

Found by the reader:

- Attendance-only (punch) sessions are built to open /api/hr/my-attendance/\* and nothing else (services/attendancePunch.js:190-199,209-213). The token is signed with a derived key, so auth rejects it (middleware/auth.js:14,102-105), and allowRoles answers 401 when userType is null (middleware/allowRoles.js:15-17). Every Me, Wall and Helpdesk endpoint meant for these staff must therefore use punchAuth and identify people by hr_employees.id. Existing per-person tables all key on users.id: priority_task_reads (20260814000001:62-68), priority_task_remarks (20260929000000:72-83), tickets.assignee_id and hr_documents.uploaded_by. This widens what the punch token can open, and RVM should sign off on it. Routes mounted inside routes/hr.js also inherit HR_MODULE_ENABLED, which returns 503 for all of them (routes/hr.js:66-74).
- Security: /api/announcements has no role gate, and auth admits student tokens (routes/announcements.js:12-14; middleware/auth.js:19-42). Any signed-in student, faculty or staff token with a branch can post to that branch's feed (controllers/announcementController.js:34-69). Any token at all can delete any announcement in any branch (controllers/announcementController.js:71-84). The web hides the page behind ADMIN_LEVEL in the UI only (Scheduler_frontend client/App.tsx:497-506). HR and HR Executive have no location, so they get 401 on GET and POST (controllers/announcementController.js:9-11,35-37; config/roles.js:103) and cannot use the existing feed at all.
- Notice-period staff disappear well beyond the org chart. The HR staff-attendance roster drops anyone with a date_of_exit (controllers/hr/staffAttendanceController.js:32-40,154), and the web Live view renders only that roster (Scheduler_frontend client/components/hr/attendance/LiveAttendance.tsx:76). Yet the same people can still punch (controllers/hr/attendancePunchController.js:89-90) and the settle job still writes their days (services/attendanceSettle.js:125-129). The same 'any date_of_exit means gone' rule appears in controllers/hr/dashboardController.js:121-122 (counted as both leaving and exited), controllers/hr/alertsController.js:254-256 and lib/mcp/tools/hrPeople.js:306-309.
- The report's picture of /api/tickets is out of date. Commit 5c82086 (12 Oct, after d2595e4) added fetchAccessibleTicket (students see only their own; admin-level staff are branch-scoped; faculty, hod and hr get 403), made reopen admin-only and made delete super_admin-only (controllers/ticketManagementController.js:18-37,280-282,307-311). Side effect: the student portal's Reopen button sends a student token (RVM_STUDENT_PORTAL client/pages/Tickets.tsx:280 -> client/services/api.ts:275-289) and now gets 403 'Access denied.' Caveat: the local portal clone is c0e713a from 17 Jul 2026 and may be behind origin.
- New modules cannot log to hr_activity_events as it stands. Its entity_type CHECK allows a fixed list (latest at supabase/migrations/20260926000000_email_custom_variables.sql:140-144), and recordEvent refuses event types not in EVENTS (services/hrEvents.js:97). Change requests, document reviews or moderation logged there need a widened CHECK (an existing-table change) or their own log table. The actor comes from req.user, so punch-only callers are recorded as 'unknown' (services/hrEvents.js:33-37), and documents they upload would get uploaded_by null with the name 'unknown' (controllers/hr/documentsController.js:105-106).
- The nginx limit is code, not ops. deploy.yml rewrites /etc/nginx/sites-available/scheduler on every deploy (.github/workflows/deploy.yml:322-323), and its /api/ block (340-350) and the student vhost's (470-476) set no client_max_body_size, so nginx's 1 MB default applies unless nginx.conf overrides it (check with nginx -T). A manual edit on the VPS would be lost at the next deploy. The limit applies to the whole request, so a 5-photo post, or a 2-5 MB phone photo of a document, fails before multer's 10 MB check. multer memoryStorage also buffers up to 10 x 10 MB per request in Node (routes/hr.js:77-84).
- E9 rollout order matters. The employee SELECT deliberately has no missing-column fallback (controllers/hr/employeesController.js:62-71), the backend deploys before migrations are applied by hand, and AUDITED copies every WRITABLE field into hr_activity_events (controllers/hr/employeesController.js:163-166). New PII columns must be migrated before the code that selects them ships, and they should be excluded or redacted from the event before/after.
- Data gaps that limit timeline and celebrations. date_of_joining was NULL on every migrated row (supabase/migrations/20260826000001_hrms_tables.sql:94-97; controllers/hr/dashboardController.js:124-126), and compensation effective_from is NULL on all 113 migrated revisions (controllers/hr/compensationController.js:771-773). Anniversaries, new-joiner lists and the timeline will be sparse until HR backfills; the database itself was not checked.
- Each person has two identities and two photos. users (username, phone_number, email, photo_path, role) drives /api/me and portal login (controllers/profileController.js:43-62). hr_employees (full_name, phone, email, photo_path) drives HR screens and attendance-only sign-in (controllers/hr/attendanceOtpController.js:128-156; controllers/hr/employeesController.js:1617-1674). Punch-only staff can set neither photo. The app needs one canonical display source.
- The Admin Manager's staff-attendance read is not branch-fenced. GET /api/hr/staff-attendance applies no branchFence (controllers/hr/staffAttendanceController.js:60-95); the fence exists only for remarks and mark (201-235, 292-300). A Team-today feature that reuses this read inherits cross-branch visibility.
- There is no planned-leave or WFH data. A future day cannot be marked (controllers/hr/staffAttendanceController.js:258-261), and the status CHECK has no WFH value (supabase/migrations/20261015000004_hr_staff_attendance.sql:18-20). 'Off this week' can only project week-offs and holidays until a staff leave-request module exists.
- There is no push infrastructure anywhere: no firebase, FCM or web-push dependency (package.json:20-37), and a search of routes, controllers, services, lib, config and migrations finds no device-token table. F1 mentions, F5 push, and G3 escalations and replies all need new FCM work and device tokens keyed on hr_employees.id.
- Two branch vocabularies. Portal roles (HoO, Admin Manager) sit on Scheduler locations (users.location_id, integer), while employees sit on hr_branches (uuid). The only bridge is a case-insensitive name match (controllers/hr/staffAttendanceController.js:201-209). F5 audiences, G1 and G3 routing to the HoO, and the G6 mirror (infra_tickets.location_id is a NOT NULL locations FK) all depend on this match, and an unmatched branch name silently breaks them.
- Infra 'escalation to HoO' is only a flag. runInfraTicketEscalation sets escalated and escalated_at and logs to the console (scheduledJobs.js:342-367); nobody is notified. The report's assumption that escalation exists to build on overstates it.
- student_app no longer calls Scheduler /api/announcements; its home feed uses the JobPortal (flutterapps apps/student_app/lib/injection.dart:92-101). The live consumers are the web, staff_app and the student portal. Snapshot ages: flutterapps 4712b91 (7 Aug 2026) and the student portal c0e713a (17 Jul 2026).

Checked:

- 1 (punch-only sessions): CONFIRMED, with one correction. Punch tokens are signed with a derived key and their own audience (services/attendancePunch.js:189-224), so auth rejects them (middleware/auth.js:14,102-105), allowRoles answers 401 (allowRoles.js:15-17), and the kill switch applies (routes/hr.js:66-74). But 'existing per-person tables all key on users.id' is too broad. Every attendance table already keys on hr_employees.id (hr_attendance_devices, punches, pings, overrides and otp_codes in 20261020000000:77-171; hr_attendance_accounts in 20261021000000:23-25; hr_attendance_employee_remarks in 20261023000000:12-14; hr_staff_attendance), and that is the precedent to follow. The users-keyed examples named are correct. Also, punchAuth falls through to auth, which admits student tokens, so new endpoints must refuse userType 'student'.
- 2 (/api/announcements has no role gate): CONFIRMED. routes/announcements.js:12-14 checks auth only. createAnnouncement inserts for any caller with a location, students included (announcementController.js:34-69), and deleteAnnouncement deletes any id with no role or branch check (71-84). hr and hr_executive are created without a branch (config/roles.js:91-103), so their GET and POST get 401 (9-11, 35-37). The web gate is UI-only (App.tsx:497-506).
- 3 (notice-period staff disappear): CONFIRMED. The roster filter (staffAttendanceController.js:32-40,154) and the web Live view (LiveAttendance.tsx:76) drop them, yet punching still admits them until the last working day passes (attendancePunchController.js:88-90) and the settle job still fills their days (services/attendanceSettle.js:125-129). The same rule appears in dashboardController.js:121-122, alertsController.js:254-256 and lib/mcp/tools/hrPeople.js:306-309.
- 4 (/api/tickets picture out of date): CONFIRMED, with an addition. 5c82086 (12 Oct 2026) added fetchAccessibleTicket, admin-only reopen and super-admin-only delete (ticketManagementController.js:18-37,280-282,307-311). The portal's Reopen button (RVM_STUDENT_PORTAL client/pages/Tickets.tsx:280 -> client/services/api.ts:275-289) sends a student token and now gets 403. Addition: the legacy /api/chat/:ticketId router (server.js:142; routes/chatRoutes.js:12-17; controllers/chatController.js:10-114) bypasses that hardening. Any token can read or post to any ticket's 'messages' thread, and a staff post flips an Open ticket to In Progress (remote_schema.sql:443-446). No client calls it.
- 5 (hr_activity_events cannot take new modules): CONFIRMED. The latest entity_type CHECK is 20260926000000_email_custom_variables.sql:136-144, with no later widening. recordEvent throws on event types not in EVENTS (services/hrEvents.js:96-100), so new types also mean editing config/hrPolicy.js. The actor comes from req.user, so punch callers become 'unknown' (hrEvents.js:33-37), and documentsController.js:105-106 behaves the same.
- 6 (the nginx limit is code, not ops): CONFIRMED in code; the effect is UNVERIFIED. deploy.yml rewrites both vhosts on every run (322-323, 453), and neither /api/ block sets client_max_body_size (340-350, 470-476), so a manual edit on the VPS would be lost. Whether the 1 MB default applies depends on /etc/nginx/nginx.conf, which is not in the repo. The intake upload allows 15 MB 'for high-res IDs' (controllers/intakeController.js:12-16), which hints that larger bodies may already pass in production; check nginx -T. The multer memory buffering (routes/hr.js:77-84) is confirmed.
- 7 (E9 rollout order): CONFIRMED. The SELECT has no 42703 fallback (employeesController.js:62-71), AUDITED copies every WRITABLE key (163-166), and the deploy workflow lints migrations without applying them (deploy.yml:36-38). Refinement: the CEO audit view shows hr_activity_events before/after verbatim (controllers/ceo/auditReadController.js:124-147,186), so keeping new PII out of AUDITED is the control that matters; WITHHOLD_VALUE_KEYS does not cover this trail.
- 8 (data gaps in joining and pay dates): CONFIRMED, but only from code comments (hrms_tables.sql:94-97; dashboardController.js:124-129; compensationController.js:771-773). The database was not checked, as the finding itself says.
- 9 (two identities and two photos): CONFIRMED. users drives /api/me (profileController.js:43-62); hr_employees drives the HR screens and attendance-only sign-in (attendanceOtpController.js:128-156; employeesController.js:1617-1674). Punch-only staff can reach neither photo upload. Teaching staff also have a third record, in faculty (name, email, phone_number), joined through users.faculty_id (middleware/auth.js:50-57).
- 10 (the Admin Manager's staff-attendance read is not branch-fenced): CONFIRMED. exports.read applies no branchFence (staffAttendanceController.js:60-95); the fence is used only by remarks (232-236) and mark (292-302).
- 11 (no planned-leave or WFH data): PARTLY REFUTED. WFH is indeed absent (20261015000004_hr_staff_attendance.sql:18-20; no WFH anywhere in the code), but planned leave exists. Only the daily sheet refuses future days (staffAttendanceController.js:258-261). The HR override records leave ahead (attendanceAdminController.js:46-60), its SQL function has no date check (20261020000000_hr_attendance_punch.sql:290-341), and the web shows it as 'Record leave' (AttendanceHistory.tsx:141-161). Faculty also have leave_requests with planned/emergency types, start and end dates, and approval (20260804000003_admin_manager_ops.sql:78-109; routes/amOps.js:80-84). What is missing is an employee-raised leave request for HR employees.
- 12 (no push infrastructure): CONFIRMED. A search of the whole backend finds no firebase, FCM, web-push or device-token code or table, and package.json:20-37 has no such dependency. hr_attendance_devices (20261020000000:77-95) is a registry of punch-phone cookies, not a push-token store.
- 13 (two branch vocabularies): CONFIRMED. No migration gives hr_branches a location_id or any other link to locations. The only bridges are case-insensitive name matches (staffAttendanceController.js:47-55,201-209), and infra_tickets.location_id is NOT NULL (20260804000003:115).
- 14 (infra escalation is only a flag): CONFIRMED. runInfraTicketEscalation sets the flag and logs to the console (scheduledJobs.js:342-367; cron at 735-738). The flag shows up only in the register list, the Data Manager and the MCP tool (opsTickets.js:59-73), and nobody is notified.
- 15 (student_app and snapshot ages): CONFIRMED. student_app's home announcements come from the JobPortal (apps/student_app/lib/injection.dart:92-101). The clones checked are flutterapps 4712b91 (7 Aug 2026) and RVM_STUDENT_PORTAL c0e713a (17 Jul 2026).
- NEW (checker): GET /api/users (routes/user.js:69) has auth and no role gate. Any signed-in token with a branch, student tokens included, gets every login at that branch with phone_number and email, plus HR full_name and designation (controllers/userController.js:543-651). This bears on E2 and E8, and fixing it means changing existing code.
- NEW (checker): GET /api/faculty (routes/faculty.js:18) is also auth-only. It returns faculty email, phone_number, leave_start_date, leave_end_date and leave_reason for the branch to any token, students included (controllers/facultyController.js:31-60).
- NEW (checker): the legacy /api/chat/:ticketId routes (see extra 4) are unguarded but no client uses them, so they can be removed rather than fixed.

### Role views and security (H, J, #70)

Found by the reader:

- Student tokens are the cheapest credential in the system, and they are what makes J1, J3, J4 and DASH open to outsiders. POST /api/users/auth/student/login issues a 7-day token for admission_number + phone_number, with no password, no OTP and no loginLimiter (routes/user.js:38; controllers/userController.js:783-801; server.js:119-125). auth admits that token everywhere and gives it a branch (middleware/auth.js:19-43). The only middleware that refuses students, staffOnly, is used on the intake routes alone (routes/intake.js:83,91,100).
- Phone-only account takeover chain (J5 is worse than reported). (1) GET /api/users hands every account's phone_number and role at the caller's branch to any token, students included (routes/user.js:69; controllers/userController.js:558,569-575). (2) POST /api/users/reset-password with username=phone and phone_number=phone resets that account with no code, because the lookup is .or(username.eq.X,phone_number.eq.X).eq(phone_number,P) with X unquoted (controllers/userController.js:1201-1202,1213-1214,1230-1236). (3) The attacker can then sign in as the HoO or an admin; only accounts with 2FA on are protected (userController.js:467). No session is revoked on a password change (middleware/auth.js has no password_changed_at check).
- Password hashes leak beyond the roster that H2/J2 name. GET /api/students spreads full select('\*') rows for up to 1000 students per page to any branch token (routes/students.js:22; controllers/studentsController.js:26,63-73,113-114). POST and PUT /api/batches reply with students:batch_students(students(\*)) (controllers/batchesController.js:263-270,505-523). The column is students.password_hash (public_schema_backup.sql:1791).
- Money writes have no role check and are not in the task list. PATCH /api/accounts/admissions/:id/approve has no role and no branch check and sets total_payable_amount from the request body (routes/accountsRoutes.js:49; controllers/accountsController.js:161-204), so any signed-in token, a student's included, can approve any branch's pending admission at any amount. POST /api/accounts/payments checks only the branch, so a faculty token at the branch can record a receipt (controllers/accountsController.js:619-647). The denyWrite on these routes does nothing (config/roles.js:109).
- The updateUser escalation fix is only partial. updateUser, assignRole and deleteUser check the NEW role and the target's branch, never the target's CURRENT role (controllers/userController.js:986-996,1022-1026; 699-721; 849-852). A plain branch admin can therefore set the password of, demote or purge an elevated account in its own branch (HoO, admin_manager, hod, hod_placement, or a super admin whose row carries that branch) and then sign in as it.
- The report's H3 'AVAILABLE/VERIFY' is wrong. hod_placement is named in no interview role set (config/hrPolicy.js:236-243; controllers/interviewsController.js:117), yet the web lands it on /interviews (FE client/App.tsx:113-114). There the server answers 403 unless the person's linked org-chart label matches LEADER_ROLE_PATTERN (config/hrPolicy.js:258; services/hrPeople.js:60-65).
- J8's '~40' undercounts. There are 49 app-facing 401 sites that are not token rejections (43 no-branch, 4 wrong-current-password, 2 sign-in failures), plus 3 non-app ones. 'Please authenticate' is also sent on a Supabase error during the user lookup (middleware/auth.js:20-28,68-72,102-105), and portal 401s carry no code. A client that signs out on 'Please authenticate' would still sign everyone out during a database outage.
- Stale line numbers in the report (the content is unchanged): READ_ONLY_ROLES is config/roles.js:109, not 94; the batch write routes are routes/batches.js:19-21, not 9-11; the roster selects are controllers/attendanceController.js:214,219, not 186,191.
- HOD count: the code comments still say no account holds 'hod' (routes/interviews.js:18-20; config/hrPolicy.js:229-231; services/hrPeople.js:25-30; FE client/lib/roles.ts:396-400). RVM's own notes record 5 hod, 2 hoo and 1 hod_placement accounts as of 2026-09-15, with one CAM HOD missing a hod_domains row. A hod without a hod_domains row is refused every Faculty Development read (controllers/hodController.js:118-126). Re-count before the H8 re-role; this was not verifiable read-only.
- Batch create and update bypass the guarded cross-branch enrollment. Any caller can insert any studentIds into batch_students with joined_at set to today, without ENROLL_ROLES or the ownership rule (controllers/batchesController.js:250-261,470-481 vs routes/batches.js:12,23; config/enrollmentPolicy.js:20-26).
- For H4: the Admin Manager's staff-attendance read is not branch-fenced on the server. It accepts any branch_id, and with none it returns every active employee and their remarks (controllers/hr/staffAttendanceController.js:60-95,130-176). The fence exists only on mark and remarks (201-209,232,292). A 'my team' endpoint must not copy this pattern.
- The faculty report route comment promises 'Admins, or the specific faculty via controller logic', but the controller only filters by branch. Any branch token, a student's included, can read any faculty's attendance report (routes/attendanceRoutes.js:79-84; controllers/attendanceController.js:505-530).

Checked:

- CONFIRMED - Student tokens are the cheapest credential. routes/user.js:38 is public, and userController.js:783-801 signs a 7-day JWT from admission_number + phone_number with no password and no OTP. loginLimiter covers only the /api/users/login prefix (server.js:119), so this route gets only apiLimiter (125). auth.js:19-43 admits the token and sets req.locationId. staffOnly is used only on routes/intake.js:83,91,100 and inside middleware/intakeAccess.js:36. requireRole and allowRoles also refuse students, but neither is present on the J1, J3, J4 or DASH routes.
- CONFIRMED - Phone-only account takeover chain. GET /api/users (routes/user.js:69, auth only) returns phone_number and role (userController.js:558) for the caller's branch, a student's included (569-575). resetPassword interpolates username unquoted (1201,1213) beside .eq('phone_number') (1202,1214), so username=phone matches any account with that phone, and 1230-1236 writes the hash with no code. login accepts the phone as identifier (271-279); only 2FA (467) stops the sign-in. auth.js never checks password_changed_at, and the legacy reset does not even set it (1233-1236).
- CONFIRMED - Password hashes leak beyond the roster. routes/students.js:22 is auth-only, studentsController.js:26 allows a 1000-row page, select('\*') at 63-73 and the spread at 113-114 return students.password_hash (public_schema_backup.sql:1791) to any branch token. batchesController.js:265 and 505 embed students(\*) in the POST and PUT replies (510, 523). GET /api/batches/:id/students is NOT a further leak: it is branch-fenced (654-656) with explicit fields (707-730).
- CONFIRMED - Money writes have no role check. accountsRoutes.js:49,55 are auth + denyWrite, and denyWrite is a no-op (roles.js:109). approveAdmission (accountsController.js:161-204) has no role or branch check and writes total_payable_amount from the body (191), so any token can approve any branch's pending admission. recordPayment checks only the branch (644-647). Sibling: GET /api/accounts/admissions (accountsRoutes.js:26; accountsController.js:21-53) lists the branch's admissions with student phone and fees to any branch token.
- CONFIRMED - The updateUser escalation fix is partial. updateUser checks only the requested role (986-991) and the target's branch (994-996), then sets password_hash whatever the target's current role (1022-1026). assignRole (699-721) and deleteUser (849-852) have the same shape. The routes require only `admin` (routes/user.js:81,84,91; middleware/admin.js:7). So a plain branch admin can reset the password of a HoO, admin_manager, hod, hod_placement, or a super_admin or ceo row carrying that branch, and sign in as it.
- CONFIRMED - The report's H3 AVAILABLE/VERIFY is wrong. hod_placement appears in no server policy set (a grep finds it only in roles.js, a userController comment and the enum migration). The web sends it to /interviews (App.tsx:114), where viewerScope answers 403 unless a linked hr_employees row qualifies through LEADER_ROLE_PATTERN (hrPolicy.js:258; hrPeople.js:60-65,182-185).
- CONFIRMED - J8's '~40' undercounts. The backend has 60 401 sites: 43 no-branch, 4 wrong-current-password, 2 sign-in failures, 3 non-app and 8 session-over. 'Please authenticate' is also sent on any Supabase error or duplicate row in auth's .single() lookups (auth.js:20-28,50-72,102-105). Addition: an expired punch-only token also gets the code-less 'Please authenticate', because readPunchSession returns null (attendancePunch.js:230-239) and punchAuth.js:33 falls through to auth.
- CONFIRMED - Stale line numbers. git show d2595e4 has READ_ONLY_ROLES at config/roles.js:94, the batch writes at routes/batches.js:9-11 and the roster selects at attendanceController.js:186,191. At c28b9ca they are 109, 19-21 and 214,219, with the content unchanged. reset-password stays at routes/user.js:28 and POST /api/attendance at attendanceRoutes.js:43.
- CONFIRMED (code part only) - The 'no account carries hod' comments are still present (routes/interviews.js:18-20; hrPolicy.js:229-231; hrPeople.js:25-30; FE roles.ts:396-400). The account counts (5 hod, 2 hoo, 1 hod_placement; Sandeep without a hod_domains row) come from memory note account_link_and_interviews_sep2026.md:20-22 and are not verifiable read-only. NO_DOMAIN_ASSIGNED is at hodController.js:118-126.
- CONFIRMED - Batch create and update bypass the guarded enrollment. createBatch inserts body studentIds with joined_at today (batchesController.js:249-260), and updateBatch inserts toAdd (470-481). Neither passes enrollGuard, which routes/batches.js applies only at 18, 23 and 24; ENROLL_ROLES is enrollmentPolicy.js:20-26. Minor: on update, a removed-then-re-added student keeps its original joined_at (477).
- CONFIRMED - For H4: staffAttendanceController.read is unfenced. branch_id is optional (60-78). With none, activeEmployees(null) returns everyone (32-40, 94), along with remarks and employee remarks (130-176). branchFence is applied only in remarks (232-236) and mark (292-302).
- CONFIRMED - The faculty report route comment (attendanceRoutes.js:79-84) promises a per-faculty check, but getFacultyAttendanceReport applies only a branch filter (attendanceController.js:524-530). The substitution batch ids (539) are not branch-filtered at all, so any branch token, a student's included, can read any faculty's report.
- NEW (checker, J7) - The nginx vhost is in the repo. .github/workflows/deploy.yml runs on every push to main (3-6, 53-57) and rewrites /etc/nginx/sites-available/scheduler each time (322-323, 411-413, 545). Its /api/ block (340-350) and the student vhost's (470-477, 510-517) set no client_max_body_size. The upload-limit fix therefore belongs in deploy.yml; a VPS-only edit is overwritten by the next deploy.
- NEW (checker, H5) - Two existing finance KPI sources were missed. GET /api/ceo/collection-rate-intelligence is gated exactly as the leader cards need (ceo, super_admin, hoo pinned; routes/ceo.js:58-65,95; ceoDashboardController.js:370-378), but runs 8 live unpaged queries (utils/collectionRate.js:58-90). The nightly branch_period_metrics rollup stores per-branch revenue_collected, billed_due and outstanding (branchRollupService.js:112-135; migration 20260804000009:30-75), readable only through the ceoOnly routes at routes/ceo.js:128,137.
- NEW (checker, H7) - GET /api/free-slots already does weekday, time and substitution logic and forces teaching callers to their own faculty_id (freeSlotsController.js:20-26,52-66), though branch-scoped. It is a reusable building block for the 'my day' endpoint.
- NEW (checker, J3 note) - The real Flutter UI gate is staff_permissions.dart:112-119 (faculty canWrite:true) together with batches_screen.dart:63,324-325, which shows create, Edit and Delete whenever canWrite is set. The data-source lines the reader cited only show that the calls exist.
