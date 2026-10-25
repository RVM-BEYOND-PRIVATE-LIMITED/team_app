-- Rollback for 20261114000000_hr_ess_wall_promotion_occasions.sql.
--
-- The old CHECK knows only birthdays and anniversaries, so the promotion rows must go first or
-- adding it back fails. They are the rows this migration made possible and no older Wall row can
-- carry them. Safe to run twice, and safe after the Wall tables have already been dropped.

DO $rollback$
BEGIN
  IF to_regclass('public.hr_ess_wall_wishes') IS NOT NULL THEN
    DELETE FROM public.hr_ess_wall_wishes WHERE occasion = 'promotion';
  END IF;

  IF to_regclass('public.hr_ess_wall_posts') IS NOT NULL THEN
    DELETE FROM public.hr_ess_wall_posts WHERE kind = 'wish' AND occasion = 'promotion';
  END IF;
END $rollback$;

DO $rollback$
DECLARE
  c record;
BEGIN
  IF to_regclass('public.hr_ess_wall_posts') IS NOT NULL THEN
    FOR c IN
      SELECT con.conname
      FROM pg_constraint con
      JOIN pg_attribute att
        ON att.attrelid = con.conrelid AND att.attnum = ANY (con.conkey)
      WHERE con.conrelid = 'public.hr_ess_wall_posts'::regclass
        AND con.contype = 'c'
        AND att.attname = 'occasion'
        AND cardinality(con.conkey) = 1
    LOOP
      EXECUTE format('ALTER TABLE public.hr_ess_wall_posts DROP CONSTRAINT %I', c.conname);
    END LOOP;

    ALTER TABLE public.hr_ess_wall_posts
      DROP CONSTRAINT IF EXISTS hr_ess_wall_posts_occasion_check;
    ALTER TABLE public.hr_ess_wall_posts
      ADD CONSTRAINT hr_ess_wall_posts_occasion_check
      CHECK (occasion IS NULL OR occasion IN ('birthday', 'anniversary'));
  END IF;

  IF to_regclass('public.hr_ess_wall_wishes') IS NOT NULL THEN
    FOR c IN
      SELECT con.conname
      FROM pg_constraint con
      JOIN pg_attribute att
        ON att.attrelid = con.conrelid AND att.attnum = ANY (con.conkey)
      WHERE con.conrelid = 'public.hr_ess_wall_wishes'::regclass
        AND con.contype = 'c'
        AND att.attname = 'occasion'
        AND cardinality(con.conkey) = 1
    LOOP
      EXECUTE format('ALTER TABLE public.hr_ess_wall_wishes DROP CONSTRAINT %I', c.conname);
    END LOOP;

    ALTER TABLE public.hr_ess_wall_wishes
      DROP CONSTRAINT IF EXISTS hr_ess_wall_wishes_occasion_check;
    ALTER TABLE public.hr_ess_wall_wishes
      ADD CONSTRAINT hr_ess_wall_wishes_occasion_check
      CHECK (occasion IN ('birthday', 'anniversary'));
  END IF;
END $rollback$;
