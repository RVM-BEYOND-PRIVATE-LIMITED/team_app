-- Team RVM (ESS): an urgent lane for the notifications the phone must deliver at once
-- (team_app #59, TA-P-01).
--
-- A CRM callback or a call placed from the web cannot wait for the 08:00 quiet hours to end. The
-- row carries its priority, and the push worker has a second loop that sends only the urgent ones
-- (src/jobs/push.js). Normal rows keep the minute loop and the quiet hours exactly as before.
--
--   priority  'normal' (the default, every existing row) or 'urgent'
--
-- Only the two CRM call categories may be urgent: an urgent 'decisions' row would be a bug in the
-- caller, and the database says so rather than letting it reach a phone at 02:00.
--
-- Safe to run twice.
--
-- Rollback: db/rollbacks/20261211000001_hr_ess_notification_priority.sql

ALTER TABLE public.hr_ess_notifications
  ADD COLUMN IF NOT EXISTS priority text NOT NULL DEFAULT 'normal';

ALTER TABLE public.hr_ess_notifications
  DROP CONSTRAINT IF EXISTS hr_ess_notifications_priority_chk;
ALTER TABLE public.hr_ess_notifications
  ADD CONSTRAINT hr_ess_notifications_priority_chk CHECK (priority IN ('normal', 'urgent'));

ALTER TABLE public.hr_ess_notifications
  DROP CONSTRAINT IF EXISTS hr_ess_notifications_urgent_category_chk;
ALTER TABLE public.hr_ess_notifications
  ADD CONSTRAINT hr_ess_notifications_urgent_category_chk CHECK (
    priority <> 'urgent' OR category IN ('crm_callback', 'crm_call')
  );

-- The urgent loop's queue: unpushed urgent rows, oldest first.
CREATE INDEX IF NOT EXISTS hr_ess_notifications_urgent_idx
  ON public.hr_ess_notifications (created_at) WHERE pushed_at IS NULL AND priority = 'urgent';

NOTIFY pgrst, 'reload schema';
