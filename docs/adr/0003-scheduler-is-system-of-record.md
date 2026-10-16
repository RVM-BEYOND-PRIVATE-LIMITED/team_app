# ADR-0003: The Scheduler stays the system of record, on one database

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: App Brief, Summary ("The Scheduler stays the single source of truth: the app calls the same backend and applies the same rules as the web"); KP on 16 Oct 2026 ("other functionalities can be pulled via API calls through the Scheduler frontend and backend")

## Context

- **One database holds everything.** Every employee, branch, attendance day, punch, shift and login already lives in the Scheduler's Supabase project, which is production.
- **There is no other database.** The old staging project is gone: its host stopped resolving on 14 Oct 2026.
- **The attendance rules live in the Scheduler.** Geofence, one phone per person, shifts, late marks, half days and the midnight close are implemented in Scheduler_Backend and its Postgres functions.

## Decision

- The new service uses the same Supabase project as the Scheduler.
- The new service never re-implements a Scheduler rule. Punching, the geofence, shifts, late and half-day judgement and the midnight close stay in the Scheduler.
- When both services need the same write, the rule lives in a Postgres function that either service can call. Approving an on-duty request, which writes the day, is one example. `hr_attendance_apply_override` is today's model for such a function.
- The new service only reads the tables the Scheduler owns: `hr_employees`, `hr_branches`, `hr_staff_attendance`, `users` and the rest. It writes to them only through such a function.

## Consequences

- The two codebases are coupled through the schema. If a Scheduler migration renames or drops a column the new service reads, the new service breaks. The new service's tests therefore run against the Scheduler's migrations.
- Changes to tables the Scheduler owns are Scheduler PRs ([ADR-0007](0007-scheduler-changes-as-scheduler-prs.md), [ADR-0009](0009-migrations.md)).
- There is no staging environment. Rehearsals run on a local Docker Postgres with PostgREST. Production is only ever read, except by migrations KP applies.
