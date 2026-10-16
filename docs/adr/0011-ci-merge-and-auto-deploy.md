# ADR-0011: CI on every PR; merging to main deploys

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's answers of 16 Oct 2026: "Auto on merge to main" and "let both the developer merge on main now"

## Decision

- **CI** runs on every PR and push:
  - ESLint;
  - vitest and supertest;
  - the OpenAPI lint;
  - `flutter analyze` and `flutter test` for the app.
- **Deploy.** A merge to `main` deploys the ESS automatically once CI passes, as the Scheduler does. The GitHub Actions job:
  1. writes `.env` from team_app's repository secrets in a quoted heredoc;
  2. prints only the length of each secret, never its value, with one check step per group (Supabase, JWT, `FIREBASE_*`);
  3. rsyncs the code to the server and runs `npm ci --omit=dev` where the lockfile is (the repository root, for the ESS workspace);
  4. writes and tests its own nginx block ([ADR-0019](0019-ess-on-its-own-subdomain.md));
  5. restarts only the ESS's own pm2 process, by name, never `pm2 restart all`.
- **A safety switch.** The deploy runs only when the repository variable `ESS_DEPLOY_ENABLED` is `true`, so merging can start before the server, the DNS record and the secrets are ready.
- **Merging.** KP and the mobile developer may both merge to `main`. For now, no second review is required.
- **Branches.** Branches are named `feat/<topic>`, `fix/<topic>` or `docs/<topic>`, from `origin/main`.
- **Agents.** On 16 Oct KP told the agents to push team_app work to `main` as each piece is finished, once its lint and tests pass ("Simultaneously start pushing the team app work on main as well"). They still ask KP before anything else that reaches production, such as turning on `ESS_DEPLOY_ENABLED` or running a migration.
- **Android releases.** Releases go through the Play Console, separately. They never deploy automatically.

## Consequences

- **Code goes live before its migration.** Every merge reaches production once the switch is on, so code runs before KP applies its migration. That is why [ADR-0021](0021-migrations-new-tables-only.md) has the 503 rule.
- **Deploys can finish out of order.** Two merges close together can deploy in the wrong order. When that happens, re-run the newest deploy.
- **Missing secrets fail silently.** A variable missing from the deploy heredoc is simply absent in production, as the Scheduler's SMS keys once were. Every new secret needs its own length check.
