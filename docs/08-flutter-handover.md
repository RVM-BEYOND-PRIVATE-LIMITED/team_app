# Team RVM app: backend handover to the Flutter developer

22 Oct 2026 · Contract `packages/contracts/openapi.yaml` **0.11.0** · ESS live at
`https://team-api.rvmcad.org`

This note is the single handover: the two hosts, the sign-in flow, every endpoint by screen, the
error model, the upload rules and what is still the app's to finish. The OpenAPI file is the
authority for shapes and statuses; this note says how the screens use them.

---

## 1. The two hosts

| Host | Base URL | What goes there |
| --- | --- | --- |
| ESS (`team_app`) | `https://team-api.rvmcad.org/api/ess` | Everything in section 4 except the Scheduler calls below |
| Scheduler | the Scheduler's API base (the app's `schedulerBaseUrl`) | The punch itself: `POST /hr/my-attendance/challenge`, `/punch`, `/ping`, `/remarks`; the attendance password login and OTP request/verify; the portal password login and forgot/reset; the teaching screens the ESS does not replace (batches/timetable, interviews) |

The app keeps two clients today and that is correct for the pilot. The ESS **never proxies** a
Scheduler call (ADR-0006): a punch goes straight to the Scheduler with the Scheduler's own token.

## 2. Sign-in

1. **One field:** `POST /sign-in/resolve { identifier }` (no token). The answer is one of:
   - `{ kind: 'portal', login_with: 'as_typed', location_names: [...] }` — the identifier is a
     `users.username` or `users.phone_number`; send it and the password to the Scheduler's portal
     login, and offer the branch list when the screen asks.
   - `{ kind: 'portal', login_with: 'username_or_phone' }` — the person was found through their
     employee code, HR email or main phone; ask them for their username or phone, then the portal
     password.
   - `{ kind: 'attendance', methods: ['code', 'password'] }` — an attendance-only login; use the
     Scheduler's OTP/password endpoints with the methods offered. `methods: []` or
     `{ kind: 'unknown' }` means no usable login — show "ask HR", never a wrong-password message.
2. **Keep the sign-in:** a fresh Scheduler sign-in (within **10 minutes**) is traded at
   `POST /session { install_id, device_label? }` for `access_token` (1 hour), `refresh_token`
   (90 days) and the session id. Send the ESS `access_token` as `Authorization: Bearer` on every
   ESS call.
3. **Refresh:** `POST /session/refresh { refresh_token, install_id }`; a refusal (401 with
   `reason`) means the sign-in is over — sign out and show why.
4. **Sign out:** `POST /session/sign-out` (or `DELETE /sessions/{id}`); list them with
   `GET /sessions`.
5. **The app signs out on 401 only.** A 403 is a refusal of one action and never ends the session.
6. **429 on the office IP:** the Scheduler limits per IP, so the first sign-ins on the shared office
   connection can hit it. Show "Try again in a few minutes" — never a wrong password. Staff can
   sign in on mobile data or in small groups.

## 3. Error model

Every refusal is `{ "error": "<staff-facing message>", "code": "UPPER_SNAKE" }`.

| Status | Meaning in the app |
| --- | --- |
| 400 `VALIDATION_FAILED` | Show the message; it names the field's rule |
| 401 `NOT_AUTHENTICATED` | Sign out. A refresh refusal adds `reason` |
| 403 (`NOT_AN_EMPLOYEE`, `NOT_LINKED`, `NOT_ACTIVE`, `PORTAL_LOGIN_REQUIRED`, `HR_ACCESS_DENIED`, `HELPDESK_AGENT_ONLY`, `CLASS_*`, `NOT_FACULTY`, …) | Do not sign out; show the message and hide/disable the action |
| 404 | The thing is gone; refresh the list |
| 409 (`CLASS_ALREADY_MARKED`, `HELPDESK_TRANSITION`, `ALREADY_DECIDED`, `CL_LIMIT`, …) | Show the message; the screen should offer "refresh" |
| 413 `PAYLOAD_TOO_LARGE` | The file is too big — compress and retry |
| 429 `RATE_LIMITED` | Back off; `Retry-After` is sent |
| 503 (`MODULE_NOT_INSTALLED`, `UNAVAILABLE`) | The server is not ready; retry later, never sign out |

The exact code list and its messages are in `apps/ess-api/README.md` (Errors) and the contract's
examples; the app should never invent wording for a code it receives.

## 4. Endpoints by screen

### Sign-in, splash, account

| Screen | Calls |
| --- | --- |
| Splash | `GET /health` (no token; `ok`, `db`, `min_app_version`, `latest_app_version`) |
| Login | `POST /sign-in/resolve`; Scheduler portal/OTP/password calls; then `POST /session` |
| Account/security | Both kinds: `GET /me/account`, `GET /me/capabilities`, `GET /sessions`, `DELETE /sessions/{id}`, `POST /session/sign-out`. Portal only: the Scheduler's `GET/POST /me/*` for email, phone, password and two-factor. Attendance only: `POST /me/password`; email and phone are HR-managed. |
| Notifications settings | `GET /notifications/settings`, `PUT /notifications/settings` |
| Push registration | `POST /push-devices`, `DELETE /push-devices/{id}` |

**Attendance-only sessions and the Scheduler (issue #10).** An attendance session has no users
row, so the Scheduler's `/api/me` guard and every other Scheduler screen cannot answer it. The
app must hide, for `login.kind === 'attendance'`: Scheduler Account & Security, Security
activity, Priority tasks, Announcements, Interviews, My batches/indicators and Faculty
Development, and the Helpdesk team queue. Use the ESS equivalents: `GET /me/account`,
`POST /me/password`, the Wall's announcements, `GET /attendance/day`, requests, documents and the
ID card. A data request is how the person asks HR to change the email or phone that their
attendance login uses. The Scheduler is not widened to accept the punch token (ADR-0018).

### Home, Me and my team

| Screen | Calls |
| --- | --- |
| Home / punch | `GET /attendance/day?date=`, `POST /attendance/mock-location` (mock report), Scheduler challenge/punch/ping |
| My profile | `GET /me/profile`; `GET /me/personal`, `PUT /me/personal`; `PUT /me/photo` |
| My org | `GET /me/org` |
| Directory | `GET /directory?q=&branch_id=&department_id=` |
| My team | `GET /team/today?filter=`, `GET /team/off-this-week` |
| Praise on my profile | `GET /me/praise?employee_id=` |
| ID card | `GET /me/id-card`; the QR opens `GET /id-card/verify/{token}` (no sign-in) |
| Data requests | `POST /me/data-requests`, `GET /me/data-requests` |
| Documents | `GET /me/documents`, `POST /me/documents`, `DELETE /me/documents/{id}`, `GET /me/documents/{id}/file` |
| Personal change requests | `POST /me/change-requests`, `GET /me/change-requests` |
| Bank details | `GET /me/bank-details`, `PUT /me/bank-details` |

### Requests, leave and approvals

| Screen | Calls |
| --- | --- |
| New request | `POST /attendance-requests` (`on_duty`, `fix_a_day`, `excuse_late`, `short_leave` with `minutes`), `POST /leave-requests` (`cl`, `lwp`, and `wfh` only when `GET /me/wfh` says enabled) |
| My requests | `GET /attendance-requests`, `GET /leave-requests`; withdraw with `POST /attendance-requests/{id}/withdraw`, `POST /leave-requests/{id}/withdraw` |
| Balances | `GET /leave/balances?month=` |
| Work from home | `GET /me/wfh` — the allowance and this month's used, pending and remaining |
| Approvals Inbox | `GET /approvals?status=`, `POST /approvals/{family}/{id}/decide`, `POST /approvals/{family}/{id}/archive` |
| The chain | `GET /approvals/{family}/{id}/chain` |

### Notifications

`GET /notifications`, `POST /notifications/{id}/read`, `POST /notifications/read-all`,
`GET/PUT /notifications/settings`. The categories are `approvals`, `decisions`,
`priority_tasks`, `mentions`, `replies`, `praise`, `announcements`, `acknowledgements`, `polls`,
`helpdesk`, `documents`. Quiet hours are 21:00-08:00 IST, server-side.

### The Wall

| Screen | Calls |
| --- | --- |
| Feed | `GET /wall/posts?scope=&before=`, `POST /wall/posts`, `GET/PATCH/DELETE /wall/posts/{id}`, `GET /wall/settings` |
| Reactions | `PUT/DELETE /wall/posts/{id}/reaction`, `GET /wall/posts/{id}/reactions`; the same on `/wall/comments/{id}/...` |
| Thread | `GET/POST /wall/posts/{id}/comments`, `PATCH/DELETE /wall/comments/{id}` |
| Praise | `POST /wall/praise` (fixed badges), `GET /me/praise` |
| Polls | `GET /wall/polls/{id}`, `POST /wall/polls/{id}/vote`, `DELETE /wall/polls/{id}/vote`, `POST /wall/polls/{id}/close` |
| Announcements | `GET /wall/announcements`, `GET /wall/announcements/{id}`, `POST .../read`, `POST .../ack`, `GET .../counts`; sender: `POST /wall/announcements`, `PATCH/DELETE /wall/announcements/{id}`, `GET /wall/hr/announcements` |
| Celebrations | `GET /wall/celebrations`, `POST /wall/wishes`, `GET/PUT /me/celebration-optout` |
| Report/moderation | `POST /wall/posts/{id}/reports`, `/wall/comments/{id}/reports`; HR: `GET /wall/hr/reports`, `POST /wall/hr/reports/{id}/resolve`, `POST /wall/posts/{id}/hide`, `/wall/comments/{id}/hide`, `GET /wall/hr/moderation-log` |

**The path is `/wall/posts`, not `/feed`.** The old placeholder in `wall_screen.dart` is stale.
Edit window 15 minutes (409 `EDIT_WINDOW_CLOSED`); photos and PDFs are base64 JSON, up to 5 files,
each ≤1 MB decoded (body limit 7 MB).

### Helpdesk

`GET /helpdesk/categories`, `POST /helpdesk/tickets`, `GET /helpdesk/tickets?status=`,
`GET /helpdesk/tickets/{id}`, `POST .../comments`, `POST .../withdraw`, `POST .../reopen`,
`POST .../close`, `POST .../claim`, `POST .../status`, `POST .../assign`;
team queue `GET /helpdesk/queue`. The ticket detail carries `infra` when a lab/facility ticket was
mirrored to the Admin Manager's register. POSH's queue is the Internal Committee only.

### Faculty (teaching roles)

| Screen | Calls |
| --- | --- |
| My day / indicators | `GET /me/faculty-day?date=` |
| Class marking | `GET /me/batches/{id}/roster?date=`, `POST /me/batches/{id}/attendance`, `PATCH /me/batches/{id}/attendance/{date}/remarks` |
| My batches/timetable, interviews | Scheduler endpoints (unchanged) |

### Leaders and HR tools

| Screen | Calls |
| --- | --- |
| Leaders overview (CEO, super admin) | `GET /leaders/overview` |
| Registered phones | `GET /hr/devices?status=&branch_id=`, `POST /hr/devices/reset` |
| Personal details | `GET/PUT /hr/employees/{id}/personal` |
| Data requests | `GET /hr/data-requests?status=`, `PATCH /hr/data-requests/{id}` |
| Mock reports | `GET /hr/mock-location-reports?from=&to=&branch_id=` |
| Request limits | `GET /hr/request-limits`, `PUT /hr/request-limits/{type}` |
| WFH allowances | `GET /hr/wfh-allowances?q=`, `PUT /hr/wfh-allowances/{employeeId}` — HR enables WFH per employee and sets the monthly days |
| Documents review | `GET /hr/employees/{id}/documents`, `POST .../{documentId}/verify`, `POST .../{documentId}/reject`, `GET .../file` |
| Change requests | `GET /hr/change-requests`, `POST /hr/change-requests/{id}/decide` |
| Bank details (HR read) | `GET /hr/employees/{id}/bank-details` |
| Cancel an approved request | `POST /hr/attendance-requests/{id}/cancel`, `POST /hr/leave-requests/{id}/cancel` |

## 5. Uploads

- Body is JSON with the file base64-encoded (no multipart): `{ file_name, content_type, data }`
  (documents add `doc_type` and `remark` for `others`).
- Compress on the phone: photos to **≤1 MB**, documents to **≤5 MB**; the ESS rejects larger.
- The ESS stores files in its private bucket and returns 300-second signed links; do not cache a
  signed URL past its life.
- A photo change is audited and needs no HR approval.

## 6. What is still the app's to finish

1. Point the Wall at `/api/ess/wall/*` and remove the `/feed` placeholder.
2. Wire the Helpdesk screens (raise, list, thread, claim/status, assign, queue).
3. Wire Documents, change requests, bank details and the ID card.
4. Wire the faculty "my day" and class marking (the roster/save/remarks endpoints above); the old
   `mark_attendance_screen` still calls the Scheduler directly and should move to the ESS.
5. Wire the leaders' overview and the approval chain view; add the `minutes` field for short leave.
6. Show all 11 notification categories in settings.
7. Handle 401-only sign-out, 429 as "try again in a few minutes", and 413 as "file too big".
8. Keep the branch chooser on a portal sign-in; do not advertise an employee code as a login until
   it matches `hr_employees.employee_code`.

**Done in this repo (22 Oct 2026):** the Home **Work-from-home** card is wired in
`lib/features/work/wfh_sheet.dart` and `lib/features/home/home_screen.dart`. It reads `GET /me/wfh`,
shows the remaining/limit and files `POST /leave-requests { type: 'wfh', day, reason }`; a login
without an allowance sees "not offered" and cannot submit. It was written without a Flutter SDK on
the build machine, so run `flutter analyze` and the widget tests before shipping the next build.

The contract and `apps/ess-api/README.md` are the reference for every field and status; a shape the
contract does not name is not sent, and a code the README does not list is not produced.
