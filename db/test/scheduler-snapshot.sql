-- The Scheduler's tables and functions that team_app's migrations point at, for the throwaway
-- Postgres in db/test/run-migrations.js. Never applied anywhere else: in production these already
-- exist.
--
-- Hand-written, and only what the migrations need: the primary key of each table they reference,
-- plus the columns of the two attendance tables the ESS's own functions read and write
-- (hr_staff_attendance), and the one Scheduler function they call
-- (hr_attendance_apply_override). Each names the Scheduler migration it copies (Scheduler_Backend
-- at c28b9ca). When a team_app migration gains a foreign key to another Scheduler table, or calls
-- another Scheduler function, add it here the same way.
--
-- The runner compares these tables' columns before the migrations and after the rollbacks, which
-- is how it checks that no team_app migration or rollback alters a Scheduler table (ADR-0021).

-- users: supabase/migrations/20251215134244_remote_schema.sql:854-863 (the table) and 1474-1475
-- (users_pkey). Referenced by hr_ess_audit.actor_user_id, hr_ess_data_requests.resolved_by_user_id,
-- hr_ess_personal_details.updated_by_user_id and hr_ess_sessions.user_id. password_hash (:858) is
-- read inside the database by hr_ess_sessions' password fingerprint, whose SQL function is checked
-- against it as it is created. NOT NULL in the Scheduler; nullable here, so a check can make a
-- users row with only an id.
CREATE TABLE public.users (
  id uuid DEFAULT gen_random_uuid() NOT NULL,
  password_hash text,
  CONSTRAINT users_pkey PRIMARY KEY (id)
);

-- hr_employees: supabase/migrations/20260826000001_hrms_tables.sql:82-83. Referenced by every
-- hr_ess_* table's employee_id, and by hr_ess_audit.actor_employee_id. Also read for one column
-- the request functions need: full_name (the history's actor name), branch_id (the on-duty write).
CREATE TABLE public.hr_employees (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name text,
  branch_id uuid
);

-- hr_branches: supabase/migrations/20260826000001_hrms_tables.sql:39-48. Referenced by
-- hr_ess_mock_location_reports.branch_id.
CREATE TABLE public.hr_branches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid()
);

-- hr_staff_attendance: 20261015000004_hr_staff_attendance.sql:13-28, plus the punch columns of
-- 20261020000000_hr_attendance_punch.sql:62-66 and the rule columns of
-- 20261022000000_hr_attendance_shifts.sql:106-127. The ESS's request functions read and write it
-- through hr_attendance_apply_override (and, for an excused late, exactly the columns HR's own
-- excuse-late writes). The one-CL unique index (20261022000000:142-145) is here too: the decision
-- function's own check is the first line, and this index is the backstop the tests provoke.
CREATE TABLE public.hr_staff_attendance (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id    uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  branch_id      uuid REFERENCES public.hr_branches(id) ON DELETE SET NULL,
  day            date NOT NULL,
  status         text NOT NULL CHECK (status IN (
                   'present', 'absent', 'half_day', 'leave', 'week_off', 'holiday'
                 )),
  leave_type     text,
  note           text,
  marked_by      uuid REFERENCES public.users(id) ON DELETE SET NULL,
  marked_by_name text,
  marked_at      timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  source         text CHECK (source IS NULL OR source IN ('manual', 'self_punch', 'override', 'auto')),
  first_in       timestamptz,
  last_out       timestamptz,
  worked_minutes integer,
  shift_id       uuid,
  shift_start    time,
  shift_end      time,
  grace_minutes  integer,
  late_minutes   integer,
  early_exit_minutes integer,
  late_count     integer,
  late_half_day  boolean NOT NULL DEFAULT false,
  late_excused   boolean NOT NULL DEFAULT false,
  late_excused_by_name text,
  late_excused_reason  text,
  late_excused_at      timestamptz,
  UNIQUE (employee_id, day)
);

CREATE UNIQUE INDEX uq_hr_staff_attendance_one_cl_a_month
  ON public.hr_staff_attendance (employee_id, (date_trunc('month', day::timestamp)))
  WHERE status = 'leave' AND leave_type = 'cl';

-- hr_attendance_overrides: 20261020000000_hr_attendance_punch.sql (the log
-- hr_attendance_apply_override writes). Referenced by the stub below only.
CREATE TABLE public.hr_attendance_overrides (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id         uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  day                 date NOT NULL,
  before              jsonb,
  after               jsonb,
  reason              text,
  overridden_by       uuid REFERENCES public.users(id) ON DELETE SET NULL,
  overridden_by_name  text,
  overridden_at       timestamptz NOT NULL DEFAULT now()
);

-- hr_attendance_apply_override: a copy of the Scheduler's own function
-- (20261020000000_hr_attendance_punch.sql:290-341) for this test only, so the ESS's request
-- functions have something to call. It behaves as the real one does: row-locks the day, upserts
-- it as source 'override' with note = p_reason, keeps the before-branch on an update, and writes
-- the before/after log -- with no day or status guard, exactly like the real one (the guards live
-- in the callers). Kept in step by hand with the Scheduler migration named above.
CREATE FUNCTION public.hr_attendance_apply_override(
  p_employee_id    uuid,
  p_day            date,
  p_branch_id      uuid,
  p_status         text,
  p_leave_type     text,
  p_first_in       timestamptz,
  p_last_out       timestamptz,
  p_worked_minutes integer,
  p_reason         text,
  p_by             uuid,
  p_by_name        text
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  v_before hr_staff_attendance;
  v_had    boolean;
  v_after  hr_staff_attendance;
BEGIN
  SELECT * INTO v_before FROM hr_staff_attendance
   WHERE employee_id = p_employee_id AND day = p_day
   FOR UPDATE;
  v_had := FOUND;

  INSERT INTO hr_staff_attendance AS a
    (employee_id, branch_id, day, status, leave_type, note, source,
     first_in, last_out, worked_minutes, marked_by, marked_by_name, marked_at, updated_at)
  VALUES
    (p_employee_id, CASE WHEN v_had THEN v_before.branch_id ELSE p_branch_id END, p_day, p_status, p_leave_type,
     p_reason, 'override', p_first_in, p_last_out, p_worked_minutes, p_by, p_by_name, now(), now())
  ON CONFLICT (employee_id, day) DO UPDATE SET
    status         = EXCLUDED.status,
    leave_type     = EXCLUDED.leave_type,
    note           = EXCLUDED.note,
    source         = 'override',
    first_in       = EXCLUDED.first_in,
    last_out       = EXCLUDED.last_out,
    worked_minutes = EXCLUDED.worked_minutes,
    marked_by      = EXCLUDED.marked_by,
    marked_by_name = EXCLUDED.marked_by_name,
    marked_at      = EXCLUDED.marked_at,
    updated_at     = EXCLUDED.updated_at
  RETURNING * INTO v_after;

  INSERT INTO hr_attendance_overrides (employee_id, day, before, after, reason, overridden_by, overridden_by_name)
  VALUES (p_employee_id, p_day, CASE WHEN v_had THEN to_jsonb(v_before) END, to_jsonb(v_after), p_reason, p_by, p_by_name);

  RETURN jsonb_build_object('before', CASE WHEN v_had THEN to_jsonb(v_before) END, 'after', to_jsonb(v_after));
END $$;
