-- ============================================================
-- R4 MIGRATION D (v2) — rpc_get_user_groups(): the authenticated user's groups
-- ============================================================
-- v1 wrapped CREATE FUNCTION in DO + EXECUTE format() with nested dollar
-- quotes; the Supabase SQL Editor split that text at the inner ';' and the
-- function was never created ("Success. No rows returned", 0 rows on verify).
-- v2 is a plain, single-level statement. `groups.updated_at` is NOT
-- assumed: it is read through to_jsonb(g), which only carries columns that
-- exist, so the body compiles either way and falls back to created_at.
-- Membership scope: JOIN group_members WHERE user_id = auth.uid() — the
-- caller sees only groups they belong to. No table/RLS/policy change.
-- Idempotent: CREATE OR REPLACE with a fixed signature; safe to re-run.
-- No logo/avatar column is known to exist → none is returned.

-- ------------------------------------------------------------
-- PREFLIGHT (read-only)
-- ------------------------------------------------------------
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND ((table_name = 'groups'        AND column_name IN ('id','name','created_by','created_at','updated_at'))
    OR (table_name = 'group_members' AND column_name IN ('group_id','user_id','role')))
ORDER BY table_name, column_name;
-- expect groups.id/name/created_by/created_at + group_members.group_id/user_id/role (updated_at optional)

SELECT p.proname, pg_get_function_arguments(p.oid) AS args
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname ILIKE '%group%'
ORDER BY 1;
-- expect: fn_is_member, fn_has_permission (…); rpc_get_user_groups absent (or the v2 one if re-running)

-- ------------------------------------------------------------
-- STEP 1 — the RPC (plain statement; no DO / no dynamic SQL)
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
    -- updated_at only if the column exists on the live table; else created_at.
    COALESCE((to_jsonb(g) ->> 'updated_at')::timestamptz, g.created_at) AS updated_at,
    (SELECT count(*) FROM public.group_members m WHERE m.group_id = g.id) AS member_count,
    gm.role::text AS user_role
  FROM public.groups g
  JOIN public.group_members gm ON gm.group_id = g.id
  WHERE gm.user_id = auth.uid()
  ORDER BY g.name;
$$;

REVOKE ALL ON FUNCTION public.rpc_get_user_groups() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_get_user_groups() FROM anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_user_groups() TO authenticated;

-- PostgREST must see the new function ("…in the schema cache" 404 otherwise).
NOTIFY pgrst, 'reload schema';

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only)
-- ------------------------------------------------------------
SELECT p.oid::regprocedure AS signature,
       pg_get_function_result(p.oid) AS returns,
       p.prosecdef AS security_definer,
       p.proconfig AS config,
       p.provolatile AS volatility
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_get_user_groups';
-- expect ONE row: rpc_get_user_groups() | TABLE(id uuid, name text, created_by uuid,
--   created_at timestamptz, updated_at timestamptz, member_count bigint, user_role text) | t | {search_path=} | s

SELECT grantee, privilege_type FROM information_schema.routine_privileges
WHERE routine_schema = 'public' AND routine_name = 'rpc_get_user_groups' ORDER BY 1;
-- expect: authenticated | EXECUTE (+ owner); NO anon, NO PUBLIC

SELECT
  pg_get_functiondef(p.oid) ~ 'JOIN\s+public\.group_members\s+gm\s+ON\s+gm\.group_id\s*=\s*g\.id' AS joins_membership,
  pg_get_functiondef(p.oid) ~ 'WHERE\s+gm\.user_id\s*=\s*auth\.uid\(\)'                          AS scoped_to_caller
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_get_user_groups';
-- expect: t | t

-- Behavioural: SELECT * FROM public.rpc_get_user_groups();   -- own groups only (0 rows if none)
