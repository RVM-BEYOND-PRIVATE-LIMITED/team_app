# Team modules (team_app #50, items 5, 7b and 12)

Every new staff module ships behind a feature switch on the Scheduler
(Scheduler_Backend#157). The app asks which switches are open to the person
and lets only those modules' routes through. When the answer is missing or
fails, nothing is open and the app looks exactly as it did before modules.

## The endpoint

`GET /api/me/features` on the Scheduler client (bearer token, staff only).

```json
{ "features": [{ "key": "crm", "dry_run": false }] }
```

- Only the switches open to the caller are listed: `on`, or `pilot` with the
  caller's user id or branch in the pilot list.
- The list is empty when no switch is open, when the table has no rows, and
  before the backend migration is applied.
- A switch change takes up to 30 seconds to show on the server (its cache).
  The app sees it the next time it asks (see below).
- The path sits under `/api/me`, which the `sales_executive` fence admits.

Code: `lib/data/datasources/team_modules_remote_data_source.dart`,
`lib/data/repositories/team_modules_repository.dart`,
`lib/domain/team_modules.dart`, `lib/bloc/team_modules_bloc.dart`.

## The keys the app understands

A key opens the module of the same name, and that module's route prefix
(`lib/router/module_routes.dart`, `TeamModule`):

| Key          | Route prefix  |
|--------------|---------------|
| `crm`        | `/crm`        |
| `fees`       | `/fees`       |
| `ops`        | `/ops`        |
| `desk`       | `/desk`       |
| `placement`  | `/placement`  |
| `scorecards` | `/scorecards` |
| `tasks`      | `/tasks`      |
| `social`     | `/social`     |
| `complaints` | `/complaints` |
| `moderation` | `/moderation` |

- Keys are matched exactly, as the server's `requireFeature('crm')` matches
  them: `CRM` or ` crm` opens nothing.
- A key the app does not know is ignored. An entry that is not
  `{ key, dry_run }` is skipped; a body that is not `{ features: [...] }`
  opens nothing.
- `dry_run` is kept per module (`TeamModules.isDryRun`). It is `true` only
  when the server sends `true`. What a dry run does is each module's own rule.
- No module has a screen yet, so an open key adds no tab and no tile. It only
  lets the module's route prefix through the router guard.

## When the app asks

- Once the shell's ESS capabilities check has succeeded: at launch with a kept
  sign-in, and after every sign-in. It is asked after that check, not with it,
  so the two never renew the kept sign-in at the same moment.
- Again each time the app comes back to the foreground.
- One request at a time: an ask while one is on its way is dropped.
- Sign-out, or a session that ended, clears the modules. An answer still on
  its way for the old session is dropped, and the next sign-in asks again.
- An attendance-only sign-in never asks: the route sits behind the Scheduler's
  `auth`, which refuses the punch token, so nothing could open for it.

The router's guard reads the bloc's state (`createRouter(modules: ...)` in
`main.dart`), and `moduleGuardListeners` runs the guard again whenever the open
modules change, so a module route on screen that closes falls back to `/home`.

## Failures

The repository never throws. Every failure is "no modules": never an error
screen, never a sign-out, never a retry loop.

| What happens                                  | Result                      |
|-----------------------------------------------|-----------------------------|
| 200 with modules                              | those modules open          |
| 200 with an empty list                        | nothing open                |
| 401, any code                                 | nothing open, still signed in |
| 403 `Access denied. Staff only.` (student)    | nothing open                |
| 404 `NOT_FOUND` (a server without the route, such as production today) | nothing open |
| 500 `Could not load your features.`, 502, 503 | nothing open                |
| Timeout                                       | nothing open, not retried   |
| Connection never opens                        | nothing open, after the client's usual three tries |
| Offline                                       | nothing open, nothing sent  |
| A body that cannot be read                    | nothing open                |
| Before the first answer                       | nothing open                |

- The request carries `BearerAuthInterceptor.keepSessionKey`, so its 401 never
  ends the session, whatever its code (`ACCOUNT_EXITED` and `PASSWORD_CHANGED`
  included). An expired token is still renewed once and the request sent
  again, through the same shared renewal as every request. If that renewal is
  refused, the refused refresh token is dropped, as for any request. Whether
  the session is over is left to the next ordinary request.
- A refresh that fails while modules are open closes them (fail closed).

## A module that is switched off (item 12)

A module route behind a closed switch answers 404
`{ "error": "Not found", "code": "NOT_FOUND" }`. The body is the same for "off"
and "not in the pilot", on purpose.

- A module's own requests carry their module:
  `options: TeamModule.crm.requestOptions` (`lib/data/module_request.dart`).
- Such a request's 404 `NOT_FOUND` becomes `ModuleUnavailableFailure`
  (`packages/core_network`, `Failure.forModule`), on both paths: a thrown
  `DioException` and a refused reply returned as a value (`DioExecutor`).
- `blockedReasonFor(failure)` turns it into `BlockedReason.moduleOff`, which
  the shared `BlockedState` shows. `pilotOnly` is never inferred from a reply,
  because the server does not tell the two apart.
- A 404 `NOT_FOUND` on any request without the tag stays a plain
  `NotFoundFailure`, as before.

## The person's level

The reply has no level field. Any decision by level uses the role already in
the session (`StaffIdentity.role`, from sign-in). A level from the server
would need a new field on `GET /api/me/features`; none exists today.

## Tests

- `test/team_modules_issue50_test.dart`: parsing, the data source and
  repository against the app's Scheduler client (200, every 401 code, 403, 404,
  500/502/503, timeout, connection error, offline, unreadable body, no
  sign-out), and the bloc.
- `test/team_modules_shell_issue50_test.dart`: the router guard follows the
  bloc and runs again by itself, sign-out clears the modules, the shell looks
  the same with no modules or any reply, foreground refresh, and no ask for
  attendance-only sign-ins.
- `test/module_off_issue50_test.dart`: "module off" through the app's
  Scheduler client and `BlockedState`; untagged 404s unchanged.
- `packages/core_network/test/keep_session_issue50_test.dart` and
  `module_unavailable_issue50_test.dart`: the 401 rule and the module-off
  mapping in the shared client.
