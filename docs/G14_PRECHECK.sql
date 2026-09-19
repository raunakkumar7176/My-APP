-- G14 PRECHECK (read-only). Run in the Supabase SQL Editor BEFORE
-- migrations/G14_drop_legacy_group_members_policy.sql.
-- Expected (live 2026-09-19): legacy_present = true; the policy list shows
-- the seven policies below; role_permissions has the three policies listed.

-- 1. the legacy policy exists and is the only FOR ALL policy on group_members
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'group_members'
ORDER BY policyname;
-- expect: "Users can manage group members" (ALL, WITH CHECK true),
--         "group creator adds self as owner" (INSERT), "join via invite code" (INSERT),
--         "manage members" (DELETE), "members see roster" (SELECT),
--         "role changes" (UPDATE), "self leave group" (DELETE)

SELECT EXISTS (
  SELECT 1 FROM pg_policies
  WHERE schemaname = 'public' AND tablename = 'group_members'
    AND policyname = 'Users can manage group members'
) AS legacy_present;

-- 2. protective triggers that stay in place
SELECT tgname, pg_get_triggerdef(oid)
FROM pg_trigger
WHERE tgrelid = 'public.group_members'::regclass AND NOT tgisinternal
ORDER BY tgname;
-- expect: trg_owner_guard (fn_prevent_owner_removal), trg_protect_group_member_identity, + system/notify triggers

-- 3. role_permissions policies the G14 Flutter matrix relies on (unchanged by G14)
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'role_permissions'
ORDER BY policyname;
-- expect: "group creator seeds leader perms" (INSERT), "manage roles perms" (ALL, MANAGE_ROLES),
--         "members view perms" (SELECT, fn_is_member)

-- 4. the permission engine (unchanged by G14)
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname IN ('fn_has_permission', 'fn_get_group_role', 'fn_is_member', 'fn_get_group_permissions')
ORDER BY 1;
-- expect: all SECURITY DEFINER with search_path=""

-- 5. role_permissions rows per role (owner never has rows; moderator none unless granted via G14)
SELECT role, count(*) FROM public.role_permissions GROUP BY role ORDER BY role;
