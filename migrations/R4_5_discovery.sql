-- ============================================================
-- R4.5 PRE-IMPLEMENTATION DISCOVERY
-- Run BEFORE writing R4_5_test_creation.sql
-- Date: 2026-09-13
--
-- Purpose: Verify actual live schema before R4.5 implementation.
-- Execute ALL queries and report results.
-- DO NOT modify anything.
-- ============================================================

-- ============================================================
-- D1: tests table columns (ACTUAL live columns)
-- ============================================================
SELECT 'D1: tests Columns' AS check_name;
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
-- D2: tests CHECK constraints
-- ============================================================
SELECT 'D2: tests CHECK Constraints' AS check_name;
SELECT
  tc.constraint_name,
  cc.check_clause
FROM information_schema.table_constraints tc
JOIN information_schema.check_constraints cc
  ON tc.constraint_name = cc.constraint_name
  AND tc.table_schema = cc.constraint_schema
WHERE tc.table_name = 'tests'
  AND tc.table_schema = 'public'
  AND tc.constraint_type = 'CHECK';

-- ============================================================
-- D3: tests FOREIGN KEY constraints
-- ============================================================
SELECT 'D3: tests Foreign Keys' AS check_name;
SELECT
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
WHERE tc.table_name = 'tests'
  AND tc.table_schema = 'public'
  AND tc.constraint_type = 'FOREIGN KEY';

-- ============================================================
-- D4: tests UNIQUE constraints
-- ============================================================
SELECT 'D4: tests Unique Constraints' AS check_name;
SELECT
  tc.constraint_name,
  string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position) AS columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
WHERE tc.table_name = 'tests'
  AND tc.table_schema = 'public'
  AND tc.constraint_type = 'UNIQUE'
GROUP BY tc.constraint_name;

-- ============================================================
-- D5: tests RLS policies
-- ============================================================
SELECT 'D5: tests RLS Policies' AS check_name;
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

-- ============================================================
-- D6: tests table grants
-- ============================================================
SELECT 'D6: tests Table Grants' AS check_name;
SELECT
  grantee,
  privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'tests'
ORDER BY grantee, privilege_type;

-- ============================================================
-- D7: tests indexes
-- ============================================================
SELECT 'D7: tests Indexes' AS check_name;
SELECT indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'tests'
ORDER BY indexname;

-- ============================================================
-- D8: questions table columns (ACTUAL live columns)
-- ============================================================
SELECT 'D8: questions Columns' AS check_name;
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'questions'
ORDER BY ordinal_position;

-- ============================================================
-- D9: questions CHECK constraints
-- ============================================================
SELECT 'D9: questions CHECK Constraints' AS check_name;
SELECT
  tc.constraint_name,
  cc.check_clause
FROM information_schema.table_constraints tc
JOIN information_schema.check_constraints cc
  ON tc.constraint_name = cc.constraint_name
  AND tc.table_schema = cc.constraint_schema
WHERE tc.table_name = 'questions'
  AND tc.table_schema = 'public'
  AND tc.constraint_type = 'CHECK';

-- ============================================================
-- D10: questions FOREIGN KEY constraints
-- ============================================================
SELECT 'D10: questions Foreign Keys' AS check_name;
SELECT
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
WHERE tc.table_name = 'questions'
  AND tc.table_schema = 'public'
  AND tc.constraint_type = 'FOREIGN KEY';

-- ============================================================
-- D11: questions RLS policies
-- ============================================================
SELECT 'D11: questions RLS Policies' AS check_name;
SELECT
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'questions'
ORDER BY policyname;

-- ============================================================
-- D12: questions table grants
-- ============================================================
SELECT 'D12: questions Table Grants' AS check_name;
SELECT
  grantee,
  privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'questions'
ORDER BY grantee, privilege_type;

-- ============================================================
-- D13: test_syllabus table columns
-- ============================================================
SELECT 'D13: test_syllabus Columns' AS check_name;
SELECT
  column_name,
  data_type,
  is_nullable,
  column_default
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'test_syllabus'
ORDER BY ordinal_position;

-- ============================================================
-- D14: test_syllabus constraints
-- ============================================================
SELECT 'D14: test_syllabus Constraints' AS check_name;
SELECT
  tc.constraint_name,
  tc.constraint_type,
  string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position) AS columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
WHERE tc.table_name = 'test_syllabus'
  AND tc.table_schema = 'public'
GROUP BY tc.constraint_name, tc.constraint_type;

-- ============================================================
-- D15: test_syllabus RLS policies
-- ============================================================
SELECT 'D15: test_syllabus RLS Policies' AS check_name;
SELECT
  policyname,
  permissive,
  roles,
  cmd,
  qual,
  with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'test_syllabus'
ORDER BY policyname;

-- ============================================================
-- D16: test_syllabus table grants
-- ============================================================
SELECT 'D16: test_syllabus Table Grants' AS check_name;
SELECT
  grantee,
  privilege_type
FROM information_schema.table_privileges
WHERE table_schema = 'public'
  AND table_name = 'test_syllabus'
ORDER BY grantee, privilege_type;

-- ============================================================
-- D17: test_status enum values
-- ============================================================
SELECT 'D17: test_status Enum Values' AS check_name;
SELECT
  e.enumlabel AS enum_value,
  e.enumsortorder AS sort_order
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
WHERE t.typname = 'test_status'
ORDER BY e.enumsortorder;

-- ============================================================
-- D18: question_type enum values
-- ============================================================
SELECT 'D18: question_type Enum Values' AS check_name;
SELECT
  e.enumlabel AS enum_value,
  e.enumsortorder AS sort_order
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
WHERE t.typname = 'question_type'
ORDER BY e.enumsortorder;

-- ============================================================
-- D19: difficulty_level enum values
-- ============================================================
SELECT 'D19: difficulty_level Enum Values' AS check_name;
SELECT
  e.enumlabel AS enum_value,
  e.enumsortorder AS sort_order
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
WHERE t.typname = 'difficulty_level'
ORDER BY e.enumsortorder;

-- ============================================================
-- D20: attempt_status enum values
-- ============================================================
SELECT 'D20: attempt_status Enum Values' AS check_name;
SELECT
  e.enumlabel AS enum_value,
  e.enumsortorder AS sort_order
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
WHERE t.typname = 'attempt_status'
ORDER BY e.enumsortorder;

-- ============================================================
-- D21: All existing functions/RPCs
-- ============================================================
SELECT 'D21: All Functions' AS check_name;
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
ORDER BY p.proname;

-- ============================================================
-- D22: Function execute grants
-- ============================================================
SELECT 'D22: Function Execute Grants' AS check_name;
SELECT
  grantee,
  routine_name,
  privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
ORDER BY routine_name, grantee;

-- ============================================================
-- D23: questions_safe view definition
-- ============================================================
SELECT 'D23: questions_safe View Definition' AS check_name;
SELECT
  view_definition
FROM information_schema.views
WHERE table_schema = 'public'
  AND table_name = 'questions_safe';

-- ============================================================
-- D24: All triggers on test-related tables
-- ============================================================
SELECT 'D24: Triggers' AS check_name;
SELECT
  trigger_name,
  event_object_table,
  action_orientation,
  action_timing,
  action_statement
FROM information_schema.triggers
WHERE event_object_table IN ('tests', 'questions', 'test_syllabus')
ORDER BY event_object_table, trigger_name;

-- ============================================================
-- D25: All indexes on test-related tables
-- ============================================================
SELECT 'D25: All Test-Related Indexes' AS check_name;
SELECT
  indexname,
  tablename,
  indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('tests', 'questions', 'test_syllabus')
ORDER BY tablename, indexname;

-- ============================================================
-- D26: subjects table (verify subject_id FK target)
-- ============================================================
SELECT 'D26: subjects Columns' AS check_name;
SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'subjects'
ORDER BY ordinal_position;

-- ============================================================
-- D27: syllabus_nodes table (verify FK target)
-- ============================================================
SELECT 'D27: syllabus_nodes Columns' AS check_name;
SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'syllabus_nodes'
ORDER BY ordinal_position;

-- ============================================================
-- D28: Row counts (data integrity baseline)
-- ============================================================
SELECT 'D28: Row Counts' AS check_name;
SELECT 'tests' AS table_name, COUNT(*) AS row_count FROM public.tests
UNION ALL
SELECT 'questions', COUNT(*) FROM public.questions
UNION ALL
SELECT 'test_syllabus', COUNT(*) FROM public.test_syllabus
UNION ALL
SELECT 'subjects', COUNT(*) FROM public.subjects
UNION ALL
SELECT 'syllabus_nodes', COUNT(*) FROM public.syllabus_nodes;

-- ============================================================
-- END OF DISCOVERY
-- ============================================================
