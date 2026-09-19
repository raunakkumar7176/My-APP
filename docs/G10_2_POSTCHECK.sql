-- ============================================================
-- G10.2 — POST-CHECK (read-only). Run AFTER migrations/G10_2_fix_group_edit_test_policy.sql.
-- ============================================================
-- Statement 1 — guard installed. Expected:
--   trigger_present=true | trigger_timing=BEFORE UPDATE | fn_present=true |
--   fn_search_path={search_path=} | fn_security_definer=false
SELECT
  EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = 'public.tests'::regclass
            AND t.tgname = 'trg_guard_test_lifecycle' AND t.tgenabled = 'O') AS trigger_present,
  (SELECT CASE WHEN (t.tgtype & 2) = 2 THEN 'BEFORE' ELSE 'AFTER' END || ' ' ||
          CASE WHEN (t.tgtype & 16) = 16 THEN 'UPDATE' ELSE '?' END
     FROM pg_trigger t WHERE t.tgrelid = 'public.tests'::regclass
      AND t.tgname = 'trg_guard_test_lifecycle') AS trigger_timing,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
            WHERE n.nspname = 'public' AND p.proname = 'fn_guard_test_lifecycle') AS fn_present,
  (SELECT p.proconfig::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_guard_test_lifecycle') AS fn_search_path,
  (SELECT p.prosecdef FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_guard_test_lifecycle') AS fn_security_definer;

-- Statement 2 — policies and grants untouched (the guard is additive).
-- Expected: the same two UPDATE policies as the pre-check.
SELECT policyname, cmd, roles, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'tests' AND cmd IN ('UPDATE', 'ALL')
ORDER BY policyname;

-- Statement 3 — the guard body references every locked column. Expected: all true.
SELECT
  p.prosrc LIKE '%NEW.status IS DISTINCT FROM OLD.status%' AS locks_status,
  p.prosrc LIKE '%NEW.created_by IS DISTINCT FROM OLD.created_by%' AS locks_created_by,
  p.prosrc LIKE '%NEW.group_id IS DISTINCT FROM OLD.group_id%' AS locks_group_id,
  p.prosrc LIKE '%NEW.is_soft_deleted IS DISTINCT FROM OLD.is_soft_deleted%' AS locks_soft_delete,
  p.prosrc LIKE '%NEW.ends_at <= NEW.starts_at%' AS validates_timing,
  p.prosrc LIKE '%current_user NOT IN (''authenticated'', ''anon'')%' AS exempts_owner_roles
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'fn_guard_test_lifecycle';

-- Statement 4 — all pre-existing triggers still present. Expected 5 rows
-- (the 4 from the pre-check + trg_guard_test_lifecycle).
SELECT tgname, tgenabled
FROM pg_trigger
WHERE tgrelid = 'public.tests'::regclass AND NOT tgisinternal
ORDER BY tgname;
