# FINAL AUDIT — PRECHECK: `fn_accept_group_invitation` / `fn_decline_group_invitation`

Run in the Supabase SQL Editor **before** `migrations/FINAL_AUDIT_fix_group_invitation_accept_decline.sql`.
Read-only.

## 1. The defect: the functions reference a column the table does not have

```sql
SELECT column_name
FROM information_schema.columns
WHERE table_schema = 'public' AND table_name = 'group_invitations'
ORDER BY ordinal_position;
-- expect exactly: id, group_id, inviter_id, invitee_id, status, created_at  (no expires_at)

SELECT p.proname,
       (p.prosrc ILIKE '%expires_at%') AS references_missing_column,   -- expect true (the bug)
       pg_get_function_identity_arguments(p.oid) AS args,               -- expect p_invitation_id uuid
       p.prosecdef, p.proconfig,
       has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_exec,
       has_function_privilege('authenticated', p.oid, 'EXECUTE') AS auth_exec
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN ('fn_accept_group_invitation', 'fn_decline_group_invitation')
ORDER BY 1;
```

## 2. Keep the previous bodies for rollback

```sql
SELECT p.proname, pg_get_functiondef(p.oid)
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.proname IN ('fn_accept_group_invitation', 'fn_decline_group_invitation');
-- save the output; it is the exact rollback
```

## 3. Live proof of the failure (optional, rolled back)

```sql
BEGIN;
-- as the owner: invite a real user, then act as that user
-- (replace <group>, <owner>, <invitee>)
INSERT INTO public.group_invitations (group_id, inviter_id, invitee_id, status)
VALUES ('<group>', '<owner>', '<invitee>', 'pending') RETURNING id;
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '<invitee>', true);
SELECT public.fn_accept_group_invitation('<id from above>');
-- expect: ERROR: column gi.expires_at does not exist
ROLLBACK;
```

## 4. Nothing else depends on the change

```sql
SELECT p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'public' AND p.prosrc ILIKE '%fn_accept_group_invitation%' AND p.proname <> 'fn_accept_group_invitation';
-- expect 0 rows (only clients call it)
```

Clients: Flutter `GroupRepository.acceptInvitation/declineInvitation` (note: sends `p_invite_id` — client fix required, see the audit report), legacy web app invitation actions (send `p_invitation_id`).
