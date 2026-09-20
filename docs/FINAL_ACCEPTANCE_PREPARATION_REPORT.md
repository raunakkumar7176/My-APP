# Final Acceptance Preparation Report

**Date:** 2026-09-20
**Branch:** `r4-restart`
**Status:** FINAL ACCEPTANCE PREPARATION COMPLETE WITH FINDINGS

---

## 1. Baseline

- **Backend commit:** `ec8f5a0` (all security migrations applied)
- **Flutter state:** 0 errors, 0 warnings, 999 tests pass
- **APK:** `app-debug.apk` built successfully
- **Credential issue:** Plaintext passwords in `tool/` (now gitignored)

---

## 2. Files Changed (This Session)

| File | Change |
|---|---|
| `lib/features/group/screens/group_leaderboard_screen.dart` | F-10: conditional header — member sees "Your result" only |
| `test/group/group_leaderboard_test.dart` | F-10: updated member test, added owner + leader tests |
| `.gitignore` | Added `tool/` to prevent credential commits |
| `docs/FINAL_DEVICE_ACCEPTANCE_RUNBOOK.md` | Created — human-executable test steps |
| `docs/FINAL_ACCEPTANCE_MATRIX.md` | Created — 5-gate acceptance matrix |
| `docs/FINAL_PRODUCT_DECISIONS.md` | Created — locked + future decisions |
| `docs/CREDENTIAL_ROTATION_RUNBOOK.md` | Created — credential rotation steps |
| `docs/FINAL_ACCEPTANCE_PREPARATION_REPORT.md` | This file |

---

## 3. F-06 — Invitation Parameter Fix

**Status:** VERIFIED

- `group_repository.dart:618` — `fn_accept_group_invitation` uses `p_invitation_id`
- `group_repository.dart:627` — `fn_decline_group_invitation` uses `p_invitation_id`
- `group_repository.dart:746` — `fn_withdraw_join_request` uses `p_request_id`
- All invitation flows verified in controller and tests

---

## 4. F-10 — Leaderboard Conditional Display

**Status:** FIXED + TESTED

**Problem found:** The leaderboard screen always showed full ranking (participant count + "Your rank") to ALL users, including ordinary members.

**Fix applied:**
- `group_leaderboard_screen.dart` — `_header()` now checks `canSeeFullLeaderboard`
- Member sees: "Your result: X/Y · Z%" (no rank, no participant count)
- Owner/analytics sees: "N ranked participants" + "Your rank: N" + full list
- Entry list filtered: member sees only their own entry

**Tests updated:**
- Member test: asserts "Your result", no "Your rank", no "ranked participants"
- Owner test: asserts full leaderboard with participant count
- Leader test: asserts full leaderboard (has `viewGroupAnalytics` permission)

---

## 5. F-11 — Deleted Message Handling

**Status:** VERIFIED

- `GroupMessage.fromJson` — parses `deleted_at` from JSON
- `GroupMessage.isDeleted` — returns `deletedAt != null`
- `group_repository.dart:966` — `_messageColumns` includes `deleted_at`
- `group_chat_section.dart:185-221` — `_bubble()` shows "Message deleted" italic placeholder
- Original body is never rendered when `isDeleted` is true
- Tests: model parsing + widget tests for deleted placeholder

---

## 6. G6 — Group Rules Client

**Status:** VERIFIED

- Repository: `groupRules()`, `createRule()`, `updateRule()`, `deleteRule()`
- Controller: `createRule()`, `updateRule()`, `deleteRule()` with error handling
- Widget: `GroupRulesSection` with add/edit/delete UI
- Permission gate: `canEditSettings` check before mutations
- Cross-group protection: rules scoped by `groupId`
- Tests: full CRUD test coverage in `group_rules_test.dart`

---

## 7. G11 — Coach Reports Client

**Status:** VERIFIED

- Controller: `requestCoachReports()` calls `_results.requestCoachReports(testId)`
- Screen: "Request AI coach reports" button with loading state
- Job states: pending → processing → completed/failed
- Idempotency: duplicate request returns same job
- No AI worker: UI shows "queued/pending" state, no report content generated
- Tests: coverage in `group_test_results_test.dart`

---

## 8. Route Audit

**Status:** VERIFIED

All routes registered in `app_router.dart`:

| Route | Screen | Parameters |
|---|---|---|
| `/groups` | GroupListScreen | — |
| `/groups/create` | GroupCreateScreen | — |
| `/groups/join` | GroupListScreen(openJoinSheet) | — |
| `/groups/:groupId` | GroupHubScreen | groupId |
| `/groups/:groupId/members` | GroupMembersScreen | groupId |
| `/groups/:groupId/notifications` | GroupNotificationsScreen | groupId |
| `/groups/:groupId/settings` | GroupSettingsScreen | groupId |
| `/groups/:groupId/tests` | GroupTestsScreen | groupId |
| `/groups/:groupId/tests/:testId/results` | GroupTestResultsScreen | groupId, testId |
| `/groups/:groupId/tests/:testId/results/leaderboard` | GroupLeaderboardScreen | groupId, testId |
| `/tests` | TestListingScreen | — |
| `/tests/create` | TestCreationScreen | — |
| `/tests/:testId` | TestDetailScreen | testId |
| `/tests/:testId/edit` | TestCreationScreen | testId |
| `/attempts/:attemptId/take` | TestTakingScreen | attemptId |
| `/attempts/:attemptId/result` | TestResultScreen | attemptId |
| `/attempts/:attemptId/review` | QuestionReviewScreen | attemptId |

---

## 9. Device Acceptance Checklist

**Status:** 66 items prepared

- `docs/G18_DEVICE_ACCEPTANCE_CHECKLIST.md` — 66 items across sections A-J
- All items have: ID, screen/flow, precondition, action, expected result, security expectation, PASS/FAIL, observation
- No items marked PASS (pending physical device execution)

---

## 10. Device Acceptance Runbook

**Status:** Created

- `docs/FINAL_DEVICE_ACCEPTANCE_RUNBOOK.md` — human-executable steps
- Prerequisites: 6 test accounts, real Android device, test data setup
- Execution order: Sections A→J
- Evidence collection: screenshots for each section
- Failure recording: continue past failures, note deviations
- Cleanup instructions included

---

## 11. Final Acceptance Matrix

**Status:** Created

- `docs/FINAL_ACCEPTANCE_MATRIX.md` — 5 gates, 35 requirements
- A. Backend Security: 10/10 PASS
- B. Flutter Functional: 14/14 PASS
- C. Device Acceptance: BLOCKED (physical device needed)
- D. Credential Hygiene: BLOCKED (tool/ gitignore now applied)
- E. Product Decisions: 6/6 PASS

---

## 12. Product Decision Register

**Status:** Created

- `docs/FINAL_PRODUCT_DECISIONS.md` — locked + future decisions
- F-10 UX: LOCKED — "Your result" for members
- F-11 UX: LOCKED — "Message deleted" placeholder
- Owner transfer: Future roadmap
- Group deletion: Future roadmap
- Logo upload: Future roadmap
- AI worker: Future roadmap

---

## 13. Credential Rotation Runbook

**Status:** Created

- `docs/CREDENTIAL_ROTATION_RUNBOOK.md` — 6-step rotation process
- Issue: plaintext passwords in `tool/*.js` files
- Mitigation: `tool/` added to `.gitignore`
- Required: rotate Supabase database password
- Verification: `git grep` for old password

---

## 14. Tests

**Status:** 999 pass, 0 fail

- `flutter analyze`: 0 errors, 0 warnings
- `flutter test`: 999 pass, 0 fail
- New test added: `widget leader with analytics permission sees full leaderboard`
- Updated test: `widget member sees only their own result (F-10)`

---

## 15. APK Build

**Status:** SUCCESS

```
flutter build apk --debug --dart-define-from-file=dart-defines.dev.json
√ Built build\app\outputs\flutter-apk\app-debug.apk
```

---

## 16. Remaining Blockers

| Blocker | Impact | Resolution |
|---|---|---|
| Physical device acceptance not started | Cannot verify 66 acceptance items | Execute on real Android device |
| `tool/` credentials not rotated | Old password still valid | Rotate in Supabase dashboard |
| Backend security re-audit pending | Backend changes not independently verified | Backend agent to complete |

---

## 17. Exact Commit Hash

**Pending** — changes not yet committed.

Files to commit:
- `.gitignore`
- `lib/features/group/screens/group_leaderboard_screen.dart`
- `test/group/group_leaderboard_test.dart`
- `docs/FINAL_DEVICE_ACCEPTANCE_RUNBOOK.md`
- `docs/FINAL_ACCEPTANCE_MATRIX.md`
- `docs/FINAL_PRODUCT_DECISIONS.md`
- `docs/CREDENTIAL_ROTATION_RUNBOOK.md`
- `docs/FINAL_ACCEPTANCE_PREPARATION_REPORT.md`

---

## Final Status

**FINAL ACCEPTANCE PREPARATION COMPLETE WITH FINDINGS**

Physical device acceptance remains pending until a real Android device executes all 66 checks.
Credential hygiene requires rotating the Supabase database password and removing plaintext credentials from `tool/`.
