-- Verbatim live pg_get_functiondef('public.rpc_generate_results(uuid)'), captured 2026-09-17.
-- Baseline for migrations/R4_HOTFIX_submit_autosubmit_batch_reuse.sql STEP 3. Do not edit.
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

  -- If an unfinished batch already exists, return it.
  SELECT *
  INTO v_batch
  FROM public.result_batches
  WHERE test_id = p_test_id
    AND status IN (
      'pending'::public.batch_status,
      'processing'::public.batch_status
    )
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
