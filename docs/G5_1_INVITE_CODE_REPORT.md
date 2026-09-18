# G5.1 — Invite Code Management: Implementation Report

**Status: IMPLEMENTED (Flutter only). Backend changes: NONE.**

## Files changed
- `lib/features/group/data/group_repository.dart` — `inviteCode(groupId)` (single explicit `invite_code` column by exact id) and `rotateInviteCode(groupId)` (`fn_reset_group_invite(p_group)`; server value returned verbatim; no `rpcShape` log on this path).
- `lib/features/group/state/invite_code_controller.dart` — **new**. Owned only by the settings screen; load / retry / rotate (single-flight); `justRotated` cleared by any later action; code dropped on dispose.
- `lib/features/group/screens/group_settings_screen.dart` — Invite code section (loading, error + retry, code, Copy, Rotate with confirmation, success/error feedback). The controller is created **only after** the server-derived `canEditBasics` (GROUP_SETTINGS via `fn_has_permission`, or owner) is true.
- `lib/features/group/domain/group_errors.dart` — `GroupErrorContext.inviteCode` + authorization message.
- `test/group/fakes.dart` — invite-code read/rotate mirroring the live policy (`groups` row readable by members / public; rotation `GROUP_SETTINGS` or owner else `NOT_AUTHORIZED`), with read tracking.
- `test/group/invite_code_test.dart` — **new**, 10 tests. One stub added to `group_core_test.dart`'s `_FailingRepository`.

## Functionality
- Read: exact-id, single-column select, only from the gated settings flow. Not loaded by the group list, hub, members hub, profile, or discovery — proven by a test that pumps all three screens and asserts zero reads.
- Display: monospace selectable code, **Copy** (system clipboard, snackbar), **Rotate** (confirmation → `fn_reset_group_invite` → the returned code is displayed; "New code generated." shown only after a success; cleared on the next action/failure).
- States: initial loading; read failure with Retry; rotation single-flight; copy/rotate disabled while busy; failed rotation keeps the previous (still valid) code and shows the error.
- Permission boundary: UI gate = existing `canEditBasics`; the server (`groups` RLS + `fn_reset_group_invite`) remains authoritative; `NOT_AUTHORIZED` maps to a clear message.

## Tests
597 passing (587 → 597). Covered: authorized load; unauthorized member never triggers the read; list/hub/members never read it; copy uses the loaded code; rotation calls with the exact group id and displays the server value; single-flight; success updates the display; failure preserves state and shows the error; authorization error handled; `invite_code` absent from the `Group` model and list/hub rows even when present in the input JSON.

## Validation
`flutter analyze`: 0 errors / 0 warnings · `flutter test`: 597 passed · APK: built · `lib/features/test/`: untouched.

## Security notes
- The code is never logged: the repository does not call `rpcShape` on these paths, and the controller logs only failures.
- Not cached beyond the settings screen: `InviteCodeController` is created per screen and nulls the code on dispose. No global state, no JSON serialization, no debug report field.
- Live fact (unchanged): `groups.invite_code` is row-readable by every member, and by any signed-in user for `public` groups. The UI hides it from non-managers; the server does not. Tightening that would be a policy change and is out of scope.

## Known limitations
- No "disable invites" — rotation is the only invalidation the backend supports.
- No invite-code display for non-owner managers unless they hold `GROUP_SETTINGS` (a `role_permissions` row), which the live seeding grants to no role.
- No live write was executed for verification (rotation is a real, permanent change); read path uses the same `groups` SELECT policy already verified in G1.
