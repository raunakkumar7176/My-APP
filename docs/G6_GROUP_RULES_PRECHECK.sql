-- ============================================================
-- G6 — PRE-CHECK (read-only). Run in the Supabase SQL Editor BEFORE
-- migrations/G6_GROUP_RULES.sql. Two statements; paste the whole file.
-- ============================================================
-- Statement 1 — dependencies the migration relies on. Expected (all live-verified in G0/G3):
--   groups_table=true | fn_is_member=true | fn_has_permission=true |
--   fn_get_group_role=true | group_settings_perm=true |
--   definer_fns=3 (all three SECURITY DEFINER, so no RLS recursion)
-- If any is false the migration must NOT be run — stop and report.
-- ------------------------------------------------------------
SELECT
  to_regclass('public.groups') IS NOT NULL AS groups_table,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'fn_is_member' AND p.pronargs = 2) AS fn_is_member,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'fn_has_permission' AND p.pronargs = 3) AS fn_has_permission,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'fn_get_group_role' AND p.pronargs = 2) AS fn_get_group_role,
  EXISTS (SELECT 1 FROM pg_enum e JOIN pg_type t ON t.oid = e.enumtypid
          WHERE t.typname = 'app_permission' AND e.enumlabel = 'GROUP_SETTINGS') AS group_settings_perm,
  (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('fn_is_member', 'fn_has_permission', 'fn_get_group_role')
       AND p.prosecdef) AS definer_fns;

-- ------------------------------------------------------------
-- Statement 2 — nothing G6 creates exists yet. Expected:
--   table_exists=false | trigger_fn_exists=false | trigger_exists=false | policy_count=0
-- (true/non-zero means a previous partial run — the migration is idempotent
--  and may still be applied, but record what was there first.)
-- ------------------------------------------------------------
SELECT
  to_regclass('public.group_rules') IS NOT NULL AS table_exists,
  EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
          WHERE n.nspname = 'public' AND p.proname = 'fn_touch_group_rule_updated_at') AS trigger_fn_exists,
  EXISTS (SELECT 1 FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid
          JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'public' AND c.relname = 'group_rules'
            AND t.tgname = 'trg_touch_group_rule') AS trigger_exists,
  (SELECT count(*) FROM pg_policies p
     WHERE p.schemaname = 'public' AND p.tablename = 'group_rules') AS policy_count;
