# Input documents

Three documents started this work. Copies are in [inputs/](inputs/). For each, this page says what it is and where it is out of date or wrong. The rule: where a document and the code disagree, the code at Scheduler_Backend `c28b9ca` is the truth ([02-reconciliation.md](02-reconciliation.md)).

## 1. Team RVM App Brief (15 Oct 2026)

**File:** [inputs/team-rvm-app-brief-2026-10-15.pdf](inputs/team-rvm-app-brief-2026-10-15.pdf). 37 pages, exported at 18:59 IST on 15 Oct. The developer's prompt calls it `rvm_team_app_requirement.pdf`.

**What it is.** RVM's full requirement for the app (the developer's prompt calls it the CEO's). The RVM CAD tech team wrote it, and it is kept as a live Claude Doc; the PDF is a snapshot. It covers:
- **Shape of the app:** a Keka-style employee app with five tabs (Home, Inbox, Wall, Me, My Team).
- **Attendance:** punch and calendar under the web's rules, plus requests and approvals.
- **Self-service:** the Wall, the Helpdesk, profile and documents, My Team, and role views.
- **Build guidance:** the theme, the API map, Android requirements, privacy and compliance.
- **Planning:** the roadmap (Phase 0 set-up, then Phases 1, 2 and 3) and 16 decisions.

**Where it is now out of date:**
- **Backend location.** Its API map puts the new backend inside the Scheduler under `/api/ess`. KP has since ruled that the Scheduler doesn't change: the new backend is a separate service in team_app, on its own subdomain ([ADR-0018](adr/0018-team-app-changes-nothing-in-the-scheduler.md), [ADR-0019](adr/0019-ess-on-its-own-subdomain.md)).
- **Corrections.** A fact-check of the brief against the code found 91 corrections. They and KP's 16 Oct answers have been written into the live doc. KP re-exports it and replaces this copy.

The corrections that matter for the backend and the app are below.

### Sign-in and sessions

- **When the app counts as signed out.** Only on a 401 that says "No token provided" or "Please authenticate", or has code `NOT_AUTHENTICATED`. The last one ends an attendance session after a password change or an HR reset.
- **Every other 401 means something else,** such as a wrong password or a missing branch. 49 places in the code the app talks to answer such a 401. "Please authenticate" is also sent during a database outage, so the app checks once more before signing anyone out.
- **Setting a password replaces the token.** `POST /api/hr/my-attendance/password` returns a fresh token and ends every older session of that login, including the caller's. The app must store the new token.
- **Changing an attendance password needs a fresh code sign-in.** It works only within 15 minutes of a code sign-in, or while the login still has HR's first-time password. Otherwise the server answers 403 `CODE_REQUIRED`.
- **Which identifiers work where:**
  - An employee code works only with a password.
  - A one-time code can be requested only with the main phone number or email.
  - The portal's forgot-password sends a code only to a verified email.
- **Password rules** also include a maximum of 72 bytes. A password made of one character repeated throughout (such as `aaaaaaaa`) is refused; repeating some characters is fine.

### Punch and ping

- **Don't scale GPS accuracy by 1.6.** Chrome on Android passes Android's `getAccuracy()` through unchanged. The app sends it as it is, and the one server limit (100 m) applies.
- **`CHALLENGE_REUSED` after a lost reply means the punch was recorded.** Reload and show it; don't retry. Only `CHALLENGE_EXPIRED` is retried.
- **Pings answer 204, not 403, for problems with the phone or the day.**
  - `POST /ping` answers 204 when the phone isn't the employee's active one (a revoked phone included), when the person isn't punched in, while the login is still on HR's first-time password, and when the last stored ping is under 60 seconds old.
  - Like the other punch routes, it can still answer 403 `NOT_LINKED`, `NOT_ACTIVE` or `NO_ATTENDANCE_LOGIN`, and 401 `NOT_AUTHENTICATED`.
  - The app stops tracking at punch-out, at the end of the shift plus its grace period, at midnight IST, and on those 401 and 403 answers.
- **Messages worded for the web.** Some server messages refer to the web page: `CHALLENGE_MISSING`, `CHALLENGE_INVALID`, `LOCATION_MISSING` and `HAS_PORTAL_LOGIN`. The app shows its own words for these.
- **Field staff exempt from the geofence** may punch even when their branch has no location set.
- **Phone resets.**
  - No bulk phone reset and no transfer code exist; HR resets one phone at a time, with a reason.
  - A reset browser is refused while it keeps its old cookie. Clearing the site's data drops the cookie, and the browser can then register again if the employee has no other active phone.
- **Play Integrity must stay off the 2-minute pings.** They would need about 29,000 tokens a day, against a free quota of 10,000.

### Days and approvals

- **`hr_attendance_apply_override` changes days, but it checks nothing itself.**
  - It writes every day with source `override`, which freezes the row against the daily sheet and later punches.
  - It stores the reason as the day's note.
  - The rule "only leave on a future day" lives in the Scheduler's override controller (`controllers/hr/attendanceAdminController.js:58-60`), not in the function.
  - So the ESS, which calls the function for approvals, enforces its own date and status rules ([ADR-0020](adr/0020-approvals-through-the-override-function.md)).
- **The status of a self-punched day is always computed.** A day marked on the daily sheet keeps HR's status. So the app reads `status` and never derives it from `late_half_day`.
- **HoO leave decisions** use `PATCH /api/am/leave/:id/decide`, not POST. A leave longer than 2 days, or touching the 1st or 2nd of a month (the salary-credit window), also needs the HoO.
- **`faculty.leave_*` holds a single date range,** so each approval overwrites the previous one.

### Who can see and do what

- **Location trail:** only HR, the CEO and super admins can read it. No manager view exists, and the privacy disclosure must say so.
- **HR Executive** has no attendance access by design.
- **The Time screen already works for employees.** `GET /api/hr/my-attendance` returns the person's name, employee code, branch, shift, week-offs and holidays.
- **Priority tasks and the interview calendar are out of reach for attendance-only staff:**
  - Priority tasks are keyed to `users.id` (`priority_tasks.assigned_to`).
  - The interview calendar finds its viewer through `users.id` behind portal-only auth, although rounds already name the interviewer by `hr_employees.id`.
  - So the attendance-only staff (about 41, per the brief) can't get either without a Scheduler change, which is out of scope ([ADR-0018](adr/0018-team-app-changes-nothing-in-the-scheduler.md)).
- **`hod_placement`:** to run the whole interview calendar it must be in `SEES_EVERY_INTERVIEW`. Today it reaches its own rounds only when its login is linked to an HR record whose ladder role (or, failing that, designation) matches the leader pattern: HOD, a head, CEO, COO, CTO or HR.
- **A `hod` login** also needs a `hod_domains` row. `GET /api/hod/interviews` expires stale holds on every call and writes whenever one has run out, so the app must not poll it.
- **The RVM Staff app** (flutterapps `4712b91`):
  - It signs in only admin, faculty, super_admin and accounts_admin among the Scheduler's roles, and treats Finance Admin (accounts_admin) as read-only.
  - It refuses Admin Manager, CEO, HoO, HOD, HOD Placement, HR and HR Executive logins.

### Open data the app can't rely on yet

- **`/api/dashboard`** returns every admission row (names, phones, payments) to any signed-in token with a branch, students included.
- **`GET /api/attendance/batch/:id/daily`** has no branch or ownership check.
- **`date_of_joining` is empty for imported employees,** so anniversary and new-joiner cards need HR to fill it in.

## 2. Backend Gap & Task Report (16 Oct 2026)

**File:** [inputs/backend-gap-and-task-report-2026-10-16.pdf](inputs/backend-gap-and-task-report-2026-10-16.pdf). 15 pages, prepared for KP by the mobile developer. The developer's prompt calls it `rvm_teamapp_gap.pdf`.

**What it contains:**
- task IDs A1–K6, each with a status and an action;
- the prerequisites;
- the 16 decisions with their impact on the backend;
- what already exists;
- an evidence appendix.

**It audited an old backend.** It checked Scheduler_Backend `d2595e4` (24 Sep 2026), which is 97 commits behind today's `main`, `c28b9ca` (15 Oct 2026).
- These merged after its snapshot:
  - the issue #70 fixes (#71, #72);
  - the CEO audit trail and MCP connector;
  - GPS punch (#76);
  - shifts and the HR Executive role (#77);
  - day rules (#80);
  - the midnight auto-submit (#81);
  - the first-time password (#83).
- **Its own condition is only half met.** It said most of section 4 would become verification if the attendance work existed. The section B attendance work is built, but most of section 4 is not: 53 of the 105 items are missing, including most of sections C and D. Only A2, B2–B7, B9–B13, B16, D2 and D3 need no backend work.
- [02-reconciliation.md](02-reconciliation.md) re-checks every one of its tasks at `c28b9ca`.

**Errors to ignore:**
- **"There is no `hr_executive`."** The role exists in `config/roles.js` at `c28b9ca`.
- **"Scheduler_frontend (Aug 2026, student-portal only)."** The developer's frontend copy was old. The live web has the HRMS, punch and attendance screens.
- **The "×1.6 Android scale" option in B7.** It is wrong; see the brief's punch corrections above.
- **Its generic table names** (`attendance`, `employee_devices`, `shifts`, `holidays`). The real tables are named `hr_*`. The mapping is in [02-reconciliation.md](02-reconciliation.md), item I.
- **The First sign-in decision, "One-time code, password fallback".** It is the last of the gap report's 16 decisions, and decision 15 in [03-decisions.md](03-decisions.md). It repeats the brief's recommendation; KP decided to keep today's flow.
- **"H3 AVAILABLE".** `hod_placement` is in no server interview role set (see above).
- **D2 and D3 as UPDATE and MISSING.** Both exist: priority tasks v2 shipped on 29 Sep.
- **"~40 endpoints" in J8.** The count is 49 places in the code that answer a 401 that isn't about the session: 43 for a missing branch, 4 for a wrong current password and 2 for sign-in failures. These are counted where they occur in the code, not per endpoint.
- **The punch body in B3 as "lat, lng".** The API takes `latitude` and `longitude`.
- **Cut-off tables.** In the PDF itself, the right-hand cells of the section E and I tables run off the page, so parts of them are missing. The brief's API map has the endpoint names.
- **What it left out.** It misses several live security holes in the Scheduler:
  - phone-only account takeover;
  - money writes without a role check;
  - a branch admin taking over elevated accounts;
  - a committed database dump.

  They are listed in [02-reconciliation.md](02-reconciliation.md).

## 3. The developer's prompt to KP (16 Oct 2026)

**File:** [inputs/kp-backend-monorepo-prompt-2026-10-16.md](inputs/kp-backend-monorepo-prompt-2026-10-16.md).

**What it is.** The working agreement for building the backend, in gated steps:

| Step | What happens | Where it stands |
| --- | --- | --- |
| STEP 0 | Questions to KP | Answered 16 Oct ([03-decisions.md](03-decisions.md), [adr/](adr/README.md)), except the layout, workspaces and Node version ([ADR-0017](adr/0017-repository-layout-and-tooling.md)), which are still proposed |
| STEP 1 | Reconcile every task ID against the real backend | Done 16 Oct ([02-reconciliation.md](02-reconciliation.md)) |
| STEP 2 | The plan and the OpenAPI contract | KP started the build on 16 Oct ("start the backend now"); the plan is [04-build-plan.md](04-build-plan.md) |
| STEP 3 | Build phase by phase, with tests | In progress: Wave 1 |

**KP's 16 Oct rule changes part of the prompt.** The prompt asked for the J security fixes, the issue #70 items and other changes inside Scheduler_Backend. KP ruled that Team RVM changes nothing in the Scheduler, so those items are out of scope ([ADR-0018](adr/0018-team-app-changes-nothing-in-the-scheduler.md)).

**Its other rules hold throughout:**
- Ask instead of assuming.
- Don't break the live portal or the staff and student apps.
- Follow the Scheduler's conventions.
- Every route needs authentication plus a role or ownership check.
- No secrets in code.
- No production writes, migrations, pushes or deploys without KP's OK. This still binds AI agents, with one exception: on 16 Oct KP told them to push finished team_app work to `main`. KP and the mobile developer may merge to `main`, and a merge deploys only once the switch is on ([ADR-0011](adr/0011-ci-merge-and-auto-deploy.md)).

**Its final deliverables:**
- the monorepo on a branch;
- the OpenAPI contract;
- the migrations in run order;
- the environment variables and secrets;
- the deploy steps;
- an A1–K6 status table;
- a handover note for the Flutter developer.

## Other references

- **Team RVM design system:** tokens, components, logos and launcher icons, in light and dark. https://claude.ai/artifact/HgNXzys7F4jtHpPc7wZJUX. It stays private until KP shares it.
- **RVM brand guidelines (September 2026):** KP's copy. Pages 9 and 10 carry another brand's text and should be fixed before the PDF is shared.
