-- Team RVM (ESS): the Wall's missing poll close column (repair for migration 13).
--
-- The live hr_ess_wall_posts was created from an earlier revision of
-- 20261108000001_hr_ess_wall_posts.sql and never had poll_closed_at, which the Wall's reads name
-- on every post. CREATE TABLE IF NOT EXISTS does not add a column to an existing table, so
-- re-running migration 13 cannot fix it; this repair adds the one column and nothing else.
--
-- Safe to run twice. Rollback: db/rollbacks/20261112000000_hr_ess_wall_poll_closed_repair.sql

DO $repair$
BEGIN
  IF to_regclass('public.hr_ess_wall_posts') IS NOT NULL THEN
    ALTER TABLE public.hr_ess_wall_posts
      ADD COLUMN IF NOT EXISTS poll_closed_at timestamptz;
  END IF;
END
$repair$;

NOTIFY pgrst, 'reload schema';
