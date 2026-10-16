# ADR-0002: team_app holds the Team RVM backend and the Flutter app

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's messages of 16 Oct 2026 ("make this monorepo … for the backend and front end of the app"; "C:\Users\Prakash\Documents\GitHub\RVMCAD_Scheduler\team_app this should be path of the app")

## Context

- **The prompt's options.** The developer's prompt asked where the monorepo should live: a new repository, Scheduler_Backend converted into a monorepo, or a folder inside an existing repository.
- **The brief's recommendation.** The App Brief recommended building the app in the flutterapps repository, beside the RVM Staff and student apps.
- **An existing scaffold.** The mobile developer has an empty Flutter scaffold, `apps/rvm_team_app`, in their local flutterapps checkout (the gap report calls that checkout `rvm_mobile`). It has not been pushed. On 16 Oct 2026, flutterapps `master` held only `staff_app` and `student_app`.

## Decision

- The private repository `RVM-BEYOND-PRIVATE-LIMITED/team_app` holds both the new Team RVM backend and the Flutter app.
- Scheduler_Backend and Scheduler_frontend stay in their own repositories. Nothing moves into team_app.
- The app uses the Scheduler's existing features through the Scheduler's API ([ADR-0006](0006-app-calls-scheduler-directly.md)).

## Consequences

- This supersedes the brief's recommendation of "Flutter in the flutterapps monorepo".
- The developer's `rvm_team_app` scaffold moves here ([ADR-0014](0014-mobile-developer-owns-flutter-app.md)).
- flutterapps packages can't be imported from here by path. This covers `core_network`, `core_auth` and the staff app's faculty-attendance blocs. Reusing them means copying them or adding a pubspec git dependency.
- Backend work is split across two repositories ([ADR-0007](0007-scheduler-changes-as-scheduler-prs.md)).
