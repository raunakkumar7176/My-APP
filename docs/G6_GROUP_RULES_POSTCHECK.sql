-- ============================================================
-- G6 — POST-CHECK (read-only). Run in the Supabase SQL Editor AFTER
-- migrations/G6_GROUP_RULES.sql. Three statements; paste the whole file
-- and paste all three result grids back into the G6 report.
-- ============================================================
-- Statement 1 — structure + grants. Expected:
--   rls_enabled=true | policies=4 | fk_to_groups=true | index_present=true |
--   trigger_present=true | anon_privileges=0 |
--   authenticated_privileges=DELETE,INSERT,SELECT,UPDATE |
--   rule_text_not_null=true | check_present=true | trigger_fn_search_path={search_path=}
-- ------------------------------------------------------------
SELECT
  c.relrowsecurity AS rls_enabled,
  (SELECT count(*) FROM pg_policies p
     WHERE p.schemaname = 'public' AND p.tablename = 'group_rules') AS policies,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'f'
            AND k.confrelid = 'public.groups'::regclass) AS fk_to_groups,
  EXISTS (SELECT 1 FROM pg_indexes i WHERE i.schemaname = 'public' AND i.tablename = 'group_rules'
            AND i.indexname = 'idx_group_rules_group_position') AS index_present,
  EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid = c.oid AND t.tgname = 'trg_touch_group_rule') AS trigger_present,
  (SELECT count(*) FROM information_schema.role_table_grants g
     WHERE g.table_schema = 'public' AND g.table_name = 'group_rules' AND g.grantee = 'anon') AS anon_privileges,
  (SELECT string_agg(g.privilege_type, ',' ORDER BY g.privilege_type)
     FROM information_schema.role_table_grants g
     WHERE g.table_schema = 'public' AND g.table_name = 'group_rules' AND g.grantee = 'authenticated') AS authenticated_privileges,
  (SELECT a.attnotnull FROM pg_attribute a
     WHERE a.attrelid = c.oid AND a.attname = 'rule_text') AS rule_text_not_null,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = c.oid AND k.contype = 'c'
            AND pg_get_constraintdef(k.oid) ILIKE '%rule_text%') AS check_present,
  (SELECT p.proconfig::text FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public' AND p.proname = 'fn_touch_group_rule_updated_at') AS trigger_fn_search_path
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname = 'group_rules';

-- ------------------------------------------------------------
-- Statement 2 — the policy text as installed. Expected 4 rows, roles {authenticated}:
--   members read rules            SELECT  qual: fn_is_member(group_id, auth.uid())
--   settings holders insert rules INSERT  with_check: fn_has_permission(...,'GROUP_SETTINGS') OR fn_get_group_role(...) = 'owner'
--   settings holders update rules UPDATE  qual AND with_check: same expression
--   settings holders delete rules DELETE  qual: same expression
-- ------------------------------------------------------------
SELECT policyname, cmd, roles, permissive, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'group_rules'
ORDER BY cmd;

-- ------------------------------------------------------------
-- Statement 3 — column shape the Flutter model parses. Expected 6 rows:
--   id uuid NO | group_id uuid NO | rule_text text NO | position integer NO |
--   created_at timestamptz NO | updated_at timestamptz NO
-- ------------------------------------------------------------
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'group_rules'
ORDER BY ordinal_position;
