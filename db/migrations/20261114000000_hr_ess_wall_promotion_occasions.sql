-- Team RVM (ESS) — let a Wall wish celebrate a promotion.
--
-- THE PROBLEM
--
-- The Wall's celebrations learned to show promotions (issue #15, QA point 20), and the wish
-- route now accepts occasion 'promotion'. Two CHECK constraints still name only the first two
-- occasions, so a promotion wish is refused by the database:
--
--   hr_ess_wall_posts.occasion   ('birthday', 'anniversary')
--   hr_ess_wall_wishes.occasion  ('birthday', 'anniversary')
--
-- WHAT IS ADDED
--
-- 'promotion' is added to both lists. Nothing else changes: no row is written, no column is
-- added, and the shapes that already existed (a wish names somebody else, a wish body is 1 to
-- 200 characters, one wish per person per occasion per year) still hold.
--
-- This is an additive widening of an hr_ess_* table's own CHECK, in the same spirit as
-- migration 23 (POSH's queue roles) and 25 (short leave). It does not touch a Scheduler table.
--
-- Safe to run twice: every single-column CHECK on `occasion` is dropped before the widened one
-- is added. Finding them by their shape rather than their name also covers a live database whose
-- constraint was created from an earlier revision of migration 13.
--
-- ROLLBACK:
--   db/rollbacks/20261114000000_hr_ess_wall_promotion_occasions.sql
--   deletes the promotion wishes and posts first, because the old CHECK would refuse them, then
--   puts both lists back to the two occasions.

DO $migration$
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
      CHECK (occasion IS NULL OR occasion IN ('birthday', 'anniversary', 'promotion'));
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
      CHECK (occasion IN ('birthday', 'anniversary', 'promotion'));
  END IF;
END $migration$;
