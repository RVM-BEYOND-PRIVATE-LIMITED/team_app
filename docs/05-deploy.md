# Deploying the ESS

The ESS is the new employee self-service API in `apps/ess-api`. It runs on the Scheduler's server as its own pm2 process, behind its own nginx file for its own host name, **`team-api.rvmcad.org`** ([ADR-0019](adr/0019-ess-on-its-own-subdomain.md)).

**Live since 16 Oct 2026.** The repository variable `ESS_DEPLOY_ENABLED` is `true`, so every merge to `main` that changes the ESS deploys it ([ADR-0011](adr/0011-ci-merge-and-auto-deploy.md)). Set it to anything else to stop deploys; the tests still run.

## Where the set-up stands (16 Oct 2026)

| Step | State |
| --- | --- |
| DNS: `team-api.rvmcad.org`, an A record to `13.234.232.151` (the Scheduler's server), at GoDaddy | Done by KP, 16 Oct |
| Repository secrets: `HOST`, `USER`, `SSH_PRIVATE_KEY`, `JWT_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` | Done by KP, 16 Oct |
| Repository variable: `ESS_HOST` = `team-api.rvmcad.org` | Done, 16 Oct |
| A deploy key of its own: `team_app_deploy`, made on the server, its public half in `/home/ubuntu/.ssh/authorized_keys`, its private half only in the `SSH_PRIVATE_KEY` secret | Done by KP, 16 Oct |
| The read-only server check (below) | Passed, 16 Oct: Node 22.23.1, nginx 1.18.0, certbot 1.21.0, pm2 6.0.14, port 3740 free |
| `ESS_DEPLOY_ENABLED` = `true`: the first deploy | Done, 16 Oct: commit `65d2b94` deployed at 18:26 IST. `https://team-api.rvmcad.org/api/ess/health` answers with the database reached; the certificate runs to 14 Jan 2027 and renews itself |

## What the deploy touches, and what it never touches

| On the server | Touched by team_app's deploy |
| --- | --- |
| `/home/ubuntu/team_app/` | Yes: the code, and `apps/ess-api/.env` (mode 600) |
| pm2 process `team-rvm-ess` (port 3740, listening on 127.0.0.1 only) | Yes: started or reloaded by name |
| `~/.pm2/dump.pm2`, the list `pm2 resurrect` restores after a reboot, which holds the Scheduler and the server's other apps too | Yes: `pm2 save` after each deploy, with two guards. Before touching pm2 at all, the deploy checks that pm2 is running every app in that list; if pm2 has lost any (a reboot without resurrect, a killed daemon), it stops with nothing changed and names them, because starting the ESS then would let the list shrink to the ESS alone. And it saves only while `scheduler-backend` is online, so a Scheduler stopped by hand is never saved as stopped |
| `/etc/nginx/sites-available/team-rvm` and its link in `sites-enabled` | Yes |
| `/var/www/team-rvm-acme/` | Yes: certbot's challenge directory |
| The certbot certificate named `team-api.rvmcad.org` | Yes |
| `/home/ubuntu/.team-rvm/` | Yes: the last nginx file that passed `nginx -t` |
| `/home/ubuntu/Scheduler_Backend/`, the pm2 process `scheduler-backend` | **Never** |
| `/etc/nginx/sites-available/scheduler` and `student`, and the server's other sites | **Never** |
| The database | **Never.** The deploy runs no migration ([ADR-0021](adr/0021-migrations-new-tables-only.md)) |

nginx is shared, and the Scheduler's deploy stops when `nginx -t` fails for any site. So team_app's deploy tests the whole server after every change to its file, and reloads nginx only when the test passes. When a test fails, it puts the last good file back, or removes its link if there is none. [`apps/ess-api/deploy/test-nginx.sh`](../apps/ess-api/deploy/test-nginx.sh) runs each of these cases against a real nginx (1.18 and 1.24) in CI.

## Before the first deploy: check the server

Actions, then **Check the server**, then **Run workflow**. It only reads: no file is written, no process is started or stopped, and nginx is tested, never reloaded. It reports:
- that the deploy key logs in;
- the server's Node version (the ESS needs Node 20 or later, and shares the Scheduler's Node);
- that the ESS's port, 3740, is free, and which process holds every listening port;
- that `sudo`, nginx and certbot work as the deploy needs, and that the server has exactly one Let's Encrypt account (certbot runs unattended, so it cannot ask which account or for an email);
- that `nginx -t` passes today, before any team_app change;
- that `team-api.rvmcad.org` points at the server the deploy logs in to;
- the server's host key, as the lines to store in `SSH_KNOWN_HOSTS` if KP wants it pinned.

## The first deploy

1. Set the repository variable `ESS_DEPLOY_ENABLED` to `true`.
2. Run the deploy: Actions, then **Deploy ESS**, then **Run workflow** on `main`. Later merges deploy by themselves.
3. Read the log. In order, it shows:
   - each setting, as a length, never a value;
   - the server's Node version and the ESS's port;
   - the ESS's health reply from the server itself, including whether it reached the database;
   - the nginx stage. On the first run nginx serves a set-up page over HTTP while certbot issues the certificate, then switches to HTTPS;
   - a last check from outside: `https://team-api.rvmcad.org/api/ess/health` must answer as the ESS at this commit. No answer only warns (DNS or the certificate may not be ready on a first deploy); an answer from anything else fails the deploy.

   If certbot fails, the deploy warns and keeps the set-up page, and the next deploy tries again.

## After that

- Every merge to `main` that changes `apps/ess-api`, the root `package.json` or `package-lock.json`, or the deploy workflow deploys again. Changes to `docs/` don't.
- Deploys run one at a time, in order.

## Switching it off, or going back

| Need | Do this |
| --- | --- |
| Stop future deploys | Set `ESS_DEPLOY_ENABLED` to anything but `true`. While it is off, the two rows below that deploy do nothing: the run ends green at "Deploy switched off" |
| Switch the ESS off, keep the process | With `ESS_DEPLOY_ENABLED` still `true`, set the variable `ESS_ENABLED` to `false` and run the deploy, which restarts the ESS with it. Every endpoint except `/api/ess/health` answers 503 `MODULE_DISABLED`, and later deploys keep it off |
| Go back to the previous code | With `ESS_DEPLOY_ENABLED` still `true`, revert the merge on `main`. The revert deploys like any merge |
| Stop the process now | First set `ESS_DEPLOY_ENABLED` to anything but `true`, because the next deploy starts it again. Then, on the server: `pm2 stop team-rvm-ess`. nginx then answers 502 |
| Take the host off nginx | First set `ESS_DEPLOY_ENABLED` to anything but `true`, because the next deploy puts the link back. Then, on the server: `sudo rm /etc/nginx/sites-enabled/team-rvm && sudo nginx -t && sudo systemctl reload nginx` |
| Delete the ESS certificate | Take the host off nginx first (the row above). The HTTPS file names the certificate, so deleting it while the file is enabled makes `nginx -t` fail for every site, and the Scheduler's deploy then stops. Then `sudo certbot delete --cert-name team-api.rvmcad.org` |
| Revoke the deploy key | On the server, delete the line ending `team_app deploy` from `~/.ssh/authorized_keys` |

None of these touch the Scheduler.

## Who can reach the deploy secrets

GitHub gives a repository's secrets to every workflow run in it, on any branch, and the organisation's GitHub Free plan cannot limit them to `main`. So anyone who can push to team_app could, with a workflow of their own, use the server login and `JWT_SECRET`. Today that is the same three people, all organisation admins, who already hold the same secrets in Scheduler_Backend, so it gives nobody anything new.

Before anyone else gets write access to team_app, in this order:
1. Upgrade the organisation to GitHub Team.
2. Lower the organisation's default repository permission from admin to read or write.
3. Create a `production` environment limited to the `main` branch, without the administrators' bypass.
4. Move `HOST`, `USER`, `SSH_PRIVATE_KEY`, `SSH_KNOWN_HOSTS`, `JWT_SECRET`, `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` and `FIREBASE_*` into that environment, and delete the repository-level copies.
5. Add `environment: production` to the `deploy` job in `deploy-ess.yml` and the `check` job in `check-server.yml`.
6. Protect `main` so that changes arrive by pull request.

Requiring two-factor sign-in for the organisation's members protects the same secrets today, on any plan.

## Settings

The deploy writes these into `apps/ess-api/.env`, from the secrets and variables, through environment variables, so no value passes through the script's text. [apps/ess-api/.env.example](../apps/ess-api/.env.example) describes each one for local work.

| Name | Required | From |
| --- | --- | --- |
| `JWT_SECRET` | Yes, at least 32 characters | Secret: the Scheduler's own value, exactly. A different value makes the ESS refuse every sign-in. The deploy refuses a value containing `$`, a backtick or a backslash, because the Scheduler's deploy rewrites those. If it stops there, rotating is not a deploy step: it changes the Scheduler, takes effect only when the Scheduler's deploy runs again, and signs everyone out of both services, so it is KP's decision |
| `SUPABASE_URL`, `SUPABASE_SERVICE_KEY` | Yes | Secrets: the Scheduler's own values |
| `PORT`, `HOST` | No: 3740 and 127.0.0.1 | Set by pm2 (`apps/ess-api/ecosystem.config.cjs`, the one place the port is set) |
| `ESS_ENABLED` | No: on unless `false` | Variable |
| `GIT_SHA` | No | The deploy writes the commit; `/api/ess/health` reports it as the version |
| `MIN_APP_VERSION`, `LATEST_APP_VERSION` | No | Variables, once the app ships |
| `FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY_B64` | No: push is log-only without all three | Secrets, once the Firebase project exists. The private key goes in base64 on one line: `base64 -w0 key.pem` |

The workflow itself also reads `HOST`, `USER` and `SSH_PRIVATE_KEY` (the server login), and the variables `ESS_HOST` and `ESS_DEPLOY_ENABLED`. `SSH_KNOWN_HOSTS` is optional: the server's host key as known_hosts lines, which the server check prints after "store these lines". Never paste the fingerprint lines printed above them: they match no host, and every deploy would then fail with "Host key verification failed".

## Migrations to apply

The deploy never runs a migration ([ADR-0021](adr/0021-migrations-new-tables-only.md)). KP applies each one by hand, after review. Until a feature's migration is applied, its endpoints answer 503 `MODULE_NOT_INSTALLED` and nothing else changes, so the code can deploy first.

Twenty-nine in all: Wave 2's five, Wave 3's five, Wave 4's two, Phase 2A's four, Phase 2B's two, Phase 2C's six, Phase 2D's two, G6's link table, the Wall's poll-close repair and the WFH allowance. KP applied 13 to 27 by 22 Oct 2026; **28 (the Wall repair) and 29 (the WFH allowance) are the ones still to apply**. Re-running any file is safe, and the read-only check below can be run at any time. [04-build-plan.md](04-build-plan.md#migrations-in-run-order) says what each creates and what waits for it.

| # | Migration | Rollback |
| --- | --- | --- |
| 1 | `db/migrations/20261101000000_hr_ess_sessions.sql` | `db/rollbacks/20261101000000_hr_ess_sessions.sql` |
| 2 | `db/migrations/20261105000000_hr_ess_audit.sql` | `db/rollbacks/20261105000000_hr_ess_audit.sql` |
| 3 | `db/migrations/20261105000001_hr_ess_data_requests.sql` | `db/rollbacks/20261105000001_hr_ess_data_requests.sql` |
| 4 | `db/migrations/20261105000002_hr_ess_personal_details.sql` | `db/rollbacks/20261105000002_hr_ess_personal_details.sql` |
| 5 | `db/migrations/20261105000003_hr_ess_mock_location_reports.sql` | `db/rollbacks/20261105000003_hr_ess_mock_location_reports.sql` |
| 6 | `db/migrations/20261106000000_hr_ess_request_limits.sql` | `db/rollbacks/20261106000000_hr_ess_request_limits.sql` |
| 7 | `db/migrations/20261106000001_hr_ess_attendance_requests.sql` | `db/rollbacks/20261106000001_hr_ess_attendance_requests.sql` |
| 8 | `db/migrations/20261106000002_hr_ess_leave_requests.sql` | `db/rollbacks/20261106000002_hr_ess_leave_requests.sql` |
| 9 | `db/migrations/20261106000003_hr_ess_request_archives.sql` | `db/rollbacks/20261106000003_hr_ess_request_archives.sql` |
| 10 | `db/migrations/20261106000004_hr_ess_request_functions.sql` | `db/rollbacks/20261106000004_hr_ess_request_functions.sql` |
| 11 | `db/migrations/20261107000000_hr_ess_push_devices.sql` | `db/rollbacks/20261107000000_hr_ess_push_devices.sql` |
| 12 | `db/migrations/20261107000001_hr_ess_notifications.sql` | `db/rollbacks/20261107000001_hr_ess_notifications.sql` |
| 13 | `db/migrations/20261108000001_hr_ess_wall_posts.sql` | `db/rollbacks/20261108000001_hr_ess_wall_posts.sql` |
| 14 | `db/migrations/20261108000002_hr_ess_wall_reports.sql` | `db/rollbacks/20261108000002_hr_ess_wall_reports.sql` |
| 15 | `db/migrations/20261108000003_hr_ess_announcements.sql` | `db/rollbacks/20261108000003_hr_ess_announcements.sql` |
| 16 | `db/migrations/20261108000004_hr_ess_notification_categories.sql` | `db/rollbacks/20261108000004_hr_ess_notification_categories.sql` |
| 17 | `db/migrations/20261109000001_hr_ess_helpdesk.sql` | `db/rollbacks/20261109000001_hr_ess_helpdesk.sql` |
| 18 | `db/migrations/20261109000002_hr_ess_notification_categories.sql` | `db/rollbacks/20261109000002_hr_ess_notification_categories.sql` |
| 19 | `db/migrations/20261110000001_hr_ess_documents.sql` | `db/rollbacks/20261110000001_hr_ess_documents.sql` |
| 20 | `db/migrations/20261110000002_hr_ess_change_requests.sql` | `db/rollbacks/20261110000002_hr_ess_change_requests.sql` |
| 21 | `db/migrations/20261110000003_hr_ess_bank_details.sql` | `db/rollbacks/20261110000003_hr_ess_bank_details.sql` |
| 22 | `db/migrations/20261110000004_hr_ess_helpdesk_assignment.sql` | `db/rollbacks/20261110000004_hr_ess_helpdesk_assignment.sql` |
| 23 | `db/migrations/20261110000005_hr_ess_posh_queue.sql` | `db/rollbacks/20261110000005_hr_ess_posh_queue.sql` |
| 24 | `db/migrations/20261110000006_hr_ess_notification_documents.sql` | `db/rollbacks/20261110000006_hr_ess_notification_documents.sql` |
| 25 | `db/migrations/20261111000001_hr_ess_short_leave.sql` | `db/rollbacks/20261111000001_hr_ess_short_leave.sql` |
| 26 | `db/migrations/20261111000002_hr_ess_approval_escalations.sql` | `db/rollbacks/20261111000002_hr_ess_approval_escalations.sql` |
| 27 | `db/migrations/20261112000001_hr_ess_infra_links.sql` | `db/rollbacks/20261112000001_hr_ess_infra_links.sql` |
| 28 | `db/migrations/20261112000000_hr_ess_wall_poll_closed_repair.sql` | `db/rollbacks/20261112000000_hr_ess_wall_poll_closed_repair.sql` |
| 29 | `db/migrations/20261113000001_hr_ess_wfh_allowances.sql` | `db/rollbacks/20261113000001_hr_ess_wfh_allowances.sql` |

**Applying them (KP):**
1. Before, on any machine with Docker: `npm run test:migrations` from the repository root. It runs all thirty against a throwaway Postgres and must end "Every migration check passed."
2. In the Supabase dashboard, open the SQL editor of the Scheduler's project.
3. Paste one file whole, from the `main` branch, and run it. Then the next, in the order above. Each is safe to run again if a run is interrupted.
4. Each file ends by telling PostgREST to reload its schema, so the endpoints work within seconds, with no restart.

**The check afterwards (an agent, read-only, with KP's OK).** Nothing is written; each step only reads:
- Each new table answers through PostgREST with the service key: `GET /rest/v1/<table>?select=id&limit=0` (`select=employee_id` for `hr_ess_personal_details`, `select=type` for `hr_ess_request_limits`) is 200, not 404 `PGRST205`.
- The same request with the anon key is refused with a permission error: every new table's privileges are revoked from the API roles, and row-level security is on as well.
- The seven request functions appear in the PostgREST OpenAPI listing (`GET /rest/v1/`) for the service key, and not for the anon key: `hr_ess_decide_attendance_request`, `hr_ess_decide_leave_request`, `hr_ess_withdraw_attendance_request`, `hr_ess_withdraw_leave_request`, `hr_ess_cancel_attendance_request`, `hr_ess_cancel_leave_request`, `hr_ess_on_duty_apply`.
- KP, in the SQL editor, which also only reads: `SELECT relname, relrowsecurity FROM pg_class WHERE relname LIKE 'hr\_ess\_%' AND relkind = 'r';` shows every `hr_ess_*` table, each `true`; `SELECT tablename, policyname FROM pg_policies WHERE tablename LIKE 'hr\_ess\_%';` shows no rows; `SELECT indexname FROM pg_indexes WHERE tablename = 'hr_ess_sessions';` shows six, `hr_ess_sessions_live_family_key` and `hr_ess_sessions_sign_in_key` among them; `SELECT tgname FROM pg_trigger WHERE tgname LIKE 'hr\_ess\_%';` shows `hr_ess_sessions_bind_password`, `hr_ess_data_requests_open_limit`, `hr_ess_attendance_requests_filed_trg` and `hr_ess_leave_requests_filed_trg`.

**Going back.** Run the rollback of the same name, last applied first. A rollback deletes that table's rows. Rolling back `hr_ess_sessions` makes the tokens the ESS minted answer 503 instead of 401, so tell staff to sign out of the app and in again ([04-build-plan.md](04-build-plan.md#migrations-in-run-order)).

B1 (the day read) and B8 (the phone list and reset) need no migration of their own, but they read the Scheduler's attendance tables (`20261015000004` to `20261023000000`), which are still to be confirmed in production. Until they are, those endpoints answer 503 `MODULE_NOT_INSTALLED`.
