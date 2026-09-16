-- ============================================================
-- R4 BACKEND HOTFIX (live-evidence only, 2026-09-17)
--   1. rpc_submit_attempt      — 42804 enum cast in CASE
--   2. fn_auto_submit(uuid)    — missing helper called by rpc_save_answers
--   3. rpc_generate_results    — duplicate result_batches (UNIQUE test_id)
-- ============================================================
-- Nothing else is touched: no schema, RLS, grants on existing objects,
-- fn_score_attempt, rpc_save_answers, results/attempts/answers tables.
-- Run in the Supabase SQL Editor top to bottom; read the preflight output
-- before continuing past it.
--
-- ------------------------------------------------------------
-- PREFLIGHT (read-only) — expected results in comments
-- ------------------------------------------------------------
SELECT p.proname,
       pg_get_function_arguments(p.oid) AS args,
       pg_get_function_result(p.oid)    AS returns,
       p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('rpc_submit_attempt', 'fn_auto_submit', 'rpc_generate_results', 'fn_score_attempt')
ORDER BY p.proname;
-- expect: rpc_submit_attempt(p_attempt uuid, p_auto boolean DEFAULT false) void, definer, search_path=public
--         rpc_generate_results(p_test_id uuid) jsonb, definer, search_path=public
--         fn_score_attempt(uuid) void
--         fn_auto_submit: NO ROW (if a row exists, STOP and report — do not run STEP 2 blindly)

SELECT conname, contype, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid = 'public.result_batches'::regclass
ORDER BY conname;
-- expect: result_batches_pkey PRIMARY KEY (id); result_batches_test_id_key UNIQUE (test_id)

-- ------------------------------------------------------------
-- STEP 1 — rpc_submit_attempt: cast the CASE branches (ONLY change)
-- ------------------------------------------------------------
-- Why: `CASE WHEN p_auto THEN 'auto_submitted' ELSE 'submitted' END`
-- resolves to text (two untyped literals), and there is no text -> enum
-- assignment cast, so `SET status = ...` raises 42804 (proven live, 4x).
-- Body otherwise verbatim: signature/default/void, DEFINER, search_path
-- 'public', ownership check, in_progress early return, submitted_at,
-- fn_score_attempt call.
CREATE OR REPLACE FUNCTION public.rpc_submit_attempt(p_attempt uuid, p_auto boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare a attempts;
begin
  select * into a from attempts where id = p_attempt and user_id = auth.uid() for update;
  if a.id is null then raise exception 'ATTEMPT_NOT_FOUND'; end if;
  if a.status <> 'in_progress' then return; end if;
  update attempts
  set status = case
                 when p_auto then 'auto_submitted'::public.attempt_status
                 else 'submitted'::public.attempt_status
               end,
      submitted_at = now()
  where id = p_attempt;
  perform fn_score_attempt(p_attempt);
end $function$;

-- ------------------------------------------------------------
-- STEP 2 — fn_auto_submit(uuid): the internal helper rpc_save_answers
--          already calls (`PERFORM public.fn_auto_submit(a.id)` on the
--          `now() > a.deadline_at` branch) but which does not exist (42883).
-- ------------------------------------------------------------
-- Why this shape: it is the p_auto = true path of rpc_submit_attempt
-- without the auth.uid() ownership check — the only caller is DEFINER code
-- that has already verified auth, ownership, FOR UPDATE and in_progress.
-- Idempotent: any status other than in_progress returns without touching
-- the row, so an attempt is never re-submitted or double-scored
-- (fn_score_attempt itself also inserts results ON CONFLICT DO NOTHING).
-- search_path '' => every reference fully qualified.
CREATE OR REPLACE FUNCTION public.fn_auto_submit(p_attempt uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  a public.attempts;
BEGIN
  SELECT *
    INTO a
    FROM public.attempts
   WHERE id = p_attempt
     FOR UPDATE;

  IF a.id IS NULL THEN
    RAISE EXCEPTION 'ATTEMPT_NOT_FOUND';
  END IF;

  IF a.status <> 'in_progress'::public.attempt_status THEN
    RETURN;
  END IF;

  UPDATE public.attempts
     SET status       = 'auto_submitted'::public.attempt_status,
         submitted_at = now()
   WHERE id = p_attempt;

  PERFORM public.fn_score_attempt(p_attempt);
END
$function$;

-- Internal only: never client-callable. DEFINER callers (rpc_save_answers)
-- execute as the function owner, so no client grant is needed.
REVOKE ALL ON FUNCTION public.fn_auto_submit(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_auto_submit(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.fn_auto_submit(uuid) FROM authenticated;

-- ------------------------------------------------------------
-- STEP 3 — rpc_generate_results: reuse ANY existing batch for the test
-- ------------------------------------------------------------
-- Why: result_batches has UNIQUE (test_id) — exactly one batch per test —
-- but the live body only reuses pending/processing batches and otherwise
-- INSERTs, so a test whose batch is completed/failed hits
-- result_batches_test_id_key (proven live: batch 8c282e91…, status completed).
--
-- Baseline: verbatim live pg_get_functiondef (docs/live/rpc_generate_results.live.sql).
-- ONLY change: the existing-batch lookup drops
--     AND status IN ('pending'::public.batch_status, 'processing'::public.batch_status)
-- so any row for test_id is returned unchanged via the existing reuse block
-- (reused = true, errors = 0, no INSERT, no processing). When no row exists
-- the processing logic runs exactly as before. Signature, return contract,
-- authorization, loop, exception handling, final status and final RETURN
-- are untouched.
CREATE OR REPLACE FUNCTION public.rpc_generate_results(p_test_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_test public.tests;
  v_batch public.result_batches;
  v_attempt record;
  v_total integer := 0;
  v_done integer := 0;
  v_errors integer := 0;
  v_error_message text := null;
BEGIN
  -- Authentication
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  -- Lock the test row so concurrent batch triggers cannot race
  SELECT *
  INTO v_test
  FROM public.tests
  WHERE id = p_test_id
    AND is_soft_deleted = false
  FOR UPDATE;

  IF v_test.id IS NULL THEN
    RAISE EXCEPTION 'TEST_NOT_FOUND';
  END IF;

  -- Authorization:
  -- owner can always generate results
  -- group members need GENERATE_RESULTS permission
  IF v_test.created_by <> v_user THEN
    IF v_test.group_id IS NULL
       OR NOT public.fn_has_permission(
            v_test.group_id,
            v_user,
            'GENERATE_RESULTS'::public.app_permission
          )
    THEN
      RAISE EXCEPTION 'GENERATE_RESULTS_FORBIDDEN';
    END IF;
  END IF;

  -- Reuse ANY existing batch for this test (result_batches is UNIQUE (test_id):
  -- at most one row can exist, so a second INSERT is impossible). The row is
  -- returned unchanged; nothing is reset or reprocessed.
  SELECT *
  INTO v_batch
  FROM public.result_batches
  WHERE test_id = p_test_id
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  IF v_batch.id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'batch_id', v_batch.id,
      'test_id', v_batch.test_id,
      'status', v_batch.status,
      'reports_done', v_batch.reports_done,
      'reports_total', v_batch.reports_total,
      'errors', 0,
      'reused', true
    );
  END IF;

  -- Count attempts that are eligible for scoring.
  SELECT count(*)
  INTO v_total
  FROM public.attempts a
  WHERE a.test_id = p_test_id
    AND a.status IN (
      'submitted'::public.attempt_status,
      'auto_submitted'::public.attempt_status,
      'scored'::public.attempt_status
    );

  -- Create a new batch.
  INSERT INTO public.result_batches (
    test_id,
    requested_by,
    status,
    reports_done,
    reports_total,
    totals
  )
  VALUES (
    p_test_id,
    v_user,
    'pending'::public.batch_status,
    0,
    v_total,
    '{}'::jsonb
  )
  RETURNING *
  INTO v_batch;

  -- Move batch into processing.
  UPDATE public.result_batches
  SET status = 'processing'::public.batch_status
  WHERE id = v_batch.id;

  -- Process every eligible attempt independently.
  FOR v_attempt IN
    SELECT a.id
    FROM public.attempts a
    WHERE a.test_id = p_test_id
      AND a.status IN (
        'submitted'::public.attempt_status,
        'auto_submitted'::public.attempt_status,
        'scored'::public.attempt_status
      )
    ORDER BY a.started_at, a.id
  LOOP
    BEGIN
      PERFORM public.fn_score_attempt(v_attempt.id);
      v_done := v_done + 1;

      UPDATE public.result_batches
      SET reports_done = v_done
      WHERE id = v_batch.id;

    EXCEPTION WHEN OTHERS THEN
      v_errors := v_errors + 1;
      v_error_message := SQLERRM;

      UPDATE public.result_batches
      SET reports_done = v_done
      WHERE id = v_batch.id;
    END;
  END LOOP;

  -- Final batch state.
  IF v_errors = 0 THEN
    UPDATE public.result_batches
    SET
      status = 'completed'::public.batch_status,
      reports_done = v_done,
      totals = jsonb_build_object(
        'processed', v_done,
        'errors', 0
      ),
      completed_at = now()
    WHERE id = v_batch.id;

  ELSIF v_done > 0 THEN
    UPDATE public.result_batches
    SET
      status = 'partially_completed'::public.batch_status,
      reports_done = v_done,
      totals = jsonb_build_object(
        'processed', v_done,
        'errors', v_errors,
        'last_error', v_error_message
      ),
      completed_at = now()
    WHERE id = v_batch.id;

  ELSE
    UPDATE public.result_batches
    SET
      status = 'failed'::public.batch_status,
      reports_done = 0,
      totals = jsonb_build_object(
        'processed', 0,
        'errors', v_errors,
        'last_error', v_error_message
      ),
      completed_at = now()
    WHERE id = v_batch.id;
  END IF;

  SELECT *
  INTO v_batch
  FROM public.result_batches
  WHERE id = v_batch.id;

  RETURN jsonb_build_object(
    'batch_id', v_batch.id,
    'test_id', v_batch.test_id,
    'status', v_batch.status,
    'reports_done', v_batch.reports_done,
    'reports_total', v_batch.reports_total,
    'errors', v_errors,
    'reused', false
  );
END;
$function$;

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only)
-- ------------------------------------------------------------
SELECT p.proname,
       pg_get_function_arguments(p.oid) AS args,
       pg_get_function_result(p.oid)    AS returns,
       p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('rpc_submit_attempt', 'fn_auto_submit', 'rpc_generate_results')
ORDER BY p.proname;
-- expect: fn_auto_submit(p_attempt uuid) void, prosecdef = true, proconfig = {search_path=}

SELECT pg_get_functiondef('public.rpc_submit_attempt(uuid, boolean)'::regprocedure);
-- expect: both CASE branches end with ::public.attempt_status
SELECT pg_get_functiondef('public.fn_auto_submit(uuid)'::regprocedure);

SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN ('fn_auto_submit', 'rpc_submit_attempt', 'rpc_generate_results')
ORDER BY 1, 2;
-- expect: fn_auto_submit has NO anon/authenticated/PUBLIC row;
--         rpc_submit_attempt / rpc_generate_results grants unchanged from preflight

SELECT conname, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.result_batches'::regclass;
-- expect: unchanged (pkey + UNIQUE (test_id))

-- Behavioural check (as the attempt owner, on an in_progress attempt):
--   SELECT public.rpc_submit_attempt('<attempt-uuid>', false);
--   SELECT id, status, submitted_at FROM public.attempts WHERE id = '<attempt-uuid>';
--     -- expect status = scored (fn_score_attempt) and one results row
--   SELECT public.rpc_submit_attempt('<attempt-uuid>', false);   -- no-op (not in_progress)
