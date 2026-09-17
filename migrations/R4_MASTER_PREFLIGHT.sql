-- ============================================================
-- R4 MASTER PREFLIGHT — READ-ONLY LIVE AUDIT (run in Supabase SQL Editor)
-- ============================================================
-- Produces every fact needed to decide APPLIED / PARTIAL / NOT APPLIED for
-- the six remaining R4 migrations and to confirm the four earlier hotfixes.
-- Nothing here writes. Paste the full output back for the apply decision.
--
-- Expected values are in the comments; anything else = STOP for that item.

-- ------------------------------------------------------------
-- 1. FUNCTION INVENTORY (signature-distinguished; overloads show as rows)
-- ------------------------------------------------------------
SELECT p.proname,
       pg_get_function_arguments(p.oid) AS args,
       pg_get_function_result(p.oid)    AS returns,
       p.prosecdef                       AS security_definer,
       p.proconfig                       AS config,
       p.provolatile                     AS volatility
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN (
    '_fn_start_attempt_core', 'rpc_start_attempt', 'rpc_start_attempt_by_code',
    'rpc_submit_attempt', 'fn_auto_submit', 'fn_score_attempt', 'rpc_generate_results',
    'rpc_create_question', 'rpc_update_question', 'rpc_get_user_groups', 'rpc_delete_test',
    'rpc_save_answers', 'rpc_publish_test', 'rpc_update_test', 'rpc_create_test',
    'get_test_questions_safe', 'fn_is_member', 'fn_has_permission', 'fn_can_access_test')
ORDER BY p.proname, args;
-- Decision keys:
--   _fn_start_attempt_core args = 'p_test uuid, p_code_verified boolean DEFAULT false'
--       → Migration A NOT APPLIED (v2 adds p_reattempt). If a 3-arg row exists → check §2.
--   rpc_start_attempt args = 'p_test uuid' / by_code = 'p_code text' → A NOT APPLIED.
--   fn_auto_submit missing → E NOT APPLIED.   rpc_delete_test missing → C NOT APPLIED.
--   rpc_get_user_groups missing → D NOT APPLIED.
--   Any function with TWO rows (overload) → STOP, report.

-- ------------------------------------------------------------
-- 2. BODY MARKERS (hotfixes + each migration's distinctive text)
-- ------------------------------------------------------------
SELECT p.proname,
  pg_get_functiondef(p.oid) LIKE '%AS answer_item%'                                    AS save_answers_alias_fix,
  pg_get_functiondef(p.oid) LIKE '%''auto_submitted''::public.attempt_status%'          AS submit_enum_cast_fix,
  pg_get_functiondef(p.oid) LIKE '%p_status::public.question_status%'                  AS update_q_status_cast_fix,
  pg_get_functiondef(p.oid) LIKE '%''published''::public.test_status%'                  AS publish_cast_fix,
  pg_get_functiondef(p.oid) LIKE '%REATTEMPT_LIMIT_REACHED%'                           AS a_reattempt_policy,
  pg_get_functiondef(p.oid) LIKE '%LATE_JOIN_WINDOW_CLOSED%'                           AS a_late_join_window,
  pg_get_functiondef(p.oid) LIKE '%ATTEMPT_ALLOCATION_CONFLICT%'                       AS a_alloc_conflict,
  pg_get_functiondef(p.oid) LIKE '%now() >= v_test.ends_at%'                           AS ends_at_hard_block,
  pg_get_functiondef(p.oid) LIKE '%LATE_JOIN_NOT_ALLOWED%'                             AS late_join_bool_rule,
  pg_get_functiondef(p.oid) LIKE '%at least 4 options are required%'                   AS b_four_option_guard,
  pg_get_functiondef(p.oid) LIKE '%every option needs text%'                           AS b_non_empty_guard,
  pg_get_functiondef(p.oid) LIKE '%at least 2 options are required%'                   AS b_old_two_option_guard,
  pg_get_functiondef(p.oid) LIKE '%status IN (%''pending''::public.batch_status%'      AS f_old_pending_only_lookup,
  pg_get_functiondef(p.oid) LIKE '%''reused'', true%'                                   AS f_reuse_branch_present,
  pg_get_functiondef(p.oid) LIKE '%fn_auto_submit%'                                    AS references_fn_auto_submit
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('rpc_save_answers','rpc_submit_attempt','rpc_update_question','rpc_publish_test',
                    '_fn_start_attempt_core','rpc_create_question','rpc_generate_results','fn_auto_submit')
ORDER BY p.proname;
-- Expected TODAY (per completion report):
--   rpc_save_answers: save_answers_alias_fix t, references_fn_auto_submit t
--   rpc_submit_attempt: submit_enum_cast_fix t
--   rpc_update_question: update_q_status_cast_fix t, b_old_two_option_guard t (B not applied)
--   rpc_publish_test: publish_cast_fix t
--   _fn_start_attempt_core: ends_at_hard_block t, late_join_bool_rule t, a_* f (A not applied)
--   rpc_create_question: b_old_two_option_guard t
--   rpc_generate_results: f_old_pending_only_lookup t → F NOT APPLIED; if f → check reuse text
-- Any "fix" column = f  → REGRESSION / missing hotfix: report before anything else.

-- ------------------------------------------------------------
-- 3. EXECUTE GRANTS (client roles only)
-- ------------------------------------------------------------
SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND grantee IN ('anon','authenticated','PUBLIC')
  AND routine_name IN (
    '_fn_start_attempt_core','rpc_start_attempt','rpc_start_attempt_by_code','rpc_submit_attempt',
    'fn_auto_submit','fn_score_attempt','rpc_generate_results','rpc_create_question','rpc_update_question',
    'rpc_get_user_groups','rpc_delete_test','rpc_save_answers','rpc_publish_test','get_test_questions_safe')
ORDER BY 1, 2;
-- Expected: rpc_* and get_test_questions_safe → authenticated only; _fn_* / fn_* → no client role.
-- anon or PUBLIC on any rpc_* → report (do not fix blindly).

-- ------------------------------------------------------------
-- 4. TABLE COLUMNS the migrations rely on
-- ------------------------------------------------------------
SELECT table_name, column_name, data_type, udt_name, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND (
    (table_name = 'tests'          AND column_name IN ('settings','allow_late_join','starts_at','ends_at','duration_sec',
                                                        'test_mode','group_id','max_participants','status','created_by',
                                                        'is_soft_deleted','deleted_at','deleted_by','deletion_reason'))
 OR (table_name = 'attempts'       AND column_name IN ('attempt_number','status','deadline_at','submitted_at','user_id','test_id'))
 OR (table_name = 'questions'      AND column_name IN ('options','correct_option','status','question_type','ordinal','test_id'))
 OR (table_name = 'answers'        AND column_name IN ('selected_option','marked_for_review'))
 OR (table_name = 'results'        AND column_name IN ('attempt_id','score','max_score'))
 OR (table_name = 'result_batches' AND column_name IN ('id','test_id','status','reports_done','reports_total','totals','completed_at'))
 OR (table_name = 'groups'         AND column_name IN ('id','name','created_by','created_at','updated_at'))
 OR (table_name = 'group_members'  AND column_name IN ('group_id','user_id','role'))
 OR (table_name = 'role_permissions'))
ORDER BY table_name, column_name;
-- Expected: tests.settings jsonb; attempts.attempt_number integer; questions.options jsonb;
--           result_batches.status batch_status; groups.updated_at present (else edit R4_GROUPS_RPC as noted).

-- ------------------------------------------------------------
-- 5. CONSTRAINTS / INDEXES
-- ------------------------------------------------------------
SELECT conrelid::regclass AS table_name, conname, contype, pg_get_constraintdef(oid) AS definition
FROM pg_constraint
WHERE conrelid IN ('public.attempts'::regclass, 'public.result_batches'::regclass,
                   'public.questions'::regclass, 'public.tests'::regclass, 'public.answers'::regclass)
ORDER BY 1, 2;
-- Expected: attempts UNIQUE (test_id, user_id, attempt_number); result_batches UNIQUE (test_id);
--           questions UNIQUE (test_id, ordinal) (or equivalent); answers PK/UNIQUE (attempt_id, question_id).

SELECT schemaname, tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public' AND tablename IN ('attempts','result_batches','questions','answers')
ORDER BY tablename, indexname;

-- ------------------------------------------------------------
-- 6. RLS (enabled flag + every policy with its expressions)
-- ------------------------------------------------------------
SELECT c.relname AS table_name, c.relrowsecurity AS rls_enabled, c.relforcerowsecurity AS rls_forced
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public'
  AND c.relname IN ('tests','questions','attempts','answers','results','result_batches','groups','group_members')
ORDER BY 1;

SELECT tablename, policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename IN ('tests','questions','attempts','answers','results','result_batches','groups','group_members')
ORDER BY tablename, policyname;
-- Expected: questions has NO SELECT policy for authenticated (safe path only);
--           attempts has an own-rows SELECT (user_id = auth.uid()); answers own-rows via attempts;
--           no policy references its own table without a definer function (recursion risk).

SELECT grantee, table_name, privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('anon','authenticated')
  AND table_name IN ('questions','attempts','answers','results','result_batches','tests','groups','group_members')
ORDER BY table_name, grantee, privilege_type;
-- Expected: questions → no SELECT for anon/authenticated (or blocked by RLS with no policy).

-- ------------------------------------------------------------
-- 7. DATA FACTS (read-only)
-- ------------------------------------------------------------
-- Legacy questions with fewer than 4 options (never modified by any migration)
SELECT count(*) AS questions_with_fewer_than_4_options
FROM public.questions
WHERE options IS NULL OR jsonb_typeof(options) <> 'array' OR jsonb_array_length(options) < 4;

SELECT q.id, q.test_id, q.status, q.question_type, jsonb_array_length(q.options) AS option_count, t.status AS test_status
FROM public.questions q JOIN public.tests t ON t.id = q.test_id
WHERE q.options IS NULL OR jsonb_typeof(q.options) <> 'array' OR jsonb_array_length(q.options) < 4
ORDER BY t.status, q.test_id, q.ordinal
LIMIT 100;

-- Tests per test_mode with a group attached (Challenge may be group-backed; Group requires it)
SELECT test_mode, (group_id IS NOT NULL) AS has_group, count(*)
FROM public.tests WHERE is_soft_deleted = false
GROUP BY 1, 2 ORDER BY 1, 2;

-- Batches per test (must be ≤ 1 each — proves UNIQUE(test_id) holds)
SELECT test_id, count(*) FROM public.result_batches GROUP BY test_id HAVING count(*) > 1;
-- Expected: 0 rows.

-- Attempt numbering sanity
SELECT test_id, user_id, count(*) AS attempts, max(attempt_number) AS max_no,
       bool_and(attempt_number >= 1) AS all_positive
FROM public.attempts GROUP BY 1, 2 HAVING count(*) <> max(attempt_number) LIMIT 20;
-- Expected: 0 rows (count == max attempt_number per user/test).

-- ------------------------------------------------------------
-- 8. QUESTION SECURITY (safe path never returns the key)
-- ------------------------------------------------------------
SELECT pg_get_function_result(p.oid) AS safe_questions_returns
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'get_test_questions_safe';
-- Expected: 15 columns, NO correct_option.
