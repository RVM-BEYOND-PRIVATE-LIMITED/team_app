-- Team RVM (ESS): undo the Helpdesk's tables (db/migrations/20261109000001_hr_ess_helpdesk.sql).
-- Safe to run twice: everything is IF EXISTS.

DROP TABLE IF EXISTS public.hr_ess_helpdesk_messages;
DROP TABLE IF EXISTS public.hr_ess_helpdesk_tickets;
DROP TABLE IF EXISTS public.hr_ess_helpdesk_categories;
DROP SEQUENCE IF EXISTS public.hr_ess_helpdesk_ticket_ref_seq;

NOTIFY pgrst, 'reload schema';
