-- ============================================================
-- R4.3 SECURITY VALIDATION
-- Run AFTER executing R4_3_secure_test_entry.sql
-- Date: 2026-09-12
--
-- Purpose: Comprehensive security verification.
-- All checks must pass for R4.3 to be marked PASS.
-- ============================================================

-- ============================================================
-- S1: FUNCTION SECURITY — prosecdef, proconfig, identity
-- ============================================================
SELECT 'S1: Function Security' AS check_name;
SELECT
  p.proname AS function_name,
  p.prosecdef AS security_definer,
  p.proconfig AS config,
  pg_get_function_arguments(p.oid) AS arguments,
  pg_get_function_result(p.oid) AS return_type,
  l.lanname AS language
FROM pg_proc p
JOIN pg_language l ON p.prolang = l.oid
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
    'rpc_start_attempt',
    'rpc_start_attempt_by_code',
    '_fn_start_attempt_core',
    'fn_can_access_test',
    'get_test_questions_safe',
    'rpc_save_answers',
    'rpc_submit_attempt',
    'fn_score_attempt'
  )
ORDER BY p.proname;

-- Verify all are SECURITY DEFINER
SELECT
  'All functions SECURITY DEFINER' AS check_name,
  CASE
    WHEN COUNT(*) = 0 THEN 'PASS — all are SECURITY DEFINER'
    ELSE 'FAIL — non-SECURITY DEFINER functions found'
  END AS result
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
    'rpc_start_attempt',
    'rpc_start_attempt_by_code',
    '_fn_start_attempt_core'
  )
  AND p.prosecdef = false;

-- Verify all have search_path = ''
SELECT
  'All functions have search_path = empty' AS check_name,
  CASE
    WHEN COUNT(*) = 0 THEN 'PASS'
    ELSE 'FAIL — functions without empty search_path found'
  END AS result
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
    'rpc_start_attempt',
    'rpc_start_attempt_by_code',
    '_fn_start_attempt_core'
  )
  AND (p.proconfig IS NULL OR NOT (p.proconfig @> ARRAY['search_path=']));

-- ============================================================
-- S2: FUNCTION PRIVILEGES
-- ============================================================
SELECT 'S2: Function Privileges' AS check_name;
SELECT
  grantee,
  routine_name,
  privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN (
    'rpc_start_attempt',
    'rpc_start_attempt_by_code',
    '_fn_start_attempt_core'
  )
ORDER BY routine_name, grantee;

-- Verify: anon cannot execute any attempt functions
SELECT
  'anon cannot execute attempt functions' AS check_name,
  CASE
    WHEN COUNT(*) = 0 THEN 'PASS'
    ELSE 'FAIL — anon has execute on attempt functions'
  END AS result
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN ('rpc_start_attempt', 'rpc_start_attempt_by_code', '_fn_start_attempt_core')
  AND grantee = 'anon';

-- Verify: public cannot execute attempt functions
SELECT
  'public cannot execute attempt functions' AS check_name,
  CASE
    WHEN COUNT(*) = 0 THEN 'PASS'
    ELSE 'FAIL — public has execute on attempt functions'
  END AS result
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN ('rpc_start_attempt', 'rpc_start_attempt_by_code', '_fn_start_attempt_core')
  AND grantee = 'public';

-- Verify: authenticated can execute rpc_start_attempt and rpc_start_attempt_by_code
SELECT
  'authenticated can execute rpc_start_attempt' AS check_name,
  CASE
    WHEN COUNT(*) > 0 THEN 'PASS'
    ELSE 'FAIL — authenticated cannot execute rpc_start_attempt'
  END AS result
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name = 'rpc_start_attempt'
  AND grantee = 'authenticated';

SELECT
  'authenticated can execute rpc_start_attempt_by_code' AS check_name,
  CASE
    WHEN COUNT(*) > 0 THEN 'PASS'
    ELSE 'FAIL — authenticated cannot execute rpc_start_attempt_by_code'
  END AS result
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name = 'rpc_start_attempt_by_code'
  AND grantee = 'authenticated';

-- Verify: authenticated CANNOT execute _fn_start_attempt_core
SELECT
  'authenticated cannot execute _fn_start_attempt_core' AS check_name,
  CASE
    WHEN COUNT(*) = 0 THEN 'PASS'
    ELSE 'FAIL — authenticated can execute internal helper'
  END AS result
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name = '_fn_start_attempt_core'
  AND grantee = 'authenticated';

-- ============================================================
-- S3: tests POLICIES AFTER REMOVAL
-- ============================================================
SELECT 'S3: tests Policies' AS check_name;
SELECT
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'tests'
ORDER BY policyname;

-- Verify: "coded tests readable" is gone
SELECT
  '"coded tests readable" policy removed' AS check_name,
  CASE
    WHEN COUNT(*) = 0 THEN 'PASS'
    ELSE 'FAIL — policy still exists'
  END AS result
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'tests'
  AND policyname = 'coded tests readable';

-- Verify: no policy exposes access_code or join_code in qual
SELECT
  'No policy exposes access_code/join_code' AS check_name,
  CASE
    WHEN COUNT(*) = 0 THEN 'PASS'
    ELSE 'WARN — policies reference access_code/join_code (review manually)'
  END AS result
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'tests'
  AND (qual LIKE '%access_code%' OR qual LIKE '%join_code%'
       OR with_check LIKE '%access_code%' OR with_check LIKE '%join_code%');

-- ============================================================
-- S4: tests TABLE GRANTS
-- ============================================================
SELECT 'S4: tests Table Grants' AS check_name;
SELECT
  grantee,
  privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'tests'
ORDER BY grantee, privilege_type;

-- Verify: anon has no SELECT on tests
SELECT
  'anon has no SELECT on tests' AS check_name,
  CASE
    WHEN COUNT(*) = 0 THEN 'PASS'
    ELSE 'FAIL — anon has SELECT on tests'
  END AS result
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'tests'
  AND grantee = 'anon'
  AND privilege_type = 'SELECT';

-- ============================================================
-- S5: attempts UNIQUE CONSTRAINT/INDEX
-- ============================================================
SELECT 'S5: attempts Unique Constraint' AS check_name;
SELECT
  tc.constraint_name,
  tc.constraint_type,
  string_agg(kcu.column_name, ', ') AS columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
WHERE tc.table_name = 'attempts'
  AND tc.table_schema = 'public'
  AND tc.constraint_type IN ('UNIQUE', 'PRIMARY KEY')
GROUP BY tc.constraint_name, tc.constraint_type;

-- ============================================================
-- S6: No recursive attempts RLS
-- ============================================================
SELECT 'S6: No Recursive attempts RLS' AS check_name;
SELECT
  policyname,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'attempts'
  AND (
    qual LIKE '%attempts%'
    OR with_check LIKE '%attempts%'
  );
-- Expected: 0 rows

SELECT
  'No recursive attempts RLS' AS check_name,
  CASE
    WHEN (
      SELECT count(*)
      FROM pg_policies
      WHERE schemaname = 'public'
        AND tablename = 'attempts'
        AND (qual LIKE '%attempts%' OR with_check LIKE '%attempts%')
    ) = 0 THEN 'PASS'
    ELSE 'FAIL — recursive policy detected'
  END AS result;

-- ============================================================
-- S7: rpc_start_attempt_by_code does NOT return codes
-- ============================================================
SELECT 'S7: No Code Exposure in RPC' AS check_name;
SELECT
  p.proname,
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%RETURN%access_code%' THEN 'EXPOSED — FAIL'
    WHEN pg_get_functiondef(p.oid) LIKE '%RETURN%join_code%' THEN 'EXPOSED — FAIL'
    WHEN pg_get_functiondef(p.oid) LIKE '%access_code%INTO%' THEN 'EXPOSED — FAIL'
    ELSE 'SAFE — codes not in RETURN'
  END AS code_exposure
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'rpc_start_attempt_by_code';

-- ============================================================
-- S8: rpc_start_attempt_by_code only works for authenticated
-- ============================================================
SELECT 'S8: Auth Required for Code Entry' AS check_name;
-- Check function body starts with auth.uid() check
SELECT
  p.proname,
  CASE
    WHEN pg_get_functiondef(p.oid) LIKE '%auth.uid()%' THEN 'PASS — auth check present'
    ELSE 'FAIL — no auth check'
  END AS auth_check
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'rpc_start_attempt_by_code';

-- ============================================================
-- S9: questions_safe view exists and strips is_correct
-- ============================================================
SELECT 'S9: questions_safe View' AS check_name;
SELECT
  table_name,
  view_definition
FROM information_schema.views
WHERE table_schema = 'public'
  AND table_name = 'questions_safe';

-- Verify: questions_safe does NOT contain is_correct
SELECT
  'questions_safe strips is_correct' AS check_name,
  CASE
    WHEN (
      SELECT view_definition
      FROM information_schema.views
      WHERE table_schema = 'public'
        AND table_name = 'questions_safe'
    ) LIKE '%is_correct%' THEN 'FAIL — is_correct visible in view'
    ELSE 'PASS — is_correct stripped'
  END AS result;

-- ============================================================
-- S10: questions SELECT revoked from authenticated
-- ============================================================
SELECT 'S10: questions SELECT Revoked' AS check_name;
SELECT
  grantee,
  privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'questions'
  AND grantee = 'authenticated'
  AND privilege_type = 'SELECT';
-- Expected: 0 rows

-- ============================================================
-- S11: fn_can_access_test definition check
-- ============================================================
SELECT 'S11: fn_can_access_test Definition' AS check_name;
SELECT pg_get_functiondef(p.oid) AS definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'fn_can_access_test';

-- ============================================================
-- S12: Overall Security Summary
-- ============================================================
SELECT 'S12: Security Summary' AS check_name;
SELECT
  (SELECT count(*) FROM pg_proc p
   WHERE p.pronamespace = 'public'::regnamespace
     AND p.proname IN ('rpc_start_attempt', 'rpc_start_attempt_by_code', '_fn_start_attempt_core')
     AND p.prosecdef = true
  ) AS security_definer_count,
  (SELECT count(*) FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename = 'tests'
     AND policyname = 'coded tests readable'
  ) AS coded_tests_policy_count,
  (SELECT count(*) FROM pg_policies
   WHERE schemaname = 'public'
     AND tablename = 'attempts'
     AND (qual LIKE '%attempts%' OR with_check LIKE '%attempts%')
  ) AS recursive_attempts_policies,
  (SELECT count(*) FROM information_schema.table_privileges
   WHERE table_schema = 'public'
     AND table_name = 'questions'
     AND grantee = 'authenticated'
     AND privilege_type = 'SELECT'
  ) AS questions_select_authenticated;

-- ============================================================
-- END OF SECURITY VALIDATION
-- ============================================================
