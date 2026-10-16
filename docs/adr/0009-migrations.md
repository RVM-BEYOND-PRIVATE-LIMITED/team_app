# ADR-0009: Where migrations live and how they reach production

- Status: Superseded by [ADR-0021](0021-migrations-new-tables-only.md) (16 Oct 2026). This proposal is kept for history; its split into team_app and Scheduler migrations no longer applies, because Scheduler tables are never altered.
- Date: 16 Oct 2026
- Decided by: KP, through ADR-0021
- Source: STEP 0 recommendation of 16 Oct 2026

## Context

- **One database.** Both services share one database ([ADR-0003](0003-scheduler-is-system-of-record.md)).
- **The Scheduler's migrations.**
  - Location and naming: they live in `Scheduler_Backend/supabase/migrations` and are named `<14-digit number>_<name>.sql`. The latest on 16 Oct 2026 was `20261023000000`.
  - Checks: `scripts/lintMigrations.js` checks their names, and its Docker test stack applies the `_hr*` ones.
- **Applied by hand, after the code.** KP applies migrations by hand in the Supabase SQL editor. Code deploys on merge, before its migration is applied ([ADR-0011](0011-ci-merge-and-auto-deploy.md)).

## Decision (proposed)

1. **Where.**
   - New tables (`hr_ess_*`) go in `team_app/db/migrations/`.
   - Changes to tables the Scheduler owns go in `Scheduler_Backend/supabase/migrations/`, through a Scheduler PR.
2. **Numbering.** One sequence across both repositories. Before picking a number, look in both folders.
3. **Rollback.** Every migration ships with `<same name>.down.sql`, and is additive and safe to re-run where possible.
4. **Applying.** Only KP applies migrations to production; agents never run one. Afterwards an agent checks the result read-only:
   - a missing table answers `PGRST205`, a missing column `42703`;
   - functions are confirmed in the PostgREST OpenAPI listing;
   - a constraint is confirmed by attempting the write it should allow or refuse.
5. **Deploy window.**
   - Until its tables exist, every ESS endpoint answers 503 `MODULE_NOT_INSTALLED`, never a 500.
   - Scheduler code that reads a new column falls back to the old column list on `42703` or `PGRST204`.
6. **Tests.** Tests run on Docker Postgres with PostgREST, like the Scheduler's `tests/stack.js`, with the Scheduler's migrations applied first. Never on production.

## Consequences

- The production schema's history is split across two folders. The handover lists every migration in run order.
- **Check production first.** Before any ESS function relies on the attendance migrations, confirm read-only that they are applied in production: `20261020000000` to `20261023000000`, and the one-CL-a-month index. The code switches features off silently when they are missing ([02-reconciliation.md](../02-reconciliation.md)).
- **Approved days are Scheduler migrations.** Approved request days need a new `source` value on `hr_staff_attendance` and an `on_duty` work mode. Those change a table the Scheduler owns, so under this ADR they are Scheduler migrations.
- The Scheduler's migration lint and test stack keep covering changes to its own tables.
