-- Team RVM (ESS): undo My Documents (db/migrations/20261110000001_hr_ess_documents.sql).
-- Safe to run twice: everything is IF EXISTS.

DROP TABLE IF EXISTS public.hr_ess_documents;
DROP TABLE IF EXISTS public.hr_ess_document_types;

NOTIFY pgrst, 'reload schema';
