# G5.4 — Incoming Group Invitations: Implementation Report

**Status: IMPLEMENTED (Flutter only). Backend changes: NONE.**

**G5.3 manager join-request queue is NOT implemented.**
**G5.5 outgoing invitation management is NOT implemented.**
No invitation creation, cancellation, expiry, or join-request approval UI exists in this phase.

## Files changed
- `lib/core/models/group_invitation.dart` — **new**. Exactly the live columns: `id, group_id, inviter_id, invitee_id, status (pending|accepted|declined|expired), created_at`. No `expiresAt`/`updatedAt`/names; extra keys in a row are ignored. Nothing added to `Group`.
- `lib/features/group/data/group_repository.dart` — `myInvitations()` (`invitee_id = uid AND status = 'pending'`, the six live columns, one query), `acceptInvitation(id)` → `fn_accept_group_invitation(p_invite_id)`, `declineInvitation(id)` → `fn_decline_group_invitation(p_invite_id)`. No direct writes to `group_invitations` or `group_members`.
- `lib/features/group/domain/group_errors.dart` — `GroupErrorContext.invitation`; `INVITE_NOT_FOUND` → "This invitation is no longer available." (no cause claimed).
- `lib/features/group/state/group_list_controller.dart` — `invitations`, `invitationsLoading`, `invitationsError`, `retryInvitations`, `actingInvitationId` (single-flight), `acceptInvitation(inv)` (returns the group id **only if it appears in `rpc_get_user_groups` after the refresh**), `declineInvitation(inv)`; any action error re-reads the caller's own rows.
- `lib/features/group/widgets/incoming_invitations_section.dart` — **new**. Loading / error+Retry / empty / list; per-row Accept and Decline (confirmation) for pending rows only; non-pending rows show the server status text and no controls.
- `lib/features/group/screens/group_list_screen.dart` — section mounted above the groups; on a confirmed accept the hub is opened by the id from the refreshed membership list.
- `test/group/fakes.dart` — invitation rows with the live SELECT/function mirrors. `test/group/incoming_invitations_test.dart` — **new**, 16 tests. Three stubs in `group_core_test.dart`'s `_FailingRepository`.

## Repository contracts used
`group_invitations` SELECT under the live policy (invitee ∨ inviter ∨ member) — the client asks only for its own invitee rows; `fn_accept_group_invitation(uuid)`; `fn_decline_group_invitation(uuid)`; `rpc_get_user_groups()` for the post-accept membership refresh.

## UI behaviour
The Groups screen shows "N invitation(s)" with one card per pending invitation: "Group invitation · Received <date time>" and Accept / Decline. Group name and inviter name are **not** shown — a non-member cannot read a private/restricted group's row and no verified path resolves them without a new RPC, so nothing RLS withholds is requested or guessed. Loading, empty (section hidden), error with Retry, and duplicate-action protection (all buttons disabled while one action runs) are implemented. The section's failure never hides the groups list.

## Accept flow
Accept → single-flight → `fn_accept_group_invitation(id)` → full reload (`myGroups` + invitations + pending requests) → if the invitation's `group_id` is now in the membership list the hub is opened, otherwise "Invitation accepted. Pull to refresh your groups." No local membership is ever marked before the RPC succeeds, and no client-supplied group id is used for navigation.

## Decline flow
Decline → confirmation → single-flight → `fn_decline_group_invitation(id)` → invitations re-read → feedback. Declining touches no membership.

## Security boundaries
- Invitation id is never authorization; the functions check invitee + pending server-side.
- Hub access remains `groupForMember` (a `group_members` row) — tested: an invitee who has not accepted gets "Group not available".
- Only the caller's invitee rows are requested; no other user's invitations, no broad RPC, no N+1.
- `INVITE_NOT_FOUND` (not pending / decided / removed / inaccessible) is mapped generically and the list is refreshed from the server.

## Tests
626 passing (610 → 626). A own-rows single read · B pending renders controls · C empty · D loading · E read failure + retry (controller and card) · F exact id on accept · G/K single-flight · H refresh + membership-confirmed hub open · I no hub via invitation alone / null when membership not visible · J exact id on decline, no membership · L `INVITE_NOT_FOUND` stale handling · M non-pending rows show no controls · N parser only live columns · O no expiry UI · P no invitation data in `Group` · Q no broad query · R G5.1/G5.2 suites unchanged and green.

## Validation
`flutter analyze`: 0 errors / 0 warnings · `flutter test`: 626 passed · APK: built · `lib/features/test/` and the G3 permission engine: untouched.

## Known limitations
- Cards cannot name the group or inviter (RLS; would need the G5.6-class RPC or a policy change — neither introduced).
- `expired` is displayed only if the server returns it; nothing computes or dates expiry.
- The accept path opens the hub only when the refreshed membership list contains the group; otherwise the user opens it from the list.
- No live accept/decline executed for verification (permanent writes).
