# Team modules (team_app #50, items 5, 7b and 12)

Every new staff module ships behind a feature switch on the Scheduler
(Scheduler_Backend#157). The app asks which switches are open to the person
and lets only those modules' routes through. Until the first answer of a
sign-in, nothing is open and the app looks exactly as it did before modules.

## The endpoint

`GET /api/me/features` on the Scheduler client (bearer token, staff only).

```json
{ "features": [{ "key": "crm", "dry_run": false }] }
```

- Only the switches open to the caller are listed: `on`, or `pilot` with the
  caller's user id or branch in the pilot list. A pilot by HR employee or by
  subject is never listed (see "Gaps").
- The list is empty when no switch is open, when the table has no rows, and
  before the backend migration is applied.
- A switch change takes up to 30 seconds to show on the server (its cache).
  The app sees it the next time it asks (see below).
- The path sits under `/api/me`, which the `sales_executive` fence admits.

Code: `lib/data/datasources/team_modules_remote_data_source.dart`,
`lib/data/repositories/team_modules_repository.dart`,
`lib/domain/team_modules.dart`, `lib/bloc/team_modules_bloc.dart`,
`lib/router/team_router_host.dart`.

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
  sign-in, and after every sign-in. It is asked after that check, so a sign-in
  the ESS refuses (a login with no employee record, which gets the access
  error) never asks. Asking at the same moment would be safe: both clients
  share one `SessionRotator`, whose renewal runs once at a time.
- Again each time the app comes back to the foreground.
- One request at a time: an ask while one is on its way is dropped.
- Sign-out, or a session that ended, clears the modules. An answer still on
  its way for the old session is dropped, and the next sign-in asks again.
- An attendance-only sign-in never asks: the route sits behind the Scheduler's
  `auth`, which refuses the punch token, so nothing could open for it.

`TeamApp` (`main.dart`) builds its router through `TeamRouterHost`
(`lib/router/team_router_host.dart`), and the tests pump the same widget. The
router's guard reads the bloc's state, and the host runs the guard again
whenever an answer changes the open modules, so a module route on screen that
an answer closes falls back to `/home`.

A module route asked for before this sign-in's first answer is held, not lost.
A push tap that opens the app is the usual case: `PushService` sends its route
as soon as the sign-in is restored, before the shell has asked. The guard
sends it to `/home` and remembers it. When the answer comes and opens its
module, the app goes there (query included). An answer that does not open it,
no answer, or a sign-out drops it, and a later answer never jumps to it.
Nothing is held for an attendance-only sign-in, which never asks, or once the
modules have answered.

## Failures

The repository never throws. Never an error screen, never a sign-out, never a
retry loop. It tells an answer from no answer:

- An answer replaces what is open, and may close modules.
- No answer keeps what is open. Before the first answer of a sign-in that is
  nothing. After it, it is the last answer, so a slow network on the
  foreground refresh (the app goes to the background on every call the dialer
  hand-off makes) never throws the person off the module screen. The server
  still guards every module route: a closed switch answers 404 `NOT_FOUND`,
  shown as "module off" (below).

| What happens                                  | Kind      | Result |
|-----------------------------------------------|-----------|--------|
| 200 with modules                              | answer    | those modules open |
| 200 with an empty list                        | answer    | nothing open |
| 403 `Access denied. Staff only.` (student)    | answer    | nothing open |
| 404 `NOT_FOUND` (a server without the route, such as production today) | answer | nothing open |
| 401, any code                                 | no answer | kept; still signed in |
| 500 `Could not load your features.`, 502, 503 | no answer | kept |
| A 404 without the Scheduler's `NOT_FOUND` (a proxy page) | no answer | kept |
| Timeout                                       | no answer | kept; not retried |
| Connection never opens                        | no answer | kept, after the client's usual three tries |
| Offline                                       | no answer | kept; nothing sent |
| A body that cannot be read, or a 200 that is not `{ features: [...] }` | no answer | kept |
| Before the first answer, and after sign-out   |           | nothing open |

"Kept" is nothing open on the first ask of a sign-in.

- The request carries `BearerAuthInterceptor.keepSessionKey`, so its 401 never
  ends the session, whatever its code (`ACCOUNT_EXITED` and `PASSWORD_CHANGED`
  included). An expired token is still renewed once and the request sent
  again, through the same shared renewal as every request. If that renewal is
  refused, the refused refresh token is dropped, as for any request. Whether
  the session is over is left to the next ordinary request, and sign-out
  clears the modules.

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

## Gaps (backend)

- **No level.** The reply has no level field. Any decision by level uses the
  role already in the session (`StaffIdentity.role`, from sign-in). A level
  from the server would need a new field on `GET /api/me/features`; none
  exists today.
- **Pilots by HR employee or by subject are never listed.** The route lists
  `listOpenFor(defaultWho(req))`, and `defaultWho` sets only the user id and
  the branch: `auth.js` never sets `hr_employee_id`, and nothing sets a
  subject (middleware/requireFeature.js says so). A switch piloted only
  through `pilot_employee_ids` or `pilot_subject_ids` is therefore missing
  from the reply, even when the module's own `requireFeature(key, { who })`
  would admit the person, and the app keeps that module closed. Until the
  route resolves the caller's employee (and each module's `who`), pilots for
  app modules must use `pilot_user_ids` or `pilot_branch_ids`. This matters
  for the check that faculty, Admin Manager, counsellor and editor pilot
  accounts each see only their own modules. It needs a backend change, for the
  backend owner.

## Tests

- `test/team_modules_issue50_test.dart`: parsing (`fromJson`, and `tryParse`
  telling no answer from an empty one), the data source and repository against
  the app's Scheduler client (200, every 401 code, 403, both 404 bodies, a
  proxy's 404, 500/502/503, timeout, connection error, offline, unreadable
  body, a 200 page that is not the reply, no sign-out), and the bloc (no
  answer keeps what is open, an answer replaces it).
- `test/team_modules_shell_issue50_test.dart`: through `TeamRouterHost`, the
  router guard follows the bloc and runs again by itself; a refresh with no
  answer keeps the module on screen; an answer that closes it sends the route
  home; a module route sent before the first answer opens once the answer
  opens it, and is dropped otherwise; sign-out clears the modules and drops a
  held route. Also: the shell looks the same with no modules or any reply,
  foreground refresh, and no ask for attendance-only sign-ins.
- `test/module_off_issue50_test.dart`: "module off" through the app's
  Scheduler client and `BlockedState`; untagged 404s unchanged.
- `packages/core_network/test/keep_session_issue50_test.dart` and
  `module_unavailable_issue50_test.dart`: the 401 rule and the module-off
  mapping in the shared client.
