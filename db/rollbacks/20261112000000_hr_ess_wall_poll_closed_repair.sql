-- Team RVM (ESS): undo the Wall poll-close column repair.
-- Safe to run twice. Only intended after the Wall is switched off.

DO $repair$
BEGIN
  IF to_regclass('public.hr_ess_wall_posts') IS NOT NULL THEN
    ALTER TABLE public.hr_ess_wall_posts
      DROP COLUMN IF EXISTS poll_closed_at;
  END IF;
END
$repair$;

NOTIFY pgrst, 'reload schema';
