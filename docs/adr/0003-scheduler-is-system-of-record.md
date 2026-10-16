# ADR-0003: The Scheduler stays the system of record, on one database

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: App Brief, Summary ("The Scheduler stays the single source of truth: the app calls the same backend and applies the same rules as the web"); KP on 16 Oct 2026 ("other functionalities can be pulled via API calls through the Scheduler frontend and backend"; "Same database, new tables")

## Context

- **One database holds everything.** Every employee, branch, attendance day, punch, shift and login already lives in the Scheduler's Supabase project, which is production.
- **There is no other database.** The old staging project is gone: its host stopped resolving on 14 Oct 2026.
- **The attendance rules live in the Scheduler.** Geofence, one phone per person, shifts, late marks, half days and the midnight close are implemented in Scheduler_Backend and its Postgres functions.

## Decision

- **Same database.** The new service uses the same Supabase project as the Scheduler. Its own data goes in new `hr_ess_*` tables ([ADR-0021](0021-migrations-new-tables-only.md)).
- **No re-implemented rules.** The new service never re-implements a Scheduler rule. Punching, the geofence, shifts, late and half-day judgement and the midnight close stay in the Scheduler. The app reaches them through the Scheduler's existing endpoints.
- **Shared writes go through existing functions.** When the new service must change a day, it uses the Scheduler's own database function rather than writing its own version of the rule. For approvals that function is `hr_attendance_apply_override` ([ADR-0020](0020-approvals-through-the-override-function.md)).
- **Scheduler tables are read-only by default.** The new service reads the tables the Scheduler owns (`hr_employees`, `hr_branches`, `hr_staff_attendance`, `users` and the rest). It writes them only through the paths in [ADR-0020](0020-approvals-through-the-override-function.md).

## Consequences

- **Schema coupling.** The two codebases are coupled through the schema. If a Scheduler migration renames or drops a column the new service reads, the new service breaks. The new service's tests therefore check every column it reads against a hand-kept list of the Scheduler's columns at `c28b9ca`, and against a schema snapshot once team_app has migrations ([ADR-0021](0021-migrations-new-tables-only.md)).
- **No Scheduler table changes.** Tables the Scheduler owns are never altered ([ADR-0018](0018-team-app-changes-nothing-in-the-scheduler.md)).
- **No staging.** Rehearsals run on a local Docker Postgres with PostgREST. During development, developers and agents only read production. The one production change they make is a migration, and KP applies it by hand. The deployed Scheduler and ESS write to production as normal.
