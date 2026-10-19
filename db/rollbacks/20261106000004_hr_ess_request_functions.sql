-- Rollback for db/migrations/20261106000004_hr_ess_request_functions.sql: drops the seven
-- functions it adds. Nothing the Scheduler owns is touched, and no table is dropped: the request
-- tables and their history stay, with every row and its status as it was. Only new decisions,
-- withdrawals and cancels stop working (the routes answer 503 MODULE_NOT_INSTALLED), and the
-- morning job stops writing on-duty days. Safe to run twice.

DROP FUNCTION IF EXISTS public.hr_ess_decide_attendance_request(uuid, uuid, uuid, text, boolean, text, timestamptz, integer);
DROP FUNCTION IF EXISTS public.hr_ess_decide_leave_request(uuid, uuid, uuid, text, boolean, text, timestamptz);
DROP FUNCTION IF EXISTS public.hr_ess_withdraw_attendance_request(uuid, uuid, timestamptz);
DROP FUNCTION IF EXISTS public.hr_ess_withdraw_leave_request(uuid, uuid, timestamptz);
DROP FUNCTION IF EXISTS public.hr_ess_cancel_attendance_request(uuid, uuid, uuid, text, text, timestamptz);
DROP FUNCTION IF EXISTS public.hr_ess_cancel_leave_request(uuid, uuid, uuid, text, text, timestamptz);
DROP FUNCTION IF EXISTS public.hr_ess_on_duty_apply(date, timestamptz);

NOTIFY pgrst, 'reload schema';
