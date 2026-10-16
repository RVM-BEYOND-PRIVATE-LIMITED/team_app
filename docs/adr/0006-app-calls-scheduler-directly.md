# ADR-0006: The app calls the Scheduler directly for existing features

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's answers of 16 Oct 2026 ("Directly"; "Scheduler's punch API")

## Context

Much of what the app needs already exists in the Scheduler:
- sign-in;
- punch, the calendar, remarks and holidays;
- account security;
- priority tasks;
- the faculty, HOD and interview endpoints;
- the leaders' attendance board.

The punch path is tied to the client in three ways:
- the device cookie `rvm_att_dev` (Path `/api/hr/my-attendance`);
- a phone User-Agent check;
- per-IP limits. For example, 40 sign-in requests per 15 minutes per IP, in one bucket shared by `otp/request`, `otp/verify` and `password-login` (a code sign-in uses two). This sits on top of a per-person cap of 3 codes per 15 minutes and 10 a day.

## Decision

- **Two hosts.** The Scheduler's base URL is `https://scheduler.rvmcad.org/api`. The ESS has its own host ([ADR-0019](0019-ess-on-its-own-subdomain.md)).
- **Who serves what.** Existing features go to the Scheduler's existing endpoints, exactly as they behave today. New features go to the ESS.
- **One sign-in.** The ESS accepts the tokens the Scheduler issues (the portal JWT and the attendance session), so one sign-in works for both.

## Consequences

- **No relaying.** The ESS never relays Scheduler calls. If it did, every punch would come from the server's IP address, and the device cookie would have to be passed through.
- **One contract for both.** The OpenAPI contract ([ADR-0010](0010-openapi-contract-first.md)) documents the existing Scheduler endpoints the app uses, exactly as they behave, alongside the new ones.
- **One cookie jar.** The app keeps one persistent cookie jar for `scheduler.rvmcad.org`.
- **A fourth client.** Team RVM becomes the fourth client of the Scheduler API, after the web portal, the flutterapps apps (staff and student) and the student portal. None of the endpoints it uses changes ([ADR-0018](0018-team-app-changes-nothing-in-the-scheduler.md)).
- **No new token types.** The Scheduler can't be changed to accept one. So the refreshable session (task A3) mints its short-lived access tokens in the Scheduler's existing formats, which the punch path already accepts.
- **The ESS checks tokens itself.** It runs as a separate process, so it cannot load the Scheduler's middleware. It must:
  - **Accept the portal JWT.**
    - HS256 over `JWT_SECRET`, valid 64 hours.
    - Payload: `userId, role, locationId, username, locationName, isSuperAdmin`, plus `id` = faculty id for teaching roles (faculty, hod). `isSuperAdmin` is true for ceo, super_admin and accounts_admin.
    - The JWT carries no audience.
    - `locationName` is the branch name the client typed at sign-in, signed without checking, so the ESS takes the branch from the `users` row, never from the token.
  - **Accept the attendance session.**
    - HS256 over `sha256hex('rvm-punch-session:' + JWT_SECRET)`, audience `rvm-punch`, valid 30 days.
    - Payload: `k: 'punch', e: <hr_employees.id>, m: 'otp' | 'pw'`.
  - **Refuse every other token signed with `JWT_SECRET`,** including student tokens and the admission-undertaking token.
  - **Repeat the punch path's checks on every request:**
    - the attendance login is still active;
    - the token's `iat` is at or after `sessions_valid_from`, comparing whole seconds. A strictly-after check would be wrong: `POST /my-attendance/password` writes the cut-off and returns the new token in the same second, so that token would be refused for good;
    - the employee is still active;
    - a portal login is linked to an HR record. An unlinked login gets 403 `NOT_LINKED`.
- **Don't sign out during a database outage.** The Scheduler answers 401 "Please authenticate" both for a bad token and for a database error during its user lookup. The app checks once more before signing anyone out.
