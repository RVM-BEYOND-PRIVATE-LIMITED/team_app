-- The Scheduler's tables that team_app's migrations point at, for the throwaway Postgres in
-- db/test/run-migrations.js. Never applied anywhere else: in production these tables already exist.
--
-- Hand-written, and only what the hr_ess_* foreign keys need: the primary key of each table they
-- reference. Each table names the Scheduler migration it copies (Scheduler_Backend at c28b9ca).
-- When a team_app migration gains a foreign key to another Scheduler table, add that table here
-- the same way.
--
-- The runner compares these tables' columns before the migrations and after the rollbacks, which
-- is how it checks that no team_app migration or rollback alters a Scheduler table (ADR-0021).

-- users: supabase/migrations/20251215134244_remote_schema.sql:854-863 (the table) and 1474-1475
-- (users_pkey). Referenced by hr_ess_audit.actor_user_id, hr_ess_data_requests.resolved_by_user_id
-- and hr_ess_personal_details.updated_by_user_id.
CREATE TABLE public.users (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  CONSTRAINT users_pkey PRIMARY KEY (id)
);

-- hr_employees: supabase/migrations/20260826000001_hrms_tables.sql:82-83. Referenced by every
-- hr_ess_* table's employee_id, and by hr_ess_audit.actor_employee_id.
CREATE TABLE public.hr_employees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid()
);

-- hr_branches: supabase/migrations/20260826000001_hrms_tables.sql:39-48. Referenced by
-- hr_ess_mock_location_reports.branch_id.
CREATE TABLE public.hr_branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid()
);
