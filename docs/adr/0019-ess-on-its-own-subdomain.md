# ADR-0019: The ESS runs on its own subdomain on the same server

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's answer of 16 Oct 2026, "Own subdomain, same server"
- Supersedes: the location and nginx parts of [ADR-0005](0005-separate-ess-service.md). The service is still a separate process ([ADR-0018](0018-team-app-changes-nothing-in-the-scheduler.md) rules out touching the Scheduler's nginx file).

## Decision

- The ESS runs on the Scheduler's VPS as its own pm2 process. The port is 3001 (proposed) and the process is named, for example, `team-rvm-ess`.
- It sits behind its own nginx server block for its own host name, for example `team-api.rvmcad.org`. KP picks the name and adds the DNS record.
- team_app's deploy manages that block:
  1. It writes the block to a file of its own, `/etc/nginx/sites-available/team-rvm`.
  2. It obtains and renews the certificate with certbot.
  3. It enables the block only after `nginx -t` passes for the whole server.
  4. It reloads nginx.
- The Scheduler's server-block files are never written.

## Consequences

- **The app has two base URLs:**
  - `https://scheduler.rvmcad.org/api` for the Scheduler's endpoints. The punch cookie stays with this host.
  - `https://<ESS host>/api/ess` for the ESS. Both accept the same sign-in token.
- **nginx is shared.**
  - The Scheduler's deploy runs `nginx -t` over every enabled site and stops if it fails. A broken team_app block would therefore block the Scheduler's deploys.
  - So team_app's deploy writes its block, tests it, and enables it only if the test passes. It also removes the block if a later test fails.
- **Upload size.** The ESS's upload limit (12 MB proposed) is set in its own block. The Scheduler's `/api/` limit stays as it is.
- **No CORS.** The Android app needs no CORS. A future web client of the ESS would.
- **Phase 0 tasks for KP:**
  - the DNS record;
  - team_app's deploy secrets (the same server login as the Scheduler's deploy, plus the ESS values);
  - turning on `ESS_DEPLOY_ENABLED`.
