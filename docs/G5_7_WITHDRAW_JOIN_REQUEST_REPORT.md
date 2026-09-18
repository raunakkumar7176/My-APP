# G5.7 — Withdraw Join Request: Implementation Report

**Status: BLOCKED — live RPC verification pending.**
**Flutter complete; backend RPC `fn_withdraw_join_request` is PROPOSED (migration drafted, NOT executed). G5.7 cannot close until it is reviewed, applied live and the postflight matches.**

## Live backend audit (Phase 0)

| Item | Finding |
|---|---|
| `group_join_requests` schema | 5 columns: `id uuid PK`, `group_id uuid FK`, `user_id uuid FK`, `status text CHECK(pending/approved/declined)`, `created_at timestamptz`. `UNIQUE(group_id, user_id)`. |
| RLS policies | SELECT: own row OR MANAGE_MEMBERS. INSERT: `user_id = auth.uid()`. UPDATE: MANAGE_MEMBERS. **DELETE: NO POLICY**. |
| DELETE privilege | `GRANT DELETE ON group_join_requests TO authenticated` exists (migration 0033, line 363). The privilege is present; only the RLS policy is missing. |
| Existing functions | `fn_join_group` (upserts pending request for restricted groups), `fn_approve_group_join_request` (approve/decline). **No withdraw/cancel function exists.** |
| Triggers/constraints | `UNIQUE(group_id, user_id)` prevents duplicate requests. No expiry column, no `cancelled`/`withdrawn` status. |

## Decision → narrow RPC

A DELETE RLS policy would be broader than necessary. A SECURITY DEFINER RPC is the narrowest safe mechanism:

- authenticated only
- SECURITY DEFINER, `search_path = ''`
- derives `auth.uid()` from session (never client-supplied)
- accepts only the request id (no group_id from client)
- locks the row (`FOR UPDATE`)
- requires `user_id = auth.uid()` (owner check)
- requires `status = 'pending'` (cannot withdraw approved/declined)
- DELETEs exactly that one row
- returns `group_id` on success
- raises `JOIN_REQUEST_NOT_FOUND` on any failure (does not leak which condition)
- cannot: withdraw another user's request, withdraw approved/declined, affect `group_members` or `group_invitations`

## Exact SQL (`migrations/G5_7_fn_withdraw_join_request.sql`)

```sql
fn_withdraw_join_request(p_request_id uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
```

Body: `SELECT FOR UPDATE` → owner + pending check → `DELETE WHERE id = p_request_id` → `RETURN group_id`.

Grants: `REVOKE ALL FROM PUBLIC, anon; GRANT EXECUTE TO authenticated`.

Rollback: `DROP FUNCTION public.fn_withdraw_join_request(uuid)`.

## Security boundary

| Attack vector | Defence |
|---|---|
| Withdraw another user's request | `user_id = auth.uid()` check in the function |
| Withdraw approved/declined request | `status = 'pending'` check in the function |
| Cross-group forged request id | Function derives group from the row, not from client input |
| Manager abuse | Function only allows own requests; manager queue uses `fn_approve_group_join_request` |
| Non-member resolution | Not applicable — the function knows nothing about groups beyond the row |
| Direct DELETE bypass | No DELETE RLS policy exists; the RPC is the only path |

## Files changed

| File | Change |
|---|---|
| `migrations/G5_7_fn_withdraw_join_request.sql` | **New** — proposed SQL migration |
| `lib/features/group/data/group_repository.dart` | Added `withdrawJoinRequest(String requestId)` to interface + `SupabaseGroupRepository` (calls RPC) |
| `lib/features/group/state/group_list_controller.dart` | Added `withdrawJoinRequest(GroupJoinRequest)` method (single-flight, re-reads pending), extracted `_loadPendingRequests()` |
| `lib/features/group/screens/group_list_screen.dart` | Updated `_pendingBanner()` to show per-request Withdraw buttons with confirmation dialog |
| `lib/features/group/domain/group_errors.dart` | Added `JOIN_REQUEST_NOT_FOUND` error mapping |
| `test/group/fakes.dart` | Added `withdrawJoinRequest` to `InMemoryGroupRepository` (mirrors server contract) |
| `test/group/pending_join_test.dart` | Added 13 G5.7 tests (A–K, F2 failed-withdrawal-preserves-state, F3 re-apply after withdrawal) |
| `test/group/group_core_test.dart` | Added `withdrawJoinRequest` stub to `_FailingRepository` |

## UI flow

```
Group List Screen
  → Pending requests banner (when hasPendingRequests)
    → Each request shows: "Join request" + Withdraw button
      → Tap Withdraw → Confirmation dialog
        → "This will cancel your join request. You can submit a new request later if the group allows it."
        → Cancel / Withdraw
          → Server call: fn_withdraw_join_request(request_id)
            → Success: "Join request withdrawn." → pending list refreshed
            → Failure: error shown → pending list re-read from server
```

## Tests (13 new; 690 in the full suite, 186 under `test/group/`)

| Test | What it verifies |
|---|---|
| A | Own pending request can be withdrawn |
| B | Another user's request cannot be withdrawn |
| C | Approved request cannot be withdrawn |
| D | Declined request cannot be withdrawn |
| E | Cross-group forged request id cannot affect another request |
| F | Successful withdrawal refreshes state |
| G | Single-flight protection |
| H | Confirmation dialog required before mutation |
| I | Permission/auth failure handled gracefully |
| J | Operation never touches `group_members` |
| K | Operation never touches `group_invitations` |

## Validation

- `flutter analyze`: 0 errors / 0 warnings (67 pre-existing info-level hints)
- `flutter test`: **690 passed** (677 → 690; all G5.1–G5.6 and R4 suites green)
- `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json`: built
- R4 test system: untouched
- G3 permission engine: untouched
- G5.1–G5.6: untouched

## Known limitations / blocker

- **Blocker:** `fn_withdraw_join_request` does not exist live. Until applied, the Flutter withdraw call will fail with a "function does not exist" error (mapped to the generic join request error message).
- To apply: run `migrations/G5_7_fn_withdraw_join_request.sql` in the Supabase SQL Editor, then confirm the postflight.
- No live send executed for verification (permanent write).
- Not implemented by design: manager-initiated deletion of another user's request, expiry, notifications, G5.8.

## Final status

READY FOR CLAUDE VERIFICATION — apply `migrations/G5_7_fn_withdraw_join_request.sql` only after review; until then the Withdraw action fails live with the mapped generic message and nothing else in G5.2 changes.

## Claude verification (2026-09-18, commit a4e4cae)

**Code audit — PASS.** `withdrawJoinRequest` calls `fn_withdraw_join_request(p_request_id)` only; the three `.delete()` calls in the repository are the G1 leave/remove (`group_members`) and G5.5 cancel (`group_invitations`) paths, none on `group_join_requests`. Controller: pending-only guard, single-flight (`_actingWithdrawId`, plus `_busy` / invitation action lock), server re-read after success **and** failure, `_pendingCodes.clear()` on success, `DisposableNotifier` drops late notifications. Screen: per-request Withdraw disabled while acting/busy, confirmation dialog (`confirm_withdraw`), success/error snackbar. `JOIN_REQUEST_NOT_FOUND` → one generic message. No `group_members` / `group_invitations` mutation in the withdraw path.

**Migration review — PASS (unchanged since a4e4cae).** `fn_withdraw_join_request(p_request_id uuid) RETURNS uuid`, plpgsql, SECURITY DEFINER, `SET search_path TO ''`; `AUTH_REQUIRED` on null uid; `SELECT … FOR UPDATE` by exact id; `JOIN_REQUEST_NOT_FOUND` for missing / not owner / not pending (one non-leaking code); `DELETE … WHERE id = p_request_id`; returns `group_id`; `REVOKE ALL FROM PUBLIC, anon`; `GRANT EXECUTE TO authenticated`; read-only postflight last. No policy, table, trigger or enum statements (the only keyword hit is a comment line).

**Regression — PASS.** `flutter analyze` 0/0 · `flutter test` 690 passed (G5.1–G5.6, G3, R4 suites green) · debug APK built · no diff since a4e4cae.

**Live application / functional test — NOT PERFORMED.** This environment has no way to execute SQL against the live project (established since G0; every migration has been applied by the owner in the SQL Editor). The RPC therefore remains UNAPPLIED and the phase is BLOCKED.

### To close (owner, SQL Editor)
1. Paste the entire `migrations/G5_7_fn_withdraw_join_request.sql` and Run. Expected postflight row: `signature = fn_withdraw_join_request(uuid)`, `returns = uuid`, `definer = true`, `config = {search_path=}`, `vol = v`, `grants` containing `authenticated:EXECUTE` and no `anon`.
2. Read-only functional check as an authenticated identity, in ONE transaction that is rolled back (no live row is changed). Replace `<UID_A>` with your own `auth.users.id`, `<GROUP_A>` with a restricted group id you do NOT belong to, `<UID_B>` with another existing user id, `<GROUP_B>` another group id:
```sql
BEGIN;
SELECT set_config('request.jwt.claims', '{"sub":"<UID_A>","role":"authenticated"}', true);
SET LOCAL ROLE authenticated;
-- controlled rows (rolled back below)
INSERT INTO public.group_join_requests (group_id, user_id, status) VALUES ('<GROUP_A>', '<UID_A>', 'pending');
RESET ROLE;
INSERT INTO public.group_join_requests (group_id, user_id, status) VALUES ('<GROUP_B>', '<UID_A>', 'approved');
INSERT INTO public.group_join_requests (group_id, user_id, status) VALUES ('<GROUP_A>', '<UID_B>', 'pending');
SET LOCAL ROLE authenticated;
SELECT 'A_own_pending' AS test,
       public.fn_withdraw_join_request((SELECT id FROM public.group_join_requests WHERE group_id='<GROUP_A>' AND user_id='<UID_A>'))::text AS result;
SELECT 'C_row_gone', count(*)::text FROM public.group_join_requests WHERE group_id='<GROUP_A>' AND user_id='<UID_A>';
SELECT 'D_approved_rejected', (SELECT 'no exception' ) WHERE false; -- placeholder, see next lines
ROLLBACK;
```
   Because a raised exception aborts the transaction, run D/E/F/G as separate single statements after the block above, each expected to fail with `JOIN_REQUEST_NOT_FOUND` (nothing is deleted on failure):
```sql
-- D approved (own)            : SELECT public.fn_withdraw_join_request('<ID_OF_APPROVED_ROW>');
-- E declined (own)            : SELECT public.fn_withdraw_join_request('<ID_OF_DECLINED_ROW>');
-- F another user's pending    : SELECT public.fn_withdraw_join_request('<ID_OF_UID_B_ROW>');
-- G random / cross-group uuid : SELECT public.fn_withdraw_join_request(gen_random_uuid());
```
   H/I: `SELECT count(*) FROM public.group_members` and `FROM public.group_invitations` before and after must be equal. J: re-running A on a withdrawn id must fail with `JOIN_REQUEST_NOT_FOUND`.
3. Paste the postflight row and the A/C counts + the D–G error texts back; the phase then gets its second verification and closure.
