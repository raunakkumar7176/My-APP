-- ============================================================
-- G5.7 — fn_withdraw_join_request(p_request_id uuid)
-- STATUS: PROPOSED — NOT EXECUTED. Apply only after review.
-- ============================================================
-- Why: a logged-in user must be able to withdraw THEIR OWN pending
-- group join request. The live group_join_requests table has:
--   SELECT: own row OR MANAGE_MEMBERS
--   INSERT: user_id = auth.uid()
--   UPDATE: MANAGE_MEMBERS
--   DELETE: NO POLICY (direct DELETE is not supported for the requester)
--
-- This function provides the narrowest safe mechanism:
--   - authenticated only (auth.uid() IS NOT NULL)
--   - SECURITY DEFINER, search_path ''
--   - accept only the request id (no group_id from client)
--   - derive auth.uid() from session
--   - require user_id = auth.uid() (owner check)
--   - require status = 'pending' (cannot withdraw approved/declined)
--   - DELETE only that one row
--   - return the group_id on success (for UI refresh if needed)
--   - raise JOIN_REQUEST_NOT_FOUND on any failure (does not leak which)
--
-- Cannot:
--   - withdraw another user's request
--   - withdraw an approved request
--   - withdraw a declined request
--   - affect group_members or group_invitations
--   - be used by managers to delete someone else's request
--     (manager queue uses fn_approve_group_join_request)
--
-- Rollback: DROP FUNCTION below.
-- ============================================================

CREATE OR REPLACE FUNCTION public.fn_withdraw_join_request(p_request_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $$
DECLARE
  v_row public.group_join_requests;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT * INTO v_row
  FROM public.group_join_requests
  WHERE id = p_request_id
  FOR UPDATE;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'JOIN_REQUEST_NOT_FOUND';
  END IF;

  IF v_row.user_id <> auth.uid() THEN
    RAISE EXCEPTION 'JOIN_REQUEST_NOT_FOUND';
  END IF;

  IF v_row.status <> 'pending' THEN
    RAISE EXCEPTION 'JOIN_REQUEST_NOT_FOUND';
  END IF;

  DELETE FROM public.group_join_requests WHERE id = p_request_id;
  RETURN v_row.group_id;
END;
$$;

REVOKE ALL ON FUNCTION public.fn_withdraw_join_request(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_withdraw_join_request(uuid) FROM anon;
GRANT EXECUTE ON FUNCTION public.fn_withdraw_join_request(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Rollback (do not run unless reverting):
--   DROP FUNCTION public.fn_withdraw_join_request(uuid);

-- ------------------------------------------------------------
-- POSTFLIGHT (read-only; last statement -> shown by the SQL Editor)
-- Expected: definer=true | config={search_path=} | vol=v |
--           grants contain authenticated:EXECUTE and NOT anon
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
      AND routine_name = 'fn_withdraw_join_request') AS grants
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public'
  AND p.proname = 'fn_withdraw_join_request';
