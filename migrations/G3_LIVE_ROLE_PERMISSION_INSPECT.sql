-- ============================================================
-- G3 — READ-ONLY live role/permission audit (NOT a migration; nothing writes)
-- ONE statement -> ONE grid. Copy the whole grid back.
-- It answers, from the live database only:
--   * every app_permission / group_role value
--   * role_permissions: columns, PK, RLS, policies, and the actual rows
--     (which permission each role holds, per group)
--   * group_members: columns, RLS, every policy (esp. UPDATE "role changes"),
--     and whether trg_owner_guard / trg_role_changed_system exist
--   * fn_has_permission / fn_get_group_role / fn_is_member /
--     fn_get_group_permissions: signature, return, definer, config, volatility,
--     grants, and the owner-bypass text in the body
--   * any function that looks like a role-management RPC
--   * groups UPDATE/DELETE policies (permission-dependent)
--   * a self-update test: does the current session's own membership row pass
--     the UPDATE policy USING clause? (evaluated read-only)
-- ============================================================
WITH enums AS (
  SELECT 'enum' AS section, t.typname AS object, e.enumlabel AS name,
         'order=' || e.enumsortorder::text AS detail
  FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid
  WHERE t.typname IN ('group_role','app_permission')
),
cols AS (
  SELECT 'column', c.table_name, c.column_name,
         format('%s | udt=%s | null=%s | default=%s', c.data_type, c.udt_name, c.is_nullable, coalesce(c.column_default,'-'))
  FROM information_schema.columns c
  WHERE c.table_schema='public' AND c.table_name IN ('role_permissions','group_members')
),
cons AS (
  SELECT 'constraint', k.conrelid::regclass::text, k.conname, format('%s | %s', k.contype, pg_get_constraintdef(k.oid))
  FROM pg_constraint k
  WHERE k.conrelid IN ('public.role_permissions'::regclass,'public.group_members'::regclass)
),
rls AS (
  SELECT 'rls', cl.relname, 'rls_enabled', format('enabled=%s | forced=%s', cl.relrowsecurity, cl.relforcerowsecurity)
  FROM pg_class cl JOIN pg_namespace n ON n.oid=cl.relnamespace
  WHERE n.nspname='public' AND cl.relname IN ('role_permissions','group_members','groups')
),
pol AS (
  SELECT 'policy', p.tablename, p.policyname,
         format('cmd=%s | roles=%s | USING %s | CHECK %s', p.cmd, p.roles::text, coalesce(p.qual,'-'), coalesce(p.with_check,'-'))
  FROM pg_policies p
  WHERE p.schemaname='public' AND p.tablename IN ('role_permissions','group_members','groups')
),
trg AS (
  SELECT 'trigger', c.relname, t.tgname,
         format('enabled=%s | %s | fn=%s', t.tgenabled, pg_get_triggerdef(t.oid), p.proname)
  FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_proc p ON p.oid=t.tgfoid
  WHERE NOT t.tgisinternal AND c.relname IN ('group_members','role_permissions','groups')
),
fns AS (
  SELECT 'function', p.proname, pg_get_function_identity_arguments(p.oid),
         format('returns=%s | definer=%s | config=%s | vol=%s | grants=%s | owner_bypass=%s | self_ref=%s',
                pg_get_function_result(p.oid), p.prosecdef, coalesce(p.proconfig::text,'-'),
                CASE p.provolatile WHEN 'i' THEN 'immutable' WHEN 's' THEN 'stable' ELSE 'volatile' END,
                coalesce((SELECT string_agg(DISTINCT rp.grantee, ',') FROM information_schema.routine_privileges rp
                          WHERE rp.specific_schema='public' AND rp.specific_name = p.proname || '_' || p.oid), '-'),
                pg_get_functiondef(p.oid) ~ '''owner''',
                pg_get_functiondef(p.oid) ~ 'auth\.uid')
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public'
    AND (p.proname IN ('fn_has_permission','fn_get_group_role','fn_is_member','fn_get_group_permissions',
                       'fn_prevent_owner_removal','trg_role_changed_system')
         OR p.proname ILIKE '%role%' OR p.proname ILIKE '%permission%' OR p.proname ILIKE '%promot%')
),
rows_rp AS (
  SELECT 'role_permissions_rows', rp.role::text, rp.permission::text,
         'groups=' || count(*)::text || ' of ' || (SELECT count(*) FROM public.groups)::text
  FROM public.role_permissions rp
  GROUP BY rp.role, rp.permission
),
rows_gm AS (
  SELECT 'group_members_rows', gm.role::text, 'count', count(*)::text
  FROM public.group_members gm GROUP BY gm.role
),
owners AS (
  SELECT 'owner_integrity', 'groups', 'owner_rows_per_group',
         format('groups=%s | with_owner_row=%s | multi_owner=%s | owner_row_mismatch=%s',
           (SELECT count(*) FROM public.groups),
           (SELECT count(DISTINCT group_id) FROM public.group_members WHERE role='owner'),
           (SELECT count(*) FROM (SELECT group_id FROM public.group_members WHERE role='owner' GROUP BY group_id HAVING count(*)>1) x),
           (SELECT count(*) FROM public.groups g LEFT JOIN public.group_members gm ON gm.group_id=g.id AND gm.user_id=g.owner_id AND gm.role='owner' WHERE gm.user_id IS NULL))
),
selfcheck AS (
  SELECT 'self_update_check', 'group_members', 'my_rows_passing_update_using',
         'uid=' || coalesce(auth.uid()::text,'NULL (run as a user, not as postgres, to test)') ||
         ' | rows=' || (SELECT count(*) FROM public.group_members gm
                        WHERE gm.user_id = auth.uid()
                          AND (public.fn_has_permission(gm.group_id, auth.uid(), 'MANAGE_ROLES') OR gm.user_id = auth.uid()))::text
)
SELECT section, object, name, detail FROM (
  SELECT * FROM enums UNION ALL SELECT * FROM cols UNION ALL SELECT * FROM cons
  UNION ALL SELECT * FROM rls UNION ALL SELECT * FROM pol UNION ALL SELECT * FROM trg
  UNION ALL SELECT * FROM fns UNION ALL SELECT * FROM rows_rp UNION ALL SELECT * FROM rows_gm
  UNION ALL SELECT * FROM owners UNION ALL SELECT * FROM selfcheck
) x
ORDER BY CASE section WHEN 'enum' THEN 1 WHEN 'column' THEN 2 WHEN 'constraint' THEN 3 WHEN 'rls' THEN 4
                      WHEN 'policy' THEN 5 WHEN 'trigger' THEN 6 WHEN 'function' THEN 7
                      WHEN 'role_permissions_rows' THEN 8 WHEN 'group_members_rows' THEN 9
                      WHEN 'owner_integrity' THEN 10 ELSE 11 END, object, name;
