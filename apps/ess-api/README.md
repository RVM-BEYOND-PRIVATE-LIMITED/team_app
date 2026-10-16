# ESS API (`apps/ess-api`)

The Team RVM employee self-service API. It runs as its own pm2 process (`team-rvm-ess`, port 3001) on the Scheduler's server ([ADR-0005](../../docs/adr/0005-separate-ess-service.md)) and serves everything under `/api/ess`. It is to be reached on a subdomain of its own, for example `https://team-api.rvmcad.org/api/ess` ([ADR-0019](../../docs/adr/0019-ess-on-its-own-subdomain.md)). The deploy step that writes that nginx block is the next piece of work ([docs/04-build-plan.md](../../docs/04-build-plan.md)).

- **The Scheduler stays the system of record.** The ESS shares its Supabase database through the service key and reads the Scheduler's tables; it never writes them directly ([ADR-0003](../../docs/adr/0003-scheduler-is-system-of-record.md)).
- **One sign-in works for both.** The ESS accepts the tokens the Scheduler issues, the portal JWT and the attendance session ([ADR-0006](../../docs/adr/0006-app-calls-scheduler-directly.md)). It never relays calls to the Scheduler.
- **Stack:** JavaScript (CommonJS) on Express 4, zod, `@supabase/supabase-js`, vitest and supertest, ESLint ([ADR-0008](../../docs/adr/0008-javascript-express.md)). Runs on Node 20 or later.

## Scripts

Run from the repository root (`npm run lint`, `npm test`) or from this folder:

| Script | What it does |
| --- | --- |
| `npm start` | Starts the server (`src/server.js`), reading `apps/ess-api/.env` |
| `npm test` | Runs the vitest suite once. No database is needed: the tests run the real store over an in-memory client |
| `npm run lint` | ESLint, including `no-undef` and `no-unused-vars` |

`tests/contract.test.js` holds the ESS against `packages/contracts/openapi.yaml`: the routes it serves must be exactly the contract's ESS operations, and every reply the tests provoke, success or refusal, must have a documented status, body, error code and headers. A field the contract does not name fails it too, so an endpoint change and its contract change go in the same PR ([ADR-0010](../../docs/adr/0010-openapi-contract-first.md)).

Set `SCHEDULER_BACKEND_DIR` to a Scheduler_Backend checkout to also run the drift checks. They compare `src/policy/roles.js` and `src/policy/hrPolicy.js` with the Scheduler's `config/roles.js` and `config/hrPolicy.js`, and the verbatim Scheduler code in `tests/helpers` with its source:

```bash
SCHEDULER_BACKEND_DIR=../Scheduler_Backend npm test
```

Without it those checks are skipped, and that includes CI, which cannot read the private Scheduler repository. Run them by hand whenever the Scheduler changes.

## Settings

`src/config.js` checks these at start-up. A missing or malformed value stops the process with a list of what is wrong, naming each variable and never printing its value. `.env.example` lists them with placeholders.

| Variable | Required | Meaning |
| --- | --- | --- |
| `PORT` | no, 3001 | Port to listen on. pm2 sets 3001 |
| `HOST` | no, `127.0.0.1` | Address to listen on. Loopback, because nginx on the same server is the only caller: point its `proxy_pass` at `http://127.0.0.1:3001`. Opening the port to the network would take tokens over plain HTTP and let a caller choose its own rate-limit bucket with a forged `X-Forwarded-For` |
| `JWT_SECRET` | **yes** | The Scheduler's own `JWT_SECRET`, byte for byte, at least 32 characters. Used to verify the Scheduler's tokens |
| `SUPABASE_URL` | **yes** | The Scheduler's Supabase project URL |
| `SUPABASE_SERVICE_KEY` | **yes** | Its service-role key |
| `ESS_ENABLED` | no, on | `false` switches every endpoint except `/api/ess/health` to 503 `MODULE_DISABLED` after a restart |
| `APP_VERSION` / `GIT_SHA` | no | The server version `/health` reports: `APP_VERSION`, else `GIT_SHA` (the deploy writes the commit), else the package version |
| `MIN_APP_VERSION` | no | Semver (`1.4.0`, `1.4.0+12`). An app below it must update. May not be above `LATEST_APP_VERSION` |
| `LATEST_APP_VERSION` | no | Semver. The newest app version, offered as an update |
| `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY_B64` | no | Push. Until all three are set, push stays log-only ([ADR-0016](../../docs/adr/0016-push-and-integrity-start-off.md)). The private key is the PEM, base64-encoded on one line |

## Endpoints

Everything is under `/api/ess`. Every reply is JSON and is sent with `Cache-Control: no-store`.

| Endpoint | Sign-in | Answer |
| --- | --- | --- |
| `GET /api/ess/health` | none | `{ ok, server_time, version, min_app_version, latest_app_version, db: "ok" \| "unavailable" }`. Always 200 while the process is up, even with the database unreachable. It stays up when `ESS_ENABLED=false` |
| `GET /api/ess/me` | portal JWT or attendance session | `{ employee: { id, full_name, employee_code, designation, employment_status, branch, department, manager }, login: { kind, role, user_id } }` |
| `GET /api/ess/me/capabilities` | portal JWT or attendance session | Tabs, sections, team, approvals, the request types with their monthly limits, Wall rights, push and integrity |

The capability rules are KP's decisions of 16 Oct 2026 ([docs/03-decisions.md](../../docs/03-decisions.md)), in `src/policy/capabilities.js`. The request types and limits are in `src/policy/requestLimits.js`, the one table the request endpoints will also use. The contract is `packages/contracts/openapi.yaml` ([ADR-0010](../../docs/adr/0010-openapi-contract-first.md)).

### How sign-in is checked

`src/middleware/employeeAuth.js` (task A1) reads `Authorization: Bearer <token>`. It tries the attendance session first and then the portal JWT, as the Scheduler's `punchAuth` does, and verifies both with HS256 only (`src/lib/tokens.js`). It re-reads the employee on every request. The checks and their order are the Scheduler's `loadEmployee` and `sessionProblem` at `c28b9ca`, including the whole-second `sessions_valid_from` comparison. A portal token is resolved through `hr_employees.user_id`.

## Errors

Every refusal is `{ "error": "<message for staff>", "code": "UPPER_SNAKE" }`. **The app signs out on 401 only.**

| Status | Code | When |
| --- | --- | --- |
| 401 | `NOT_AUTHENTICATED` | No token; a bad signature; expired; the wrong algorithm; a deleted account or employee; an attendance session issued before its login's `sessions_valid_from`. Sent with `WWW-Authenticate: Bearer` |
| 403 | `NOT_AN_EMPLOYEE` | A valid token that is not a staff login: a student token, an admission-undertaking token, any other token signed with `JWT_SECRET`, or the connector account |
| 403 | `NOT_LINKED` | A portal login with no HR record (`hr_employees.user_id`) |
| 403 | `NOT_ACTIVE` | The employee has left: archived, exited, or past the last working day (IST) |
| 403 | `NO_ATTENDANCE_LOGIN` | An attendance session whose login is missing or switched off |
| 404 | `NOT_FOUND` | No such endpoint, or a method the endpoint does not take (OPTIONS included) |
| 400 | `INVALID_JSON` | A request body that is not valid JSON |
| 413 | `PAYLOAD_TOO_LARGE` | A JSON body over 16 kB |
| 429 | `RATE_LIMITED` | Over 600 requests a minute from one address (before sign-in), or 120 a minute from one employee (after it). Sent with `Retry-After` |
| 503 | `UNAVAILABLE` | The database could not be reached. Never a 401 |
| 503 | `MODULE_NOT_INSTALLED` | A table or column the ESS reads is missing: the code is live before its migration ([ADR-0021](../../docs/adr/0021-migrations-new-tables-only.md)) |
| 503 | `MODULE_DISABLED` | `ESS_ENABLED=false` |
| 500 | `INTERNAL_ERROR` | Anything unexpected. The detail goes to the pm2 log, never to the reply |

## Running it

`ecosystem.config.cjs` runs one instance in fork mode, named `team-rvm-ess`, with `PORT=3001`, listening on `127.0.0.1` (`HOST`). It must stay one instance: the rate limits are counted in memory, and the background jobs still to come must run once. The deploy is `.github/workflows/deploy-ess.yml` ([ADR-0011](../../docs/adr/0011-ci-merge-and-auto-deploy.md)). It does not touch nginx yet: the ESS's own server block and certificate ([ADR-0019](../../docs/adr/0019-ess-on-its-own-subdomain.md)) come next, and the Scheduler's nginx files are never written ([ADR-0018](../../docs/adr/0018-team-app-changes-nothing-in-the-scheduler.md)).

`@supabase/supabase-js` is held below 2.110, because 2.110 and later need Node 22 and the server's Node version is not confirmed ([ADR-0017](../../docs/adr/0017-repository-layout-and-tooling.md)). Lift the cap once the server runs Node 22 or later. The development tools (ESLint 10, vitest 4) need Node 20.19 or later.
