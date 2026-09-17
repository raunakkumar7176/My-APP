-- ============================================================
-- R4 MIGRATION F — rpc_generate_results: batch reuse under UNIQUE(test_id)
-- ============================================================
-- Live bug (reproduced 2026-09-16): the function reuses only pending /
-- processing batches and otherwise INSERTs; a completed/failed batch for
-- the same test hits result_batches_test_id_key (23505).
--
-- Baseline: the VERBATIM live body (docs/live/rpc_generate_results.live.sql,
-- pg_get_functiondef captured 2026-09-17). Changes, and nothing else:
--   1. search_path stays 'public' (live value): validating the body under ''
--      raised 42P01 in the SQL Editor; every object is public.-qualified anyway.
--   2. Existing-batch lookup drops the pending/processing filter and locks
--      the single row for the test.
--   3. Behaviour per existing status:
--        pending / processing            -> return existing (reused = true)
--        completed / partially_completed -> return existing (reused = true);
--                                           never re-inserted, never re-scored
--        failed                          -> legitimate retry: the SAME row is
--                                           reset in place (pending, counters 0,
--                                           totals {}, completed_at NULL) and
--                                           reprocessed
--        no row                          -> INSERT the single batch (unchanged)
-- Authorization (creator or GENERATE_RESULTS via fn_has_permission), the
-- processing loop, per-attempt fn_score_attempt call + exception handling,
-- final status logic and the return JSON contract
-- {batch_id, test_id, status, reports_done, reports_total, errors, reused}
-- are byte-for-byte the live text. Signature unchanged -> CREATE OR REPLACE
-- keeps existing grants. No schema / constraint / RLS / fn_score_attempt change.
--
-- ------------------------------------------------------------
-- PREFLIGHT (read-only) — STOP if anything differs from "expect"
-- ------------------------------------------------------------
SELECT p.oid::regprocedure AS signature, pg_get_function_result(p.oid) AS returns,
       p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_generate_results';
-- expect exactly one row: rpc_generate_results(uuid) | jsonb | t | {search_path=public}

SELECT
  pg_get_functiondef(p.oid) ~ 'AND status IN \(\s*''pending''::public\.batch_status,\s*''processing''::public\.batch_status\s*\)' AS live_has_pending_only_lookup,
  pg_get_functiondef(p.oid) ~ 'GENERATE_RESULTS_FORBIDDEN'                        AS live_has_authorization,
  pg_get_functiondef(p.oid) ~ 'PERFORM public\.fn_score_attempt\(v_attempt\.id\)'  AS live_scores_via_fn_score_attempt,
  pg_get_functiondef(p.oid) ~ '''reused'', false'                                   AS live_returns_reused_flag,
  pg_get_functiondef(p.oid) ~ 'result_batches_test_id_key|ON CONFLICT'             AS live_already_handles_conflict_should_be_f
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_generate_results';
-- expect: t | t | t | t | f   (= the captured baseline; if the first is f the
-- function was changed since capture -> paste pg_get_functiondef and STOP)

SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid = 'public.result_batches'::regclass ORDER BY 1;
-- expect: result_batches_pkey PRIMARY KEY (id); result_batches_test_id_key UNIQUE (test_id)

SELECT grantee, privilege_type FROM information_schema.routine_privileges
WHERE routine_schema = 'public' AND routine_name = 'rpc_generate_results' ORDER BY 1;
-- note: expected authenticated EXECUTE (+ owner); re-checked in postflight

SELECT test_id, count(*) FROM public.result_batches GROUP BY test_id HAVING count(*) > 1;
-- expect: 0 rows

-- ------------------------------------------------------------
-- STEP 1 — replace the function (same signature)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_generate_results(p_test_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_test tests%ROWTYPE;
  v_batch result_batches%ROWTYPE;
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

  -- result_batches is UNIQUE (test_id): at most one row per test. Lock it.
  SELECT *
  INTO v_batch
  FROM public.result_batches
  WHERE test_id = p_test_id
  ORDER BY created_at DESC
  LIMIT 1
  FOR UPDATE;

  -- Reuse for every status except 'failed' (pending/processing: still
  -- running; completed/partially_completed: already produced — returned as-is
  -- with reused = true, never re-inserted, never re-scored here).
  IF v_batch.id IS NOT NULL AND v_batch.status <> 'failed'::public.batch_status THEN
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

  IF v_batch.id IS NOT NULL THEN
    -- Legitimate retry of a FAILED batch: reset the existing row in place
    -- (UNIQUE(test_id) forbids a second row) and reprocess below.
    UPDATE public.result_batches
    SET
      requested_by = v_user,
      status = 'pending'::public.batch_status,
      reports_done = 0,
      reports_total = v_total,
      totals = '{}'::jsonb,
      completed_at = NULL
    WHERE id = v_batch.id
    RETURNING *
    INTO v_batch;
  ELSE
    -- Create the single batch for this test.
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
  END IF;

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
-- POSTFLIGHT (read-only) — A..I
-- ------------------------------------------------------------
-- A/B/C/D: exists, signature, DEFINER, hardened search_path
SELECT p.oid::regprocedure AS signature, pg_get_function_result(p.oid) AS returns,
       p.prosecdef AS security_definer, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_generate_results';
-- expect exactly one row: rpc_generate_results(uuid) | jsonb | t | {search_path=public}

-- E/F/G: authorization intact; reuse instead of duplicate insert; failed reset in place
SELECT
  pg_get_functiondef(p.oid) ~ 'GENERATE_RESULTS_FORBIDDEN'                                   AS authorization_present,
  pg_get_functiondef(p.oid) ~ 'fn_has_permission\('                                          AS group_permission_check,
  pg_get_functiondef(p.oid) ~ 'AND status IN \(\s*''pending''::public\.batch_status'         AS old_pending_only_lookup_should_be_f,
  pg_get_functiondef(p.oid) ~ 'v_batch\.status <> ''failed''::public\.batch_status THEN'     AS reuses_all_but_failed,
  pg_get_functiondef(p.oid) ~ 'requested_by = v_user,\s+status = ''pending''::public\.batch_status,\s+reports_done = 0' AS failed_reset_in_place,
  (SELECT count(*) FROM regexp_matches(pg_get_functiondef(p.oid), 'INSERT INTO public\.result_batches', 'g')) AS insert_count_expect_1,
  pg_get_functiondef(p.oid) ~ 'PERFORM public\.fn_score_attempt\(v_attempt\.id\)'             AS scoring_path_unchanged,
  pg_get_functiondef(p.oid) ~ '''reused'', true'                                              AS reuse_branch_present
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_generate_results';
-- expect: t | t | f | t | t | 1 | t | t

-- H: only authenticated may call (the body then authorizes creator / GENERATE_RESULTS)
SELECT grantee, privilege_type FROM information_schema.routine_privileges
WHERE routine_schema = 'public' AND routine_name = 'rpc_generate_results' ORDER BY 1;
-- expect: identical to preflight (authenticated EXECUTE + owner; no anon / PUBLIC)

-- I: nothing else touched
SELECT conname, pg_get_constraintdef(oid) FROM pg_constraint
WHERE conrelid = 'public.result_batches'::regclass ORDER BY 1;                 -- unchanged
SELECT p.proname, pg_get_function_arguments(p.oid)
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN ('fn_score_attempt','fn_auto_submit','rpc_submit_attempt')
ORDER BY 1;                                                                    -- unchanged
SELECT test_id, count(*) FROM public.result_batches GROUP BY test_id HAVING count(*) > 1;  -- 0 rows

-- Behavioural (as the creator of a test that already has a COMPLETED batch,
-- e.g. 872907fc-49a9-41b2-9d4e-bad1d7e52e4c):
--   SELECT public.rpc_generate_results('<test>');   -- {..., "reused": true, "status": "completed"}, no 23505
--   SELECT public.rpc_generate_results('<test>');   -- same row again (idempotent)
--   SELECT count(*) FROM public.result_batches WHERE test_id = '<test>';   -- 1
