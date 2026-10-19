-- Team RVM (ESS): the Wall's report queue and the celebration opt-out (tasks F6, F7).
--
-- F7: anybody may report a post or a comment. A report goes to HR's queue and changes nothing on
-- its own: HR hides the post or comment with a reason (in the routes, audited as
-- 'wall.post.hidden' / 'wall.comment.hidden') or leaves it. One report per person per thing, so a
-- second tap is the same tap; the baseless ones stay in the row's history either way.
--
-- The body of the report is HR's only window on what a reporter saw: it is the reporter's own
-- words (a reason and, at most, a line of detail), never a copy of the post. Nothing in this
-- table is ever shown to anybody but HR.
--
-- F6: birthdays are day and month only — never the year — and are "hidden for anyone who opts
-- out". The opt-out is one row per employee who wants their birthday left off the Wall's
-- celebration cards; a row with hidden = false is somebody who looked at the switch and left it
-- on, which keeps HR's answer ("nobody opted out") a fact rather than a missing row.
--
-- New tables only (ADR-0021). Safe to run twice. Row-level security is on with no policy, so only
-- the service role (the ESS) can read or write.
--
-- Rollback: db/rollbacks/20261108000002_hr_ess_wall_reports.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_wall_reports (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id       uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  post_id           uuid REFERENCES public.hr_ess_wall_posts(id) ON DELETE CASCADE,
  comment_id        uuid REFERENCES public.hr_ess_wall_comments(id) ON DELETE CASCADE,
  -- The reporter's own words. Shown to HR, never to the reported person.
  reason            text NOT NULL CHECK (length(btrim(reason)) BETWEEN 3 AND 280),
  detail            text CHECK (detail IS NULL OR length(btrim(detail)) BETWEEN 1 AND 500),
  -- Who handled it, when, and what they decided. NULL means the queue still holds it.
  status            text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'hidden', 'kept')),
  resolved_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  resolved_by_name  text,
  resolved_at       timestamptz,
  resolution_note   text CHECK (resolution_note IS NULL OR length(btrim(resolution_note)) BETWEEN 1 AND 200),
  created_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hr_ess_wall_reports_target_chk CHECK ((post_id IS NULL) <> (comment_id IS NULL)),
  CONSTRAINT hr_ess_wall_reports_resolved_chk CHECK (
    (status = 'open' AND resolved_at IS NULL AND resolved_by_name IS NULL AND resolution_note IS NULL)
    OR (status IN ('hidden', 'kept') AND resolved_at IS NOT NULL AND resolved_by_name IS NOT NULL)
  )
);

-- HR's queue: what is still open, oldest first, and one page of history.
CREATE INDEX IF NOT EXISTS hr_ess_wall_reports_queue_idx
  ON public.hr_ess_wall_reports (status, created_at);
-- A thing's own reports, newest first.
CREATE INDEX IF NOT EXISTS hr_ess_wall_reports_post_idx
  ON public.hr_ess_wall_reports (post_id, created_at DESC) WHERE post_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS hr_ess_wall_reports_comment_idx
  ON public.hr_ess_wall_reports (comment_id, created_at DESC) WHERE comment_id IS NOT NULL;
-- One report per person per thing: a second tap is the same tap.
CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_wall_reports_post_key
  ON public.hr_ess_wall_reports (post_id, reporter_id) WHERE post_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_wall_reports_comment_key
  ON public.hr_ess_wall_reports (comment_id, reporter_id) WHERE comment_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.hr_ess_celebration_optouts (
  employee_id uuid PRIMARY KEY REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  hidden      boolean NOT NULL DEFAULT true,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.hr_ess_wall_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_ess_celebration_optouts ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_wall_reports FROM anon;
    REVOKE ALL ON TABLE public.hr_ess_celebration_optouts FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_wall_reports FROM authenticated;
    REVOKE ALL ON TABLE public.hr_ess_celebration_optouts FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_wall_reports TO service_role;
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_celebration_optouts TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
