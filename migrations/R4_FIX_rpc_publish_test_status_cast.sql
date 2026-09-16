-- ============================================================
-- R4 FIX — rpc_publish_test: unqualified enum cast under search_path ''
-- ============================================================
-- Live evidence (2026-09-16, Chrome run, Edit Test → Publish):
--   PostgrestException code=42704: type "test_status" does not exist
--
-- Cause: rpc_publish_test is declared with SET search_path TO '' (correct
-- for SECURITY DEFINER), but its final UPDATE casts with an unqualified
-- type name:
--     SET status = 'published'::test_status
-- With an empty search_path the enum must be schema-qualified. All earlier
-- validations pass first, which is why this only surfaced once every
-- question was approved.
--
-- Fix: qualify that one cast. No RLS, grants, schema, validation, question
-- or attempt logic changes.
--
-- STEP 1 (read-only) — confirm the live definition has the unqualified cast:
-- SELECT pg_get_functiondef('public.rpc_publish_test(uuid)'::regprocedure);
--
-- If the live body differs from the one below, apply ONLY this line change
-- to the live body instead of running STEP 2:
--     SET status = 'published'::public.test_status
--
-- STEP 2 — targeted replacement (R4_5_1 body + the single qualified cast).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_publish_test(p_test_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_test record;
  v_question_count integer;
  v_invalid_questions integer;
  v_ordinal_issues integer;
  v_duplicate_ordinals integer;
  v_syllabus_valid boolean;
BEGIN
  -- Auth check
  v_uid := public._fn_auth_uid();

  -- Load test
  SELECT * INTO v_test FROM public.tests t WHERE t.id = p_test_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TEST_NOT_FOUND';
  END IF;

  -- Permission check: only creator can publish
  IF v_test.created_by != v_uid THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Only test creator can publish';
  END IF;

  -- Lifecycle check: can only publish draft tests
  IF v_test.status::text != 'draft' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Can only publish draft tests. Current status: %', v_test.status;
  END IF;

  -- Validate title exists
  IF v_test.title IS NULL OR TRIM(v_test.title) = '' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: title is required for publishing';
  END IF;

  -- Validate duration
  IF v_test.duration_sec < 60 OR v_test.duration_sec > 21600 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Invalid duration_sec for publishing';
  END IF;

  -- Validate scoring
  IF v_test.marks_per_question <= 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: marks_per_question must be > 0';
  END IF;

  IF v_test.negative_marks < 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: negative_marks cannot be negative';
  END IF;

  -- Validate test_mode
  IF v_test.test_mode IS NOT NULL AND v_test.test_mode NOT IN ('self', 'live', 'group') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Invalid test_mode';
  END IF;

  -- Group test validation
  IF v_test.test_mode = 'group' AND v_test.group_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: group_id is required for group tests';
  END IF;

  -- Validate timing
  PERFORM public._fn_validate_test_timing(v_test.starts_at, v_test.ends_at);

  -- Validate max_participants
  IF v_test.max_participants IS NOT NULL AND (v_test.max_participants < 2 OR v_test.max_participants > 10000) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Invalid max_participants';
  END IF;

  -- Check at least one approved question exists
  SELECT COUNT(*) INTO v_question_count
  FROM public.questions q
  WHERE q.test_id = p_test_id
    AND q.status = 'approved';

  IF v_question_count = 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Test must have at least one approved question to publish';
  END IF;

  -- Check for non-approved questions (only 'approved' questions may be published)
  -- Archived questions are excluded from the count (they are intentionally hidden)
  -- Rejected/needs_revision/pending_review questions block publishing
  SELECT COUNT(*) INTO v_invalid_questions
  FROM public.questions q
  WHERE q.test_id = p_test_id
    AND q.status != 'approved'
    AND q.status != 'archived';

  IF v_invalid_questions > 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: % questions must be approved before publishing (pending_review/rejected/needs_revision not allowed)', v_invalid_questions;
  END IF;

  -- Check for duplicate ordinals
  SELECT COUNT(*) INTO v_duplicate_ordinals
  FROM (
    SELECT q.ordinal
    FROM public.questions q
    WHERE q.test_id = p_test_id
    GROUP BY q.ordinal
    HAVING COUNT(*) > 1
  ) d;

  IF v_duplicate_ordinals > 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: % duplicate ordinals found in questions', v_duplicate_ordinals;
  END IF;

  -- Check for NULL ordinals
  SELECT COUNT(*) INTO v_ordinal_issues
  FROM public.questions q
  WHERE q.test_id = p_test_id
    AND q.ordinal IS NULL;

  IF v_ordinal_issues > 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: % questions have NULL ordinal', v_ordinal_issues;
  END IF;

  -- Validate syllabus references if test_syllabus has entries
  SELECT EXISTS (
    SELECT 1
    FROM public.test_syllabus ts
    WHERE ts.test_id = p_test_id
      AND NOT EXISTS (
        SELECT 1 FROM public.syllabus_nodes sn WHERE sn.id = ts.syllabus_node_id
      )
  ) INTO v_syllabus_valid;

  IF v_syllabus_valid THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Some syllabus references are invalid';
  END IF;

  -- Publish the test
  UPDATE public.tests
  SET status = 'published'::public.test_status
  WHERE id = p_test_id;

  RETURN jsonb_build_object(
    'test_id', p_test_id,
    'status', 'published',
    'question_count', v_question_count,
    'published_at', now(),
    'message', 'Test published successfully'
  );
END;
$function$;

-- STEP 3 (read-only) — verify on a draft you own whose questions are all
-- approved (replace the id):
-- SELECT public.rpc_publish_test('<test-uuid>');
-- SELECT id, status FROM public.tests WHERE id = '<test-uuid>';
