# ADR-0006: The app calls the Scheduler directly for existing features

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's answer of 16 Oct 2026

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
- per-IP limits, for example 40 one-time codes per 15 minutes per IP.

## Decision

- The base URL is `https://scheduler.rvmcad.org/api`.
- For existing features, the app calls the Scheduler's existing endpoints. Only new features call `/api/ess/*`.
- The new service accepts the same tokens the Scheduler issues (the portal JWT and the attendance session), so one sign-in works for both.

## Consequences

- **No relaying.** The new service never relays Scheduler calls. If it did, every punch would come from the server's IP address, and the device cookie would have to be passed through.
- **One contract for both.** The OpenAPI contract ([ADR-0010](0010-openapi-contract-first.md)) documents the existing Scheduler endpoints the app uses, exactly as they behave, alongside the new ones.
- **One cookie jar.** The app keeps one persistent cookie jar for `scheduler.rvmcad.org`.
- **A fourth client.** Team RVM becomes the fourth client of the Scheduler API, after the web portal, the flutterapps staff and student apps, and the student portal. Changing how an existing endpoint behaves needs KP's OK and a note in the contract.
- **New token types.** If the refreshable session (task A3) introduces a new token type, both the Scheduler's punch middleware and the ESS must accept it.
- **The ESS checks tokens itself.** It runs as a separate process, so it cannot load the Scheduler's middleware ([02-reconciliation.md](../02-reconciliation.md), A1 and the identity findings). It must:
  - Accept the portal JWT: HS256 over `JWT_SECRET`, 64 hours, payload `userId, role, locationId, username, isSuperAdmin`, plus `id` = faculty id for teaching roles. The JWT carries no audience.
  - Accept the attendance session: HS256 over `sha256hex('rvm-punch-session:' + JWT_SECRET)`, audience `rvm-punch`, 30 days, payload `k: 'punch', e: <hr_employees.id>, m: 'otp' | 'pw'`.
  - Refuse student tokens, the admission-undertaking token and any other token signed with `JWT_SECRET`.
  - On every request, check the same things the punch path checks:
    - the attendance login is still active;
    - the token was issued after `sessions_valid_from`;
    - the employee is still active;
    - a portal login is linked to an HR record. An unlinked login gets 403 `NOT_LINKED`.
- **Don't sign out during a database outage.** The Scheduler answers 401 "Please authenticate" both for a bad token and for a database error during its user lookup. The app checks once more before signing anyone out.
