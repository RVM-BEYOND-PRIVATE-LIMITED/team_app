-- Team RVM (ESS): the colleague profile's social fields and work experience (issue #31, KP 27 Oct 2026).
--
-- Two new hr_ess_* tables and the replace function, and nothing else:
--
--   hr_ess_work_experience   the owner's own history, replaced as a whole by PUT
--                            /api/ess/me/work-experience. company and role_title are 1 to 200
--                            characters after trimming; from_date is required; to_date may be
--                            omitted for a past role; is_current means "no end date"; is_visible
--                            hides an entry from colleagues without deleting it.
--
--   hr_ess_profile_details   one row per employee: about (up to 1,000), likes and dislikes (up to
--                            500 each), and anniversary_date, a personal date separate from the
--                            work anniversary derived from hr_employees.date_of_joining. The blood
--                            group stays in hr_ess_personal_details.
--
-- Both are the ESS's own tables (ADR-0021): RLS on with no policy, and only service_role may read
-- or write them. No Scheduler table is altered (ADR-0018).
--
-- Safe to run twice: every object is CREATE ... IF NOT EXISTS and every grant is idempotent.
--
-- Rollback: db/rollbacks/20261115000001_hr_ess_profile_and_experience.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_work_experience (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id  uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  company      text NOT NULL CHECK (length(btrim(company)) BETWEEN 1 AND 200),
  role_title   text NOT NULL CHECK (length(btrim(role_title)) BETWEEN 1 AND 200),
  from_date    date NOT NULL,
  to_date      date,
  is_current   boolean NOT NULL DEFAULT false,
  location     text CHECK (location IS NULL OR length(btrim(location)) BETWEEN 1 AND 200),
  description  text CHECK (description IS NULL OR length(btrim(description)) BETWEEN 1 AND 1000),
  is_visible   boolean NOT NULL DEFAULT true,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hr_ess_work_experience_dates_chk CHECK (to_date IS NULL OR to_date >= from_date),
  CONSTRAINT hr_ess_work_experience_current_chk CHECK (is_current = false OR to_date IS NULL)
);

CREATE INDEX IF NOT EXISTS hr_ess_work_experience_employee_idx
  ON public.hr_ess_work_experience (employee_id, from_date DESC, created_at DESC);

CREATE TABLE IF NOT EXISTS public.hr_ess_profile_details (
  employee_id          uuid PRIMARY KEY REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  about                text CHECK (about IS NULL OR length(btrim(about)) BETWEEN 1 AND 1000),
  likes                text CHECK (likes IS NULL OR length(btrim(likes)) BETWEEN 1 AND 500),
  dislikes             text CHECK (dislikes IS NULL OR length(btrim(dislikes)) BETWEEN 1 AND 500),
  anniversary_date     date,
  updated_at           timestamptz NOT NULL DEFAULT now(),
  updated_by_user_id   uuid REFERENCES public.users(id) ON DELETE SET NULL
);

ALTER TABLE public.hr_ess_work_experience ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_ess_profile_details ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_work_experience FROM anon;
    REVOKE ALL ON TABLE public.hr_ess_profile_details FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_work_experience FROM authenticated;
    REVOKE ALL ON TABLE public.hr_ess_profile_details FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_ess_work_experience TO service_role;
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_ess_profile_details TO service_role;
  END IF;
END
$$;

-- PUT /me/work-experience replaces the whole list in one transaction: the delete and the insert
-- cannot leave somebody with half a history if the second half fails. The route has already
-- validated every field; the table's CHECKs remain the backstop.
CREATE OR REPLACE FUNCTION public.hr_ess_replace_work_experience(
  p_employee_id uuid,
  p_entries     jsonb
)
RETURNS SETOF public.hr_ess_work_experience
LANGUAGE plpgsql
SET search_path = public, pg_temp
AS $$
BEGIN
  DELETE FROM public.hr_ess_work_experience WHERE employee_id = p_employee_id;
  RETURN QUERY
    INSERT INTO public.hr_ess_work_experience
      (employee_id, company, role_title, from_date, to_date, is_current, location, description, is_visible)
    SELECT p_employee_id,
           e->>'company',
           e->>'role_title',
           (e->>'from_date')::date,
           NULLIF(e->>'to_date', '')::date,
           COALESCE((e->>'is_current')::boolean, false),
           NULLIF(e->>'location', ''),
           NULLIF(e->>'description', ''),
           COALESCE((e->>'is_visible')::boolean, true)
      FROM jsonb_array_elements(p_entries) WITH ORDINALITY AS x(e, ord)
     ORDER BY ord
    RETURNING *;
END
$$;

REVOKE EXECUTE ON FUNCTION public.hr_ess_replace_work_experience(uuid, jsonb) FROM PUBLIC;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE EXECUTE ON FUNCTION public.hr_ess_replace_work_experience(uuid, jsonb) FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE EXECUTE ON FUNCTION public.hr_ess_replace_work_experience(uuid, jsonb) FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT EXECUTE ON FUNCTION public.hr_ess_replace_work_experience(uuid, jsonb) TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
