# ADR-0014: The mobile developer sets up and builds the Flutter app

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's answer of 16 Oct 2026

## Decision

- The mobile developer moves the existing `rvm_team_app` scaffold into team_app and builds the app there. The folder name, `apps/rvm_team_app`, follows the layout proposed in [ADR-0017](0017-repository-layout-and-tooling.md).
- The backend side delivers:
  - the contract ([ADR-0010](0010-openapi-contract-first.md));
  - a handover note: base URL, auth flow, endpoints per screen and error codes;
  - the link to the Team RVM design system.
- Backend work doesn't touch `apps/rvm_team_app` unless asked.

## Consequences

- The theme, logos and launcher icons come from two sources:
  - the Team RVM design system, which stays private until KP shares it;
  - the brand guidelines PDF.
- Code from flutterapps can be reused only by copying it or through a git dependency ([ADR-0002](0002-monorepo-is-team-app.md)).
