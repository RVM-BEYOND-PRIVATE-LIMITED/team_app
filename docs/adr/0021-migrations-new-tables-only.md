# ADR-0021: Migrations add new hr_ess_* tables only, and live in team_app

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's answers of 16 Oct 2026 ("Same database, new tables") and [ADR-0018](0018-team-app-changes-nothing-in-the-scheduler.md)
- Supersedes: [ADR-0009](0009-migrations.md) (Proposed)

## Decision

1. **Where.** Migrations live in `team_app/db/migrations/` and are named `<14-digit number>_hr_ess_<module>.sql`. They only create new things: `hr_ess_*` tables, their indexes and policies, and new functions. They never alter or drop a table the Scheduler owns.
2. **Numbering.** One sequence across the shared database. Before picking a number, look at both team_app's folder and Scheduler_Backend's `supabase/migrations` (read only). The Scheduler's latest on 16 Oct 2026 is `20261023000000`.
3. **Rollback.** Each migration has a rollback script of the same name in `team_app/db/rollbacks/`, outside the migrations folder, so no tool ever replays it as a forward migration.
4. **Safety.** Migrations are additive and safe to re-run (`IF NOT EXISTS`). Row-level security is on with deny-all policies, as on the Scheduler's tables, so only the service role reads and writes.
5. **Applying.**
   - Only KP applies migrations, by hand in the Supabase SQL editor. Agents never run one.
   - Afterwards an agent checks the result read-only through PostgREST: a missing table answers `PGRST205`, a missing column `42703`, and functions are looked up in the OpenAPI listing.
   - Constraints and indexes are confirmed by a catalog query KP runs (`pg_indexes`, `pg_constraint`), never by trying a write in production.
6. **Deploy window.** Code deploys on merge, before KP applies its migration ([ADR-0011](0011-ci-merge-and-auto-deploy.md)). So every ESS endpoint answers 503 `MODULE_NOT_INSTALLED` until its tables exist, never a 500.
7. **Tests.** Production is never used. Until team_app has a migration, the tests use no database: they run the real store over an in-memory stand-in (`apps/ess-api/tests/helpers/fakeSupabase.js`) that answers `PGRST205`, `42703` and `PGRST116` as PostgREST does, and CI starts no database. From the first migration on, they also run on a local Postgres, with the schema in two parts:
   - a snapshot of the Scheduler tables the ESS reads, generated from the Scheduler's migrations by a script and refreshed by hand;
   - then team_app's own migrations.

## Consequences

- The shared database's history is split across two folders. The handover lists every team_app migration in run order.
- The ESS reads Scheduler tables. It writes them only through the paths named in [ADR-0020](0020-approvals-through-the-override-function.md).
