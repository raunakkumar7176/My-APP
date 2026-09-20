-- R7 — fix rpc_create_question (owner apply required; independent of R7_QUESTION_BANK_V1)
--
-- LIVE FINDING (2026-09-20, rolled-back proof): every call to public.rpc_create_question
-- fails with  column "status" is of type public.question_status but expression is of
-- type text  because the INSERT passes the text parameter p_status into the enum column
-- without a cast (the sibling rpc_update_question casts with p_status::public.question_status).
-- Consequence: the Flutter test-creation flow cannot add questions live; the legacy web
-- app is unaffected (it inserts into questions directly).
--
-- FIX: the live body verbatim with the single cast added. Signature, guards
-- (_fn_can_manage_questions: creator, draft/published), validation, grants unchanged.
-- Rollback: re-create the previous body (docs/R7_QUESTION_BANK_PRECHECK.md §5 captures it).

CREATE OR REPLACE FUNCTION public.rpc_create_question(p_test_id uuid, p_question text, p_options jsonb, p_correct_option integer, p_ordinal integer DEFAULT NULL::integer, p_explanation text DEFAULT ''::text, p_subject_id uuid DEFAULT NULL::uuid, p_topic_node_id uuid DEFAULT NULL::uuid, p_difficulty text DEFAULT 'medium'::text, p_marks numeric DEFAULT 1, p_status text DEFAULT 'pending_review'::text, p_source_batch integer DEFAULT NULL::integer, p_bank_id uuid DEFAULT NULL::uuid, p_language text DEFAULT 'en'::text, p_question_type text DEFAULT 'mcq'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_question_id uuid;
  v_final_ordinal integer;
BEGIN
  -- Auth check
  v_uid := public._fn_auth_uid();

  -- Permission check
  IF NOT public._fn_can_manage_questions(p_test_id, v_uid) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Cannot add questions to this test';
  END IF;

  -- Validate question text
  IF p_question IS NULL OR TRIM(p_question) = '' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: question text is required';
  END IF;

  -- Validate options (V1 product rule: every question carries >= 4 options;
  -- nothing is synthesised — the caller must supply them)
  IF p_options IS NULL OR jsonb_typeof(p_options) <> 'array' OR jsonb_array_length(p_options) < 4 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: at least 4 options are required';
  END IF;
  -- Every option must carry text: {"id","text"} objects (client shape) or
  -- bare strings. Blank options would be unanswerable choices.
  IF EXISTS (
    SELECT 1 FROM jsonb_array_elements(p_options) AS o
    WHERE btrim(COALESCE(
      CASE WHEN jsonb_typeof(o) = 'object' THEN o->>'text'
           WHEN jsonb_typeof(o) = 'string' THEN o #>> '{}' END, '')) = ''
  ) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: every option needs text';
  END IF;

  -- Validate correct_option
  IF p_correct_option < 0 OR p_correct_option >= jsonb_array_length(p_options) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: correct_option must be a valid option index';
  END IF;

  -- Validate difficulty
  IF p_difficulty NOT IN ('easy', 'medium', 'hard') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: difficulty must be easy, medium, or hard';
  END IF;

  -- Validate marks
  IF p_marks <= 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: marks must be greater than 0';
  END IF;

  -- Validate language
  IF p_language IS NOT NULL AND p_language NOT IN ('en', 'hi', 'hinglish') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: language must be en, hi, or hinglish';
  END IF;

  -- Validate question_type
  IF p_question_type IS NOT NULL AND p_question_type NOT IN ('mcq', 'tf', 'short', 'num') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: question_type must be mcq, tf, short, or num';
  END IF;

  -- Validate status (question_status enum)
  IF p_status IS NOT NULL AND p_status NOT IN ('pending_review', 'approved', 'rejected', 'needs_revision', 'archived') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: status must be pending_review, approved, rejected, needs_revision, or archived';
  END IF;

  -- Validate subject_id if provided
  IF p_subject_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.subjects s WHERE s.id = p_subject_id) THEN
      RAISE EXCEPTION 'VALIDATION_ERROR: subject_id does not exist';
    END IF;
  END IF;

  -- Validate topic_node_id if provided
  IF p_topic_node_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM public.syllabus_nodes sn WHERE sn.id = p_topic_node_id) THEN
      RAISE EXCEPTION 'VALIDATION_ERROR: topic_node_id does not exist';
    END IF;
  END IF;

  -- Determine ordinal
  IF p_ordinal IS NOT NULL THEN
    -- Check if ordinal is already taken
    IF EXISTS (
      SELECT 1 FROM public.questions q
      WHERE q.test_id = p_test_id AND q.ordinal = p_ordinal
    ) THEN
      RAISE EXCEPTION 'VALIDATION_ERROR: ordinal % is already taken in this test', p_ordinal;
    END IF;
    v_final_ordinal := p_ordinal;
  ELSE
    -- Auto-assign next ordinal
    v_final_ordinal := public._fn_get_next_question_ordinal(p_test_id);
  END IF;

  -- Create question
  INSERT INTO public.questions (
    test_id,
    ordinal,
    question,
    options,
    correct_option,
    explanation,
    subject_id,
    topic_node_id,
    difficulty,
    marks,
    status,
    source_batch,
    bank_id,
    language,
    question_type
  ) VALUES (
    p_test_id,
    v_final_ordinal,
    TRIM(p_question),
    p_options,
    p_correct_option,
    COALESCE(p_explanation, ''),
    p_subject_id,
    p_topic_node_id,
    p_difficulty,
    p_marks,
    p_status::public.question_status,
    p_source_batch,
    p_bank_id,
    p_language,
    p_question_type
  )
  RETURNING id INTO v_question_id;

  RETURN jsonb_build_object(
    'question_id', v_question_id,
    'ordinal', v_final_ordinal,
    'message', 'Question created successfully'
  );
END;
$function$
;

-- postflight (read-only)
SELECT (prosrc ILIKE '%p_status::public.question_status%') AS cast_present FROM pg_proc WHERE proname = 'rpc_create_question'; -- expect true
