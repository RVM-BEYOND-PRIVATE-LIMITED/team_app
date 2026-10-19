# Team RVM app — ESS integration (handover)

How `rvm_team_app` talks to KP's Team RVM ESS backend (`team_app`), what is
wired today, and what still waits on the backend. Contract:
`team_app/packages/contracts/openapi.yaml` (v0.2.1).

## Base URLs

| Backend | Default | dart-define |
| --- | --- | --- |
| Scheduler (system of record) | `https://scheduler.rvmcad.org/api` | `SCHEDULER_BASE_URL` |
| Team RVM ESS | `https://team-api.rvmcad.org/api/ess` | `ESS_BASE_URL` |
| JobPortal (student app only) | `https://jobs.rvmcad.org/api/v1` | `JOBPORTAL_BASE_URL` |

Defined in `packages/core_network/lib/src/api_environment.dart`. For a local
backend: `--dart-define=ESS_BASE_URL=http://10.0.2.2:3740/api/ess`.

## Auth flow

1. **Sign-in stays on the Scheduler.** Two routes:
   - Portal staff: `POST /users/login` / `/users/login/verify` (password, 2FA),
     plus `forgot-password` / `confirm`. The one-field resolver
     (`POST /api/ess/sign-in/resolve`) narrows the branch list.
   - Attendance-only staff (A2, no portal login): the login screen's
     "Sign in with attendance" mode calls `POST /hr/my-attendance/password-login`,
     or `POST /hr/my-attendance/otp/request` + `/otp/verify` for a code. A
     temporary/no password is changed via `POST /hr/my-attendance/password`
     (the punch screen prompts for it). These sessions carry `k:"punch"` and are
     admitted as `StaffIdentity.attendance`.
   The app stores the Scheduler JWT (`AuthSession`).
2. **Kept sign-in (A3)** — right after a successful sign-in the app calls
   `POST /api/ess/session` (`EssRepository.keepSignIn`) with the fresh token and
   the install id, and stores the rotating refresh token. Best-effort: a failure
   never blocks sign-in.
3. **Every ESS call** goes through `DioFactory.ess`, whose `EssAuthInterceptor`
   attaches the bearer token and, on a 401, silently rotates the refresh token
   once (`POST /session/refresh`) and replays the request. The ESS access token
   is minted in the Scheduler's format, so it is stored in the Scheduler token
   slot and accepted by both hosts.
4. **Restore on launch** — if the Scheduler token has expired but the kept
   sign-in is alive, `GET /me` rotates it during the startup probe.
5. **Sign-out** calls `POST /session/sign-out` and clears all local tokens.

The punch path prerequisite (tasks B8/B13) is also wired: `DioFactory.scheduler`
sends a mobile `User-Agent` and persists the `rvm_att_dev` cookie in
`AuthSession.schedulerCookieJar` (never cleared on sign-out).

## Endpoints per screen

| Screen (`features/…`) | Endpoint(s) |
| --- | --- |
| startup `VersionGate` | `GET /health` (min/latest app version, K2) |
| shell (capabilities) | `GET /me/capabilities` (tab/section gating) |
| Me → My day (`me/attendance_day_screen.dart`) | `GET /attendance/day`, `POST /attendance/mock-location` |
| Me → Personal details (`me/personal_details_screen.dart`) | `GET`/`PUT /me/personal` |
| Me → Data requests (`me/data_requests_screen.dart`) | `GET`/`POST /me/data-requests` |
| Me → Signed-in devices (`me/sessions_screen.dart`) | `GET /sessions`, `DELETE /sessions/:id`, `POST /session/sign-out` |
| Me → HR tools (`hr/hr_tools_screen.dart`) | `GET`/`PATCH /hr/data-requests`, `GET /hr/mock-location-reports`, `GET /hr/devices`, `POST /hr/devices/reset`, `GET`/`PUT /hr/employees/:id/personal` |
| Login (resolver available, not yet wired to UI) | `POST /sign-in/resolve` |

Not built in this round because the backend does not expose them yet:
`GET /me/data-requests` is A8; **Wall** (2A), **My Team** (1E), **Documents**
(2C), **Helpdesk** (2B), requests/leave/approvals (1C), inbox/push (1D) all
remain `BackendPending` placeholders.

## Error codes

The ESS answers `{ "error": "<staff copy>", "code": "UPPER_SNAKE" }`. The app maps
them through `Failure`:

- `401 NOT_AUTHENTICATED` → a silent refresh, then sign-out if that fails.
- `403` (`NOT_LINKED`, `NOT_ACTIVE`, `PASSWORD_CHANGE_REQUIRED`, `HR_ACCESS_DENIED`, …)
  → `ForbiddenFailure` with the server's message.
- `503 MODULE_NOT_INSTALLED` → the server's own copy ("…needs a database update
  that has not been applied yet…"); shown verbatim. This is what every Phase-1B
  endpoint returns until KP applies the five migrations (`team_app/docs/05-deploy.md`).
- `503 MODULE_DISABLED` / `UNAVAILABLE`, `429 RATE_LIMITED` → likewise surfaced.

## Theme

The app uses the shared Team RVM design system in `packages/core_ui`:
`RvmColors.teamSeed` (Forge Orange `#F84E28`), `RvmColors.ironwood` (`#331714`),
`RvmColors.ivory` (`#F3F5F4`), plus `RvmSpacing`/`RvmRadii`, via
`RvmTheme.light/dark`. Punch-in/out colours follow decision 16 (Forge Orange in,
Ironwood out) when the punch screen lands.
