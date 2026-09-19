-- G14 — close the legacy `group_members` ALL policy (owner apply required)
--
-- LIVE FINDING (2026-09-19, read-only audit + rolled-back probe):
--   policy "Users can manage group members" ON public.group_members FOR ALL
--     USING      (auth.uid() = user_id OR auth.uid() IN (SELECT owner_id FROM groups WHERE id = group_id))
--     WITH CHECK (true)
--   Proven consequences (transaction rolled back, residue 0):
--     * a member / moderator UPDATEs their own row to role = 'leader'
--       (self-promotion; the "role changes" policy is bypassed because the
--       legacy USING branch `auth.uid() = user_id` matches the caller's row);
--     * ANY authenticated user INSERTs a row into ANY group — including
--       themselves as 'leader' of a group they are not a member of
--       (WITH CHECK true).
--   Only `trg_owner_guard` / `trg_protect_group_member_identity` stop the
--   owner row from being touched; every other row is open.
--
-- WHAT STAYS (all live, unchanged, and sufficient for every client path):
--   SELECT  "members see roster"               fn_is_member
--   INSERT  "group creator adds self as owner" owner row on group creation
--   INSERT  "join via invite code"             user_id = uid AND invite.code setting
--   UPDATE  "role changes"                     role <> 'owner' AND MANAGE_ROLES
--   DELETE  "manage members"                   other row, not owner, MANAGE_MEMBERS
--   DELETE  "self leave group"                 own row, not owner
--   SECURITY DEFINER functions (fn_create_group, fn_join_group,
--   fn_accept_group_invitation, fn_approve_group_join_request) insert
--   memberships themselves and do not depend on the dropped policy.
--   The owner keeps every capability through `fn_has_permission`'s bypass.
--
-- NOT CHANGED: tables, columns, enums, triggers, functions, grants, any
-- other policy. Rollback = re-create the policy verbatim (see bottom).

DROP POLICY IF EXISTS "Users can manage group members" ON public.group_members;

-- postflight (read-only): the legacy policy is gone, the six specific ones remain
SELECT
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'group_members'
      AND policyname = 'Users can manage group members') AS legacy_policy_count,
  (SELECT count(*) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'group_members') AS remaining_policy_count,
  (SELECT array_agg(policyname ORDER BY policyname) FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'group_members') AS remaining_policies;

-- ROLLBACK (only if a legitimate path is found to depend on the legacy policy):
-- CREATE POLICY "Users can manage group members" ON public.group_members FOR ALL
--   USING ((auth.uid() = user_id) OR (auth.uid() IN (SELECT groups.owner_id FROM groups WHERE groups.id = group_members.group_id)))
--   WITH CHECK (true);
