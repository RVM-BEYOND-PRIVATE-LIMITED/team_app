const { createClient } = require('@supabase/supabase-js');
const { HttpError, MESSAGES } = require('./errors');
const { monthBounds } = require('./time');

/**
 * The ESS's reads and writes on the Scheduler's database, which stays the system of record
 * (ADR-0003).
 *
 * The ESS reads the Scheduler's tables. It writes its own hr_ess_* tables (ADR-0021), and the
 * Scheduler's tables only through named methods KP sanctioned, each doing what the Scheduler's
 * own code does and nothing more:
 *
 *   hr_attendance_devices  HR's bulk phone reset, the Scheduler's own update (revokeActiveDevices;
 *                          KP, 16 Oct, decision 11)
 *   hr_staff_attendance    the shift snapshot the Scheduler's ensureSnapshot copies onto a day
 *                          (setDaySnapshot)
 *   hr_employees           the photo pointer only, the columns the Scheduler's setPhoto writes
 *                          (setEmployeePhoto)
 *   student_attendance     H1 class marking: the upsert of a day's rows and an absent remark's
 *                          update (saveClassAttendance, updateClassRemark; KP, decision 8)
 *   pending_alerts         H1: resolving an 'absent_remarks_missing' alert when the student is
 *                          marked present or the reason is filled (resolveAbsentRemarkAlerts)
 *
 * Never a delete, never another table, never another column.
 *
 * Every read names its columns, and nothing selects '*'. A select('*') is how the Scheduler's
 * marking roster came to hand out password hashes (J2), and a list also means that a column
 * added to one of these tables later cannot reach a reply by accident. hr_attendance_accounts
 * holds a password hash, so it is read for its status and cut-off only, and asked whether a
 * hash exists without the hash ever being sent; hr_attendance_devices holds the hash of each
 * phone's token, so it is never read whole either.
 *
 * Tables and columns checked against Scheduler_Backend supabase/migrations at c28b9ca:
 *   users                   id, username, phone_number, role, faculty_id:
 *                           20251215134244_remote_schema.sql:854-863; location_id:
 *                           20260514000000_schema_gaps.sql:13-14; email, password_changed_at:
 *                           20260909000000_user_profile_security.sql:40-49
 *   locations               id, name: 20260514000000_schema_gaps.sql:42-45
 *   hr_employees            20260826000001_hrms_tables.sql; user_id from
 *                           20260910000000_hr_employee_user_link.sql; the employment_status
 *                           values from 20260917000000_hr_employment_lifecycle.sql
 *   hr_branches, hr_departments  id, name: 20260826000001_hrms_tables.sql
 *   hr_attendance_accounts  20261021000000_hr_attendance_accounts.sql
 *   hr_attendance_devices   20261020000000_hr_attendance_punch.sql:77-93
 *   hr_staff_attendance     20261015000004_hr_staff_attendance.sql, with the punch columns of
 *                           20261020000000:62-66 and the rule columns of 20261022000000:106-123
 *   hr_attendance_remarks   HR's remark: 20261022000000_hr_attendance_shifts.sql:151-160
 *   hr_attendance_employee_remarks  the employee's own: 20261023000000
 * and team_app's own hr_ess_* tables in db/migrations (hr_ess_sessions:
 * 20261101000000_hr_ess_sessions.sql; the others: 20261105000000 to 20261105000003).
 */
const COLUMNS = Object.freeze({
  user: 'id, role, faculty_id',
  // The username is what the Scheduler records as the actor's name (attendanceAdminController.js:18).
  userLogin: 'id, username',
  // Account & Security (issue #10). Never password_hash: it is read by its own method below,
  // compared in memory, and never returned.
  userAccount: 'id, username, email, email_verified_at, phone_number, two_factor_enabled',
  employeeContact: 'id, employee_code, email, phone',
  attendancePassword: 'id, employee_id, status, password_hash, password_set_at, sessions_valid_from',
  // What a minted portal token is built from (lib/accessTokens.js), and when the password last
  // changed, which ends a kept sign-in made before it (policy/sessions.js passwordChangedSince).
  userForToken: 'id, username, role, location_id, faculty_id, password_changed_at',
  // What the sign-in resolver needs to know about an account, and no more: never its username,
  // phone or email, which it is found by and must not hand back.
  userForSignIn: 'id, role, location_id',
  employee: 'id, full_name, employee_code, designation, employment_status, date_of_exit, is_archived, branch_id, department_id, manager_id',
  // The attendance sign-in's own columns (attendanceOtpController.js:134) less the extra phones,
  // which only decide between two of its refusals. Matched in memory and never sent anywhere.
  employeeForSignIn: 'id, employee_code, email, phone, user_id, is_archived, employment_status, date_of_exit',
  report: 'id, employment_status, date_of_exit, is_archived',
  employeeName: 'id, full_name',
  // What HR's lists show about a person: never their phone, email or anything else on the record.
  employeeCard: 'id, full_name, employee_code, branch_id',
  branch: 'id, name',
  department: 'id, name',
  location: 'id, name',
  // H7 (2D): the faculty "my day" reads. The Scheduler's own columns
  // (public_schema_backup.sql:1474-1490, 1744-1753, 1775-1797, 2155-2162).
  batch: 'id, name, faculty_id, start_date, end_date, start_time, end_time, days_of_week, schedule, location_id',
  substitution: 'id, batch_id, original_faculty_id, substitute_faculty_id, start_date, end_date',
  batchStudent: 'batch_id, student_id, joined_at',
  admissionJoined: 'student_id, joined',
  studentAttendance: 'batch_id, student_id, date',
  holdPeriod: 'student_id, hold_start, hold_end',
  studentHoldFlag: 'id, is_on_hold, hold_applied_at',
  pendingRemark: 'id, batch_id, student_id, date, alert_type, is_resolved',
  // H1 (2D): the roster's students, and the day's marks as class marking reads and writes them.
  classStudent: 'id, name, admission_number, is_on_hold, hold_applied_at',
  classAttendance: 'batch_id, student_id, date, is_present, absent_reason, follow_up_comment',
  // password_set_at, and never password_hash: a 'pw' session already proves a hash existed, so
  // whether the person chose their own password is all the first-time check needs.
  attendanceAccount: 'id, employee_id, status, sessions_valid_from, password_set_at',
  attendanceLogin: 'employee_id, status',
  // Every column but refresh_hash and password_fingerprint: a session is found by its hash and
  // never hands it back, and the fingerprint is compared inside the database only.
  session: 'id, family_id, employee_id, login_kind, user_id, location_name, method, signed_in_at, install_id, device_label, created_at, last_used_at, expires_at, revoked_at, revoked_reason',
  sessionStart: 'id, created_at',
  // Never token_hash: it is what a phone's cookie is checked against. Neither user_agent nor
  // bound_ip either: HR's reset needs to know whose phone it is and when it was last used.
  device: 'id, employee_id, status, bound_at, last_seen_at, revoked_at, revoked_by_name, revoke_reason',
  revokedDevice: 'id, employee_id',
  // The day row as the punch screen reads it (attendancePunchController.js:178-179), plus note,
  // which the punch screen leaves out and B1 serves.
  day: 'day, status, leave_type, source, first_in, last_out, worked_minutes, note, '
    + 'late_minutes, early_exit_minutes, late_count, late_half_day, late_excused, shift_start, shift_end',
  hrRemark: 'remarks, updated_at',
  myRemark: 'day, remarks, updated_at',
  // resolved_by_user_id is kept for the record and never sent: the name is what people read.
  dataRequest: 'id, employee_id, kind, details, status, created_at, resolved_at, resolved_by_name, resolution_note',
  personal: 'employee_id, date_of_birth, blood_group, address_line1, address_line2, city, state, pincode, '
    + 'emergency_name, emergency_relation, emergency_phone, updated_at, updated_by_name',
  mockReport: 'id, employee_id, branch_id, reported_at, client_at, kind, latitude, longitude, accuracy_m, provider, app_version, install_id',
  mockReportCreated: 'id, reported_at',
  // C6: the numbers HR can change. updated_by_user_id is kept for the record and never sent.
  requestLimit: 'type, limit_count, limit_minutes, updated_at, updated_by_name',
  // WFH (KP, 22 Oct): HR's per-employee allowance. set_by_user_id is kept for the record and
  // never sent; the name is what people read.
  wfhAllowance: 'employee_id, is_enabled, monthly_limit_days, note, set_by_name, created_at, updated_at',
  // The employee card the allowance list joins to: enough for a name, code, branch and department.
  wfhEmployee: 'id, full_name, employee_code, branch_id, department_id',
  // C1-C12: a request as the app reads it. day_before and day_written_at stay server-side (HR's
  // cancel reads them inside SQL), and the decided_by and cancelled_by account ids are never sent.
  attendanceRequest: 'id, employee_id, type, status, day, reason, place, fix_in, fix_out, minutes, '
    + 'decided_by_name, decided_at, decision_note, cancelled_by_name, cancelled_at, cancel_reason, created_at, updated_at',
  leaveRequest: 'id, employee_id, type, status, day, reason, '
    + 'decided_by_name, decided_at, decision_note, cancelled_by_name, cancelled_at, cancel_reason, created_at, updated_at',
  // The counters and duplicate checks read these. The leave table has no `minutes` column, so the
  // attendance family names its own facts (short leave counts by minutes, C3).
  requestFacts: 'id, employee_id, type, status, day',
  attendanceRequestFacts: 'id, employee_id, type, status, day, minutes',
  // D4: one escalation as the record reads it; nothing here is secret.
  approvalEscalation: 'id, family, request_id, from_employee_id, to_employee_id, reason, escalated_at',
  archive: 'id, family, request_id, employee_id',
  // What ensureSnapshot reads before it copies a shift onto a day (attendanceRules.js:214-236).
  daySnapshot: 'id, source, shift_start',
  employeeShifts: 'id, shift_id, saturday_shift_id, sunday_shift_id, week_off_days',
  shift: 'id, start_time, end_time, grace_minutes, is_active',
  holiday: 'id, day, name, branch_id',
  // The approvals Inbox's context: a day's late marks, and who else is off a day.
  dayLate: 'employee_id, day, late_minutes, late_count, late_half_day, late_excused',
  dayLeave: 'employee_id, day',
  leaveOnDay: 'employee_id, day, status',
  // D5: a registered phone. The token itself is never sent back to the app.
  pushDevice: 'id, employee_id, platform, device_label, install_id, created_at, updated_at, last_seen_at, revoked_at',
  pushTarget: 'id, employee_id, token',
  // D6: one notification as the Inbox reads it; the push bookkeeping stays server-side.
  notification: 'id, category, title, body, data, read_at, created_at',
  notificationWorker: 'id, employee_id, category, title, body, data, push_attempts',
  notificationSetting: 'employee_id, disabled_categories, updated_at',
  taskNotification: 'id, data',
  // D2: the Scheduler's priority tasks, read for push only (its own columns).
  task: 'id, title, due_date, task_date, assigned_to, created_at',
  employeeForUser: 'id, user_id',
  // E1, E2: the HR record as the app may read it (never performance tags, never pay).
  profile: 'id, full_name, employee_code, designation, department_id, branch_id, manager_id, email, phone, '
    + 'date_of_joining, date_of_exit, employment_status, is_archived, photo_path, photo_updated_at',
  // The directory's own columns: enough for a card, nothing more (user_id is read for the
  // "Reports to the CEO (not recorded)" test and never sent).
  directoryPerson: 'id, full_name, employee_code, designation, department_id, branch_id, manager_id, user_id, email, phone, '
    + 'employment_status, date_of_exit, is_archived',
  // E12: the events the Timeline reads. before/after and notes are never selected.
  timeline: 'id, event_type, occurred_at, changed_keys',
  // E6: a team member's day (never the leave type or the reason).
  teamDay: 'employee_id, day, status, first_in, last_out, late_minutes, late_excused',
  userRole: 'id, role',
  // F1-F5: the Wall's rows. A post as the feed reads it: hidden_by_user_id and the delete
  // bookkeeping stay server-side and are never sent. F5's audience list is one jsonb object.
  wallPost: 'id, employee_id, kind, scope, branch_id, body, attachments, mentions, badge, occasion, '
    + 'about_employee_id, poll_multiple, poll_anonymous, poll_closes_on, options_locked_at, poll_closed_at, reaction_counts, '
    + 'comment_count, edited_at, created_at, updated_at, hidden_at, hidden_by_name, hide_reason, deleted_at',
  // What the viewer may do with one row (F1, F2): the author, the two clocks, and a hint of the
  // hidden state, and nothing else.
  wallPostOwn: 'id, employee_id, kind, hidden_at, deleted_at, edited_at, created_at',
  wallComment: 'id, post_id, employee_id, parent_id, body, mentions, reaction_counts, reply_count, created_at, updated_at, '
    + 'hidden_at, hidden_by_name, hide_reason, deleted_at, edited_at',
  wallCommentOwn: 'id, post_id, parent_id, employee_id, hidden_at, deleted_at, edited_at, created_at',
  wallOption: 'id, post_id, option_key, label, position, created_at',
  wallVote: 'id, post_id, option_id, voter_employee_id, voted_at',
  wallReaction: 'id, post_id, comment_id, employee_id, reaction, created_at',
  wallMention: 'mentioned_id',
  wallWish: 'post_id, about_id, wisher_id, occasion, year, created_at',
  wallReport: 'id, reporter_id, post_id, comment_id, reason, detail, status, resolved_by_name, resolved_at, '
    + 'resolution_note, created_at',
  // F5: an announcement as the app reads it, with its audience and its counts. The sender's own
  // list uses the same columns.
  announcement: 'id, employee_id, title, body, attachments, audience, publish_at, published_at, needs_ack, '
    + 'closes_on, pinned, read_count, ack_count, reminded_at, created_at, updated_at, edited_at, deleted_at',
  // F5's audience resolution reads the same card the directory uses, plus the account link so a
  // role filter can be applied to the people behind the logins.
  audienceEmployee: 'id, full_name, employee_code, branch_id, department_id, user_id, employment_status, '
    + 'date_of_joining, date_of_exit',
  // Phase 2B: the Helpdesk's rows. A ticket as every read shows it: the whole row minus nothing
  // sensitive — the raiser is hidden by the views, never by the columns.
  helpdeskCategory: 'id, slug, name, is_ticket, flow, queue_roles, confidential, allows_hold, priority, '
    + 'first_response_hours, resolution_hours, is_active',
  helpdeskTicket: 'id, ref, created_by, category_id, priority, subject, body, attachments, anonymous, branch_id, '
    + 'status, assignee_id, claimed_at, assigned_by_employee_id, assigned_by_name, assigned_at, '
    + 'first_response_at, first_response_due_at, resolution_due_at, resolved_at, '
    + 'closed_at, closed_by_employee_id, closing_reason, rating, reopened_at, escalation_level, created_at, updated_at',
  // What a write needs to know about the row it is about to move.
  helpdeskTicketOwn: 'id, ref, created_by, category_id, status, assignee_id, anonymous, closed_at, resolved_at, '
    + 'assigned_by_employee_id, assigned_at, first_response_at, first_response_due_at, resolution_due_at, '
    + 'escalation_level, created_at',
  helpdeskMessage: 'id, ticket_id, employee_id, kind, body, event, details, created_at',
  // Phase 2C. An assignment's history row: who had it before, who it went to, who pointed it.
  helpdeskAssignment: 'id, ticket_id, from_employee_id, to_employee_id, assigned_by_name, note, created_at',
  // G6 (2D): the mirror to the Admin Manager's register. infra_tickets is the Scheduler's table;
  // only the summary columns the mirror reads or sets are ever named.
  infraTicket: 'id, ticket_no, location_id, raised_on, audit_type, issue, owner, deadline, status, closed_on, raised_by, created_at',
  infraLink: 'id, ticket_id, infra_ticket_id, state, reason, last_synced_at, created_at',
  // My Documents: a type as the raise form reads it, and a document as every read shows it.
  // verified_by_user_id is kept for the record and never sent; the name is what people read.
  documentType: 'slug, name, is_mandatory, sort, created_at',
  document: 'id, employee_id, doc_type, file_name, storage_path, content_type, size_bytes, remark, status, '
    + 'verified_by_name, verified_at, rejection_reason, created_at, updated_at',
  // Profile-change requests. decided_by_user_id is kept for the record and never sent.
  changeRequest: 'id, employee_id, field, old_value, new_value, reason, status, decided_by_name, decided_at, '
    + 'decision_note, created_at, updated_at',
  // Bank details. The account number is masked before it leaves the server for anybody but its
  // owner (routes/bankDetails.js), so the whole row only ever exists inside the server.
  bankDetails: 'employee_id, bank_name, branch_name, account_number, ifsc_code, upi_id, consent_given_at, '
    + 'consent_name, updated_by_name, created_at, updated_at',
  // What an assignment's role check needs to know about the person it points at.
  employeeLink: 'id, user_id, is_archived',
  // What the ID card shows, from the HR record: the card's own fields and the photo pointer.
  idCardEmployee: 'id, full_name, employee_code, designation, branch_id, department_id, photo_path, is_archived',
});

/** The Scheduler's private bucket every HR file lives in (20260830000001:15-16). */
const PHOTO_BUCKET = 'documents';

/**
 * The ESS's own private bucket (KP, 19 Oct 2026): wall photos and PDFs, praise photos and
 * announcement attachments. Employee photos stay in the Scheduler's `documents` bucket, where the
 * HR record's path lives (docs/03-decisions.md).
 */
const ESS_BUCKET = 'ESS';

/**
 * A missing table or column means the code is live before its migration: merges deploy at
 * once and KP applies migrations by hand afterwards (ADR-0011, ADR-0021). That answers 503
 * MODULE_NOT_INSTALLED, never a 500. PGRST205 and PGRST204 are PostgREST's "not in the schema
 * cache" for a table or a column, PGRST202 the same for a function; 42P01, 42703 and 42883 are
 * Postgres's own "undefined table", "undefined column" and "undefined function".
 */
const NOT_INSTALLED_CODES = new Set(['PGRST205', 'PGRST204', 'PGRST202', '42P01', '42703', '42883']);

/** The functions db/migrations/20261101000000_hr_ess_sessions.sql creates for the ESS to call. */
const SESSION_FUNCTIONS = Object.freeze({
  rotate: 'hr_ess_session_rotate',
  revoke: 'hr_ess_session_revoke',
  passwordCurrent: 'hr_ess_session_password_current',
});

/** The functions db/migrations/20261106000004_hr_ess_request_functions.sql creates. */
const REQUEST_FUNCTIONS = Object.freeze({
  decideAttendance: 'hr_ess_decide_attendance_request',
  decideLeave: 'hr_ess_decide_leave_request',
  withdrawAttendance: 'hr_ess_withdraw_attendance_request',
  withdrawLeave: 'hr_ess_withdraw_leave_request',
  cancelAttendance: 'hr_ess_cancel_attendance_request',
  cancelLeave: 'hr_ess_cancel_leave_request',
  onDutyApply: 'hr_ess_on_duty_apply',
});

/**
 * Refusals the database gives on purpose, which the routes answer as a 409 rather than as a
 * failure: the name of the key or rule is in Postgres's message, which PostgREST passes on.
 *   SIGN_IN_KEPT  a Scheduler sign-in already traded (hr_ess_sessions_sign_in_key, 23505)
 *   OPEN_LIMIT    a sixth open data request (the hr_ess_data_requests_open_limit trigger, 23514)
 *   EMERGENCY_HALF  personal details left with half an emergency contact by two saves made at
 *                   once (hr_ess_personal_details_emergency_chk, 23514)
 */
const REFUSALS = Object.freeze({
  SIGN_IN_KEPT: { code: '23505', name: 'hr_ess_sessions_sign_in_key' },
  OPEN_LIMIT: { code: '23514', name: 'hr_ess_data_requests_open_limit' },
  EMERGENCY_HALF: { code: '23514', name: 'hr_ess_personal_details_emergency_chk' },
  // The Scheduler's own one-CL-a-month index, hit when two CL approvals race (or a CL is
  // approved while somebody marks one): the decision answers 409 CL_LIMIT, as its own check does.
  CL_TAKEN: { code: '23505', name: 'uq_hr_staff_attendance_one_cl_a_month' },
  // Archiving a request twice for the same approver: the second is simply already archived.
  ARCHIVE_KEPT: { code: '23505', name: 'hr_ess_request_archives_family_request_id_employee_id_key' },
  // F2: a second reaction on the same post or comment, by the same person, whatever the emoji:
  // the route finds it first (getMyReaction), so this is the backstop for two taps at once.
  ALREADY_REACTED: { code: '23505', name: 'hr_ess_wall_reactions_post_key' },
  ALREADY_REACTED_COMMENT: { code: '23505', name: 'hr_ess_wall_reactions_comment_key' },
  // F6: a second wish for the same person, occasion and year.
  ALREADY_WISHED: { code: '23505', name: 'hr_ess_wall_wishes_key' },
  // F7: a second report of the same thing by the same person: HR already has the first.
  ALREADY_REPORTED: { code: '23505', name: 'hr_ess_wall_reports_post_key' },
  ALREADY_REPORTED_COMMENT: { code: '23505', name: 'hr_ess_wall_reports_comment_key' },
  // F4: an option the poll already has (the unique key on its key, or on its position).
  POLL_OPTION_TAKEN: { code: '23505', name: 'hr_ess_wall_poll_options_post_key' },
  POLL_POSITION_TAKEN: { code: '23505', name: 'hr_ess_wall_poll_options_post_position' },
  // F4: a second vote on one option by the same person (tapping twice quickly).
  ALREADY_VOTED: { code: '23505', name: 'hr_ess_wall_poll_votes_option_key' },
  // F5: the same person added to one announcement's audience twice.
  AUDIENCE_KEPT: { code: '23505', name: 'hr_ess_announcement_audience_key' },
  ANNOUNCEMENT_READ_KEPT: { code: '23505', name: 'hr_ess_announcement_reads_key' },
  // E3: a second open change request for the same field by the same person (the partial unique
  // index). The route checks first; this is the backstop for two saves made at once.
  CHANGE_REQUEST_KEPT: { code: '23505', name: 'hr_ess_change_requests_open_field_key' },
  // D4: the escalation job racing itself -- the same person already escalated for this request.
  ESCALATION_KEPT: { code: '23505', name: 'hr_ess_approval_escalations_family_request_id_to_employee_id_key' },
});

const isRefusal = (error, { code, name }) =>
  Boolean(error && error.code === code && String(error.message || '').includes(name));

/**
 * Matches nothing, so the sign-in resolver can make the same request whatever it found
 * (routes/signIn.js): a lookup it skipped would make "nobody" answer faster than "two people".
 */
const NIL_UUID = '00000000-0000-0000-0000-000000000000';

/**
 * How long one database request may take before it is abandoned. Without it, a database that
 * accepts the connection and then says nothing holds the request for fetch's five-minute
 * default. supabase-js still retries a failed connection a few times (1, 2 and 4 seconds
 * apart), which rides out a blip without letting an outage hang the app.
 */
const DB_REQUEST_TIMEOUT_MS = 5000;

/**
 * How many ids go into one IN filter. PostgREST takes the list in the URL, and a few hundred
 * UUIDs make a URL long enough to be refused; the Scheduler slices at the same size
 * (controllers/hr/staffAttendanceController.js:182-183).
 */
const IN_CHUNK = 150;

/** The most rows one HR list returns. One more is read, to tell the app the list was cut. */
const LIST_LIMITS = Object.freeze({
  // As many as the Scheduler's own phone list (attendanceAdminController.js:260).
  devices: 1000,
  mockReports: 500,
  dataRequests: 500,
  myDataRequests: 100,
  // My own requests, and one approver's Inbox.
  myRequests: 100,
  inbox: 100,
  // The notifications Inbox, newest first.
  notifications: 100,
  // F1, F2: the Wall's feed and one post's thread. 20 keeps a phone's first paint small; the
  // app asks for more with ?before=.
  wallPosts: 20,
  wallComments: 50,
  // F3: a person's praise as their profile shows it, and the celebration cards' look-ahead.
  praiseFor: 20,
  celebrations: 60,
  // F5: an announcement sender's own list, and HR's report queue (F7).
  myAnnouncements: 100,
  announcementsInbox: 100,
  reports: 100,
  moderationLog: 100,
  // Phase 2B: the Helpdesk. A raiser's own list, a team's queue page, and one ticket's thread.
  helpdeskTickets: 50,
  helpdeskQueue: 100,
  helpdeskMessages: 200,
  // Phase 2C: My Documents (a person's own list and HR's per-person list), the change-request
  // queues, and one ticket's assignment history.
  documents: 100,
  hrDocuments: 200,
  changeRequests: 100,
  hrChangeRequests: 200,
  helpdeskAssignments: 50,
  // WFH's per-employee allowance list (KP, 22 Oct).
  wfhAllowances: 200,
});

/**
 * supabase-js builds a Realtime client inside createClient, and on Node 20, which has no
 * built-in WebSocket, that throws as the server starts. The ESS never subscribes to anything,
 * so Realtime gets a transport that refuses to be used instead of a WebSocket library nothing
 * would call.
 */
class NoRealtime {
  constructor() {
    throw new Error('The ESS does not use Supabase Realtime.');
  }
}

/**
 * The refusal for a failed read or write. Never a 401: an outage must not sign anybody out.
 *
 * A data or integrity error (SQLSTATE class 22 or 23: a CHECK, a NOT NULL, a foreign key) means
 * the database refused what the ESS sent, which the ESS's own checks should have stopped. That
 * is the server's fault, not an outage, so it is a 500 rather than "cannot reach the database".
 */
function storeError(table, error) {
  if (error && NOT_INSTALLED_CODES.has(error.code)) {
    return new HttpError(
      503,
      'MODULE_NOT_INSTALLED',
      `Team RVM needs a database update that has not been applied yet (it cannot read ${table}). Ask the tech team.`,
    );
  }
  if (error && typeof error.code === 'string' && /^2[23][0-9A-Z]{3}$/.test(error.code)) {
    return new HttpError(500, 'INTERNAL_ERROR', MESSAGES.INTERNAL_ERROR);
  }
  return new HttpError(503, 'UNAVAILABLE', MESSAGES.UNAVAILABLE);
}

/** What run() answers in place of data for a refusal the caller asked to hear about. */
const REFUSED = Symbol('refused');

const chunks = (list, size = IN_CHUNK) => {
  const out = [];
  for (let i = 0; i < list.length; i += size) out.push(list.slice(i, i + size));
  return out;
};

/**
 * @param {{ supabaseUrl: string, supabaseServiceKey: string }} config
 * @param {{ client?: object }} [options]  tests pass an in-memory client in place of supabase-js
 */
function createSupabaseStore(config, { client } = {}) {
  // The service key, because every HR table is row-level-security deny-all (ADR-0005). No
  // session handling: this is a server, not a signed-in browser.
  const db = client || createClient(config.supabaseUrl, config.supabaseServiceKey, {
    auth: { autoRefreshToken: false, persistSession: false, detectSessionInUrl: false },
    db: { timeout: DB_REQUEST_TIMEOUT_MS },
    realtime: { transport: NoRealtime },
  });

  /**
   * One database request. Only the table, the code and PostgREST's message are logged, never the
   * values asked with: those include refresh-token hashes and whatever was typed at sign-in.
   */
  async function run(verb, table, request, refusal = null) {
    let result;
    try {
      result = await request();
    } catch (e) {
      console.error(`[ess] ${verb} ${table} failed: ${e && e.message ? e.message : e}`);
      throw storeError(table, e);
    }
    // An answer the caller asked for (REFUSALS), not a failure: nothing to log.
    if (result.error && refusal && isRefusal(result.error, refusal)) return REFUSED;
    if (result.error) {
      console.error(`[ess] ${verb} ${table} failed: ${result.error.code || '-'} ${result.error.message || ''}`.trim());
      throw storeError(table, result.error);
    }
    return result.data;
  }

  const read = (table, build) => run('reading', table, () => build(db.from(table)));
  const write = (table, build, refusal) => run('writing', table, () => build(db.from(table)), refusal);
  /**
   * A database function. The table it carries is for the 503's words (and for tests that make one
   * table fail): the sessions functions read and write hr_ess_sessions, the request functions
   * their request table. `refusal` is a database refusal the caller answers as its own 409.
   */
  const call = (fn, args, { table = 'hr_ess_sessions', refusal = null } = {}) =>
    run('writing', table, () => db.rpc(fn, args), refusal);

  /** At most one row, or null. Every filter here is on a key that is unique in the schema. */
  const one = (table, columns, column, value) =>
    read(table, (q) => q.select(columns).eq(column, value).maybeSingle());

  const list = async (table, build) => (await read(table, build)) || [];

  /** Rows whose `column` is one of `ids`, in slices; `extend` adds the other filters. */
  async function readIn(table, columns, column, ids, extend = (q) => q) {
    const unique = [...new Set(ids.filter(Boolean))];
    const out = [];
    for (const part of chunks(unique)) {
      out.push(...((await read(table, (q) => extend(q.select(columns).in(column, part)))) || []));
    }
    return out;
  }

  return {
    getUser: (userId) => one('users', COLUMNS.user, 'id', userId),
    getUserLogin: (userId) => one('users', COLUMNS.userLogin, 'id', userId),
    getUserAccount: (userId) => one('users', COLUMNS.userAccount, 'id', userId),
    getEmployeeContact: (employeeId) => one('hr_employees', COLUMNS.employeeContact, 'id', employeeId),
    getAttendancePasswordHash: (employeeId) => one('hr_attendance_accounts', COLUMNS.attendancePassword, 'employee_id', employeeId),
    getEmployeeById: (employeeId) => one('hr_employees', COLUMNS.employee, 'id', employeeId),
    // hr_employees.user_id is unique where set (hr_employees_user_id_key), so a login is at
    // most one employee.
    getEmployeeByUserId: (userId) => one('hr_employees', COLUMNS.employee, 'user_id', userId),
    getEmployeeName: (employeeId) => one('hr_employees', COLUMNS.employeeName, 'id', employeeId),
    getEmployeeCard: (employeeId) => one('hr_employees', COLUMNS.employeeCard, 'id', employeeId),
    listEmployeeCards: (employeeIds) => readIn('hr_employees', COLUMNS.employeeCard, 'id', employeeIds),
    /** The staff behind a set of employee codes: what the Wall's @mentions resolve to (F1). */
    listEmployeeCardsByCodes: (codes) => list('hr_employees', (q) => q.select(COLUMNS.employeeCard)
      .in('employee_code', codes.length ? codes : [NIL_UUID])),
    /** Everybody whose HR record puts them at this branch, leavers included: their phones are still registered. */
    listEmployeeIdsInBranch: async (branchId) =>
      ((await read('hr_employees', (q) => q.select('id').eq('branch_id', branchId))) || []).map((e) => e.id),
    getBranch: (branchId) => one('hr_branches', COLUMNS.branch, 'id', branchId),
    listBranches: (branchIds) => readIn('hr_branches', COLUMNS.branch, 'id', branchIds),
    listAllBranches: async () => (await read('hr_branches', (q) => q.select(COLUMNS.branch))) || [],
    getDepartment: (departmentId) => one('hr_departments', COLUMNS.department, 'id', departmentId),
    getAttendanceAccount: (employeeId) => one('hr_attendance_accounts', COLUMNS.attendanceAccount, 'employee_id', employeeId),

    /**
     * The people who report to this employee and are not archived. The caller applies the full
     * on-strength rule (policy/employment.js) rather than this query repeating it as filters,
     * so the rule exists in one place.
     */
    listDirectReports: (managerId) =>
      list('hr_employees', (q) => q.select(COLUMNS.report).eq('manager_id', managerId).eq('is_archived', false)),

    /* ── the users row a minted portal token is built from (task A3) ── */

    getUserForToken: (userId) => one('users', COLUMNS.userForToken, 'id', userId),

    /* ── the sign-in resolver (task A5) ── */

    /**
     * The accounts the Scheduler's portal login would consider for a typed identifier: username
     * or login phone, compared exactly (controllers/userController.js:271-279). Two eq filters
     * rather than its or=(...), which needs the value quoted to stay a value; eq takes it as one.
     */
    findUsersByUsername: (value) => list('users', (q) => q.select(COLUMNS.userForSignIn).eq('username', value)),
    findUsersByPhoneNumber: (value) => list('users', (q) => q.select(COLUMNS.userForSignIn).eq('phone_number', value)),
    /** Stored lower-cased, so an exact match on the lower-cased value is the Scheduler's own (authSecurityController.js:139-141). */
    findUsersByEmail: (email) => list('users', (q) => q.select(COLUMNS.userForSignIn).eq('email', email)),
    /** Never empty: an empty list is asked as NIL_UUID, which matches nothing, at the same cost. */
    listUsersByIds: (ids) => list('users', (q) => q.select(COLUMNS.userForSignIn).in('id', ids.length ? ids : [NIL_UUID])),

    /**
     * Every employee not archived, matched in memory as the attendance sign-in matches them
     * (attendanceOtpController.js:132-142): a PostgREST ilike would read `_` and `*` in an address
     * as wildcards. About a hundred rows.
     */
    listEmployeesForSignIn: () => list('hr_employees', (q) => q.select(COLUMNS.employeeForSignIn).eq('is_archived', false)),
    listLocations: () => list('locations', (q) => q.select(COLUMNS.location)),

    /* ── the faculty "my day", H7 (2D): the Scheduler's teaching tables, read only ── */

    listBatchesForFaculty: (facultyId) =>
      list('batches', (q) => q.select(COLUMNS.batch).eq('faculty_id', facultyId)),
    listBatchesByIds: (ids) => readIn('batches', COLUMNS.batch, 'id', ids),
    listSubstitutionsForSubstitute: (facultyId) =>
      list('faculty_substitutions', (q) => q.select(COLUMNS.substitution).eq('substitute_faculty_id', facultyId)),
    listBatchStudents: (batchIds) => readIn('batch_students', COLUMNS.batchStudent, 'batch_id', batchIds),
    /** H7/H1: a student on a roster is joined only when admissions.joined agrees (utils/attendanceEligibility.js:55-89). */
    listAdmissionsJoined: (studentIds) => readIn('admissions', COLUMNS.admissionJoined, 'student_id', studentIds),
    listAttendanceForBatchesBetween: (batchIds, from, to) =>
      readIn('student_attendance', COLUMNS.studentAttendance, 'batch_id', batchIds,
        (q) => q.gte('date', from).lte('date', to)),
    listHoldPeriods: (studentIds) => readIn('hold_periods', COLUMNS.holdPeriod, 'student_id', studentIds),
    listStudentsOnHold: (studentIds) =>
      readIn('students', COLUMNS.studentHoldFlag, 'id', studentIds, (q) => q.eq('is_on_hold', true)),
    listPendingRemarksFor: (batchIds, day) =>
      readIn('pending_alerts', COLUMNS.pendingRemark, 'batch_id', batchIds,
        (q) => q.eq('date', day).eq('alert_type', 'absent_remarks_missing').eq('is_resolved', false)),

    /* ── H1 (2D): class marking, the Scheduler's own rows ── */

    getBatch: (id) => one('batches', COLUMNS.batch, 'id', id),
    /** The roster's own columns and the hold flag, and nothing else from a student's record. */
    listStudentsFor: (studentIds) => readIn('students', COLUMNS.classStudent, 'id', studentIds),
    /** The batch's marks for one day: what the roster shows and the lock is decided from. */
    listClassAttendance: (batchId, day) =>
      list('student_attendance', (q) => q.select(COLUMNS.classAttendance).eq('batch_id', batchId).eq('date', day)),
    /**
     * One row per (batch, student, date), the Scheduler's own unique key: an upsert on it corrects
     * a day for an admin and leaves every other column of an existing row alone.
     */
    saveClassAttendance: (rows) =>
      write('student_attendance', (q) => q.upsert(rows, { onConflict: 'batch_id,student_id,date' })),
    /** The absent remark alone: the mark itself, its presence and the caller's stamp stay put. */
    updateClassRemark: ({ batchId, studentId, day, absentReason, followUpComment, by, at }) =>
      write('student_attendance', (q) => q.update({
        absent_reason: absentReason,
        follow_up_comment: followUpComment,
        remarks_updated_by: by,
        remarks_updated_at: at,
      }).eq('batch_id', batchId).eq('student_id', studentId).eq('date', day).eq('is_present', false)
        .select(COLUMNS.classAttendance).maybeSingle()),
    /**
     * The Scheduler's own alert resolution (attendanceController.js:149-162,1194-1201): every
     * unresolved 'absent_remarks_missing' alert for these students on this day is resolved. One
     * update, never a delete.
     */
    resolveAbsentRemarkAlerts: async ({ batchId, studentIds, day, by, at }) => {
      const ids = [...new Set((studentIds || []).filter(Boolean))];
      if (!ids.length) return 0;
      const rows = await write('pending_alerts', (q) => q.update({ is_resolved: true, resolved_at: at, resolved_by: by })
        .eq('batch_id', batchId).eq('date', day).eq('alert_type', 'absent_remarks_missing')
        .eq('is_resolved', false).in('student_id', ids).select('id'));
      return (rows || []).length;
    },

    listAttendanceLogins: () => list('hr_attendance_accounts', (q) => q.select(COLUMNS.attendanceLogin)),
    /** The logins that have a password, asked as a filter, so not one hash leaves the database. */
    listAttendanceLoginsWithPassword: () =>
      list('hr_attendance_accounts', (q) => q.select('employee_id').not('password_hash', 'is', null)),

    /* ── kept sign-ins, hr_ess_sessions (task A3) ── */

    getSessionByRefreshHash: (hash) => one('hr_ess_sessions', COLUMNS.session, 'refresh_hash', hash),
    /** A family's live row. hr_ess_sessions_live_family_key allows one, so this is at most one row. */
    getLiveSession: (familyId) =>
      read('hr_ess_sessions', (q) => q.select(COLUMNS.session).eq('family_id', familyId).is('revoked_at', null).maybeSingle()),
    listLiveSessions: (employeeId) =>
      list('hr_ess_sessions', (q) => q.select(COLUMNS.session).eq('employee_id', employeeId).is('revoked_at', null)),
    /** A family's id is its first row's, so this is when each sign-in began. */
    listSessionStarts: (familyIds) => list('hr_ess_sessions', (q) => q.select(COLUMNS.sessionStart).in('id', familyIds)),

    /**
     * false when this Scheduler sign-in has been kept before (hr_ess_sessions_sign_in_key): one
     * token is traded once. The database adds the portal password's fingerprint as the row goes in.
     */
    createSession: async (row) => (await write('hr_ess_sessions', (q) => q.insert(row), REFUSALS.SIGN_IN_KEPT)) !== REFUSED,

    /**
     * Is this portal session's password still the one it was kept with (hr_ess_session_password_current)?
     * true, false, or null for a row that is not a portal session or whose account is gone. The
     * hash and its fingerprint stay in the database.
     */
    isSessionPasswordCurrent: async (sessionId) => {
      const answer = await call(SESSION_FUNCTIONS.passwordCurrent, { p_session_id: sessionId });
      return typeof answer === 'boolean' ? answer : null;
    },

    /**
     * Retires a live row and adds the next one in its family, in one transaction
     * (hr_ess_session_rotate): null when the row was no longer live, because another refresh with
     * the same token got there first or the family has just ended.
     */
    rotateSession: async ({ sessionId, newId, refreshHash, at, expiresAt }) => {
      const rows = await call(SESSION_FUNCTIONS.rotate, {
        p_session_id: sessionId, p_new_id: newId, p_refresh_hash: refreshHash, p_now: at, p_expires_at: expiresAt,
      });
      const row = Array.isArray(rows) ? rows[0] : rows;
      return row && row.new_session_id
        ? { id: row.new_session_id, family_id: row.session_family_id, expires_at: row.new_expires_at }
        : null;
    },

    /**
     * Ends a family: its live row is revoked with the reason (hr_ess_session_revoke). With
     * `employeeId`, only a family of that employee. How many rows ended: 0 or 1.
     */
    revokeFamily: async ({ familyId, reason, at, employeeId = null }) => {
      const n = await call(SESSION_FUNCTIONS.revoke, { p_family_id: familyId, p_reason: reason, p_now: at, p_employee_id: employeeId });
      return Number(n) || 0;
    },

    /* ── Account & Security (issue #10): own password ── */

    /**
     * The attendance login's password. sessions_valid_from moves with it, which is exactly how
     * the Scheduler ends every punch session issued before a password change; password_set_at
     * marks that HR's first-time password has been replaced.
     */
    updateAttendancePassword: (employeeId, hash, at) => write('hr_attendance_accounts',
      (q) => q.update({ password_hash: hash, password_set_at: at, sessions_valid_from: at })
        .eq('employee_id', employeeId).select('id').single()),
    /** End every live ESS sign-in this employee holds, including the one making this request. */
    revokeAllSessionsForEmployee: (employeeId, at, reason = 'password_changed') => write('hr_ess_sessions',
      (q) => q.update({ revoked_at: at, revoked_reason: reason }).eq('employee_id', employeeId)
        .is('revoked_at', null).select('id')),

    /* ── B1: one of the caller's days ── */

    /** hr_staff_attendance is UNIQUE (employee_id, day) (20261015000004:27). */
    getDayRow: (employeeId, day) =>
      read('hr_staff_attendance', (q) => q.select(COLUMNS.day).eq('employee_id', employeeId).eq('day', day).maybeSingle()),
    /** HR's remark, UNIQUE (employee_id, day) (20261022000000:159). */
    getHrRemark: (employeeId, day) =>
      read('hr_attendance_remarks', (q) => q.select(COLUMNS.hrRemark).eq('employee_id', employeeId).eq('day', day).maybeSingle()),
    listMyRemarks: async (employeeId, day) =>
      (await read('hr_attendance_employee_remarks', (q) => q.select(COLUMNS.myRemark).eq('employee_id', employeeId).eq('day', day))) || [],

    /* ── B8: registered phones ── */

    /**
     * Registered phones, newest first, optionally only these employees' and only one status.
     * Reads one more than LIST_LIMITS.devices so the caller can say the list was cut.
     */
    listDevices: async ({ status = null, employeeIds = null } = {}) => {
      const limit = LIST_LIMITS.devices + 1;
      const withStatus = (q) => (status ? q.eq('status', status) : q);
      if (employeeIds) {
        const rows = await readIn('hr_attendance_devices', COLUMNS.device, 'employee_id', employeeIds,
          (q) => withStatus(q).order('bound_at', { ascending: false }).limit(limit));
        return rows.sort((a, b) => Date.parse(b.bound_at) - Date.parse(a.bound_at)).slice(0, limit);
      }
      return (await read('hr_attendance_devices', (q) => withStatus(q.select(COLUMNS.device))
        .order('bound_at', { ascending: false }).limit(limit))) || [];
    },

    /**
     * The one write to a Scheduler table (ADR-0018, decision 11): every ACTIVE phone of these
     * employees gets exactly the update the Scheduler's revokeDevice makes
     * (controllers/hr/attendanceAdminController.js:284-289): status 'revoked', revoked_at,
     * revoked_by, revoked_by_name and revoke_reason, only where the status is still 'active'.
     * A phone reset in the meantime is left alone, as there.
     *
     * One request per slice and no transaction around them, so a failure part-way leaves the
     * earlier slices reset. `onReset` hears of each slice's phones as soon as they are reset, so
     * the caller can record them whatever happens to the next slice.
     *
     * @returns the reset phones, { id, employee_id }
     */
    revokeActiveDevices: async (employeeIds, patch, onReset = () => {}) => {
      const unique = [...new Set(employeeIds.filter(Boolean))];
      const out = [];
      for (const part of chunks(unique)) {
        const reset = (await write('hr_attendance_devices', (q) => q
          .update({
            status: 'revoked',
            revoked_at: patch.revoked_at,
            revoked_by: patch.revoked_by,
            revoked_by_name: patch.revoked_by_name,
            revoke_reason: patch.revoke_reason,
          })
          .in('employee_id', part)
          .eq('status', 'active')
          .select(COLUMNS.revokedDevice))) || [];
        out.push(...reset);
        onReset(reset);
      }
      return out;
    },

    /* ── A8: requests to correct or delete my data ── */

    /** The new request, or null when the person already has five open (the database's own count). */
    createDataRequest: async (row) => {
      const created = await write('hr_ess_data_requests', (q) => q.insert([row]).select(COLUMNS.dataRequest).single(), REFUSALS.OPEN_LIMIT);
      return created === REFUSED ? null : created;
    },
    countOpenDataRequests: async (employeeId) =>
      ((await read('hr_ess_data_requests', (q) => q.select('id').eq('employee_id', employeeId).eq('status', 'open'))) || []).length,
    listMyDataRequests: async (employeeId) =>
      (await read('hr_ess_data_requests', (q) => q.select(COLUMNS.dataRequest).eq('employee_id', employeeId)
        .order('created_at', { ascending: false }).limit(LIST_LIMITS.myDataRequests))) || [],
    /** Newest first; one more than LIST_LIMITS.dataRequests, to tell a cut list. */
    listDataRequests: async ({ status = null } = {}) =>
      (await read('hr_ess_data_requests', (q) => {
        const base = q.select(COLUMNS.dataRequest);
        return (status ? base.eq('status', status) : base)
          .order('created_at', { ascending: false }).limit(LIST_LIMITS.dataRequests + 1);
      })) || [],
    getDataRequest: (id) => one('hr_ess_data_requests', COLUMNS.dataRequest, 'id', id),
    /**
     * Resolves a request only while it is still open, so two HR people answering at the same
     * moment cannot both resolve it: the second finds nothing to update and gets null.
     */
    resolveDataRequest: (id, patch) =>
      write('hr_ess_data_requests', (q) => q.update(patch).eq('id', id).eq('status', 'open')
        .select(COLUMNS.dataRequest).maybeSingle()),

    /* ── E9: personal details ── */

    getPersonalDetails: (employeeId) => one('hr_ess_personal_details', COLUMNS.personal, 'employee_id', employeeId),
    /** The dates of birth the celebration cards need, and nothing else from these rows (F6). */
    listPersonalDetailsFor: (employeeIds) => readIn('hr_ess_personal_details', 'employee_id, date_of_birth', 'employee_id', employeeIds),
    /**
     * One row per employee (its primary key). Only the columns in `row` are written: PostgREST's
     * upsert sets just those on a conflict, so a save cannot put back a field somebody else
     * changed since it read the row. Answers the whole row as it now stands, or null when the
     * row would be left with half an emergency contact by a save made in between.
     */
    savePersonalDetails: async (row) => {
      const saved = await write('hr_ess_personal_details', (q) => q.upsert([row], { onConflict: 'employee_id' }).select(COLUMNS.personal).single(),
        REFUSALS.EMERGENCY_HALF);
      return saved === REFUSED ? null : saved;
    },

    /* ── B14: mocked-location reports ── */

    createMockReport: (row) =>
      write('hr_ess_mock_location_reports', (q) => q.insert([row]).select(COLUMNS.mockReportCreated).single()),
    /**
     * Reports from `fromIso` (inclusive) to `toIso` (exclusive), newest first, optionally one
     * branch's; one more than LIST_LIMITS.mockReports, to tell a cut list.
     */
    listMockReports: async ({ fromIso, toIso, branchId = null }) =>
      (await read('hr_ess_mock_location_reports', (q) => {
        const base = q.select(COLUMNS.mockReport).gte('reported_at', fromIso).lt('reported_at', toIso);
        return (branchId ? base.eq('branch_id', branchId) : base)
          .order('reported_at', { ascending: false }).limit(LIST_LIMITS.mockReports + 1);
      })) || [],

    /* ── C6: the request limits HR can change ── */

    getRequestLimits: () => list('hr_ess_request_limits', (q) => q.select(COLUMNS.requestLimit).order('type')),
    /** One row per type (its primary key), so the update is at most one row; null for no such type. */
    setRequestLimit: (type, patch) =>
      write('hr_ess_request_limits', (q) => q.update(patch).eq('type', type).select(COLUMNS.requestLimit).maybeSingle()),

    /* ── WFH: HR's per-employee allowance (KP, 22 Oct) ── */

    /** One employee's allowance, or null when HR has not selected them. */
    getWfhAllowance: (employeeId) =>
      read('hr_ess_wfh_allowances', (q) => q.select(COLUMNS.wfhAllowance).eq('employee_id', employeeId).maybeSingle()),
    /**
     * The allowance list, newest change first, optionally only these employees' (the search's
     * matches). One more than `limit` is read, so the caller can say the list was cut.
     */
    listWfhAllowances: async ({ employeeIds = null, limit = LIST_LIMITS.wfhAllowances + 1 } = {}) => {
      const ordered = (q) => q.select(COLUMNS.wfhAllowance)
        .order('updated_at', { ascending: false }).limit(limit);
      if (employeeIds) {
        const rows = await readIn('hr_ess_wfh_allowances', COLUMNS.wfhAllowance, 'employee_id', employeeIds, ordered);
        return rows.sort((a, b) => Date.parse(b.updated_at) - Date.parse(a.updated_at)).slice(0, limit);
      }
      return (await read('hr_ess_wfh_allowances', ordered)) || [];
    },
    /** One row per employee (its primary key): only the columns sent are written on a conflict. */
    upsertWfhAllowance: (row) =>
      write('hr_ess_wfh_allowances', (q) => q.upsert([row], { onConflict: 'employee_id' })
        .select(COLUMNS.wfhAllowance).single()),
    /** The employee card the allowance list shows: branch and department ids, never contact data. */
    listWfhEmployees: (employeeIds) => readIn('hr_employees', COLUMNS.wfhEmployee, 'id', employeeIds),
    /**
     * How many WFH days this employee has in `month` (YYYY-MM) with one of `statuses`, optionally
     * leaving out one request. The allowance is the limit, so this is the only counter WFH needs.
     */
    countWfhDays: async ({ employeeId, month, statuses, excludeRequestId = null }) => {
      const { from, to } = monthBounds(`${month}-01`);
      const rows = await read('hr_ess_leave_requests', (q) => {
        const base = q.select('id').eq('employee_id', employeeId).eq('type', 'wfh')
          .in('status', statuses).gte('day', from).lte('day', to);
        return excludeRequestId ? base.neq('id', excludeRequestId) : base;
      });
      return (rows || []).length;
    },

    /* ── C1, C3: my attendance requests ── */

    createAttendanceRequest: (row) =>
      write('hr_ess_attendance_requests', (q) => q.insert([row]).select(COLUMNS.attendanceRequest).single()),
    getAttendanceRequest: (id) => one('hr_ess_attendance_requests', COLUMNS.attendanceRequest, 'id', id),
    listMyAttendanceRequests: async (employeeId) =>
      (await read('hr_ess_attendance_requests', (q) => q.select(COLUMNS.attendanceRequest)
        .eq('employee_id', employeeId).order('created_at', { ascending: false }).limit(LIST_LIMITS.myRequests))) || [],
    /**
     * The counters a form and the balances need: the caller's attendance requests whose day is
     * in from..to, as the four columns that decide them -- never the reasons or the days' detail.
     */
    listMyRequestFacts: async (family, employeeId, from, to) => {
      const table = family === 'leave' ? 'hr_ess_leave_requests' : 'hr_ess_attendance_requests';
      const columns = family === 'leave' ? COLUMNS.requestFacts : COLUMNS.attendanceRequestFacts;
      return (await read(table, (q) => q.select(columns).eq('employee_id', employeeId)
        .gte('day', from).lte('day', to))) || [];
    },
    /** Whether the same type+day already waits: the duplicate check before a request goes in. */
    countPendingRequests: async ({ family, employeeId, type, day }) => {
      const table = family === 'leave' ? 'hr_ess_leave_requests' : 'hr_ess_attendance_requests';
      const rows = await read(table, (q) => q.select('id').eq('employee_id', employeeId)
        .eq('type', type).eq('day', day).eq('status', 'pending'));
      return (rows || []).length;
    },

    /* ── C2, C4, C5: my leave requests and the days the sheet records ── */

    createLeaveRequest: (row) =>
      write('hr_ess_leave_requests', (q) => q.insert([row]).select(COLUMNS.leaveRequest).single()),
    getLeaveRequest: (id) => one('hr_ess_leave_requests', COLUMNS.leaveRequest, 'id', id),
    listMyLeaveRequests: async (employeeId) =>
      (await read('hr_ess_leave_requests', (q) => q.select(COLUMNS.leaveRequest)
        .eq('employee_id', employeeId).order('created_at', { ascending: false }).limit(LIST_LIMITS.myRequests))) || [],
    /** The CL and LWP days the sheet records for the month: the leave ledger the balance shows. */
    listMyLeaveDays: async (employeeId, from, to) =>
      (await read('hr_staff_attendance', (q) => q.select('day, leave_type').eq('employee_id', employeeId)
        .eq('status', 'leave').in('leave_type', ['cl', 'lwp']).gte('day', from).lte('day', to))) || [],

    /* ── D1, H6: the approvals Inbox ── */

    /**
     * One family's requests, oldest first. `employeeIds` limits it to those people (a manager's
     * reports); without it, everybody (an HR decider's view). `status` null means any.
     */
    listRequestsForApprover: async ({ family, employeeIds = null, status = 'pending' }) => {
      const table = family === 'leave' ? 'hr_ess_leave_requests' : 'hr_ess_attendance_requests';
      const columns = family === 'leave' ? COLUMNS.leaveRequest : COLUMNS.attendanceRequest;
      const limit = LIST_LIMITS.inbox + 1;
      const withStatus = (q) => (status ? q.eq('status', status) : q);
      if (employeeIds) {
        const rows = await readIn(table, columns, 'employee_id', employeeIds,
          (q) => withStatus(q).order('created_at', { ascending: true }).limit(limit));
        return rows.sort((a, b) => Date.parse(a.created_at) - Date.parse(b.created_at)).slice(0, limit);
      }
      return (await read(table, (q) => withStatus(q.select(columns)).order('created_at', { ascending: true }).limit(limit))) || [];
    },
    /** One employee's requests of every status whose day is in from..to, for the context counts. */
    listRequestCountsFor: async ({ family, employeeIds, from, to }) => {
      const table = family === 'leave' ? 'hr_ess_leave_requests' : 'hr_ess_attendance_requests';
      const columns = family === 'leave' ? COLUMNS.requestFacts : COLUMNS.attendanceRequestFacts;
      return readIn(table, columns, 'employee_id', employeeIds, (q) => q.gte('day', from).lte('day', to));
    },
    /** The day rows' late marks for the Inbox's context, for these days. */
    listDayLateMarks: async (days) => {
      const unique = [...new Set((days || []).filter(Boolean))];
      if (!unique.length) return [];
      return readIn('hr_staff_attendance', COLUMNS.dayLate, 'day', unique);
    },
    /** Who the sheet records on leave on these days. */
    listDaysOnLeave: async (days) => {
      const unique = [...new Set((days || []).filter(Boolean))];
      if (!unique.length) return [];
      return readIn('hr_staff_attendance', COLUMNS.dayLeave, 'day', unique, (q) => q.eq('status', 'leave'));
    },
    /** Leave requests, pending or approved, whose day is one of these: "who else is off". */
    listLeaveRequestsOnDays: async (days, statuses) => {
      const unique = [...new Set((days || []).filter(Boolean))];
      if (!unique.length) return [];
      return readIn('hr_ess_leave_requests', COLUMNS.leaveOnDay, 'day', unique, (q) => q.in('status', statuses));
    },

    /* ── the decisions, withdrawals and cancels (the SQL functions) ── */

    /** A database refusal (a racing second CL) answers as the function's own cl_limit outcome. */
    decideAttendanceRequest: async (args) => {
      const out = await call(REQUEST_FUNCTIONS.decideAttendance, args,
        { table: 'hr_ess_attendance_requests', refusal: REFUSALS.CL_TAKEN });
      return out === REFUSED ? { outcome: 'cl_limit' } : out;
    },
    decideLeaveRequest: async (args) => {
      const out = await call(REQUEST_FUNCTIONS.decideLeave, args,
        { table: 'hr_ess_leave_requests', refusal: REFUSALS.CL_TAKEN });
      return out === REFUSED ? { outcome: 'cl_limit' } : out;
    },
    withdrawAttendanceRequest: (args) =>
      call(REQUEST_FUNCTIONS.withdrawAttendance, args, { table: 'hr_ess_attendance_requests' }),
    withdrawLeaveRequest: (args) =>
      call(REQUEST_FUNCTIONS.withdrawLeave, args, { table: 'hr_ess_leave_requests' }),
    cancelAttendanceRequest: (args) =>
      call(REQUEST_FUNCTIONS.cancelAttendance, args, { table: 'hr_ess_attendance_requests' }),
    cancelLeaveRequest: (args) =>
      call(REQUEST_FUNCTIONS.cancelLeave, args, { table: 'hr_ess_leave_requests' }),
    /**
     * The on-duty morning job (one call a day, idempotent): every approved on_duty request for
     * `day` with no day row yet is written as present. Answers { applied, failed, employees }.
     */
    applyOnDutyDays: (day, at) =>
      call(REQUEST_FUNCTIONS.onDutyApply, { p_day: day, p_now: at }, { table: 'hr_ess_attendance_requests' }),
    /** Archiving twice is the same as once: the unique key answers the second one. */
    createArchive: async (row) => {
      const created = await write('hr_ess_request_archives', (q) => q.insert([row]), REFUSALS.ARCHIVE_KEPT);
      return created !== REFUSED;
    },
    listMyArchives: async (employeeId) =>
      (await read('hr_ess_request_archives', (q) => q.select(COLUMNS.archive).eq('employee_id', employeeId))) || [],

    /* ── D4: the approval chain's escalations ── */

    /**
     * One family's requests that went pending before `beforeIso`, oldest first: the ones the
     * escalation job judges and the leaders' overview counts. The facts carry the counter's
     * columns (minutes for attendance only) plus created_at, and nothing more.
     */
    listPendingRequestsSince: async (family, beforeIso, limit) => {
      const table = family === 'leave' ? 'hr_ess_leave_requests' : 'hr_ess_attendance_requests';
      const columns = family === 'leave'
        ? `${COLUMNS.requestFacts}, created_at`
        : `${COLUMNS.attendanceRequestFacts}, created_at`;
      return (await read(table, (q) => q.select(columns).eq('status', 'pending')
        .lt('created_at', beforeIso).order('created_at', { ascending: true }).limit(limit))) || [];
    },
    /** The escalations recorded for one request, oldest first. */
    listEscalationsFor: async (family, requestId) =>
      (await read('hr_ess_approval_escalations', (q) => q.select(COLUMNS.approvalEscalation)
        .eq('family', family).eq('request_id', requestId).order('escalated_at'))) || [],
    /** Escalating twice for the same person is the same as once: the unique key answers the second. */
    createEscalation: async (row) => {
      const created = await write('hr_ess_approval_escalations', (q) => q.insert([row]), REFUSALS.ESCALATION_KEPT);
      return created !== REFUSED;
    },

    /* ── the day's shift snapshot, and the month's recompute (policy/attendance.js) ── */

    getEmployeeShifts: (employeeId) => one('hr_employees', COLUMNS.employeeShifts, 'id', employeeId),
    getShift: (shiftId) => one('hr_shifts', COLUMNS.shift, 'id', shiftId),
    listHolidays: (from, to) => list('hr_holidays', (q) => q.select(COLUMNS.holiday).gte('day', from).lte('day', to)),
    getDaySnapshotState: (employeeId, day) =>
      read('hr_staff_attendance', (q) => q.select(COLUMNS.daySnapshot).eq('employee_id', employeeId).eq('day', day).maybeSingle()),
    /** The shift a day is judged by, copied on while it has none (attendanceRules.js ensureSnapshot). */
    setDaySnapshot: (id, snapshot) =>
      write('hr_staff_attendance', (q) => q.update(snapshot).eq('id', id).select('id').maybeSingle()),
    /**
     * Re-work late, early and the third-late half day for the month of `day`. Before the
     * Scheduler's shifts migration the function is missing and the rules are simply off
     * (attendanceRules.js:20-22): that is not a failure of the decision that called this.
     */
    recomputeAttendance: async ({ employeeIds, day, today, halfDayMinutes }) => {
      try {
        await run('writing', 'hr_attendance_recompute', () => db.rpc('hr_attendance_recompute', {
          p_employee_ids: employeeIds,
          p_day: day,
          p_today: today,
          p_half_day_minutes: halfDayMinutes,
        }));
      } catch (e) {
        if (!(e instanceof HttpError && e.code === 'MODULE_NOT_INSTALLED')) throw e;
      }
    },

    /* ── D5: push devices ── */

    /** The same token registers once: an upsert moves it to the caller and lifts any revocation. */
    registerPushDevice: async (row) => write('hr_ess_push_devices',
      (q) => q.upsert([row], { onConflict: 'token' }).select(COLUMNS.pushDevice).single()),
    /** Revokes one of the caller's own live phones; null when it is not theirs or already revoked. */
    revokePushDevice: (id, employeeId, at) => write('hr_ess_push_devices',
      (q) => q.update({ revoked_at: at, updated_at: at }).eq('id', id).eq('employee_id', employeeId)
        .is('revoked_at', null).select('id').maybeSingle()),
    /** The worker's own revoke, by row id, when FCM says the token belongs to no install. */
    revokePushDeviceRow: (id, at) => write('hr_ess_push_devices',
      (q) => q.update({ revoked_at: at, updated_at: at }).eq('id', id).select('id').maybeSingle()),
    listPushDevicesFor: async (employeeIds) =>
      readIn('hr_ess_push_devices', COLUMNS.pushTarget, 'employee_id', employeeIds, (q) => q.is('revoked_at', null)),

    /* ── D6, D8: notifications and their settings ── */

    createNotification: (row) => write('hr_ess_notifications', (q) => q.insert([row]).select('id, employee_id').single()),
    /** Newest first, one more than LIST_LIMITS.notifications so the caller can say it was cut. */
    listNotifications: async (employeeId) =>
      (await read('hr_ess_notifications', (q) => q.select(COLUMNS.notification).eq('employee_id', employeeId)
        .order('created_at', { ascending: false }).limit(LIST_LIMITS.notifications + 1))) || [],
    getNotification: (id, employeeId) =>
      read('hr_ess_notifications', (q) => q.select(COLUMNS.notification).eq('id', id).eq('employee_id', employeeId).maybeSingle()),
    countUnreadNotifications: async (employeeId) =>
      ((await read('hr_ess_notifications', (q) => q.select('id').eq('employee_id', employeeId).is('read_at', null))) || []).length,
    markNotificationRead: (id, employeeId, at) => write('hr_ess_notifications',
      (q) => q.update({ read_at: at }).eq('id', id).eq('employee_id', employeeId).select('id').maybeSingle()),
    markAllNotificationsRead: async (employeeId, at) =>
      ((await write('hr_ess_notifications', (q) => q.update({ read_at: at }).eq('employee_id', employeeId)
        .is('read_at', null).select('id'))) || []).length,
    getNotificationSettings: (employeeId) => one('hr_ess_notification_settings', COLUMNS.notificationSetting, 'employee_id', employeeId),
    saveNotificationSettings: (employeeId, row) => write('hr_ess_notification_settings',
      (q) => q.upsert([{ employee_id: employeeId, ...row }], { onConflict: 'employee_id' }).select(COLUMNS.notificationSetting).single()),
    /** The push worker's queue: not yet pushed, oldest first. */
    listUndeliveredNotifications: async (limit) =>
      (await read('hr_ess_notifications', (q) => q.select(COLUMNS.notificationWorker)
        .is('pushed_at', null).order('created_at', { ascending: true }).limit(limit))) || [],
    markNotificationPushed: (id, patch) => write('hr_ess_notifications',
      (q) => q.update(patch).eq('id', id).select('id').maybeSingle()),
    notificationSettingsFor: async (employeeIds) =>
      readIn('hr_ess_notification_settings', COLUMNS.notificationSetting, 'employee_id', employeeIds),
    /** The priority-task notifications this person already has, for the worker's dedupe. */
    listTaskNotifications: async (employeeId, sinceIso) =>
      (await read('hr_ess_notifications', (q) => q.select(COLUMNS.taskNotification).eq('employee_id', employeeId)
        .eq('category', 'priority_tasks').gte('created_at', sinceIso))) || [],

    /** The notifications these people already have, for a dedupe the Wall's job can read. */
    listNotificationsWithData: async (employeeIds, category, key, value) => {
      const rows = await readIn('hr_ess_notifications', 'id, employee_id, category, data', 'employee_id', employeeIds,
        (q) => q.eq('category', category));
      return rows.filter((n) => n.data && String(n.data[key] ?? '') === String(value));
    },

    /* ── D2: the Scheduler's priority tasks, read for push only ── */

    /** Tasks assigned to one person, created since the window opens. Broadcast tasks have no assignee. */
    listNewPriorityTasks: async ({ sinceIso, limit }) =>
      (await read('priority_tasks', (q) => q.select(COLUMNS.task).not('assigned_to', 'is', null)
        .gte('created_at', sinceIso).order('created_at', { ascending: true }).limit(limit))) || [],
    listEmployeesByUserIds: async (userIds) => readIn('hr_employees', COLUMNS.employeeForUser, 'user_id', userIds),
    listHrUserIds: () => list('users', (q) => q.select('id').eq('role', 'hr')),

    /* ── E1, E2, E12: the profile, the org and the timeline ── */

    getProfile: (employeeId) => one('hr_employees', COLUMNS.profile, 'id', employeeId),
    /** Everybody not archived, with the directory's columns: the org views and search work from here. */
    listActiveEmployees: async () =>
      (await read('hr_employees', (q) => q.select(COLUMNS.directoryPerson).eq('is_archived', false))) || [],
    listAllDepartments: async () => (await read('hr_departments', (q) => q.select('id, name, is_active'))) || [],
    /** The person's own HR events, newest first; values and notes are never selected. */
    listTimeline: async (employeeId, limit = 50) =>
      (await read('hr_activity_events', (q) => q.select(COLUMNS.timeline).eq('entity_type', 'employee')
        .eq('entity_id', employeeId).order('occurred_at', { ascending: false }).limit(limit))) || [],
    /** The portal roles behind these user ids: the "Reports to the CEO (not recorded)" test. */
    listUserRolesFor: async (userIds) => readIn('users', COLUMNS.userRole, 'id', userIds),

    /* ── E10: photos through the Scheduler's private bucket, as its own code uses it ── */

    /** A 300-second signed link, exactly as the Scheduler signs its HR files; null on any failure. */
    signedPhotoUrl: async (path, expiresIn = 300) => {
      if (!path) return null;
      try {
        const { data } = await db.storage.from(PHOTO_BUCKET).createSignedUrl(path, expiresIn);
        return (data && data.signedUrl) || null;
      } catch {
        return null;
      }
    },
    /** Upload bytes under `path`; a storage failure is an outage, never a 500 with a stack. */
    uploadProfilePhoto: async (path, buffer, contentType) => {
      const { error } = await db.storage.from(PHOTO_BUCKET).upload(path, buffer, { contentType, upsert: false });
      if (error) throw new HttpError(503, 'UNAVAILABLE', MESSAGES.UNAVAILABLE);
    },
    /** Best effort: an orphaned file is a cleanup job, not a failed request. */
    removeStorageObjects: async (paths) => {
      try {
        await db.storage.from(PHOTO_BUCKET).remove(paths);
      } catch { /* logged nowhere: nothing reads the object once the row points elsewhere */ }
    },
    /**
     * The employee's photo pointer on their HR record — the one write to hr_employees the ESS
     * makes, and only to the photo columns (the Scheduler's own setPhoto writes the same ones).
     */
    setEmployeePhoto: (employeeId, patch) =>
      write('hr_employees', (q) => q.update(patch).eq('id', employeeId).select('id, photo_path').maybeSingle()),

    /* ── E6: the team's day, and the week's leave ── */

    listTeamDayRows: async (employeeIds, day) =>
      readIn('hr_staff_attendance', COLUMNS.teamDay, 'employee_id', employeeIds, (q) => q.eq('day', day)),
    /** The days the sheet records leave for these people in from..to (never the leave type). */
    listLeaveDaysBetween: async (employeeIds, from, to) =>
      readIn('hr_staff_attendance', 'employee_id, day', 'employee_id', employeeIds,
        (q) => q.eq('status', 'leave').gte('day', from).lte('day', to)),

    /* ── F1-F6: the Wall's feed ── */

    /**
     * One feed page, newest first: the organisation's wall plus the caller's own branch's, or one
     * branch alone. `before` pages back (`created_at` older than the last row of the page).
     */
    listFeedPosts: async ({ branchId, scope = null, before = null, limit }) => {
      const one = (extra) => read('hr_ess_wall_posts', (q) => {
        const base = q.select(COLUMNS.wallPost).is('deleted_at', null);
        return extra(base)
          .order('created_at', { ascending: false }).limit(limit + 1);
      });
      const late = before ? (q) => q.lt('created_at', before) : (q) => q;
      if (scope === 'branch') return (await one((q) => late(q).eq('scope', 'branch').eq('branch_id', branchId))) || [];
      if (scope === 'org') return (await one((q) => late(q).eq('scope', 'org'))) || [];
      // No branch on the HR record: only the organisation's wall can be read.
      if (!branchId) return (await one((q) => late(q).eq('scope', 'org'))) || [];
      // The two walls as one feed: the branch's own and the organisation's, merged by time.
      const [mine, everyone] = await Promise.all([
        one((q) => late(q).eq('scope', 'branch').eq('branch_id', branchId)),
        one((q) => late(q).eq('scope', 'org')),
      ]);
      return [...(mine || []), ...(everyone || [])]
        .sort((a, b) => Date.parse(b.created_at) - Date.parse(a.created_at))
        .slice(0, limit + 1);
    },
    getWallPost: (id) => read('hr_ess_wall_posts', (q) => q.select(COLUMNS.wallPost).eq('id', id).maybeSingle()),
    /** The author and the two clocks, for the edit window and the delete check (F1). */
    getWallPostOwn: (id) => read('hr_ess_wall_posts', (q) => q.select(COLUMNS.wallPostOwn).eq('id', id).maybeSingle()),
    createWallPost: (row) => write('hr_ess_wall_posts', (q) => q.insert([row]).select(COLUMNS.wallPost).single()),
    /** An edit writes the body (or the poll additions) and the edited stamp; null when it was deleted meanwhile. */
    updateWallPost: (id, patch) =>
      write('hr_ess_wall_posts', (q) => q.update(patch).eq('id', id).is('deleted_at', null).select(COLUMNS.wallPost).maybeSingle()),
    /** The first edit stamp wins, so `edited_at` means "has been edited", whoever wrote it (F1). */
    markWallPostEdited: (id, at) =>
      write('hr_ess_wall_posts', (q) => q.update({ edited_at: at, updated_at: at }).eq('id', id).is('edited_at', null).select('id').maybeSingle()),
    /** HR's hide, or an undo: one update, and null when the row is gone (F7). */
    moderateWallPost: (id, patch) =>
      write('hr_ess_wall_posts', (q) => q.update(patch).eq('id', id).select(COLUMNS.wallPost).maybeSingle()),
    /** The author's own delete: the body and the counters are cleared as the stamp goes on (F1). */
    deleteWallPost: (id, at) => write('hr_ess_wall_posts', (q) => q.update({
      deleted_at: at,
      updated_at: at,
      body: '(deleted)',
      attachments: [],
      mentions: [],
      reaction_counts: {},
      comment_count: 0,
    }).eq('id', id).is('deleted_at', null).select('id').maybeSingle()),

    /* ── F4: a poll's options, its votes, and the counters ── */

    createPollOptions: (rows) => write('hr_ess_wall_poll_options', (q) => q.insert(rows).select(COLUMNS.wallOption)),
    listPollOptions: (postId) =>
      list('hr_ess_wall_poll_options', (q) => q.select(COLUMNS.wallOption).eq('post_id', postId).order('position')),
    getPollOption: (id) => read('hr_ess_wall_poll_options', (q) => q.select(COLUMNS.wallOption).eq('id', id).maybeSingle()),
    listPollVotes: (postId) => list('hr_ess_wall_poll_votes', (q) => q.select(COLUMNS.wallVote).eq('post_id', postId)),
    /** One person's own votes on one poll: single-choice is zero or one, multiple is any. */
    listMyPollVotes: (postId, employeeId) =>
      list('hr_ess_wall_poll_votes', (q) => q.select(COLUMNS.wallVote).eq('post_id', postId).eq('voter_employee_id', employeeId)),
    /** Recording a vote that is already there is not an error: a second tap on the same option. */
    createPollVote: async (row) => {
      const made = await write('hr_ess_wall_poll_votes', (q) => q.insert([row]), REFUSALS.ALREADY_VOTED);
      return made !== REFUSED;
    },
    /** A single-choice vote is changed by deleting the old row and adding the new one. */
    deletePollVote: (postId, employeeId) =>
      write('hr_ess_wall_poll_votes', (q) => q.delete().eq('post_id', postId).eq('voter_employee_id', employeeId).select('id')),
    /** F4: the option set is frozen from the first vote on; this stamps it, once. */
    lockPollOptions: (postId, at) =>
      write('hr_ess_wall_posts', (q) => q.update({ options_locked_at: at, updated_at: at })
        .eq('id', postId).is('options_locked_at', null).select('id').maybeSingle()),
    /** The poll that closes tonight, for the job (F4). */
    listPollsClosingOn: (day) => list('hr_ess_wall_posts', (q) => q.select(COLUMNS.wallPost)
      .eq('kind', 'poll').eq('poll_closes_on', day).is('deleted_at', null).is('hidden_at', null)),
    /** Who voted: null for an anonymous poll, which is never read out (F4). */
    listPollVoters: (postId) => list('hr_ess_wall_poll_votes', (q) => q.select(COLUMNS.wallVote).eq('post_id', postId)),

    /* ── F1, F2: comments and their threads ── */

    createWallComment: (row) => write('hr_ess_wall_comments', (q) => q.insert([row]).select(COLUMNS.wallComment).single()),
    getWallComment: (id) => read('hr_ess_wall_comments', (q) => q.select(COLUMNS.wallComment).eq('id', id).maybeSingle()),
    getWallCommentOwn: (id) => read('hr_ess_wall_comments', (q) => q.select(COLUMNS.wallCommentOwn).eq('id', id).maybeSingle()),
    updateWallComment: (id, patch) =>
      write('hr_ess_wall_comments', (q) => q.update(patch).eq('id', id).is('deleted_at', null).select(COLUMNS.wallComment).maybeSingle()),
    markWallCommentEdited: (id, at) =>
      write('hr_ess_wall_comments', (q) => q.update({ edited_at: at, updated_at: at }).eq('id', id).is('edited_at', null).select('id').maybeSingle()),
    moderateWallComment: (id, patch) =>
      write('hr_ess_wall_comments', (q) => q.update(patch).eq('id', id).select(COLUMNS.wallComment).maybeSingle()),
    deleteWallComment: (id, at) => write('hr_ess_wall_comments', (q) => q.update({
      deleted_at: at,
      updated_at: at,
      body: '(deleted)',
      mentions: [],
      reaction_counts: {},
      reply_count: 0,
    }).eq('id', id).is('deleted_at', null).select('id').maybeSingle()),
    /** One post's top-level comments and their replies, oldest first (one level, F2). */
    listThreadComments: async (postId, limit) =>
      (await read('hr_ess_wall_comments', (q) => q.select(COLUMNS.wallComment).eq('post_id', postId)
        .order('created_at').limit(limit + 1))) || [],
    countWallComments: async (postId) => {
      const rows = await read('hr_ess_wall_comments', (q) => q.select('id').eq('post_id', postId).is('deleted_at', null).is('hidden_at', null));
      return (rows || []).length;
    },
    /** One person's own comment count on a post, for the "already said something" test. */
    countMyComments: async (postId, employeeId) => {
      const rows = await read('hr_ess_wall_comments', (q) => q.select('id').eq('post_id', postId).eq('employee_id', employeeId));
      return (rows || []).length;
    },
    /** A counter patch on a post or a comment (reactions, comment and reply counts, body). */
    saveWallPostCounter: (id, patch) =>
      write('hr_ess_wall_posts', (q) => q.update(patch).eq('id', id).select('id').maybeSingle()),
    saveWallCommentCounter: (id, patch) =>
      write('hr_ess_wall_comments', (q) => q.update(patch).eq('id', id).select('id').maybeSingle()),

    /* ── F2: reactions ── */

    /** One person's own reaction on a post or a comment, whatever it was (one per person). */
    getMyPostReaction: (postId, employeeId) => read('hr_ess_wall_reactions', (q) => q.select(COLUMNS.wallReaction)
      .eq('post_id', postId).eq('employee_id', employeeId).maybeSingle()),
    getMyCommentReaction: (commentId, employeeId) => read('hr_ess_wall_reactions', (q) => q.select(COLUMNS.wallReaction)
      .eq('comment_id', commentId).eq('employee_id', employeeId).maybeSingle()),
    /** A second reaction by the same person is simply their first, so the route updates it. */
    createPostReaction: async (row) => {
      const made = await write('hr_ess_wall_reactions', (q) => q.insert([row]), REFUSALS.ALREADY_REACTED);
      return made !== REFUSED;
    },
    createCommentReaction: async (row) => {
      const made = await write('hr_ess_wall_reactions', (q) => q.insert([row]), REFUSALS.ALREADY_REACTED_COMMENT);
      return made !== REFUSED;
    },
    updatePostReaction: (id, reaction) =>
      write('hr_ess_wall_reactions', (q) => q.update({ reaction }).eq('id', id).select(COLUMNS.wallReaction).maybeSingle()),
    updateCommentReaction: (id, reaction) =>
      write('hr_ess_wall_reactions', (q) => q.update({ reaction }).eq('id', id).select(COLUMNS.wallReaction).maybeSingle()),
    removePostReaction: (id) =>
      write('hr_ess_wall_reactions', (q) => q.delete().eq('id', id).select('id').maybeSingle()),
    removeCommentReaction: (id) =>
      write('hr_ess_wall_reactions', (q) => q.delete().eq('id', id).select('id').maybeSingle()),
    /** "Who reacted": the people behind one post's or comment's reactions, newest first (F2). */
    listReactionsForPost: (postId) => list('hr_ess_wall_reactions', (q) => q.select(COLUMNS.wallReaction)
      .eq('post_id', postId).order('created_at', { ascending: false })),
    listReactionsForComment: (commentId) => list('hr_ess_wall_reactions', (q) => q.select(COLUMNS.wallReaction)
      .eq('comment_id', commentId).order('created_at', { ascending: false })),

    /* ── F1, F2: @mentions ── */

    /** The mention rows a post or a comment carries, written as the row goes in. */
    createWallMentions: (rows) => write('hr_ess_wall_mentions', (q) => q.insert(rows).select(COLUMNS.wallMention)),

    /* ── F6: praise and the wish book ── */

    /** A person's praise, newest first: what the profile's "Praise" strip shows (F3). */
    listPraiseFor: (employeeId, limit) => list('hr_ess_wall_posts', (q) => q.select(COLUMNS.wallPost)
      .eq('kind', 'praise').eq('about_employee_id', employeeId).is('deleted_at', null).is('hidden_at', null)
      .order('created_at', { ascending: false }).limit(limit)),
    createWallWish: async (row) => {
      const made = await write('hr_ess_wall_wishes', (q) => q.insert([row]).select('id, post_id'), REFUSALS.ALREADY_WISHED);
      return made === REFUSED ? null : made;
    },
    /** Who has been wished what this year, for the celebration cards (F6). */
    listWishesFor: (employeeIds, year) => readIn('hr_ess_wall_wishes', COLUMNS.wallWish, 'about_id', employeeIds,
      (q) => q.eq('year', year)),

    /* ── F7: reports and the moderation log ── */

    /** One report per person per thing: a second tap answers 409, never a second row. */
    createWallReport: async (row, onComment) => {
      const made = await write('hr_ess_wall_reports', (q) => q.insert([row]),
        onComment ? REFUSALS.ALREADY_REPORTED_COMMENT : REFUSALS.ALREADY_REPORTED);
      return made !== REFUSED;
    },
    /** HR's queue: open first, newest first; one more than the limit, so a cut list is known. */
    listWallReports: async ({ status = null, limit }) =>
      (await read('hr_ess_wall_reports', (q) => {
        const base = q.select(COLUMNS.wallReport);
        return (status ? base.eq('status', status) : base)
          .order('created_at', { ascending: false }).limit(limit + 1);
      })) || [],
    getWallReport: (id) => read('hr_ess_wall_reports', (q) => q.select(COLUMNS.wallReport).eq('id', id).maybeSingle()),
    /** Answering a report only while it is still open, so two HR people cannot both answer it. */
    resolveWallReport: (id, patch) =>
      write('hr_ess_wall_reports', (q) => q.update(patch).eq('id', id).eq('status', 'open').select(COLUMNS.wallReport).maybeSingle()),
    /** The moderation trail's own rows, from hr_ess_audit (F7). */
    listModerationLog: (actions, limit) => list('hr_ess_audit', (q) => q.select('id, at, actor_name, action, target_employee_id, details')
      .in('action', actions).order('at', { ascending: false }).limit(limit)),

    /* ── F5: announcements ── */

    createAnnouncement: (row) => write('hr_ess_announcements', (q) => q.insert([row]).select(COLUMNS.announcement).single()),
    getAnnouncement: (id) => read('hr_ess_announcements', (q) => q.select(COLUMNS.announcement).eq('id', id).maybeSingle()),
    updateAnnouncement: (id, patch) => write('hr_ess_announcements', (q) => q.update(patch).eq('id', id).select(COLUMNS.announcement).maybeSingle()),
    /** A draft is visible to its sender alone until its publish_at; scheduled ones are the job's. */
    listMyAnnouncements: async (employeeId, limit) =>
      (await read('hr_ess_announcements', (q) => q.select(COLUMNS.announcement).eq('employee_id', employeeId)
        .order('created_at', { ascending: false }).limit(limit + 1))) || [],
    /** The announcements the job must publish: scheduled times that have arrived (F5). */
    listDueAnnouncements: (atIso, limit) => list('hr_ess_announcements', (q) => q.select(COLUMNS.announcement)
      .is('published_at', null).is('deleted_at', null).not('publish_at', 'is', null).lte('publish_at', atIso)
      .order('publish_at', { ascending: true }).limit(limit)),
    /** The ones needing an acknowledgement whose close is near, for the reminder (F5). */
    listAckAnnouncementsClosingOn: (day) => list('hr_ess_announcements', (q) => q.select(COLUMNS.announcement)
      .eq('needs_ack', true).eq('closes_on', day).is('deleted_at', null).not('published_at', 'is', null)),
    /** An announcement as a reader of the Wall sees it: those published to them, newest first. */
    listAnnouncementsFor: async (audienceRows, limit) => {
      const ids = [...new Set((audienceRows || []).map((r) => r.announcement_id).filter(Boolean))];
      if (!ids.length) return [];
      const found = await readIn('hr_ess_announcements', COLUMNS.announcement, 'id', ids);
      // A reader is never shown a draft or a deleted one, whatever their audience row says.
      return found.filter((a) => a.published_at != null && a.deleted_at == null)
        .sort((a, b) => Date.parse(b.published_at) - Date.parse(a.published_at))
        .slice(0, limit + 1);
    },
    /** The audience rows for these people, newest first: what each was sent (F5). */
    listMyAudienceRows: async (employeeId, limit) =>
      (await read('hr_ess_announcement_audience', (q) => q.select('announcement_id, employee_id, added_at')
        .eq('employee_id', employeeId).order('added_at', { ascending: false }).limit(limit + 1))) || [],
    /** Everybody an audience may name, with the account link a role filter needs. */
    listAudienceEmployees: async () =>
      (await read('hr_employees', (q) => q.select(COLUMNS.audienceEmployee).eq('is_archived', false))) || [],
    /** The count of pinned announcements, against MAX_PINNED (F5). */
    countPinnedAnnouncements: async () => {
      const rows = await read('hr_ess_announcements', (q) => q.select('id').eq('pinned', true).is('deleted_at', null));
      return (rows || []).length;
    },
    /** An announcement's counts, the sender's own reading (F5). */
    listAudienceRows: (announcementId) => list('hr_ess_announcement_audience', (q) => q.select('id, announcement_id, employee_id, added_at')
      .eq('announcement_id', announcementId)),
    /** A draft publishes once: the update answers null when it was already published. */
    publishAnnouncement: (id, at) => write('hr_ess_announcements', (q) => q.update({ published_at: at, updated_at: at })
      .eq('id', id).is('published_at', null).select(COLUMNS.announcement).maybeSingle()),
    /** One audience row per person; a second save moves on without a row. */
    addAudienceRows: async (rows) => {
      const made = await write('hr_ess_announcement_audience', (q) => q.insert(rows), REFUSALS.AUDIENCE_KEPT);
      return made !== REFUSED;
    },
    markAnnouncementReminded: (id, at) => write('hr_ess_announcements', (q) => q.update({ reminded_at: at })
      .eq('id', id).select('id').maybeSingle()),
    /** One read row per person per announcement: the first open wins. */
    getAnnouncementRead: (announcementId, employeeId) => read('hr_ess_announcement_reads',
      (q) => q.select('id, announcement_id, employee_id, read_at, ack_at').eq('announcement_id', announcementId).eq('employee_id', employeeId).maybeSingle()),
    listAnnouncementReads: (announcementId) => list('hr_ess_announcement_reads', (q) => q.select('id, announcement_id, employee_id, read_at, ack_at')
      .eq('announcement_id', announcementId)),
    createAnnouncementRead: (row) => write('hr_ess_announcement_reads', (q) => q.insert([row]).select('id, announcement_id, employee_id, read_at, ack_at')),
    /** The acknowledgement button: only while it is still open (the route checks the day). */
    ackAnnouncement: (announcementId, employeeId, at) => write('hr_ess_announcement_reads',
      (q) => q.update({ ack_at: at }).eq('announcement_id', announcementId).eq('employee_id', employeeId)
        .is('ack_at', null).select('id, announcement_id, employee_id, read_at, ack_at').maybeSingle()),

    /* ── F6: the celebration opt-out ── */

    getCelebrationOptout: (employeeId) => read('hr_ess_celebration_optouts', (q) => q.select('employee_id, hidden, updated_at').eq('employee_id', employeeId).maybeSingle()),
    setCelebrationOptout: (employeeId, hidden, at) => write('hr_ess_celebration_optouts',
      (q) => q.upsert([{ employee_id: employeeId, hidden, updated_at: at }], { onConflict: 'employee_id' })
        .select('employee_id, hidden, updated_at').single()),
    /** Everybody who has asked to be left off the cards. */
    listCelebrationOptouts: () => list('hr_ess_celebration_optouts', (q) => q.select('employee_id, hidden, updated_at')),

    /* ── F1, F3, F5: the ESS's own bucket (KP, 19 Oct) ── */

    /** A 300-second signed link into the ESS bucket; null on any failure, as the photo link is. */
    signedEssUrl: async (path, expiresIn = 300) => {
      if (!path) return null;
      try {
        const { data } = await db.storage.from(ESS_BUCKET).createSignedUrl(path, expiresIn);
        return (data && data.signedUrl) || null;
      } catch {
        return null;
      }
    },
    /** Upload bytes under `path`; a storage failure is an outage, never a 500 with a stack. */
    uploadEssObject: async (path, buffer, contentType) => {
      const { error } = await db.storage.from(ESS_BUCKET).upload(path, buffer, { contentType, upsert: false });
      if (error) throw new HttpError(503, 'UNAVAILABLE', MESSAGES.UNAVAILABLE);
    },
    /** Best effort: an orphaned file is a cleanup job, not a failed request. */
    removeEssObjects: async (paths) => {
      try {
        await db.storage.from(ESS_BUCKET).remove(paths);
      } catch { /* nothing reads the object once no row points at it */ }
    },

    /* ── Phase 2B: the Helpdesk (docs/06, G1 to G5) ── */

    /** The category list the raise form and the queue read; seeds live in the migration. */
    listHelpdeskCategories: () =>
      list('hr_ess_helpdesk_categories', (q) => q.select(COLUMNS.helpdeskCategory).order('id')),
    getHelpdeskCategoryBySlug: (slug) =>
      read('hr_ess_helpdesk_categories', (q) => q.select(COLUMNS.helpdeskCategory).eq('slug', slug).maybeSingle()),
    getHelpdeskCategoryById: (id) =>
      read('hr_ess_helpdesk_categories', (q) => q.select(COLUMNS.helpdeskCategory).eq('id', id).maybeSingle()),

    /** The raise: the ref comes from the column default, not from here. */
    createHelpdeskTicket: (row) =>
      write('hr_ess_helpdesk_tickets', (q) => q.insert([row]).select(COLUMNS.helpdeskTicket).single()),
    getHelpdeskTicket: (id) =>
      read('hr_ess_helpdesk_tickets', (q) => q.select(COLUMNS.helpdeskTicket).eq('id', id).maybeSingle()),
    /** What a transition needs to know about the row it is about to move. */
    getHelpdeskTicketOwn: (id) =>
      read('hr_ess_helpdesk_tickets', (q) => q.select(COLUMNS.helpdeskTicketOwn).eq('id', id).maybeSingle()),
    /** A raiser's own list, newest first, optionally held to one status. */
    listMyHelpdeskTickets: (employeeId, statuses, limit) =>
      list('hr_ess_helpdesk_tickets', (q) => {
        const base = q.select(COLUMNS.helpdeskTicket).eq('created_by', employeeId);
        const filtered = statuses ? base.in('status', statuses) : base;
        return filtered.order('created_at', { ascending: false }).limit(limit + 1);
      }),
    /** A queue page: the team's categories and statuses, newest first. Callers pass the
     * category ids their roles serve, so the store stays policy-free. */
    listHelpdeskQueue: (categoryIds, statuses, limit) =>
      list('hr_ess_helpdesk_tickets', (q) => {
        const base = q.select(COLUMNS.helpdeskTicket).in('category_id', categoryIds).in('status', statuses);
        return base.order('created_at', { ascending: false }).limit(limit + 1);
      }),
    /** One patch, one row: claim, status moves, close, reopen and the job's escalation stamp. */
    updateHelpdeskTicket: (id, patch) =>
      write('hr_ess_helpdesk_tickets', (q) => q.update(patch).eq('id', id).select(COLUMNS.helpdeskTicket).maybeSingle()),

    /** A ticket's thread, oldest first, one page with a has-more marker. */
    listHelpdeskMessages: (ticketId, limit) =>
      list('hr_ess_helpdesk_messages', (q) => q.select(COLUMNS.helpdeskMessage)
        .eq('ticket_id', ticketId).order('created_at').limit(limit + 1)),
    /** Comment, withdraw, reopen, close and status all leave a message row; nothing deletes one. */
    createHelpdeskMessage: (row) =>
      write('hr_ess_helpdesk_messages', (q) => q.insert([row]).select(COLUMNS.helpdeskMessage).single()),

    /** The job's read: every open or in-progress ticket, for the overdue checks. */
    listActiveHelpdeskTickets: (statuses, limit) =>
      list('hr_ess_helpdesk_tickets', (q) => q.select(COLUMNS.helpdeskTicketOwn)
        .in('status', statuses).order('created_at').limit(limit)),

    /** Employee ids whose login holds one of `roles`, for the queue-role notifications. */
    listEmployeeIdsForRoles: async (roles) => {
      const users = await readIn('users', COLUMNS.userRole, 'role', roles);
      if (!users.length) return [];
      const links = await readIn('hr_employees', COLUMNS.employeeForUser, 'user_id',
        users.map((u) => u.id));
      return links.map((l) => l.id);
    },

    /* ── G6 (2D): the Admin Manager's infra register mirror ── */

    /**
     * One summary row in the Scheduler's infra_tickets (KP, 22 Oct; sanctioned write). The register
     * has no thread and no in-progress state: the helpdesk stays the record.
     */
    createInfraTicket: (row) =>
      write('infra_tickets', (q) => q.insert([row]).select(COLUMNS.infraTicket).single()),
    getInfraTicket: (id) => read('infra_tickets', (q) => q.select(COLUMNS.infraTicket).eq('id', id).maybeSingle()),
    listInfraTicketsByIds: (ids) => readIn('infra_tickets', COLUMNS.infraTicket, 'id', ids),
    /** The only update: closing the register row (the Scheduler's closeInfraTicket does the same). */
    closeInfraTicket: (id, closedOn) =>
      write('infra_tickets', (q) => q.update({ status: 'closed', closed_on: closedOn }).eq('id', id)
        .select(COLUMNS.infraTicket).maybeSingle()),

    /** The ESS side of the link; one row per helpdesk ticket (unique). */
    createInfraLink: (row) =>
      write('hr_ess_infra_links', (q) => q.insert([row]).select(COLUMNS.infraLink).single()),
    updateInfraLink: (id, patch) =>
      write('hr_ess_infra_links', (q) => q.update(patch).eq('id', id).select(COLUMNS.infraLink).maybeSingle()),
    getInfraLinkForTicket: (ticketId) =>
      read('hr_ess_infra_links', (q) => q.select(COLUMNS.infraLink).eq('ticket_id', ticketId).maybeSingle()),
    /** The job's retry list: links whose mirror could not be made at raise. */
    listSkippedInfraLinks: (limit) =>
      list('hr_ess_infra_links', (q) => q.select(COLUMNS.infraLink).eq('state', 'skipped')
        .order('created_at').limit(limit)),
    /** The job's close-sync read: every linked ticket, oldest first. */
    listLinkedInfraLinks: (limit) =>
      list('hr_ess_infra_links', (q) => q.select(COLUMNS.infraLink).eq('state', 'linked')
        .order('created_at').limit(limit)),

    /* ── the audit trail ── */

    /** Append-only: nothing in the ESS updates or deletes a row of hr_ess_audit. */
    writeAudit: async (row) => {
      await write('hr_ess_audit', (q) => q.insert([row]));
    },

    /* ── Phase 2C: Helpdesk assignment history ── */

    /** One row per assignment, so a reassign does not overwrite who had it first (KP 5). */
    createHelpdeskAssignment: (row) =>
      write('hr_ess_helpdesk_assignments', (q) => q.insert([row]).select(COLUMNS.helpdeskAssignment).single()),
    listHelpdeskAssignments: (ticketId) =>
      list('hr_ess_helpdesk_assignments', (q) => q.select(COLUMNS.helpdeskAssignment)
        .eq('ticket_id', ticketId).order('created_at').limit(LIST_LIMITS.helpdeskAssignments + 1)),
    /** What an assignment needs to know about the person it points at: the login link, to read
     * the role the queue check needs (routes/helpdeskTickets.js), and nothing else. */
    getEmployeeLink: (employeeId) => one('hr_employees', COLUMNS.employeeLink, 'id', employeeId),
    /** What the ID card shows, and whether its holder is still on the record. */
    getIdCardEmployee: (employeeId) => one('hr_employees', COLUMNS.idCardEmployee, 'id', employeeId),

    /* ── Phase 2C: My Documents ── */

    /** The type list the raise form and every list screen read; seeds live in the migration. */
    listDocumentTypes: () => list('hr_ess_document_types', (q) => q.select(COLUMNS.documentType).order('sort')),
    getDocument: (id) => read('hr_ess_documents', (q) => q.select(COLUMNS.document).eq('id', id).maybeSingle()),
    /** A person's own list, newest first; one more than LIST_LIMITS.documents, to tell a cut list. */
    listMyDocuments: (employeeId) =>
      list('hr_ess_documents', (q) => q.select(COLUMNS.document).eq('employee_id', employeeId)
        .order('created_at', { ascending: false }).limit(LIST_LIMITS.documents + 1)),
    /** HR's read of one person's record, newest first, one more than the limit. */
    listDocumentsFor: (employeeId) =>
      list('hr_ess_documents', (q) => q.select(COLUMNS.document).eq('employee_id', employeeId)
        .order('created_at', { ascending: false }).limit(LIST_LIMITS.hrDocuments + 1)),
    /** The one-file-per-upload cap: the count of rows on one person's record. */
    countDocuments: async (employeeId) => {
      const rows = await read('hr_ess_documents', (q) => q.select('id').eq('employee_id', employeeId));
      return (rows || []).length;
    },
    /** The ref comes from the column defaults, the status from the database's own CHECK. */
    createDocument: (row) =>
      write('hr_ess_documents', (q) => q.insert([row]).select(COLUMNS.document).single()),
    /** HR's verify or reject: one patch, one row. */
    updateDocument: (id, patch) =>
      write('hr_ess_documents', (q) => q.update(patch).eq('id', id).select(COLUMNS.document).maybeSingle()),
    /** The row and its bucket path in one read, so the delete can remove the file too. */
    deleteDocument: (id) =>
      write('hr_ess_documents', (q) => q.delete().eq('id', id).select('id, storage_path').maybeSingle()),
    /** The weekly reminder's read: which person holds which type, and nothing more. */
    listDocumentEmployeeTypes: () => list('hr_ess_documents', (q) => q.select('employee_id, doc_type')),

    /* ── Phase 2C: profile-change requests ── */

    getChangeRequest: (id) =>
      read('hr_ess_change_requests', (q) => q.select(COLUMNS.changeRequest).eq('id', id).maybeSingle()),
    /** The caller's own asks, newest first (E3). */
    listMyChangeRequests: (employeeId) =>
      list('hr_ess_change_requests', (q) => q.select(COLUMNS.changeRequest).eq('employee_id', employeeId)
        .order('created_at', { ascending: false }).limit(LIST_LIMITS.changeRequests + 1)),
    /** HR's queue, newest first, optionally held to one status. */
    listChangeRequests: (statuses) =>
      list('hr_ess_change_requests', (q) => {
        const base = q.select(COLUMNS.changeRequest);
        const filtered = statuses ? base.in('status', statuses) : base;
        return filtered.order('created_at', { ascending: false }).limit(LIST_LIMITS.hrChangeRequests + 1);
      }),
    /** One open ask per field per person: the database's partial unique index holds this, and
     * REFUSALS.CHANGE_REQUEST_KEPT answers it as the route's 409. */
    createChangeRequest: (row) =>
      write('hr_ess_change_requests', (q) => q.insert([row]).select(COLUMNS.changeRequest).single(),
        REFUSALS.CHANGE_REQUEST_KEPT),
    /** HR's decision: only an open row moves, so a second decide finds nothing and answers null. */
    decideChangeRequest: (id, patch) =>
      write('hr_ess_change_requests', (q) => q.update(patch).eq('id', id).eq('status', 'open')
        .select(COLUMNS.changeRequest).maybeSingle()),

    /* ── Phase 2C: bank details ── */

    /** One row per person (its primary key), or null while none is saved. */
    getBankDetails: (employeeId) =>
      read('hr_ess_bank_details', (q) => q.select(COLUMNS.bankDetails).eq('employee_id', employeeId).maybeSingle()),
    /** The save: consent already checked by the route; the stamp lands here with it. */
    upsertBankDetails: (row) =>
      write('hr_ess_bank_details', (q) => q.upsert([row], { onConflict: 'employee_id' })
        .select(COLUMNS.bankDetails).single()),

    /* ── the audit trail (health) ── */

    /** The health check's read: one row of a small table. `signal` lets the caller give up on it. */
    ping: async ({ signal } = {}) => {
      await read('hr_branches', (q) => {
        const query = q.select('id').limit(1);
        return signal ? query.abortSignal(signal) : query;
      });
    },
  };
}

module.exports = {
  createSupabaseStore,
  storeError,
  COLUMNS,
  NOT_INSTALLED_CODES,
  SESSION_FUNCTIONS,
  REFUSALS,
  NIL_UUID,
  DB_REQUEST_TIMEOUT_MS,
  IN_CHUNK,
  LIST_LIMITS,
};
