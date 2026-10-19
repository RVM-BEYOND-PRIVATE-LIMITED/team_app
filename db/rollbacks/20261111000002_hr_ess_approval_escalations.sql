-- Team RVM (ESS): undo the approval escalations (db/migrations/20261111000002_hr_ess_approval_escalations.sql).
-- The trail's rows go with the table. Safe to run twice.

DROP TABLE IF EXISTS public.hr_ess_approval_escalations;

NOTIFY pgrst, 'reload schema';
