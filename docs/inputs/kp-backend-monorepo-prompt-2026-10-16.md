# Prompt for KP — build the missing Team RVM backend (monorepo)

> **KP:** copy everything below the line into your AI coding agent (Claude Code or similar), run it from the folder where you want the work done, and attach or point it at the two PDFs listed in "Inputs". The agent will **ask you questions first** (where the monorepo goes, which kind, and so on) and will not write code until you answer.

---

## Role and goal

You are the backend engineer for **RVM CAD**. We are building **Team RVM** (`rvm_team_app`), an Android employee app modelled on the Keka employee app: punch in/out, requests and approvals, inbox and push, Wall, Helpdesk, and Me / My Team. The Flutter app will be built against **whatever backend exists**, and the backend features it needs that are missing must be built by you.

Your job is to build every **missing or to-be-updated** backend item from the gap report, organised as a **monorepo**, without breaking anything the live web portal (`scheduler.rvmcad.org`) or the existing mobile apps use today.

## Inputs (read both fully before doing anything)

1. **Gap report** — `rvm_teamapp_gap.pdf` ("Team RVM — Backend Gap & Task Report", 16 Oct 2026, 15 pages). It lists what exists, what is missing and what must change, task IDs **A1–K6**, the 16 decisions, and the evidence. Some table cells in section E are cut off in text extraction, so read the **PDF itself**, not just extracted text.
2. **App brief** — `rvm_team_app_requirement.pdf` ("Team RVM App Brief", 15 Oct 2026, 37 pages). This is the CEO's full requirement: the Keka parity map, phases (1 / 2 / 3 / Later), rules, decisions and role views.
3. **Existing backend** — `Scheduler_Backend` (Node/Express + Supabase/Postgres, `config/roles.js`, `middleware/auth.js`, `supabase/migrations/`, vitest + supertest).

If you cannot find either PDF, stop and ask me for its location.

## STEP 0 — Ask me these questions first. Wait for my answers. Write nothing yet.

Ask them as one numbered list. Where useful, offer options and a recommendation, but **do not assume an answer**.

**Monorepo**
1. **Where** should the monorepo live? Options: a brand-new repository (give name and GitHub org), the existing `Scheduler_Backend` converted into a monorepo, or a new top-level folder inside an existing repo. Give the exact path or URL.
2. **Which kind** of monorepo? Options: npm / pnpm / yarn workspaces, Turborepo, Nx, or something else. Which package manager and which Node version?
3. **What goes inside it?** Options: only the new Team RVM (`/api/ess`) backend; the new backend plus `Scheduler_Backend` moved in as a package; or shared packages (auth, roles, DB client, types) used by both. Should the existing Scheduler stay where it is and only consume shared packages?
4. **Package layout and names**: for example `apps/scheduler-api`, `apps/ess-api`, `packages/auth`, `packages/db`, `packages/contracts`. Propose a layout and let me confirm it.
5. **Language and framework**: keep JavaScript / Express like `Scheduler_Backend`, or use TypeScript for new packages? Any framework change needs my explicit yes.

**Runtime and data**
6. **One service or two?** Should the new endpoints run inside the same Express process as the Scheduler (same port, same nginx at `scheduler.rvmcad.org`), or as a separate service behind nginx at a path such as `/api/ess`?
7. **Database**: the same Supabase project as the live Scheduler, or a separate one? Where do new migrations live, and how are they applied (Supabase CLI, manual, CI)? **Never run a migration against production without my explicit OK.**
8. **Current backend revision**: the gap report audited `d2595e4` (24 Sep 2026), but the brief says attendance and ESS are "live on web" at commit `c28b9ca`, which is not in that checkout. Where is the latest backend? If the attendance / ESS work exists there, most of sections B, C and D become **verify only**.
9. **Git and deploy**: branch naming, PR flow, who reviews, and how and where it deploys (the deploy workflow, nginx config, secrets location). Never push to `main` or deploy without my OK.

**Product decisions the backend depends on** (gap report §5 and the brief's "Decisions")

10. For each of the 16 decisions, accept the recommended answer or give a different one. In particular: who approves requests; the monthly limits (WFH 2, on-duty 4, fix-a-day 3, excuse-late 2, short leave 120 min, CL 1); mocked location (refuse vs flag); offline punching; colleague contact visibility; overtime; first sign-in flow; one-field vs two-field sign-in.
11. **HR Executive** role: add `hr_executive` to `config/roles.js`, or treat it as `hr`?
12. **Phase scope** for this round: Phase 1 only, or Phases 1 + 2?

After I answer, repeat back a short summary of the decisions and wait for my **"go"**.

## STEP 1 — Reconcile the gap report against the real backend (no code)

The report may be out of date (see Q8). For **every task ID A1–K6**, check the current backend and mark it **AVAILABLE / UPDATE / MISSING / VERIFY-PASSED**, with file:line evidence. Never rebuild something that already exists. Show me the reconciled table and wait for approval.

## STEP 2 — Plan (no code)

Using the answers and the reconciled table, give me:
- the monorepo structure (folders, packages, what each owns);
- the order of work: **security fixes first** (section J), then identity and session (A), then Phase 1 features, then the rest;
- the list of new tables and columns (section I) as migration files, each reversible;
- the API contract: one **OpenAPI file** covering every new or changed endpoint (paths, request and response bodies, error `code`s). The Flutter team builds against this file, so it is the deliverable that matters most;
- risks and anything that could break the live web portal or the existing staff and student apps.

Wait for approval before building.

## STEP 3 — Build, phase by phase

Work through the approved plan. After each section, run the tests and report what was done and which task IDs are complete.

### Task checklist (every ID must end up DONE, VERIFIED or explicitly DEFERRED with a reason)

- **A — Identity, auth, session:**
  - A1 `employeeAuth` (portal token **or** attendance session → `hr_employees.id`)
  - A2 HRMS attendance sign-in (password, OTP, first-time and forced change, lockout 5 → 15 min)
  - A3 short access token + rotating, hashed, install-bound refresh token (revoked on password change, HR disable or exit)
  - A4 `GET /api/ess/me/capabilities`
  - A5 single-field sign-in resolver
  - A6 per-employee rate limiting
  - A7 sign out everywhere + reject old tokens after a password change
  - A8 data/account deletion request (Google Play requirement)
  - A9 retire `POST /api/users/reset-password`
  - A10 block shared-desk logins from PIN, biometric and phone binding
- **B — Attendance punch:**
  - B1–B5: month view with `server_now`, challenge, punch with all error codes, 2-min ping, own remark
  - B6 geofence + field-staff exemption
  - B7 accuracy rule
  - B8 one phone per person + HR reset
  - B9 shifts, week-offs, holidays
  - B10 late / half-day engine + 00:05 midnight close
  - B11 one session per day
  - B12 holiday list
  - B13 User-Agent rule
  - B14 `is_mock`
  - B15 batched offline pings + purge
  - B16 leader/HR board and controls
  - B17 lock against the Admin Manager daily sheet
- **C — Requests, leave, approvals:**
  - C1 request tables, history and `work_mode`
  - C2 CL/LWP
  - C3 attendance requests + quotas
  - C4 leave requests
  - C5 balances
  - C6 limits config
  - C7 one DB function per request type
  - C8 withdraw / HR cancel
  - C9 daily-sheet lock
  - C10 approver resolution (manager → HR fallback)
  - C11 faculty leave reaches staff attendance
  - C12 reach-back window + payroll cut-off
- **D — Inbox, notifications, push:**
  - D1 approvals inbox + decide
  - D2 priority tasks visible to every role except CEO
  - D3 task remarks
  - D4 multi-level chains (Phase 2)
  - D5 FCM device registration
  - D6 notifications + unread count
  - D7 Firebase push worker + secret length check
  - D8 categories, opt-outs and quiet hours
- **E — Me / My Team:**
  - E1 self profile (never pay or HR remarks)
  - E2 org chain + directory
  - E3 sensitive change requests
  - E4 employee documents (upload, verification, signed 5-min links, masked Aadhaar, no storage paths)
  - E5 HR review queues
  - E6 team today / off this week
  - E7 digital ID card
  - E8 contact visibility rule
  - E9 `date_of_birth`, `blood_group`, `address`, `emergency_contact` on `hr_employees`
  - E10 photo exposure
  - E11 notice-period chip
  - E12 timeline from HR events
- **F — Wall:**
  - F1 posts
  - F2 reactions and comments
  - F3 praise and badges
  - F4 polls
  - F5 staff announcements with audience, ack and pin (the existing `announcements` table is student/batch-only)
  - F6 celebrations
  - F7 moderation
  - F8 wall settings
  - F9 image compression + storage
- **G — Helpdesk:**
  - G1 categories
  - G2 tickets and lifecycle (`HD-0001…`)
  - G3 working-hours SLA + escalation
  - G4 confidential categories
  - G5 agent workspace
  - G6 mirror into `infra_tickets`
- **H — Role views:**
  - H1 server-side checks on attendance marking
  - H2 trim the roster columns (no password hashes)
  - H3 `hod_placement` as interviewer
  - H4 HoO team today
  - H5 light KPI endpoints
  - H6 HR approval endpoints
  - H7 faculty "my day"
  - H8 re-role HOD/HoO (ops: list the accounts for me, do not change roles yourself)
- **I — Data model:** every table, column and DB function in section I, as reviewed migrations.
- **J — Security before launch:**
  - J1 attendance POST
  - J2 roster leak
  - J3 batch writes with no role check
  - J4 announcement writes with no role check
  - J5 reset-password
  - J6 roles
  - J7 upload limit + health
  - J8 401 only for real token rejection (`No token provided` / `Please authenticate`); nginx HTML must not come back as a JSON 200
  - J9 Play Integrity
  - Also close the open items in GitHub issue **#70** on `Scheduler_Backend`: `/api/activities` without auth, public course writes, public intake list, public `/api/chat`, `ensureFacultyId` blank email, missing `/api/intakes/by-phone`.
- **K — Infra:**
  - K1 nginx upload limit
  - K2 health + minimum-app-version
  - K3 `FIREBASE_*` in deploy with a length check
  - K4 per-employee rate limit
  - K5 ping purge + 180-day log retention
  - K6 Play Integrity / Keystore / Data-safety notes

## Rules (always)

- **Do not assume.** If the docs, the code and my answers don't settle something, ask.
- **Don't break what is live.** The web portal and the existing `staff_app` / `student_app` must keep working. Changing an existing endpoint's behaviour needs my OK and a note in the contract.
- Follow the existing conventions:
  - roles and inheritance from `config/roles.js`;
  - auth through the real middleware;
  - errors as `{ "error": "...", "code": "..." }`;
  - IST dates;
  - Supabase via the existing DB client.
- **Security:** every new route needs `auth` (or `employeeAuth`) plus a role or ownership check. Never return password hashes, storage paths or full Aadhaar. 401 is only for a rejected or absent token. Use 403 or 409 for everything else.
- **Tests:** add vitest/supertest tests for every endpoint, including the role-denied and wrong-owner cases. All tests must pass before you report a section as done.
- **No production writes, migrations, pushes or deploys without my explicit OK.** No secrets in code or commits.
- **Final deliverables:**
  1. the monorepo, working, on a branch;
  2. the OpenAPI contract;
  3. the migrations list with run order;
  4. the env vars and secrets needed;
  5. deploy steps;
  6. a final table of every task ID (A1–K6) with status and evidence, and anything deferred with a reason;
  7. a short handover note for the Flutter team: base URL, auth flow, endpoints per screen and error codes.

**Start with STEP 0 now: ask me your questions.**
