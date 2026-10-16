# ADR-0012: Security fixes first, then identity, then features

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: the developer's prompt of 16 Oct 2026, STEP 2: "security fixes first (section J), then identity and session (A), then Phase 1 features, then the rest"

## Decision

- **Order:**
  1. the section J fixes, plus any issue #70 items still open;
  2. identity and session (section A);
  3. Phase 1;
  4. Phase 2.
- **Every new route** needs `auth` (or `employeeAuth`) plus a role or ownership check. Its tests include a role-denied case and a wrong-owner case.
- **Never returned:** password hashes, storage paths and full Aadhaar numbers.
- **401** is only for an absent or rejected token.

## What "section J" covers now

The STEP 1 check found the open holes to be wider than the gap report's J1–J9. The list is in [02-reconciliation.md](../02-reconciliation.md), under "Security holes that are open today". In order:

1. **Phone-only takeover.** A phone number is enough to take over a portal account. Retire `POST /api/users/reset-password` and stop `GET /api/users` handing out phone numbers.
2. **Money writes.** `/api/accounts` approvals and payments have no role check.
3. **Elevated accounts.** A branch admin can reset the password of an elevated account in its branch.
4. **Student-token exposure.** Student tokens reach attendance writes, student password hashes, admissions and dues, alerts, announcements, batch writes, faculty reports and faculty contacts.
5. **Exit.** Leaving the company does not end portal access.
6. **The committed dump.** `physical_dump_2026.sql` holds password hashes and auth tokens. Removing it from history is KP's decision.

## Consequences

- No more tokens go onto phones until the open J items are fixed.
- The faculty views can't ship until the server checks who may mark which batch, and on which dates (H1, J1, J2).
