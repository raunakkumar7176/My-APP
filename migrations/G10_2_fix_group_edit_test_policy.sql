-- ============================================================
-- G10.2 — LIVE DEFECT FIX (PROPOSED — NOT APPLIED): lifecycle / ownership
--         guard for direct UPDATEs on public.tests  (B2 of the G10 audit)
-- ============================================================
-- Live finding (2026-09-19, rolled-back transaction): the UPDATE policies
--   "group edit test"            USING/CHECK fn_has_permission(group_id, uid, 'EDIT_TEST')
--   "standalone owner update test" USING/CHECK group_id IS NULL AND created_by = uid
-- restrict WHO may update a row but not WHICH columns. A leader with
-- EDIT_TEST set status = 'published' on another creator's draft by direct
-- UPDATE, skipping every rpc_publish_test validation; created_by, group_id
-- and is_soft_deleted are equally writable.
--
-- Design chosen: Option B — a BEFORE UPDATE guard trigger (least privilege,
-- additive). Option A (narrowing the policy) cannot express "same row, but
-- only these columns" in RLS and would remove the whole direct-edit
-- capability. The guard:
--   * applies only when the UPDATE runs as a client role (authenticated /
--     anon). The SECURITY DEFINER RPCs (rpc_update_test, rpc_publish_test,
--     rpc_delete_test, fn_soft_delete_test), the cron sweep and service_role
--     run as the function/table owner and are untouched;
--   * blocks changes to status, created_by, group_id, test_mode,
--     is_soft_deleted, deleted_at, deleted_by, deletion_reason, archived_at;
--   * re-applies the live timing rule (ends_at > starts_at) to direct
--     window edits, so "schedule validation" cannot be bypassed;
--   * leaves content edits (title, description, duration, marks, window,
--     config, settings, codes, participants, late join) exactly as today.
-- PRODUCT IMPACT (decision required before applying): the legacy Next.js web
-- app (My-Prepration/src/app/(app)/tests/[id]/lifecycle-actions.ts) sets
-- status = 'ready' / 'scheduled' / 'live' / 'cancelled' / 'archived' by
-- direct UPDATE as the signed-in user. With this guard those actions raise
-- LIFECYCLE_LOCKED. The Flutter app never issues such UPDATEs (all
-- transitions go through the RPCs) and is unaffected.
-- Rollback: DROP TRIGGER trg_guard_test_lifecycle ON public.tests;
--           DROP FUNCTION public.fn_guard_test_lifecycle();
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_guard_test_lifecycle()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO ''
AS $$
BEGIN
  -- Client roles only. Definer RPCs / cron / service_role run as their
  -- owner and keep full control of the lifecycle.
  IF current_user NOT IN ('authenticated', 'anon') THEN
    RETURN NEW;
  END IF;

  IF NEW.status IS DISTINCT FROM OLD.status THEN
    RAISE EXCEPTION 'LIFECYCLE_LOCKED: status can only change through rpc_publish_test, rpc_delete_test or fn_soft_delete_test';
  END IF;
  IF NEW.created_by IS DISTINCT FROM OLD.created_by THEN
    RAISE EXCEPTION 'OWNERSHIP_LOCKED: created_by cannot be changed';
  END IF;
  IF NEW.group_id IS DISTINCT FROM OLD.group_id
     OR NEW.test_mode IS DISTINCT FROM OLD.test_mode THEN
    RAISE EXCEPTION 'GROUP_LOCKED: group_id / test_mode cannot be changed after creation';
  END IF;
  IF NEW.is_soft_deleted IS DISTINCT FROM OLD.is_soft_deleted
     OR NEW.deleted_at IS DISTINCT FROM OLD.deleted_at
     OR NEW.deleted_by IS DISTINCT FROM OLD.deleted_by
     OR NEW.deletion_reason IS DISTINCT FROM OLD.deletion_reason
     OR NEW.archived_at IS DISTINCT FROM OLD.archived_at THEN
    RAISE EXCEPTION 'DELETE_LOCKED: use rpc_delete_test or fn_soft_delete_test';
  END IF;
  -- Same rule as public._fn_validate_test_timing (inlined: no EXECUTE
  -- dependency for client roles).
  IF (NEW.starts_at IS DISTINCT FROM OLD.starts_at OR NEW.ends_at IS DISTINCT FROM OLD.ends_at)
     AND NEW.starts_at IS NOT NULL AND NEW.ends_at IS NOT NULL
     AND NEW.ends_at <= NEW.starts_at THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: ends_at must be after starts_at';
  END IF;
  RETURN NEW;
END;
$$;

GRANT EXECUTE ON FUNCTION public.fn_guard_test_lifecycle() TO authenticated, anon, service_role;

DROP TRIGGER IF EXISTS trg_guard_test_lifecycle ON public.tests;
CREATE TRIGGER trg_guard_test_lifecycle
  BEFORE UPDATE ON public.tests
  FOR EACH ROW EXECUTE FUNCTION public.fn_guard_test_lifecycle();

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only; last statement)
-- Expected: trigger_present=true | fn_present=true | fn_search_path={search_path=}
-- ------------------------------------------------------------
SELECT
  EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.tests'::regclass
            AND t.tgname = 'trg_guard_test_lifecycle' AND t.tgenabled = 'O') AS trigger_present,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'fn_guard_test_lifecycle') AS fn_present,
  (SELECT p.proconfig::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_guard_test_lifecycle') AS fn_search_path;
