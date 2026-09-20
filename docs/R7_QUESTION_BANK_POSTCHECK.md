# R7 — Question Bank V1: POSTCHECK

Run after both migrations. Read-only except §4 (rolled back).

## 1. Functions

```sql
SELECT p.proname, p.prosecdef AS definer, p.proconfig,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN ('_fn_can_read_bank','_fn_can_see_bank_answer','rpc_list_question_bank',
  'rpc_get_question_bank_question','rpc_clone_bank_questions','fn_bank_available')
ORDER BY 1;
-- expect 6 rows: definer=true, proconfig={search_path=}, anon_exec=false for all;
--        auth_exec=false for _fn_can_read_bank and _fn_can_see_bank_answer, true for the four RPCs
SELECT (prosrc ILIKE '%p_status::public.question_status%') AS cast_present FROM pg_proc WHERE proname = 'rpc_create_question';
-- expect true
```

## 2. Nothing else changed

```sql
SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='question_bank';  -- 3 (unchanged)
SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='questions';      -- 4 (unchanged)
SELECT grantee, privilege_type FROM information_schema.role_table_grants
WHERE table_schema='public' AND table_name='questions' AND grantee='authenticated';       -- DELETE, INSERT, UPDATE (no SELECT — unchanged)
```

## 3. Answer key never leaks through the new browse/detail path

```sql
SELECT column_name FROM information_schema.columns
WHERE table_schema='public' AND table_name='rpc_list_question_bank';  -- (n/a: function) — instead:
SELECT pg_get_function_result(oid) FROM pg_proc WHERE proname='rpc_list_question_bank';
-- expect: no correct_option column in the TABLE(...) result
```

## 4. Functional proof (rolled back) — as a test creator who can read the bank

```sql
BEGIN;
SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub', '<creator uid>', true);
SELECT id, question, total_count FROM public.rpc_list_question_bank(NULL, 'approved');        -- key-free rows
SELECT public.rpc_get_question_bank_question('<bank id>');                                  -- answer_included=false, no correct_option
SELECT public.rpc_get_question_bank_question('<bank id>', true);                            -- correct_option only if creator/REVIEW_QUESTIONS, else ERROR ANSWER_KEY_FORBIDDEN
SELECT public.rpc_clone_bank_questions('<own draft test>', ARRAY['<bank id>']::uuid[], 1);  -- {"cloned":1,...}
SELECT public.rpc_clone_bank_questions('<own draft test>', ARRAY['<bank id>']::uuid[], 1);  -- {"cloned":0,"skipped_duplicate":[...]}
RESET ROLE;
UPDATE public.question_bank SET question='EDITED', correct_option=0 WHERE id='<bank id>';
SELECT question, correct_option FROM public.questions WHERE bank_id='<bank id>';           -- original text and answer (independent)
ROLLBACK;
```

## 5. Regression

- `flutter test` (question-related suites) unchanged — no Flutter file is part of this migration.
- Legacy web app: bank pages keep using direct table reads (unchanged policies/grants).
