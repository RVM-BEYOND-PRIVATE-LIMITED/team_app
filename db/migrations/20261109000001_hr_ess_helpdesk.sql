-- Team RVM (ESS): the Helpdesk (Phase 2B, tasks G1 to G5).
--
-- The brief's Phase 2 helpdesk, as Phase 2B builds it: six ticket categories fixed from the
-- brief, each routed by portal role to the team that answers it; tickets numbered HD-0001
-- onwards; a thread of comments and of status events; a lifecycle of Open, In progress, On hold
-- (where the category allows it), Resolved and Closed with a reason; reopening within 7 days;
-- a rating of 1 to 5 at close; withdrawal of an open ticket. Nothing is ever deleted: a
-- withdrawn or closed ticket stays, and every status change is an 'event' row in the messages
-- table, so the thread is also the record.
--
-- The categories carry what G1 needs and what G3 needs:
--   queue_roles             the portal roles whose queue the ticket lands in. There is no
--                           branch-to-location link in the Scheduler, so the queue is not
--                           branch-filtered (KP decision 7 open; flagged in the README);
--   confidential            grievances and POSH: hidden from every list but their team's, and
--                           every read of one is audited;
--   allows_hold             whether the ticket may sit On hold (physical work can; paperwork
--                           cannot);
--   first_response_hours, resolution_hours  the SLA targets, in working hours, that the hourly
--                           job (src/jobs/helpdesk.js) judges overdue by.
-- The lab has no desk role and the Internal Committee has no login role, so lab tickets route to
-- the admin roles and POSH routes to HR; both are build decisions flagged for KP.
--
-- The non-ticket rows of the same table (leave, WFH, an attendance fix, an asset request) are
-- the brief's "not tickets": the category list links to the flows that already exist, and a
-- ticket can never be raised on one (is_ticket false).
--
-- The ref is 'HD-' + four digits from hr_ess_helpdesk_ticket_ref_seq: HD-0001 first. The
-- sequence is the numbering, so two tickets raised at once cannot take one number.
--
-- New tables only (ADR-0021). Safe to run twice. Row-level security is on with no policy, so
-- only the service role (the ESS) can read or write.
--
-- Rollback: db/rollbacks/20261109000001_hr_ess_helpdesk.sql

CREATE SEQUENCE IF NOT EXISTS public.hr_ess_helpdesk_ticket_ref_seq START 1;

CREATE TABLE IF NOT EXISTS public.hr_ess_helpdesk_categories (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug                  text NOT NULL UNIQUE,
  name                  text NOT NULL CHECK (length(btrim(name)) BETWEEN 3 AND 120),
  -- A ticket category is raisable; a non-ticket row is the link to a flow that is not a ticket
  -- (leave, WFH, an attendance fix, an asset request), and carries which one.
  is_ticket             boolean NOT NULL DEFAULT true,
  flow                  text CHECK (length(btrim(flow)) BETWEEN 1 AND 40),
  -- The portal roles whose queue the ticket lands in. Exact membership, as the Scheduler's
  -- allowRoles works: nothing inherits its way in.
  queue_roles           text[] NOT NULL DEFAULT '{}',
  confidential          boolean NOT NULL DEFAULT false,
  allows_hold           boolean NOT NULL DEFAULT false,
  priority              text NOT NULL DEFAULT 'medium',
  -- G3: the SLA targets in working hours. The build's defaults, for KP to confirm.
  first_response_hours  integer NOT NULL CHECK (first_response_hours BETWEEN 1 AND 24 * 30),
  resolution_hours      integer NOT NULL CHECK (resolution_hours BETWEEN 1 AND 24 * 90),
  is_active             boolean NOT NULL DEFAULT true,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hr_ess_helpdesk_categories_priority_chk CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
  CONSTRAINT hr_ess_helpdesk_categories_roles_chk CHECK (queue_roles <@ ARRAY[
    'ceo', 'super_admin', 'hoo', 'hod', 'hod_placement', 'admin_manager', 'admin',
    'accounts_admin', 'hr', 'hr_executive', 'faculty'
  ]::text[]),
  -- A non-ticket row names the flow it links to; a ticket category does not.
  CONSTRAINT hr_ess_helpdesk_categories_flow_chk CHECK (
    (is_ticket AND flow IS NULL) OR (NOT is_ticket AND flow IS NOT NULL)
  )
);

-- The six ticket categories of the brief, fixed (KP, 19 Oct 2026), and the four non-ticket rows
-- that link to the flows the app already has. Safe to run twice: a re-run changes nothing.
INSERT INTO public.hr_ess_helpdesk_categories
  (slug, name, is_ticket, flow, queue_roles, confidential, allows_hold, priority, first_response_hours, resolution_hours)
VALUES
  ('it_lab',       'IT and lab equipment',        true, NULL,        ARRAY['admin', 'admin_manager'], false, true,  'medium',  8, 48),
  ('facility',     'Facility and housekeeping',   true, NULL,        ARRAY['admin', 'admin_manager'], false, true,  'medium',  8, 48),
  ('hr_documents', 'HR and documents',            true, NULL,        ARRAY['hr', 'hr_executive'],     false, false, 'medium', 24, 72),
  ('payroll',      'Payroll and reimbursements',  true, NULL,        ARRAY['accounts_admin'],         false, false, 'high',   24, 72),
  ('grievance',    'Grievance',                   true, NULL,        ARRAY['hr'],                     true,  false, 'high',   12, 48),
  ('posh',         'POSH complaint',              true, NULL,        ARRAY['hr'],                     true,  false, 'urgent', 12, 72),
  ('leave_link',   'Leave',                       false, 'leave',    '{}',                            false, false, 'medium', 24, 72),
  ('wfh_link',     'Work from home',              false, 'wfh',      '{}',                            false, false, 'medium', 24, 72),
  ('attendance_fix_link', 'Attendance fix',       false, 'attendance_fix', '{}',                      false, false, 'medium', 24, 72),
  ('asset_link',   'Asset request',               false, 'assets',   '{}',                            false, false, 'medium', 24, 72)
ON CONFLICT (slug) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.hr_ess_helpdesk_tickets (
  id                      uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  -- HD-0001 onwards, from the sequence above.
  ref                     text NOT NULL DEFAULT 'HD-' || lpad(nextval('public.hr_ess_helpdesk_ticket_ref_seq'::regclass)::text, 4, '0'),
  -- The raiser is recorded even on an anonymous ticket: anonymity hides them from the team that
  -- answers, never from the record, and HR still sees who it was.
  created_by              uuid NOT NULL REFERENCES public.hr_employees(id) ON DELETE CASCADE,
  category_id             uuid NOT NULL REFERENCES public.hr_ess_helpdesk_categories(id),
  -- The category sets it at raise, and the row keeps what it was set to.
  priority                text NOT NULL,
  subject                 text NOT NULL CHECK (length(btrim(subject)) BETWEEN 3 AND 200),
  body                    text NOT NULL CHECK (length(btrim(body)) BETWEEN 3 AND 2000),
  -- Files attached when the ticket was raised, as on the Wall: [{ path, name }], ESS bucket.
  attachments             jsonb NOT NULL DEFAULT '[]'::jsonb CHECK (jsonb_typeof(attachments) = 'array'),
  anonymous               boolean NOT NULL DEFAULT false,
  -- The raiser's branch at raise, kept for the working-hours calendar (G3) and the record.
  branch_id               uuid REFERENCES public.hr_branches(id) ON DELETE SET NULL,
  status                  text NOT NULL DEFAULT 'open',
  -- The team member who claimed it. Assign and reassign are not built (decision 7 open): a
  -- claim is the only way a ticket gets an assignee.
  assignee_id             uuid REFERENCES public.hr_employees(id) ON DELETE SET NULL,
  claimed_at              timestamptz,
  first_response_at       timestamptz,
  -- G3: the two deadlines in working hours, worked out from the calendar when the ticket was
  -- raised and stored, so the job judges them against the clock, not the calendar again.
  first_response_due_at   timestamptz NOT NULL,
  resolution_due_at       timestamptz NOT NULL,
  resolved_at             timestamptz,
  closed_at               timestamptz,
  closed_by_employee_id   uuid REFERENCES public.hr_employees(id) ON DELETE SET NULL,
  closing_reason          text CHECK (closing_reason IS NULL OR length(btrim(closing_reason)) BETWEEN 3 AND 280),
  -- The raiser's rating of the answer, 1 to 5, at close only.
  rating                  integer CHECK (rating BETWEEN 1 AND 5),
  reopened_at             timestamptz,
  -- G3's escalation: 0 none, 1 the category's team told the first response is overdue,
  -- 2 the HoO told it is unresolved, 3 the CEO told. One notification per stage.
  escalation_level        integer NOT NULL DEFAULT 0 CHECK (escalation_level BETWEEN 0 AND 3),
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hr_ess_helpdesk_tickets_status_chk CHECK (status IN (
    'open', 'in_progress', 'on_hold', 'resolved', 'closed', 'withdrawn'
  )),
  CONSTRAINT hr_ess_helpdesk_tickets_priority_chk CHECK (priority IN ('low', 'medium', 'high', 'urgent')),
  -- A closed ticket knows when and why it closed; a resolved one knows when; a rating only
  -- stands on a closed ticket; an assignee has a claim stamp.
  CONSTRAINT hr_ess_helpdesk_tickets_state_chk CHECK (
    (status = 'closed') = (closed_at IS NOT NULL AND closing_reason IS NOT NULL)
    AND (status = 'resolved') = (resolved_at IS NOT NULL)
    AND (rating IS NULL OR status = 'closed')
    AND (assignee_id IS NULL OR claimed_at IS NOT NULL)
  )
);

CREATE UNIQUE INDEX IF NOT EXISTS hr_ess_helpdesk_tickets_ref_key
  ON public.hr_ess_helpdesk_tickets (ref);
-- The raiser's own list.
CREATE INDEX IF NOT EXISTS hr_ess_helpdesk_tickets_raiser_idx
  ON public.hr_ess_helpdesk_tickets (created_by, created_at DESC);
-- The job's walk: the tickets still being worked, with their deadlines.
CREATE INDEX IF NOT EXISTS hr_ess_helpdesk_tickets_active_idx
  ON public.hr_ess_helpdesk_tickets (first_response_due_at)
  WHERE status IN ('open', 'in_progress', 'on_hold');
CREATE INDEX IF NOT EXISTS hr_ess_helpdesk_tickets_resolution_idx
  ON public.hr_ess_helpdesk_tickets (resolution_due_at)
  WHERE status IN ('open', 'in_progress', 'on_hold');
CREATE INDEX IF NOT EXISTS hr_ess_helpdesk_tickets_category_idx
  ON public.hr_ess_helpdesk_tickets (category_id, created_at DESC);

-- The thread: the comments people write, and the 'event' rows the server writes as the ticket
-- moves. Nothing is deleted, so the thread is also the ticket's record (the brief).
CREATE TABLE IF NOT EXISTS public.hr_ess_helpdesk_messages (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id     uuid NOT NULL REFERENCES public.hr_ess_helpdesk_tickets(id) ON DELETE CASCADE,
  -- The author of a comment; NULL for an event the server wrote.
  employee_id   uuid REFERENCES public.hr_employees(id) ON DELETE SET NULL,
  kind          text NOT NULL DEFAULT 'comment',
  body          text CHECK (length(btrim(body)) BETWEEN 1 AND 2000),
  -- What happened, for an event row: opened, claimed, status_changed, withdrawn, closed,
  -- reopened. The details carry the from and to statuses, the reason and the rating.
  event         text CHECK (length(btrim(event)) BETWEEN 1 AND 60),
  details       jsonb NOT NULL DEFAULT '{}'::jsonb CHECK (jsonb_typeof(details) = 'object'),
  created_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT hr_ess_helpdesk_messages_kind_chk CHECK (kind IN ('comment', 'event')),
  CONSTRAINT hr_ess_helpdesk_messages_shape_chk CHECK (
    (kind = 'comment' AND body IS NOT NULL AND event IS NULL)
    OR (kind = 'event' AND body IS NULL AND event IS NOT NULL)
  )
);

CREATE INDEX IF NOT EXISTS hr_ess_helpdesk_messages_ticket_idx
  ON public.hr_ess_helpdesk_messages (ticket_id, created_at);

ALTER TABLE public.hr_ess_helpdesk_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_ess_helpdesk_tickets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.hr_ess_helpdesk_messages ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN
    REVOKE ALL ON TABLE public.hr_ess_helpdesk_categories FROM anon;
    REVOKE ALL ON TABLE public.hr_ess_helpdesk_tickets FROM anon;
    REVOKE ALL ON TABLE public.hr_ess_helpdesk_messages FROM anon;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN
    REVOKE ALL ON TABLE public.hr_ess_helpdesk_categories FROM authenticated;
    REVOKE ALL ON TABLE public.hr_ess_helpdesk_tickets FROM authenticated;
    REVOKE ALL ON TABLE public.hr_ess_helpdesk_messages FROM authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_helpdesk_categories TO service_role;
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_helpdesk_tickets TO service_role;
    GRANT SELECT, INSERT, UPDATE ON TABLE public.hr_ess_helpdesk_messages TO service_role;
  END IF;
END
$$;

NOTIFY pgrst, 'reload schema';
