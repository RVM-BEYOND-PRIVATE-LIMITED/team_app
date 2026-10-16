# ADR-0017: Repository layout, workspaces and Node version

- Status: Proposed
- Date: 16 Oct 2026
- Decided by: waiting for KP
- Source: STEP 0 recommendation of 16 Oct 2026

## Decision (proposed)

```
team_app/
  apps/ess-api/          new backend (Node + Express), served at /api/ess
  apps/rvm_team_app/     Flutter app, Android first (the mobile developer's)
  packages/contracts/    openapi.yaml and the error codes
  db/migrations/         new hr_ess_* tables, each with a .down.sql
  docs/                  summary, inputs, reconciliation, decisions, ADRs
  .github/workflows/     api-ci, api-deploy, mobile-ci
```

- **JavaScript side.** npm workspaces with one `package-lock.json` at the root. Turborepo or Nx would add tooling that one API and one contract package don't need.
- **Flutter side.** The mobile developer decides. A Dart pub workspace with melos would match flutterapps.
- **Node version.** Node 24 LTS for the new service. The Scheduler's CI uses Node 20, which reached end of life on 30 Apr 2026.

The ESS foundation, started on 16 Oct after KP's "start the backend now", follows this layout. It is still easy to change until KP confirms it.

## Open

- Which Node version the server runs. If one Node install serves both processes, the ESS runs on that version until the server is upgraded.
