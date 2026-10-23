# Migration status, verified 23 Oct 2026

This is the single answer to the 28/29 conflict in the programme issues (#9, #93, #102) and to
the stale lines in `04-build-plan.md` and `06-backend-phases.md`.

**The check was read-only.** It is the repository's own
[`verify-migrations.yml`](../.github/workflows/verify-migrations.yml), dispatched on 23 Oct 2026
as run [39939895079](https://github.com/RVM-BEYOND-PRIVATE-LIMITED/team_app/actions/runs/39939895079).
It probes production PostgREST with the deploy's own secrets and changes nothing. Result:
**0 missing checks** — every `hr_ess_*` table, column and seed the migrations create is present,
including:

- `hr_ess_wall_posts.poll_closed_at` (migration 28's repair);
- `hr_ess_wfh_allowances` (migration 29);
- the six seeded request limits, nine document types, ten helpdesk categories and the POSH
  queue's `internal_committee`.

No migration was run by this pass. KP applies migrations by hand (ADR-0021); this table only
records what the read-only check found.

| # | Migration (`db/migrations`) | Rollback (`db/rollbacks`) | Creates (short) | Feature | Applied |
| --- | --- | --- | --- | --- | --- |
| 1 | `20261101000000_hr_ess_sessions.sql` | same name | `hr_ess_sessions`, rotate/revoke/password functions | A3 | yes |
| 2 | `20261105000000_hr_ess_audit.sql` | same name | `hr_ess_audit` | A8, B8, E9 | yes |
| 3 | `20261105000001_hr_ess_data_requests.sql` | same name | `hr_ess_data_requests` + open-limit trigger | A8 | yes |
| 4 | `20261105000002_hr_ess_personal_details.sql` | same name | `hr_ess_personal_details` | E9 | yes |
| 5 | `20261105000003_hr_ess_mock_location_reports.sql` | same name | `hr_ess_mock_location_reports` | B14 | yes |
| 6 | `20261106000000_hr_ess_request_limits.sql` | same name | `hr_ess_request_limits` + seeds | C6 | yes |
| 7 | `20261106000001_hr_ess_attendance_requests.sql` | same name | attendance requests + history | C1, C3 | yes |
| 8 | `20261106000002_hr_ess_leave_requests.sql` | same name | leave requests + history | C2, C4 | yes |
| 9 | `20261106000003_hr_ess_request_archives.sql` | same name | `hr_ess_request_archives` | D1 | yes |
| 10 | `20261106000004_hr_ess_request_functions.sql` | same name | seven decide/withdraw/cancel/apply functions | C7, C8, D1, H6 | yes |
| 11 | `20261107000000_hr_ess_push_devices.sql` | same name | `hr_ess_push_devices` | D5 | yes |
| 12 | `20261107000001_hr_ess_notifications.sql` | same name | notifications + settings | D6, D8 | yes |
| 13 | `20261108000001_hr_ess_wall_posts.sql` | same name | posts, comments, polls, reactions, mentions, wishes | F1–F4, F6, F9 | yes |
| 14 | `20261108000002_hr_ess_wall_reports.sql` | same name | reports + celebration opt-outs | F6, F7 | yes |
| 15 | `20261108000003_hr_ess_announcements.sql` | same name | announcements, audience, reads | F5 | yes |
| 16 | `20261108000004_hr_ess_notification_categories.sql` | same name | notification category CHECKs | F8 | yes |
| 17 | `20261109000001_hr_ess_helpdesk.sql` | same name | categories, tickets, messages, ref sequence | G1–G5 | yes |
| 18 | `20261109000002_hr_ess_notification_categories.sql` | same name | `helpdesk` category CHECK | G2, G3 | yes |
| 19 | `20261110000001_hr_ess_documents.sql` | same name | document types + documents | E4 | yes |
| 20 | `20261110000002_hr_ess_change_requests.sql` | same name | `hr_ess_change_requests` | E3 | yes |
| 21 | `20261110000003_hr_ess_bank_details.sql` | same name | `hr_ess_bank_details` | KP 3 | yes |
| 22 | `20261110000004_hr_ess_helpdesk_assignment.sql` | same name | assignment columns + history | KP 5 | yes |
| 23 | `20261110000005_hr_ess_posh_queue.sql` | same name | POSH queue role + seed | KP 6 | yes |
| 24 | `20261110000006_hr_ess_notification_documents.sql` | same name | `documents` category CHECK | E4 | yes |
| 25 | `20261111000001_hr_ess_short_leave.sql` | same name | `short_leave` type + minutes | C3 | yes |
| 26 | `20261111000002_hr_ess_approval_escalations.sql` | same name | `hr_ess_approval_escalations` | D4 | yes |
| 27 | `20261112000001_hr_ess_infra_links.sql` | same name | `hr_ess_infra_links` | G6 | yes |
| 28 | `20261112000000_hr_ess_wall_poll_closed_repair.sql` | same name | `hr_ess_wall_posts.poll_closed_at` | F4 | yes |
| 29 | `20261113000001_hr_ess_wfh_allowances.sql` | same name | `hr_ess_wfh_allowances`, WFH decide branch | WFH (C3) | yes |

## Run order and reversibility

Apply in the number order above; roll back in reverse. All 29 are additive `hr_ess_*` objects
(ADR-0021) and each rollback file is beside its migration. Migration 23 is the only one that
modifies a seeded row rather than a table shape, and its rollback restores it. None alters a
Scheduler table.

## What this settles

- Issue #9 was right: **29 is applied**.
- `04-build-plan.md` and `06-backend-phases.md` said 28–29 were still to apply; they have been
  corrected to point at this check.
- The Wall (F), the infra mirror (G6) and WFH (C3) are not blocked by a missing migration.
