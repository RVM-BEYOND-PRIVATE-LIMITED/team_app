# ADR-0011: CI on every PR; merging to main deploys

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's answers of 16 Oct 2026: "Auto on merge to main" and "let both the developer merge on main now"

## Decision

- **CI** runs on every PR and push:
  - ESLint;
  - vitest and supertest on Docker Postgres with PostgREST;
  - the OpenAPI lint;
  - `flutter analyze` and `flutter test` for the app.
- **Deploy.** A merge to `main` deploys `apps/ess-api` automatically once CI passes, as the Scheduler does. The GitHub Actions job:
  1. writes `.env` from team_app's repository secrets in a heredoc;
  2. prints only the length of each secret, never its value, with one check step per group (Supabase, JWT, `FIREBASE_*`);
  3. rsyncs the code to the VPS, runs `npm ci --omit=dev`, then `pm2 restart`.
- **Merging.** KP and the mobile developer may both merge to `main`. For now, no second review is required.
- **Branches.** Branches are named `feat/<topic>`, `fix/<topic>` or `docs/<topic>`, from `origin/main`.
- **Agents.** AI agents still ask KP before they push or merge anything, as the developer's prompt requires.
- **Android releases.** Releases go through the Play Console, separately. They never deploy automatically.

## Consequences

- **Code goes live before its migration.** Every merge reaches production, so code runs before KP applies its migration. That is why [ADR-0009](0009-migrations.md) has the 503 rule.
- **Deploys can finish out of order.** Two merges close together can deploy in the wrong order. When that happens, re-run the newest deploy.
- **Missing secrets fail silently.** A variable missing from the deploy heredoc is simply absent in production, as the Scheduler's SMS keys once were. Every new secret needs its own length check.
