-- G14 POSTCHECK (read-only). Run AFTER migrations/G14_drop_legacy_group_members_policy.sql.

-- 1. the legacy policy is gone; six specific policies remain
SELECT
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'group_members'
      AND policyname = 'Users can manage group members') AS legacy_policy_count,      -- expect 0
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'group_members') AS remaining_policy_count, -- expect 6
  (SELECT array_agg(policyname ORDER BY policyname) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'group_members') AS remaining_policies;
-- expect: {group creator adds self as owner, join via invite code, manage members,
--          members see roster, role changes, self leave group}

-- 2. no FOR ALL policy is left on group_members
SELECT count(*) AS all_cmd_policies
FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'group_members' AND cmd = 'ALL';
-- expect 0

-- 3. RLS still enabled; triggers untouched
SELECT relrowsecurity, relforcerowsecurity FROM pg_class WHERE oid = 'public.group_members'::regclass;
-- expect true, false
SELECT count(*) AS guard_triggers
FROM pg_trigger
WHERE tgrelid = 'public.group_members'::regclass
  AND tgname IN ('trg_owner_guard', 'trg_protect_group_member_identity');
-- expect 2

-- 4. nothing else changed
SELECT count(*) AS role_permissions_policies FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'role_permissions';
-- expect 3
SELECT count(*) AS owners FROM public.group_members WHERE role = 'owner';
-- expect = number of groups
