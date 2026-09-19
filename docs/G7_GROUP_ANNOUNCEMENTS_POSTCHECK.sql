-- ============================================================
-- G7 — POST-CHECK (read-only). Run in the Supabase SQL Editor AFTER the
-- pre-check (and after migrations/G7_GROUP_ANNOUNCEMENTS.sql only if the
-- pre-check showed the table absent). Paste every grid back into the report.
-- ============================================================

-- ------------------------------------------------------------
-- Statement 1 — structure, grants, RLS. Expected:
--   table_exists=true | rls_enabled=true | policy_count>=3 |
--   has_select_policy=true | has_insert_policy=true |
--   has_update_or_all_policy=true | has_delete_or_all_policy=true |
--   fk_group=true | fk_author_profiles=true | title_check=true | body_check=true |
--   anon_privileges=0 | authenticated_privileges=DELETE,INSERT,SELECT,UPDATE |
--   group_created_index=true
-- ------------------------------------------------------------
SELECT
  to_regclass('public.group_announcements') IS NOT NULL AS table_exists,
  (SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'public' AND c.relname = 'group_announcements') AS rls_enabled,
  (SELECT count(*) FROM pg_policies p
     WHERE p.schemaname = 'public' AND p.tablename = 'group_announcements') AS policy_count,
  EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public'
            AND p.tablename = 'group_announcements' AND p.cmd IN ('SELECT', 'ALL')) AS has_select_policy,
  EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public'
            AND p.tablename = 'group_announcements' AND p.cmd IN ('INSERT', 'ALL')) AS has_insert_policy,
  EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public'
            AND p.tablename = 'group_announcements' AND p.cmd IN ('UPDATE', 'ALL')) AS has_update_or_all_policy,
  EXISTS (SELECT 1 FROM pg_policies p WHERE p.schemaname = 'public'
            AND p.tablename = 'group_announcements' AND p.cmd IN ('DELETE', 'ALL')) AS has_delete_or_all_policy,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = to_regclass('public.group_announcements')
            AND k.contype = 'f' AND k.confrelid = 'public.groups'::regclass) AS fk_group,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = to_regclass('public.group_announcements')
            AND k.contype = 'f' AND k.confrelid = 'public.profiles'::regclass) AS fk_author_profiles,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = to_regclass('public.group_announcements')
            AND k.contype = 'c' AND pg_get_constraintdef(k.oid) ILIKE '%title%') AS title_check,
  EXISTS (SELECT 1 FROM pg_constraint k WHERE k.conrelid = to_regclass('public.group_announcements')
            AND k.contype = 'c' AND pg_get_constraintdef(k.oid) ILIKE '%body%') AS body_check,
  (SELECT count(*) FROM information_schema.role_table_grants g
     WHERE g.table_schema = 'public' AND g.table_name = 'group_announcements' AND g.grantee = 'anon') AS anon_privileges,
  (SELECT string_agg(g.privilege_type, ',' ORDER BY g.privilege_type)
     FROM information_schema.role_table_grants g
     WHERE g.table_schema = 'public' AND g.table_name = 'group_announcements' AND g.grantee = 'authenticated') AS authenticated_privileges,
  EXISTS (SELECT 1 FROM pg_indexes i WHERE i.schemaname = 'public' AND i.tablename = 'group_announcements'
            AND i.indexdef ILIKE '%(group_id,%') AS group_created_index;

-- ------------------------------------------------------------
-- Statement 2 — permission enforcement as installed (the policy text).
-- Every write policy (INSERT / UPDATE / DELETE / ALL) must reference
-- fn_has_permission(... 'SEND_ANNOUNCEMENT') and fn_get_group_role(...) = 'owner';
-- the SELECT policy must reference fn_is_member(group_id, auth.uid()).
-- Expected: write_policies_gated = write_policies_total and read_gated_by_membership = true.
-- ------------------------------------------------------------
SELECT
  count(*) FILTER (WHERE cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL')) AS write_policies_total,
  count(*) FILTER (WHERE cmd IN ('INSERT', 'UPDATE', 'DELETE', 'ALL')
                     AND coalesce(qual, '') || coalesce(with_check, '') ILIKE '%SEND_ANNOUNCEMENT%'
                     AND coalesce(qual, '') || coalesce(with_check, '') ILIKE '%fn_get_group_role%') AS write_policies_gated,
  bool_and(CASE WHEN cmd IN ('SELECT', 'ALL') THEN coalesce(qual, '') ILIKE '%fn_is_member%' ELSE true END) AS read_gated_by_membership,
  bool_and('authenticated' = ANY (roles)) AS all_policies_authenticated_only,
  bool_and(NOT ('anon' = ANY (roles)) AND NOT ('public' = ANY (roles))) AS no_anon_or_public_policy
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'group_announcements';

-- ------------------------------------------------------------
-- Statement 3 — no cross-group read/write path: no SECURITY DEFINER function
-- writes to group_announcements without its own permission check. Lists every
-- definer function whose body mentions the table; each must be reviewed
-- (legacy: fn_mark_announcement_read / fn_announcement_seen_count only touch
-- reads; fn_archive_expired_announcements is status-only; notify/chat-pin
-- triggers write elsewhere). Expected: no function that INSERTs/UPDATEs/
-- DELETEs group_announcements rows on behalf of an unchecked caller.
-- ------------------------------------------------------------
SELECT p.proname,
       p.prosecdef AS security_definer,
       p.proconfig,
       (pg_get_functiondef(p.oid) ILIKE '%insert into public.group_announcements%'
        OR pg_get_functiondef(p.oid) ILIKE '%update public.group_announcements%'
        OR pg_get_functiondef(p.oid) ILIKE '%delete from public.group_announcements%') AS writes_table
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND pg_get_functiondef(p.oid) ILIKE '%group_announcements%'
ORDER BY p.proname;

-- ------------------------------------------------------------
-- Statement 4 — column shape the Flutter model parses. Expected to include:
--   id uuid NO | group_id uuid NO | author_id uuid NO | title text NO |
--   body text NO | created_at timestamptz NO | updated_at timestamptz NO
-- ------------------------------------------------------------
SELECT column_name, data_type, is_nullable, column_default
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'group_announcements'
  AND column_name IN ('id', 'group_id', 'author_id', 'title', 'body', 'created_at', 'updated_at')
ORDER BY ordinal_position;
