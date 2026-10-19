-- Team RVM (ESS): undo the bank details (db/migrations/20261110000003_hr_ess_bank_details.sql).
-- Safe to run twice: everything is IF EXISTS.

DROP TABLE IF EXISTS public.hr_ess_bank_details;

NOTIFY pgrst, 'reload schema';
