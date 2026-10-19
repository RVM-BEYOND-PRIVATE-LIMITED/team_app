-- Team RVM (ESS): My Documents (Phase 2C, KP 1 and KP 2).
--
-- A person uploads their own documents -- resume, identity proof, certificates, the offer and
-- joining papers, experience and exit letters -- and HR reads them from the same record. The
-- files live in the ESS's private bucket (KP, 19 Oct 2026) under `documents/`, exactly as the
-- Wall's attachments do; the row keeps the path and the facts, never the bytes.
--
-- The types are FIXED in code (policy/documents.js) and seeded by this migration from that list
-- (KP, 19 Oct 2026), exactly as the Helpdesk's categories are. Two build decisions flagged for KP:
--   `others`     an ESS-only type for anything the list does not name; it REQUIRES a free-text
--                remark saying what the file is, so HR is never handed a mystery file;
--   `identity`   the gated one: only HR (the manager role), the CEO and super admins may open
--                one (KP 2: an HR Executive must not), and every opening is audited. The list
--                rules live in one place, src/policy/documents.js IDENTITY_ROLES.
-- Which types are mandatory (the weekly reminder job asks for them) is carried on the type row,
-- so KP can turn one off with one UPDATE.
--
-- No Aadhaar number is ever stored: the row is the file and what it is, nothing more.
--
-- New tables only (ADR-0021). Safe to run twice. Row-level security is on with no policy, so
-- only the service role (the ESS) can read or write.
--
-- Rollback: db/rollbacks/20261110000001_hr_ess_documents.sql

CREATE TABLE IF NOT EXISTS public.hr_ess_document_types (
  slug         text PRIMARY KEY,
  name         text NOT NULL CHECK (length(btrim(name)) BETWEEN 3 AND 120),
  -- The weekly job (src/jobs/documents.js) reminds for the mandatory ones only.
  is_mandatory boolean NOT NULL DEFAULT false,
  sort         integer NOT NULL DEFAULT 0,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- The types policy/documents.js lists. Safe to run twice: a re-run changes nothing.
INSERT INTO public.hr_ess_document_types (slug, name, is_mandatory, sort) VALUES
  ('resume',     'Resume',                     false, 10),
  ('identity',   'Identity document',          true,  20),
  ('certificate','Certificate',                false, 30),
  ('offer',      'Offer letter',               true,  40),
  ('joining',    'Joining letter',             true,  50),
  ('experience', 'Experience letter',          false, 60),
  ('exit',       'Exit letter',                false, 70),
  ('other',      'Other document',             false, 80),
  ('others',     'Other (say what it is)',     false, 90)
ON CONFLICT (slug) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.hr_ess_documents (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  employee_id       uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  doc_type          text NOT NULL REFERENCES public.hr_ess_document_types(slug),
  -- What the app shows as the file's name.
  file_name         text NOT NULL CHECK (length(btrim(file_name)) BETWEEN 1 AND 200),
  -- The ESS bucket path the row points at: documents/<employee_id>/<uuid>.<ext>.
  storage_path      text NOT NULL CHECK (length(btrim(storage_path)) BETWEEN 3 AND 500),
  content_type      text NOT NULL CHECK (length(btrim(content_type)) BETWEEN 3 AND 100),
  size_bytes        integer NOT NULL CHECK (size_bytes BETWEEN 1 AND 5 * 1024 * 1024),
  -- The free text `others` requires; any type may carry one.
  remark            text CHECK (remark IS NULL OR length(btrim(remark)) BETWEEN 3 AND 500),
  -- HR's read: pending until a reviewer answers it.
  status            text NOT NULL DEFAULT 'pending',
  verified_by_user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  verified_by_name  text,
  verified_at       timestamptz,
  -- Why a reviewer turned a document away; the employee sees it.
  rejection_reason  text CHECK (rejection_reason IS NULL OR length(btrim(rejection_reason)) BETWEEN 3 AND 500),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hr_ess_documents_status_chk CHECK (status IN ('pending', 'verified', 'rejected')),
  -- A verified document knows when; a rejected one says why.
  CONSTRAINT hr_ess_documents_review_chk CHECK (
    (status = 'verified') = (verified_at IS NOT NULL)
    AND (status = 'rejected') = (rejection_reason IS NOT NULL)
  ),
  -- The mystery-file rule: an `others` upload says what it is.
  CONSTRAINT hr_ess_documents_others_remark_chk CHECK (
    doc_type <> 'others' OR remark IS NOT NULL
  )
);

-- The person's own list, newest first.
CREATE INDEX IF NOT EXISTS hr_ess_documents_employee_idx
  ON public.hr_ess_documents (employee_id, created_at DESC);

ALTER TABLE public.hr_ess_document_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_ess_documents ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_document_types FROM anon;
    REVOKE ALL ON TABLE public.hr_ess_documents FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_document_types FROM authenticated;
    REVOKE ALL ON TABLE public.hr_ess_documents FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_ess_document_types TO service_role;
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.hr_ess_documents TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
