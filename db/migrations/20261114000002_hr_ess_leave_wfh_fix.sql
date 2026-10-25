-- Team RVM (ESS): keep work-from-home exactly as it was under the range rules.
--
-- 20261114000001 made every leave request compute working days and made cancel restore only
-- rows whose leave_type matched the request. WFH is written as a PRESENT day with no leave_type,
-- so both changes were wrong for it:
--
--   * a WFH request on a weekly off or holiday was refused as DAY_OFF. WFH is work, and the old
--     flow wrote it on any day. It is one day again, written as before.
--   * cancelling an approved WFH restored nothing. It now restores its days_before like any other.
--
-- Run after 20261114000001. Safe to run twice.

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

  IF r.type = 'cl' THEN
    PERFORM pg_advisory_xact_lock(
      hashtextextended('hr_ess_leave_cl:' || r.employee_id::text || ':'
                       || date_trunc('month', r.day::timestamp)::date::text, 0));
    SELECT hr_ess_leave_cl_units(r.employee_id, r.day) INTO v_taken;
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

    IF r.type = 'wfh' THEN
      v_status := 'present';
      v_note := 'Work from home: ' || r.reason;
    ELSE
      v_status := CASE WHEN r.portion = 'full' THEN 'leave' ELSE 'half_day' END;
      v_note := r.reason;
      IF r.portion <> 'full' THEN
        v_note := r.reason || CASE WHEN r.portion = 'first_half'
                                   THEN ' (first half)' ELSE ' (second half)' END;
      END IF;
    END IF;

    PERFORM hr_attendance_apply_override(
      r.employee_id, v_one, v_day.branch_id, v_status,
      CASE WHEN r.type = 'wfh' THEN NULL ELSE r.type END,
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

      CONTINUE WHEN r.type <> 'wfh'
                 AND (v_cur.leave_type IS DISTINCT FROM r.type
                      OR v_cur.status NOT IN ('leave', 'half_day'));

      IF v_before IS NULL OR v_before = 'null'::jsonb THEN
        IF v_cur.first_in IS NULL AND v_cur.last_out IS NULL THEN
          DELETE FROM hr_staff_attendance WHERE id = v_cur.id;
        ELSE
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

REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.hr_ess_cancel_leave_request(uuid, uuid, uuid, text, text, timestamptz) FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz) FROM anon;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_cancel_leave_request(uuid, uuid, uuid, text, text, timestamptz) FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE EXECUTE ON FUNCTION public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz) FROM authenticated;
    REVOKE EXECUTE ON FUNCTION public.hr_ess_cancel_leave_request(uuid, uuid, uuid, text, text, timestamptz) FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz) TO service_role;
    GRANT EXECUTE ON FUNCTION public.hr_ess_cancel_leave_request(uuid, uuid, uuid, text, text, timestamptz) TO service_role;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
