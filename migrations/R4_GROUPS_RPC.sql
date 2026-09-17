-- ============================================================
-- R4 — rpc_get_user_groups(): minimum secure read for Group Test creation
-- ============================================================
-- Live evidence (Chrome, 2026-09-16/17, every Create/Edit Test open):
--   PostgrestException: Could not find the function public.rpc_get_user_groups
--   without parameters in the schema cache
-- The client already calls it (GroupRepository) and degrades to "no groups";
-- Group Test creation is therefore impossible live. fn_is_member /
-- fn_has_permission ARE live (used by _fn_start_attempt_core and
-- rpc_generate_results), so the group tables exist; only the read RPC is
-- missing. No new architecture: R4_5_5 shape, auth.uid() scoped, DEFINER.
--
-- ------------------------------------------------------------
-- PREFLIGHT (read-only) — STOP if anything differs from "expect"
-- ------------------------------------------------------------
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND ((table_name = 'groups' AND column_name IN ('id','name','created_by','created_at','updated_at'))
    OR (table_name = 'group_members' AND column_name IN ('group_id','user_id','role')))
ORDER BY table_name, column_name;
-- expect 8 rows. If groups.updated_at is missing, edit the SELECT below to
-- return g.created_at AS updated_at (the client tolerates equal values).

SELECT p.oid::regprocedure, pg_get_function_result(p.oid)
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_get_user_groups';
-- expect: 0 rows (live error above). If a row exists with another result
-- type, DROP it first — CREATE OR REPLACE cannot change a return type.

-- ------------------------------------------------------------
-- STEP 1 — the RPC (own memberships only; never lists other users' groups)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_get_user_groups()
RETURNS TABLE (
  id uuid,
  name text,
  created_by uuid,
  created_at timestamptz,
  updated_at timestamptz,
  member_count bigint,
  user_role text
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path TO ''
AS $$
  SELECT
    g.id,
    g.name,
    g.created_by,
    g.created_at,
    g.updated_at,
    (SELECT count(*) FROM public.group_members m WHERE m.group_id = g.id) AS member_count,
    gm.role AS user_role
  FROM public.groups g
  JOIN public.group_members gm ON gm.group_id = g.id
  WHERE gm.user_id = auth.uid()
  ORDER BY g.name;
$$;

REVOKE ALL ON FUNCTION public.rpc_get_user_groups() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_get_user_groups() FROM anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_user_groups() TO authenticated;

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only)
-- ------------------------------------------------------------
SELECT p.oid::regprocedure, p.prosecdef, p.proconfig, pg_get_function_result(p.oid)
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_get_user_groups';
-- expect: 1 row, prosecdef t, proconfig {search_path=}
SELECT grantee, privilege_type FROM information_schema.routine_privileges
WHERE routine_schema = 'public' AND routine_name = 'rpc_get_user_groups';
-- expect: authenticated only
-- As a member: SELECT * FROM public.rpc_get_user_groups();   -- own groups
-- Unauthenticated (anon key, no JWT): 0 rows / permission denied
