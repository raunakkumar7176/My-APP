-- R7 — Question Bank V1 backend (owner apply required; NOT applied automatically)
--
-- LIVE FACTS (read-only, 2026-09-20):
--   * public.question_bank EXISTS (legacy 0045-era table): question, options jsonb,
--     correct_option int (0..3), explanation, subject_id, subject_name, chapter,
--     topic_node_id, difficulty, language, question_type ('mcq' only), source
--     (manual|upload|ai|mixed), created_by, times_used, status question_status,
--     reviewed_by/at, updated_at, archived_at, duplicate_key. RLS on; policies
--     "auth read bank" / "auth insert bank" / "owner update bank"; grants
--     authenticated INSERT,SELECT,UPDATE. 1 row live.
--   * public.questions.test_id is NOT NULL — a "test_id IS NULL = reusable" design
--     is impossible; questions rows are always test-linked. questions.bank_id
--     REFERENCES question_bank(id) ON DELETE SET NULL (metadata only).
--   * No bank-selection function exists; rpc_create_question copies content passed
--     by the client, so the legacy "select from bank" flow is a client-side copy
--     that requires reading correct_option from the bank.
--
-- THIS MIGRATION (additive; no table/column/policy/grant on existing objects changes):
--   _fn_can_read_bank(uid)            mirror of policy "auth read bank" for DEFINER use
--   _fn_can_see_bank_answer(uid, row) creator or REVIEW_QUESTIONS holder
--   rpc_list_question_bank(...)       key-free, server-filtered, bounded pages
--   rpc_get_question_bank_question    key-free by default; key only when authorized
--   rpc_clone_bank_questions          SERVER-SIDE SNAPSHOT bank -> independent questions row
--   fn_bank_available(...)            legacy-compatible count (client already calls it)
-- Rollback: docs/R7_QUESTION_BANK_ROLLBACK.md (DROP the six functions).

-- ─────────────────────────────────────────────────────────────────────────────
-- helpers (not client-callable)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._fn_can_read_bank(p_user uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
  -- Same predicate as the live SELECT policy "auth read bank": any signed-in
  -- user who holds REVIEW_QUESTIONS or GENERATE_QUESTIONS in at least one group.
  -- (Own rows are handled by the callers via created_by = p_user.)
  SELECT p_user IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.group_members gm
    WHERE gm.user_id = p_user
      AND (public.fn_has_permission(gm.group_id, p_user, 'REVIEW_QUESTIONS'::public.app_permission)
        OR public.fn_has_permission(gm.group_id, p_user, 'GENERATE_QUESTIONS'::public.app_permission))
  );
$$;
REVOKE ALL ON FUNCTION public._fn_can_read_bank(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public._fn_can_see_bank_answer(p_user uuid, p_created_by uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
  -- Answer key: the author, or a REVIEW_QUESTIONS holder (same actors the live
  -- "owner update bank" policy trusts with the content).
  SELECT p_user IS NOT NULL AND (
    p_created_by = p_user
    OR EXISTS (
      SELECT 1 FROM public.group_members gm
      WHERE gm.user_id = p_user
        AND public.fn_has_permission(gm.group_id, p_user, 'REVIEW_QUESTIONS'::public.app_permission)
    )
  );
$$;
REVOKE ALL ON FUNCTION public._fn_can_see_bank_answer(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- browse (no answer key)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_list_question_bank(
  p_search text DEFAULT NULL,
  p_status text DEFAULT NULL,
  p_subject_id uuid DEFAULT NULL,
  p_topic_node_id uuid DEFAULT NULL,
  p_difficulty text DEFAULT NULL,
  p_language text DEFAULT NULL,
  p_question_type text DEFAULT NULL,
  p_source text DEFAULT NULL,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
 RETURNS TABLE(
   id uuid, question text, options jsonb, explanation text, subject_id uuid,
   subject_name text, chapter text, topic_node_id uuid, difficulty text,
   language text, question_type text, source text, status public.question_status,
   created_by uuid, created_by_name text, times_used integer,
   created_at timestamptz, updated_at timestamptz, archived_at timestamptz,
   total_count bigint
 )
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_uid uuid := auth.uid();
  v_limit integer := least(greatest(coalesce(p_limit, 20), 1), 50);
  v_offset integer := greatest(coalesce(p_offset, 0), 0);
  v_reader boolean;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if p_status is not null and p_status not in ('pending_review','approved','rejected','needs_revision','archived') then
    raise exception 'VALIDATION_ERROR: invalid status filter';
  end if;
  if p_difficulty is not null and p_difficulty not in ('easy','medium','hard') then
    raise exception 'VALIDATION_ERROR: invalid difficulty filter';
  end if;
  if p_language is not null and p_language not in ('en','hi','hinglish') then
    raise exception 'VALIDATION_ERROR: invalid language filter';
  end if;
  if p_source is not null and p_source not in ('manual','upload','ai','mixed') then
    raise exception 'VALIDATION_ERROR: invalid source filter';
  end if;
  v_reader := public._fn_can_read_bank(v_uid);
  return query
  select qb.id, qb.question, qb.options, qb.explanation, qb.subject_id,
         qb.subject_name, qb.chapter, qb.topic_node_id, qb.difficulty,
         qb.language, qb.question_type, qb.source, qb.status,
         qb.created_by, p.full_name, qb.times_used,
         qb.created_at, qb.updated_at, qb.archived_at,
         count(*) over () as total_count
  from public.question_bank qb
  left join public.profiles p on p.id = qb.created_by
  where (qb.created_by = v_uid or v_reader)
    and (p_status is null or qb.status = p_status::public.question_status)
    and (p_subject_id is null or qb.subject_id = p_subject_id)
    and (p_topic_node_id is null or qb.topic_node_id = p_topic_node_id)
    and (p_difficulty is null or qb.difficulty = p_difficulty)
    and (p_language is null or qb.language = p_language)
    and (p_question_type is null or qb.question_type = p_question_type)
    and (p_source is null or qb.source = p_source)
    and (p_search is null or btrim(p_search) = ''
         or qb.question ilike '%' || btrim(p_search) || '%'
         or coalesce(qb.subject_name, '') ilike '%' || btrim(p_search) || '%'
         or coalesce(qb.chapter, '') ilike '%' || btrim(p_search) || '%')
  order by qb.updated_at desc, qb.id desc
  limit v_limit offset v_offset;
end
$$;
REVOKE ALL ON FUNCTION public.rpc_list_question_bank(text, text, uuid, uuid, text, text, text, text, integer, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_list_question_bank(text, text, uuid, uuid, text, text, text, text, integer, integer) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- detail (answer key only when explicitly requested AND authorized)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_get_question_bank_question(p_id uuid, p_include_answer boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_uid uuid := auth.uid();
  qb public.question_bank%rowtype;
  v_name text;
  v_out jsonb;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  select * into qb from public.question_bank where id = p_id;
  if not found or not (qb.created_by = v_uid or public._fn_can_read_bank(v_uid)) then
    raise exception 'QUESTION_NOT_FOUND';
  end if;
  select full_name into v_name from public.profiles where id = qb.created_by;
  v_out := jsonb_build_object(
    'id', qb.id, 'question', qb.question, 'options', qb.options,
    'explanation', qb.explanation, 'subject_id', qb.subject_id,
    'subject_name', qb.subject_name, 'chapter', qb.chapter,
    'topic_node_id', qb.topic_node_id, 'difficulty', qb.difficulty,
    'language', qb.language, 'question_type', qb.question_type,
    'source', qb.source, 'status', qb.status, 'created_by', qb.created_by,
    'created_by_name', v_name, 'times_used', qb.times_used,
    'created_at', qb.created_at, 'updated_at', qb.updated_at,
    'archived_at', qb.archived_at, 'reviewed_by', qb.reviewed_by,
    'reviewed_at', qb.reviewed_at, 'answer_included', false
  );
  if coalesce(p_include_answer, false) then
    if not public._fn_can_see_bank_answer(v_uid, qb.created_by) then
      raise exception 'ANSWER_KEY_FORBIDDEN';
    end if;
    v_out := v_out || jsonb_build_object('correct_option', qb.correct_option, 'answer_included', true);
  end if;
  return v_out;
end
$$;
REVOKE ALL ON FUNCTION public.rpc_get_question_bank_question(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_question_bank_question(uuid, boolean) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- snapshot: bank row -> independent test-linked questions row (server-side copy)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.rpc_clone_bank_questions(p_test_id uuid, p_bank_ids uuid[], p_marks_per_question numeric DEFAULT 1)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_uid uuid := auth.uid();
  v_test public.tests%rowtype;
  v_reader boolean;
  v_bank_id uuid;
  qb public.question_bank%rowtype;
  v_qid uuid;
  v_ordinal integer;
  v_cloned uuid[] := '{}';
  v_dup uuid[] := '{}';
  v_unavail uuid[] := '{}';
  v_ids uuid[];
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  if p_bank_ids is null or coalesce(array_length(p_bank_ids, 1), 0) = 0 then
    raise exception 'VALIDATION_ERROR: p_bank_ids is required';
  end if;
  if array_length(p_bank_ids, 1) > 100 then
    raise exception 'VALIDATION_ERROR: at most 100 questions per call';
  end if;
  if p_marks_per_question is null or p_marks_per_question <= 0 then
    raise exception 'VALIDATION_ERROR: marks must be greater than 0';
  end if;
  -- target test: exists, not soft-deleted, editable lifecycle (same window as the
  -- live questions INSERT policy), caller = creator or EDIT_TEST in its group
  select * into v_test from public.tests where id = p_test_id for update;
  if not found or coalesce(v_test.is_soft_deleted, false) then
    raise exception 'TEST_NOT_FOUND';
  end if;
  if v_test.status::text not in ('draft', 'ready', 'scheduled', 'published') then
    raise exception 'TEST_LOCKED: questions can only be added to draft, ready, scheduled or published tests';
  end if;
  if v_test.created_by is distinct from v_uid
     and not (v_test.group_id is not null
              and public.fn_has_permission(v_test.group_id, v_uid, 'EDIT_TEST'::public.app_permission)) then
    raise exception 'PERMISSION_DENIED: creator or EDIT_TEST required for this test';
  end if;
  v_reader := public._fn_can_read_bank(v_uid);
  select array_agg(distinct x) into v_ids from unnest(p_bank_ids) x;
  foreach v_bank_id in array v_ids loop
    select * into qb from public.question_bank where id = v_bank_id;
    -- unavailable: missing, not readable by the caller, not approved, or archived
    if not found
       or not (qb.created_by = v_uid or v_reader)
       or qb.status <> 'approved'::public.question_status
       or qb.archived_at is not null then
      v_unavail := v_unavail || v_bank_id;
      continue;
    end if;
    -- duplicate: this bank question is already in the test
    if exists (select 1 from public.questions q where q.test_id = p_test_id and q.bank_id = v_bank_id) then
      v_dup := v_dup || v_bank_id;
      continue;
    end if;
    v_ordinal := public._fn_get_next_question_ordinal(p_test_id);
    -- SNAPSHOT: every content field is copied by value; the only link back is the
    -- bank_id metadata column (FK ON DELETE SET NULL). Later bank edits never
    -- touch this row.
    insert into public.questions (
      test_id, ordinal, question, options, correct_option, explanation,
      subject_id, topic_node_id, difficulty, marks, status, source_batch,
      bank_id, language, question_type
    ) values (
      p_test_id, v_ordinal, qb.question, qb.options, qb.correct_option,
      coalesce(qb.explanation, ''), qb.subject_id, qb.topic_node_id,
      coalesce(qb.difficulty, 'medium'), p_marks_per_question,
      'approved'::public.question_status, null,
      qb.id, coalesce(qb.language, 'en'), coalesce(qb.question_type, 'mcq')
    ) returning id into v_qid;
    v_cloned := v_cloned || v_qid;
    update public.question_bank set times_used = times_used + 1 where id = qb.id;
  end loop;
  return jsonb_build_object(
    'test_id', p_test_id,
    'cloned', coalesce(array_length(v_cloned, 1), 0),
    'question_ids', to_jsonb(v_cloned),
    'skipped_duplicate', to_jsonb(v_dup),
    'skipped_unavailable', to_jsonb(v_unavail)
  );
end
$$;
REVOKE ALL ON FUNCTION public.rpc_clone_bank_questions(uuid, uuid[], numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_clone_bank_questions(uuid, uuid[], numeric) TO authenticated, service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- legacy-compatible availability count (the Flutter draft and legacy call it)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_bank_available(p_subject_name text DEFAULT '', p_chapter text DEFAULT '', p_difficulty text DEFAULT '', p_language text DEFAULT '')
 RETURNS integer
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_uid uuid := auth.uid();
  v_reader boolean;
  v_n integer;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  v_reader := public._fn_can_read_bank(v_uid);
  select count(*)::integer into v_n
  from public.question_bank qb
  where (qb.created_by = v_uid or v_reader)
    and qb.status = 'approved'::public.question_status
    and qb.archived_at is null
    and (coalesce(p_subject_name, '') = '' or coalesce(qb.subject_name, '') ilike '%' || btrim(p_subject_name) || '%')
    and (coalesce(p_chapter, '') = '' or coalesce(qb.chapter, '') ilike '%' || btrim(p_chapter) || '%')
    and (coalesce(p_difficulty, '') = '' or qb.difficulty = p_difficulty)
    and (coalesce(p_language, '') = '' or qb.language = p_language);
  return v_n;
end
$$;
REVOKE ALL ON FUNCTION public.fn_bank_available(text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_bank_available(text, text, text, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- postflight (read-only)
SELECT p.proname, p.prosecdef AS definer, p.proconfig AS config,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('_fn_can_read_bank', '_fn_can_see_bank_answer', 'rpc_list_question_bank', 'rpc_get_question_bank_question', 'rpc_clone_bank_questions', 'fn_bank_available')
ORDER BY 1;
-- expect: all definer=true, config={search_path=}, anon_exec=false; auth_exec=false for the two _fn_ helpers, true for the four RPCs
