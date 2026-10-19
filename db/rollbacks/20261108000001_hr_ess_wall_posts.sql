-- Rollback of db/migrations/20261108000001_hr_ess_wall_posts.sql.
--
-- Drops every table the migration creates, children before parents, so a re-run is safe. It
-- deletes the rows they hold: every Wall post, comment, reaction, poll, vote and wish. Run it
-- only to take the Wall out, as the rollback for the migration that built it
-- (docs/04-build-plan.md, Migrations, in run order).
--
-- Safe to run twice. Touches nothing the Scheduler owns, and nothing of another migration.

DROP TABLE IF EXISTS public.hr_ess_wall_wishes;
DROP TABLE IF EXISTS public.hr_ess_wall_mentions;
DROP TABLE IF EXISTS public.hr_ess_wall_reactions;
DROP TABLE IF EXISTS public.hr_ess_wall_poll_votes;
DROP TABLE IF EXISTS public.hr_ess_wall_poll_options;
DROP TABLE IF EXISTS public.hr_ess_wall_comments;
DROP TABLE IF EXISTS public.hr_ess_wall_posts;

NOTIFY pgrst, 'reload schema';
