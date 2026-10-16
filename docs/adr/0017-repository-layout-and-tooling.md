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
  db/migrations/         new hr_ess_* tables only (ADR-0021)
  db/rollbacks/          one rollback per migration, outside the migrations folder (ADR-0021)
  docs/                  summary, inputs, reconciliation, decisions, ADRs
  .github/workflows/     ci.yml, deploy-ess.yml, check-server.yml; mobile CI when the app arrives
```

- **JavaScript side.** npm workspaces with one `package-lock.json` at the root. Turborepo or Nx would add tooling that one API and one contract package don't need.
- **Flutter side.** The mobile developer decides. A Dart pub workspace with melos would match flutterapps.
- **Node version.** Node 24 LTS for the new service. The Scheduler's CI uses Node 20, which reached end of life on 30 Apr 2026.

The ESS foundation, started on 16 Oct after KP's "start the backend now", follows this layout. It is still easy to change until KP confirms it.

## Open

- Which Node version the server runs: answered on 16 Oct by the server check, Node 22.23.1, shared with the Scheduler. The ESS still supports Node 20 and holds `@supabase/supabase-js` below 2.110 (which needs Node 22); both can be raised now that the server runs 22.
