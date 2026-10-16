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
  - shellcheck, and the nginx cases in a container (`apps/ess-api/deploy/test-nginx.sh`);
  - `flutter analyze` and `flutter test` for the app, once it is in the repository.
- **Deploy.** A merge to `main` deploys the ESS automatically once its tests pass, as the Scheduler does. The workflow, `.github/workflows/deploy-ess.yml`:
  1. writes `.env` from team_app's repository secrets and variables through environment variables and `printf`, so no value passes through the script's text, and refuses a value with a line break;
  2. prints only the length of each secret, never its value, with one check step per group (Supabase and JWT, `FIREBASE_*`, the switches), and checks the settings with the ESS's own `loadConfig` before anything reaches the server;
  3. rsyncs the code to the server and runs `npm ci --omit=dev --ignore-scripts` for the ESS workspace;
  4. starts or reloads only the ESS's own pm2 process, by name, never `pm2 restart all`, and waits until it reports this deploy's commit;
  5. writes and tests its own nginx block ([ADR-0019](0019-ess-on-its-own-subdomain.md));
  6. checks `https://team-api.rvmcad.org/api/ess/health` from outside.
- **A safety switch.** The deploy runs only when the repository variable `ESS_DEPLOY_ENABLED` is `true`, so merging can start before the server, the DNS record and the secrets are ready.
- **A read-only server check.** `.github/workflows/check-server.yml`, run by hand, logs in with the deploy key and reports what the deploy depends on (Node, pm2, the ESS's port and every listening port, sudo, nginx, certbot, DNS) without changing anything.
- **Merging.** KP and the mobile developer may both merge to `main`. For now, no second review is required.
- **Branches.** Branches are named `feat/<topic>`, `fix/<topic>` or `docs/<topic>`, from `origin/main`.
- **Agents.** On 16 Oct KP told the agents to push team_app work to `main` as each piece is finished, once its lint and tests pass ("Simultaneously start pushing the team app work on main as well"). They still ask KP before anything else that reaches production, such as turning on `ESS_DEPLOY_ENABLED` or running a migration.
- **Android releases.** Releases go through the Play Console, separately. They never deploy automatically.

## Consequences

- **Code goes live before its migration.** Every merge reaches production once the switch is on, so code runs before KP applies its migration. That is why [ADR-0021](0021-migrations-new-tables-only.md) has the 503 rule.
- **Deploys run one at a time.** The workflow's concurrency group queues a second merge behind the first, so two deploys never overlap or finish out of order.
- **Missing secrets fail silently.** A variable missing from the deploy is simply absent in production, as the Scheduler's SMS keys once were. Every new secret needs its own line in the `.env` step and its own length check.
- **`JWT_SECRET` must avoid `$`, a backtick and a backslash.** The Scheduler's deploy writes its `.env` through an unquoted heredoc, which rewrites those characters, so the two services would hold different values. The ESS deploy refuses such a secret.
