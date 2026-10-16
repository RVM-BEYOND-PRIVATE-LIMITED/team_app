# ADR-0001: Record architecture decisions as ADRs

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's request of 16 Oct 2026 to keep a summary and ADRs of the project documents in this repository

## Context

Team RVM is built by a backend engineer (KP, working with AI coding agents) and a mobile developer, in two repositories: team_app and Scheduler_Backend. So far its decisions have been made in many places:
- voice notes and chat;
- the App Brief;
- the gap report;
- the developer's prompt.

Without one place to look, settled questions get asked again and earlier answers are lost.

## Decision

- Each architecture decision gets its own numbered file in `docs/adr/`, using the template in [README.md](README.md).
- Product rules go in [../03-decisions.md](../03-decisions.md).
- Every record names who decided, when, and where.

## Consequences

- Agents and new developers read `docs/` before they start, and don't reopen settled questions.
- An Accepted ADR is changed only by a newer ADR that supersedes it.
