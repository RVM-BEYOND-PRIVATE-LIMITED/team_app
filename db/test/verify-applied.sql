-- Team RVM (ESS): are all 27 migrations applied?
--
-- Read-only. Run in the Supabase SQL editor. One row per check, MISSING first; every row must
-- read OK. Nothing is created, changed or deleted.
--
-- Table and function names come from db/migrations; the seeds are the migrations' ON CONFLICT DO
-- NOTHING rows, so a re-run cannot change them.

WITH expected_tables(name) AS (VALUES
  ('hr_ess_sessions'), ('hr_ess_audit'), ('hr_ess_data_requests'), ('hr_ess_personal_details'),
  ('hr_ess_mock_location_reports'), ('hr_ess_request_limits'), ('hr_ess_attendance_requests'),
  ('hr_ess_attendance_request_history'), ('hr_ess_leave_requests'), ('hr_ess_leave_request_history'),
  ('hr_ess_request_archives'), ('hr_ess_push_devices'), ('hr_ess_notifications'),
  ('hr_ess_notification_settings'), ('hr_ess_wall_posts'), ('hr_ess_wall_comments'),
  ('hr_ess_wall_poll_options'), ('hr_ess_wall_poll_votes'), ('hr_ess_wall_reactions'),
  ('hr_ess_wall_mentions'), ('hr_ess_wall_wishes'), ('hr_ess_wall_reports'),
  ('hr_ess_celebration_optouts'), ('hr_ess_announcements'), ('hr_ess_announcement_audience'),
  ('hr_ess_announcement_reads'), ('hr_ess_helpdesk_categories'), ('hr_ess_helpdesk_tickets'),
  ('hr_ess_helpdesk_messages'), ('hr_ess_document_types'), ('hr_ess_documents'),
  ('hr_ess_change_requests'), ('hr_ess_bank_details'), ('hr_ess_helpdesk_assignments'),
  ('hr_ess_approval_escalations'), ('hr_ess_infra_links'), ('hr_ess_wfh_allowances')
),
expected_functions(name) AS (VALUES
  ('hr_ess_session_rotate'), ('hr_ess_session_revoke'), ('hr_ess_session_password_current'),
  ('hr_ess_password_fingerprint'), ('hr_ess_sessions_bind_password'),
  ('hr_ess_decide_attendance_request'), ('hr_ess_decide_leave_request'),
  ('hr_ess_withdraw_attendance_request'), ('hr_ess_withdraw_leave_request'),
  ('hr_ess_cancel_attendance_request'), ('hr_ess_cancel_leave_request'), ('hr_ess_on_duty_apply'),
  ('hr_ess_data_requests_open_limit'), ('hr_ess_attendance_requests_filed'),
  ('hr_ess_leave_requests_filed')
),
checks AS (
  SELECT 'table public.' || name AS check,
         to_regclass('public.' || name) IS NOT NULL AS ok
  FROM expected_tables
  UNION ALL
  SELECT 'function public.' || name,
         EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                  WHERE n.nspname = 'public' AND p.proname = expected_functions.name)
  FROM expected_functions
  UNION ALL
  SELECT 'column hr_ess_attendance_requests.minutes (migration 25)',
         EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'hr_ess_attendance_requests'
                    AND column_name = 'minutes')
  UNION ALL
  SELECT 'column hr_ess_helpdesk_tickets.assigned_at (migration 22)',
         EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'hr_ess_helpdesk_tickets'
                    AND column_name = 'assigned_at')
  UNION ALL
  SELECT 'column hr_ess_wall_posts.poll_closed_at (repair for migration 13)',
         EXISTS (SELECT 1 FROM information_schema.columns
                  WHERE table_schema = 'public' AND table_name = 'hr_ess_wall_posts'
                    AND column_name = 'poll_closed_at')
  UNION ALL
  SELECT 'leave type check includes wfh (migration 29)',
         EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'hr_ess_leave_requests_type_check'
                    AND pg_get_constraintdef(oid) LIKE '%wfh%')
  UNION ALL
  SELECT 'notification categories include documents (migration 24)',
         EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'hr_ess_notifications_category_check'
                    AND pg_get_constraintdef(oid) LIKE '%documents%')
  UNION ALL
  SELECT 'notification setting categories include documents (migration 24)',
         EXISTS (SELECT 1 FROM pg_constraint
                  WHERE conname = 'hr_ess_notification_settings_disabled_categories_check'
                    AND pg_get_constraintdef(oid) LIKE '%documents%')
  UNION ALL
  SELECT 'seed: 9 document types (migration 19)',
         (SELECT count(*) FROM public.hr_ess_document_types) >= 9
  UNION ALL
  SELECT 'seed: 6 request limits (migration 6; WFH is per employee since 29)',
         (SELECT count(*) FROM public.hr_ess_request_limits) >= 6
  UNION ALL
  SELECT 'seed: 10 helpdesk categories (migration 17)',
         (SELECT count(*) FROM public.hr_ess_helpdesk_categories) >= 10
  UNION ALL
  SELECT 'seed: POSH queue is internal_committee (migration 23)',
         EXISTS (SELECT 1 FROM public.hr_ess_helpdesk_categories
                  WHERE slug = 'posh' AND 'internal_committee' = ANY (queue_roles))
)
SELECT check, CASE WHEN ok THEN 'OK' ELSE 'MISSING' END AS state
FROM checks
ORDER BY ok, check;
