-- ============================================================
-- G11 — rpc_request_coach_reports  (STATUS: PROPOSED — NOT APPLIED LIVE)
-- ============================================================
-- Live facts (audited 2026-09-19): public.ai_jobs exists (type CHECK
-- 'gen_questions' | 'coach_reports', UNIQUE(idempotency_key), status
-- job_status default 'pending') but NO client policy (SELECT = false, no
-- INSERT) and NO function touches it; public.ai_reports (UNIQUE(test_id,
-- user_id), payload jsonb, model) is written only by the legacy web app's
-- inline Gemini call. rpc_generate_results scores attempts deterministically
-- into public.results and completes the test's single result_batches row —
-- no AI anywhere in the Flutter path.
--
-- This RPC is the minimal client entry point to the EXISTING queue: it
-- enqueues ONE coach_reports job per (test, batch), idempotently, after the
-- deterministic batch has finished. It never calls an AI provider; a worker
-- (out of G11 scope, e.g. an edge function / cron consumer of ai_jobs) is
-- expected to read pending jobs, call the model, upsert public.ai_reports
-- (test_id, user_id, batch_id, payload, model) and mark the job completed.
-- Reading stored reports needs no RPC (existing ai_reports RLS).
--
-- Authorization mirrors rpc_generate_results exactly: creator OR
-- fn_has_permission(group_id, uid, 'GENERATE_RESULTS') (owner via bypass).
-- SECURITY DEFINER because ai_jobs is closed to clients; search_path = '';
-- auth.uid() required; EXECUTE to authenticated only.
-- Rollback: DROP FUNCTION public.rpc_request_coach_reports(uuid);
-- ============================================================

CREATE OR REPLACE FUNCTION public.rpc_request_coach_reports(p_test_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_test public.tests%ROWTYPE;
  v_batch public.result_batches%ROWTYPE;
  v_key text;
  v_job public.ai_jobs%ROWTYPE;
  v_created boolean := false;
  v_reports integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT * INTO v_test
  FROM public.tests t
  WHERE t.id = p_test_id AND t.is_soft_deleted = false;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'TEST_NOT_FOUND';
  END IF;

  IF v_test.created_by <> v_uid THEN
    IF v_test.group_id IS NULL
       OR NOT public.fn_has_permission(v_test.group_id, v_uid, 'GENERATE_RESULTS'::public.app_permission) THEN
      RAISE EXCEPTION 'GENERATE_RESULTS_FORBIDDEN';
    END IF;
  END IF;

  -- Deterministic results must exist first (one batch per test, live UNIQUE).
  SELECT * INTO v_batch
  FROM public.result_batches b
  WHERE b.test_id = p_test_id;
  IF NOT FOUND
     OR v_batch.status NOT IN ('completed'::public.batch_status, 'partially_completed'::public.batch_status) THEN
    RAISE EXCEPTION 'RESULTS_NOT_GENERATED: run rpc_generate_results first';
  END IF;

  v_key := 'coach_reports:' || p_test_id::text || ':' || v_batch.id::text;

  INSERT INTO public.ai_jobs (type, test_id, result_batch_id, idempotency_key, payload)
  VALUES (
    'coach_reports',
    p_test_id,
    v_batch.id,
    v_key,
    jsonb_build_object('group_id', v_test.group_id, 'requested_by', v_uid, 'requested_at', now())
  )
  ON CONFLICT (idempotency_key) DO NOTHING
  RETURNING * INTO v_job;

  IF v_job.id IS NOT NULL THEN
    v_created := true;
  ELSE
    SELECT * INTO v_job FROM public.ai_jobs j WHERE j.idempotency_key = v_key;
  END IF;

  SELECT count(*) INTO v_reports FROM public.ai_reports r WHERE r.test_id = p_test_id;

  RETURN jsonb_build_object(
    'job_id', v_job.id,
    'status', v_job.status,
    'reports_done', v_reports,
    'reports_total', v_batch.reports_total,
    'created', v_created
  );
END;
$$;

REVOKE ALL ON FUNCTION public.rpc_request_coach_reports(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_request_coach_reports(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.rpc_request_coach_reports(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only; last statement)
-- Expected: fn_present=true | security_definer=true | search_path={search_path=} |
--           anon_can_execute=false | authenticated_can_execute=true
-- ------------------------------------------------------------
SELECT
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'rpc_request_coach_reports') AS fn_present,
  (SELECT p.prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'rpc_request_coach_reports') AS security_definer,
  (SELECT p.proconfig::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'rpc_request_coach_reports') AS search_path,
  has_function_privilege('anon', 'public.rpc_request_coach_reports(uuid)', 'EXECUTE') AS anon_can_execute,
  has_function_privilege('authenticated', 'public.rpc_request_coach_reports(uuid)', 'EXECUTE') AS authenticated_can_execute;
