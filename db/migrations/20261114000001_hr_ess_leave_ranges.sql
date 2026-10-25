-- Team RVM (ESS): leave in half days, single days and date ranges.
--
-- RVM, 26 Oct 2026: "Allow half days and single day as well as multiple days leave".
--
-- A request keeps one row. `day` is the first day (the column the app has always read),
-- `end_day` the last; `portion` says whether the day or days are full days, the first half or
-- the second half; `day_count` is the leave it consumes (0.5 for a half day, one per working
-- day otherwise); `working_days` is the list of days the approval will write.
--
-- Weekly offs and holidays are skipped: they are not leave, are not written to the Scheduler
-- and do not consume the balance. The employee's `week_off_days` and the branch's holidays
-- decide them, and a day the Scheduler already records as week_off/holiday is skipped too.
--
-- Casual leave keeps its monthly allowance from hr_ess_request_limits (`leave_cl`, one day
-- until HR changes it). A half day costs 0.5, so two half days are one full day; a range is
-- allowed only when the whole range fits. Leave without pay has no limit until HR sets one.
-- The Scheduler's one-CL unique index is replaced by the allowance check below plus the
-- database trigger in Scheduler_Backend 20261114000001 (the two are deployed together).
--
-- Approval writes every working day through the Scheduler's hr_attendance_apply_override:
-- a full day as status 'leave', a half day as 'half_day' with leave_type set and the portion
-- in the note. Cancel restores every day from `days_before`, the same way the single-day
-- cancel always did.
--
-- Rollback: db/rollbacks/20261114000001_hr_ess_leave_ranges.sql

/* ── the request: a range, a half-day choice, and the days it consumes ── */
ALTER TABLE public.hr_ess_leave_requests
  ADD COLUMN IF NOT EXISTS end_day       date,
  ADD COLUMN IF NOT EXISTS portion       text NOT NULL DEFAULT 'full',
  ADD COLUMN IF NOT EXISTS day_count     numeric(5,1) NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS working_days  jsonb NOT NULL DEFAULT '[]'::jsonb,
  ADD COLUMN IF NOT EXISTS days_before   jsonb;

UPDATE public.hr_ess_leave_requests
   SET end_day = day
 WHERE end_day IS NULL;

UPDATE public.hr_ess_leave_requests
   SET working_days = jsonb_build_array(day)
 WHERE working_days = '[]'::jsonb;

ALTER TABLE public.hr_ess_leave_requests
  ALTER COLUMN end_day SET NOT NULL;

DO $$
BEGIN
  ALTER TABLE public.hr_ess_leave_requests
    ADD CONSTRAINT hr_ess_leave_requests_range_chk CHECK (end_day >= day);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$
BEGIN
  ALTER TABLE public.hr_ess_leave_requests
    ADD CONSTRAINT hr_ess_leave_requests_portion_chk
    CHECK (portion IN ('full', 'first_half', 'second_half'));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$
BEGIN
  ALTER TABLE public.hr_ess_leave_requests
    ADD CONSTRAINT hr_ess_leave_requests_half_day_chk
    CHECK (portion = 'full' OR day = end_day);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$
BEGIN
  ALTER TABLE public.hr_ess_leave_requests
    ADD CONSTRAINT hr_ess_leave_requests_count_chk CHECK (day_count > 0);
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

/* ── the working days of a range: week offs and holidays left out ── */
CREATE OR REPLACE FUNCTION public.hr_ess_leave_working_days(
  p_employee_id uuid,
  p_from        date,
  p_to          date
)
RETURNS date[]
LANGUAGE plpgsql
STABLE
SET search_path = public, pg_temp
AS $$
DECLARE
  v_branch   uuid;
  v_week_off smallint[];
BEGIN
  SELECT branch_id, week_off_days INTO v_branch, v_week_off
    FROM hr_employees WHERE id = p_employee_id;
  IF NOT FOUND THEN RETURN ARRAY[]::date[]; END IF;

  RETURN ARRAY(
    SELECT g::date
      FROM generate_series(p_from, p_to, interval '1 day') AS g
     WHERE NOT (extract(dow FROM g)::smallint = ANY(COALESCE(v_week_off, '{0}'::smallint[])))
       AND NOT EXISTS (
         SELECT 1 FROM hr_holidays h
          WHERE h.day = g::date
            AND (h.branch_id IS NULL OR h.branch_id = v_branch)
       )
       AND NOT EXISTS (
         SELECT 1 FROM hr_staff_attendance a
          WHERE a.employee_id = p_employee_id
            AND a.day = g::date
            AND a.status IN ('week_off', 'holiday')
       )
     ORDER BY 1
  );
END $$;

/* ── the CL allowance, and what the month already uses ── */
CREATE OR REPLACE FUNCTION public.hr_ess_leave_cl_units(p_employee_id uuid, p_month date)
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE(SUM(CASE WHEN status = 'leave' THEN 1::numeric ELSE 0.5::numeric END), 0)
    FROM hr_staff_attendance
   WHERE employee_id = p_employee_id
     AND leave_type = 'cl'
     AND status IN ('leave', 'half_day')
     AND day >= date_trunc('month', p_month::timestamp)::date
     AND day <  (date_trunc('month', p_month::timestamp) + interval '1 month')::date;
$$;

CREATE OR REPLACE FUNCTION public.hr_ess_leave_cl_limit()
RETURNS numeric
LANGUAGE sql
STABLE
SET search_path = public, pg_temp
AS $$
  SELECT CASE
           WHEN EXISTS (SELECT 1 FROM hr_ess_request_limits WHERE type = 'leave_cl')
             THEN (SELECT limit_count::numeric FROM hr_ess_request_limits WHERE type = 'leave_cl')
           ELSE 1::numeric
         END;
$$;

/* ── the 'filed' history entry now names the whole range ── */
CREATE OR REPLACE FUNCTION public.hr_ess_leave_requests_filed()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO hr_ess_leave_request_history
    (request_id, at, actor_employee_id, actor_name, action, details)
  VALUES
    (NEW.id, NEW.created_at, NEW.employee_id,
     (SELECT full_name FROM hr_employees WHERE id = NEW.employee_id),
     'filed', jsonb_build_object(
       'type', NEW.type, 'day', NEW.day, 'end_day', NEW.end_day,
       'portion', NEW.portion, 'day_count', NEW.day_count));
  RETURN NEW;
END $$;

/* ── decide a leave request: a half day, one day, or a working-day range ── */
CREATE OR REPLACE FUNCTION public.hr_ess_decide_leave_request(
  p_request_id           uuid,
  p_decider_employee_id  uuid,
  p_decider_user_id      uuid,
  p_decider_name         text,
  p_approve              boolean,
  p_note                 text,
  p_now                  timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  r            hr_ess_leave_requests;
  v_today      date := (p_now AT TIME ZONE 'Asia/Kolkata')::date;
  v_boundary   date;
  v_days       date[];
  v_units      numeric;
  v_taken      numeric;
  v_limit      numeric;
  v_day        hr_staff_attendance;
  v_had        boolean;
  v_one        date;
  v_before     jsonb := '{}'::jsonb;
  v_first      jsonb;
  v_status     text;
  v_note       text;
BEGIN
  SELECT * INTO r FROM hr_ess_leave_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('outcome', 'not_found'); END IF;
  IF r.status <> 'pending' THEN
    RETURN jsonb_build_object('outcome', 'not_pending', 'request', to_jsonb(r));
  END IF;

  v_boundary := date_trunc('month', v_today::timestamp)::date;
  IF r.day < v_boundary THEN
    IF r.day < (date_trunc('month', v_today::timestamp) - interval '1 month')::date THEN
      RETURN jsonb_build_object('outcome', 'too_old');
    END IF;
    IF extract(day FROM v_today) > 5 THEN
      RETURN jsonb_build_object('outcome', 'cutoff');
    END IF;
  END IF;

  IF NOT p_approve THEN
    IF p_note IS NULL OR length(btrim(p_note)) < 3 THEN
      RETURN jsonb_build_object('outcome', 'note_required');
    END IF;
    UPDATE hr_ess_leave_requests
       SET status = 'rejected', decided_by_employee_id = p_decider_employee_id,
           decided_by_user_id = p_decider_user_id, decided_by_name = p_decider_name,
           decided_at = p_now, decision_note = btrim(p_note), updated_at = p_now
     WHERE id = r.id
     RETURNING * INTO r;
    INSERT INTO hr_ess_leave_request_history
      (request_id, at, actor_employee_id, actor_user_id, actor_name, action, note, details)
    VALUES
      (r.id, p_now, p_decider_employee_id, p_decider_user_id, p_decider_name, 'rejected', btrim(p_note),
       jsonb_build_object('type', r.type, 'day', r.day, 'end_day', r.end_day,
                          'portion', r.portion, 'day_count', r.day_count));
    RETURN jsonb_build_object('outcome', 'rejected', 'request', to_jsonb(r));
  END IF;

  -- WFH is one day and is work, so it is written even on a weekly off (its old behaviour).
  IF r.type = 'wfh' THEN
    v_days := ARRAY[r.day];
  ELSE
    v_days := hr_ess_leave_working_days(r.employee_id, r.day, r.end_day);
  END IF;
  IF COALESCE(array_length(v_days, 1), 0) = 0 THEN
    RETURN jsonb_build_object('outcome', 'no_working_days');
  END IF;
  IF r.portion <> 'full' AND array_length(v_days, 1) <> 1 THEN
    RETURN jsonb_build_object('outcome', 'invalid_range');
  END IF;

  v_units := CASE WHEN r.portion = 'full'
                  THEN array_length(v_days, 1)::numeric
                  ELSE 0.5::numeric END;

  -- The month's CL allowance, under a lock so two approvals cannot both spend the last half.
  IF r.type = 'cl' THEN
    PERFORM pg_advisory_xact_lock(
      hashtextextended('hr_ess_leave_cl:' || r.employee_id::text || ':'
                       || date_trunc('month', r.day::timestamp)::date::text, 0));
    SELECT hr_ess_leave_cl_units(r.employee_id, r.day) INTO v_taken;
    -- Days this request is about to overwrite do not count twice.
    SELECT v_taken - COALESCE(SUM(CASE WHEN status = 'leave' THEN 1::numeric ELSE 0.5::numeric END), 0)
      INTO v_taken
      FROM hr_staff_attendance
     WHERE employee_id = r.employee_id
       AND leave_type = 'cl'
       AND status IN ('leave', 'half_day')
       AND day = ANY(v_days);
    SELECT hr_ess_leave_cl_limit() INTO v_limit;
    IF v_limit IS NOT NULL AND v_taken + v_units > v_limit THEN
      RETURN jsonb_build_object('outcome', 'cl_limit');
    END IF;
  END IF;

  FOREACH v_one IN ARRAY v_days LOOP
    SELECT * INTO v_day FROM hr_staff_attendance
     WHERE employee_id = r.employee_id AND day = v_one
     FOR UPDATE;
    v_had := FOUND;
    v_before := jsonb_set(
      v_before, ARRAY[v_one::text],
      CASE WHEN v_had THEN to_jsonb(v_day) ELSE 'null'::jsonb END, true);

    v_status := CASE WHEN r.portion = 'full' THEN 'leave' ELSE 'half_day' END;
    v_note := r.reason;
    IF r.portion <> 'full' THEN
      v_note := r.reason || CASE WHEN r.portion = 'first_half'
                                 THEN ' (first half)' ELSE ' (second half)' END;
    END IF;

    PERFORM hr_attendance_apply_override(
      r.employee_id, v_one, v_day.branch_id, v_status, r.type,
      v_day.first_in, v_day.last_out, v_day.worked_minutes,
      v_note, p_decider_user_id, p_decider_name);
  END LOOP;

  v_first := v_before -> (v_days[1]::text);
  UPDATE hr_ess_leave_requests
     SET status = 'approved', decided_by_employee_id = p_decider_employee_id,
         decided_by_user_id = p_decider_user_id, decided_by_name = p_decider_name,
         decided_at = p_now, decision_note = NULLIF(btrim(p_note), ''),
         day_before = CASE WHEN jsonb_typeof(v_first) = 'object' THEN v_first END,
         days_before = v_before,
         working_days = to_jsonb(v_days),
         day_count = v_units,
         day_written_at = p_now,
         updated_at = p_now
   WHERE id = r.id
   RETURNING * INTO r;
  INSERT INTO hr_ess_leave_request_history
    (request_id, at, actor_employee_id, actor_user_id, actor_name, action, note, details)
  VALUES
    (r.id, p_now, p_decider_employee_id, p_decider_user_id, p_decider_name, 'approved',
     NULLIF(btrim(p_note), ''),
     jsonb_build_object('type', r.type, 'day', r.day, 'end_day', r.end_day,
                        'portion', r.portion, 'day_count', v_units,
                        'days_written', to_jsonb(v_days)));
  RETURN jsonb_build_object(
    'outcome', 'approved', 'request', to_jsonb(r),
    'day_written', true, 'days_written', to_jsonb(v_days));
END $$;

/* ── withdraw: unchanged for the employee, the history now names the range ── */
CREATE OR REPLACE FUNCTION public.hr_ess_withdraw_leave_request(
  p_request_id  uuid,
  p_employee_id uuid,
  p_now         timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  r hr_ess_leave_requests;
BEGIN
  SELECT * INTO r FROM hr_ess_leave_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND OR r.employee_id <> p_employee_id THEN
    RETURN jsonb_build_object('outcome', 'not_found');
  END IF;
  IF r.status <> 'pending' THEN
    RETURN jsonb_build_object('outcome', 'not_pending', 'request', to_jsonb(r));
  END IF;
  UPDATE hr_ess_leave_requests
     SET status = 'withdrawn', updated_at = p_now
   WHERE id = r.id
   RETURNING * INTO r;
  INSERT INTO hr_ess_leave_request_history
    (request_id, at, actor_employee_id, actor_name, action, details)
  VALUES
    (r.id, p_now, r.employee_id, (SELECT full_name FROM hr_employees WHERE id = r.employee_id),
     'withdrawn', jsonb_build_object('type', r.type, 'day', r.day, 'end_day', r.end_day,
                                     'portion', r.portion, 'day_count', r.day_count));
  RETURN jsonb_build_object('outcome', 'withdrawn', 'request', to_jsonb(r));
END $$;

/* ── cancel: restore every day the approval wrote ── */
CREATE OR REPLACE FUNCTION public.hr_ess_cancel_leave_request(
  p_request_id  uuid,
  p_by_employee_id uuid,
  p_by_user_id  uuid,
  p_by_name     text,
  p_reason      text,
  p_now         timestamptz
)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
DECLARE
  r            hr_ess_leave_requests;
  v_key        text;
  v_before     jsonb;
  v_cur        hr_staff_attendance;
BEGIN
  SELECT * INTO r FROM hr_ess_leave_requests WHERE id = p_request_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('outcome', 'not_found'); END IF;
  IF r.status <> 'approved' THEN
    RETURN jsonb_build_object('outcome', 'not_approved', 'request', to_jsonb(r));
  END IF;

  IF r.days_before IS NULL OR r.days_before = '{}'::jsonb THEN
    -- A request approved before this migration: the single day the old cancel restored.
    IF r.day_before IS NULL THEN
      DELETE FROM hr_staff_attendance WHERE employee_id = r.employee_id AND day = r.day;
    ELSE
      UPDATE hr_staff_attendance
         SET status = r.day_before ->> 'status',
             leave_type = r.day_before ->> 'leave_type',
             note = r.day_before ->> 'note',
             source = r.day_before ->> 'source',
             first_in = (r.day_before ->> 'first_in')::timestamptz,
             last_out = (r.day_before ->> 'last_out')::timestamptz,
             worked_minutes = (r.day_before ->> 'worked_minutes')::integer,
             marked_by = (r.day_before ->> 'marked_by')::uuid,
             marked_by_name = r.day_before ->> 'marked_by_name',
             marked_at = (r.day_before ->> 'marked_at')::timestamptz,
             updated_at = p_now
       WHERE employee_id = r.employee_id AND day = r.day;
    END IF;
  ELSE
    FOR v_key, v_before IN SELECT * FROM jsonb_each(r.days_before) LOOP
      SELECT * INTO v_cur FROM hr_staff_attendance
       WHERE employee_id = r.employee_id AND day = v_key::date
       FOR UPDATE;
      CONTINUE WHEN NOT FOUND;

      -- Somebody changed the day after the approval: leave their change alone. WFH writes a
      -- present day with no leave_type, so it is restored from days_before without this test.
      CONTINUE WHEN r.type <> 'wfh'
                 AND (v_cur.leave_type IS DISTINCT FROM r.type
                      OR v_cur.status NOT IN ('leave', 'half_day'));

      IF v_before IS NULL OR v_before = 'null'::jsonb THEN
        IF v_cur.first_in IS NULL AND v_cur.last_out IS NULL THEN
          DELETE FROM hr_staff_attendance WHERE id = v_cur.id;
        ELSE
          -- The half-day leave let the person punch: keep the punches, drop the leave.
          UPDATE hr_staff_attendance
             SET status = CASE WHEN COALESCE(v_cur.worked_minutes, 0) >= 240
                               THEN 'present' ELSE 'half_day' END,
                 leave_type = NULL, note = NULL, source = 'self_punch',
                 updated_at = p_now
           WHERE id = v_cur.id;
        END IF;
      ELSE
        UPDATE hr_staff_attendance
           SET status = v_before ->> 'status',
               leave_type = v_before ->> 'leave_type',
               note = v_before ->> 'note',
               source = v_before ->> 'source',
               first_in = (v_before ->> 'first_in')::timestamptz,
               last_out = (v_before ->> 'last_out')::timestamptz,
               worked_minutes = (v_before ->> 'worked_minutes')::integer,
               marked_by = (v_before ->> 'marked_by')::uuid,
               marked_by_name = v_before ->> 'marked_by_name',
               marked_at = (v_before ->> 'marked_at')::timestamptz,
               updated_at = p_now
         WHERE id = v_cur.id;
      END IF;
    END LOOP;
  END IF;

  UPDATE hr_ess_leave_requests
     SET status = 'cancelled', cancelled_by_user_id = p_by_user_id, cancelled_by_name = p_by_name,
         cancelled_at = p_now, cancel_reason = btrim(p_reason), updated_at = p_now
   WHERE id = r.id
   RETURNING * INTO r;
  INSERT INTO hr_ess_leave_request_history
    (request_id, at, actor_employee_id, actor_user_id, actor_name, action, note, details)
  VALUES
    (r.id, p_now, p_by_employee_id, p_by_user_id, p_by_name, 'cancelled', btrim(p_reason),
     jsonb_build_object('type', r.type, 'day', r.day, 'end_day', r.end_day,
                        'portion', r.portion, 'day_count', r.day_count, 'day_restored', true));
  RETURN jsonb_build_object('outcome', 'cancelled', 'request', to_jsonb(r), 'day_restored', true);
END $$;

/* ── function access: service role only, as every function here ── */
REVOKE EXECUTE ON FUNCTION public.hr_ess_leave_working_days(uuid, date, date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_leave_cl_units(uuid, date) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_leave_cl_limit() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_withdraw_leave_request(uuid, uuid, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_cancel_leave_request(uuid, uuid, uuid, text, text, timestamptz) FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION public.hr_ess_leave_working_days(uuid, date, date) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_leave_cl_units(uuid, date) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_leave_cl_limit() FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_withdraw_leave_request(uuid, uuid, timestamptz) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_cancel_leave_request(uuid, uuid, uuid, text, text, timestamptz) FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE EXECUTE ON FUNCTION public.hr_ess_leave_working_days(uuid, date, date) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_leave_cl_units(uuid, date) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_leave_cl_limit() FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_withdraw_leave_request(uuid, uuid, timestamptz) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_cancel_leave_request(uuid, uuid, uuid, text, text, timestamptz) FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION public.hr_ess_leave_working_days(uuid, date, date) TO service_role;
    GRANT EXECUTE ON FUNCTION public.hr_ess_leave_cl_units(uuid, date) TO service_role;
    GRANT EXECUTE ON FUNCTION public.hr_ess_leave_cl_limit() TO service_role;
    GRANT EXECUTE ON FUNCTION public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz) TO service_role;
    GRANT EXECUTE ON FUNCTION public.hr_ess_withdraw_leave_request(uuid, uuid, timestamptz) TO service_role;
    GRANT EXECUTE ON FUNCTION public.hr_ess_cancel_leave_request(uuid, uuid, uuid, text, text, timestamptz) TO service_role;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
