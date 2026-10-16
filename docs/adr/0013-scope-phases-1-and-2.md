# ADR-0013: This round builds Phases 1 and 2

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's answer of 16 Oct 2026

## Decision

In scope, as phased in the brief's Keka parity map:

**Phase 1**
- the five-tab shell, sign-in and the app lock;
- punch, the calendar, location pings and reminders;
- quick actions and "Off this week";
- upcoming holidays;
- requests with allowed/used/remaining counters: on duty, fix a day, excuse a late;
- leave: CL and leave without pay;
- approvals and the Inbox, with push and priority tasks;
- Me › Profile (Summary and Job);
- My Team: manager, peers, colleague search, team today and the reporting chain.

**Phase 2**
- birthdays, anniversaries and new joiners;
- announcements with acknowledgement;
- short leave;
- leave balances and history;
- multi-level approvals;
- the Wall: posts, six reactions, comments, praise and polls;
- the Helpdesk, with confidential categories;
- personal-detail edits with HR approval;
- documents;
- the digital ID card;
- the faculty and leader views.

**Out of scope**
- Phase 3 and Later items: languages, pulse surveys, letters and policies (including the Letters folder in E4, following the parity map's Phase 3 row), assets in custody, payslips, optional holidays, points and rewards.
- Anything that would need a change to the Scheduler ([ADR-0018](0018-team-app-changes-nothing-in-the-scheduler.md)). [04-build-plan.md](../04-build-plan.md) lists these items and how team_app works around each one.
- Work from home, which is not offered at all ([../03-decisions.md](../03-decisions.md)).

## Consequences

- The build order still follows [ADR-0012](0012-security-first.md).
- The brief's pilot gate stays. Phase 1 runs at one branch for two weeks before the other branches move to the app. Phase 2 work continues in the meantime.
