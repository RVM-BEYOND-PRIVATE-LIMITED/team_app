# Deploying the ESS

The ESS is the new employee self-service API in `apps/ess-api`. It runs on the Scheduler's server as its own pm2 process, behind its own nginx file for its own host name, **`team-api.rvmcad.org`** ([ADR-0019](adr/0019-ess-on-its-own-subdomain.md)).

**Nothing deploys yet.** A merge to `main` deploys only when the repository variable `ESS_DEPLOY_ENABLED` is `true` ([ADR-0011](adr/0011-ci-merge-and-auto-deploy.md)). Until KP sets it, the deploy workflow runs the tests and stops.

## Where the set-up stands (16 Oct 2026)

| Step | State |
| --- | --- |
| DNS: `team-api.rvmcad.org`, an A record to `13.234.232.151` (the Scheduler's server), at GoDaddy | Done by KP, 16 Oct |
| Repository secrets: `HOST`, `USER`, `SSH_PRIVATE_KEY`, `JWT_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` | Done by KP, 16 Oct |
| Repository variable: `ESS_HOST` = `team-api.rvmcad.org` | Done, 16 Oct |
| A deploy key of its own: `team_app_deploy`, made on the server, its public half in `/home/ubuntu/.ssh/authorized_keys`, its private half only in the `SSH_PRIVATE_KEY` secret | Done by KP, 16 Oct |
| The read-only server check (below) | To run |
| `ESS_DEPLOY_ENABLED` = `true`: the first deploy | KP, when ready |

## What the deploy touches, and what it never touches

| On the server | Touched by team_app's deploy |
| --- | --- |
| `/home/ubuntu/team_app/` | Yes: the code, and `apps/ess-api/.env` (mode 600) |
| pm2 process `team-rvm-ess` (port 3001, listening on 127.0.0.1 only) | Yes: started or reloaded by name |
| `/etc/nginx/sites-available/team-rvm` and its link in `sites-enabled` | Yes |
| `/var/www/team-rvm-acme/` | Yes: certbot's challenge directory |
| The certbot certificate named `team-api.rvmcad.org` | Yes |
| `/home/ubuntu/.team-rvm/` | Yes: the last nginx file that passed `nginx -t` |
| `/home/ubuntu/Scheduler_Backend/`, the pm2 process `scheduler-backend` | **Never** |
| `/etc/nginx/sites-available/scheduler` and `student` | **Never** |
| The database | **Never.** The deploy runs no migration ([ADR-0021](adr/0021-migrations-new-tables-only.md)) |

nginx is shared, and the Scheduler's deploy stops when `nginx -t` fails for any site. So team_app's deploy tests the whole server after every change to its file, and reloads nginx only when the test passes. When a test fails, it puts the last good file back, or removes its link if there is none. [`apps/ess-api/deploy/test-nginx.sh`](../apps/ess-api/deploy/test-nginx.sh) runs each of these cases against a real nginx in CI.

## Before the first deploy: check the server

Actions, then **Check the server**, then **Run workflow**. It only reads: no file is written, no process is started or stopped, and nginx is tested, never reloaded. It reports:
- that the deploy key logs in;
- the server's Node version (the ESS needs Node 20 or later, and shares the Scheduler's Node);
- that port 3001 is free;
- that `sudo`, nginx and certbot work as the deploy needs;
- that `nginx -t` passes today, before any team_app change;
- that `team-api.rvmcad.org` points at the server the deploy logs in to.

## The first deploy

1. Set the repository variable `ESS_DEPLOY_ENABLED` to `true`.
2. Run the deploy: Actions, then **Deploy ESS**, then **Run workflow** on `main`. Later merges deploy by themselves.
3. Read the log. In order, it shows:
   - each setting, as a length, never a value;
   - the server's Node version;
   - the ESS's health reply from the server itself, including whether it reached the database;
   - the nginx stage. On the first run nginx serves a set-up page over HTTP while certbot issues the certificate, then switches to HTTPS;
   - a last check from outside: `https://team-api.rvmcad.org/api/ess/health`.

   If certbot fails, the deploy warns and keeps the set-up page, and the next deploy tries again.

## After that

- Every merge to `main` that changes `apps/ess-api`, the root `package.json` or `package-lock.json`, or the deploy workflow deploys again. Changes to `docs/` don't.
- Deploys run one at a time, in order.

## Switching it off, or going back

| Need | Do this |
| --- | --- |
| Stop future deploys | Set `ESS_DEPLOY_ENABLED` to anything but `true` |
| Switch the ESS off, keep the process | Set the variable `ESS_ENABLED` to `false` and run the deploy. Every endpoint except `/api/ess/health` answers 503 `MODULE_DISABLED` |
| Go back to the previous code | Revert the merge on `main`. The revert deploys like any merge |
| Stop the process now | On the server: `pm2 stop team-rvm-ess`. nginx then answers 502 |
| Take the host off nginx | On the server: `sudo rm /etc/nginx/sites-enabled/team-rvm && sudo nginx -t && sudo systemctl reload nginx` |
| Revoke the deploy key | On the server, delete the line ending `team_app deploy` from `~/.ssh/authorized_keys` |

None of these touch the Scheduler.

## Settings

The deploy writes these into `apps/ess-api/.env`, from the secrets and variables, through environment variables, so no value passes through the script's text. [apps/ess-api/.env.example](../apps/ess-api/.env.example) describes each one for local work.

| Name | Required | From |
| --- | --- | --- |
| `JWT_SECRET` | Yes, at least 32 characters | Secret: the Scheduler's own value, exactly. A different value makes the ESS refuse every sign-in |
| `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` | Yes | Secrets: the Scheduler's own values |
| `PORT`, `HOST` | No: 3001 and 127.0.0.1 | Set by pm2 (`apps/ess-api/ecosystem.config.cjs`) |
| `ESS_ENABLED` | No: on unless `false` | Variable |
| `GIT_SHA` | No | The deploy writes the commit; `/api/ess/health` reports it as the version |
| `MIN_APP_VERSION`, `LATEST_APP_VERSION` | No | Variables, once the app ships |
| `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY_B64` | No: push is log-only without all three | Secrets, once the Firebase project exists. The private key goes in base64 on one line: `base64 -w0 key.pem` |

The workflow itself also reads `HOST`, `USER` and `SSH_PRIVATE_KEY` (the server login), `SSH_KNOWN_HOSTS` (optional: the server's pinned host key, which the server check prints), and the variables `ESS_HOST` and `ESS_DEPLOY_ENABLED`.

## Migrations

There are none yet. When the first `hr_ess_*` tables arrive, they will be in `db/migrations`, with a rollback for each in `db/rollbacks`. KP applies them by hand, in order ([ADR-0021](adr/0021-migrations-new-tables-only.md)). Until a feature's migration is applied, its endpoints answer 503 `MODULE_NOT_INSTALLED`.
