-- ============================================================
-- G4 — READ-ONLY live Members Hub audit (NOT a migration; nothing writes)
-- ONE statement -> ONE grid: section | object | name | detail.
-- Run in the Supabase SQL Editor and paste the whole grid back.
--
-- Covers: group_members (columns, constraints, RLS, policies, triggers with
-- timing/events, and the COMPLETE bodies of every trigger function attached),
-- the group_members.user_id -> profiles FK and profiles' readable policies,
-- group_join_requests and group_invitations (existence, columns, constraints,
-- RLS, policies, triggers, row counts by status), every function whose name
-- mentions member/join/invit/request/role/permission (signature, return,
-- definer, config, volatility, grants) plus the COMPLETE bodies of the
-- request/invitation functions, groups policies that gate member visibility,
-- realtime publication membership, and the G3 role-policy text (unchanged
-- check).
-- ============================================================
WITH tables_of_interest AS (
  SELECT unnest(ARRAY['group_members','group_join_requests','group_invitations',
                      'profiles','groups','role_permissions']) AS t
),
existence AS (
  SELECT 'exists' AS section, toi.t AS object, 'table' AS name,
         CASE WHEN c.oid IS NULL THEN 'NO' ELSE 'YES' END AS detail
  FROM tables_of_interest toi
  LEFT JOIN pg_class c ON c.relname = toi.t AND c.relkind = 'r'
  LEFT JOIN pg_namespace n ON n.oid = c.relnamespace AND n.nspname = 'public'
),
cols AS (
  SELECT 'column', c.table_name, lpad(c.ordinal_position::text, 2, '0') || ' ' || c.column_name,
         format('%s | udt=%s | null=%s | default=%s', c.data_type, c.udt_name, c.is_nullable, coalesce(c.column_default,'-'))
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name IN ('group_members','group_join_requests','group_invitations','profiles')
),
cons AS (
  SELECT 'constraint', k.conrelid::regclass::text, k.conname,
         format('%s | %s', k.contype, pg_get_constraintdef(k.oid))
  FROM pg_constraint k
  JOIN pg_class cl ON cl.oid = k.conrelid
  JOIN pg_namespace n ON n.oid = cl.relnamespace
  WHERE n.nspname = 'public'
    AND cl.relname IN ('group_members','group_join_requests','group_invitations','profiles')
),
rls AS (
  SELECT 'rls', cl.relname, 'rls_enabled',
         format('enabled=%s | forced=%s', cl.relrowsecurity, cl.relforcerowsecurity)
  FROM pg_class cl JOIN pg_namespace n ON n.oid = cl.relnamespace
  WHERE n.nspname = 'public'
    AND cl.relname IN ('group_members','group_join_requests','group_invitations','profiles','groups')
),
pol AS (
  SELECT 'policy', p.tablename, p.policyname,
         format('cmd=%s | permissive=%s | roles=%s | USING %s | CHECK %s',
                p.cmd, p.permissive, p.roles::text, coalesce(p.qual,'-'), coalesce(p.with_check,'-'))
  FROM pg_policies p
  WHERE p.schemaname = 'public'
    AND p.tablename IN ('group_members','group_join_requests','group_invitations','profiles','groups')
),
tgrants AS (
  SELECT 'table_grant', g.table_name, g.grantee, string_agg(g.privilege_type, ',' ORDER BY g.privilege_type)
  FROM information_schema.role_table_grants g
  WHERE g.table_schema = 'public'
    AND g.table_name IN ('group_members','group_join_requests','group_invitations','profiles')
    AND g.grantee IN ('anon','authenticated')
  GROUP BY g.table_name, g.grantee
),
trg AS (
  SELECT 'trigger', c.relname, t.tgname,
         format('enabled=%s | fn=%s | %s', t.tgenabled, p.proname, pg_get_triggerdef(t.oid))
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_proc p ON p.oid = t.tgfoid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE NOT t.tgisinternal AND n.nspname = 'public'
    AND c.relname IN ('group_members','group_join_requests','group_invitations','groups')
),
trigger_fn_bodies AS (
  -- COMPLETE live body of every function attached as a trigger to the tables above.
  SELECT DISTINCT 'trigger_fn_body', p.proname, 'body', pg_get_functiondef(p.oid)
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_proc p ON p.oid = t.tgfoid
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE NOT t.tgisinternal AND n.nspname = 'public'
    AND c.relname IN ('group_members','group_join_requests','group_invitations')
),
fns AS (
  SELECT 'function', p.proname, pg_get_function_identity_arguments(p.oid),
         format('returns=%s | definer=%s | config=%s | vol=%s | lang=%s | grants=%s',
                pg_get_function_result(p.oid), p.prosecdef, coalesce(p.proconfig::text,'-'),
                CASE p.provolatile WHEN 'i' THEN 'immutable' WHEN 's' THEN 'stable' ELSE 'volatile' END,
                l.lanname,
                coalesce((SELECT string_agg(DISTINCT rp.grantee, ',') FROM information_schema.routine_privileges rp
                          WHERE rp.specific_schema = 'public' AND rp.specific_name = p.proname || '_' || p.oid), '-'))
  FROM pg_proc p
  JOIN pg_namespace n ON n.oid = p.pronamespace
  JOIN pg_language l ON l.oid = p.prolang
  WHERE n.nspname = 'public'
    AND (p.proname ILIKE '%member%' OR p.proname ILIKE '%join%' OR p.proname ILIKE '%invit%'
         OR p.proname ILIKE '%request%' OR p.proname ILIKE '%role%' OR p.proname ILIKE '%permission%'
         OR p.proname ILIKE '%group%')
),
fn_bodies AS (
  -- COMPLETE live bodies of the request / invitation / membership functions G4 would call.
  SELECT 'function_body', p.proname, pg_get_function_identity_arguments(p.oid), pg_get_functiondef(p.oid)
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public'
    AND (p.proname ILIKE '%join_request%' OR p.proname ILIKE '%invitation%' OR p.proname ILIKE '%invite%'
         OR p.proname IN ('fn_join_group','fn_get_group_permissions','fn_get_group_role','fn_is_member','fn_has_permission'))
),
fk_profiles AS (
  SELECT 'fk_to_profiles', k.conrelid::regclass::text, k.conname, pg_get_constraintdef(k.oid)
  FROM pg_constraint k
  WHERE k.contype = 'f' AND k.confrelid = 'public.profiles'::regclass
    AND k.conrelid IN ('public.group_members'::regclass,
                       (SELECT oid FROM pg_class WHERE relname = 'group_join_requests' AND relnamespace = 'public'::regnamespace),
                       (SELECT oid FROM pg_class WHERE relname = 'group_invitations' AND relnamespace = 'public'::regnamespace))
),
realtime AS (
  SELECT 'realtime', pt.tablename, pt.pubname,
         'in publication | replica_identity=' ||
         (SELECT CASE c.relreplident WHEN 'd' THEN 'default' WHEN 'f' THEN 'full' WHEN 'i' THEN 'index' ELSE 'nothing' END
          FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
          WHERE n.nspname = 'public' AND c.relname = pt.tablename)
  FROM pg_publication_tables pt
  WHERE pt.schemaname = 'public'
    AND pt.tablename IN ('group_members','group_join_requests','group_invitations','profiles','groups')
),
counts_members AS (
  SELECT 'row_count', 'group_members', 'by_role:' || gm.role::text, count(*)::text
  FROM public.group_members gm GROUP BY gm.role
),
counts_requests AS (
  SELECT 'row_count', 'group_join_requests', 'by_status:' || r.status, count(*)::text
  FROM public.group_join_requests r GROUP BY r.status
),
counts_invites AS (
  SELECT 'row_count', 'group_invitations', 'by_status:' || i.status, count(*)::text
  FROM public.group_invitations i GROUP BY i.status
),
isolation AS (
  -- Membership isolation: any user present in more than one group (informational),
  -- and any join request / invitation whose group no longer exists (orphans).
  SELECT 'isolation', 'group_members', 'users_in_multiple_groups',
         (SELECT count(*) FROM (SELECT user_id FROM public.group_members GROUP BY user_id HAVING count(*) > 1) x)::text
  UNION ALL
  SELECT 'isolation', 'group_join_requests', 'pending_requests_from_existing_members',
         (SELECT count(*) FROM public.group_join_requests r
          JOIN public.group_members gm ON gm.group_id = r.group_id AND gm.user_id = r.user_id
          WHERE r.status = 'pending')::text
  UNION ALL
  SELECT 'isolation', 'group_invitations', 'pending_invitations_to_existing_members',
         (SELECT count(*) FROM public.group_invitations i
          JOIN public.group_members gm ON gm.group_id = i.group_id AND gm.user_id = i.invitee_id
          WHERE i.status = 'pending')::text
),
g3_check AS (
  SELECT 'g3_unchanged', 'group_members', 'role changes',
         coalesce((SELECT format('USING %s | CHECK %s', p.qual, p.with_check)
                   FROM pg_policies p WHERE p.schemaname = 'public' AND p.tablename = 'group_members'
                     AND p.policyname = 'role changes'), 'POLICY MISSING')
)
SELECT section, object, name, detail FROM (
  SELECT * FROM existence
  UNION ALL SELECT * FROM cols UNION ALL SELECT * FROM cons UNION ALL SELECT * FROM fk_profiles
  UNION ALL SELECT * FROM rls UNION ALL SELECT * FROM pol UNION ALL SELECT * FROM tgrants
  UNION ALL SELECT * FROM trg UNION ALL SELECT * FROM trigger_fn_bodies
  UNION ALL SELECT * FROM fns UNION ALL SELECT * FROM fn_bodies
  UNION ALL SELECT * FROM realtime
  UNION ALL SELECT * FROM counts_members UNION ALL SELECT * FROM counts_requests UNION ALL SELECT * FROM counts_invites
  UNION ALL SELECT * FROM isolation UNION ALL SELECT * FROM g3_check
) x
ORDER BY CASE section
           WHEN 'exists' THEN 1 WHEN 'column' THEN 2 WHEN 'constraint' THEN 3 WHEN 'fk_to_profiles' THEN 4
           WHEN 'rls' THEN 5 WHEN 'policy' THEN 6 WHEN 'table_grant' THEN 7 WHEN 'trigger' THEN 8
           WHEN 'trigger_fn_body' THEN 9 WHEN 'function' THEN 10 WHEN 'function_body' THEN 11
           WHEN 'realtime' THEN 12 WHEN 'row_count' THEN 13 WHEN 'isolation' THEN 14 ELSE 15 END,
         object, name;
