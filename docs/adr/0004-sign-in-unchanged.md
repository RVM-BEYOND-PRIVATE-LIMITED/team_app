# ADR-0004: Sign-in stays as it is, behind a one-field front door

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source:
  - KP's voice note of 15 Oct 2026: "the email ID and passwords flow of the HRMS … will stay the same for this app";
  - the first-time password flow deployed on 15 Oct 2026 (Scheduler_Backend PR #83);
  - KP's answer of 16 Oct 2026: one sign-in field.

## Context

Two kinds of login exist at Scheduler_Backend `c28b9ca`.

| | Portal login | Attendance login |
| --- | --- | --- |
| Who has it | People with a `users` row | Staff with no portal login (41 on 15 Oct 2026, per the brief) |
| Endpoints | `POST /api/users/login`, and `/login/verify` when two-factor is on | `POST /api/hr/my-attendance/password-login`, `/otp/request`, `/otp/verify`, `/password` |
| What it returns | A 64-hour JWT with no refresh | A 30-day session that opens only `/api/hr/my-attendance/*` |
| Rules | | HR creates it with a first-time password, which must be replaced before the first punch. Five wrong passwords lock it for 15 minutes. |

KP first asked for a password generated automatically at first login, then decided the HRMS email-and-password flow stays the same.

## Decision

- The app uses the same two logins and the same credentials. No new password scheme.
- The sign-in screen has one field, which takes a phone number, email, employee code or username. A resolver endpoint in the ESS (task A5) tells the app which login applies. It never creates or changes a credential.
- The first-time flow stays as deployed: sign in with HR's password, then choose your own. The one-time-code route stays as well.
- The PIN and fingerprint stay on the phone. They unlock the stored session and are never sent to the server.

## Consequences

- This supersedes "password generated automatically at first login". It also settles the brief's recommendation ("First sign-in: the code, password fallback"), because both routes already exist.
- **The resolver can't widen portal login.**
  - Portal login matches only the username or the login phone, and changing that would be a Scheduler change ([ADR-0018](0018-team-app-changes-nothing-in-the-scheduler.md)).
  - So when the field holds an email or employee code that belongs to a portal account, the app asks for the username or phone instead.
  - The resolver must not reveal more about whether an account exists than the login endpoints already do, and it needs rate limits.
- **A refreshable session (task A3) is still needed:** a PIN cannot reopen a 64-hour token that has expired.
  - It must keep the attendance login's revocation rule. That is `sessions_valid_from`, which only attendance logins have.
  - Portal logins have no revocation today (task A7). Adding one would be a Scheduler change, which is out of scope.
