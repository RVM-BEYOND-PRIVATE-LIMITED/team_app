# ADR-0005: The new API runs as a separate service at /api/ess

- Status: Accepted for the separate process. Its location (`/api/ess` on scheduler.rvmcad.org) and nginx consequences are superseded by [ADR-0019](0019-ess-on-its-own-subdomain.md) (16 Oct 2026): the ESS gets its own subdomain and never touches the Scheduler's nginx file.
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's answer of 16 Oct 2026

## Context

There were three options:
- a separate service in team_app on the Scheduler's server;
- new routes inside Scheduler_Backend;
- a separate service on its own subdomain.

The Scheduler runs on one AWS VPS (`scheduler.rvmcad.org`) as the pm2 process `scheduler-backend` on port 3000. nginx forwards `/api/` to it.

## Decision

`apps/ess-api` runs as its own pm2 process on the same server, on port 3001 (proposed). It is reached at `https://scheduler.rvmcad.org/api/ess/`.

## Consequences

- **nginx belongs to the Scheduler's deploy.**
  - Scheduler_Backend's `.github/workflows/deploy.yml` rewrites the `scheduler.rvmcad.org` server block on every Scheduler deploy.
  - A `location /api/ess/ { proxy_pass http://localhost:3001; … }` block must therefore be added there, in a Scheduler PR, before the first ESS deploy. A hand edit on the server would be erased by the next Scheduler deploy.
  - The same block carries the upload size limit for `/api/ess` (task K1).
- **Shared secrets.** The service needs `JWT_SECRET` (to verify Scheduler-issued tokens), `SUPABASE_URL` and `SUPABASE_SERVICE_KEY` as team_app repository secrets. Rotating either secret means updating both repositories. The service key is unavoidable: every attendance table is RLS deny-all and readable only with the service role.
- **Shared rules live in the database or in the Scheduler's controllers.** Some Scheduler rules live in controllers rather than the database, so the ESS cannot call them. One example is the "future day only for leave" guard around `hr_attendance_apply_override`. So an approval writes the day through that existing function, with the ESS making the controller's checks itself ([ADR-0020](0020-approvals-through-the-override-function.md)), and nothing the Scheduler owns is widened ([ADR-0018](0018-team-app-changes-nothing-in-the-scheduler.md)).
- **Secrets in the deploy file.** The Scheduler's deploy writes `.env` through an unquoted heredoc, so a `$` or a backtick in a secret is expanded by the shell, and a multi-line key breaks `.env`. team_app's deploy writes each value with `printf` from an environment variable, never through a heredoc, refuses a value with a line break, and stores the Firebase key base64-encoded on one line.
- **Isolation.** If the ESS crashes, runs out of memory or deploys badly, the portal keeps running, and the other way round.
- **Downtime looks different.** While the ESS is down, nginx answers 502 with an HTML page. The app treats any non-JSON reply as "server restarting".
- **Background jobs run inside the ESS.** These are the push worker and the helpdesk response-time checks. pm2 must run exactly one instance (fork mode), or every job runs twice.
