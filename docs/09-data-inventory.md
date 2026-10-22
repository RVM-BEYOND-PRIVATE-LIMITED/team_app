# Data inventory for Google Play's Data safety form

22 Oct 2026 · Team RVM app (staff only) · Applies to the ESS (`team_app`) and the Scheduler calls
the app makes

This is the working answer sheet for the Play Console's Data safety section: what the app collects
or processes, why, who can see it, how long it is kept and how a person asks for deletion. It
covers the app's own data and the HR records the app reads; it does not cover the students' data,
which the staff app does not collect from the person using it.

## 1. Summary for the form

| Play category | Collected? | Shared? | Purpose | Optional? |
| --- | --- | --- | --- | --- |
| Name, employee code, designation, department, branch | Yes (from HR records) | No | App functionality, employee management | No (employment record) |
| Email address, phone number | Yes (HR record; phone for HR's reset and contact rules) | No | App functionality, communications, account management | No |
| Address, date of birth, blood group, emergency contact | Yes, if the person fills them in (`/me/personal`) | No | App functionality, safety | Yes |
| Photos (profile, Wall, documents) | Yes, when the person uploads one | No | App functionality | Yes (profile photo optional; document types vary) |
| Files and documents (PDFs, certificates, ID proofs) | Yes, when uploaded | No | App functionality, HR records | Some mandatory document types |
| Financial info: bank account number, IFSC, bank name | Yes, when the person saves them | No | Payroll/HR administration | Yes |
| Precise location | Yes, at punch/ping time and in a mocked-location report | No | App functionality (attendance), fraud prevention | No while punching |
| App activity: Wall posts/comments/reactions, helpdesk tickets, leave/attendance requests, poll votes, acknowledgements | Yes | No | App functionality | Yes (except the work actions) |
| Device or other IDs: FCM push token, install id, device label | Yes | No | App functionality (push, kept sign-in) | Push can be refused at the OS level |
| App info and performance: app version, provider label, mock flag, client time | Yes (with punches and reports) | No | App functionality, fraud prevention | No |
| Messages (helpdesk thread, Wall comments) | Yes | No | App functionality | — |
| Contacts, calendar, SMS, call log, microphone, camera roll browsing, health, browsing history | **No** | — | — | — |

No advertising, no analytics SDK, no crash-reporting SDK, no sale of data. There is no third-party
sharing; Supabase (database, storage) and, when enabled, Google Firebase Cloud Messaging are
processors acting for RVM.

## 2. What each thing is, and where it lives

| Data | Where it is stored | Who can see it |
| --- | --- | --- |
| Identity and job fields | Scheduler `hr_employees`, `users` | The person; HR roles; managers see their reports' names and job fields (contact rule: email to everyone, phone to HR/self/manager chain) |
| Personal details and emergency contact | ESS `hr_ess_personal_details` | The person; HR roles (reads audited) |
| Profile photo | Scheduler `hr_employees.photo_path` + bucket `documents` | The person, colleagues via the directory/profile, HR |
| Documents | ESS `hr_ess_documents` + private bucket `ESS` | The person; HR; identity documents only HR Manager and above (audited) |
| Bank details | ESS `hr_ess_bank_details` | The person; HR reads are audited and masked to the last four |
| Attendance day and punches | Scheduler `hr_staff_attendance`; punches/pings in the Scheduler's attendance tables | The person; HR; the reporting line as the Scheduler allows |
| Location at punch/ping | The Scheduler's punch/ping rows (latitude, longitude, accuracy) | The person, HR, the reporting line where the Scheduler shows it |
| Mocked-location report | ESS `hr_ess_mock_location_reports` | The person's HR roles (report list) |
| Requests, balances, decisions | ESS `hr_ess_attendance_requests`, `hr_ess_leave_requests`, histories | The person; the approver chain; HR |
| Wall content | ESS Wall tables | Colleagues per scope; HR moderation; the author |
| Praise | ESS Wall tables | Colleagues; the receiver |
| Poll votes | ESS `hr_ess_wall_poll_votes` | Nobody for anonymous polls (the database keeps the voter for integrity but no reply exposes it); for named polls, counts only to readers |
| Announcements and acknowledgements | ESS announcement tables | The audience; the sender sees counts, not who read what except acknowledgement totals |
| Helpdesk tickets | ESS `hr_ess_helpdesk_tickets`, messages, attachments | The raiser; the category's team; HR's oversight except confidential categories (POSH/grievance hidden) |
| Infra register mirror | Scheduler `infra_tickets` (summary only) + ESS link | Admin Manager's roles; anonymous tickets carry no identity |
| Class attendance | Scheduler `student_attendance` (written by the ESS for teaching staff) | The faculty who own/cover the batch and the admin roles; students' names and admission numbers only |
| Class attendance alerts | Scheduler `pending_alerts` (resolved only) | The Scheduler's faculty screens |
| Sessions and tokens | ESS `hr_ess_sessions` (hashes only) | The person (list/end); the ESS |
| Push tokens | ESS `hr_ess_push_devices` | The person; no other person sees a token |
| Audit trail | ESS `hr_ess_audit` | HR's technical roles; the trail records acts, not content |

## 3. Location declaration

- **Precise location is collected only at the moment of a punch, a ping while on duty, or when the
  phone reports a mocked location.** The ESS does not track in the background; the Scheduler's
  punch/ping does not either.
- The app declares location as **collected, not shared, for app functionality and fraud
  prevention**, and explains in the listing that attendance is location-verified at the office and
  during on-duty pings.
- A mocked-location report is a **security report**, not the person's location history; it is shown
  to HR only.
- The branch geofence and the accuracy rule are the Scheduler's; the app does not store a location
  history of its own.

## 4. Retention and deletion

- **HR records** (identity, attendance, requests) follow RVM's employment-record retention and the
  Scheduler's own rules; attendance records are kept five years (ADR: no automated purge).
- **ESS files** (photos, documents) stay until replaced or deleted; the old photo file is left for
  manual cleanup (flagged to KP).
- **Sessions** expire (90 days) or are ended; ended sessions keep their row for the audit trail, not
  for use.
- **Requests and audit** are retained as the employment record and the security trail.
- **Deletion/correction:** the app's Data requests screen (`POST /me/data-requests`) is the route;
  HR answers it (`/hr/data-requests`). The Play listing's data-deletion link points to RVM's
  privacy page and the same HR channel. Deleting the app does not delete the employment record;
  leaving the company ends access (the ESS refuses inactive employees).

## 5. Security

- TLS everywhere; tokens are short-lived access tokens (1 hour) plus a revocable refresh token
  (90 days), stored on the phone in the platform's secure storage.
- The ESS uses the Scheduler's service key only server-side; every database table is service-role
  only (RLS on, no public policy).
- HR reads of personal details, bank details and confidential helpdesk tickets are audited; a
  failed audit refuses the read.
- No data is sent to an ad network, analytics provider or data broker.

## 6. What the Play form should say, in one pass

- **Data types:** personal info (name, email, phone, address, DOB, employee ID), financial info
  (bank account), photos, files/docs, precise location, app activity (in-app actions and content),
  app info/performance (app version, diagnostics-free), device IDs (push token, install id),
  messages.
- **Collected or shared:** collected; **not shared**.
- **Purposes:** app functionality; account management; communications; fraud prevention/security;
  employee/HR administration.
- **Encrypted in transit:** yes.
- **Deletion request:** yes, via the in-app data request and the privacy-page link.
- **Children:** the app is for RVM staff (18+); not designed for children.
