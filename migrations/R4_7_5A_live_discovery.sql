-- ============================================================
-- R4.7.5A — LIVE SUPABASE DATABASE DISCOVERY
-- READ-ONLY — ABSOLUTELY NO MODIFICATIONS
-- Date: 2026-09-14
--
-- PURPOSE: Execute ALL queries in Supabase SQL Editor.
--          Copy the results back for audit analysis.
--
-- RULES:
-- - Do NOT modify anything
-- - Do NOT run CREATE/ALTER/DROP/INSERT/UPDATE/DELETE
-- - Do NOT change grants, policies, or functions
-- - ONLY read metadata and function definitions
-- ============================================================

-- ============================================================
-- SECTION 1: LIVE TABLE SCHEMA
-- ============================================================

-- 1.1 tests columns
SELECT '1.1 tests columns' AS section;
SELECT
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'tests'
ORDER BY ordinal_position;

-- 1.2 questions columns
SELECT '1.2 questions columns' AS section;
SELECT
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'questions'
ORDER BY ordinal_position;

-- 1.3 attempts columns
SELECT '1.3 attempts columns' AS section;
SELECT
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'attempts'
ORDER BY ordinal_position;

-- 1.4 answers columns
SELECT '1.4 answers columns' AS section;
SELECT
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'answers'
ORDER BY ordinal_position;

-- 1.5 results columns
SELECT '1.5 results columns' AS section;
SELECT
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'results'
ORDER BY ordinal_position;

-- 1.6 ai_reports columns
SELECT '1.6 ai_reports columns' AS section;
SELECT
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'ai_reports'
ORDER BY ordinal_position;

-- 1.7 test_syllabus columns
SELECT '1.7 test_syllabus columns' AS section;
SELECT
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'test_syllabus'
ORDER BY ordinal_position;

-- 1.8 subjects columns
SELECT '1.8 subjects columns' AS section;
SELECT
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'subjects'
ORDER BY ordinal_position;

-- 1.9 syllabus_nodes columns
SELECT '1.9 syllabus_nodes columns' AS section;
SELECT
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'syllabus_nodes'
ORDER BY ordinal_position;

-- 1.10 groups columns
SELECT '1.10 groups columns' AS section;
SELECT
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'groups'
ORDER BY ordinal_position;

-- 1.11 group_members columns
SELECT '1.11 group_members columns' AS section;
SELECT
  column_name,
  data_type,
  udt_name,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'group_members'
ORDER BY ordinal_position;

-- 1.12 All constraints on tests
SELECT '1.12 tests constraints' AS section;
SELECT
  tc.constraint_name,
  tc.constraint_type,
  string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position) AS columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
WHERE tc.table_schema = 'public' AND tc.table_name = 'tests'
GROUP BY tc.constraint_name, tc.constraint_type
ORDER BY tc.constraint_type, tc.constraint_name;

-- 1.13 All constraints on attempts
SELECT '1.13 attempts constraints' AS section;
SELECT
  tc.constraint_name,
  tc.constraint_type,
  string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position) AS columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
WHERE tc.table_schema = 'public' AND tc.table_name = 'attempts'
GROUP BY tc.constraint_name, tc.constraint_type
ORDER BY tc.constraint_type, tc.constraint_name;

-- 1.14 All constraints on answers
SELECT '1.14 answers constraints' AS section;
SELECT
  tc.constraint_name,
  tc.constraint_type,
  string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position) AS columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
WHERE tc.table_schema = 'public' AND tc.table_name = 'answers'
GROUP BY tc.constraint_name, tc.constraint_type
ORDER BY tc.constraint_type, tc.constraint_name;

-- 1.15 All constraints on results
SELECT '1.15 results constraints' AS section;
SELECT
  tc.constraint_name,
  tc.constraint_type,
  string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position) AS columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
WHERE tc.table_schema = 'public' AND tc.table_name = 'results'
GROUP BY tc.constraint_name, tc.constraint_type
ORDER BY tc.constraint_type, tc.constraint_name;

-- 1.16 All CHECK constraints
SELECT '1.16 CHECK constraints' AS section;
SELECT
  tc.table_name,
  tc.constraint_name,
  cc.check_clause
FROM information_schema.table_constraints tc
JOIN information_schema.check_constraints cc
  ON tc.constraint_name = cc.constraint_name
  AND tc.table_schema = cc.constraint_schema
WHERE tc.constraint_type = 'CHECK'
  AND tc.table_schema = 'public'
  AND tc.table_name IN ('tests', 'questions', 'attempts', 'answers', 'results')
ORDER BY tc.table_name, tc.constraint_name;

-- 1.17 All indexes
SELECT '1.17 All indexes' AS section;
SELECT
  indexname,
  tablename,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('tests', 'questions', 'attempts', 'answers', 'results', 'test_syllabus')
ORDER BY tablename, indexname;

-- ============================================================
-- SECTION 2: LIVE ENUMS
-- ============================================================

-- 2.1 test_status enum
SELECT '2.1 test_status enum' AS section;
SELECT e.enumlabel AS value, e.enumsortorder AS sort_order
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
WHERE t.typname = 'test_status'
ORDER BY e.enumsortorder;

-- 2.2 attempt_status enum
SELECT '2.2 attempt_status enum' AS section;
SELECT e.enumlabel AS value, e.enumsortorder AS sort_order
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
WHERE t.typname = 'attempt_status'
ORDER BY e.enumsortorder;

-- 2.3 question_type enum
SELECT '2.3 question_type enum' AS section;
SELECT e.enumlabel AS value, e.enumsortorder AS sort_order
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
WHERE t.typname = 'question_type'
ORDER BY e.enumsortorder;

-- 2.4 difficulty_level enum
SELECT '2.4 difficulty_level enum' AS section;
SELECT e.enumlabel AS value, e.enumsortorder AS sort_order
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
WHERE t.typname = 'difficulty_level'
ORDER BY e.enumsortorder;

-- 2.5 question_status enum (may not exist)
SELECT '2.5 question_status enum' AS section;
SELECT e.enumlabel AS value, e.enumsortorder AS sort_order
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
WHERE t.typname = 'question_status'
ORDER BY e.enumsortorder;

-- 2.6 app_permission enum (may not exist)
SELECT '2.6 app_permission enum' AS section;
SELECT e.enumlabel AS value, e.enumsortorder AS sort_order
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
WHERE t.typname = 'app_permission'
ORDER BY e.enumsortorder;

-- 2.7 All enum types (list all)
SELECT '2.7 All enums in public schema' AS section;
SELECT t.typname AS enum_name,
  array_agg(e.enumlabel ORDER BY e.enumsortorder) AS values
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
WHERE t.typnamespace = 'public'::regnamespace
GROUP BY t.typname
ORDER BY t.typname;

-- ============================================================
-- SECTION 3: LIVE RLS STATUS
-- ============================================================

-- 3.1 RLS status for all relevant tables
SELECT '3.1 RLS status' AS section;
SELECT
  schemaname,
  tablename,
  relrowsecurity AS rls_enabled,
  relforcerowsecurity AS rls_forced
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename IN (
    'tests', 'questions', 'test_syllabus', 'attempts', 'answers',
    'results', 'ai_reports', 'test_invitations', 'groups', 'group_members'
  )
ORDER BY tablename;

-- 3.2 ALL policies on ALL tables
SELECT '3.2 ALL policies' AS section;
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
ORDER BY tablename, policyname;

-- ============================================================
-- SECTION 4: LIVE PRIVILEGES
-- ============================================================

-- 4.1 tests privileges
SELECT '4.1 tests privileges' AS section;
SELECT grantee, privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public' AND table_name = 'tests'
ORDER BY grantee, privilege_type;

-- 4.2 questions privileges
SELECT '4.2 questions privileges' AS section;
SELECT grantee, privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public' AND table_name = 'questions'
ORDER BY grantee, privilege_type;

-- 4.3 attempts privileges
SELECT '4.3 attempts privileges' AS section;
SELECT grantee, privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public' AND table_name = 'attempts'
ORDER BY grantee, privilege_type;

-- 4.4 answers privileges
SELECT '4.4 answers privileges' AS section;
SELECT grantee, privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public' AND table_name = 'answers'
ORDER BY grantee, privilege_type;

-- 4.5 results privileges
SELECT '4.5 results privileges' AS section;
SELECT grantee, privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public' AND table_name = 'results'
ORDER BY grantee, privilege_type;

-- ============================================================
-- SECTION 5: LIVE FUNCTIONS — EXISTENCE CHECK
-- ============================================================

-- 5.1 Check all target functions
SELECT '5.1 Function existence check' AS section;
SELECT
  p.proname AS function_name,
  pg_get_function_arguments(p.oid) AS arguments,
  pg_get_function_result(p.oid) AS return_type,
  l.lanname AS language,
  p.prosecdef AS is_security_definer,
  p.proconfig AS config,
  pg_get_userbyid(p.proowner) AS owner
FROM pg_proc p
JOIN pg_language l ON p.prolang = l.oid
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname IN (
    'rpc_save_answers',
    'rpc_submit_attempt',
    'fn_score_attempt',
    '_fn_start_attempt_core',
    'rpc_start_attempt',
    'rpc_start_attempt_by_code',
    'fn_can_access_test',
    'get_test_questions_safe',
    'rpc_create_test',
    'rpc_create_question',
    'rpc_publish_test',
    'rpc_update_test',
    'rpc_update_question',
    'rpc_delete_question',
    'rpc_add_test_syllabus',
    'rpc_remove_test_syllabus',
    'rpc_get_user_groups',
    'rpc_create_group',
    '_fn_auth_uid',
    '_fn_can_create_test',
    '_fn_can_update_test',
    '_fn_can_manage_questions',
    '_fn_get_next_question_ordinal',
    '_fn_validate_test_timing',
    '_fn_validate_test_config',
    '_fn_is_group_member',
    '_fn_is_group_leader',
    'fn_update_updated_at'
  )
ORDER BY p.proname;

-- 5.2 ALL functions in public schema
SELECT '5.2 ALL public functions' AS section;
SELECT
  p.proname AS function_name,
  pg_get_function_arguments(p.oid) AS arguments,
  pg_get_function_result(p.oid) AS return_type,
  l.lanname AS language,
  p.prosecdef AS is_security_definer
FROM pg_proc p
JOIN pg_language l ON p.prolang = l.oid
WHERE p.pronamespace = 'public'::regnamespace
ORDER BY p.proname;

-- 5.3 Function execute privileges
SELECT '5.3 Function execute privileges' AS section;
SELECT
  grantee,
  routine_name,
  privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
ORDER BY routine_name, grantee;

-- ============================================================
-- SECTION 6: LIVE FUNCTION SOURCE CODE
-- ============================================================

-- 6.1 _fn_start_attempt_core source
SELECT '6.1 _fn_start_attempt_core source' AS section;
SELECT pg_get_functiondef(p.oid) AS full_definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = '_fn_start_attempt_core';

-- 6.2 rpc_start_attempt source
SELECT '6.2 rpc_start_attempt source' AS section;
SELECT pg_get_functiondef(p.oid) AS full_definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'rpc_start_attempt';

-- 6.3 rpc_start_attempt_by_code source
SELECT '6.3 rpc_start_attempt_by_code source' AS section;
SELECT pg_get_functiondef(p.oid) AS full_definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'rpc_start_attempt_by_code';

-- 6.4 rpc_save_answers source
SELECT '6.4 rpc_save_answers source' AS section;
SELECT pg_get_functiondef(p.oid) AS full_definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'rpc_save_answers';

-- 6.5 rpc_submit_attempt source
SELECT '6.5 rpc_submit_attempt source' AS section;
SELECT pg_get_functiondef(p.oid) AS full_definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'rpc_submit_attempt';

-- 6.6 fn_score_attempt source
SELECT '6.6 fn_score_attempt source' AS section;
SELECT pg_get_functiondef(p.oid) AS full_definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'fn_score_attempt';

-- 6.7 fn_can_access_test source
SELECT '6.7 fn_can_access_test source' AS section;
SELECT pg_get_functiondef(p.oid) AS full_definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'fn_can_access_test';

-- 6.8 get_test_questions_safe source
SELECT '6.8 get_test_questions_safe source' AS section;
SELECT pg_get_functiondef(p.oid) AS full_definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'get_test_questions_safe';

-- 6.9 rpc_create_test source
SELECT '6.9 rpc_create_test source' AS section;
SELECT pg_get_functiondef(p.oid) AS full_definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'rpc_create_test';

-- 6.10 rpc_create_question source
SELECT '6.10 rpc_create_question source' AS section;
SELECT pg_get_functiondef(p.oid) AS full_definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'rpc_create_question';

-- 6.11 rpc_publish_test source
SELECT '6.11 rpc_publish_test source' AS section;
SELECT pg_get_functiondef(p.oid) AS full_definition
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND p.proname = 'rpc_publish_test';

-- 6.12 questions_safe view definition
SELECT '6.12 questions_safe view definition' AS section;
SELECT view_definition
FROM information_schema.views
WHERE table_schema = 'public' AND table_name = 'questions_safe';

-- ============================================================
-- SECTION 7: ATTEMPT NUMBER ANALYSIS
-- ============================================================

-- 7.1 attempts unique constraint (confirm)
SELECT '7.1 attempts unique constraint' AS section;
SELECT
  tc.constraint_name,
  tc.constraint_type,
  string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position) AS columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
WHERE tc.table_name = 'attempts'
  AND tc.table_schema = 'public'
  AND tc.constraint_type IN ('UNIQUE', 'PRIMARY KEY')
GROUP BY tc.constraint_name, tc.constraint_type;

-- 7.2 Row counts
SELECT '7.2 Row counts' AS section;
SELECT 'tests' AS t, COUNT(*) AS c FROM public.tests
UNION ALL SELECT 'questions', COUNT(*) FROM public.questions
UNION ALL SELECT 'attempts', COUNT(*) FROM public.attempts
UNION ALL SELECT 'answers', COUNT(*) FROM public.answers
UNION ALL SELECT 'results', COUNT(*) FROM public.results
UNION ALL SELECT 'test_invitations', COUNT(*) FROM public.test_invitations
UNION ALL SELECT 'subjects', COUNT(*) FROM public.subjects
UNION ALL SELECT 'syllabus_nodes', COUNT(*) FROM public.syllabus_nodes
UNION ALL SELECT 'groups', COUNT(*) FROM public.groups
UNION ALL SELECT 'group_members', COUNT(*) FROM public.group_members
UNION ALL SELECT 'ai_reports', COUNT(*) FROM public.ai_reports;

-- 7.3 Attempt number distribution
SELECT '7.3 Attempt number distribution' AS section;
SELECT
  attempt_number,
  COUNT(*) AS count
FROM public.attempts
GROUP BY attempt_number
ORDER BY attempt_number;

-- 7.4 Attempts per test per user
SELECT '7.4 Attempts per test per user (top 10)' AS section;
SELECT
  test_id,
  user_id,
  COUNT(*) AS attempt_count,
  MAX(attempt_number) AS max_attempt_number
FROM public.attempts
GROUP BY test_id, user_id
HAVING COUNT(*) > 1
ORDER BY COUNT(*) DESC
LIMIT 10;

-- ============================================================
-- SECTION 8: MAX ATTEMPTS ANALYSIS
-- ============================================================

-- 8.1 tests.max_attempts values
SELECT '8.1 tests.max_attempts distribution' AS section;
SELECT
  max_attempts,
  COUNT(*) AS test_count
FROM public.tests
GROUP BY max_attempts
ORDER BY max_attempts;

-- ============================================================
-- SECTION 9: LIVE TEST STATUS VALUES
-- ============================================================

-- 9.1 Actual test statuses in use
SELECT '9.1 Test statuses in use' AS section;
SELECT status, COUNT(*) AS count
FROM public.tests
GROUP BY status
ORDER BY count DESC;

-- ============================================================
-- SECTION 10: LIVE ATTEMPT STATUS VALUES
-- ============================================================

-- 10.1 Actual attempt statuses in use
SELECT '10.1 Attempt statuses in use' AS section;
SELECT status, COUNT(*) AS count
FROM public.attempts
GROUP BY status
ORDER BY count DESC;

-- ============================================================
-- SECTION 11: VIEWS
-- ============================================================

-- 11.1 All views
SELECT '11.1 All views' AS section;
SELECT table_name, view_definition
FROM information_schema.views
WHERE table_schema = 'public'
ORDER BY table_name;

-- ============================================================
-- SECTION 12: TRIGGERS
-- ============================================================

-- 12.1 All triggers
SELECT '12.1 All triggers' AS section;
SELECT
  trigger_name,
  event_object_table,
  action_orientation,
  action_timing,
  action_statement
FROM information_schema.triggers
WHERE event_object_schema = 'public'
ORDER BY event_object_table, trigger_name;

-- ============================================================
-- SECTION 13: POST-SUBMISSION REVIEW SEARCH
-- ============================================================

-- 13.1 Search for any review/correctness functions
SELECT '13.1 Review/correctness function search' AS section;
SELECT
  p.proname AS function_name,
  pg_get_function_arguments(p.oid) AS arguments,
  pg_get_function_result(p.oid) AS return_type
FROM pg_proc p
WHERE p.pronamespace = 'public'::regnamespace
  AND (
    p.proname LIKE '%review%'
    OR p.proname LIKE '%correct%'
    OR p.proname LIKE '%reveal%'
    OR p.proname LIKE '%answer%'
    OR p.proname LIKE '%scor%'
    OR p.proname LIKE '%result%'
  )
ORDER BY p.proname;

-- 13.2 Search for any views with correctness data
SELECT '13.2 Views with correctness data' AS section;
SELECT table_name, view_definition
FROM information_schema.views
WHERE table_schema = 'public'
  AND (
    view_definition LIKE '%correct%'
    OR view_definition LIKE '%is_correct%'
    OR view_definition LIKE '%review%'
  )
ORDER BY table_name;

-- ============================================================
-- SECTION 14: FOREIGN KEYS
-- ============================================================

-- 14.1 All foreign keys
SELECT '14.1 All foreign keys' AS section;
SELECT
  tc.table_name,
  tc.constraint_name,
  kcu.column_name,
  ccu.table_name AS references_table,
  ccu.column_name AS references_column
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage ccu
  ON tc.constraint_name = ccu.constraint_name
  AND tc.table_schema = ccu.table_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND tc.table_schema = 'public'
  AND tc.table_name IN (
    'tests', 'questions', 'attempts', 'answers', 'results',
    'test_syllabus', 'test_invitations', 'ai_reports',
    'groups', 'group_members'
  )
ORDER BY tc.table_name, tc.constraint_name;

-- ============================================================
-- SECTION 15: SUPABASE FUNCTIONS (pg_stat_user_functions)
-- ============================================================

-- 15.1 Function call stats
SELECT '15.1 Function call stats' AS section;
SELECT
  funcname,
  calls,
  total_time,
  self_time
FROM pg_stat_user_functions
WHERE schemaname = 'public'
ORDER BY calls DESC;

-- ============================================================
-- END OF DISCOVERY
-- ============================================================
SELECT '=== DISCOVERY COMPLETE ===' AS status;
