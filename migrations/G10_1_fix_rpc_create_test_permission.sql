-- ============================================================
-- G10.1 — LIVE DEFECT FIX (PROPOSED — NOT APPLIED): rpc_create_test
-- ============================================================
-- Found by the G10 live audit (2026-09-19, rolled-back transaction):
--   rpc_create_test is SECURITY DEFINER and only checks "authenticated"
--   (_fn_can_create_test), so ANY signed-in user can create a
--   test_mode = 'group' test with ANY group_id — bypassing the live RLS
--   policy "group create test" (CREATE_TEST in that group). Proven live:
--   member without CREATE_TEST → created; non-member → created; leader of
--   another group → created in a group they are not in.
-- Fix: the six-line block marked "G10.1 fix" below (qualified names because
-- the function runs with search_path = ''). Everything else is the live
-- definition verbatim (pg_get_functiondef). Standalone (self/live) creation
-- is unchanged. Proven sufficient in a rolled-back transaction: leader with
-- CREATE_TEST → OK; forged group → denied; non-member → denied; self test → OK.
-- Rollback: re-run the previous definition (this file minus the block).
-- ============================================================

CREATE OR REPLACE FUNCTION public.rpc_create_test(p_title text, p_description text DEFAULT ''::text, p_duration_sec integer DEFAULT 3600, p_marks_per_question numeric DEFAULT 1, p_negative_marks numeric DEFAULT 0, p_test_mode text DEFAULT 'self'::text, p_creation_method text DEFAULT 'manual'::text, p_group_id uuid DEFAULT NULL::uuid, p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_ends_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_max_participants integer DEFAULT NULL::integer, p_allow_late_join boolean DEFAULT false, p_config jsonb DEFAULT '{}'::jsonb, p_settings jsonb DEFAULT '{}'::jsonb, p_access_code text DEFAULT NULL::text, p_join_code text DEFAULT NULL::text)
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
  v_uid := public._fn_auth_uid();

  IF NOT public._fn_can_create_test(v_uid) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: Cannot create tests';
  END IF;

  IF p_title IS NULL OR TRIM(p_title) = '' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: title is required and cannot be empty';
  END IF;

  IF p_duration_sec < 60 OR p_duration_sec > 21600 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: duration_sec must be between 60 and 21600';
  END IF;

  IF p_marks_per_question <= 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: marks_per_question must be greater than 0';
  END IF;

  IF p_negative_marks < 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: negative_marks cannot be negative';
  END IF;

  IF p_test_mode IS NOT NULL
     AND p_test_mode NOT IN ('self', 'live', 'group') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: test_mode must be self, live, group, or null';
  END IF;

  IF p_creation_method IS NOT NULL
     AND p_creation_method NOT IN ('manual', 'upload', 'ai', 'mixed') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: creation_method must be manual, upload, ai, mixed, or null';
  END IF;

  IF p_max_participants IS NOT NULL
     AND (p_max_participants < 2 OR p_max_participants > 10000) THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: max_participants must be NULL or between 2 and 10000';
  END IF;

  PERFORM public._fn_validate_test_timing(p_starts_at, p_ends_at);
  PERFORM public._fn_validate_test_config(p_config);

  IF p_test_mode = 'group' AND p_group_id IS NULL THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: group_id is required for group tests';
  END IF;
  -- G10.1 fix: a group test needs CREATE_TEST in that group (mirrors the
  -- live RLS policy "group create test", which this DEFINER function bypasses).
  IF p_test_mode = 'group'
     AND NOT public.fn_has_permission(p_group_id, v_uid, 'CREATE_TEST'::public.app_permission) THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: CREATE_TEST is required to create a test in this group';
  END IF;

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
    'draft'::public.test_status
  )
  RETURNING id, created_at INTO v_test_id, v_created_at;

  RETURN jsonb_build_object(
    'test_id', v_test_id,
    'created_at', v_created_at,
    'status', 'draft',
    'message', 'Test created successfully'
  );
END;
$function$
;

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only; last statement)
-- Expected: has_fix = true
-- ------------------------------------------------------------
SELECT (p.prosrc LIKE '%G10.1 fix%') AS has_fix,
       p.prosecdef AS security_definer,
       p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_create_test';
