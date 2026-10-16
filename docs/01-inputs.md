# Input documents

Three documents started this work. Copies are in [inputs/](inputs/). Each section below says what the document is and where it is out of date or wrong. The rule: where a document and the code disagree, the code at Scheduler_Backend `c28b9ca` is the truth ([02-reconciliation.md](02-reconciliation.md)).

## 1. Team RVM App Brief (15 Oct 2026)

**File:** [inputs/team-rvm-app-brief-2026-10-15.pdf](inputs/team-rvm-app-brief-2026-10-15.pdf). 37 pages, exported at 18:59 IST on 15 Oct. The developer's prompt calls it `rvm_team_app_requirement.pdf`.

**What it is.** KP's full requirement, kept as a live Claude Doc; the PDF is a snapshot. It covers:
- **Shape of the app:** a Keka-style employee app with five tabs (Home, Inbox, Wall, Me, My Team).
- **Attendance:** punch and calendar under the web's rules, plus requests and approvals.
- **Self-service:** the Wall, the Helpdesk, profile and documents, My Team, and role views.
- **Build guidance:** the theme, the API map, Android requirements, privacy and compliance.
- **Planning:** the roadmap (Phase 0 set-up, then Phases 1, 2 and 3) and 16 decisions.

**It needs a fresh export.** After this PDF was made, a fact-check of the brief against the code found 91 corrections, which are being applied to the live doc. Re-export it and replace this copy. These corrections matter for the backend and the app.

### Sign-in and sessions

- **When the app counts as signed out.** Only on a 401 that says "No token provided" or "Please authenticate", or has code `NOT_AUTHENTICATED`. The last one ends an attendance session after a password change or an HR reset.
- **Every other 401 means something else,** such as a wrong password or a missing branch. There are 49 such call sites in the code the app talks to. "Please authenticate" is also sent during a database outage, so the app checks once more before signing anyone out.
- **Setting a password replaces the token.** `POST /api/hr/my-attendance/password` returns a fresh token and ends every older session of that login, including the caller's. The app must store the new token.
- **Changing an attendance password needs a fresh code sign-in.** It works only within 15 minutes of a code sign-in, or while the login still has HR's first-time password. Otherwise the server answers 403 `CODE_REQUIRED`.
- **Which identifiers work where:**
  - An employee code works only with a password.
  - A one-time code can be requested only with the main phone number or email.
  - The portal's forgot-password sends a code only to a verified email.
- **Password rules** also include at most 72 bytes and not one character repeated.

### Punch and ping

- **Don't scale GPS accuracy by 1.6.** Chrome on Android passes Android's `getAccuracy()` through unchanged. The app sends it as it is, and the one server limit (100 m) applies.
- **`CHALLENGE_REUSED` after a lost reply means the punch was recorded.** Reload and show it; don't retry. Only `CHALLENGE_EXPIRED` is retried.
- **Pings never answer 403.** `POST /ping` answers 204 when the phone is revoked or the day is closed. The app stops tracking at punch-out, at midnight, and at shift end plus a grace period.
- **Messages worded for the web.** Some server messages refer to the web page: `CHALLENGE_MISSING`, `CHALLENGE_INVALID`, `LOCATION_MISSING` and `HAS_PORTAL_LOGIN`. The app shows its own words for these.
- **Field staff exempt from the geofence** may punch even when their branch has no location set.
- **Phone resets.** No bulk phone reset and no transfer code exist. HR resets one phone at a time, with a reason. A browser that has been reset is refused for good.
- **Play Integrity must stay off the 2-minute pings.** About 29,000 tokens a day would be needed, against a free quota of 10,000.

### Days and approvals

- **WFH and on-duty approvals need their own database function.** `hr_attendance_apply_override` won't do: it refuses future days other than leave, and it freezes the row against later punches.
- **The status of a self-punched day is always computed.** A day marked on the daily sheet keeps HR's status, so the app reads `status` and never derives it from `late_half_day`.
- **HoO leave decisions** use `PATCH /api/am/leave/:id/decide`, not POST. A leave touching the 1st of the month (salary credit) also needs the HoO.
- **`faculty.leave_*` holds a single date range,** so each approval overwrites the previous one.

### Who can see and do what

- **Location trail:** only HR, the CEO and super admins can read it; no manager view exists. The privacy disclosure must say so.
- **HR Executive** has no attendance access by design.
- **The Time screen already works for employees.** `GET /api/hr/my-attendance` returns the person's name, employee code, branch, shift, week-offs and holidays.
- **Priority tasks and interviews** are tied to `users.id`, so the 41 attendance-only staff can't get them until those features are keyed to the HR record.
- **`hod_placement`** must be in `SEES_EVERY_INTERVIEW` to run the whole interview calendar.
- **A `hod` login** also needs a `hod_domains` row. `GET /api/hod/interviews` writes on every call, so the app must not poll it.
- **The RVM Staff app** refuses Admin Manager logins and treats Finance Admin as read-only.

### Open data the app can't rely on yet

- **`/api/dashboard`** returns every admission row (names, phones, payments) to any signed-in token with a branch, including students.
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
- Its own conclusion applies: "If the latest backend already contains the attendance/ESS work from the brief, most of Section 4 becomes verification only."
- [02-reconciliation.md](02-reconciliation.md) re-checks every one of its tasks at `c28b9ca`.

**Errors to ignore:**
- **"There is no `hr_executive`."** The role exists in `config/roles.js` at `c28b9ca`.
- **"Scheduler_frontend (Aug 2026, student-portal only)."** The developer's frontend copy was old. The live web has the HRMS, punch and attendance screens.
- **The "×1.6 Android scale" option in B7.** It is wrong; see the brief's punch corrections above.
- **"H3 AVAILABLE".** `hod_placement` is in no server interview role set. It reaches its own rounds only when its login is linked to an HR record with a "head" title.
- **D2 and D3 as UPDATE and MISSING.** Both exist: priority tasks v2 shipped on 29 Sep.
- **"~40 endpoints" in J8.** The count is 49.
- **The punch body in B3 as "lat, lng".** The API takes `latitude` and `longitude`.
- **What it left out.** It misses several live security holes:
  - phone-only account takeover;
  - money writes without a role check;
  - a branch admin taking over elevated accounts;
  - a committed database dump.

  They are listed in [02-reconciliation.md](02-reconciliation.md).
- **Its generic table names** (`attendance`, `employee_devices`, `shifts`, `holidays`). The real tables are named `hr_*`. The mapping is in [02-reconciliation.md](02-reconciliation.md), item I.
- **Decision 15, "First sign-in: one-time code, password fallback".** This repeats the brief's recommendation. KP decided to keep today's flow ([03-decisions.md](03-decisions.md)).
- **Cut-off tables.** In the PDF itself, the right-hand cells of the section E and I tables run off the page, so parts of them are missing. The brief's API map has the endpoint names: `GET /api/ess/me/profile`, `/me/org`, `/me/department`, `/directory`; `POST /me/change-requests`; `GET` and `POST /api/ess/me/documents`.

## 3. The developer's prompt to KP (16 Oct 2026)

**File:** [inputs/kp-backend-monorepo-prompt-2026-10-16.md](inputs/kp-backend-monorepo-prompt-2026-10-16.md).

**What it is.** The working agreement for building the backend, in gated steps:

| Step | What happens | Where it stands |
| --- | --- | --- |
| STEP 0 | Questions to KP | Answers recorded in [03-decisions.md](03-decisions.md) and [adr/](adr/README.md) |
| STEP 1 | Reconcile every task ID against the real backend | [02-reconciliation.md](02-reconciliation.md) |
| STEP 2 | The plan and the OpenAPI contract | Waits for KP's approval |
| STEP 3 | Build phase by phase, with tests | |

**Its rules hold throughout:**
- Ask instead of assuming.
- Don't break the live portal or the staff and student apps.
- Follow the Scheduler's conventions.
- Every route needs authentication plus a role or ownership check.
- No production writes, migrations, pushes or deploys without KP's OK.
- No secrets in code.

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
