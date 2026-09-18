-- ============================================================
-- G5.6 — rpc_find_profile_by_student_code(p_code text)
-- STATUS: PROPOSED — NOT EXECUTED. Apply only after review.
-- ============================================================
-- Why: sending a group invitation needs `profiles.id` for a person who is
-- NOT yet a member. The live `profiles` SELECT policies are
--   own row  OR  fellow member  OR  test participant
-- so a manager cannot resolve a stranger's student code through the table.
-- No existing function does this (audited: fn_next_student_code /
-- fn_set_student_code / fn_ensure_student_code only generate codes).
--
-- Precondition (confirm with G5_6_VERIFY.sql before applying):
--   profiles.student_code has UNIQUE index profiles_student_code_key
--   (0007_student_code_and_standalone_tests, re-asserted in 0033).
--   If it is NOT unique live, do not apply this file.
--
-- Contract: exact-match lookup of one registered user.
--   returns at most one row: id, full_name, avatar_url, student_code
--   never: email, mobile, bio, exam_targets, timezone, group membership,
--          invite codes, auth data
--   SECURITY DEFINER, search_path '', STABLE, authenticated only, anon revoked
--   NULL / blank / unknown code -> zero rows (no error, nothing leaked)
--   The caller's own code resolves too (harmless; the UI refuses self-invite).
-- Plain single-level dollar quoting. No DO block, no dynamic SQL. Idempotent.
-- No table / policy / trigger / enum change. Rollback: DROP FUNCTION below.
-- ============================================================

CREATE OR REPLACE FUNCTION public.rpc_find_profile_by_student_code(p_code text)
RETURNS TABLE (
  id uuid,
  full_name text,
  avatar_url text,
  student_code text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO ''
AS $$
  SELECT p.id, p.full_name, p.avatar_url, p.student_code
  FROM public.profiles p
  WHERE auth.uid() IS NOT NULL
    AND p.student_code IS NOT NULL
    AND p.student_code = upper(trim(p_code))
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.rpc_find_profile_by_student_code(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.rpc_find_profile_by_student_code(text) FROM anon;
GRANT EXECUTE ON FUNCTION public.rpc_find_profile_by_student_code(text) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Rollback (do not run unless reverting):
--   DROP FUNCTION public.rpc_find_profile_by_student_code(text);

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only; last statement -> shown by the SQL Editor)
-- Expected: definer=true | config={search_path=} | vol=s |
--           grants contain authenticated:EXECUTE and NOT anon |
--           student_code_unique=true
-- ------------------------------------------------------------
SELECT
  p.oid::regprocedure AS signature,
  pg_get_function_result(p.oid) AS returns,
  p.prosecdef AS definer,
  p.proconfig AS config,
  p.provolatile AS vol,
  (SELECT string_agg(grantee || ':' || privilege_type, ', ' ORDER BY grantee)
     FROM information_schema.routine_privileges
    WHERE routine_schema = 'public'
      AND routine_name = 'rpc_find_profile_by_student_code') AS grants,
  EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public' AND tablename = 'profiles'
      AND indexdef ILIKE '%UNIQUE%' AND indexdef ILIKE '%(student_code)%'
  ) AS student_code_unique
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'rpc_find_profile_by_student_code';
