-- ============================================================
-- R4 D — public.rpc_get_user_groups()  (final, derived from the LIVE schema)
-- ============================================================
-- Live facts (owner-run inspection, 2026-09-17):
--   groups(id, name, description, logo_url NULL, invite_code, owner_id, created_at, privacy)
--   group_members(group_id, user_id, role public.group_role, joined_at)  PK (group_id, user_id)
--   group_role: owner | leader | moderator | member
-- No created_by / updated_at exist → not returned, not fabricated.
-- invite_code / description / privacy are NOT returned (client does not need them;
-- invite_code is a join secret that must not leak through a list call).
--
-- Result (exactly 7 columns): id, name, owner_id, logo_url, created_at, member_count, user_role
-- Scope: groups the caller OWNS or is a MEMBER of — never anyone else's.
-- Shape: one row per group (groups × LEFT JOIN of the caller's own membership
-- row, which is unique by PK (group_id, user_id)); member_count is a scalar
-- subquery, so no fan-out and no duplicate rows.
-- Plain single-level statement (no DO / no dynamic SQL); idempotent.

-- ------------------------------------------------------------
-- STEP 1 — function
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_get_user_groups()
RETURNS TABLE (
  id uuid,
  name text,
  owner_id uuid,
  logo_url text,
  created_at timestamptz,
  member_count bigint,
  user_role text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT
    g.id,
    g.name,
    g.owner_id,
    g.logo_url,
    g.created_at,
    (SELECT count(*) FROM public.group_members mc WHERE mc.group_id = g.id) AS member_count,
    COALESCE(me.role::text, 'owner') AS user_role
  FROM public.groups g
  LEFT JOIN public.group_members me
         ON me.group_id = g.id
        AND me.user_id  = auth.uid()
  WHERE g.owner_id = auth.uid()
     OR me.user_id IS NOT NULL
  ORDER BY g.name;
$$;

REVOKE ALL ON FUNCTION public.rpc_get_user_groups() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_get_user_groups() FROM anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_user_groups() TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only) — one statement, one grid
-- ------------------------------------------------------------
-- SELECT p.oid::regprocedure AS signature,                       -- rpc_get_user_groups()
--        pg_get_function_arguments(p.oid) AS args,               -- '' (zero arguments)
--        pg_get_function_result(p.oid) AS returns,               -- TABLE(id uuid, name text, owner_id uuid,
--                                                                --   logo_url text, created_at timestamptz,
--                                                                --   member_count bigint, user_role text)
--        p.prosecdef, p.proconfig, p.provolatile,                -- t | {search_path=} | s
--        (SELECT string_agg(grantee || ':' || privilege_type, ', ')
--           FROM information_schema.routine_privileges
--          WHERE routine_schema = 'public' AND routine_name = 'rpc_get_user_groups') AS grants,
--                                                                -- authenticated:EXECUTE (+ owner); no anon/PUBLIC
--        pg_get_functiondef(p.oid) ~ 'invite_code' AS leaks_invite_code_should_be_f
-- FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public' AND p.proname = 'rpc_get_user_groups';
--
-- Behavioural (as an authenticated user):
--   SELECT * FROM public.rpc_get_user_groups();
--     → only groups you own or belong to; user_role = your membership role,
--       or 'owner' when you own a group without a membership row;
--       member_count = SELECT count(*) FROM public.group_members WHERE group_id = <that group>.
--   With the anon key (no JWT): permission denied for function rpc_get_user_groups.
