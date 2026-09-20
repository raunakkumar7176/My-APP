# FINAL AUDIT — POSTCHECK: `fn_accept_group_invitation` / `fn_decline_group_invitation`

Run **after** `migrations/FINAL_AUDIT_fix_group_invitation_accept_decline.sql`. Read-only except §3 (rolled back).

## 1. Definition

```sql
SELECT p.proname,
       (p.prosrc NOT ILIKE '%expires_at%') AS expires_branch_removed,  -- expect true
       pg_get_function_identity_arguments(p.oid) AS args,             -- expect p_invitation_id uuid (unchanged)
       p.prosecdef AS security_definer,                                -- expect true
       p.proconfig,                                                    -- expect {search_path=}
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,          -- expect false
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec, -- expect true
       has_function_privilege('service_role', p.oid, 'EXECUTE') AS service_exec -- expect true
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN ('fn_accept_group_invitation', 'fn_decline_group_invitation')
ORDER BY 1;
```

## 2. Policies untouched

```sql
SELECT count(*) AS invitation_policies FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'group_invitations';   -- expect 4 (unchanged)
SELECT count(*) AS member_policies FROM pg_policies
WHERE schemaname = 'public' AND tablename = 'group_members';       -- unchanged from before (7, or 6 after G14)
```

## 3. Functional proof (rolled back)

```sql
BEGIN;
INSERT INTO public.group_invitations (group_id, inviter_id, invitee_id, status)
VALUES ('<group>', '<owner>', '<invitee>', 'pending') RETURNING id;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '<other user>', true);
SELECT public.fn_accept_group_invitation('<id>');   -- expect ERROR INVITATION_NOT_FOUND (not the invitee)
SELECT set_config('request.jwt.claim.sub', '<invitee>', true);
SELECT public.fn_accept_group_invitation('<id>');   -- expect {"success":true,"group_id":...,"group_name":...}
SELECT public.fn_accept_group_invitation('<id>');   -- expect ERROR INVITATION_NOT_PENDING (reuse)
RESET ROLE;
SELECT status FROM public.group_invitations WHERE id = '<id>';        -- expect accepted
SELECT role FROM public.group_members WHERE group_id='<group>' AND user_id='<invitee>'; -- expect member
ROLLBACK;
```

## 4. Client follow-up (not part of this migration)

Flutter `lib/features/group/data/group_repository.dart` must send `p_invitation_id` (currently `p_invite_id`) for both RPCs; the fake and tests are parameter-agnostic, so this is a two-line change plus a re-run of `test/group/incoming_invitations_test.dart`.
