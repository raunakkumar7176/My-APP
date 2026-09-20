# R7 — Question Bank V1: PRECHECK (read-only)

Run in the Supabase SQL Editor **before** `migrations/R7_QUESTION_BANK_V1.sql` and
`migrations/R7_FIX_rpc_create_question_status_cast.sql`. Expected values are the live
state observed on 2026-09-20.

## 1. The bank table exists (architecture B) and `questions.test_id` is NOT NULL

```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public' AND table_name IN ('question_bank', 'questions', 'questions_safe');
-- expect 3 rows

SELECT column_name, is_nullable FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'questions' AND column_name IN ('test_id', 'bank_id', 'status', 'correct_option');
-- expect test_id NO, bank_id YES, status NO, correct_option NO

SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'question_bank' ORDER BY ordinal_position;
-- expect: id, question, options, correct_option, explanation, subject_id, subject_name, chapter,
--         topic_node_id, difficulty, language, question_type, source, created_by, times_used,
--         created_at, status, reviewed_by, reviewed_at, updated_at, archived_at, duplicate_key
```

## 2. Bank RLS / grants (the migration does not change them)

```sql
SELECT policyname, cmd FROM pg_policies WHERE schemaname='public' AND tablename='question_bank' ORDER BY 1;
-- expect: auth insert bank (INSERT), auth read bank (SELECT), owner update bank (UPDATE)
SELECT grantee, string_agg(privilege_type, ',') FROM information_schema.role_table_grants
WHERE table_schema='public' AND table_name='question_bank' AND grantee IN ('anon','authenticated') GROUP BY 1;
-- expect: authenticated INSERT,SELECT,UPDATE (no anon)
```

## 3. None of the R7 functions exist yet

```sql
SELECT proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND proname IN ('_fn_can_read_bank','_fn_can_see_bank_answer','rpc_list_question_bank',
  'rpc_get_question_bank_question','rpc_clone_bank_questions','fn_bank_available');
-- expect 0 rows
```

## 4. The helpers the migration relies on exist

```sql
SELECT proname, prosecdef, proconfig FROM pg_proc
WHERE proname IN ('fn_has_permission', '_fn_get_next_question_ordinal', '_fn_can_manage_questions');
-- expect 3 rows, all SECURITY DEFINER, search_path=""
SELECT enumlabel FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid WHERE t.typname = 'question_status' ORDER BY enumsortorder;
-- expect pending_review, approved, rejected, needs_revision, archived
```

## 5. The `rpc_create_question` defect (captures the rollback body)

```sql
SELECT (prosrc ILIKE '%p_status::public.question_status%') AS cast_present FROM pg_proc WHERE proname = 'rpc_create_question';
-- expect false (the bug)
SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'rpc_create_question';
-- save the output: it is the exact rollback for R7_FIX_rpc_create_question_status_cast.sql
```

Optional live proof of the defect (rolled back):

```sql
BEGIN;
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '<creator of a draft test>', true);
SELECT public.rpc_create_question('<draft test id>', 'q', '["a","b","c","d"]'::jsonb, 1);
-- expect ERROR: column "status" is of type public.question_status but expression is of type text
ROLLBACK;
```
