-- ============================================================
-- R4.3 DISCOVERY VALIDATION
-- Run BEFORE executing R4.3 migration
-- Date: 2026-09-12
--
-- Purpose: Verify current live state before making changes.
-- Execute these queries and report results.
-- ============================================================

-- ============================================================
-- D1: Current function definitions
-- ============================================================
SELECT 'D1: Function Definitions' AS check_name;

SELECT
  p.proname AS function_name,
  pg_get_function_arguments(p.oid) AS arguments,
  pg_get_function_result(p.oid) AS return_type,
  p.prosecdef AS is_security_definer,
  p.proconfig AS config,
  l.lanname AS language
FROM pg_proc p
JOIN pg_language l ON p.prolang = l.oid
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
    'rpc_start_attempt',
    'rpc_start_attempt_by_code',
    'fn_can_access_test',
    'get_test_questions_safe',
    'rpc_save_answers',
    'rpc_submit_attempt',
    'fn_score_attempt'
  )
ORDER BY p.proname;

-- ============================================================
-- D2: Function source code (key functions)
-- ============================================================
SELECT 'D2: rpc_start_attempt Source' AS check_name;
SELECT pg_get_functiondef(p.oid) AS full_definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'rpc_start_attempt';

SELECT 'D2: fn_can_access_test Source' AS check_name;
SELECT pg_get_functiondef(p.oid) AS full_definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'fn_can_access_test';

-- ============================================================
-- D3: tests table RLS policies
-- ============================================================
SELECT 'D3: tests RLS Policies' AS check_name;
SELECT
  schemaname,
  tablename,
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

-- ============================================================
-- D4: tests table column list
-- ============================================================
SELECT 'D4: tests Columns' AS check_name;
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'tests'
ORDER BY ordinal_position;

-- ============================================================
-- D5: attempts table column list
-- ============================================================
SELECT 'D5: attempts Columns' AS check_name;
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'attempts'
ORDER BY ordinal_position;

-- ============================================================
-- D6: Function execute grants
-- ============================================================
SELECT 'D6: Function Execute Grants' AS check_name;
SELECT
  grantee,
  routine_schema,
  routine_name,
  privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN (
    'rpc_start_attempt',
    'rpc_start_attempt_by_code',
    'fn_can_access_test',
    'get_test_questions_safe',
    'rpc_save_answers',
    'rpc_submit_attempt',
    'fn_score_attempt'
  )
ORDER BY routine_name, grantee;

-- ============================================================
-- D7: tests table grants
-- ============================================================
SELECT 'D7: tests Table Grants' AS check_name;
SELECT
  grantee,
  table_schema,
  table_name,
  privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'tests'
ORDER BY grantee, privilege_type;

-- ============================================================
-- D8: attempts table grants
-- ============================================================
SELECT 'D8: attempts Table Grants' AS check_name;
SELECT
  grantee,
  table_schema,
  table_name,
  privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'attempts'
ORDER BY grantee, privilege_type;

-- ============================================================
-- D9: attempts unique constraints
-- ============================================================
SELECT 'D9: attempts Unique Constraints' AS check_name;
SELECT
  tc.constraint_name,
  string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position) AS columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
WHERE tc.table_name = 'attempts'
  AND tc.table_schema = 'public'
  AND tc.constraint_type IN ('UNIQUE', 'PRIMARY KEY')
GROUP BY tc.constraint_name;

-- ============================================================
-- D10: attempts indexes
-- ============================================================
SELECT 'D10: attempts Indexes' AS check_name;
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'attempts'
ORDER BY indexname;

-- ============================================================
-- D11: Recursive attempts RLS check
-- ============================================================
SELECT 'D11: Recursive attempts RLS' AS check_name;
SELECT
  policyname,
  cmd,
  qual
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'attempts'
  AND qual LIKE '%attempts%'
ORDER BY policyname;

-- ============================================================
-- D12: questions table RLS and grants
-- ============================================================
SELECT 'D12: questions RLS Policies' AS check_name;
SELECT
  policyname,
  cmd,
  roles,
  qual
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'questions'
ORDER BY policyname;

SELECT 'D12: questions Table Grants' AS check_name;
SELECT
  grantee,
  privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'questions'
ORDER BY grantee, privilege_type;

-- ============================================================
-- D13: questions_safe view exists
-- ============================================================
SELECT 'D13: questions_safe View' AS check_name;
SELECT
  table_name,
  view_definition
FROM information_schema.views
WHERE table_schema = 'public'
  AND table_name = 'questions_safe';

-- ============================================================
-- D14: Row counts (data integrity baseline)
-- ============================================================
SELECT 'D14: Row Counts' AS check_name;
SELECT 'tests' AS table_name, COUNT(*) AS row_count FROM public.tests
UNION ALL
SELECT 'attempts', COUNT(*) FROM public.attempts
UNION ALL
SELECT 'answers', COUNT(*) FROM public.answers
UNION ALL
SELECT 'questions', COUNT(*) FROM public.questions
UNION ALL
SELECT 'results', COUNT(*) FROM public.results
UNION ALL
SELECT 'test_invitations', COUNT(*) FROM public.test_invitations
UNION ALL
SELECT 'subjects', COUNT(*) FROM public.subjects
UNION ALL
SELECT 'syllabus_nodes', COUNT(*) FROM public.syllabus_nodes;

-- ============================================================
-- D15: Check if rpc_start_attempt_by_code already exists
-- ============================================================
SELECT 'D15: rpc_start_attempt_by_code Exists?' AS check_name;
SELECT EXISTS (
  SELECT 1 FROM pg_proc
  WHERE pronamespace = 'public'::regnamespace
    AND proname = 'rpc_start_attempt_by_code'
) AS already_exists;

-- ============================================================
-- D16: Check for "coded tests readable" policy
-- ============================================================
SELECT 'D16: Coded Tests Readable Policy' AS check_name;
SELECT
  policyname,
  cmd,
  qual
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'tests'
  AND policyname LIKE '%coded%'
ORDER BY policyname;

-- ============================================================
-- D17: Check access_code/join_code column existence
-- ============================================================
SELECT 'D17: access_code/join_code Columns' AS check_name;
SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'tests'
  AND column_name IN ('access_code', 'join_code')
ORDER BY column_name;

-- ============================================================
-- END OF DISCOVERY
-- ============================================================
