-- ============================================================
-- G10.2 — PRE-CHECK (read-only). Run BEFORE migrations/G10_2_fix_group_edit_test_policy.sql.
-- ============================================================
-- Statement 1 — the UPDATE policies as installed. Expected (live 2026-09-19):
--   "group edit test"              USING/CHECK fn_has_permission(group_id, auth.uid(), 'EDIT_TEST')
--   "standalone owner update test" USING/CHECK group_id IS NULL AND created_by = auth.uid()
-- Neither restricts columns → B2. If they differ, STOP and re-audit.
SELECT policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'tests' AND cmd IN ('UPDATE', 'ALL')
ORDER BY policyname;

-- Statement 2 — who owns the lifecycle RPCs (the guard exempts the owner
-- role, so every SECURITY DEFINER path keeps working). Expected: all rows
-- owner = postgres, prosecdef = true.
SELECT p.proname, r.rolname AS owner, p.prosecdef, p.proconfig
FROM pg_proc p
JOIN pg_roles r ON r.oid = p.proowner
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('rpc_update_test', 'rpc_publish_test', 'rpc_create_test',
                    'rpc_delete_test', 'fn_soft_delete_test', 'fn_sweep_deadlines')
ORDER BY p.proname;

-- Statement 3 — nothing G10.2 creates exists yet. Expected: both false.
SELECT
  EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid = 'public.tests'::regclass
            AND tgname = 'trg_guard_test_lifecycle') AS trigger_exists,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'fn_guard_test_lifecycle') AS fn_exists;

-- Statement 4 — existing triggers on tests (must all remain after the fix).
-- Expected: trg_group_test_notify, trg_set_access_code, trg_set_join_code, trg_test_chat_pin
SELECT tgname, tgenabled
FROM pg_trigger
WHERE tgrelid = 'public.tests'::regclass AND NOT tgisinternal
ORDER BY tgname;
