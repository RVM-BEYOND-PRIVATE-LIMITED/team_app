# Product decisions

How Team RVM behaves, as RVM decided it. Architecture decisions are in [adr/](adr/README.md).

- **Decided**: KP chose it.
- **Default**: the brief's recommendation, not yet confirmed. Build to it unless KP says otherwise.
- **Open**: still needs an answer.

## The 16 decisions in the brief

| # | Decision | Answer | Status | Source | Tasks affected |
| --- | --- | --- | --- | --- | --- |
| 1 | Who approves requests | The reporting manager on the HR record (`hr_employees.manager_id`), or HR when none is recorded. HR, the CEO and super admins can decide any request; their decision is recorded as HR's. | Decided | KP, 16 Oct | C10, D1, H6 |
| 2 | Monthly request limits | See [Request limits](#request-limits) | Decided | KP, 16 Oct | C3, C6 |
| 3 | Tabs for Admin, Admin Manager and Finance Admin | All five tabs (Home, Inbox, Wall, Me, My Team), with no Work section | Decided | KP, 16 Oct | A4 |
| 4 | Sign-in screen | One field (phone, email, employee code or username). Credentials stay exactly the same. | Decided | KP, 16 Oct | A5 |
| 5 | Location with the screen off | Yes, while punched in. A foreground service with a visible notification sends a ping every 2 minutes until punch-out or midnight. Google Play's location declaration is needed. | Decided | KP, 16 Oct | B4 |
| 6 | Mocked location | Refuse the punch. Record mocked pings and flag them for HR. | Decided | KP, 16 Oct | B14 |
| 7 | Offline punching | Not allowed in the first version ("Punching needs a connection") | Default | Brief | B15 |
| 8 | Posting on the Wall | Everyone can post, comment, react, praise and run polls. Only HR, the CEO and super admins post announcements. HR can hide anything, with a reason. | Decided | KP, 16 Oct | F1–F8 |
| 9 | Colleague contact details | Work email is visible to everyone. A phone number is visible only to that person's manager chain and to HR. | Decided | KP, 16 Oct | E2, E8 |
| 10 | Pay in the app | Nothing for now | Default | Brief | E1 (never return pay) |
| 11 | Moving phones from the browser to the app | HR resets the registered phones in bulk, branch by branch, at go-live. A reset browser can never punch again. | Decided | KP, 16 Oct | B8 |
| 12 | Build stack | Flutter, in team_app (not flutterapps) | Decided | KP, 16 Oct | — |
| 13 | Distribution | Google Play, from an organisation account, with closed testing for the pilot | Default | Brief | K6 |
| 14 | Overtime | None, anywhere. The brief advises asking counsel first, because the Code on Wages pays overtime at twice the normal rate. | Decided | KP, 15 Oct | B10 |
| 15 | First sign-in | Unchanged: HR's first-time password, then the employee chooses their own. The one-time-code route also stays. | Decided | KP, 15 Oct | A2 |
| 16 | Punch button colours | Forge Orange to punch in, Ironwood to punch out | Default | Brief | None (app only) |

## Request limits

Limits are per employee, per calendar month. HR can change them later (task C6).

| Request | Limit | Notes |
| --- | --- | --- |
| Work from home | Not allowed | The request type is hidden. The design keeps a `work_mode` column so WFH can be switched on later. |
| On duty | No limit | Each request still needs approval. The geofence is waived on an approved day. |
| Fix a day | 3 | |
| Excuse a late | 3 | |
| Short leave | 180 minutes | Phase 2 |
| CL (casual leave) | 1 | The database already enforces this with a unique index. |
| Leave without pay | Not set | Open |

**Payroll cut-off: the 5th of the next month** (KP, 16 Oct). Requests can reach back to this month and last month. Last month's requests close on the 5th.

## Other decisions

| Decision | Answer | Status | Source |
| --- | --- | --- | --- |
| HR Executive in the app | HR's powers without attendance. Approves documents, profile changes and HR helpdesk tickets. Does not approve attendance or leave requests, and makes no overrides. | Decided | KP, 16 Oct (matches how the role was defined on 15 Oct) |
| Who sees the location trail | HR, the CEO and super admins, as today. No manager view. | Default | Scheduler today |
| Keeping location pings and logs | No automatic deletion; KP deletes them by hand ([ADR-0015](adr/0015-no-automated-retention.md)) | Decided | KP, 16 Oct |
| Push before Firebase is set up | Messages go to the log until the keys are added ([ADR-0016](adr/0016-push-and-integrity-start-off.md)) | Decided | KP, 16 Oct |
| Shared desk logins (fbd.admin and similar) | Can't use the app; each admin signs in as themselves | Default | Brief |

## What RVM must provide (Phase 0)

- A Firebase project for push, and a Google Play organisation account for RVM Beyond Pvt Ltd. The Play account needs a D-U-N-S number.
- From HR:
  - the main phone and email checked for every employee;
  - date of birth, blood group, address and emergency contact, entered once the HR record has those fields.
- Every HOD and HoO on the right login role, every portal login linked to its HR record, and no shared desk logins.
- A privacy and location policy page that names a grievance officer.
- From the brand designer: master logo files and an "rvm TEAM" lockup. Pages 9 and 10 of the brand guidelines also need fixing.
