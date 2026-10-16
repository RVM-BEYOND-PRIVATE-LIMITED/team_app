# @team-rvm/contracts

The Team RVM API contract ([ADR-0010](../../docs/adr/0010-openapi-contract-first.md)). [`openapi.yaml`](openapi.yaml) describes every endpoint the Android app calls, new and existing. The mobile developer builds against this file, so it must always say what the servers really do.

## How to read the file

Read it in this order:

1. **`info.description`.** The rules that hold everywhere: who owns what, the error shape, IST days, staying signed in and when to sign out, replies that are not JSON, and the rate limits.
2. **`components.securitySchemes.bearer`.** The two kinds of token (the portal JWT and the attendance session), how long each lasts, where each one works, and the one-hour access tokens the ESS mints in the same two formats for a kept sign-in.
3. **The operations, by tag.** Each operation carries:
   - `summary` and `description`: what it does, and the order in which it checks things;
   - `x-owner`: which service answers it (`ess` or `scheduler`);
   - `x-notes`: the traps a native client walks into. Read them before building the screen;
   - `x-source` (Scheduler only): the files and lines at commit `c28b9ca` that the entry was read from;
   - every status the code can return, with each error `code` and an example. A `text/html` entry marks a reply that is an HTML page rather than JSON.
4. **The two error schemas.** `Error` is the ESS's: `code` is always there. `SchedulerError` is the Scheduler's: `code` is sometimes missing, and a few refusals add fields such as `attempts_left` or `distance_m`.

There are two servers ([ADR-0019](../../docs/adr/0019-ess-on-its-own-subdomain.md)), and each path is relative to its own:
- The Scheduler's paths (`/users/*`, `/hr/my-attendance/*`) use the top-level server, `https://scheduler.rvmcad.org/api`.
- The ESS paths (`/ess/*`) name their own server, `https://{essHost}/api`. So `/ess/health` is `https://team-api.rvmcad.org/api/ess/health`. KP chose the host name on 16 Oct 2026 ([ADR-0019](../../docs/adr/0019-ess-on-its-own-subdomain.md)), and it is the variable's default.

The device cookie's path, `/api/hr/my-attendance`, is the full path on the Scheduler's host.

To read it as a web page, build it into a folder outside any repository and open the file. Never commit the output.

```sh
npx redocly build-docs --config packages/contracts/redocly.yaml packages/contracts/openapi.yaml -o <a folder outside the repository>/contract.html
```

## Ownership tags

| Tag | `x-owner` | Served by | How it changes |
| --- | --- | --- | --- |
| `ESS` | `ess` | team_app, `apps/ess-api`, under `/api/ess` on its own host (port 3740 behind nginx) | A team_app PR that updates this file in the same PR |
| `Scheduler (existing)` | `scheduler` | Scheduler_Backend (port 3000), the system of record, at `scheduler.rvmcad.org` | Never by Team RVM ([ADR-0018](../../docs/adr/0018-team-app-changes-nothing-in-the-scheduler.md)). If the Scheduler changes one of these endpoints on its own, a team_app PR updates this file to match. |

The Scheduler entries record its behaviour at `c28b9ca` exactly, and nothing in them implies a change. The security holes found in STEP 1 stay open, so the contract keeps showing them where the app could trip over them. For example, `POST /users/reset-password` is marked deprecated and "never call" because it is still live.

## Rules for changing the contract

- **Every endpoint change updates this file in the same PR.** That means a new endpoint, a removed one, or any change to a request, a response, a status or an error code. If the Scheduler changes one of its endpoints on its own, the team_app PR that records it says which Scheduler commit it describes.
- **A breaking change says so in the PR title**, for example `BREAKING(contract): /ess/me drops employee.designation`. A change is breaking when an app built against the previous file can go wrong. Examples:
  - removing or renaming an endpoint, an `operationId`, a field or an enum value;
  - changing a type, or whether a field can be null;
  - a new required request field, or tighter validation;
  - a new status, or a new error code the app must handle;
  - a code that now means something else.

  Adding an endpoint, an optional request field, a response field or an example is not breaking.
- **Raise `info.version`** whenever the contract changes, so the app can say which version it was built against.
- **Keep these on every operation:** an `operationId`, one ownership tag and the matching `x-owner`. A generated client turns each `operationId` into a method name.
- **Error messages are written for staff.** The app branches on `code` and shows `error` as it is.

## How to lint

This package is an npm workspace, so `npm ci` at the repository root installs Redocly CLI from the lockfile. From the root:

```sh
npm run lint --workspace @team-rvm/contracts
```

The settings are in [`redocly.yaml`](redocly.yaml): Redocly's `recommended` rules with every warning raised to an error (`recommended-strict`), and no usage data sent to Redocly (`telemetry: 'off'`). Without the strict rules, an example that no longer matches its schema is only a warning, and CI would pass a contract whose examples are wrong. `@redocly/cli` 2.56.1 needs Node 20.19 or later on the 20 line, or Node 22.12 or later.

The lint checks the file against itself. Whether the ESS really answers as the file says is checked by `apps/ess-api/tests/contract.test.js`, which runs with the ESS's tests: it compares the routes the ESS serves with the ESS operations here, and holds every reply it provokes against the documented status, schema (with no undocumented fields), error codes and headers.

## Not covered yet

- **Scheduler endpoints.** Only the Phase 1 sign-in and attendance ones are in. The calendar, holidays, priority tasks and faculty views come in with the slices that use them.
- **ESS endpoints still to come, each with its own slice.** Several replace a Scheduler change that ADR-0018 ruled out:
  - the refreshable session (A3);
  - the one-field sign-in resolver (A5);
  - the day's note, HR's remark and the server time for the attendance screen (B1);
  - reporting a mocked location to HR (B14, decision 6);
  - HR's bulk phone reset (B8, decision 11).
- **Out of scope** under ADR-0018, so the Scheduler entries here stay as they are:
  - a device-id header instead of the cookie (part of B8);
  - batched pings (B15);
  - 401s with a code (J8);
  - retiring the old reset (A9).
