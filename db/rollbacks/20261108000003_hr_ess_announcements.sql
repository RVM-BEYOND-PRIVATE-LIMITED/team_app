-- Rollback of db/migrations/20261108000003_hr_ess_announcements.sql.
--
-- Drops the announcements, their resolved audience and their read state: the sender's counts and
-- the read record go with them. Run it only to take the Wall out; the read state cannot be
-- rebuilt afterwards.
--
-- Safe to run twice. The Scheduler's student notices are not touched (they never were).

DROP TABLE IF EXISTS public.hr_ess_announcement_reads;
DROP TABLE IF EXISTS public.hr_ess_announcement_audience;
DROP TABLE IF EXISTS public.hr_ess_announcements;

NOTIFY pgrst, 'reload schema';
