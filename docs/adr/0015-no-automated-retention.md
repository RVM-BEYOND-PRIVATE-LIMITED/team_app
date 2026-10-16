# ADR-0015: No automated purge of location pings or logs

- Status: Accepted
- Date: 16 Oct 2026
- Decided by: KP
- Source: KP's answer of 16 Oct 2026: "I will do it manually so no need to create functionality"

## Context

The gap report asked for a job that purges location pings (K5, and part of B15), and for access logs to be kept for 180 days. The law sets two retention floors:
- **Today:** CERT-In's directions require logs to be kept for 180 days.
- **From about 13 May 2027:** the DPDP Rules require at least one year.

## Decision

- No purge job and no retention setting are built.
- KP deletes old pings and logs by hand.

## Consequences

- K5 and the purge part of B15 are removed from the build.
- `hr_attendance_pings` grows by about 29,000 rows on a full working day (about 107 staff × one ping every 2 minutes over a 9-hour shift), or roughly 9 million rows a year. Its indexes must serve reads by employee and day.
- Manual deletion must keep at least 180 days of logs now, and at least one year from May 2027. This is research, not legal advice.
