-- G17-02 — fn_increment_batch_progress: require authorization (owner apply required)
--
-- LIVE FINDING (2026-09-20): public.fn_increment_batch_progress(p_batch uuid,
-- p_count integer) is SECURITY DEFINER (search_path=public) with EXECUTE for
-- anon AND authenticated, and does `update result_batches set reports_done =
-- reports_done + p_count where id = p_batch` with no check at all. Any caller
-- (even anon) can alter any batch's progress counter (negative counts, wrong
-- test). Caller: the legacy web app's inline report generator
-- (tests/[id]/results-actions.ts) using the USER session — so a blanket revoke
-- would break that path; the fix authorizes instead.
--
-- FIX: same signature/return; anon revoked; a signed-in caller must be the
-- batch's test creator or hold GENERATE_RESULTS in the test's group (the same
-- gate as rpc_generate_results); the service role keeps working (worker).
-- Rollback: restore the one-line SQL body and re-grant anon.

CREATE OR REPLACE FUNCTION public.fn_increment_batch_progress(p_batch uuid, p_count integer)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_uid uuid := auth.uid();
  v_role text := current_setting('request.jwt.claim.role', true);
  v_test public.tests%rowtype;
begin
  if v_role is distinct from 'service_role' then
    if v_uid is null then
      raise exception 'NOT_AUTHENTICATED';
    end if;
    select t.* into v_test
    from public.result_batches b
    join public.tests t on t.id = b.test_id
    where b.id = p_batch;
    if not found then
      raise exception 'BATCH_NOT_FOUND';
    end if;
    if v_test.created_by is distinct from v_uid
       and not (
         v_test.group_id is not null
         and public.fn_has_permission(v_test.group_id, v_uid, 'GENERATE_RESULTS'::public.app_permission)
       ) then
      raise exception 'NOT_AUTHORIZED';
    end if;
  end if;
  if p_count is null or p_count < 0 then
    raise exception 'INVALID_COUNT';
  end if;
  update public.result_batches
  set reports_done = reports_done + p_count
  where id = p_batch;
end
$$;

REVOKE EXECUTE ON FUNCTION public.fn_increment_batch_progress(uuid, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_increment_batch_progress(uuid, integer) TO authenticated, service_role;

-- postflight (read-only)
SELECT has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_execute,                   -- expect false
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS authenticated_can_execute, -- expect true
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_role_can_execute,   -- expect true
       p.proconfig AS config                                                                    -- expect {search_path=}
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname = 'fn_increment_batch_progress';
