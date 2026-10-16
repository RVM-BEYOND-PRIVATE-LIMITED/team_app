# Architecture decision records

Each file records one decision: what was decided, why, and what follows from it. Product rules, such as limits, approvers and who sees what, are in [../03-decisions.md](../03-decisions.md), not here.

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-record-architecture-decisions.md) | Record architecture decisions as ADRs | Accepted |
| [0002](0002-monorepo-is-team-app.md) | team_app holds the Team RVM backend and the Flutter app | Accepted |
| [0003](0003-scheduler-is-system-of-record.md) | The Scheduler stays the system of record, on one database | Accepted |
| [0004](0004-sign-in-unchanged.md) | Sign-in stays as it is, behind a one-field front door | Accepted |
| [0005](0005-separate-ess-service.md) | The new API runs as a separate service | Accepted; its location is superseded by 0019 |
| [0006](0006-app-calls-scheduler-directly.md) | The app calls the Scheduler directly for existing features | Accepted |
| [0007](0007-scheduler-changes-as-scheduler-prs.md) | Changes to existing Scheduler code ship as Scheduler PRs | Superseded by 0018 |
| [0008](0008-javascript-express.md) | JavaScript, Express and the Scheduler's conventions for the new API | Accepted |
| [0009](0009-migrations.md) | Where migrations live and how they reach production | Superseded by 0021 |
| [0010](0010-openapi-contract-first.md) | One OpenAPI contract is the source of truth for the app | Accepted |
| [0011](0011-ci-merge-and-auto-deploy.md) | CI on every PR; merging to main deploys (behind a switch) | Accepted |
| [0012](0012-security-first.md) | Security rules for everything team_app builds | Accepted; amended by 0018 |
| [0013](0013-scope-phases-1-and-2.md) | This round builds Phases 1 and 2 | Accepted |
| [0014](0014-mobile-developer-owns-flutter-app.md) | The mobile developer sets up and builds the Flutter app | Accepted |
| [0015](0015-no-automated-retention.md) | No automated purge of location pings or logs | Accepted |
| [0016](0016-push-and-integrity-start-off.md) | Push and Play Integrity start switched off | Accepted |
| [0017](0017-repository-layout-and-tooling.md) | Repository layout, workspaces and Node version | Proposed |
| [0018](0018-team-app-changes-nothing-in-the-scheduler.md) | Team RVM changes nothing in Scheduler_Backend or Scheduler_frontend | Accepted |
| [0019](0019-ess-on-its-own-subdomain.md) | The ESS runs on its own subdomain on the same server | Accepted |
| [0020](0020-approvals-through-the-override-function.md) | Approvals write the official day through HR's override function | Accepted |
| [0021](0021-migrations-new-tables-only.md) | Migrations add new hr_ess_* tables only, and live in team_app | Accepted |

## Status values

- **Proposed**: written up and waiting for KP.
- **Accepted**: decided; build to it.
- **Superseded by ADR-NNNN**: replaced by a later decision and kept for history.
- **Rejected**: considered and turned down.

## Adding one

Copy the template into `NNNN-short-title.md` with the next free number. To change your mind about an Accepted ADR, don't edit it. Write a new ADR that supersedes it, and mark the old one "Superseded by ADR-NNNN".

```markdown
# ADR-NNNN: <the decision in one sentence>

- Status: Proposed
- Date: <d Mon yyyy>
- Decided by: <who>
- Source: <where and how it was decided>

## Context

## Decision

## Consequences
```
