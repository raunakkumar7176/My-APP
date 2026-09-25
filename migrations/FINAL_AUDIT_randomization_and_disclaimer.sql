-- ============================================================
-- FINAL AUDIT — question-order randomization toggle + pre-test
-- disclaimer acceptance record (both additive, neither modifies any
-- existing function body)
-- ============================================================
-- AUDIT FINDING (this task's own required Part M step): the question-order
-- randomization feature described in this task ALREADY EXISTS end-to-end on
-- the client:
--   lib/features/test/domain/deterministic_shuffle.dart — DeterministicShuffle
--   lib/features/test/state/attempt_controller.dart:289-299 — _applyQuestions()
--     seeds the shuffle with `_attempt!.id` (the server-generated, RLS-
--     protected, per-attempt UUID) whenever `tests.shuffle_questions` is
--     true, and shuffles a SEPARATE deterministic order for each question's
--     own options (seed `'${attemptId}_${questionId}'`). Answers are already
--     keyed by question_id (Map<String, Answer> _answersById), never by
--     display position, so scoring is unaffected by construction.
-- The ONE real gap: `tests.shuffle_questions` (confirmed to exist as a
-- client-read field; DDL default `false`) has NO client-facing way to be
-- set to true — neither `rpc_create_test` (G10_1_fix_rpc_create_test_
-- permission.sql, most recent live version, full body read) nor
-- `rpc_update_test` (R4_5_1_test_creation_write.sql) accepts a
-- p_shuffle_questions parameter. This migration adds ONE new, narrow RPC to
-- toggle just this column, rather than modifying either of those two
-- already-once-security-patched functions — smaller blast radius, and this
-- repo's own migration history for rpc_create_test does not perfectly
-- track live schema (a `duration_sec` vs the original DDL's
-- `duration_minutes` naming mismatch was found during this same audit),
-- so a targeted new function is the safer additive choice than editing a
-- function whose exact current live body cannot be independently confirmed
-- from this environment (no Supabase CLI/psql/.env — same constraint noted
-- in every prior gate this series).
--
-- SEPARATELY: no existing table/column anywhere in this repo's migrations
-- records pre-test disclaimer acceptance. Adds three nullable columns to
-- the already-fully-defined `public.attempts` table (a pure schema
-- addition, not a function edit) plus one new RPC to set them, immutable
-- after first acceptance.
--
-- Run in the Supabase SQL Editor top to bottom. NOT applied automatically —
-- no live database access exists in the environment that authored this file.
--
-- ------------------------------------------------------------
-- PREFLIGHT (read-only) — expected results in comments
-- ------------------------------------------------------------
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'tests' AND column_name = 'shuffle_questions';
-- expect: boolean, NOT NULL, default false. If this column does not exist,
-- STOP — the randomization feature already reads a field that would then
-- be entirely fictional; do not proceed on an unverified assumption.

SELECT column_name FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'attempts'
  AND column_name IN ('disclaimer_accepted_at', 'disclaimer_version', 'disclaimer_language');
-- expect: NO ROWS (none of these three columns exist yet). If any already
-- exist, STOP — a disclaimer-acceptance mechanism may already be in place
-- under a different design; do not blindly add columns that might collide.

SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('rpc_set_test_shuffle_questions', 'rpc_record_disclaimer_acceptance');
-- expect: NO ROWS (neither function exists yet).

-- ------------------------------------------------------------
-- STEP 1 — allow a test's creator/permitted editor to toggle shuffle_questions
-- ------------------------------------------------------------
-- Mirrors the existing test-edit permission pattern used elsewhere in this
-- project (creator, or EDIT_TEST in the test's group for a group test) —
-- reusing public.fn_has_permission, never inventing a new permission check.
-- Only draft tests may be changed, matching this app's general "published
-- tests are mostly immutable" convention (rpc_update_test's own
-- restricted-field design) — shuffle order is presentation-only and safe
-- to change on a draft, but changing it on a published/live test could
-- alter what students who already started see if they reload, which is
-- exactly the kind of mid-test inconsistency this task explicitly asks to
-- avoid (A7: never reshuffle after attempt creation) — restricting to
-- draft is the conservative, safe choice.
CREATE OR REPLACE FUNCTION public.rpc_set_test_shuffle_questions(
  p_test_id uuid,
  p_shuffle boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_test public.tests;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT * INTO v_test FROM public.tests WHERE id = p_test_id AND is_soft_deleted = false;
  IF v_test.id IS NULL THEN
    RAISE EXCEPTION 'TEST_NOT_FOUND';
  END IF;

  IF v_test.status::text <> 'draft' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: shuffle_questions can only be changed while the test is a draft';
  END IF;

  IF v_test.created_by <> v_uid THEN
    IF v_test.group_id IS NULL
       OR NOT public.fn_has_permission(v_test.group_id, v_uid, 'EDIT_TEST'::public.app_permission)
    THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Cannot edit this test';
    END IF;
  END IF;

  UPDATE public.tests SET shuffle_questions = p_shuffle WHERE id = p_test_id;

  RETURN jsonb_build_object('test_id', p_test_id, 'shuffle_questions', p_shuffle);
END
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_set_test_shuffle_questions(uuid, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.rpc_set_test_shuffle_questions(uuid, boolean) FROM anon;
REVOKE ALL ON FUNCTION public.rpc_set_test_shuffle_questions(uuid, boolean) FROM PUBLIC;

-- ------------------------------------------------------------
-- STEP 2 — disclaimer acceptance columns (pure additive schema change)
-- ------------------------------------------------------------
ALTER TABLE public.attempts
  ADD COLUMN IF NOT EXISTS disclaimer_accepted_at timestamptz,
  ADD COLUMN IF NOT EXISTS disclaimer_version text,
  ADD COLUMN IF NOT EXISTS disclaimer_language text;

COMMENT ON COLUMN public.attempts.disclaimer_accepted_at IS
  'Set once, server-side, by rpc_record_disclaimer_acceptance; NULL means not yet accepted. Never set by any other path.';
COMMENT ON COLUMN public.attempts.disclaimer_version IS
  'Disclaimer text version the student acknowledged, e.g. "v1".';
COMMENT ON COLUMN public.attempts.disclaimer_language IS
  '"en" or "hi" — which language the student read when accepting.';

-- ------------------------------------------------------------
-- STEP 3 — rpc_record_disclaimer_acceptance: record acceptance once,
--          immutably, for the caller's own attempt only.
-- ------------------------------------------------------------
-- Called immediately after rpc_start_attempt/rpc_start_attempt_by_code
-- succeeds (the disclaimer itself is shown BEFORE that call, so nothing
-- is created merely by opening/reading the disclaimer — matches this
-- task's Part G). Idempotent and immutable: the WHERE clause only ever
-- matches a row that has not yet recorded acceptance, so a second call
-- (retry, double-tap, or a client bug) is a silent no-op rather than
-- overwriting the original acceptance timestamp.
CREATE OR REPLACE FUNCTION public.rpc_record_disclaimer_acceptance(
  p_attempt_id uuid,
  p_version text,
  p_language text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_count integer;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  IF p_version IS NULL OR length(trim(p_version)) = 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: version is required';
  END IF;

  IF p_language NOT IN ('en', 'hi') THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: language must be en or hi';
  END IF;

  UPDATE public.attempts
     SET disclaimer_accepted_at = now(),
         disclaimer_version = p_version,
         disclaimer_language = p_language
   WHERE id = p_attempt_id
     AND user_id = v_uid
     AND disclaimer_accepted_at IS NULL;
  GET DIAGNOSTICS v_count = ROW_COUNT;

  IF v_count = 0 THEN
    -- Either the attempt doesn't exist/belong to this user (ownership
    -- failure — reported the same as "already recorded" so a non-owner
    -- cannot distinguish the two cases), or acceptance was already
    -- recorded (idempotent no-op). Confirm which, for the caller's own
    -- attempt only, without revealing anything about attempts it does
    -- not own.
    IF NOT EXISTS (
      SELECT 1 FROM public.attempts WHERE id = p_attempt_id AND user_id = v_uid
    ) THEN
      RAISE EXCEPTION 'ATTEMPT_NOT_FOUND';
    END IF;
  END IF;

  RETURN jsonb_build_object('attempt_id', p_attempt_id, 'recorded', v_count > 0);
END
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_record_disclaimer_acceptance(uuid, text, text) TO authenticated;
REVOKE ALL ON FUNCTION public.rpc_record_disclaimer_acceptance(uuid, text, text) FROM anon;
REVOKE ALL ON FUNCTION public.rpc_record_disclaimer_acceptance(uuid, text, text) FROM PUBLIC;

-- ------------------------------------------------------------
-- ROLLBACK
-- ------------------------------------------------------------
-- DROP FUNCTION IF EXISTS public.rpc_set_test_shuffle_questions(uuid, boolean);
-- DROP FUNCTION IF EXISTS public.rpc_record_disclaimer_acceptance(uuid, text, text);
-- ALTER TABLE public.attempts
--   DROP COLUMN IF EXISTS disclaimer_accepted_at,
--   DROP COLUMN IF EXISTS disclaimer_version,
--   DROP COLUMN IF EXISTS disclaimer_language;

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only)
-- ------------------------------------------------------------
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('rpc_set_test_shuffle_questions', 'rpc_record_disclaimer_acceptance')
ORDER BY 1;
-- expect: both rows, prosecdef = true, proconfig = {search_path=}

SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public'
  AND routine_name IN ('rpc_set_test_shuffle_questions', 'rpc_record_disclaimer_acceptance')
ORDER BY 1, 2;
-- expect: authenticated EXECUTE only, no anon/PUBLIC row for either.

-- ------------------------------------------------------------
-- SECURITY TEST MATRIX (manual / staging verification only)
-- ------------------------------------------------------------
-- 1. Owner sets shuffle on own draft test -> succeeds, shuffle_questions=true.
-- 2. Non-owner, non-permitted user attempts to set it -> PERMISSION_DENIED.
-- 3. Attempt to set it on a published test -> VALIDATION_ERROR.
-- 4. Own attempt, first acceptance call -> recorded=true, columns set.
-- 5. Same attempt, second acceptance call -> recorded=false (idempotent no-op),
--    disclaimer_accepted_at UNCHANGED from the first call's timestamp.
-- 6. Another user's attempt_id -> ATTEMPT_NOT_FOUND (ownership-filtered,
--    never reveals whether that id exists at all).
-- 7. Forged/nonexistent attempt_id -> ATTEMPT_NOT_FOUND.
