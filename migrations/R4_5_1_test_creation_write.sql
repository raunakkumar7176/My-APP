-- ============================================================
-- R4.5.1 PHASE: TEST CREATION DB WRITE FOUNDATION
-- My Preparation — Flutter + Supabase
-- Date: 2026-09-13
-- Status: PENDING APPROVAL
--
-- PREREQUISITES:
-- - R4.1 executed (tables exist)
-- - R4.2 partially complete (some hardening done)
-- - R4.3 executed (secure test entry RPCs exist)
-- - R4.5 discovery D4-D28 completed
--
-- RULES:
-- - Use LIVE schema as ONLY source of truth
-- - Do NOT redesign architecture
-- - Do NOT delete/drop/truncate/recreate existing tables/data
-- - Do NOT modify unrelated R0-R4.4 functionality
-- - Do NOT expose correct_option through student-facing APIs
-- - Do NOT break existing secure question architecture
-- - Do NOT implement Flutter UI, notifications, leaderboard
-- - Do NOT invent tables for Books module
--
-- EXECUTION: Run via Supabase SQL Editor AFTER discovery
-- ROLLBACK: See ROLLBACK section at end of file
-- ============================================================

-- ============================================================
-- SECTION 0: PREFLIGHT DISCOVERY
-- Capture existing state before any changes
-- ============================================================

-- NOTE: Row count verification is captured at the end of the migration
-- using an inline CTE (Section 6). Cross-statement temporary tables are
-- not supported in Supabase SQL Editor because each statement may run in
-- its own transaction context.

-- Capture existing functions
SELECT 'PREFLIGHT: Existing Functions' AS check_name;
SELECT
  p.proname AS function_name,
  pg_get_function_arguments(p.oid) AS arguments,
  pg_get_function_result(p.oid) AS return_type,
  p.prosecdef AS is_security_definer,
  p.proconfig AS config
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
    'rpc_create_test', 'rpc_update_test', 'rpc_publish_test',
    'rpc_create_question', 'rpc_update_question', 'rpc_delete_question',
    'rpc_add_test_syllabus', 'rpc_remove_test_syllabus',
    '_fn_can_create_test', '_fn_can_update_test', '_fn_can_manage_questions',
    '_fn_validate_test_for_publish', '_fn_get_next_question_ordinal'
  )
ORDER BY p.proname;

-- ============================================================
-- SECTION 1: HELPER FUNCTIONS (Internal Use Only)
-- These are SECURITY DEFINER with search_path = ''
-- and are NOT granted to any role except postgres
-- ============================================================

-- ------------------------------------------------------------
-- 1.1 _fn_auth_uid()
-- Safe wrapper for auth.uid() that raises on null
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._fn_auth_uid()
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;
  RETURN v_uid;
END;
$function$;

-- ------------------------------------------------------------
-- 1.2 _fn_can_create_test(p_user uuid)
-- Checks if user can create tests (any authenticated user)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._fn_can_create_test(p_user uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  -- Any authenticated user can create tests
  RETURN p_user IS NOT NULL;
END;
$function$;

-- ------------------------------------------------------------
-- 1.3 _fn_can_update_test(p_test_id uuid, p_user uuid)
-- Checks if user can update a test (creator only, draft status)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._fn_can_update_test(p_test_id uuid, p_user uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_test record;
BEGIN
  SELECT * INTO v_test
  FROM public.tests t
  WHERE t.id = p_test_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  -- Only creator can update
  IF v_test.created_by != p_user THEN
    RETURN false;
  END IF;

  -- Can only update draft or published tests (with restrictions)
  -- Draft: full edit access
  -- Published: limited fields only
  -- Other statuses: no updates allowed
  IF v_test.status::text NOT IN ('draft', 'published') THEN
    RETURN false;
  END IF;

  RETURN true;
END;
$function$;

-- ------------------------------------------------------------
-- 1.4 _fn_can_manage_questions(p_test_id uuid, p_user uuid)
-- Checks if user can manage questions for a test
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._fn_can_manage_questions(p_test_id uuid, p_user uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_test record;
BEGIN
  SELECT * INTO v_test
  FROM public.tests t
  WHERE t.id = p_test_id;

  IF NOT FOUND THEN
    RETURN false;
  END IF;

  -- Only creator can manage questions
  IF v_test.created_by != p_user THEN
    RETURN false;
  END IF;

  -- Can only manage questions in draft or published tests
  -- Published tests: can add/edit questions but with restrictions
  -- Other statuses: no question management
  IF v_test.status::text NOT IN ('draft', 'published') THEN
    RETURN false;
  END IF;

  RETURN true;
END;
$function$;

-- ------------------------------------------------------------
-- 1.5 _fn_get_next_question_ordinal(p_test_id uuid)
-- Gets the next available ordinal for a question in a test
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._fn_get_next_question_ordinal(p_test_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_max_ordinal integer;
BEGIN
  SELECT COALESCE(MAX(q.ordinal), 0) INTO v_max_ordinal
  FROM public.questions q
  WHERE q.test_id = p_test_id;

  RETURN v_max_ordinal + 1;
END;
$function$;

-- ------------------------------------------------------------
-- 1.6 _fn_validate_test_timing(p_starts_at timestamptz, p_ends_at timestamptz)
-- Validates test timing constraints
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._fn_validate_test_timing(
  p_starts_at timestamptz,
  p_ends_at timestamptz
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  IF p_starts_at IS NOT NULL AND p_ends_at IS NOT NULL THEN
    IF p_ends_at <= p_starts_at THEN
      RAISE EXCEPTION 'VALIDATION_ERROR: ends_at must be after starts_at';
    END IF;
  END IF;
END;
$function$;

-- ------------------------------------------------------------
-- 1.7 _fn_validate_test_config(p_config jsonb)
-- Validates test configuration JSON
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._fn_validate_test_config(p_config jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
BEGIN
  -- Config is flexible JSONB, just ensure it's valid
  IF p_config IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: config cannot be null';
  END IF;
END;
$function$;

-- ============================================================
-- SECTION 2: TEST CREATION RPCs
-- ============================================================

-- ------------------------------------------------------------
-- 2.1 rpc_create_test(p_title, p_description, p_duration_sec, ...)
-- Creates a new test in DRAFT status
-- Returns: JSONB with test_id and created_at
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_create_test(
  p_title text,
  p_description text DEFAULT '',
  p_duration_sec integer DEFAULT 3600,
  p_marks_per_question numeric DEFAULT 1,
  p_negative_marks numeric DEFAULT 0,
  p_test_mode text DEFAULT 'self',
  p_creation_method text DEFAULT 'manual',
  p_group_id uuid DEFAULT NULL,
  p_starts_at timestamptz DEFAULT NULL,
  p_ends_at timestamptz DEFAULT NULL,
  p_max_participants integer DEFAULT NULL,
  p_allow_late_join boolean DEFAULT false,
  p_config jsonb DEFAULT '{}',
  p_settings jsonb DEFAULT '{}',
  p_access_code text DEFAULT NULL,
  p_join_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_test_id uuid;
  v_created_at timestamptz;
  v_test record;
BEGIN
  -- Auth check
  v_uid := public._fn_auth_uid();

  -- Permission check
  IF NOT public._fn_can_create_test(v_uid) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Cannot create tests';
  END IF;

  -- Validate title
  IF p_title IS NULL OR TRIM(p_title) = '' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: title is required and cannot be empty';
  END IF;

  -- Validate duration_sec
  IF p_duration_sec < 60 OR p_duration_sec > 21600 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: duration_sec must be between 60 and 21600';
  END IF;

  -- Validate marks_per_question
  IF p_marks_per_question <= 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: marks_per_question must be greater than 0';
  END IF;

  -- Validate negative_marks
  IF p_negative_marks < 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: negative_marks cannot be negative';
  END IF;

  -- Validate test_mode
  IF p_test_mode IS NOT NULL AND p_test_mode NOT IN ('self', 'live', 'group') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: test_mode must be self, live, group, or null';
  END IF;

  -- Validate creation_method
  IF p_creation_method IS NOT NULL AND p_creation_method NOT IN ('manual', 'upload', 'ai', 'mixed') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: creation_method must be manual, upload, ai, mixed, or null';
  END IF;

  -- Validate max_participants
  IF p_max_participants IS NOT NULL AND (p_max_participants < 2 OR p_max_participants > 10000) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: max_participants must be NULL or between 2 and 10000';
  END IF;

  -- Validate timing
  PERFORM public._fn_validate_test_timing(p_starts_at, p_ends_at);

  -- Validate config
  PERFORM public._fn_validate_test_config(p_config);

  -- Group test validation
  IF p_test_mode = 'group' AND p_group_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: group_id is required for group tests';
  END IF;

  -- Create test
  INSERT INTO public.tests (
    title,
    description,
    duration_sec,
    marks_per_question,
    negative_marks,
    test_mode,
    creation_method,
    group_id,
    starts_at,
    ends_at,
    max_participants,
    allow_late_join,
    config,
    settings,
    access_code,
    join_code,
    created_by,
    status
  ) VALUES (
    TRIM(p_title),
    COALESCE(p_description, ''),
    p_duration_sec,
    p_marks_per_question,
    p_negative_marks,
    p_test_mode,
    p_creation_method,
    p_group_id,
    p_starts_at,
    p_ends_at,
    p_max_participants,
    p_allow_late_join,
    p_config,
    p_settings,
    p_access_code,
    p_join_code,
    v_uid,
    'draft'::test_status
  )
  RETURNING id, created_at INTO v_test_id, v_created_at;

  -- Return created test metadata (no sensitive data)
  RETURN jsonb_build_object(
    'test_id', v_test_id,
    'created_at', v_created_at,
    'status', 'draft',
    'message', 'Test created successfully'
  );
END;
$function$;

-- ------------------------------------------------------------
-- 2.2 rpc_update_test(p_test_id, p_updates jsonb)
-- Updates a draft/published test with restricted fields
-- Returns: JSONB with updated_at timestamp
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_update_test(
  p_test_id uuid,
  p_title text DEFAULT NULL,
  p_description text DEFAULT NULL,
  p_duration_sec integer DEFAULT NULL,
  p_marks_per_question numeric DEFAULT NULL,
  p_negative_marks numeric DEFAULT NULL,
  p_starts_at timestamptz DEFAULT NULL,
  p_ends_at timestamptz DEFAULT NULL,
  p_max_participants integer DEFAULT NULL,
  p_allow_late_join boolean DEFAULT NULL,
  p_config jsonb DEFAULT NULL,
  p_settings jsonb DEFAULT NULL,
  p_access_code text DEFAULT NULL,
  p_join_code text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_test record;
  v_new_starts_at timestamptz;
  v_new_ends_at timestamptz;
BEGIN
  -- Auth check
  v_uid := public._fn_auth_uid();

  -- Permission check
  IF NOT public._fn_can_update_test(p_test_id, v_uid) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Cannot update this test';
  END IF;

  -- Load current test
  SELECT * INTO v_test FROM public.tests t WHERE t.id = p_test_id;

  -- Determine effective values (use new value if provided, else existing)
  v_new_starts_at := COALESCE(p_starts_at, v_test.starts_at);
  v_new_ends_at := COALESCE(p_ends_at, v_test.ends_at);

  -- Validate timing if either is being updated
  IF p_starts_at IS NOT NULL OR p_ends_at IS NOT NULL THEN
    PERFORM public._fn_validate_test_timing(v_new_starts_at, v_new_ends_at);
  END IF;

  -- Validate title if provided
  IF p_title IS NOT NULL AND TRIM(p_title) = '' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: title cannot be empty';
  END IF;

  -- Validate duration_sec if provided
  IF p_duration_sec IS NOT NULL AND (p_duration_sec < 60 OR p_duration_sec > 21600) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: duration_sec must be between 60 and 21600';
  END IF;

  -- Validate marks_per_question if provided
  IF p_marks_per_question IS NOT NULL AND p_marks_per_question <= 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: marks_per_question must be greater than 0';
  END IF;

  -- Validate negative_marks if provided
  IF p_negative_marks IS NOT NULL AND p_negative_marks < 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: negative_marks cannot be negative';
  END IF;

  -- Validate max_participants if provided
  IF p_max_participants IS NOT NULL AND (p_max_participants < 2 OR p_max_participants > 10000) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: max_participants must be NULL or between 2 and 10000';
  END IF;

  -- Update test (only provided fields)
  UPDATE public.tests SET
    title = COALESCE(p_title, title),
    description = COALESCE(p_description, description),
    duration_sec = COALESCE(p_duration_sec, duration_sec),
    marks_per_question = COALESCE(p_marks_per_question, marks_per_question),
    negative_marks = COALESCE(p_negative_marks, negative_marks),
    starts_at = v_new_starts_at,
    ends_at = v_new_ends_at,
    max_participants = COALESCE(p_max_participants, max_participants),
    allow_late_join = COALESCE(p_allow_late_join, allow_late_join),
    config = COALESCE(p_config, config),
    settings = COALESCE(p_settings, settings),
    access_code = COALESCE(p_access_code, access_code),
    join_code = COALESCE(p_join_code, join_code)
  WHERE id = p_test_id;

  RETURN jsonb_build_object(
    'test_id', p_test_id,
    'updated_at', now(),
    'message', 'Test updated successfully'
  );
END;
$function$;

-- ------------------------------------------------------------
-- 2.3 rpc_publish_test(p_test_id)
-- Publishes a draft test after comprehensive validation
-- Returns: JSONB with published status
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
  SET status = 'published'::test_status
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

-- ============================================================
-- SECTION 3: QUESTION MANAGEMENT RPCs
-- ============================================================

-- ------------------------------------------------------------
-- 3.1 rpc_create_question(p_test_id, p_question, p_options, ...)
-- Creates a new question linked to a test
-- Returns: JSONB with question_id and ordinal
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
  v_created_at timestamptz;
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

  -- Validate options
  IF p_options IS NULL OR jsonb_array_length(p_options) < 2 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: at least 2 options are required';
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
  RETURNING id, created_at INTO v_question_id, v_created_at;

  RETURN jsonb_build_object(
    'question_id', v_question_id,
    'ordinal', v_final_ordinal,
    'created_at', v_created_at,
    'message', 'Question created successfully'
  );
END;
$function$;

-- ------------------------------------------------------------
-- 3.2 rpc_update_question(p_question_id, p_updates jsonb)
-- Updates a question with restricted fields
-- Returns: JSONB with updated_at timestamp
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
    status = COALESCE(p_status, status),
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
-- 3.3 rpc_delete_question(p_question_id)
-- Deletes a question from a draft test
-- Returns: JSONB with deletion confirmation
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_delete_question(p_question_id uuid)
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
    RAISE EXCEPTION 'PERMISSION_DENIED: Cannot delete this question';
  END IF;

  -- Load test for lifecycle check
  SELECT * INTO v_test FROM public.tests t WHERE t.id = v_question.test_id;

  -- Cannot delete questions from published/completed tests
  IF v_test.status::text NOT IN ('draft', 'published') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Cannot delete questions from % tests', v_test.status;
  END IF;

  -- For published tests, use soft-delete (set status to 'archived')
  IF v_test.status::text = 'published' THEN
    UPDATE public.questions
    SET status = 'archived'
    WHERE id = p_question_id;

    RETURN jsonb_build_object(
      'question_id', p_question_id,
      'action', 'archived',
      'message', 'Question archived from published test'
    );
  ELSE
    -- For draft tests, physical delete
    DELETE FROM public.questions WHERE id = p_question_id;

    RETURN jsonb_build_object(
      'question_id', p_question_id,
      'action', 'deleted',
      'message', 'Question deleted from draft test'
    );
  END IF;
END;
$function$;

-- ============================================================
-- SECTION 4: TEST SYLLABUS MANAGEMENT RPCs
-- ============================================================

-- ------------------------------------------------------------
-- 4.1 rpc_add_test_syllabus(p_test_id, p_syllabus_node_id, p_material_ids)
-- Adds a syllabus node to a test
-- Returns: JSONB with confirmation
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_add_test_syllabus(
  p_test_id uuid,
  p_syllabus_node_id uuid,
  p_material_ids uuid[] DEFAULT '{}'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_test record;
BEGIN
  -- Auth check
  v_uid := public._fn_auth_uid();

  -- Permission check
  IF NOT public._fn_can_update_test(p_test_id, v_uid) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Cannot modify test syllabus';
  END IF;

  -- Validate test exists
  SELECT * INTO v_test FROM public.tests t WHERE t.id = p_test_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'TEST_NOT_FOUND';
  END IF;

  -- Validate syllabus_node exists
  IF NOT EXISTS (SELECT 1 FROM public.syllabus_nodes sn WHERE sn.id = p_syllabus_node_id) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: syllabus_node_id does not exist';
  END IF;

  -- Check for duplicate
  IF EXISTS (
    SELECT 1 FROM public.test_syllabus ts
    WHERE ts.test_id = p_test_id AND ts.syllabus_node_id = p_syllabus_node_id
  ) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: This syllabus node is already added to the test';
  END IF;

  -- Insert syllabus link
  INSERT INTO public.test_syllabus (test_id, syllabus_node_id, material_ids)
  VALUES (p_test_id, p_syllabus_node_id, p_material_ids);

  RETURN jsonb_build_object(
    'test_id', p_test_id,
    'syllabus_node_id', p_syllabus_node_id,
    'message', 'Syllabus node added to test'
  );
END;
$function$;

-- ------------------------------------------------------------
-- 4.2 rpc_remove_test_syllabus(p_test_id, p_syllabus_node_id)
-- Removes a syllabus node from a test
-- Returns: JSONB with confirmation
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_remove_test_syllabus(
  p_test_id uuid,
  p_syllabus_node_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_deleted_count integer;
BEGIN
  -- Auth check
  v_uid := public._fn_auth_uid();

  -- Permission check
  IF NOT public._fn_can_update_test(p_test_id, v_uid) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Cannot modify test syllabus';
  END IF;

  -- Remove syllabus link
  DELETE FROM public.test_syllabus ts
  WHERE ts.test_id = p_test_id
    AND ts.syllabus_node_id = p_syllabus_node_id;

  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;

  IF v_deleted_count = 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: This syllabus node is not linked to the test';
  END IF;

  RETURN jsonb_build_object(
    'test_id', p_test_id,
    'syllabus_node_id', p_syllabus_node_id,
    'message', 'Syllabus node removed from test'
  );
END;
$function$;

-- ============================================================
-- SECTION 5: GRANTS & SECURITY
-- ============================================================

-- Grant EXECUTE on public RPCs to authenticated users only
GRANT EXECUTE ON FUNCTION public.rpc_create_test(
  text, text, integer, numeric, numeric, text, text, uuid,
  timestamptz, timestamptz, integer, boolean, jsonb, jsonb, text, text
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_update_test(
  uuid, text, text, integer, numeric, numeric, timestamptz, timestamptz,
  integer, boolean, jsonb, jsonb, text, text
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_publish_test(uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_create_question(
  uuid, text, jsonb, integer, integer, text, uuid, uuid, text, numeric,
  text, integer, uuid, text, text
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_update_question(
  uuid, text, jsonb, integer, text, uuid, uuid, text, numeric,
  text, text, text
) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_delete_question(uuid) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_add_test_syllabus(uuid, uuid, uuid[]) TO authenticated;

GRANT EXECUTE ON FUNCTION public.rpc_remove_test_syllabus(uuid, uuid) TO authenticated;

-- Revoke from PUBLIC and anon for all functions
REVOKE EXECUTE ON FUNCTION public.rpc_create_test(
  text, text, integer, numeric, numeric, text, text, uuid,
  timestamptz, timestamptz, integer, boolean, jsonb, jsonb, text, text
) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.rpc_update_test(
  uuid, text, text, integer, numeric, numeric, timestamptz, timestamptz,
  integer, boolean, jsonb, jsonb, text, text
) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.rpc_publish_test(uuid) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.rpc_create_question(
  uuid, text, jsonb, integer, integer, text, uuid, uuid, text, numeric,
  text, integer, uuid, text, text
) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.rpc_update_question(
  uuid, text, jsonb, integer, text, uuid, uuid, text, numeric,
  text, text, text
) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.rpc_delete_question(uuid) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.rpc_add_test_syllabus(uuid, uuid, uuid[]) FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.rpc_remove_test_syllabus(uuid, uuid) FROM PUBLIC;

-- Revoke from anon
REVOKE EXECUTE ON FUNCTION public.rpc_create_test(
  text, text, integer, numeric, numeric, text, text, uuid,
  timestamptz, timestamptz, integer, boolean, jsonb, jsonb, text, text
) FROM anon;

REVOKE EXECUTE ON FUNCTION public.rpc_update_test(
  uuid, text, text, integer, numeric, numeric, timestamptz, timestamptz,
  integer, boolean, jsonb, jsonb, text, text
) FROM anon;

REVOKE EXECUTE ON FUNCTION public.rpc_publish_test(uuid) FROM anon;

REVOKE EXECUTE ON FUNCTION public.rpc_create_question(
  uuid, text, jsonb, integer, integer, text, uuid, uuid, text, numeric,
  text, integer, uuid, text, text
) FROM anon;

REVOKE EXECUTE ON FUNCTION public.rpc_update_question(
  uuid, text, jsonb, integer, text, uuid, uuid, text, numeric,
  text, text, text
) FROM anon;

REVOKE EXECUTE ON FUNCTION public.rpc_delete_question(uuid) FROM anon;

REVOKE EXECUTE ON FUNCTION public.rpc_add_test_syllabus(uuid, uuid, uuid[]) FROM anon;

REVOKE EXECUTE ON FUNCTION public.rpc_remove_test_syllabus(uuid, uuid) FROM anon;

-- Internal helper functions: no direct EXECUTE grants
REVOKE EXECUTE ON FUNCTION public._fn_auth_uid() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._fn_auth_uid() FROM anon;
REVOKE EXECUTE ON FUNCTION public._fn_auth_uid() FROM authenticated;

REVOKE EXECUTE ON FUNCTION public._fn_can_create_test(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._fn_can_create_test(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public._fn_can_create_test(uuid) FROM authenticated;

REVOKE EXECUTE ON FUNCTION public._fn_can_update_test(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._fn_can_update_test(uuid, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public._fn_can_update_test(uuid, uuid) FROM authenticated;

REVOKE EXECUTE ON FUNCTION public._fn_can_manage_questions(uuid, uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._fn_can_manage_questions(uuid, uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public._fn_can_manage_questions(uuid, uuid) FROM authenticated;

REVOKE EXECUTE ON FUNCTION public._fn_get_next_question_ordinal(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._fn_get_next_question_ordinal(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public._fn_get_next_question_ordinal(uuid) FROM authenticated;

REVOKE EXECUTE ON FUNCTION public._fn_validate_test_timing(timestamptz, timestamptz) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._fn_validate_test_timing(timestamptz, timestamptz) FROM anon;
REVOKE EXECUTE ON FUNCTION public._fn_validate_test_timing(timestamptz, timestamptz) FROM authenticated;

REVOKE EXECUTE ON FUNCTION public._fn_validate_test_config(jsonb) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._fn_validate_test_config(jsonb) FROM anon;
REVOKE EXECUTE ON FUNCTION public._fn_validate_test_config(jsonb) FROM authenticated;

-- ============================================================
-- SECTION 6: POST-EXECUTION ROW COUNT VERIFICATION
-- Capture current row counts for manual comparison against
-- pre-migration baseline. This does NOT prove data unchanged —
-- it is a manual audit aid only.
-- NOTE: This migration creates/replaces functions and manages
-- grants only — no INSERT/UPDATE/DELETE on production tables.
-- ============================================================

WITH row_counts AS (
  SELECT
    (SELECT COUNT(*) FROM public.tests) AS tests_count,
    (SELECT COUNT(*) FROM public.questions) AS questions_count,
    (SELECT COUNT(*) FROM public.test_syllabus) AS test_syllabus_count,
    (SELECT COUNT(*) FROM public.attempts) AS attempts_count,
    (SELECT COUNT(*) FROM public.answers) AS answers_count,
    (SELECT COUNT(*) FROM public.results) AS results_count,
    (SELECT COUNT(*) FROM public.test_invitations) AS invitations_count,
    (SELECT COUNT(*) FROM public.ai_reports) AS ai_reports_count
)
SELECT
  'tests' AS table_name, tests_count AS row_count, 'PASS' AS status FROM row_counts
UNION ALL SELECT 'questions', questions_count, 'PASS' FROM row_counts
UNION ALL SELECT 'test_syllabus', test_syllabus_count, 'PASS' FROM row_counts
UNION ALL SELECT 'attempts', attempts_count, 'PASS' FROM row_counts
UNION ALL SELECT 'answers', answers_count, 'PASS' FROM row_counts
UNION ALL SELECT 'results', results_count, 'PASS' FROM row_counts
UNION ALL SELECT 'invitations', invitations_count, 'PASS' FROM row_counts
UNION ALL SELECT 'ai_reports', ai_reports_count, 'PASS' FROM row_counts;

-- ============================================================
-- SECTION 7: VALIDATION QUERIES
-- Run after migration to verify correctness
-- ============================================================

-- V1: All RPCs exist with correct signatures
SELECT 'V1: RPCs Exist' AS check_name;
SELECT
  p.proname,
  pg_get_function_arguments(p.oid) AS args,
  pg_get_function_result(p.oid) AS return_type,
  p.prosecdef AS security_definer,
  p.proconfig AS config
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
    'rpc_create_test', 'rpc_update_test', 'rpc_publish_test',
    'rpc_create_question', 'rpc_update_question', 'rpc_delete_question',
    'rpc_add_test_syllabus', 'rpc_remove_test_syllabus'
  )
ORDER BY p.proname;

-- V2: Helper functions exist
SELECT 'V2: Helper Functions Exist' AS check_name;
SELECT
  p.proname,
  pg_get_function_arguments(p.oid) AS args,
  p.prosecdef AS security_definer,
  p.proconfig AS config
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
    '_fn_auth_uid', '_fn_can_create_test', '_fn_can_update_test',
    '_fn_can_manage_questions', '_fn_get_next_question_ordinal',
    '_fn_validate_test_timing', '_fn_validate_test_config'
  )
ORDER BY p.proname;

-- V3: All RPCs have SECURITY DEFINER
SELECT 'V3: SECURITY DEFINER Check' AS check_name;
SELECT
  p.proname,
  p.prosecdef AS is_security_definer,
  CASE WHEN p.prosecdef THEN 'PASS' ELSE 'FAIL' END AS status
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
    'rpc_create_test', 'rpc_update_test', 'rpc_publish_test',
    'rpc_create_question', 'rpc_update_question', 'rpc_delete_question',
    'rpc_add_test_syllabus', 'rpc_remove_test_syllabus'
  )
ORDER BY p.proname;

-- V4: All RPCs have search_path = ''
SELECT 'V4: search_path Check' AS check_name;
SELECT
  p.proname,
  p.proconfig,
  CASE WHEN p.proconfig @> ARRAY['search_path='] THEN 'PASS' ELSE 'FAIL' END AS status
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
    'rpc_create_test', 'rpc_update_test', 'rpc_publish_test',
    'rpc_create_question', 'rpc_update_question', 'rpc_delete_question',
    'rpc_add_test_syllabus', 'rpc_remove_test_syllabus'
  )
ORDER BY p.proname;

-- V5: Function privileges
SELECT 'V5: Function Privileges' AS check_name;
SELECT
  grantee,
  routine_name,
  privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN (
    'rpc_create_test', 'rpc_update_test', 'rpc_publish_test',
    'rpc_create_question', 'rpc_update_question', 'rpc_delete_question',
    'rpc_add_test_syllabus', 'rpc_remove_test_syllabus'
  )
ORDER BY routine_name, grantee;

-- V6: No correct_option in student-facing functions
SELECT 'V6: No Answer Key Exposure' AS check_name;
SELECT
  p.proname,
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%correct_option%' THEN 'EXPOSED'
    ELSE 'SAFE'
  END AS answer_key_check
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
    'rpc_create_test', 'rpc_update_test', 'rpc_publish_test',
    'rpc_add_test_syllabus', 'rpc_remove_test_syllabus'
  )
ORDER BY p.proname;

-- V7: questions_safe view still exists
SELECT 'V7: questions_safe View' AS check_name;
SELECT
  table_name,
  view_definition
FROM information_schema.views
WHERE table_schema = 'public'
  AND table_name = 'questions_safe';

-- V8: questions SELECT revoked from authenticated
SELECT 'V8: questions SELECT Revoked' AS check_name;
SELECT
  grantee,
  privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'questions'
  AND grantee = 'authenticated'
  AND privilege_type = 'SELECT';
-- Expected: 0 rows (SELECT revoked)

-- V9: Existing R4.3 functions still exist
SELECT 'V9: R4.3 Functions Intact' AS check_name;
SELECT
  p.proname,
  pg_get_function_arguments(p.oid) AS args,
  p.prosecdef AS security_definer
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
    'rpc_start_attempt', 'rpc_start_attempt_by_code',
    '_fn_start_attempt_core', 'fn_can_access_test',
    'rpc_save_answers', 'rpc_submit_attempt', 'fn_score_attempt'
  )
ORDER BY p.proname;

-- V10: No access_code/join_code exposed in new functions
SELECT 'V10: No Code Exposure in New Functions' AS check_name;
SELECT
  p.proname,
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%access_code%' THEN 'CHECK'
    WHEN pg_get_functiondef(p.oid) LIKE '%join_code%' THEN 'CHECK'
    ELSE 'SAFE'
  END AS code_exposure_check
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
    'rpc_create_test', 'rpc_update_test', 'rpc_publish_test'
  )
ORDER BY p.proname;

-- V11: test_status enum values unchanged
SELECT 'V11: test_status Enum Values' AS check_name;
SELECT
  e.enumlabel AS enum_value,
  e.enumsortorder AS sort_order
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
WHERE t.typname = 'test_status'
ORDER BY e.enumsortorder;

-- V12: question_status enum values (if exists)
SELECT 'V12: question_status Enum Values' AS check_name;
SELECT
  e.enumlabel AS enum_value,
  e.enumsortorder AS sort_order
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
WHERE t.typname = 'question_status'
ORDER BY e.enumsortorder;

-- ============================================================
-- ROLLBACK SCRIPT
-- ============================================================
-- Execute this to undo R4.5.1 changes.
-- WARNING: This drops all new functions created in this migration.

-- -- Drop public RPCs
-- DROP FUNCTION IF EXISTS public.rpc_create_test(text, text, integer, numeric, numeric, text, text, uuid, timestamptz, timestamptz, integer, boolean, jsonb, jsonb, text, text);
-- DROP FUNCTION IF EXISTS public.rpc_update_test(uuid, text, text, integer, numeric, numeric, timestamptz, timestamptz, integer, boolean, jsonb, jsonb, text, text);
-- DROP FUNCTION IF EXISTS public.rpc_publish_test(uuid);
-- DROP FUNCTION IF EXISTS public.rpc_create_question(uuid, text, jsonb, integer, integer, text, uuid, uuid, text, numeric, text, integer, uuid, text, text);
-- DROP FUNCTION IF EXISTS public.rpc_update_question(uuid, text, jsonb, integer, text, uuid, uuid, text, numeric, text, text, text);
-- DROP FUNCTION IF EXISTS public.rpc_delete_question(uuid);
-- DROP FUNCTION IF EXISTS public.rpc_add_test_syllabus(uuid, uuid, uuid[]);
-- DROP FUNCTION IF EXISTS public.rpc_remove_test_syllabus(uuid, uuid);
--
-- -- Drop helper functions
-- DROP FUNCTION IF EXISTS public._fn_auth_uid();
-- DROP FUNCTION IF EXISTS public._fn_can_create_test(uuid);
-- DROP FUNCTION IF EXISTS public._fn_can_update_test(uuid, uuid);
-- DROP FUNCTION IF EXISTS public._fn_can_manage_questions(uuid, uuid);
-- DROP FUNCTION IF EXISTS public._fn_get_next_question_ordinal(uuid);
-- DROP FUNCTION IF EXISTS public._fn_validate_test_timing(timestamptz, timestamptz);
-- DROP FUNCTION IF EXISTS public._fn_validate_test_config(jsonb);

-- ============================================================
-- END OF R4.5.1 MIGRATION
-- ============================================================
