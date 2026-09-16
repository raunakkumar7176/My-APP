-- ============================================================
-- R4 — rpc_delete_test(p_test_id uuid): DRAFT-ONLY soft delete (V1)
-- ============================================================
-- Repo audit (2026-09-16): no delete RPC exists in any migration; the old
-- Flutter TestService did a direct `UPDATE public.tests` (removed in the R4
-- rebuild) and no client UPDATE policy on tests is verified live. Existing
-- soft-delete contract: `is_soft_deleted`, `deleted_at`, `deleted_by`,
-- `deletion_reason` columns (owner-listed), and every read path already
-- filters `is_soft_deleted = false` (rpc_start_attempt_by_code,
-- rpc_start_attempt core, client list/detail queries).
--
-- Rule (server-enforced): creator only, status = 'draft', not already
-- soft-deleted. Nothing is physically deleted; questions/attempts/results
-- are untouched. No RLS/grant/schema change.
--
-- STEP 1 (read-only) — preflight, run first and check:
--   a) the four soft-delete columns exist with the expected types
--   b) no existing rpc_delete_test signature (return-type conflict)
-- ------------------------------------------------------------
-- SELECT column_name, data_type, udt_name, is_nullable
--   FROM information_schema.columns
--  WHERE table_schema = 'public' AND table_name = 'tests'
--    AND column_name IN ('is_soft_deleted','deleted_at','deleted_by','deletion_reason','status','created_by');
-- SELECT p.oid::regprocedure, pg_get_function_result(p.oid)
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--  WHERE n.nspname = 'public' AND p.proname = 'rpc_delete_test';
--   -- expected: 0 rows. If a row exists with a non-jsonb result, DROP it
--   -- explicitly before STEP 2 (CREATE OR REPLACE cannot change return type).
--
-- STEP 2 — create the RPC.
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_delete_test(p_test_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_uid uuid;
  v_test record;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT t.id, t.created_by, t.status, t.is_soft_deleted
    INTO v_test
    FROM public.tests t
   WHERE t.id = p_test_id
   FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'TEST_NOT_FOUND';
  END IF;

  IF v_test.created_by IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'PERMISSION_DENIED: only the creator can delete this test';
  END IF;

  IF COALESCE(v_test.is_soft_deleted, false) THEN
    RAISE EXCEPTION 'TEST_ALREADY_DELETED';
  END IF;

  IF v_test.status::text <> 'draft' THEN
    RAISE EXCEPTION 'TEST_NOT_DRAFT: only draft tests can be deleted';
  END IF;

  UPDATE public.tests
     SET is_soft_deleted = true,
         deleted_at      = now(),
         deleted_by      = v_uid,
         deletion_reason = 'Deleted by test owner'
   WHERE id = p_test_id;

  RETURN jsonb_build_object('test_id', p_test_id, 'deleted', true);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.rpc_delete_test(uuid) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.rpc_delete_test(uuid) FROM anon;
GRANT  EXECUTE ON FUNCTION public.rpc_delete_test(uuid) TO authenticated;

-- STEP 3 (read-only) — verify.
-- ------------------------------------------------------------
-- SELECT p.oid::regprocedure, p.prosecdef, p.proconfig
--   FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
--  WHERE n.nspname = 'public' AND p.proname = 'rpc_delete_test';
-- SELECT grantee, privilege_type FROM information_schema.routine_privileges
--  WHERE routine_schema = 'public' AND routine_name = 'rpc_delete_test';
--   -- expected: authenticated EXECUTE only (plus owner).
-- As the creator, on one of your own drafts:
-- SELECT public.rpc_delete_test('<draft-test-uuid>');   -- {"test_id":..,"deleted":true}
-- SELECT id, status, is_soft_deleted, deleted_at, deleted_by, deletion_reason
--   FROM public.tests WHERE id = '<draft-test-uuid>';
-- SELECT public.rpc_delete_test('<draft-test-uuid>');   -- TEST_ALREADY_DELETED
-- SELECT public.rpc_delete_test('<published-test-uuid>'); -- TEST_NOT_DRAFT
