# ADR-0019: The ESS runs on its own subdomain on the same server

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's answer of 16 Oct 2026, "Own subdomain, same server". KP chose the name `team-api.rvmcad.org` and added its DNS record the same day.
- Supersedes: the location and nginx parts of [ADR-0005](0005-separate-ess-service.md). The service is still a separate process ([ADR-0018](0018-team-app-changes-nothing-in-the-scheduler.md) rules out touching the Scheduler's nginx file).

## Decision

- The ESS runs on the Scheduler's server as its own pm2 process, `team-rvm-ess`, on port 3001. It listens on 127.0.0.1 only, so nginx on the same server is its only caller.
- Its host name is **`team-api.rvmcad.org`**: an A record at GoDaddy to `13.234.232.151`, the Scheduler's server (KP, 16 Oct). The deploy reads it from the repository variable `ESS_HOST`.
- It sits behind its own nginx server block. team_app's deploy manages that block with [`apps/ess-api/deploy/configure-nginx.sh`](../../apps/ess-api/deploy/configure-nginx.sh):
  1. It writes the block to a file of its own, `/etc/nginx/sites-available/team-rvm`.
  2. Until the certificate exists, the block only serves certbot's challenge over HTTP and answers everything else with a JSON 503. The API is never served over plain HTTP.
  3. It obtains the certificate with certbot (webroot, `/var/www/team-rvm-acme`), then switches the block to HTTPS. certbot renews it through the same directory.
  4. After every change it runs `nginx -t` for the whole server and reloads nginx only when the test passes.
- The Scheduler's server-block files are never written. The script refuses a host name that is the Scheduler's (`scheduler.rvmcad.org`, `student.rvmcad.org`) or that another enabled site already serves.

## Consequences

- **The app has two base URLs:**
  - `https://scheduler.rvmcad.org/api` for the Scheduler's endpoints. The punch cookie stays with this host.
  - `https://team-api.rvmcad.org/api/ess` for the ESS. Both accept the same sign-in token.
- **nginx is shared.**
  - The Scheduler's deploy runs `nginx -t` over every enabled site and stops if it fails. A broken team_app block would therefore block the Scheduler's deploys.
  - So when a test fails, the script puts the last good file back (kept in `~/.team-rvm/`), or removes its link if there is none, and the deploy fails loudly. If the test still fails without the new file, another site is broken, and the script switches its own block off too.
  - [`apps/ess-api/deploy/test-nginx.sh`](../../apps/ess-api/deploy/test-nginx.sh) runs each of these cases against a real nginx in CI.
- **Upload size.** The ESS's upload limit (12 MB) is set in its own block. The Scheduler's `/api/` limit stays as it is.
- **No CORS.** The Android app needs no CORS. A future web client of the ESS would.
- **Phase 0 tasks for KP:**
  - the DNS record (done, 16 Oct);
  - team_app's deploy secrets, with a deploy key of its own (done, 16 Oct);
  - turning on `ESS_DEPLOY_ENABLED` ([docs/05-deploy.md](../05-deploy.md)).
