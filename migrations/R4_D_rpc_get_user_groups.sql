-- ============================================================
-- R4 D — public.rpc_get_user_groups()  (final, LIVE schema)
-- ============================================================
-- Live facts (owner-run inspection, 2026-09-17):
--   groups(id, name, description, logo_url NULL, invite_code, owner_id, created_at, privacy)
--   group_members(group_id, user_id, role public.group_role, joined_at)  PK (group_id, user_id)
--   group_role: owner | leader | moderator | member
-- Result: exactly 7 columns (id, name, owner_id, logo_url, created_at, member_count, user_role).
-- Scope: groups the caller owns OR is a member of. Nothing else is returned.
-- Not exposed: invite_code, description, privacy. No created_by / updated_at (do not exist).
-- One row per group: the LEFT JOIN is on the caller's own membership row only
-- (unique by PK), member_count is an independent scalar subquery.
-- Plain single-level dollar-quoted body. No DO block, no dynamic SQL. Idempotent.
-- No table / enum / RLS / helper-function change.

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
-- POSTFLIGHT (read-only; last statement → shown by the SQL Editor)
-- Expected: rpc_get_user_groups() | '' | TABLE(id uuid, name text, owner_id uuid,
--   logo_url text, created_at timestamp with time zone, member_count bigint, user_role text)
--   | true | {search_path=} | s | authenticated:EXECUTE (+ owner) | false
-- ------------------------------------------------------------
SELECT
  p.oid::regprocedure AS signature,
  pg_get_function_arguments(p.oid) AS args,
  pg_get_function_result(p.oid) AS returns,
  p.prosecdef AS security_definer,
  p.proconfig AS config,
  p.provolatile AS volatility,
  (
    SELECT string_agg(
      grantee || ':' || privilege_type,
      ', ' ORDER BY grantee, privilege_type
    )
    FROM information_schema.routine_privileges
    WHERE routine_schema = 'public'
      AND routine_name = 'rpc_get_user_groups'
  ) AS grants,
  pg_get_functiondef(p.oid) ~ 'invite_code' AS leaks_invite_code
FROM pg_proc p
JOIN pg_namespace n
  ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'rpc_get_user_groups'
  AND pg_get_function_identity_arguments(p.oid) = '';
