-- ============================================================
-- R4 MIGRATION C — rpc_delete_test(p_test_id uuid, p_reason text DEFAULT NULL)
--                  DRAFT-ONLY SOFT DELETE (server-authorized)
-- ============================================================
-- Live facts (owner-verified 2026-09-17): tests has is_soft_deleted,
-- deleted_at, deleted_by, deletion_reason; RLS enabled; NO rpc_delete_test
-- exists; only rpc_delete_question (questions) exists as a delete RPC.
-- Every read path already excludes soft-deleted rows: client getById /
-- listAccessible / listMyDrafts (.eq is_soft_deleted false), core start
-- (is_soft_deleted → TEST_NOT_AVAILABLE), by-code lookup (is_soft_deleted =
-- false AND deleted_at IS NULL). So is_soft_deleted = true alone hides the
-- test everywhere; status is NOT changed (no enum value is repurposed).
--
-- Rule: auth.uid() = created_by AND status = 'draft' AND NOT is_soft_deleted.
-- Never a physical DELETE; questions/attempts/results untouched.
-- Idempotent: DROP IF EXISTS of the earlier 1-arg draft signature (never
-- applied) prevents an overload; CREATE OR REPLACE for the final signature.
--
-- ------------------------------------------------------------
-- PREFLIGHT (read-only) — STOP if anything differs from "expect"
-- ------------------------------------------------------------
SELECT column_name, data_type, udt_name, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'tests'
  AND column_name IN ('is_soft_deleted','deleted_at','deleted_by','deletion_reason','status','created_by')
ORDER BY column_name;
-- expect 6 rows: created_by uuid, deleted_at timestamptz, deleted_by uuid,
--                deletion_reason text, is_soft_deleted boolean, status test_status

SELECT p.oid::regprocedure AS signature, pg_get_function_result(p.oid) AS returns
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_delete_test';
-- expect: 0 rows. (If a (uuid) row exists it is the unapplied draft signature;
-- STEP 1 drops it. Any other signature/return type → STOP and report.)

SELECT c.relname, c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'tests';
-- expect: tests | t

SELECT count(*) AS soft_deleted_tests_before FROM public.tests WHERE is_soft_deleted = true;
-- note the number; it must be identical after the migration (no data change).

-- ------------------------------------------------------------
-- STEP 1 — remove the never-applied 1-arg draft signature (no-op when absent)
-- ------------------------------------------------------------
DROP FUNCTION IF EXISTS public.rpc_delete_test(uuid);

-- ------------------------------------------------------------
-- STEP 2 — the RPC
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_delete_test(p_test_id uuid, p_reason text DEFAULT NULL)
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

  IF v_test.status <> 'draft'::public.test_status THEN
    RAISE EXCEPTION 'TEST_NOT_DRAFT: only draft tests can be deleted';
  END IF;

  -- Soft delete only. deleted_by is always the caller (never a client value).
  UPDATE public.tests
     SET is_soft_deleted = true,
         deleted_at      = now(),
         deleted_by      = v_uid,
         deletion_reason = COALESCE(NULLIF(btrim(p_reason), ''), 'Deleted by test owner')
   WHERE id = p_test_id;

  RETURN jsonb_build_object('test_id', p_test_id, 'deleted', true);
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_delete_test(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_delete_test(uuid, text) FROM anon;
GRANT  EXECUTE ON FUNCTION public.rpc_delete_test(uuid, text) TO authenticated;

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only)
-- ------------------------------------------------------------
-- 1–3. signature, DEFINER, search_path
SELECT p.oid::regprocedure AS signature, pg_get_function_result(p.oid) AS returns,
       p.prosecdef AS security_definer, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_delete_test';
-- expect exactly one row: rpc_delete_test(uuid, text) | jsonb | t | {search_path=}

-- 4–5. grants: authenticated only; no anon / PUBLIC
SELECT grantee, privilege_type FROM information_schema.routine_privileges
WHERE routine_schema = 'public' AND routine_name = 'rpc_delete_test' ORDER BY 1;
-- expect: authenticated | EXECUTE (owner row may also appear); no anon, no PUBLIC

-- 6–8. body: soft-delete columns used, no physical DELETE, draft + owner rule
SELECT
  pg_get_functiondef(p.oid) LIKE '%is_soft_deleted = true%'             AS sets_soft_deleted,
  pg_get_functiondef(p.oid) LIKE '%deleted_by      = v_uid%'             AS deleted_by_is_caller,
  pg_get_functiondef(p.oid) LIKE '%deletion_reason = COALESCE(NULLIF(btrim(p_reason)%' AS reason_from_param,
  pg_get_functiondef(p.oid) ~* 'delete\s+from'                          AS has_physical_delete_should_be_f,
  pg_get_functiondef(p.oid) LIKE '%''draft''::public.test_status%'        AS draft_only,
  pg_get_functiondef(p.oid) LIKE '%created_by IS DISTINCT FROM v_uid%'   AS owner_only,
  pg_get_functiondef(p.oid) LIKE '%TEST_ALREADY_DELETED%'                AS rejects_repeat
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_delete_test';
-- expect: t | t | t | f | t | t | t

-- 9. RLS still enabled on tests (and untouched policies)
SELECT c.relname, c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'tests';
SELECT policyname, cmd FROM pg_policies WHERE schemaname = 'public' AND tablename = 'tests' ORDER BY 1;
-- expect: t; same policy list as before the migration

-- 10. no data modified
SELECT count(*) AS soft_deleted_tests_after FROM public.tests WHERE is_soft_deleted = true;
-- expect: equal to soft_deleted_tests_before

-- Behavioural (as the creator; use one of YOUR OWN throwaway drafts):
--   SELECT public.rpc_delete_test('<draft-uuid>');                       -- {"test_id":..,"deleted":true}
--   SELECT id, status, is_soft_deleted, deleted_at, deleted_by, deletion_reason
--     FROM public.tests WHERE id = '<draft-uuid>';                        -- status still draft, flags set
--   SELECT public.rpc_delete_test('<draft-uuid>');                       -- TEST_ALREADY_DELETED
--   SELECT public.rpc_delete_test('<published-uuid>');                   -- TEST_NOT_DRAFT
--   (as another user) SELECT public.rpc_delete_test('<draft-uuid-2>');   -- PERMISSION_DENIED
