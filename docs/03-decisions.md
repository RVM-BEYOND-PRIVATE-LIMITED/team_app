# Product decisions

How Team RVM behaves, as RVM decided it. Architecture decisions are in [adr/](adr/README.md).

- **Decided**: KP chose it.
- **Default**: the brief's recommendation, not yet confirmed. Build to it unless KP says otherwise.
- **Open**: still needs an answer.

## The ground rule (KP, 16 Oct)

Team RVM is its own app. **Nothing in Scheduler_Backend or Scheduler_frontend changes for it.** The Scheduler only supplies information and its existing endpoints, used as they are ([ADR-0018](adr/0018-team-app-changes-nothing-in-the-scheduler.md)). Within that rule KP chose:

| Topic | Answer |
| --- | --- |
| Punching | The app punches through the Scheduler's existing punch API, unchanged: the same rules and records as the web punch page |
| Team-app data | New `hr_ess_*` tables in the same database; the Scheduler's code and web never use them ([ADR-0021](adr/0021-migrations-new-tables-only.md)) |
| Approvals | They write the official day through HR's existing override function, so HR's daily sheet and payroll see them ([ADR-0020](adr/0020-approvals-through-the-override-function.md)) |
| Hosting | The backend runs on its own subdomain on the same server, with its own nginx file ([ADR-0019](adr/0019-ess-on-its-own-subdomain.md)) |

## The 16 decisions in the brief

| # | Decision | Answer | Status | Source | Tasks affected |
| --- | --- | --- | --- | --- | --- |
| 1 | Who approves requests | The reporting manager on the HR record (`hr_employees.manager_id`), or HR when none is recorded. HR, the CEO and super admins can decide any request; their decision is recorded as HR's. For attendance and leave requests, "HR" means the `hr` role only: the Scheduler's `ATTENDANCE_OVERRIDE_ROLES` (hr, ceo, super_admin), never `HR_ROLES`, which includes `hr_executive`. | Decided | KP, 16 Oct | C10, D1, H6 |
| 2 | Monthly request limits | See [Request limits](#request-limits) | Decided | KP, 16 Oct | C3, C6 |
| 3 | Tabs for Admin, Admin Manager and Finance Admin | All five tabs (Home, Inbox, Wall, Me, My Team), with no Work section | Decided | KP, 16 Oct | A4 |
| 4 | Sign-in screen | One field: phone, email, employee code or username. Credentials stay the same. A portal account can only sign in with its username or login phone, so the app asks for one of those when the field holds a portal account's email or employee code. | Decided | KP, 16 Oct | A5 |
| 5 | Location with the screen off | Yes, while punched in. A foreground service with a visible notification sends a ping every 2 minutes. It stops at the first of: punch-out, the end of the shift plus its grace period, or midnight IST. When a ping answers 204, the app re-reads `GET /api/hr/my-attendance` to decide whether to stop. Google Play's location declaration is needed. | Decided | KP, 16 Oct | B4 |
| 6 | Mocked location | The app refuses the punch on the phone and reports the attempt to the ESS for HR (the Scheduler's punch API can't take a mock flag without a change). Not yet confirmed: what happens to a mocked ping (the proposal is to report it to HR the same way). | Decided (punch); Open (pings) | KP, 16 Oct | B14 |
| 7 | Offline punching | Not allowed in the first version ("Punching needs a connection") | Default | Brief | B15 |
| 8 | Posting on the Wall | Everyone can post, comment, react, praise and run polls. Only HR, the CEO and super admins post announcements. HR can hide anything, with a reason. | Decided | KP, 16 Oct | F1–F8 |
| 9 | Colleague contact details | Work email is visible to everyone. A phone number is visible only to HR and to the managers above that person on the HR record, so a manager sees their reports' phones. KP to confirm whether an employee also sees their own managers' phones. | Decided (KP to confirm one point) | KP, 16 Oct | E2, E8 |
| 10 | Pay in the app | Nothing for now | Default | Brief | E1 (never return pay) |
| 11 | Moving phones from the browser to the app | HR resets the registered phones in bulk, branch by branch, at go-live. Only a one-at-a-time reset exists today, so the ESS adds an HR action that writes the same device rows the Scheduler's own reset writes (KP to confirm). A reset browser can't punch while it keeps its old cookie. | Decided | KP, 16 Oct | B8 |
| 12 | Build stack | Flutter, in team_app (not flutterapps) | Decided | KP, 16 Oct | — |
| 13 | Distribution | Google Play, from an organisation account, with closed testing for the pilot. Not yet confirmed, but Phase 0 starts the account now because the D-U-N-S number takes time. | Default | Brief | K6 |
| 14 | Overtime | None, anywhere. The brief advises asking counsel first, because the Code on Wages pays overtime at twice the normal rate. | Decided | KP, 15 Oct | B10 |
| 15 | First sign-in | Unchanged: HR's first-time password, then the employee chooses their own. The one-time-code route also stays. | Decided | KP, 15 Oct | A2 |
| 16 | Punch button colours | Forge Orange to punch in, Ironwood to punch out | Default | Brief | None (app only) |

This table has its own order. In the brief and the gap report, "Overtime" is the 15th decision and "First sign-in" the 16th.

## Request limits

Limits are per employee, per calendar month. HR can change them later (task C6).

| Request | Limit | Notes |
| --- | --- | --- |
| Work from home | Not allowed | The request type is hidden. |
| On duty | No limit | Each request still needs approval. An approved day is written as present (on duty) and needs no punch ([ADR-0020](adr/0020-approvals-through-the-override-function.md)). |
| Fix a day | 3 | |
| Excuse a late | 3 | |
| Short leave | 180 minutes | Phase 2. It works by excusing the late it covers ([ADR-0020](adr/0020-approvals-through-the-override-function.md)). |
| CL (casual leave) | 1 | The code at `c28b9ca` relies on a unique index for this. Its migration skips the index (with only a notice) if anyone already had two CLs in a month, so confirm the index exists in production. The ESS checks the limit itself either way. |
| Leave without pay | Not set | Open |

**Payroll cut-off: the 5th of the next month** (KP, 16 Oct). Requests can reach back to this month and last month, and last month's requests close at the cut-off. Still to confirm with KP:
- whether the 5th itself is still open;
- whether a request for last month raised before the cut-off can still be approved or cancelled after it.

## Other decisions

| Decision | Answer | Status | Source |
| --- | --- | --- | --- |
| HR Executive in the app | HR's powers without attendance or leave: approves documents, profile changes and HR helpdesk tickets, never HR-wide attendance or leave, and makes no overrides. An HR Executive who manages people approves their own team's attendance and leave requests as that team's manager, like any manager. | Decided | KP, 16 Oct (the role as defined on 15 Oct; the manager answer the same evening) |
| Who sees the location trail | HR, the CEO and super admins, as today. No manager view. | Default | Scheduler today |
| Keeping location pings and logs | No automatic deletion; KP deletes them by hand ([ADR-0015](adr/0015-no-automated-retention.md)) | Decided | KP, 16 Oct |
| Push before Firebase is set up | Messages go to the log until the keys are added ([ADR-0016](adr/0016-push-and-integrity-start-off.md)) | Decided | KP, 16 Oct |
| Shared desk logins (fbd.admin and similar) | None are allowed at all: every app login belongs to one employee, and each admin signs in as themselves. There is no list to keep. A portal login with no linked HR record is refused (403 `NOT_LINKED`); one linked to somebody's record would act as that person, so RVM gives each person their own login | Decided | KP, 16 Oct |
| Staying signed in (task A3) | The ESS swaps a fresh sign-in for a refresh token and issues short sign-in tokens in the Scheduler's own formats. They last 1 hour; the sign-in lasts 90 days from its last use. It ends on an attendance password change, when HR switches the login off, on exit, or on signing out | Decided | KP, 16 Oct |
| HR's bulk phone reset (task B8) | Writes the same device rows the Scheduler's own reset writes, branch by branch, for HR, the CEO and super admins | Decided | KP, 16 Oct |
| Faculty class marking in the app (Phase 2) | `POST /api/attendance` keeps its missing server checks, because fixing them is a Scheduler change. Decide before Phase 2 whether the app offers marking. | Open | [ADR-0018](adr/0018-team-app-changes-nothing-in-the-scheduler.md) |

## What RVM must provide (Phase 0)

- A Firebase project for push, and a Google Play organisation account for RVM Beyond Pvt Ltd. The Play account needs a D-U-N-S number.
- The ESS's own subdomain, `team-api.rvmcad.org`, and team_app's deploy secrets: both done by KP on 16 Oct ([ADR-0019](adr/0019-ess-on-its-own-subdomain.md)). Next comes the read-only server check, then the first deploy ([05-deploy.md](05-deploy.md)).
- From HR:
  - joining dates for imported employees, now (anniversary and new-joiner cards need them);
  - the main phone and email checked for every employee;
  - date of birth, blood group, address and emergency contact, once the ESS's personal-details screen exists.
- Every HOD and HoO on the right login role, every portal login linked to its HR record, and no shared desk logins.
- A privacy and location policy page that names a grievance officer.
- From the brand designer: master logo files and an "rvm TEAM" lockup. Pages 9 and 10 of the brand guidelines also need fixing.

## 19 Oct 2026 - Phase 2A and 1E decisions (KP)

- The ESS's files live in its own private Supabase bucket, `ESS` (created by KP, 19 Oct). Employee photos stay in the Scheduler's `documents` bucket, where the HR record's path lives; wall photos, praise photos and later ESS files go to `ESS`.
- Praise badges are FIXED: not HR-editable. The catalogue ships in code.
- Staff announcement email has no provider yet: log-only, like push. The Firebase project is issue #1 against Rishi; push stays log-only until it exists.
- An employee's own photo change needs NO HR approval (audited; the old file is left for cleanup).
- HR data (date of birth, joining date) is pulled from the HR database; nothing is requested from KP.
