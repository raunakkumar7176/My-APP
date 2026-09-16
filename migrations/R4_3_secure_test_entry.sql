-- ============================================================
-- R4.3 PHASE: SECURE TEST ENTRY & ATTEMPT RPC
-- My Preparation — Flutter + Supabase
-- Date: 2026-09-12
-- Status: APPROVED
--
-- PREREQUISITES:
-- - R4.1 executed (tables exist)
-- - R4.2 partially complete (some hardening done)
-- - Discovery queries run (R4_3_discovery.sql)
--
-- RULES:
-- - Do NOT seed syllabus data
-- - Do NOT modify syllabus
-- - Do NOT redesign tests schema
-- - Do NOT delete existing test data
-- - Do NOT truncate tables
-- - Do NOT drop existing tables
-- - Do NOT modify unrelated RLS
-- - Do NOT expose access_code or join_code
-- - Do NOT expose questions.correct_option
-- - Do NOT use service_role in Flutter
--
-- EXECUTION: Run via Supabase SQL Editor AFTER discovery
-- ROLLBACK: See ROLLBACK section at end of file
-- ============================================================

-- ============================================================
-- SECTION 1: DATA INTEGRITY BASELINE
-- Capture row counts BEFORE any changes
-- ============================================================

CREATE TEMPORARY TABLE _r43_before AS
SELECT
  (SELECT COUNT(*) FROM public.tests) AS tests_count,
  (SELECT COUNT(*) FROM public.attempts) AS attempts_count,
  (SELECT COUNT(*) FROM public.answers) AS answers_count,
  (SELECT COUNT(*) FROM public.questions) AS questions_count,
  (SELECT COUNT(*) FROM public.results) AS results_count,
  (SELECT COUNT(*) FROM public.test_invitations) AS invitations_count;

-- ============================================================
-- SECTION 2: SHARED HELPER FUNCTION
-- _fn_start_attempt_core(p_test uuid)
--
-- Contains the common attempt-start logic used by both:
--   rpc_start_attempt(test_id) — normal authorized access
--   rpc_start_attempt_by_code(code) — coded test entry
--
-- SECURITY DEFINER: Bypasses RLS for attempt creation
-- search_path = '': All objects fully qualified
-- ============================================================

CREATE OR REPLACE FUNCTION public._fn_start_attempt_core(p_test uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_test record;
  v_attempt record;
  v_deadline timestamptz;
  v_status text;
BEGIN
  -- Auth check
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  -- Load test with access check
  SELECT t.* INTO v_test
  FROM public.tests t
  WHERE t.id = p_test;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TEST_NOT_FOUND';
  END IF;

  -- Soft-delete check
  IF v_test.is_soft_deleted THEN
    RAISE EXCEPTION 'TEST_NOT_AVAILABLE';
  END IF;

  -- Access check via existing function
  IF NOT public.fn_can_access_test(p_test) THEN
    RAISE EXCEPTION 'TEST_ACCESS_DENIED';
  END IF;

  -- Lifecycle check
  v_status := v_test.status::text;

  IF v_status IN ('cancelled', 'archived', 'expired') THEN
    RAISE EXCEPTION 'TEST_NOT_AVAILABLE';
  END IF;

  IF v_status IN ('completed', 'ended', 'evaluated') THEN
    RAISE EXCEPTION 'TEST_ENDED';
  END IF;

  -- Must be scheduled or live
  IF v_status NOT IN ('scheduled', 'live', 'ready', 'published') THEN
    RAISE EXCEPTION 'TEST_NOT_AVAILABLE';
  END IF;

  -- Timing: starts_at check
  IF v_test.starts_at IS NOT NULL AND now() < v_test.starts_at THEN
    RAISE EXCEPTION 'TEST_NOT_STARTED';
  END IF;

  -- Timing: ends_at check (unless allow_late_join)
  IF v_test.ends_at IS NOT NULL AND now() > v_test.ends_at THEN
    IF NOT v_test.allow_late_join THEN
      RAISE EXCEPTION 'TEST_ENDED';
    END IF;
  END IF;

  -- Max participants check
  IF v_test.max_participants IS NOT NULL THEN
    IF (SELECT count(*) FROM public.attempts a WHERE a.test_id = p_test) >= v_test.max_participants THEN
      RAISE EXCEPTION 'TEST_FULL';
    END IF;
  END IF;

  -- Check for existing attempt
  SELECT a.* INTO v_attempt
  FROM public.attempts a
  WHERE a.test_id = p_test AND a.user_id = v_uid
    AND a.status IN ('in_progress', 'active')
  ORDER BY a.started_at DESC
  LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'attempt_id', v_attempt.id,
      'test_id', p_test,
      'status', 'resumed',
      'started_at', v_attempt.started_at,
      'deadline_at', v_attempt.deadline_at
    );
  END IF;

  -- Calculate deadline
  IF v_test.ends_at IS NOT NULL THEN
    v_deadline := LEAST(
      now() + (COALESCE(v_test.duration_sec, 3600) || ' seconds')::interval,
      v_test.ends_at
    );
  ELSE
    v_deadline := now() + (COALESCE(v_test.duration_sec, 3600) || ' seconds')::interval;
  END IF;

  -- Create new attempt
  INSERT INTO public.attempts (test_id, user_id, status, started_at, deadline_at)
  VALUES (p_test, v_uid, 'in_progress', now(), v_deadline)
  RETURNING * INTO v_attempt;

  RETURN jsonb_build_object(
    'attempt_id', v_attempt.id,
    'test_id', p_test,
    'status', 'started',
    'started_at', v_attempt.started_at,
    'deadline_at', v_attempt.deadline_at
  );
END;
$function$;

-- ============================================================
-- SECTION 3: NEW RPC — rpc_start_attempt_by_code(text)
--
-- Secure code-based test entry.
-- Resolves access_code or join_code to test_id,
-- then delegates to shared helper.
-- ============================================================

CREATE OR REPLACE FUNCTION public.rpc_start_attempt_by_code(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_normalized text;
  v_test record;
  v_test_count bigint;
  v_result jsonb;
BEGIN
  -- Auth check
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  -- Code normalization: trim whitespace, lowercase
  v_normalized := LOWER(TRIM(p_code));

  IF v_normalized = '' OR v_normalized IS NULL THEN
    RAISE EXCEPTION 'TEST_CODE_INVALID';
  END IF;

  -- Count matching tests (safety: detect ambiguity)
  SELECT count(*) INTO v_test_count
  FROM public.tests t
  WHERE t.is_soft_deleted = false
    AND (
      t.access_code = v_normalized
      OR t.join_code = v_normalized
    );

  IF v_test_count = 0 THEN
    RAISE EXCEPTION 'TEST_CODE_INVALID';
  END IF;

  IF v_test_count > 1 THEN
    -- Multiple tests share the same code — this is a data integrity issue
    RAISE EXCEPTION 'TEST_CODE_AMBIGUOUS: multiple tests match this code';
  END IF;

  -- Locate the single matching test
  SELECT t.* INTO v_test
  FROM public.tests t
  WHERE t.is_soft_deleted = false
    AND (
      t.access_code = v_normalized
      OR t.join_code = v_normalized
    )
  LIMIT 1;

  -- Delegate to shared helper (applies lifecycle, timing, access checks)
  v_result := public._fn_start_attempt_core(v_test.id);

  -- Append code metadata (NOT the code itself)
  v_result := v_result || jsonb_build_object(
    'entry_method', 'code',
    'test_title', v_test.title
  );

  RETURN v_result;
END;
$function$;

-- ============================================================
-- SECTION 4: REFACTOR EXISTING rpc_start_attempt(uuid)
--
-- Refactored to delegate to shared helper.
-- Signature unchanged — existing Flutter code remains compatible.
-- ============================================================

CREATE OR REPLACE FUNCTION public.rpc_start_attempt(p_test uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_result jsonb;
BEGIN
  -- Delegate to shared helper
  v_result := public._fn_start_attempt_core(p_test);

  -- Append entry method metadata
  v_result := v_result || jsonb_build_object(
    'entry_method', 'direct'
  );

  RETURN v_result;
END;
$function$;

-- ============================================================
-- SECTION 5: REMOVE CODE LEAK POLICY
-- DROP the dangerous "coded tests readable" policy
-- ============================================================

DROP POLICY IF EXISTS "coded tests readable" ON public.tests;

-- Verify no policy exposes access_code or join_code
-- (Run D3 discovery query after this to confirm)

-- ============================================================
-- SECTION 6: FUNCTION PRIVILEGES
-- Least-privilege grants for new and existing functions
-- ============================================================

-- rpc_start_attempt_by_code: authenticated only
REVOKE EXECUTE ON FUNCTION public.rpc_start_attempt_by_code(text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.rpc_start_attempt_by_code(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.rpc_start_attempt_by_code(text) TO authenticated;

-- rpc_start_attempt: verify existing grants (should already be correct)
-- REVOKE EXECUTE ON FUNCTION public.rpc_start_attempt(uuid) FROM PUBLIC;
-- REVOKE EXECUTE ON FUNCTION public.rpc_start_attempt(uuid) FROM anon;
-- GRANT EXECUTE ON FUNCTION public.rpc_start_attempt(uuid) TO authenticated;

-- _fn_start_attempt_core: internal only — no direct EXECUTE grants
REVOKE EXECUTE ON FUNCTION public._fn_start_attempt_core(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public._fn_start_attempt_core(uuid) FROM anon;
REVOKE EXECUTE ON FUNCTION public._fn_start_attempt_core(uuid) FROM authenticated;
-- Only postgres/service_role can call the internal helper

-- ============================================================
-- SECTION 7: SEARCH PATH HARDENING
-- Review and harden attempt-related functions
-- ============================================================

-- NOTE: The following functions are LEFT UNCHANGED because:
-- 1. fn_can_access_test — already has search_path = '' (verified in discovery)
-- 2. rpc_save_answers — already hardened in R4.2 (authenticated + postgres only)
-- 3. rpc_submit_attempt — already hardened in R4.2 (authenticated + postgres only)
-- 4. fn_score_attempt — already hardened in R4.2 (postgres only)
--
-- The refactored rpc_start_attempt now has search_path = '' (Section 4).
-- The new rpc_start_attempt_by_code has search_path = '' (Section 3).
-- The shared helper _fn_start_attempt_core has search_path = '' (Section 2).
--
-- If discovery reveals any of these functions still use search_path = 'public',
-- they should be hardened separately with careful regression testing.

-- ============================================================
-- SECTION 8: DATA INTEGRITY VERIFICATION
-- Capture row counts AFTER changes and compare
-- ============================================================

CREATE TEMPORARY TABLE _r43_after AS
SELECT
  (SELECT COUNT(*) FROM public.tests) AS tests_count,
  (SELECT COUNT(*) FROM public.attempts) AS attempts_count,
  (SELECT COUNT(*) FROM public.answers) AS answers_count,
  (SELECT COUNT(*) FROM public.questions) AS questions_count,
  (SELECT COUNT(*) FROM public.results) AS results_count,
  (SELECT COUNT(*) FROM public.test_invitations) AS invitations_count;

-- Compare before/after
SELECT
  'tests' AS table_name,
  b.tests_count AS before_count,
  a.tests_count AS after_count,
  CASE WHEN b.tests_count = a.tests_count THEN 'PASS' ELSE 'FAIL' END AS status
FROM _r43_before b, _r43_after a
UNION ALL
SELECT 'attempts', b.attempts_count, a.attempts_count,
  CASE WHEN b.attempts_count = a.attempts_count THEN 'PASS' ELSE 'FAIL' END
FROM _r43_before b, _r43_after a
UNION ALL
SELECT 'answers', b.answers_count, a.answers_count,
  CASE WHEN b.answers_count = a.answers_count THEN 'PASS' ELSE 'FAIL' END
FROM _r43_before b, _r43_after a
UNION ALL
SELECT 'questions', b.questions_count, a.questions_count,
  CASE WHEN b.questions_count = a.questions_count THEN 'PASS' ELSE 'FAIL' END
FROM _r43_before b, _r43_after a
UNION ALL
SELECT 'results', b.results_count, a.results_count,
  CASE WHEN b.results_count = a.results_count THEN 'PASS' ELSE 'FAIL' END
FROM _r43_before b, _r43_after a
UNION ALL
SELECT 'invitations', b.invitations_count, a.invitations_count,
  CASE WHEN b.invitations_count = a.invitations_count THEN 'PASS' ELSE 'FAIL' END
FROM _r43_before b, _r43_after a;

-- Cleanup
DROP TABLE IF EXISTS _r43_before;
DROP TABLE IF EXISTS _r43_after;

-- ============================================================
-- SECTION 9: VALIDATION QUERIES
-- Run after migration to verify correctness
-- ============================================================

-- V1: New function exists with correct signature
SELECT 'V1: rpc_start_attempt_by_code Exists' AS check_name;
SELECT
  p.proname,
  pg_get_function_arguments(p.oid) AS args,
  p.prosecdef AS security_definer,
  p.proconfig AS config
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'rpc_start_attempt_by_code';

-- V2: Shared helper exists
SELECT 'V2: _fn_start_attempt_core Exists' AS check_name;
SELECT
  p.proname,
  pg_get_function_arguments(p.oid) AS args,
  p.prosecdef AS security_definer,
  p.proconfig AS config
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = '_fn_start_attempt_core';

-- V3: Refactored rpc_start_attempt uses helper
SELECT 'V3: rpc_start_attempt Source Updated' AS check_name;
SELECT pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'rpc_start_attempt';

-- V4: "coded tests readable" policy removed
SELECT 'V4: Coded Tests Readable Removed' AS check_name;
SELECT count(*) AS remaining_policies
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'tests'
  AND policyname LIKE '%coded%';
-- Expected: 0

-- V5: Function privileges
SELECT 'V5: Function Privileges' AS check_name;
SELECT
  grantee,
  routine_name,
  privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN ('rpc_start_attempt_by_code', '_fn_start_attempt_core')
ORDER BY routine_name, grantee;

-- V6: No access_code/join_code in function definitions
SELECT 'V6: No Code Exposure' AS check_name;
SELECT
  p.proname,
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%access_code%' THEN 'EXPOSED'
    WHEN pg_get_functiondef(p.oid) LIKE '%join_code%' THEN 'EXPOSED'
    ELSE 'SAFE'
  END AS code_exposure_check
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN ('rpc_start_attempt_by_code', '_fn_start_attempt_core', 'rpc_start_attempt');

-- V7: No correct_option in function definitions
SELECT 'V7: No Answer Key Exposure' AS check_name;
SELECT
  p.proname,
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%correct_option%' THEN 'EXPOSED'
    WHEN pg_get_functiondef(p.oid) LIKE '%is_correct%' THEN 'EXPOSED'
    ELSE 'SAFE'
  END AS answer_key_check
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN ('rpc_start_attempt_by_code', '_fn_start_attempt_core', 'rpc_start_attempt');

-- V8: tests policies after removal
SELECT 'V8: tests Policies Final' AS check_name;
SELECT
  policyname,
  cmd,
  roles,
  qual
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'tests'
ORDER BY policyname;

-- V9: attempts unique constraint
SELECT 'V9: attempts Unique Constraint' AS check_name;
SELECT
  tc.constraint_name,
  string_agg(kcu.column_name, ', ') AS columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
WHERE tc.table_name = 'attempts'
  AND tc.table_schema = 'public'
  AND tc.constraint_type IN ('UNIQUE', 'PRIMARY KEY')
GROUP BY tc.constraint_name;

-- V10: No recursive attempts RLS
SELECT 'V10: No Recursive attempts RLS' AS check_name;
SELECT
  policyname,
  cmd,
  qual
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'attempts'
  AND (qual LIKE '%attempts%' OR with_check LIKE '%attempts%');
-- Expected: 0 rows (no self-referencing policies)

-- V11: questions_safe view still exists
SELECT 'V11: questions_safe View' AS check_name;
SELECT
  table_name,
  view_definition
FROM information_schema.views
WHERE table_schema = 'public'
  AND table_name = 'questions_safe';

-- V12: questions SELECT revoked from authenticated
SELECT 'V12: questions SELECT Revoked' AS check_name;
SELECT
  grantee,
  privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'questions'
  AND grantee = 'authenticated'
  AND privilege_type = 'SELECT';
-- Expected: 0 rows (SELECT revoked)

-- ============================================================
-- ROLLBACK SCRIPT
-- ============================================================
-- Execute this to undo R4.3 changes.
-- WARNING: This restores the original rpc_start_attempt.

-- -- Restore original rpc_start_attempt (without helper delegation)
-- CREATE OR REPLACE FUNCTION public.rpc_start_attempt(p_test uuid)
-- RETURNS jsonb
-- LANGUAGE plpgsql
-- SECURITY DEFINER
-- SET search_path TO 'public'
-- AS $function$
-- BEGIN
--   -- Original implementation would need to be restored from backup
--   -- This is a placeholder — restore from pre-R4.3 function dump
--   RAISE EXCEPTION 'ROLLBACK: Original function must be restored from backup';
-- END;
-- $function$;
--
-- DROP FUNCTION IF EXISTS public.rpc_start_attempt_by_code(text);
-- DROP FUNCTION IF EXISTS public._fn_start_attempt_core(uuid);
--
-- -- Restore "coded tests readable" policy if needed
-- -- (Original definition needed from discovery)

-- ============================================================
-- END OF R4.3 MIGRATION
-- ============================================================
