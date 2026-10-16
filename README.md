# team_app

Team RVM is RVM CAD's Android app for every employee, modelled on the Keka employee app: punch in and out, requests and approvals, an Inbox with push, a Wall, a Helpdesk, Me and My Team.

This private repository holds the new backend that the app needs, the **ESS** (employee self-service API, `apps/ess-api`), and later the Flutter app. The Scheduler (`scheduler.rvmcad.org`, Scheduler_Backend) stays the system of record. The app calls the Scheduler directly for what already exists (sign-in, punch, calendar, holidays) and calls the ESS, under `/api/ess` on a host of its own ([ADR-0019](docs/adr/0019-ess-on-its-own-subdomain.md)), for everything new. One sign-in token works for both. Nothing in the Scheduler's repositories changes for Team RVM ([ADR-0018](docs/adr/0018-team-app-changes-nothing-in-the-scheduler.md)). Start with [docs/00-summary.md](docs/00-summary.md).

## Layout

The layout proposed in [ADR-0017](docs/adr/0017-repository-layout-and-tooling.md), still to be confirmed by KP:

```
team_app/
  apps/ess-api/          the ESS: Node + Express, served under /api/ess
  apps/rvm_team_app/     the Flutter app, Android first (set up by the mobile developer)
  packages/contracts/    openapi.yaml and the error codes (ADR-0010)
  db/migrations/         new hr_ess_* tables only (ADR-0021)
  db/rollbacks/          one rollback per migration, kept out of the migrations folder
  docs/                  summary, inputs, reconciliation, decisions, build plan, ADRs
  .github/workflows/     ci.yml (every PR and push), deploy-ess.yml (merge to main),
                         check-server.yml (a read-only look at the server, run by hand)
```

Only `apps/ess-api` and `packages/contracts` exist so far. `apps/ess-api/deploy/` holds the ESS's nginx file and the script the deploy installs it with.

The JavaScript side is one set of npm workspaces with a single `package-lock.json` at the root: `apps/ess-api` and `packages/contracts`.

## Install, test and run

You need Node 20.19 or later (ESLint 10, vitest 4 and Redocly CLI 2 need 20.19; the service itself runs on any Node 20). Node 24 is the target ([ADR-0017](docs/adr/0017-repository-layout-and-tooling.md)).

```bash
npm ci          # install every workspace from the lockfile
npm run lint    # ESLint for the ESS, and the Redocly lint of the contract
npm test        # the ESS's tests, including its replies checked against the contract; no database is needed
```

To run the ESS locally, copy `apps/ess-api/.env.example` to `apps/ess-api/.env`, fill in your own values (never production's), and start it:

```bash
npm start --workspace=apps/ess-api
curl http://127.0.0.1:3740/api/ess/health
```

The settings, endpoints and error codes are in [apps/ess-api/README.md](apps/ess-api/README.md).

## CI and deploy

- **CI** ([.github/workflows/ci.yml](.github/workflows/ci.yml)) runs on every pull request and push: `npm ci`, then the ESS's lint and tests on Node 20 and 24, the Redocly lint of `packages/contracts/openapi.yaml`, and the nginx cases (shellcheck, then `apps/ess-api/deploy/test-nginx.sh` against a real nginx in a container).
- **Deploy** ([.github/workflows/deploy-ess.yml](.github/workflows/deploy-ess.yml)) runs on a merge to `main` that touches the ESS ([ADR-0011](docs/adr/0011-ci-merge-and-auto-deploy.md)). It runs the tests again, then writes `.env` from the repository secrets through environment variables, printing only lengths. It rsyncs to `~/team_app` on the server, installs the production dependencies, starts or reloads the pm2 process `team-rvm-ess` and waits until `/api/ess/health` reports the commit it deployed. Last, it puts the ESS's own nginx file in front, for `team-api.rvmcad.org`, with its own certificate ([ADR-0019](docs/adr/0019-ess-on-its-own-subdomain.md)), and checks the host from outside. It does nothing until the repository variable `ESS_DEPLOY_ENABLED` is `true`. Step by step, with how to switch it off: [docs/05-deploy.md](docs/05-deploy.md).
- **Server check** ([.github/workflows/check-server.yml](.github/workflows/check-server.yml)), run by hand, logs in with the deploy key and reports what the deploy depends on, changing nothing.

What the deploy reads:

| Kind | Name | Use |
| --- | --- | --- |
| Secret | `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` | The Scheduler's database (required) |
| Secret | `JWT_SECRET` | The Scheduler's own value (required) |
| Secret | `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY_B64` | Push; log-only while empty |
| Secret | `HOST`, `USER`, `SSH_PRIVATE_KEY` | The server and the deploy login |
| Secret | `SSH_KNOWN_HOSTS` | Optional: the server's pinned host key |
| Variable | `ESS_HOST` | The ESS's host name, `team-api.rvmcad.org` |
| Variable | `ESS_DEPLOY_ENABLED` | `true` to deploy at all |
| Variable | `ESS_ENABLED` | `false` switches the ESS off without a code change |
| Variable | `MIN_APP_VERSION`, `LATEST_APP_VERSION` | What `/api/ess/health` tells the app |

## Docs

| File | What it covers |
| --- | --- |
| [docs/00-summary.md](docs/00-summary.md) | The whole project on one page |
| [docs/01-inputs.md](docs/01-inputs.md) | The brief, the gap report and the developer's prompt |
| [docs/02-reconciliation.md](docs/02-reconciliation.md) | Every task checked against the Scheduler's code |
| [docs/03-decisions.md](docs/03-decisions.md) | Product decisions and limits |
| [docs/04-build-plan.md](docs/04-build-plan.md) | The build plan, wave by wave |
| [docs/05-deploy.md](docs/05-deploy.md) | Deploying the ESS, and switching it off |
| [docs/06-backend-phases.md](docs/06-backend-phases.md) | The backend work left, phase by phase |
| [docs/adr/](docs/adr/README.md) | Architecture decisions |

The Scheduler is used as it is: its endpoints as a client and its database as a data source, never changed for Team RVM ([ADR-0018](docs/adr/0018-team-app-changes-nothing-in-the-scheduler.md)).
