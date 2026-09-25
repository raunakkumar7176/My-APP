-- GROUP_HUB_rpc_delete_group.sql
-- ============================================================================
-- UNAPPLIED. This environment has no live Supabase access (no CLI/psql/.env).
-- A human with production DB access must review and run this manually.
-- ============================================================================
--
-- CONTEXT: Group Hub redesign, Phase 7 — a group with exactly one member
-- (its owner, no one else) may be deleted by that owner. No such capability
-- existed anywhere in this schema before (confirmed by inspection: no
-- rpc_delete_group/fn_delete_group in any prior migration).
--
-- WHY A HARD DELETE, NOT SOFT: `public.tests` has an explicit soft-delete
-- design (`is_soft_deleted`, `deleted_by` — see migrations/0047,0050) that
-- this task's own instructions say to preserve wherever it already exists.
-- `public.groups` has NEVER had an equivalent column added across its
-- entire migration history (checked every ALTER TABLE groups in this
-- project) — it has no soft-delete design to preserve. Every group_id FK
-- referencing `groups(id)` in the base schema (group_members,
-- group_messages, group_rules, group_announcements, and others) is already
-- `ON DELETE CASCADE`, so a hard DELETE on `groups` cleanly removes exactly
-- this group's own data and nothing else's — this is the existing,
-- intentional design for this table, not a new one.
--
-- AUTHORIZATION (re-verified server-side, never trusts the client):
--   1. Caller must be authenticated.
--   2. Caller must be the group's owner_id.
--   3. No group_members row for this group may belong to anyone other
--      than the owner (covers both "owner has their own membership row"
--      — the normal case per fn_create_group, see 0001_init.sql:358 — and
--      the defensive case documented in lib/core/models/group.dart where
--      an owner might have no row at all).
--
-- RULES: additive only (one new function). No existing table/column/
-- policy/RLS/grant touched. Idempotent (CREATE OR REPLACE).
--
-- OWNER APPLY REQUIRED

-- ------------------------------------------------------------
-- PREFLIGHT
-- ------------------------------------------------------------
-- SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public' AND p.proname = 'rpc_delete_group';
-- expect: NO ROWS.

CREATE OR REPLACE FUNCTION public.rpc_delete_group(p_group uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $function$
DECLARE
  v_owner uuid;
  v_other_members integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT owner_id INTO v_owner FROM public.groups WHERE id = p_group;
  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'GROUP_NOT_FOUND';
  END IF;
  IF v_owner <> auth.uid() THEN
    RAISE EXCEPTION 'NOT_AUTHORIZED';
  END IF;

  SELECT count(*) INTO v_other_members
  FROM public.group_members
  WHERE group_id = p_group AND user_id <> v_owner;
  IF v_other_members > 0 THEN
    RAISE EXCEPTION 'GROUP_HAS_OTHER_MEMBERS';
  END IF;

  -- Cascades to group_members/group_messages/group_rules/
  -- group_announcements/tests(group_id)/etc. via each table's existing
  -- ON DELETE CASCADE — nothing here duplicates that cleanup logic.
  DELETE FROM public.groups WHERE id = p_group;
END;
$function$;

REVOKE ALL ON FUNCTION public.rpc_delete_group(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_delete_group(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.rpc_delete_group(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ------------------------------------------------------------
-- POSTFLIGHT
-- ------------------------------------------------------------
-- SELECT p.proname, p.prosecdef, p.proconfig
-- FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public' AND p.proname = 'rpc_delete_group';
-- expect: one row, prosecdef = true, proconfig contains search_path.
--
-- SELECT has_function_privilege('anon', 'public.rpc_delete_group(uuid)', 'EXECUTE') AS anon_can_execute,
--        has_function_privilege('authenticated', 'public.rpc_delete_group(uuid)', 'EXECUTE') AS authenticated_can_execute;
-- expect: anon_can_execute = false, authenticated_can_execute = true.

-- ------------------------------------------------------------
-- SECURITY / BEHAVIOR TEST MATRIX (manual, run against a live project)
-- ------------------------------------------------------------
-- 1. Owner of a solo group (only member) calls rpc_delete_group -> group
--    and all its cascaded rows (messages, rules, announcements, any
--    group-scoped tests, etc.) are gone.
-- 2. Owner of a group with 2+ members calls rpc_delete_group ->
--    GROUP_HAS_OTHER_MEMBERS, group untouched.
-- 3. A non-owner member of a solo-owner... (impossible by definition, but)
--    a non-owner member of a multi-member group calls it -> NOT_AUTHORIZED.
-- 4. A user with no relationship to the group calls it with its id ->
--    NOT_AUTHORIZED (same message as #3 — existence is not leaked
--    differently for a stranger vs. a member, matching this app's existing
--    "one honest denial" convention elsewhere, e.g. GroupHubController's
--    accessDenied handling).
-- 5. An unauthenticated call -> AUTH_REQUIRED.
-- 6. Calling with a non-existent group id -> GROUP_NOT_FOUND.

-- ------------------------------------------------------------
-- ROLLBACK
-- ------------------------------------------------------------
-- DROP FUNCTION IF EXISTS public.rpc_delete_group(uuid);

-- ============================================================================
-- END OF GROUP_HUB_rpc_delete_group MIGRATION
-- ============================================================================
