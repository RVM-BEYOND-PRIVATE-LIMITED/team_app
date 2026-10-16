# ADR-0010: One OpenAPI contract is the source of truth for the app

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: the developer's prompt of 16 Oct 2026, adopted by KP: "one OpenAPI file covering every new or changed endpoint … The Flutter team builds against this file, so it is the deliverable that matters most"

## Decision

- One OpenAPI file describes every endpoint the app calls. Its path, `packages/contracts/openapi.yaml`, follows the layout proposed in [ADR-0017](0017-repository-layout-and-tooling.md). The ESS and the Scheduler appear as two servers in the file ([ADR-0019](0019-ess-on-its-own-subdomain.md)). The file covers:
  - the new `/api/ess` endpoints;
  - the existing Scheduler endpoints the app uses. These are marked as existing and described exactly as they behave: auth, request, response and error codes.
- An endpoint change updates the contract in the same PR.
- CI lints the file. Later, a test checks that the implemented routes match it.

## Consequences

- The mobile developer builds against the contract. Generating a Dart client from it is the developer's choice.
- Both developers can merge to `main` ([ADR-0011](0011-ci-merge-and-auto-deploy.md)), so a PR that breaks the contract says so in its title.
