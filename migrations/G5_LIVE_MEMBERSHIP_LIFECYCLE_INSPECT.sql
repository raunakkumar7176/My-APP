-- ============================================================
-- G5 — READ-ONLY live membership-lifecycle audit (NOT a migration; nothing writes)
-- ONE statement -> ONE grid: section | object | name | detail.
-- Run in the Supabase SQL Editor and paste the whole grid back.
--
-- Covers: groups (invite_code / privacy columns + constraints), group_members,
-- group_invitations, group_join_requests, group_mutes — existence, columns,
-- constraints/FKs, RLS, every policy, grants, triggers with timing, and the
-- COMPLETE live bodies of every attached trigger function; every function whose
-- name mentions join / invit / request / member / mute / code, with COMPLETE
-- bodies for the lifecycle ones (fn_join_group, fn_accept/decline_group_invitation,
-- fn_approve_group_join_request, fn_reset_group_invite, any cancel/expire/withdraw);
-- realtime publication; row counts by status; isolation / stale-state probes.
-- ============================================================
WITH toi AS (
  SELECT unnest(ARRAY['groups','group_members','group_invitations','group_join_requests','group_mutes']) AS t
),
existence AS (
  SELECT 'exists' AS section, toi.t AS object, 'table' AS name,
         CASE WHEN c.oid IS NULL THEN 'NO' ELSE 'YES' END AS detail
  FROM toi
  LEFT JOIN pg_class c ON c.relname = toi.t AND c.relkind = 'r'
       AND c.relnamespace = 'public'::regnamespace
),
cols AS (
  SELECT 'column', c.table_name, lpad(c.ordinal_position::text, 2, '0') || ' ' || c.column_name,
         format('%s | udt=%s | null=%s | default=%s', c.data_type, c.udt_name, c.is_nullable, coalesce(c.column_default,'-'))
  FROM information_schema.columns c
  WHERE c.table_schema = 'public'
    AND c.table_name IN ('groups','group_members','group_invitations','group_join_requests','group_mutes')
),
cons AS (
  SELECT 'constraint', k.conrelid::regclass::text, k.conname,
         format('%s | %s', k.contype, pg_get_constraintdef(k.oid))
  FROM pg_constraint k
  JOIN pg_class cl ON cl.oid = k.conrelid
  WHERE cl.relnamespace = 'public'::regnamespace
    AND cl.relname IN ('groups','group_members','group_invitations','group_join_requests','group_mutes')
),
rls AS (
  SELECT 'rls', cl.relname, 'rls_enabled',
         format('enabled=%s | forced=%s', cl.relrowsecurity, cl.relforcerowsecurity)
  FROM pg_class cl
  WHERE cl.relnamespace = 'public'::regnamespace
    AND cl.relname IN ('groups','group_members','group_invitations','group_join_requests','group_mutes')
),
pol AS (
  SELECT 'policy', p.tablename, p.policyname,
         format('cmd=%s | permissive=%s | roles=%s | USING %s | CHECK %s',
                p.cmd, p.permissive, p.roles::text, coalesce(p.qual,'-'), coalesce(p.with_check,'-'))
  FROM pg_policies p
  WHERE p.schemaname = 'public'
    AND p.tablename IN ('groups','group_members','group_invitations','group_join_requests','group_mutes')
),
tgrants AS (
  SELECT 'table_grant', g.table_name, g.grantee, string_agg(g.privilege_type, ',' ORDER BY g.privilege_type)
  FROM information_schema.role_table_grants g
  WHERE g.table_schema = 'public'
    AND g.table_name IN ('groups','group_members','group_invitations','group_join_requests','group_mutes')
    AND g.grantee IN ('anon','authenticated')
  GROUP BY g.table_name, g.grantee
),
trg AS (
  SELECT 'trigger', c.relname, t.tgname,
         format('enabled=%s | fn=%s | %s', t.tgenabled, p.proname, pg_get_triggerdef(t.oid))
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_proc p ON p.oid = t.tgfoid
  WHERE NOT t.tgisinternal AND c.relnamespace = 'public'::regnamespace
    AND c.relname IN ('groups','group_members','group_invitations','group_join_requests','group_mutes')
),
trigger_fn_bodies AS (
  SELECT DISTINCT 'trigger_fn_body', p.proname, 'body', pg_get_functiondef(p.oid)
  FROM pg_trigger t
  JOIN pg_class c ON c.oid = t.tgrelid
  JOIN pg_proc p ON p.oid = t.tgfoid
  WHERE NOT t.tgisinternal AND c.relnamespace = 'public'::regnamespace
    AND c.relname IN ('groups','group_members','group_invitations','group_join_requests','group_mutes')
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
  JOIN pg_language l ON l.oid = p.prolang
  WHERE p.pronamespace = 'public'::regnamespace
    AND (p.proname ILIKE '%join%' OR p.proname ILIKE '%invit%' OR p.proname ILIKE '%request%'
         OR p.proname ILIKE '%member%' OR p.proname ILIKE '%mute%' OR p.proname ILIKE '%code%'
         OR p.proname ILIKE '%group%')
),
fn_bodies AS (
  SELECT 'function_body', p.proname, pg_get_function_identity_arguments(p.oid), pg_get_functiondef(p.oid)
  FROM pg_proc p
  WHERE p.pronamespace = 'public'::regnamespace
    AND (p.proname ILIKE '%join_request%' OR p.proname ILIKE '%group_invit%' OR p.proname ILIKE '%invite%'
         OR p.proname ILIKE '%join_code%' OR p.proname IN ('fn_join_group','fn_is_member','fn_has_permission','fn_get_group_role'))
),
realtime AS (
  SELECT 'realtime', pt.tablename, pt.pubname,
         'in publication | replica_identity=' ||
         (SELECT CASE c.relreplident WHEN 'd' THEN 'default' WHEN 'f' THEN 'full' WHEN 'i' THEN 'index' ELSE 'nothing' END
          FROM pg_class c WHERE c.relnamespace = 'public'::regnamespace AND c.relname = pt.tablename)
  FROM pg_publication_tables pt
  WHERE pt.schemaname = 'public'
    AND pt.tablename IN ('groups','group_members','group_invitations','group_join_requests','group_mutes')
),
counts AS (
  SELECT 'row_count', 'groups', 'by_privacy:' || g.privacy, count(*)::text FROM public.groups g GROUP BY g.privacy
  UNION ALL
  SELECT 'row_count', 'group_members', 'by_role:' || gm.role::text, count(*)::text FROM public.group_members gm GROUP BY gm.role
  UNION ALL
  SELECT 'row_count', 'group_join_requests', 'by_status:' || r.status, count(*)::text FROM public.group_join_requests r GROUP BY r.status
  UNION ALL
  SELECT 'row_count', 'group_invitations', 'by_status:' || i.status, count(*)::text FROM public.group_invitations i GROUP BY i.status
  UNION ALL
  SELECT 'row_count', 'group_mutes', 'total', count(*)::text FROM public.group_mutes
),
probes AS (
  SELECT 'probe', 'groups', 'invite_code_shape',
         format('distinct=%s | total=%s | all_8_upper_hex=%s',
                (SELECT count(DISTINCT invite_code) FROM public.groups),
                (SELECT count(*) FROM public.groups),
                (SELECT bool_and(invite_code ~ '^[0-9A-F]{8}$') FROM public.groups))
  UNION ALL
  SELECT 'probe', 'group_join_requests', 'pending_from_existing_members',
         (SELECT count(*) FROM public.group_join_requests r
          JOIN public.group_members gm ON gm.group_id = r.group_id AND gm.user_id = r.user_id
          WHERE r.status = 'pending')::text
  UNION ALL
  SELECT 'probe', 'group_invitations', 'pending_to_existing_members',
         (SELECT count(*) FROM public.group_invitations i
          JOIN public.group_members gm ON gm.group_id = i.group_id AND gm.user_id = i.invitee_id
          WHERE i.status = 'pending')::text
  UNION ALL
  SELECT 'probe', 'group_invitations', 'has_expiry_column',
         (SELECT CASE WHEN count(*) > 0 THEN 'YES' ELSE 'NO' END FROM information_schema.columns
          WHERE table_schema = 'public' AND table_name = 'group_invitations' AND column_name IN ('expires_at','expiry','expired_at'))
  UNION ALL
  SELECT 'probe', 'group_members', 'owner_integrity',
         format('groups=%s | with_owner_row=%s | multi_owner=%s | mismatch=%s',
           (SELECT count(*) FROM public.groups),
           (SELECT count(DISTINCT group_id) FROM public.group_members WHERE role = 'owner'),
           (SELECT count(*) FROM (SELECT group_id FROM public.group_members WHERE role = 'owner' GROUP BY group_id HAVING count(*) > 1) x),
           (SELECT count(*) FROM public.groups g LEFT JOIN public.group_members gm
              ON gm.group_id = g.id AND gm.user_id = g.owner_id AND gm.role = 'owner' WHERE gm.user_id IS NULL))
)
SELECT section, object, name, detail FROM (
  SELECT * FROM existence
  UNION ALL SELECT * FROM cols UNION ALL SELECT * FROM cons
  UNION ALL SELECT * FROM rls UNION ALL SELECT * FROM pol UNION ALL SELECT * FROM tgrants
  UNION ALL SELECT * FROM trg UNION ALL SELECT * FROM trigger_fn_bodies
  UNION ALL SELECT * FROM fns UNION ALL SELECT * FROM fn_bodies
  UNION ALL SELECT * FROM realtime UNION ALL SELECT * FROM counts UNION ALL SELECT * FROM probes
) x
ORDER BY CASE section
           WHEN 'exists' THEN 1 WHEN 'column' THEN 2 WHEN 'constraint' THEN 3 WHEN 'rls' THEN 4
           WHEN 'policy' THEN 5 WHEN 'table_grant' THEN 6 WHEN 'trigger' THEN 7 WHEN 'trigger_fn_body' THEN 8
           WHEN 'function' THEN 9 WHEN 'function_body' THEN 10 WHEN 'realtime' THEN 11
           WHEN 'row_count' THEN 12 ELSE 13 END,
         object, name;
