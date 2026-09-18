# G5.2 — Pending Join Lifecycle: Implementation Report

**Status: IMPLEMENTED (Flutter only). Backend changes: NONE.**
**G5.3 manager request queue is NOT implemented.** No approval/decline UI, no withdrawal (G5.7), no expiry.

## Files changed
- `lib/core/models/group_join_request.dart` — **new**. Exactly the live columns: `id, group_id, user_id, status (pending|approved|declined), created_at`. No other field is modelled; extra keys in a row are ignored.
- `lib/features/group/data/group_repository.dart` — `myJoinRequest(groupId)` (exact `group_id` + caller's `user_id`, `maybeSingle` on the UNIQUE pair) and `myPendingJoinRequests()` (caller's own `status = 'pending'` rows). Both select only the five live columns; neither lists other users' rows.
- `lib/features/group/state/group_list_controller.dart` — `pendingRequests` / `hasPendingRequests` (one own-rows query alongside `myGroups`, failure-tolerant), `isCodePending(code)` session guard, `joinByCode` re-reads pending rows after a NULL outcome.
- `lib/features/group/widgets/join_group_sheet.dart` — pending banner ("You have N join request(s) awaiting approval"), "Join request pending" copy after NULL when the server returned the row, the previous "Request sent" copy when it did not.
- `lib/features/group/screens/group_list_screen.dart` — compact "N join request(s) pending" card (no link; count only).
- `test/group/fakes.dart` — join-request rows keyed `(group, user)` with the own-rows SELECT mirror; `fn_join_group` restricted path upserts `pending`.
- `test/group/pending_join_test.dart` — **new**, 13 tests. Two stubs in `group_core_test.dart`'s `_FailingRepository`.

## Functionality / state transitions
| From | Event | To |
|---|---|---|
| idle | submit (blank) | validation error |
| idle | submit, `fn_join_group` → uuid | **joined** → hub opened (existing) |
| idle | submit, uuid for an existing member | joined (`alreadyMember`) — idempotent |
| idle | submit, `fn_join_group` → NULL | **pending**: own pending rows re-read; sheet shows "Join request pending" (row present) or "Request sent" (no row yet); hub **not** opened |
| pending | same code again | refused client-side ("already pending"), no server call |
| pending | different code | normal submit |
| any | `INVALID_INVITE_CODE` | mapped invalid-invite message |
| any | network/other failure | mapped generic error; retry by resubmitting |
| pending | manager declines/approves externally | next load/refresh re-reads own rows and `rpc_get_user_groups`; membership (not the request) decides access |

## Repository / data contract
`group_join_requests` reads: `select('id, group_id, user_id, status, created_at').eq('group_id', id).eq('user_id', uid).maybeSingle()` and `.eq('user_id', uid).eq('status','pending').order('created_at')`. `fn_join_group(p_invite_code)` unchanged from G1. The NULL contract is handled as the verified restricted-group case only.

## Security boundary
- A pending request is never treated as membership; `groupForMember` (a `group_members` row) remains the only hub gate — tested: a user with only a pending request gets "Group not available".
- No request row of another user is ever requested; the list read is the caller's own rows (the live SELECT policy is the boundary).
- No group id from a pending request is used to open anything; restricted groups are not readable to non-members, so the list shows a count, not names.
- No new RPC, no broad listing, no N+1 (one query per list load).

## Tests
610 passing (597 → 610). Covered: A joined path; B NULL → own pending read; C pending state; D duplicate submit blocked; E pending never opens hub (router + hub screen); F invalid code; G idempotent existing member; H external approve/decline → server decides; I exact-id / own-rows reads; J parser matches only live columns; K no `invite_code` in Group payloads; plus pending-read failure never hides the groups list, and the "no row returned" fallback copy.

## Validation
`flutter analyze`: 0 errors / 0 warnings · `flutter test`: 610 passed · APK: built · `lib/features/test/` and the G3 permission engine: untouched · G5.1 tests unchanged and green.

## Known limitations
- The pending card cannot name the group: a restricted group's row is unreadable to a non-member under the live SELECT policy.
- The duplicate-code guard is session-scoped (the server upsert is idempotent regardless).
- No withdrawal (no live DELETE policy — G5.7) and no expiry (not supported live).
- No live restricted join was executed for verification (it writes a permanent request row).
