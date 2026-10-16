# ADR-0008: JavaScript, Express and the Scheduler's conventions for the new API

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's answer of 16 Oct 2026: JavaScript

## Context

Scheduler_Backend is written in CommonJS JavaScript on Express 4. It uses:
- `express ^4.19.2`;
- `zod ^4.6.6`;
- `jsonwebtoken ^9.0.2`;
- `@supabase/supabase-js ^2.44.4`;
- `vitest ^4.1.11` with `supertest` for tests.

It has no linter, and it has shipped bugs where a handler used a name that was never defined.

## Decision

- **Stack.** The new API is JavaScript (CommonJS) on Express 4. It uses:
  - zod for input validation;
  - `@supabase/supabase-js` with the service key;
  - vitest and supertest for tests.

  Dependency versions start from the Scheduler's.
- **Lint.** ESLint, including `no-undef`, runs in CI.
- **Conventions copied from the Scheduler:**
  - errors are `{ "error": "<message for staff>", "code": "<CODE>" }`;
  - 401 is only for an absent or rejected token; 403 or 409 for everything else;
  - dates are in IST (`Asia/Kolkata`) as `YYYY-MM-DD`, and days turn over at IST midnight;
  - role names and inheritance come from a copy of the Scheduler's `config/roles.js`, and the HR and attendance role sets from a copy of `config/hrPolicy.js` (where `HR_ROLES` includes `hr_executive` and `ATTENDANCE_OVERRIDE_ROLES` does not). A test compares both copies with a local Scheduler_Backend checkout when one is available. CI can't read the private Scheduler repository, so the copies are refreshed by hand when the Scheduler changes;
  - a response never contains a password hash, a storage path or a full Aadhaar number.

## Consequences

- Code and patterns move between the two repositories unchanged.
- There is no build step on the server.
- TypeScript was considered and not chosen.
