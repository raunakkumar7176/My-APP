-- ============================================================
-- R4 BACKEND HOTFIX — rpc_create_group has no SET search_path
-- (found by static code audit 2026-09-21, NOT yet proven live — see
--  preflight below; this is a code-review finding, not a reproduced bug)
-- ============================================================
-- Problem: rpc_create_group(text), defined in R4_5_5_group_foundation.sql,
-- is SECURITY DEFINER, GRANTed to `authenticated`, and client-callable —
-- but unlike every other SECURITY DEFINER function in this project (all of
-- which set `SET search_path TO ''`), it has no search_path pin at all.
-- Every reference inside its body is already schema-qualified
-- (public._fn_auth_uid(), public.groups, public.group_members) and the two
-- unqualified calls (trim(), length()) are pg_catalog builtins that are
-- always resolved first regardless of search_path — so this function is
-- not currently exploitable as written. The fix is defense-in-depth and
-- consistency with the project's own hardening standard: pinning
-- search_path now means a future edit that accidentally adds an
-- unqualified reference fails loudly (function/table not found) instead
-- of silently resolving against a schema an attacker could shadow.
--
-- Nothing else is touched: no schema, RLS, grants, or any other function.
-- Run in the Supabase SQL Editor top to bottom; read the preflight output
-- before continuing past it.
--
-- ------------------------------------------------------------
-- PREFLIGHT (read-only) — expected results in comments
-- ------------------------------------------------------------
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_create_group';
-- expect: prosecdef = true, proconfig = NULL (no search_path set yet) —
-- if proconfig already shows search_path=, STOP: this hotfix is unnecessary.

-- ------------------------------------------------------------
-- STEP 1 — rpc_create_group: pin search_path (ONLY change; body verbatim)
-- ------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_create_group(
  p_name text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_user_id uuid;
  v_group_id uuid;
  v_result jsonb;
BEGIN
  -- Get authenticated user
  v_user_id := public._fn_auth_uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'AUTHENTICATION_REQUIRED: You must be logged in to create a group';
  END IF;

  -- Validate input
  IF p_name IS NULL OR trim(p_name) = '' THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Group name is required';
  END IF;

  IF length(trim(p_name)) > 100 THEN
    RAISE EXCEPTION 'VALIDATION_ERROR: Group name must be 100 characters or less';
  END IF;

  -- Create the group
  INSERT INTO public.groups (name, created_by)
  VALUES (trim(p_name), v_user_id)
  RETURNING id INTO v_group_id;

  -- Add creator as leader
  INSERT INTO public.group_members (group_id, user_id, role)
  VALUES (v_group_id, v_user_id, 'leader');

  -- Return the created group
  SELECT jsonb_build_object(
    'id', g.id,
    'name', g.name,
    'created_by', g.created_by,
    'created_at', g.created_at,
    'updated_at', g.updated_at,
    'member_count', (SELECT COUNT(*) FROM public.group_members gm WHERE gm.group_id = g.id),
    'user_role', 'leader'
  ) INTO v_result
  FROM public.groups g
  WHERE g.id = v_group_id;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.rpc_create_group(text) IS
  'Creates a new group and adds the authenticated user as leader. Returns the created group.';

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only)
-- ------------------------------------------------------------
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_create_group';
-- expect: proconfig = {search_path=}

SELECT routine_name, grantee, privilege_type
FROM information_schema.routine_privileges
WHERE routine_schema = 'public' AND routine_name = 'rpc_create_group'
ORDER BY 1, 2;
-- expect: unchanged from preflight (authenticated EXECUTE, no anon)

-- Behavioural check: as an authenticated user, call
--   SELECT public.rpc_create_group('Test Group Name');
-- and confirm it still returns the expected jsonb shape and that the
-- caller becomes a 'leader' member of the new group.
