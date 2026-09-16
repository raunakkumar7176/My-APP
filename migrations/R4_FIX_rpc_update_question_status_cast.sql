-- ============================================================
-- R4 FIX — rpc_update_question: COALESCE(text, question_status) mismatch
-- ============================================================
-- Device evidence (2026-09-16, Edit Test → Review → Approve):
--   "COALESCE types text and public.question_status cannot be matched."
--
-- Cause: public.questions.status is the enum public.question_status, but
-- rpc_update_question takes p_status text and does
--   status = COALESCE(p_status, status)
-- COALESCE has no assignment context, so text vs enum cannot be unified.
-- (rpc_create_question is unaffected: a plain INSERT VALUES uses the
-- assignment cast text → enum.)
--
-- Fix: cast the parameter inside that one COALESCE. Nothing else changes:
-- no RLS, grants, schema, statuses, scoring or other functions. Invalid
-- values are still rejected by the existing IN (...) validation before the
-- cast runs; every existing status value is preserved.
--
-- STEP 1 (read-only) — confirm the live definition matches before replacing.
-- Expect: status column udt_name = question_status, and the functiondef to
-- contain "status = COALESCE(p_status, status)".
-- ------------------------------------------------------------
-- SELECT column_name, data_type, udt_name
--   FROM information_schema.columns
--  WHERE table_schema = 'public' AND table_name = 'questions'
--    AND column_name IN ('status', 'difficulty', 'question_type', 'language');
-- SELECT pg_get_functiondef('public.rpc_update_question(uuid,text,jsonb,integer,text,uuid,uuid,text,numeric,text,text,text)'::regprocedure);
--
-- If the live body differs from the one below, apply ONLY this line change
-- to the live body instead of running STEP 2:
--     status = COALESCE(p_status::public.question_status, status),
--
-- STEP 2 — targeted replacement (R4_5_1 body + the single cast).
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_update_question(
  p_question_id uuid,
  p_question text DEFAULT NULL,
  p_options jsonb DEFAULT NULL,
  p_correct_option integer DEFAULT NULL,
  p_explanation text DEFAULT NULL,
  p_subject_id uuid DEFAULT NULL,
  p_topic_node_id uuid DEFAULT NULL,
  p_difficulty text DEFAULT NULL,
  p_marks numeric DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_language text DEFAULT NULL,
  p_question_type text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_question record;
  v_test record;
BEGIN
  -- Auth check
  v_uid := public._fn_auth_uid();

  -- Load question
  SELECT * INTO v_question FROM public.questions q WHERE q.id = p_question_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'QUESTION_NOT_FOUND';
  END IF;

  -- Permission check
  IF NOT public._fn_can_manage_questions(v_question.test_id, v_uid) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Cannot update this question';
  END IF;

  -- Load test for lifecycle check
  SELECT * INTO v_test FROM public.tests t WHERE t.id = v_question.test_id;

  -- For published tests, restrict certain updates
  IF v_test.status::text = 'published' THEN
    -- Cannot change correct_option on published test questions
    IF p_correct_option IS NOT NULL AND p_correct_option != v_question.correct_option THEN
      RAISE EXCEPTION 'VALIDATION_ERROR: Cannot change correct_option on published test';
    END IF;
  END IF;

  -- Validate question text if provided
  IF p_question IS NOT NULL AND TRIM(p_question) = '' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: question text cannot be empty';
  END IF;

  -- Validate options if provided
  IF p_options IS NOT NULL AND jsonb_array_length(p_options) < 2 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: at least 2 options are required';
  END IF;

  -- Validate correct_option if provided
  IF p_correct_option IS NOT NULL THEN
    DECLARE
      v_options jsonb := COALESCE(p_options, v_question.options);
    BEGIN
      IF p_correct_option < 0 OR p_correct_option >= jsonb_array_length(v_options) THEN
        RAISE EXCEPTION 'VALIDATION_ERROR: correct_option must be a valid option index';
      END IF;
    END;
  END IF;

  -- Validate difficulty if provided
  IF p_difficulty IS NOT NULL AND p_difficulty NOT IN ('easy', 'medium', 'hard') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: difficulty must be easy, medium, or hard';
  END IF;

  -- Validate marks if provided
  IF p_marks IS NOT NULL AND p_marks <= 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: marks must be greater than 0';
  END IF;

  -- Validate language if provided
  IF p_language IS NOT NULL AND p_language NOT IN ('en', 'hi', 'hinglish') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: language must be en, hi, or hinglish';
  END IF;

  -- Validate question_type if provided
  IF p_question_type IS NOT NULL AND p_question_type NOT IN ('mcq', 'tf', 'short', 'num') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: question_type must be mcq, tf, short, or num';
  END IF;

  -- Validate status (question_status enum) if provided
  IF p_status IS NOT NULL AND p_status NOT IN ('pending_review', 'approved', 'rejected', 'needs_revision', 'archived') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: status must be pending_review, approved, rejected, needs_revision, or archived';
  END IF;

  -- Update question
  UPDATE public.questions SET
    question = COALESCE(p_question, question),
    options = COALESCE(p_options, options),
    correct_option = COALESCE(p_correct_option, correct_option),
    explanation = COALESCE(p_explanation, explanation),
    subject_id = COALESCE(p_subject_id, subject_id),
    topic_node_id = COALESCE(p_topic_node_id, topic_node_id),
    difficulty = COALESCE(p_difficulty, difficulty),
    marks = COALESCE(p_marks, marks),
    status = COALESCE(p_status::public.question_status, status),
    language = COALESCE(p_language, language),
    question_type = COALESCE(p_question_type, question_type)
  WHERE id = p_question_id;

  RETURN jsonb_build_object(
    'question_id', p_question_id,
    'updated_at', now(),
    'message', 'Question updated successfully'
  );
END;
$function$;

-- STEP 3 (read-only) — verify: the following must now succeed
-- (replace the id with any pending_review question you own):
-- SELECT public.rpc_update_question(p_question_id := '<question-uuid>', p_status := 'approved');
-- SELECT id, status FROM public.questions WHERE id = '<question-uuid>';
