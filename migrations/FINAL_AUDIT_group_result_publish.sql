-- FINAL_AUDIT_group_result_publish.sql
-- ============================================================================
-- UNAPPLIED. This environment has no live Supabase access (no CLI/psql/.env).
-- A human with production DB access must review and run this manually.
-- ============================================================================
--
-- CONTEXT (live-proven, see docs/live/rpc_generate_results.live.sql,
-- migrations/R4_HOTFIX_submit_autosubmit_batch_reuse.sql, and
-- docs/NOTIFICATION_SYSTEM_FULL_VERIFICATION_REPORT.md §3.4/§5.2):
--
-- 1. rpc_submit_attempt / fn_auto_submit already call fn_score_attempt(uuid)
--    synchronously at submit/auto-submit time. The live `results` RLS SELECT
--    policy "own results" is simply `user_id = auth.uid()` — there is no
--    publish gate. A student can therefore read their own final marks the
--    instant they submit, which violates this task's Core Product Rule
--    ("submission" and "result published" must be two different events).
--
-- 2. rpc_get_leaderboard (migrations/G17_01_fix_rpc_get_leaderboard_access.sql,
--    live) joins `results` for any creator/group-member/participant caller
--    with NO publish check either — any group member can see EVERYONE's
--    score/rank the moment attempts are scored, not just their own. This is
--    a bigger leak than #1: it exposes other students' data pre-publish.
--
-- 3. `notif_category` already includes RESULTS_AVAILABLE (live, confirmed in
--    docs/NOTIFICATION_SYSTEM_FULL_VERIFICATION_REPORT.md §3.4) but no
--    trigger or RPC ever creates it (confirmed NOT IMPLEMENTED, same report
--    §2 row E). This migration is the first thing that emits it.
--
-- WHAT THIS MIGRATION DOES (additive only):
--   A. result_batches: + published_at timestamptz, + published_by uuid.
--   B. rpc_publish_results(p_test_id) — a NEW, separate action from
--      rpc_generate_results. Requires an already-completed/partially-
--      completed batch (does not score anything itself), same authorization
--      as rpc_generate_results (owner or GENERATE_RESULTS), idempotent
--      (second call returns the existing published state, no duplicate
--      notifications), notifies only eligible participants (attempts with
--      status submitted/auto_submitted/scored for that test — the exact
--      eligibility rpc_generate_results itself already uses, not blindly
--      every group_member) via the existing RESULTS_AVAILABLE category and
--      notifications table, respecting fn_is_notification_allowed and using
--      dedupe_key so a repeat/concurrent publish cannot double-notify.
--   C. `results` SELECT policy "own results" — ALTER POLICY only, same
--      command/roles, adds a publish check that is a no-op for every
--      self/practice test (group_id IS NULL — completely unaffected,
--      unchanged behavior) and requires result_batches.published_at IS NOT
--      NULL for group tests (group_id IS NOT NULL).
--   D. rpc_get_leaderboard — CREATE OR REPLACE with the identical signature,
--      columns and ordering as the live G17-01 version, adding the same
--      group_id-scoped publish check to its WHERE clause. Nothing else in
--      the function changes.
--
-- NOT changed: fn_score_attempt, rpc_generate_results, rpc_submit_attempt,
-- fn_auto_submit, fn_notify_group, fn_is_notification_allowed, any table's
-- grants, the "analytics holders see group results" policy (VIEW_GROUP_
-- ANALYTICS holders keep seeing results pre-publish for internal review —
-- that is the deliberate purpose of that separate permission and this task
-- never asked to remove it), notifications table schema/RLS.
--
-- ------------------------------------------------------------
-- PREFLIGHT — verify current state before applying
-- ------------------------------------------------------------
-- SELECT column_name FROM information_schema.columns
-- WHERE table_schema='public' AND table_name='result_batches' AND column_name IN ('published_at','published_by');
-- expect: NO ROWS.
--
-- SELECT policyname, qual FROM pg_policies
-- WHERE schemaname='public' AND tablename='results' AND policyname='own results';
-- expect: ONE ROW, qual = '(user_id = auth.uid())'.
--
-- SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
-- WHERE n.nspname='public' AND p.proname='rpc_publish_results';
-- expect: NO ROWS.

-- ------------------------------------------------------------
-- STEP A — result_batches: additive publish columns
-- ------------------------------------------------------------
ALTER TABLE public.result_batches
  ADD COLUMN IF NOT EXISTS published_at timestamptz,
  ADD COLUMN IF NOT EXISTS published_by uuid REFERENCES public.profiles(id);

COMMENT ON COLUMN public.result_batches.published_at IS
  'Set once, server-side, only by rpc_publish_results. NULL means the batch is scored but not yet visible to students. Never set by rpc_generate_results itself — generation and publication are two separate events by product rule.';
COMMENT ON COLUMN public.result_batches.published_by IS
  'auth.uid() of the authorized user (owner or GENERATE_RESULTS holder) who published this batch.';

-- ------------------------------------------------------------
-- STEP B — rpc_publish_results: the one authoritative publish action
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_publish_results(p_test_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_user uuid := auth.uid();
  v_test public.tests;
  v_batch public.result_batches;
  v_notified integer := 0;
  v_uid uuid;
BEGIN
  IF v_user IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT * INTO v_test FROM public.tests WHERE id = p_test_id AND is_soft_deleted = false FOR UPDATE;
  IF v_test.id IS NULL THEN
    RAISE EXCEPTION 'TEST_NOT_FOUND';
  END IF;

  -- Same authorization as rpc_generate_results: owner always; group members
  -- need GENERATE_RESULTS. No new permission invented.
  IF v_test.created_by <> v_user THEN
    IF v_test.group_id IS NULL
       OR NOT public.fn_has_permission(v_test.group_id, v_user, 'GENERATE_RESULTS'::public.app_permission)
    THEN
      RAISE EXCEPTION 'GENERATE_RESULTS_FORBIDDEN';
    END IF;
  END IF;

  SELECT * INTO v_batch FROM public.result_batches WHERE test_id = p_test_id FOR UPDATE;

  IF v_batch.id IS NULL OR v_batch.status NOT IN ('completed'::public.batch_status, 'partially_completed'::public.batch_status) THEN
    RAISE EXCEPTION 'RESULTS_NOT_GENERATED: Result cannot be published yet because result processing is incomplete.';
  END IF;

  -- Idempotent: already published -> return the existing state, notify no one again.
  IF v_batch.published_at IS NOT NULL THEN
    RETURN jsonb_build_object(
      'batch_id', v_batch.id,
      'test_id', v_batch.test_id,
      'status', 'published',
      'published_at', v_batch.published_at,
      'notified', 0,
      'reused', true
    );
  END IF;

  UPDATE public.result_batches
  SET published_at = now(), published_by = v_user
  WHERE id = v_batch.id
  RETURNING * INTO v_batch;

  -- Notify only eligible participants — the same finalized-attempt set
  -- rpc_generate_results itself scores, never all group_members.
  FOR v_uid IN
    SELECT DISTINCT a.user_id
    FROM public.attempts a
    WHERE a.test_id = p_test_id
      AND a.status IN ('submitted'::public.attempt_status, 'auto_submitted'::public.attempt_status, 'scored'::public.attempt_status)
  LOOP
    IF public.fn_is_notification_allowed(v_uid, 'RESULTS_AVAILABLE', v_test.group_id) THEN
      INSERT INTO public.notifications (user_id, category, title, body, data, dedupe_key)
      VALUES (
        v_uid,
        'RESULTS_AVAILABLE'::public.notif_category,
        'Test Result Published',
        'The result for ' || v_test.title || ' is now available.',
        jsonb_build_object('test_id', p_test_id, 'deep_link', '/tests/' || p_test_id::text),
        'results_published:' || p_test_id::text
      )
      ON CONFLICT (user_id, dedupe_key) DO NOTHING;
      v_notified := v_notified + 1;
    END IF;
  END LOOP;

  RETURN jsonb_build_object(
    'batch_id', v_batch.id,
    'test_id', v_batch.test_id,
    'status', 'published',
    'published_at', v_batch.published_at,
    'notified', v_notified,
    'reused', false
  );
END
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_publish_results(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.rpc_publish_results(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.rpc_publish_results(uuid) FROM PUBLIC;

-- ------------------------------------------------------------
-- STEP C — results SELECT: gate "own results" on publication for group
--          tests only (self/practice tests: group_id IS NULL, unaffected).
-- ------------------------------------------------------------
ALTER POLICY "own results" ON public.results
USING (
  user_id = auth.uid()
  AND (
    NOT EXISTS (
      SELECT 1 FROM public.tests t WHERE t.id = results.test_id AND t.group_id IS NOT NULL
    )
    OR EXISTS (
      SELECT 1 FROM public.result_batches rb
      WHERE rb.test_id = results.test_id AND rb.published_at IS NOT NULL
    )
  )
);

-- "analytics holders see group results" (VIEW_GROUP_ANALYTICS) is left
-- untouched on purpose: that permission exists specifically so an
-- authorized manager can review results before publishing.

-- ------------------------------------------------------------
-- STEP D — rpc_get_leaderboard: same publish gate, same exemption.
--          Signature/columns/ordering verbatim from the live G17-01 body.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_get_leaderboard(p_test uuid)
 RETURNS TABLE(rank bigint, user_id uuid, full_name text, avatar_url text, student_code text, score numeric, max_score numeric, percentage numeric, accuracy numeric, submitted_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $$
    SELECT
        row_number() OVER (
            ORDER BY r.score DESC, r.percentage DESC, a.submitted_at ASC, a.id ASC
        ) AS rank,
        a.user_id,
        p.full_name,
        p.avatar_url,
        p.student_code,
        r.score,
        r.max_score,
        r.percentage,
        r.accuracy,
        a.submitted_at
    FROM public.attempts a
    INNER JOIN public.results r ON r.attempt_id = a.id
    LEFT JOIN public.profiles p ON p.id = a.user_id
    INNER JOIN public.tests t ON t.id = a.test_id
    WHERE a.test_id = p_test
      AND auth.uid() IS NOT NULL
      AND (
            t.created_by = auth.uid()
         OR (t.group_id IS NOT NULL AND public.fn_is_member(t.group_id, auth.uid()))
         OR EXISTS (
              SELECT 1 FROM public.attempts mine
              WHERE mine.test_id = t.id AND mine.user_id = auth.uid()
            )
      )
      AND (
            t.group_id IS NULL
         OR EXISTS (
              SELECT 1 FROM public.result_batches rb
              WHERE rb.test_id = t.id AND rb.published_at IS NOT NULL
            )
         -- Same asymmetry as the "analytics holders see group results"
         -- policy on results: the owner and VIEW_GROUP_ANALYTICS holders may
         -- preview the leaderboard before publishing (Part 14 — the result
         -- manager's own view is not gated the same way a student's is).
         OR t.created_by = auth.uid()
         OR public.fn_has_permission(t.group_id, auth.uid(), 'VIEW_GROUP_ANALYTICS'::public.app_permission)
      )
    ORDER BY r.score DESC, r.percentage DESC, a.submitted_at ASC, a.id ASC;
$$;

REVOKE EXECUTE ON FUNCTION public.rpc_get_leaderboard(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_leaderboard(uuid) TO authenticated, service_role;

-- ------------------------------------------------------------
-- POSTFLIGHT — verify after applying
-- ------------------------------------------------------------
-- SELECT p.proname, p.prosecdef, p.proconfig
-- FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public' AND p.proname IN ('rpc_publish_results', 'rpc_get_leaderboard');
-- expect: both rows, prosecdef = true, proconfig contains search_path.
--
-- SELECT policyname, qual FROM pg_policies
-- WHERE schemaname='public' AND tablename='results' AND policyname='own results';
-- expect: qual now includes 'published_at'.
--
-- ------------------------------------------------------------
-- SECURITY / BEHAVIOR TEST MATRIX (manual, run against a live project)
-- ------------------------------------------------------------
-- 1. Self/practice test (group_id NULL): student reads own results row
--    immediately after submit, unchanged from today. No batch/publish needed.
-- 2. Group test: student submits; SELECT own results row -> 0 rows (RLS)
--    until published.
-- 3. Group test: any group member calls rpc_get_leaderboard before publish
--    -> 0 rows, even though attempts are scored.
-- 4. Owner calls rpc_generate_results -> batch completed, published_at
--    still NULL -> results/leaderboard still hidden from students.
-- 5. Owner calls rpc_publish_results before rpc_generate_results (no batch,
--    or batch pending/processing/failed) -> RESULTS_NOT_GENERATED.
-- 6. Owner calls rpc_publish_results after a completed batch -> succeeds;
--    published_at set; eligible participants get one RESULTS_AVAILABLE
--    notification each; non-participant group members get none.
-- 7. Owner calls rpc_publish_results twice (or two callers race) ->
--    second call returns reused:true, published_at unchanged, notified:0,
--    no duplicate notification rows (dedupe_key unique index).
-- 8. After publish: student SELECT own results row -> 1 row. Another
--    student's row -> still 0 rows (RLS still scopes by user_id).
-- 9. After publish: rpc_get_leaderboard returns all eligible rows, ranked
--    identically to its pre-existing ORDER BY (no ranking logic changed).
-- 10. Non-member / anon calling rpc_publish_results -> GENERATE_RESULTS_FORBIDDEN
--     / permission denied respectively.
-- 11. VIEW_GROUP_ANALYTICS holder (not GENERATE_RESULTS) can still read all
--     results rows before publish (existing "analytics holders" policy
--     untouched) -> confirms manager preview is preserved.
-- 12. Owner (or VIEW_GROUP_ANALYTICS holder) calls rpc_get_leaderboard before
--     publish -> full ranked rows (manager preview, matches #11's asymmetry).
--     A plain member/participant with neither role gets 0 rows for the same
--     call at the same pre-publish moment (test #3 above).
