-- ============================================================
-- R4 MIGRATION D — rpc_get_user_groups(): the authenticated user's groups
-- ============================================================
-- Live evidence: every Create/Edit Test open logs
--   "Could not find the function public.rpc_get_user_groups without parameters"
-- (Chrome 2026-09-16/17) → the RPC is absent; the client already calls it
-- (GroupRepository.myGroups) and shows "no groups" on failure, so Group Test
-- creation is impossible live. fn_is_member / fn_has_permission ARE live
-- (used by _fn_start_attempt_core / rpc_generate_results), so the group
-- tables exist. R4_5_5 shape: groups(id, name, created_by, created_at[,
-- updated_at]), group_members(group_id, user_id, role).
--
-- Design: SECURITY DEFINER, search_path '', scoped by auth.uid() through a
-- membership JOIN — a user can only ever see groups they are a member of;
-- nothing from other groups is reachable. No table/RLS/grant change.
-- Schema-adaptive: groups.updated_at is NOT assumed. The DO block checks
-- the column and builds the function either way, always returning the
-- 7 columns the Flutter model parses (updated_at falls back to created_at).
-- Idempotent: CREATE OR REPLACE with the same signature; re-running is safe.
-- No logo/avatar column is known to exist → none is returned (not invented).
--
-- ------------------------------------------------------------
-- PREFLIGHT (read-only) — STOP if anything differs from "expect"
-- ------------------------------------------------------------
-- (1) tables + columns the RPC needs
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'public'
  AND ((table_name = 'groups'        AND column_name IN ('id','name','created_by','created_at','updated_at','logo_url','avatar_url'))
    OR (table_name = 'group_members' AND column_name IN ('group_id','user_id','role')))
ORDER BY table_name, column_name;
-- expect at least: groups.id/name/created_by/created_at, group_members.group_id/user_id/role.
-- groups.updated_at optional (handled). If a logo/avatar column appears, report it —
-- it is NOT returned by this migration (Flutter does not read one).

-- (2) any existing groups RPC under another name (avoid duplicates)
SELECT p.proname, pg_get_function_arguments(p.oid) AS args, pg_get_function_result(p.oid) AS returns,
       p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND (p.proname ILIKE '%group%')
ORDER BY p.proname;
-- expect: fn_is_member(uuid, uuid) boolean, fn_has_permission(...), rpc_get_user_groups ABSENT.
-- If an equivalent "list my groups" RPC already exists → STOP and report (reuse instead).

-- (3) RLS state on the group tables (unchanged by this migration)
SELECT c.relname, c.relrowsecurity
FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE n.nspname = 'public' AND c.relname IN ('groups','group_members') ORDER BY 1;
SELECT tablename, policyname, cmd, roles
FROM pg_policies WHERE schemaname = 'public' AND tablename IN ('groups','group_members') ORDER BY 1, 2;

-- ------------------------------------------------------------
-- STEP 1 — create the RPC (adaptive to groups.updated_at)
-- ------------------------------------------------------------
DO $do$
DECLARE
  v_has_updated_at boolean;
  v_updated_expr   text;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'groups' AND column_name = 'updated_at'
  ) INTO v_has_updated_at;

  v_updated_expr := CASE WHEN v_has_updated_at THEN 'g.updated_at' ELSE 'g.created_at' END;

  EXECUTE format($fn$
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
    AS $body$
      SELECT
        g.id,
        g.name,
        g.created_by,
        g.created_at,
        %s AS updated_at,
        (SELECT count(*) FROM public.group_members m WHERE m.group_id = g.id) AS member_count,
        gm.role AS user_role
      FROM public.groups g
      JOIN public.group_members gm ON gm.group_id = g.id
      WHERE gm.user_id = auth.uid()
      ORDER BY g.name;
    $body$;
  $fn$, v_updated_expr);
END
$do$;

REVOKE ALL ON FUNCTION public.rpc_get_user_groups() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_get_user_groups() FROM anon;
GRANT EXECUTE ON FUNCTION public.rpc_get_user_groups() TO authenticated;

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only) — A..J
-- ------------------------------------------------------------
-- A/B/C/D/E: exists, signature, return type, DEFINER, hardened search_path
SELECT p.oid::regprocedure AS signature,
       pg_get_function_arguments(p.oid) AS args,          -- expect: '' (no parameters)
       pg_get_function_result(p.oid)    AS returns,       -- expect: TABLE(id uuid, name text, created_by uuid, created_at timestamptz, updated_at timestamptz, member_count bigint, user_role text)
       p.prosecdef                       AS security_definer,  -- expect: t
       p.proconfig                       AS config,            -- expect: {search_path=}
       p.provolatile                     AS volatility         -- expect: s (STABLE)
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_get_user_groups';
-- expect exactly ONE row.

-- F/G: grants
SELECT grantee, privilege_type FROM information_schema.routine_privileges
WHERE routine_schema = 'public' AND routine_name = 'rpc_get_user_groups' ORDER BY 1;
-- expect: authenticated | EXECUTE (plus the owner, e.g. postgres); NO anon, NO PUBLIC

-- H/I: membership scoping is in the body (no bypass, own groups only)
SELECT
  pg_get_functiondef(p.oid) ~ 'JOIN\s+public\.group_members\s+gm\s+ON\s+gm\.group_id\s*=\s*g\.id' AS joins_membership,
  pg_get_functiondef(p.oid) ~ 'WHERE\s+gm\.user_id\s*=\s*auth\.uid\(\)'                          AS scoped_to_caller,
  pg_get_functiondef(p.oid) ~* '(service_role|secret|api_key)'                                   AS references_secrets_should_be_f
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'rpc_get_user_groups';
-- expect: t | t | f

-- J: no client credential involved — the function reads auth.uid() from the
-- caller's JWT only (see scoped_to_caller). Nothing else to check.

-- Behavioural (read-only):
--   as a member:      SELECT * FROM public.rpc_get_user_groups();   -- own groups only
--   as a non-member of everything: 0 rows
--   with the anon key (no JWT): permission denied for function rpc_get_user_groups
