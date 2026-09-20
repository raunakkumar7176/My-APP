-- FINAL AUDIT — fn_accept_group_invitation / fn_decline_group_invitation reference a
-- column that does not exist (owner apply required)
--
-- LIVE FINDING (2026-09-20, rolled-back proof): public.group_invitations has exactly
--   id, group_id, inviter_id, invitee_id, status, created_at
-- but both live functions SELECT `gi.expires_at` and test it. plpgsql resolves the
-- column at execution, so the functions compile, pass the NOT_FOUND / NOT_PENDING
-- branches used in earlier proofs, and then fail for the real invitee with
--   ERROR: column gi.expires_at does not exist
-- Consequence: no invitation can be accepted or declined (G5.4 path broken live).
-- The Flutter client additionally sends parameter `p_invite_id` while the live
-- parameter is `p_invitation_id` (client fix listed separately in the audit report;
-- this migration keeps the live parameter name so the legacy web app is unaffected).
--
-- FIX: same signatures, same return shapes, same guards (auth, invitee-only,
-- pending-only, membership insert ON CONFLICT DO NOTHING), search_path hardened to '',
-- expiry branch removed (no column, nothing sets `expired`). Nothing else changes.
-- Rollback: re-create the previous bodies (recorded verbatim by docs/FINAL_AUDIT_..._PRECHECK.md §2).

CREATE OR REPLACE FUNCTION public.fn_accept_group_invitation(p_invitation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_user_id uuid;
  v_invitation record;
  v_group_name text;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  select gi.id, gi.group_id, gi.invitee_id, gi.status
  into v_invitation
  from public.group_invitations gi
  where gi.id = p_invitation_id
    and gi.invitee_id = v_user_id
  for update;
  if not found then
    raise exception 'INVITATION_NOT_FOUND';
  end if;
  if v_invitation.status <> 'pending' then
    raise exception 'INVITATION_NOT_PENDING';
  end if;
  select name into v_group_name
  from public.groups
  where id = v_invitation.group_id;
  if v_group_name is null then
    raise exception 'GROUP_NOT_FOUND';
  end if;
  insert into public.group_members (group_id, user_id, role)
  values (v_invitation.group_id, v_user_id, 'member'::public.group_role)
  on conflict (group_id, user_id) do nothing;
  update public.group_invitations
  set status = 'accepted'
  where id = p_invitation_id;
  return jsonb_build_object(
    'success', true,
    'group_id', v_invitation.group_id,
    'group_name', v_group_name
  );
end;
$$;

CREATE OR REPLACE FUNCTION public.fn_decline_group_invitation(p_invitation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $$
declare
  v_user_id uuid;
  v_invitation record;
begin
  v_user_id := auth.uid();
  if v_user_id is null then
    raise exception 'AUTH_REQUIRED';
  end if;
  select gi.id, gi.group_id, gi.invitee_id, gi.status
  into v_invitation
  from public.group_invitations gi
  where gi.id = p_invitation_id
    and gi.invitee_id = v_user_id
  for update;
  if not found then
    raise exception 'INVITATION_NOT_FOUND';
  end if;
  if v_invitation.status <> 'pending' then
    raise exception 'INVITATION_NOT_PENDING';
  end if;
  update public.group_invitations
  set status = 'declined'
  where id = p_invitation_id;
  return jsonb_build_object('success', true, 'group_id', v_invitation.group_id);
end;
$$;

REVOKE EXECUTE ON FUNCTION public.fn_accept_group_invitation(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.fn_decline_group_invitation(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fn_accept_group_invitation(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.fn_decline_group_invitation(uuid) TO authenticated, service_role;

-- postflight (read-only)
SELECT p.proname, p.prosecdef, p.proconfig,
       (p.prosrc NOT ILIKE '%expires_at%') AS expires_branch_removed,       -- expect true
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec, -- expect true
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec          -- expect false
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN ('fn_accept_group_invitation', 'fn_decline_group_invitation')
ORDER BY 1;
