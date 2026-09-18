# G5.5 — Outgoing Invitation Management: Implementation Report

**Status: IMPLEMENTED (Flutter only). Backend changes: NONE.**

**G5.6 send invitation is NOT implemented.**
**G5.7 withdraw join request is NOT implemented.**
**G5.8 final lifecycle hardening is NOT implemented.**

**Declined re-invite: SAFELY IMPLEMENTED** as the two-step DELETE + INSERT the live policies permit (see "Re-invite behaviour"); it is not atomic, and a failure after the first step is reported explicitly, never silently.

## Files changed
- `lib/features/group/data/group_repository.dart` — `groupInvitations(groupId)` (exact `group_id`, all statuses, six live columns), `cancelInvitation(id)` (exact-row DELETE returning the deleted id; **0 rows ⇒ error**, never a silent success), `reinvite(declined)` (DELETE declined row → INSERT `{group_id, inviter_id: uid, invitee_id}`; a failing second step throws a `DataError` prefixed with `reinviteIncompletePrefix`).
- `lib/features/group/state/group_hub_controller.dart` — `outgoingInvitations`, `outgoingLoading`, `outgoingError`, `retryOutgoingInvitations`, `actingInvitationId`, `canReinvite(inv)`, `cancelInvitation(inv)`, `reinvite(inv)`. Loaded inside `load()` **only when server-reported `MANAGE_MEMBERS` is true**.
- `lib/features/group/widgets/outgoing_invitations_section.dart` — **new**. "Sent invitations" with pending count; loading / error+Retry / empty / items ("Invitation · Sent <when>", status verbatim); Cancel on pending, Re-invite on declined (non-member invitee), nothing on accepted/expired; confirmation dialogs.
- `lib/features/group/screens/group_hub_screen.dart` — section mounted (managers only), separate from the G5.3 join-request queue and from G5.4 incoming invitations.
- `test/group/fakes.dart` — mirrors of the live SELECT/DELETE/INSERT policies and `UNIQUE(group_id, invitee_id)`, plus `failInsertWith` for the two-step failure. `test/group/outgoing_invitations_test.dart` — **new**, 18 tests. Three stubs in `group_core_test.dart`.

## Repository contract
- **A. invitations sent by the current user** and **B. invitations visible to a manager** are both served by the same live SELECT policy (`invitee ∨ inviter ∨ fn_is_member`) on an exact-`group_id` read; the client requests it only for `MANAGE_MEMBERS` holders and filters status locally for display. No cross-group query, no profile query, no RPC.
- Cancel: `delete().eq('id', id).select('id')` — DELETE policy `inviter_id = uid OR MANAGE_MEMBERS`.
- Re-invite: `cancelInvitation` then `insert` — INSERT policy `inviter_id = uid AND MANAGE_MEMBERS`; the re-inviting manager becomes the inviter.

## Outgoing list behaviour
Loaded once per hub load for managers; states loading, error with Retry (isolated — the hub still renders), empty, list. Ordinary members never trigger the read and never see the section.

## Permission behaviour
UX gate = `permissions.canManageMembers` from `fn_has_permission`. Role names are not used. RLS remains authoritative: a manager of group A cancelling a group B row gets 0 rows deleted → mapped error (tested with a forged row that lies about its group; only the invitation id is sent).

## Status behaviour
`pending` → Cancel · `accepted` → no action · `declined` → Re-invite (only if the invitee is not already in the roster) · `expired` → no action. The server status string is displayed verbatim; nothing computes, dates, or times out an expiry.

## Cancel behaviour
Confirm → exact-id DELETE → list re-read from the server (success or failure). Single-flight per invitation; global mutations disable the buttons. No `group_members` or `group_join_requests` change.

## Re-invite behaviour
Only for `declined` rows whose invitee is not a member; never for pending/accepted/expired. Confirm (the dialog states the two-step nature) → step 1 DELETE the declined row → step 2 INSERT a new pending row. Outcomes: both succeed → new pending row (one row per `(group, invitee)`); step 1 fails → declined row untouched, nothing inserted, error shown; **step 2 fails → the user is told explicitly that the declined record was removed and nothing is pending**, and the list is re-read. Nothing is lost silently and no atomicity is claimed. A transactional RPC would remove the window; that is the only improvement a backend change could add (G5.6/G5.8 scope).

## Security boundary
Member cannot load the manager list (never queried; RLS would still limit rows) · invitation id never authorizes anything — the DELETE/INSERT policies do · only exact-group reads · no cross-group mutation · no `group_members` / `group_join_requests` mutation · no profile enumeration · no expiry fabricated · no client-generated ids (`id` defaults server-side) · no RPC · no RLS bypass.

## Tests
660 passing (642 → 660). A manager loads exact-group rows · B member never queries · C exact group_id · D empty · E loading · F error + retry · G pending shows Cancel · H accepted no Cancel · I declined shows Re-invite · J expired no Cancel, no expiry behaviour · K exact-id delete · L single-flight · M success re-reads · N failure re-reads · O re-invite never targets pending/accepted/expired (nor a member) · P UNIQUE respected (one row per invitee after re-invite) · Q step-2 failure reported explicitly, plus step-1 failure leaves the declined row · R/S no resolver, no profile query · T cross-group cancel rejected · U G5.1–G5.4 unchanged and green · V grep confirms no G5.6/G5.7 symbols.

## Validation
`flutter analyze`: 0 errors / 0 warnings · `flutter test`: 660 passed · APK: built · `lib/features/test/` and the G3 permission engine: untouched.

## Known limitations
- Invitee cannot be named (RLS; needs the G5.6 lookup).
- Re-invite is two-step and non-atomic by design of the live schema; the failure window is surfaced, not hidden.
- New invitations to arbitrary users are not possible until G5.6.
- No live cancel/re-invite executed for verification (permanent writes).
