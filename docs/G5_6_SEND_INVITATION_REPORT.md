# G5.6 — Send Invitation: Implementation Report

**Status: FLUTTER IMPLEMENTED — BLOCKED ON ONE BACKEND RESOLVER (proposed, NOT executed).**
**G5.6 is NOT COMPLETE until `rpc_find_profile_by_student_code` is verified/applied live and the live lookup is observed.**

## Live backend audit (Phase 0)
Evidence = the migration set that built the live database (`My-Prepration/supabase/migrations`, [LEGACY-SQL]) plus prior live verifications; the read-only confirmation is `migrations/G5_6_VERIFY.sql` (one SELECT, nothing writes).

| Item | Finding |
|---|---|
| A. `profiles` identity columns | `id, full_name, avatar_url, student_code` (plus `bio, mobile, exam_targets, timezone, created_at` — never selected by G5.6) |
| B. `student_code` uniqueness | **UNIQUE index `profiles_student_code_key (student_code)`** created in `0007` and re-asserted in `0033`; codes are generated as `MP-` + 5 upper hex by `fn_next_student_code`. The verify grid prints the index text and a duplicate count. |
| C. Existing resolver | **None.** Only `fn_next_student_code`, `fn_set_student_code`, `fn_ensure_student_code` exist (they generate/assign codes). The legacy web client never sent invitations by code. `profiles` SELECT policies are `own row OR fellow member OR test participant`, so a manager cannot resolve a stranger via the table. |
| D. Invitation functions / INSERT policy | `fn_accept_group_invitation(uuid)`, `fn_decline_group_invitation(uuid)` unchanged (G5.4). INSERT policy: `inviter_id = auth.uid() AND fn_has_permission(group_id, uid, 'MANAGE_MEMBERS')`. No creation RPC exists → direct INSERT is the live-supported path. |
| E. Membership helpers | `fn_is_member(uuid,uuid)`, `fn_has_permission(uuid,uuid,app_permission)` — live-verified in G1/G3. |

## Decision gate → PATH B
No safe resolver exists; `student_code` is unique by index. One narrowly scoped resolver is genuinely required.

### Exact SQL (proposed — `migrations/G5_6_rpc_find_profile_by_student_code.sql`, NOT executed)
`rpc_find_profile_by_student_code(p_code text) RETURNS TABLE(id uuid, full_name text, avatar_url text, student_code text)` — `LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO ''`; body: exact match on `public.profiles.student_code = upper(trim(p_code))`, `auth.uid() IS NOT NULL`, `LIMIT 1`; `REVOKE ALL FROM PUBLIC, anon`; `GRANT EXECUTE TO authenticated`; postflight prints definer/config/volatility/grants and `student_code_unique`. Returns nothing else — no email, mobile, bio, exam targets, group data, invite codes, auth data. No table/policy/trigger/enum change. Rollback: `DROP FUNCTION`.

Apply order: run `G5_6_VERIFY.sql` → confirm `unique_check` shows the UNIQUE index and `duplicate_student_codes = 0` and no resolver row exists → apply the resolver file → confirm postflight.

## Invitation creation contract (Phase 2)
Client sends `{group_id, invitee_id, inviter_id: session uid}` (the policy requires `inviter_id = auth.uid()`; it is supplied from the session, never user input). Only `group_invitations` is written. `UNIQUE(group_id, invitee_id)` → mapped "An invitation for this person already exists in this group." The G5.5 `reinvite` now reuses the same `sendInvitation` primitive.

## Files changed
- `lib/core/models/profile_match.dart` — **new**; exactly the four resolver fields.
- `lib/features/group/data/group_repository.dart` — `findProfileByStudentCode(code)` (RPC; logs shape only, never values), `sendInvitation(groupId:, inviteeId:)`; `reinvite` refactored onto it.
- `lib/features/group/domain/group_errors.dart` — duplicate-key mapping in the invitation context.
- `lib/features/group/state/invite_member_controller.dart` — **new**; explicit Search (single-flight, trimmed), pre-send `InviteeState` (self / member / pending / accepted / declined / expired / canInvite) derived from the hub's roster + outgoing list, Send (single-flight, server-confirmed), match discarded on dispose (no global cache).
- `lib/features/group/state/group_hub_controller.dart` — `repository` getter so the sheet shares the hub's data source.
- `lib/features/group/widgets/invite_member_sheet.dart` — **new**; code input, Search, match card (avatar, name, code), state label, confirm dialog, Send.
- `lib/features/group/screens/group_hub_screen.dart` — "Invite member" app-bar action shown only when `canManageMembers`; hub refreshed after a send.
- `migrations/G5_6_rpc_find_profile_by_student_code.sql` (proposed), `migrations/G5_6_VERIFY.sql` (read-only).
- `test/group/fakes.dart` (resolver + INSERT/UNIQUE mirrors), `test/group/send_invitation_test.dart` — **new**, 17 tests; two stubs in `group_core_test.dart`.

## UI flow
Group Hub → Invite member (manager only) → sheet → Student code → **Search** (explicit, not per keystroke) → match card → Send invitation → confirm → server INSERT → "Invitation sent." → sheet closes → hub reloads (outgoing list shows the pending row).

## Pre-send validation (Phase 3)
1 unknown code → "No user found with that student code." · 2 member → refused, labelled · 3 pending → refused, labelled; server UNIQUE also refuses · 4 declined → refused with pointer to G5.5 Re-invite (old row never mutated silently) · 5 accepted → refused as already invited · 6 expired → refused, explicit that the existing row blocks a new one; no expiry logic · 7 forged group → INSERT policy refuses (fake mirror tested). Server remains authoritative for all of them.

## Security findings
- Lookup is exact-match, one row, four identity fields, authenticated only; nothing about groups leaks (the resolver knows no group). Code guessing is bounded by the 16^5 space and by Supabase rate limits, not by this client.
- Non-managers never open the sheet, so the lookup is never triggered for them; the RPC would still refuse nothing for them by itself — it is a public-identity lookup by design, same as showing the code on the profile screen.
- Invitation creation touches only `group_invitations`; `group_members` and `group_join_requests` are provably untouched (tests R/S).
- The match is held only by the sheet's controller and nulled on dispose; nothing logged beyond the response shape.

## Tests
677 passing (660 → 677). A manager sees Invite · B member never looks up · C trimmed/upper-cased · D/Q only identity fields · E not found · F/G/H send with session inviter and current group · I single-flight · J hub outgoing refreshed · K pending handled + UNIQUE · L member handled · M declined explicit · N expired explicit, no logic invented · O/P forged group / non-manager refused by INSERT policy · R/S no members / requests touched · T G5.1–G5.5 green (677 total).

## Validation
`flutter analyze`: 0 errors / 0 warnings · `flutter test`: 677 passed · APK: built · `lib/features/test/` and the G3 engine: untouched.

## Known limitations / blocker
- **Blocker:** the resolver does not exist live. Until `G5_6_VERIFY.sql` confirms uniqueness/no-resolver and the proposed function is applied, `findProfileByStudentCode` will fail live with a "function does not exist" error (mapped to the generic invitation message). Everything else in the flow is live-supported today.
- If the verify grid shows `student_code` is **not** unique, do not apply the resolver; report back and the phase stops there (no Flutter uniqueness rule will be invented).
- No live send executed for verification (permanent write).
- Not implemented by design: email/SMS/phone/link/new-user invitations, expiry, notifications, G5.7, G5.8.
