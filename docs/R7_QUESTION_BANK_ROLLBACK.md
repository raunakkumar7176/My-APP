# R7 — Question Bank V1: ROLLBACK

Both migrations are additive; rollback removes only what they created. Nothing they
touch is a table, column, policy or grant on an existing object (the fix migration
only re-creates one existing function body).

## R7_QUESTION_BANK_V1.sql

```sql
DROP FUNCTION IF EXISTS public.rpc_clone_bank_questions(uuid, uuid[], numeric);
DROP FUNCTION IF EXISTS public.rpc_get_question_bank_question(uuid, boolean);
DROP FUNCTION IF EXISTS public.rpc_list_question_bank(text, text, uuid, uuid, text, text, text, text, integer, integer);
DROP FUNCTION IF EXISTS public.fn_bank_available(text, text, text, text);
DROP FUNCTION IF EXISTS public._fn_can_see_bank_answer(uuid, uuid);
DROP FUNCTION IF EXISTS public._fn_can_read_bank(uuid);
NOTIFY pgrst, 'reload schema';
```

Data created through `rpc_clone_bank_questions` (test-linked `questions` rows) is ordinary
question data and is intentionally **not** removed by rollback; `question_bank.times_used`
increments are likewise left as history.

## R7_FIX_rpc_create_question_status_cast.sql

Re-create the previous body captured by `docs/R7_QUESTION_BANK_PRECHECK.md §5` (it
re-introduces the failing text→enum insert, so only do this for strict reversal).

## Verification after rollback

```sql
SELECT count(*) FROM pg_proc WHERE proname IN ('_fn_can_read_bank','_fn_can_see_bank_answer','rpc_list_question_bank',
  'rpc_get_question_bank_question','rpc_clone_bank_questions','fn_bank_available');  -- expect 0
```

Rollback was proven in-transaction on 2026-09-20 (`r7_proof.js`: the whole migration is applied and
rolled back in one transaction; residue check shows `r7_functions_live=0`).
