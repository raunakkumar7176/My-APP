-- ============================================================
-- R4.1 VALIDATION SCRIPT
-- Run AFTER executing R4_1_phase_db_foundation.sql
-- Date: 2026-09-12
--
-- Expected: All queries return results.
-- If any query returns empty or errors, STOP and investigate.
-- ============================================================

-- ============================================================
-- V1: ALL TABLES EXIST
-- Expected: 8 rows
-- ============================================================
SELECT 'V1: Tables' AS check_name;
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('tests', 'questions', 'test_syllabus', 'test_invitations', 'attempts', 'answers', 'results', 'ai_reports')
ORDER BY table_name;

-- ============================================================
-- V2: ALL ENUM TYPES EXIST
-- Expected: 4 rows
-- ============================================================
SELECT 'V2: Enum Types' AS check_name;
SELECT typname
FROM pg_type
WHERE typname IN ('test_status', 'attempt_status', 'question_type', 'difficulty_level')
ORDER BY typname;

-- ============================================================
-- V3: TESTS TABLE COLUMNS
-- Expected: 24 columns
-- ============================================================
SELECT 'V3: Tests Columns' AS check_name;
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'tests' AND table_schema = 'public'
ORDER BY ordinal_position;

-- ============================================================
-- V4: QUESTIONS TABLE COLUMNS
-- Expected: 18 columns
-- ============================================================
SELECT 'V4: Questions Columns' AS check_name;
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'questions' AND table_schema = 'public'
ORDER BY ordinal_position;

-- ============================================================
-- V5: ATTEMPTS TABLE COLUMNS
-- Expected: 12 columns
-- ============================================================
SELECT 'V5: Attempts Columns' AS check_name;
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'attempts' AND table_schema = 'public'
ORDER BY ordinal_position;

-- ============================================================
-- V6: ANSWERS TABLE COLUMNS
-- Expected: 9 columns
-- ============================================================
SELECT 'V6: Answers Columns' AS check_name;
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'answers' AND table_schema = 'public'
ORDER BY ordinal_position;

-- ============================================================
-- V7: RESULTS TABLE COLUMNS
-- Expected: 15 columns
-- ============================================================
SELECT 'V7: Results Columns' AS check_name;
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_name = 'results' AND table_schema = 'public'
ORDER BY ordinal_position;

-- ============================================================
-- V8: ALL FOREIGN KEYS
-- Expected: 15+ FK constraints across all tables
-- ============================================================
SELECT 'V8: Foreign Keys' AS check_name;
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
  AND tc.table_name IN ('tests', 'questions', 'test_syllabus', 'test_invitations', 'attempts', 'answers', 'results', 'ai_reports')
ORDER BY tc.table_name, tc.constraint_name;

-- ============================================================
-- V9: ALL UNIQUE CONSTRAINTS
-- Expected: 5 unique constraints
-- ============================================================
SELECT 'V9: Unique Constraints' AS check_name;
SELECT
  tc.table_name,
  tc.constraint_name,
  string_agg(kcu.column_name, ', ' ORDER BY kcu.ordinal_position) AS columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
WHERE tc.constraint_type = 'UNIQUE'
  AND tc.table_schema = 'public'
  AND tc.table_name IN ('tests', 'questions', 'test_syllabus', 'test_invitations', 'attempts', 'answers', 'results', 'ai_reports')
GROUP BY tc.table_name, tc.constraint_name
ORDER BY tc.table_name;

-- ============================================================
-- V10: ALL INDEXES
-- Expected: 25+ indexes
-- ============================================================
SELECT 'V10: Indexes' AS check_name;
SELECT
  indexname,
  tablename
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN ('tests', 'questions', 'test_syllabus', 'test_invitations', 'attempts', 'answers', 'results', 'ai_reports')
ORDER BY tablename, indexname;

-- ============================================================
-- V11: QUESTIONS_SAFE VIEW
-- Expected: 15 columns (no is_correct)
-- ============================================================
SELECT 'V11: Questions Safe View' AS check_name;
SELECT column_name
FROM information_schema.columns
WHERE table_name = 'questions_safe' AND table_schema = 'public'
ORDER BY ordinal_position;

-- ============================================================
-- V12: RLS NOT ENABLED (no policies on new tables)
-- Expected: 0 rows
-- ============================================================
SELECT 'V12: RLS Policies (should be empty)' AS check_name;
SELECT
  schemaname,
  tablename,
  policyname
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('tests', 'questions', 'test_syllabus', 'test_invitations', 'attempts', 'answers', 'results', 'ai_reports');

-- ============================================================
-- V13: TRIGGERS EXIST
-- Expected: 3 triggers
-- ============================================================
SELECT 'V13: Triggers' AS check_name;
SELECT
  trigger_name,
  event_object_table
FROM information_schema.triggers
WHERE trigger_name LIKE 'trg_%'
ORDER BY event_object_table;

-- ============================================================
-- V14: CHECK CONSTRAINTS
-- Expected: 8+ CHECK constraints
-- ============================================================
SELECT 'V14: CHECK Constraints' AS check_name;
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
ORDER BY tc.table_name;

-- ============================================================
-- V15: EXISTING TABLES UNCHANGED
-- Verify subjects, syllabus_nodes, profiles not modified
-- ============================================================
SELECT 'V15: Existing Tables Unchanged' AS check_name;
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN ('subjects', 'syllabus_nodes', 'profiles', 'study_materials', 'node_materials', 'material_chunks', 'progress_snapshots', 'routines', 'routine_logs')
ORDER BY table_name;

-- ============================================================
-- V16: EXISTING DATA INTACT
-- Verify subjects still has 11 rows
-- ============================================================
SELECT 'V16: Subjects Row Count' AS check_name;
SELECT COUNT(*) AS subject_count FROM public.subjects;

-- ============================================================
-- V17: TEST_SYLLABUS RECREATED WITH PK
-- Expected: PK exists on test_syllabus
-- ============================================================
SELECT 'V17: test_syllabus PK' AS check_name;
SELECT
  tc.constraint_name,
  tc.constraint_type,
  string_agg(kcu.column_name, ', ') AS columns
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
  ON tc.constraint_name = kcu.constraint_name
  AND tc.table_schema = kcu.table_schema
WHERE tc.table_name = 'test_syllabus'
  AND tc.table_schema = 'public'
GROUP BY tc.constraint_name, tc.constraint_type;

-- ============================================================
-- VALIDATION SUMMARY
-- ============================================================
SELECT '=== VALIDATION COMPLETE ===' AS status;
SELECT
  (SELECT COUNT(*) FROM information_schema.tables
   WHERE table_schema = 'public'
   AND table_name IN ('tests', 'questions', 'test_syllabus', 'test_invitations', 'attempts', 'answers', 'results', 'ai_reports')
  ) AS tables_found,
  (SELECT COUNT(*) FROM pg_type
   WHERE typname IN ('test_status', 'attempt_status', 'question_type', 'difficulty_level')
  ) AS enums_found,
  (SELECT COUNT(*) FROM pg_policies
   WHERE schemaname = 'public'
   AND tablename IN ('tests', 'questions', 'test_syllabus', 'test_invitations', 'attempts', 'answers', 'results', 'ai_reports')
  ) AS rls_policies_found,
  (SELECT COUNT(*) FROM information_schema.columns
   WHERE table_name = 'questions_safe' AND table_schema = 'public'
  ) AS questions_safe_columns;
