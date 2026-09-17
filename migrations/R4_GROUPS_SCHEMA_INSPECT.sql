-- ============================================================
-- R4 D — READ-ONLY live inspection of public.groups / public.group_members
-- ONE statement → ONE result set (the SQL Editor only shows the last
-- statement's output, which is why a multi-query run showed just a count).
-- Copy the whole grid back. Nothing here writes.
-- ============================================================
WITH
cols AS (
  SELECT 'column' AS section, table_name AS object, ordinal_position AS ord,
         column_name AS name,
         format('%s | udt=%s | nullable=%s | default=%s', data_type, udt_name, is_nullable, coalesce(column_default, '-')) AS detail
  FROM information_schema.columns
  WHERE table_schema = 'public' AND table_name IN ('groups', 'group_members')
),
cons AS (
  SELECT 'constraint' AS section, conrelid::regclass::text AS object, 0 AS ord,
         conname AS name,
         format('%s | %s', contype, pg_get_constraintdef(oid)) AS detail
  FROM pg_constraint
  WHERE conrelid IN ('public.groups'::regclass, 'public.group_members'::regclass)
),
refs AS (
  SELECT 'fk_referencing_groups' AS section, conrelid::regclass::text AS object, 0 AS ord,
         conname AS name, pg_get_constraintdef(oid) AS detail
  FROM pg_constraint
  WHERE contype = 'f' AND confrelid = 'public.groups'::regclass
),
rls AS (
  SELECT 'rls' AS section, c.relname AS object, 0 AS ord, 'rls_enabled' AS name,
         format('enabled=%s | forced=%s', c.relrowsecurity, c.relforcerowsecurity) AS detail
  FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relname IN ('groups', 'group_members')
),
pol AS (
  SELECT 'policy' AS section, tablename AS object, 0 AS ord, policyname AS name,
         format('cmd=%s | roles=%s | permissive=%s | USING: %s | WITH CHECK: %s',
                cmd, roles::text, permissive, coalesce(qual, '-'), coalesce(with_check, '-')) AS detail
  FROM pg_policies
  WHERE schemaname = 'public' AND tablename IN ('groups', 'group_members')
),
grants AS (
  SELECT 'table_grant' AS section, table_name AS object, 0 AS ord, grantee AS name, privilege_type AS detail
  FROM information_schema.role_table_grants
  WHERE table_schema = 'public' AND table_name IN ('groups', 'group_members')
    AND grantee IN ('anon', 'authenticated')
),
funcs AS (
  SELECT 'function' AS section, 'public' AS object, 0 AS ord,
         p.proname || '(' || pg_get_function_arguments(p.oid) || ')' AS name,
         format('returns %s | definer=%s | config=%s | vol=%s',
                pg_get_function_result(p.oid), p.prosecdef, coalesce(p.proconfig::text, '-'), p.provolatile) AS detail
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND (p.proname ILIKE '%group%' OR p.proname ILIKE '%member%' OR p.proname ILIKE '%permission%')
),
bodies AS (
  SELECT 'function_body' AS section, 'public' AS object, 0 AS ord, p.proname AS name,
         pg_get_functiondef(p.oid) AS detail
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname IN ('fn_is_member', 'fn_has_permission', 'fn_can_access_test')
),
enums AS (
  SELECT 'enum' AS section, t.typname AS object, e.enumsortorder::int AS ord, e.enumlabel AS name, '' AS detail
  FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid
  WHERE t.typname IN ('app_permission', 'group_role', 'member_role')
),
counts AS (
  SELECT 'row_count' AS section, 'groups' AS object, 0 AS ord, 'rows' AS name, (SELECT count(*) FROM public.groups)::text AS detail
  UNION ALL
  SELECT 'row_count', 'group_members', 0, 'rows', (SELECT count(*) FROM public.group_members)::text
)
SELECT section, object, name, detail
FROM (
  SELECT * FROM cols UNION ALL SELECT * FROM cons UNION ALL SELECT * FROM refs
  UNION ALL SELECT * FROM rls UNION ALL SELECT * FROM pol UNION ALL SELECT * FROM grants
  UNION ALL SELECT * FROM funcs UNION ALL SELECT * FROM bodies UNION ALL SELECT * FROM enums
  UNION ALL SELECT * FROM counts
) x
ORDER BY CASE section
           WHEN 'column' THEN 1 WHEN 'constraint' THEN 2 WHEN 'fk_referencing_groups' THEN 3
           WHEN 'rls' THEN 4 WHEN 'policy' THEN 5 WHEN 'table_grant' THEN 6
           WHEN 'function' THEN 7 WHEN 'function_body' THEN 8 WHEN 'enum' THEN 9 ELSE 10 END,
         object, ord, name;
