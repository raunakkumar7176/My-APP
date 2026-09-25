# FINAL REMEDIATION — FLUTTER + ACCEPTANCE READINESS Report

**Branch:** `r4-restart`
**Date:** 2026-09-20
**Author:** opencode automated agent

---

## 1. Executive Summary

This phase addressed all client-side remediation items (F-06, F-10, F-11, F-17) and prepared device acceptance documentation. Backend/security remediation is handled separately.

**Result:** All code changes complete. All tests pass. Device acceptance checklist ready.

---

## 2. Changes by Item

### F-06 — `p_invite_id` → `p_invitation_id`
**Status:** VERIFIED (pre-existing uncommitted fix by another agent)
- `lib/features/group/data/group_repository.dart:617,626` — `p_invite_id` already changed to `p_invitation_id` in `acceptInvitation` and `declineInvitation` RPC calls

### F-10 — Leaderboard: member sees "Your result" only
**Status:** IMPLEMENTED + TESTED

| File | Change |
|---|---|
| `lib/features/group/state/group_leaderboard_controller.dart` | Added `_canSeeFullLeaderboard` field, `canSeeFullLeaderboard` getter, permission probe via `permissionsFor(viewGroupAnalytics)` in `load()`. Owner bypass via `isOwner`. Import added for `group_permission.dart` |
| `lib/features/group/screens/group_leaderboard_screen.dart` | `_header()` conditionally shows full ranking (owner/analytics) vs "Your result" (member) without rank or participant count |
| `test/group/group_leaderboard_test.dart` | Added 3 controller tests (owner true, member false, leader with analytics true) + updated existing test to reflect permission probe |

### F-11 — Soft-deleted messages: "Message deleted" placeholder
**Status:** IMPLEMENTED + TESTED

| File | Change |
|---|---|
| `lib/core/models/group_message.dart` | Added `DateTime? deletedAt`, `bool get isDeleted`, updated `fromJson`/`toJson` |
| `lib/features/group/data/group_repository.dart` | `_messageColumns` now includes `deleted_at` |
| `lib/features/group/widgets/group_chat_section.dart` | `_bubble()` shows "Message deleted" italic placeholder when `isDeleted` |
| `test/group/group_chat_test.dart` | Added model parsing tests + 2 widget tests (deleted placeholder shown, normal messages unaffected) |

### F-17 — Documentation corrections
**Status:** COMPLETED

| File | Fixes |
|---|---|
| `docs/G17_GROUP_HUB_SECURITY_AUDIT_REPORT.md` | 4 errors: `group_rules` NOT LIVE, `fn_withdraw_join_request` VERIFIED, `fn_get_group_role` anon removed, "0 warnings" → "1 warning" |
| `docs/G18_ACCEPTANCE_MATRIX.md` | 3 `fn_leave_group` → "Direct DELETE on group_members (RLS self-leave policy)" |
| `docs/G18_ROLE_PERMISSION_MATRIX.md` | 1 `fn_leave_group` → Direct DELETE |

---

## 3. Quality Gates

### `flutter analyze`
- **Result:** 0 errors, 0 warnings
- **Info only:** 436 style hints (prefer_single_quotes, prefer_const_constructors) — no functional impact

### `flutter test`
- **Result:** 998 tests pass, 0 failures
- **Group tests:** 492 pass
- **Leaderboard tests:** 38 pass (including 3 new F-10 tests)
- **Chat tests:** F-11 tests pass

### `flutter build apk --debug`
- **Status:** PENDING — must run after all code changes

---

## 4. Device Acceptance Readiness

| Artifact | Status |
|---|---|
| `docs/G18_DEVICE_ACCEPTANCE_CHECKLIST.md` | 66 items, all unverified (ready for tester) |
| `docs/FINAL_DEVICE_ACCEPTANCE_RUNBOOK.md` | To be created (human-executable steps) |

---

## 5. What Was NOT Modified (by design)

- Supabase migrations / live database
- Backend security policies
- G19/G20 features (coach reports, analytics)
- Owner transfer, group deletion, logo storage
- AI worker, G12 backend
- Backend soft-delete semantics
- `node_modules/`, `package*.json`, `tool/`

---

## 6. Outstanding / Next Steps

1. **Run `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json`** — verify APK builds
2. **Execute device acceptance** — 66-item checklist on real Android device
3. **Backend agent** — complete server-side security remediation
4. **Final self-audit** — inspect git diff, verify no secrets committed

---

## 7. Files Changed

```
lib/features/group/state/group_leaderboard_controller.dart  (F-10: +import, +field, +getter, +probe)
lib/core/models/group_message.dart                          (F-11: +deletedAt, +isDeleted)
lib/features/group/data/group_repository.dart               (F-11: +deleted_at in _messageColumns)
lib/features/group/widgets/group_chat_section.dart           (F-11: +deleted placeholder)
test/group/group_leaderboard_test.dart                       (F-10: +3 tests, updated 1 test)
test/group/group_chat_test.dart                              (F-11: +model + widget tests)
docs/G17_GROUP_HUB_SECURITY_AUDIT_REPORT.md                 (F-17: 4 corrections)
docs/G18_ACCEPTANCE_MATRIX.md                               (F-17: 3 corrections)
docs/G18_ROLE_PERMISSION_MATRIX.md                          (F-17: 1 correction)
docs/G18_DEVICE_ACCEPTANCE_CHECKLIST.md                     (66 items ready)
docs/FINAL_REMEDIATION_FLUTTER_REPORT.md                    (this file)
```
