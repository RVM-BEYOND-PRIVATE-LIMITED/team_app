-- Team RVM (ESS): undo the infra link table (db/migrations/20261112000001_hr_ess_infra_links.sql).
-- Safe to run twice. Nothing outside the ESS's own table is touched.

DROP TABLE IF EXISTS public.hr_ess_infra_links;

NOTIFY pgrst, 'reload schema';
