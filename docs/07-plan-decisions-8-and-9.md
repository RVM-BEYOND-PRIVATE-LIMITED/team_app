# Plan: decisions 8 and 9 (faculty class marking, the infra register)

22 Oct 2026 · **Approved by KP on 22 Oct 2026 and built**: H1 and G6 are in `main`, and migration 27
is the only database step left (plus 13-16, the Wall's). · Backend: `apps/ess-api`

Two decisions were left open because each writes a Scheduler table, which ADR-0018 and ADR-0021
forbid unless KP sanctions the write. This plan states the exact writes, the rules, the endpoints,
the tests and the rollout for both, so the sanction can be given once and the build run to the end.

The plan changes **no Scheduler code and no Scheduler schema**. It adds one `hr_ess_*` table
(migration 27), three ESS routes and one hourly job. Everything else is code in `team_app`.

---

## 1. The approval this plan needs

The ESS currently writes exactly three Scheduler tables (asserted by `tests/store.test.js:252-269`):
`hr_attendance_devices` (HR's phone reset), `hr_staff_attendance` (the shift snapshot the
Scheduler's own override function also writes) and `hr_employees` (photo columns only).

This plan adds three more, each through **one named store method** and nothing else:

| Scheduler table | Operations | Columns written | Why |
| --- | --- | --- | --- |
| `student_attendance` | upsert (`insert ... on conflict (batch_id, student_id, date) do update`), update | `student_id, batch_id, date, is_present, absent_reason, follow_up_comment, remarks_updated_by, remarks_updated_at` | H1 class marking and its absent remarks (the Scheduler's own rows) |
| `pending_alerts` | update | `is_resolved, resolved_at, resolved_by` | Resolve the "absent remarks missing" alert when a student is marked present or the reason is filled — exactly what `attendanceController.js:149-162,1194-1201` does |
| `infra_tickets` | insert, update | insert: `location_id, raised_on, audit_type, issue, owner, deadline, raised_by`; update: `status, closed_on` | G6: the Admin Manager's register row for lab/facility helpdesk tickets |

Never a delete; never any other column or table. `store.test.js` is extended to allow exactly
these methods and to assert each table appears once, so a later change cannot quietly widen them.
The same rule is written into `docs/04-build-plan.md` and the ADR record.

**Decisions embedded in the plan (KP to confirm with the sanction):**
1. An Admin Manager closing the register entry **resolves the helpdesk ticket** (with a system
   event, and the raiser is told). The register is the Admin Manager's system of record; the
   helpdesk follows it. The reverse also holds: closing the ticket closes the register entry.
2. Anonymous helpdesk tickets are mirrored **without identity** (`raised_by` and `owner` null);
   the register sees the summary, never the person.
3. Only `it_lab` and `facility` are mirrored. POSH, grievance, HR documents and payroll never are.
4. The ESS sends a summary row to the register, not the thread: `issue = "<HD-ref>: <subject>"`.

---

## 2. Decision 8 — faculty class marking (H1)

### Why it was open

`POST /api/attendance` (Scheduler) has no server-side checks: `denyWrite` refuses nobody, a
student token is accepted, and the batch/date/roster/ownership checks live only in the browser
(02-reconciliation.md, H1; `attendanceRoutes.js:43`, `attendanceController.js:124-145`). Offering
marking in the ESS while those stay open means the ESS must implement the checks itself.

### What the ESS will offer

Three routes, all behind `employeeAuth`, all portal logins (teaching roles and the admin roles
the Scheduler's register trusts):

| Route | Who | Answer |
| --- | --- | --- |
| `GET /api/ess/me/batches/{id}/roster?date=YYYY-MM-DD` | the batch's faculty or covering substitute; admin roles for their branch | batch, date, `already_marked`, `can_edit`, and the eligible students: `id, full_name, admission_number, marked ('present'\|'absent'\|null), absent_reason, follow_up_comment` |
| `POST /api/ess/me/batches/{id}/attendance` `{ date, attendance: [{ student_id, present, absent_reason?, follow_up_comment? }] }` | same | the saved day, with counts |
| `PATCH /api/ess/me/batches/{id}/attendance/{date}/remarks` `{ student_id, absent_reason, follow_up_comment? }` | same | the updated mark |

### The rules (the H1 list, made real)

1. **Who may mark.** `faculty`, `hod` (teaching) and the Scheduler's admin roles: `admin`,
   `admin_manager`, `hoo`, `accounts_admin`, `ceo`, `super_admin`. `hr`, `hr_executive`,
   `hod_placement` and students are 403 `CLASS_ROLE_DENIED`.
2. **Branch.** A teaching caller marks only batches they own or cover. An admin caller marks
   batches in their own branch (by `locations.id` mapped from the employee's `hr_branches.name`);
   `ceo` and `super_admin` are global.
3. **Ownership or substitution.** For `faculty`/`hod`: `batches.faculty_id = users.faculty_id`, or
   a `faculty_substitutions` row for that batch whose range includes the date with
   `substitute_faculty_id = users.faculty_id`. Otherwise 403 `CLASS_NOT_YOURS`.
4. **The date.** A real `YYYY-MM-DD`, `batch.start_date <= date <= min(batch.end_date, today IST)`.
   No future days: 403 `CLASS_WINDOW`.
5. **The roster.** Every `student_id` in the body must be on `batch_students` for the batch and be
   eligible on the date: `batch_students.joined_at` set, and `admissions.joined` true unless the
   student has no admissions row at all (the Scheduler's own rule,
   `utils/attendanceEligibility.js:55-89`), and not on hold (a `hold_periods` row covering the date,
   or `students.is_on_hold` with `hold_applied_at <= date`). Anything else: 400 `CLASS_ROSTER`.
6. **The lock after the first save.** A teaching caller gets 409 `CLASS_ALREADY_MARKED` when the
   batch+date already has rows; admin roles may correct the day. The rule is server-side only —
   the web's lock is client-side (`BatchTable.tsx:591-593`).
7. **The write.** Upsert one row per student. A student flipped to present resolves their
   `absent_remarks_missing` alert for that date (same condition the Scheduler's marking uses).
   An absent student keeps/accepts `absent_reason` (3 to 500 characters when present) and an
   optional `follow_up_comment` (up to 1,000). `remarks_updated_by` is the caller's name and
   `remarks_updated_at` the server's time — the Scheduler's own columns.
8. **Audit.** One `class.attendance.marked` entry per save (batch, date, present/absent counts —
   never names) and one `class.remark.changed` per remark (before/after reason), in
   `hr_ess_audit`, as the Scheduler records its own.
9. **No leak.** The roster returns names and admission numbers only — never a phone, password
   hash, fee or personal detail. The response is exactly the schema in the contract.

### What it does not do

- No class marking for a date in another month, no batch-wide "mark all" (the app can send all
  rows in one call), no editing another teacher's past day by a teaching role.
- No new tables; the Scheduler's `student_attendance` and `pending_alerts` are the record.
- It does not change the Scheduler's insecure endpoint; that remains a Scheduler-side gap (J1),
  listed as out of scope. The ESS is safe on its own.

### The bug this research found (fixed now, no approval needed)

H7's "active students" counted a roster link with `joined_at` as joined, but the Scheduler
cross-checks `admissions.joined` and excludes a student all of whose admissions have
`joined = false`. H7 now applies the same rule (`src/routes/facultyDay.js`,
`store.listAdmissionsJoined`), with a test. The H1 roster will use the same helper.

---

## 3. Decision 9 — the infra register mirror (G6)

### Why it was open

`infra_tickets` is the Admin Manager's branch register (`20260804000003:111-130`): A IT & PCs,
B machines/tools/material, C books/brochures/certificates, D facility/maintenance/AMC; open or
closed; a 7-day escalation flag. Faculty, HR, HODs and punch-only staff cannot write it, so an
ESS helpdesk ticket raised by them never appears there. The register must stay complete.

### What the ESS will do

- **On raise** of an `it_lab` or `facility` ticket: after the ticket row exists, best effort,
  insert one `infra_tickets` row and record the link.
  - `it_lab` → `audit_type = 'A'`; `facility` → `'D'`.
  - `location_id`: the ticket's branch (`hr_branches.id`) mapped to `locations.id` **by name**
    (the two vocabularies differ, 02-reconciliation.md). No match → the link is `skipped`
    (`branch_not_mapped`) and the hourly job retries once the branches are fixed.
  - `raised_on`: the IST day. `issue`: `"<HD-ref>: <subject>"`. `deadline`: the IST date of the
    ticket's resolution deadline, when set. `owner`: the raiser's name only when `raised_by`
    cannot be set.
  - `raised_by`: the raiser's `users.id` when they have a portal login and the ticket is not
    anonymous; null otherwise (the reconciliation's rule for punch-only raisers).
  - The summary never contains the thread, attachments, or an anonymous raiser's identity.
- **On the helpdesk side** (resolve, close or withdraw): close the linked register row
  (`status = 'closed'`, `closed_on = IST day`) if it is still open.
- **On the register side:** an hourly job (`src/jobs/infra.js`, same shape as the others) reads
  linked open tickets whose register row is now closed and **resolves the helpdesk ticket** with
  a system event (`register_closed`), a resolution note ("Closed in the Admin Manager's infra
  register.") and a notification to the raiser. This is how "closing syncs both ways" happens
  without changing Scheduler code (no `closeInfraTicket` hook — ADR-0018).
- **Retries:** a `skipped` link is retried each run; a failed insert is logged, never fails the
  ticket. The link's unique keys make a retry idempotent.

### Schema (migration 27, `hr_ess_*` only)

`hr_ess_infra_links`:

| Column | Rule |
| --- | --- |
| `id` | uuid primary key |
| `ticket_id` | uuid, unique, references `hr_ess_helpdesk_tickets(id)` on delete cascade |
| `infra_ticket_id` | uuid, unique, null while skipped |
| `state` | `linked` or `skipped` |
| `reason` | text, the skip reason (`branch_not_mapped`, `foreign_key`, …) |
| `last_synced_at` | timestamptz |
| `created_at` | timestamptz default now() |

RLS on with no policy; grants to `service_role` only; safe to run twice; `NOTIFY pgrst`. Rollback
drops the table. One index on `infra_ticket_id` (the job's lookup).

### API surface

No new routes. The ticket detail (`GET /api/ess/helpdesk/tickets/{id}`) and the HR queue gain a
small object: `infra: { ticket_no, status, closed_on } | null`. Raising the ticket is unchanged
from the app's point of view; the mirror is a server-side side effect.

---

## 4. Contract, tests and docs

- **Contract:** `packages/contracts/openapi.yaml` **0.10.0**; three H1 paths and their schemas;
  the ticket detail's `infra` object; examples using exact `MESSAGES` strings. A **Wave 10**
  scenario table covers every documented status of every new route (role-denied, wrong owner,
  window, roster, lock, 503), merged into the three lists in `tests/contract.test.js`.
- **H1 tests (`tests/classMarking.test.js`):** roster for owner/cover/admin; branch and role
  refusals; date window; roster membership and eligibility (joined/admissions/hold); lock and
  admin correction; alert resolution; remark rules; no phone/hash in any reply; 503s.
- **G6 tests (`tests/infraMirror.test.js`):** raise creates the row/link; mapping A/D; branch name
  mapping and `skipped`; anonymous identity suppression; POSH/grievance never mirrored; ticket
  close closes the register; job resolves the ticket when the register closes; retry; 503.
- **Migrations:** `npm run test:migrations` gains migration 27's row rules and rollback twice.
- **Docs:** `04-build-plan.md` (Phase 2D/2B sections and the migrations table), `06-backend-phases.md`
  (H1 and G6 states), `05-deploy.md` (27), `apps/ess-api/README.md` (endpoints, settings, errors,
  contract version), `03-decisions.md` (the two decisions and the four embedded rules),
  `00-summary.md`.

## 5. Rollout

1. KP sanctions the three writes and confirms the four embedded rules (this plan).
2. Build H1 + G6 + migration 27 + contract + tests; all five checks green.
3. Deploy to `main`; KP applies migration 27.
4. Verify: a faculty login marks a batch and sees the 409 on re-open; an `it_lab` ticket appears
   in the Admin Manager's register; closing it in the register resolves the ticket within the hour.
5. No Scheduler deploy and no Scheduler schema change.

## 6. Risks

| Risk | Mitigation |
| --- | --- |
| A new Scheduler write goes wrong | One method per table, exact columns, audited, tested against a fake; no delete; a failed mirror never fails the ticket |
| Branch names differ between `hr_branches` and `locations` | The link records `branch_not_mapped`; the job retries; the fix is a data correction in HR/branches |
| Two people mark the same day | The lock is per batch+date for teaching roles; admins correcting concurrently last-write-wins, as the Scheduler's own upsert |
| Register close and ticket close race | Both paths are idempotent: closing a closed ticket/row is a no-op; the job only moves open tickets |
| Anonymous ticket identity leaks into the register | `raised_by` and `owner` are forced null for anonymous tickets; a test asserts it |
| H1 becomes a second, divergent marking system | It applies the Scheduler's six rules and writes the same rows and alerts; the Scheduler remains the record |

## 7. Estimate

- H1: 1.5–2 working days (routes, policy, roster/marking/remarks, tests, contract).
- G6: 1–1.5 days (link table, mirror, job, tests, contract).
- Docs and the full verification pass: half a day.

**Total: 3–4 working days.** No open question remains except the sanction and the four embedded
rules above; once confirmed, the build can run without stopping for another decision.
