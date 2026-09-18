# G5.3 — Manager Join-Request Queue: Implementation Report

**Status: IMPLEMENTED (Flutter only). Backend changes: NONE.**

**G5.5 outgoing invitation management is NOT implemented.**
**G5.6 send invitation is NOT implemented.**
**G5.7 withdraw request is NOT implemented.**
**G5.8 final lifecycle hardening is NOT implemented.**

## Files changed
- `lib/features/group/data/group_repository.dart` — `pendingJoinRequests(groupId)` (exact `group_id`, `status='pending'`, five live columns, RLS decides visibility) and `decideJoinRequest(requestId, approve:)` → `fn_approve_group_join_request(p_request_id, p_approve)`. No direct writes to `group_members` or `group_join_requests`.
- `lib/features/group/domain/group_errors.dart` — `GroupErrorContext.joinRequest` + permission message.
- `lib/features/group/state/group_hub_controller.dart` — `joinRequests`, `pendingRequestCount`, `joinRequestsLoading`, `joinRequestsError`, `retryJoinRequests`, `actingRequestId`, `decideJoinRequest(request, approve:)`. The queue is loaded inside `load()` **only when the server-reported `MANAGE_MEMBERS` is true**; otherwise it is never queried.
- `lib/features/group/widgets/join_request_queue.dart` — **new**. Heading + count badge, loading / error+Retry / empty / items with Approve and Decline (confirmation dialogs).
- `lib/features/group/screens/group_hub_screen.dart` — queue mounted above Members, only when `canManageMembers`.
- `test/group/fakes.dart` — live mirrors of the SELECT policy (own row OR MANAGE_MEMBERS) and of the function (group derived from the row; `NOT_AUTHORIZED` otherwise; approve inserts membership). `test/group/join_request_queue_test.dart` — **new**, 16 tests. Two stubs in `group_core_test.dart`.

## Repository contracts
`group_join_requests` SELECT under the live policy; `fn_approve_group_join_request(uuid, boolean)`; existing `groupForMember` / `members` / `permissionsFor` for the post-approval reload. `GroupJoinRequest` unchanged from G5.2 (five live columns).

## Permission behaviour
UX gate = `permissions.canManageMembers` from `fn_has_permission(MANAGE_MEMBERS)` (owner true by the function's own branch; leader true by live seeding). Members without it never trigger the read, see no queue, and `decideJoinRequest` refuses before any call. Role names are not used as authorization. Server (RLS + function) remains authoritative.

## Queue behaviour
Loaded once per hub load for managers (no per-group calls on the Groups list, no second count query — the badge is the queue length). States: loading, error with Retry (isolated: the hub still renders), empty ("No pending requests."), items.

## Approve flow
Confirm → `decideJoinRequest(id, approve: true)` → full hub reload → the new member appears from the `group_members` row the function inserted; member count re-read from the server; queue re-read; success snackbar. No local membership insert.

## Decline flow
Confirm → `decideJoinRequest(id, approve: false)` → queue re-read → success snackbar. No membership touched (tested: an existing member is unaffected).

## Requester identity handling
Not shown. A pending requester is not a member, so their `profiles` row is not readable under the live "own row OR fellow member" policy, and no verified path resolves it without a new RPC. Items are "Join request · Requested <date time>". No profile query was introduced.

## Security boundaries
- Only the request id is sent; the client never passes a group id as authorization. The server derives the group from the row and checks `MANAGE_MEMBERS` there — tested with a forged row whose `groupId` lies (refused; the other group's request stays pending).
- RLS controls which rows are readable; the client never reads across groups.
- Any mutation error → mapped message + server re-read; no status transition is fabricated (tested: a request decided by another manager disappears after the re-read).
- Per-request single-flight; global mutations also disable the queue's buttons.

## Tests
642 passing (626 → 642). A manager loads exact-group rows · B non-manager never queries / cannot decide · C leader sees the queue · D empty · E loading · F error + retry · G item renders controls · H exact id + true · I exact id + false · J single-flight · K approve refreshes queue + count + members · L decline refreshes queue · M stale/failed → re-read · N no local membership insert · O decline removes nothing · P requester not treated as member · Q no profile query · R cross-group refused with request-id-only call · S G5.1/G5.2/G5.4 unchanged and green · T grep confirms no G5.5–G5.7 symbols.

## Validation
`flutter analyze`: 0 errors / 0 warnings · `flutter test`: 642 passed · APK: built · `lib/features/test/` and the G3 permission engine: untouched.

## Known limitations
- Requester cannot be named (RLS); would need the G5.6-class lookup RPC or a policy change — neither introduced.
- No realtime; explicit refresh after mutations only.
- No requester withdrawal (G5.7) and no expiry (unsupported live).
- No live approve/decline executed for verification (permanent writes).
