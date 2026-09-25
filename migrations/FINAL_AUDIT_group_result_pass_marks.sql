-- FINAL_AUDIT_group_result_pass_marks.sql
-- ============================================================================
-- UNAPPLIED. This environment has no live Supabase access (no CLI/psql/.env).
-- A human with production DB access must review and run this manually.
-- ============================================================================
--
-- Context: public.tests.passing_marks (integer NOT NULL DEFAULT 0) already
-- exists in the original DDL (R4_1_phase_db_foundation.sql) and is already
-- read/written by the Dart model (Test.passingMarks, JSON key
-- "passing_marks", lib/core/models/test.dart). But no live RPC exposes a
-- write path to it: the full parameter/INSERT-column lists of both
-- rpc_create_test and rpc_update_test do not include passing_marks. This is
-- the exact same shape of gap already found and fixed once for
-- shuffle_questions (see FINAL_AUDIT_randomization_and_disclaimer.sql) —
-- the column exists but is unreachable, so this adds ONE new, narrow,
-- additive RPC rather than risk modifying an existing, already-once-patched
-- RPC whose exact current live body cannot be independently confirmed from
-- this environment.
--
-- Group-result "PASS/FAIL" (Part of the FINAL GROUP RESULT task) is derived
-- as plain arithmetic (marks >= test.passing_marks) at the call site — this
-- RPC only lets a test's creator/editor set the threshold on a draft test;
-- it does not compute or store any student's pass/fail itself.
--
-- ------------------------------------------------------------
-- PREFLIGHT — verify current state before applying
-- ------------------------------------------------------------
-- SELECT p.proname
-- FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public' AND p.proname = 'rpc_set_test_pass_marks';
-- expect: NO ROWS (function does not exist yet).
--
-- SELECT column_name FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'tests' AND column_name = 'passing_marks';
-- expect: ONE ROW (column already exists; this migration does not touch it).

CREATE OR REPLACE FUNCTION public.rpc_set_test_pass_marks(
  p_test_id uuid,
  p_passing_marks integer
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

  IF p_passing_marks IS NULL OR p_passing_marks < 0 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: passing_marks must be a non-negative integer';
  END IF;

  SELECT * INTO v_test FROM public.tests WHERE id = p_test_id AND is_soft_deleted = false;
  IF v_test.id IS NULL THEN
    RAISE EXCEPTION 'TEST_NOT_FOUND';
  END IF;

  IF v_test.status::text <> 'draft' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: passing_marks can only be changed while the test is a draft';
  END IF;

  IF v_test.total_marks IS NOT NULL AND p_passing_marks > v_test.total_marks THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: passing_marks cannot exceed total_marks';
  END IF;

  IF v_test.created_by <> v_uid THEN
    IF v_test.group_id IS NULL
       OR NOT public.fn_has_permission(v_test.group_id, v_uid, 'EDIT_TEST'::public.app_permission)
    THEN
      RAISE EXCEPTION 'PERMISSION_DENIED: Cannot edit this test';
    END IF;
  END IF;

  UPDATE public.tests SET passing_marks = p_passing_marks WHERE id = p_test_id;

  RETURN jsonb_build_object('test_id', p_test_id, 'passing_marks', p_passing_marks);
END
$function$;

GRANT EXECUTE ON FUNCTION public.rpc_set_test_pass_marks(uuid, integer) TO authenticated;
REVOKE ALL ON FUNCTION public.rpc_set_test_pass_marks(uuid, integer) FROM anon;
REVOKE ALL ON FUNCTION public.rpc_set_test_pass_marks(uuid, integer) FROM PUBLIC;

-- ------------------------------------------------------------
-- POSTFLIGHT — verify after applying
-- ------------------------------------------------------------
-- SELECT p.proname, p.prosecdef, p.proconfig
-- FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public' AND p.proname = 'rpc_set_test_pass_marks';
-- expect: ONE ROW, prosecdef = true, proconfig contains 'search_path='.
--
-- ------------------------------------------------------------
-- SECURITY TEST MATRIX (manual, to run against a live project)
-- ------------------------------------------------------------
-- 1. Anon call -> must fail (no EXECUTE grant).
-- 2. Authenticated non-owner, non-EDIT_TEST student -> PERMISSION_DENIED.
-- 3. Creator, draft test, valid value <= total_marks -> succeeds, tests row updated.
-- 4. Creator, published test -> VALIDATION_ERROR (draft-only).
-- 5. Creator, negative value -> VALIDATION_ERROR.
-- 6. Creator, value > total_marks -> VALIDATION_ERROR.
-- 7. Group editor with EDIT_TEST permission, not the creator -> succeeds.
