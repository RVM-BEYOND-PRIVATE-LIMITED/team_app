# ADR-0016: Push and Play Integrity start switched off

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's answer of 16 Oct 2026: neither the Firebase project nor the Google Play organisation account exists yet

## Decision

- **Push (D5–D8) is built in full:**
  - device registration;
  - notifications with an unread count;
  - categories;
  - the push worker.

  Until the `FIREBASE_*` secrets exist, the worker writes each message to the log instead of sending it, like the Scheduler's SMS "console mode". The deploy log says this on every deploy.
- **Play Integrity is built but stays off.** The server-side verification (J9, K6) sits behind a switch that stays off until a Play project exists. Until then, a punch doesn't need an integrity token.

## Consequences

- RVM needs two Phase 0 items:
  - a Firebase project, which is free and quick to create;
  - a Google Play organisation account for RVM Beyond Pvt Ltd, which needs a D-U-N-S number and takes longer.
- Mocked locations are refused regardless ([../03-decisions.md](../03-decisions.md)). That doesn't depend on Play Integrity.
