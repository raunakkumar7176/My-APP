-- ============================================================
-- G1 — READ-ONLY live contract inspection (NOT a migration; nothing writes)
-- ONE statement -> ONE grid. The SQL Editor shows only the last statement's
-- result, so everything is folded into a single SELECT. Copy the grid back.
-- Expected (from the migration set that built this database, 0033/0034):
--   fn_create_group(p_name text, p_description text, p_privacy text DEFAULT 'public') -> uuid, definer, search_path=public, volatile, EXECUTE: authenticated (anon revoked)
--   fn_create_group(p_name text, p_description text) -> uuid (2-arg overload, sql)
--   fn_join_group(p_invite_code text) -> uuid, definer, search_path=public, volatile, EXECUTE: authenticated (anon revoked)
--   fn_has_permission(p_group uuid, p_user uuid, p_perm app_permission) -> boolean, definer, search_path=public, stable, EXECUTE: authenticated (anon revoked)
--   fn_is_member(p_group uuid, p_user uuid) -> boolean, definer, stable, EXECUTE: authenticated (+anon)
--   rpc_get_user_groups() -> TABLE(id, name, owner_id, logo_url, created_at, member_count, user_role)
-- ============================================================
WITH fns AS (
  SELECT 'function' AS section,
         p.proname AS object,
         pg_get_function_identity_arguments(p.oid) AS name,
         format('args=[%s] | returns=%s | definer=%s | config=%s | vol=%s | lang=%s | grants=%s | body_refs=%s',
                pg_get_function_arguments(p.oid),
                pg_get_function_result(p.oid),
                p.prosecdef,
                coalesce(p.proconfig::text, '-'),
                CASE p.provolatile WHEN 'i' THEN 'immutable' WHEN 's' THEN 'stable' ELSE 'volatile' END,
                l.lanname,
                coalesce((SELECT string_agg(rp.grantee || ':' || rp.privilege_type, ', ' ORDER BY rp.grantee)
                          FROM information_schema.routine_privileges rp
                          WHERE rp.specific_schema = 'public' AND rp.specific_name = p.proname || '_' || p.oid), '-'),
                array_to_string(ARRAY[
                  CASE WHEN pg_get_functiondef(p.oid) ~ 'group_members'     THEN 'group_members' END,
                  CASE WHEN pg_get_functiondef(p.oid) ~ 'role_permissions'  THEN 'role_permissions' END,
                  CASE WHEN pg_get_functiondef(p.oid) ~ 'group_join_requests' THEN 'group_join_requests' END,
                  CASE WHEN pg_get_functiondef(p.oid) ~ 'fn_ensure_profile' THEN 'fn_ensure_profile' END,
                  CASE WHEN pg_get_functiondef(p.oid) ~ 'invite_code'       THEN 'invite_code' END,
                  CASE WHEN pg_get_functiondef(p.oid) ~ '''owner'''         THEN 'owner-bypass' END
                ], ',')
         ) AS detail
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  JOIN pg_language l ON l.oid = p.prolang
  WHERE n.nspname = 'public'
    AND p.proname IN ('fn_create_group','fn_join_group','fn_has_permission','fn_is_member',
                      'fn_get_group_role','rpc_get_user_groups')
),
cols AS (
  SELECT 'column', c.table_name, c.column_name,
         format('%s | udt=%s | null=%s | default=%s', c.data_type, c.udt_name, c.is_nullable, coalesce(c.column_default,'-'))
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name IN ('groups','group_members','profiles','role_permissions')
),
cons AS (
  SELECT 'constraint', k.conrelid::regclass::text, k.conname,
         format('%s | %s', k.contype, pg_get_constraintdef(k.oid))
  FROM pg_constraint k
  WHERE k.conrelid IN ('public.groups'::regclass,'public.group_members'::regclass,
                       'public.profiles'::regclass,'public.role_permissions'::regclass)
),
pol AS (
  SELECT 'policy', p.tablename, p.policyname,
         format('cmd=%s | roles=%s | USING %s | CHECK %s', p.cmd, p.roles::text,
                coalesce(p.qual,'-'), coalesce(p.with_check,'-'))
  FROM pg_policies p
  WHERE p.schemaname = 'public'
    AND p.tablename IN ('groups','group_members','profiles','role_permissions')
),
rls AS (
  SELECT 'rls', cl.relname, 'rls_enabled',
         format('enabled=%s | forced=%s', cl.relrowsecurity, cl.relforcerowsecurity)
  FROM pg_class cl JOIN pg_namespace n ON n.oid = cl.relnamespace
  WHERE n.nspname = 'public'
    AND cl.relname IN ('groups','group_members','profiles','role_permissions')
),
tgrants AS (
  SELECT 'table_grant', g.table_name, g.grantee, g.privilege_type
  FROM information_schema.role_table_grants g
  WHERE g.table_schema = 'public'
    AND g.table_name IN ('groups','group_members','profiles','role_permissions')
    AND g.grantee IN ('anon','authenticated')
),
enums AS (
  SELECT 'enum', t.typname, e.enumlabel, e.enumsortorder::text
  FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid
  WHERE t.typname IN ('group_role','app_permission')
)
SELECT section, object, name, detail FROM (
  SELECT * FROM fns UNION ALL SELECT * FROM cols UNION ALL SELECT * FROM cons
  UNION ALL SELECT * FROM rls UNION ALL SELECT * FROM pol UNION ALL SELECT * FROM tgrants
  UNION ALL SELECT * FROM enums
) x
ORDER BY CASE section WHEN 'function' THEN 1 WHEN 'enum' THEN 2 WHEN 'column' THEN 3
                      WHEN 'constraint' THEN 4 WHEN 'rls' THEN 5 WHEN 'policy' THEN 6 ELSE 7 END,
         object, name;
