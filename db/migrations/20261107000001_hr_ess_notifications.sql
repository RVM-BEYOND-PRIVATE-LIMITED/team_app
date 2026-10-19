-- Team RVM (ESS): the in-app notifications and the categories a person can turn off (tasks D6, D8).
--
-- Every notification is an in-app row first, and the push worker delivers it to the phone after:
-- the app's Inbox shows the row at once, whether or not the push ever leaves the server. A row
-- keeps what the worker needs (pushed_at, push_mode, attempts, the last error), so a failed push
-- is retried and an old one is never sent twice.
--
-- Categories are the three Phase 1 events: an approval waiting for me, my request decided, and a
-- priority task assigned to me. The Wall's categories (mentions, replies, praise, announcements,
-- acknowledgements, polls) arrive with Phase 2 and extend the CHECK then.
--
-- Nothing is pushed at night: the worker holds PUSH_QUIET_FROM to PUSH_QUIET_TO (21:00 to 08:00
-- IST, src/policy/notifications.js); the in-app row is still written at once.
--
-- hr_ess_notification_settings holds only what a person turns off; no row means everything on.
--
-- New tables only (ADR-0021). Safe to run twice. Row-level security on with no policy.
--
-- Rollback: db/rollbacks/20261107000001_hr_ess_notifications.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_notifications (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id   uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  category      text NOT NULL CHECK (category IN ('approvals', 'decisions', 'priority_tasks')),
  title         text NOT NULL CHECK (length(btrim(title)) BETWEEN 1 AND 200),
  body          text NOT NULL CHECK (length(btrim(body)) BETWEEN 1 AND 1000),
  -- The ids a tap needs (request_id, request_family, task_id): never personal data.
  data          jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(data) = 'object'),
  read_at       timestamptz,
  pushed_at     timestamptz,
  push_mode     text CHECK (push_mode IS NULL OR push_mode IN ('fcm', 'log', 'skipped')),
  push_attempts integer NOT NULL DEFAULT 0 CHECK (push_attempts >= 0),
  push_error    text CHECK (push_error IS NULL OR length(push_error) <= 500),
  created_at    timestamptz NOT NULL DEFAULT now(),
  -- A pushed row says how it went; an unpushed one says nothing.
  CONSTRAINT hr_ess_notifications_push_chk CHECK ((pushed_at IS NULL) = (push_mode IS NULL))
);

CREATE INDEX IF NOT EXISTS hr_ess_notifications_person_idx
  ON public.hr_ess_notifications (employee_id, created_at DESC);
CREATE INDEX IF NOT EXISTS hr_ess_notifications_unread_idx
  ON public.hr_ess_notifications (employee_id) WHERE read_at IS NULL;
-- The worker's queue: rows not yet pushed, oldest first.
CREATE INDEX IF NOT EXISTS hr_ess_notifications_pending_idx
  ON public.hr_ess_notifications (created_at) WHERE pushed_at IS NULL;
-- One notification per person per priority task, so a poll or a restart cannot notify twice.
CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_notifications_task_key
  ON public.hr_ess_notifications (employee_id, category, (data ->> 'task_id'))
  WHERE category = 'priority_tasks' AND data ? 'task_id';

CREATE TABLE IF NOT EXISTS public.hr_ess_notification_settings (
  employee_id         uuid PRIMARY KEY REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  disabled_categories text[] NOT NULL DEFAULT '{}'
                        CHECK (disabled_categories <@ ARRAY['approvals', 'decisions', 'priority_tasks']::text[]),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.hr_ess_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_ess_notification_settings ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_notifications FROM anon;
    REVOKE ALL ON TABLE public.hr_ess_notification_settings FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_notifications FROM authenticated;
    REVOKE ALL ON TABLE public.hr_ess_notification_settings FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_notifications TO service_role;
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_notification_settings TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
