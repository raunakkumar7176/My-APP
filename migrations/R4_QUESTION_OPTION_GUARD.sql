-- ============================================================
-- R4 — QUESTION OPTION GUARD: >= 4 options (server-authoritative), 2026-09-17
-- ============================================================
-- V1 product rule: every question created or updated through the RPCs must
-- carry at least 4 answer options (MCQ is the only exposed type; TF /
-- multiple / numeric / short stay "Coming soon" — no options are invented).
--
-- Baselines (verified in this project):
--   rpc_update_question — the live body = migrations/R4_FIX_rpc_update_question_status_cast.sql
--                         (applied; approvals work live).
--   rpc_create_question — R4_5_1 body with the live RETURN shape
--                         {question_id, ordinal, message} (R4.1 evidence: no created_at).
-- Changes, and nothing else:
--   create : option check 2 -> 4 (array + length).
--   update : validates the FINAL option set (p_options, else the stored
--            options) >= 4; correct_option (new or existing) checked
--            against that final set. Signatures, DEFINER, search_path '',
--            ownership/lifecycle checks, published-test restriction,
--            status cast, all other validation: unchanged.
-- No schema, RLS, grant or scoring change. Existing rows are NOT modified.
--
-- ------------------------------------------------------------
-- PREFLIGHT (read-only) — STOP if anything differs from "expect"
-- ------------------------------------------------------------
-- (1) exact signatures (must match the CREATE OR REPLACE below 1:1)
SELECT p.proname, pg_get_function_arguments(p.oid) AS args,
       pg_get_function_result(p.oid) AS returns, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN ('rpc_create_question', 'rpc_update_question')
ORDER BY p.proname;
-- expect:
--   rpc_create_question | p_test_id uuid, p_question text, p_options jsonb, p_correct_option integer,
--     p_ordinal integer DEFAULT NULL, p_explanation text DEFAULT ''::text, p_subject_id uuid DEFAULT NULL,
--     p_topic_node_id uuid DEFAULT NULL, p_difficulty text DEFAULT 'medium'::text, p_marks numeric DEFAULT 1,
--     p_status text DEFAULT 'pending_review'::text, p_source_batch integer DEFAULT NULL, p_bank_id uuid DEFAULT NULL,
--     p_language text DEFAULT 'en'::text, p_question_type text DEFAULT 'mcq'::text | jsonb | t | {search_path=}
--   rpc_update_question | p_question_id uuid, p_question text DEFAULT NULL, p_options jsonb DEFAULT NULL,
--     p_correct_option integer DEFAULT NULL, p_explanation text DEFAULT NULL, p_subject_id uuid DEFAULT NULL,
--     p_topic_node_id uuid DEFAULT NULL, p_difficulty text DEFAULT NULL, p_marks numeric DEFAULT NULL,
--     p_status text DEFAULT NULL, p_language text DEFAULT NULL, p_question_type text DEFAULT NULL | jsonb | t | {search_path=}

-- (2) live-body markers (the baselines used below)
SELECT p.proname,
       pg_get_functiondef(p.oid) LIKE '%at least 2 options are required%'          AS has_old_guard,
       pg_get_functiondef(p.oid) LIKE '%p_status::public.question_status%'          AS has_status_cast,
       pg_get_functiondef(p.oid) LIKE '%Cannot change correct_option on published%' AS has_published_rule,
       pg_get_functiondef(p.oid) LIKE '%''created_at'', v_created_at%'               AS returns_created_at
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN ('rpc_create_question', 'rpc_update_question')
ORDER BY p.proname;
-- expect: create → has_old_guard t, returns_created_at f
--         update → has_old_guard t, has_status_cast t, has_published_rule t
-- If not, paste pg_get_functiondef for the differing function and STOP.

-- (3) grants snapshot (re-checked in postflight; CREATE OR REPLACE keeps them)
SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public' AND routine_name IN ('rpc_create_question', 'rpc_update_question')
ORDER BY 1, 2;

-- (4) PRE-EXISTING DATA AUDIT — report, never modify
SELECT count(*) AS questions_with_fewer_than_4_options
FROM public.questions
WHERE options IS NULL OR jsonb_typeof(options) <> 'array' OR jsonb_array_length(options) < 4;

SELECT q.id, q.test_id, q.status, q.question_type,
       CASE WHEN options IS NULL OR jsonb_typeof(options) <> 'array' THEN NULL
            ELSE jsonb_array_length(options) END AS option_count,
       t.status AS test_status
FROM public.questions q JOIN public.tests t ON t.id = q.test_id
WHERE q.options IS NULL OR jsonb_typeof(q.options) <> 'array' OR jsonb_array_length(q.options) < 4
ORDER BY t.status, q.test_id, q.ordinal;
-- These rows stay untouched. After this migration they can no longer be
-- re-saved without supplying >= 4 options (creator fixes them in the editor).

-- ------------------------------------------------------------
-- STEP 1 — rpc_create_question (guard 2 -> 4)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_create_question(
  p_test_id uuid,
  p_question text,
  p_options jsonb,
  p_correct_option integer,
  p_ordinal integer DEFAULT NULL,
  p_explanation text DEFAULT '',
  p_subject_id uuid DEFAULT NULL,
  p_topic_node_id uuid DEFAULT NULL,
  p_difficulty text DEFAULT 'medium',
  p_marks numeric DEFAULT 1,
  p_status text DEFAULT 'pending_review',
  p_source_batch integer DEFAULT NULL,
  p_bank_id uuid DEFAULT NULL,
  p_language text DEFAULT 'en',
  p_question_type text DEFAULT 'mcq'
)
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
    p_status,
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
$function$;

-- ------------------------------------------------------------
-- STEP 2 — rpc_update_question (final option set >= 4)
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
  v_final_options jsonb;
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

  -- Validate the FINAL option set that will be stored (supplied options,
  -- else the existing ones). V1 product rule: >= 4 options. A text-only
  -- update of a legacy <4-option row is rejected too, so nothing invalid
  -- can be re-saved; nothing is synthesised.
  v_final_options := COALESCE(p_options, v_question.options);
  IF v_final_options IS NULL
     OR jsonb_typeof(v_final_options) <> 'array'
     OR jsonb_array_length(v_final_options) < 4 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: at least 4 options are required';
  END IF;

  -- Validate correct_option against the final option set
  IF p_correct_option IS NOT NULL THEN
    IF p_correct_option < 0 OR p_correct_option >= jsonb_array_length(v_final_options) THEN
      RAISE EXCEPTION 'VALIDATION_ERROR: correct_option must be a valid option index';
    END IF;
  ELSIF p_options IS NOT NULL
        AND v_question.correct_option IS NOT NULL
        AND v_question.correct_option >= jsonb_array_length(v_final_options) THEN
    -- Replacing options without a new key must not orphan the stored key.
    RAISE EXCEPTION 'VALIDATION_ERROR: correct_option must be a valid option index';
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

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only)
-- ------------------------------------------------------------
SELECT p.proname, pg_get_function_arguments(p.oid) AS args,
       pg_get_function_result(p.oid) AS returns, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN ('rpc_create_question', 'rpc_update_question')
ORDER BY p.proname;
-- expect: identical to preflight (1); exactly one row each (no overloads)

SELECT p.proname,
       pg_get_functiondef(p.oid) LIKE '%at least 4 options are required%'            AS has_4_option_guard,
       pg_get_functiondef(p.oid) LIKE '%correct_option must be a valid option index%' AS has_correct_option_check,
       pg_get_functiondef(p.oid) LIKE '%at least 2 options are required%'            AS old_guard_gone_should_be_f,
       pg_get_functiondef(p.oid) LIKE '%Cannot change correct_option on published%'  AS has_published_rule,
       p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN ('rpc_create_question', 'rpc_update_question')
ORDER BY p.proname;
-- expect: t | t | f | (update: t) | t | {search_path=}

SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public' AND routine_name IN ('rpc_create_question', 'rpc_update_question')
ORDER BY 1, 2;
-- expect: identical to preflight (3)

-- Behavioural (as the creator of a draft test <test>):
--   SELECT public.rpc_create_question('<test>', 'Q?', '["a","b"]'::jsonb, 0);            -- at least 4 options
--   SELECT public.rpc_create_question('<test>', 'Q?', '["a","b","c"]'::jsonb, 0);        -- at least 4 options
--   SELECT public.rpc_create_question('<test>', 'Q?', '["a","b","c","d"]'::jsonb, 3);    -- ok
--   SELECT public.rpc_create_question('<test>', 'Q?', '["a","b","c","d","e"]'::jsonb, 4);-- ok
--   SELECT public.rpc_create_question('<test>', 'Q?', '["a","b","c","d"]'::jsonb, 4);    -- correct_option invalid
--   SELECT public.rpc_update_question('<q>', p_options := '["a","b","c"]'::jsonb);       -- at least 4 options
--   SELECT public.rpc_update_question('<q>', p_options := '["a","b","c","d"]'::jsonb);   -- ok
--   SELECT public.rpc_update_question('<q>', p_question := 'Renamed');                   -- ok (final set has 4)
--   -- on a legacy <4-option row: SELECT public.rpc_update_question('<legacy>', p_question := 'x'); -- rejected
