# G18 — Group Hub Acceptance Preparation Report

## Status
PREPARATION COMPLETE — NOT FINAL VERIFICATION
This is G18 PREPARATION, not final production verification.

## Current Test Count
- **Previous (G15 baseline):** 932 tests passing
- **New G18 acceptance tests:** 50 tests
- **Total:** 982 tests passing
- **flutter analyze:** 0 errors, 0 warnings, 438 info-level hints
- **APK build:** SUCCESS (debug APK built)

## Existing G1–G16 Coverage
All G1–G16 phases have existing automated test coverage:
- G1: group_core_test.dart (model parsing, controller access, leave/remove, screens)
- G2: group_settings_test.dart (settings screen, logo)
- G3: group_roles_test.dart (role parsing, permissions, role change)
- G4: group_members_test.dart (member list, search, filter)
- G5: invite_code_test.dart, pending_join_test.dart, join_request_queue_test.dart, incoming_invitations_test.dart, outgoing_invitations_test.dart, send_invitation_test.dart
- G6: group_rules_test.dart (rules CRUD)
- G7: group_announcements_test.dart (announcements CRUD)
- G8: group_chat_test.dart (chat send/receive/pagination)
- G9: (integrated into G10 tests)
- G10: group_tests_management_test.dart (test management)
- G11: group_test_results_test.dart (results)
- G12: group_leaderboard_test.dart (leaderboard)
- G13: group_settings_test.dart (rules/members summaries)
- G14: group_controls_test.dart (management controls)
- G15: group_membership_edge_cases_test.dart (edge cases)
- G16: group_notifications_test.dart (notifications, badge)

## New Tests Added (G18)
File: test/group/group_acceptance_test.dart — 50 tests

### Journey A: Group Creation → Hub Entry → Full Hub Load (2 tests)
- Create group, enter hub, verify all sections loaded
- Create restricted group, join by code files request

### Journey B: Permission Visibility Across Roles (6 tests)
- Member sees no management controls
- Leader sees management controls from seeded permissions
- Non-member sees access denied
- Moderator has no default permissions
- Hub renders management section only for authorized users (widget)
- Hub renders no management section for plain member (widget)

### Journey C: Invitation Flow (2 tests)
- Send → accept → membership appears
- Decline → no membership

### Journey D: Join Request Flow (2 tests)
- Restricted join → approve → membership
- Restricted join → decline → no membership

### Journey E: Role Change → Permission Propagation (5 tests)
- Promote member to leader
- Demote leader to member
- Leader cannot change roles
- Cannot assign owner role
- Cannot self-change role

### Journey F: Settings Update → Refresh (4 tests)
- Owner edits name, hub refreshes
- Member cannot edit
- Empty name rejected client-side
- Backend failure surfaces error

### Journey G: Chat Send → Receive (6 tests)
- Member sends message, appears in chat
- Empty message rejected
- System message shows System label
- Former member shows Former label
- Non-member cannot send
- Single-flight: concurrent sends are dropped

### Journey H: Announcements (3 tests)
- Owner creates, member reads
- Member cannot create
- Owner deletes

### Journey I: Rules (4 tests)
- Owner creates rule, member reads
- Member cannot create rule
- Owner edits rule
- Owner deletes rule

### Journey J: Leave / Remove (5 tests)
- Member leaves, hub shows access denied
- Owner cannot leave
- Owner removes member, roster refreshes
- Cannot remove owner
- Plain member cannot remove others

### Journey K: Notification Badge (3 tests)
- Unread count shown, cleared after mark all
- No notification repo means no badge
- Another user's rows not counted

### Journey L: State Reset After Leave/Remove (3 tests)
- Leave clears all hub state
- Owner removed clears permissions
- Leader demotion removes management controls

### Journey M: Cross-Group Isolation (2 tests)
- Operations on g-1 do not leak to g-2
- Cannot send message to wrong group

### Journey N: Error Recovery (2 tests)
- Hub refresh succeeds normally
- clearError removes error state

### Journey O: Hub Refresh After Sub-Screen (1 test)
- Refresh reloads all sections

## Acceptance Matrix
See: docs/G18_ACCEPTANCE_MATRIX.md

## Role/Permission Matrix
See: docs/G18_ROLE_PERMISSION_MATRIX.md

## Device Acceptance Checklist
See: docs/G18_DEVICE_ACCEPTANCE_CHECKLIST.md

## E2E Test Plan
See: docs/G18_GROUP_HUB_E2E_PLAN.md

## Route / Navigation Audit
All Group Hub routes verified:
- /groups — GroupListScreen
- /groups/create — GroupCreateScreen
- /groups/join — GroupListScreen(openJoinSheet: true)
- /groups/:groupId — GroupHubScreen
- /groups/:groupId/members — GroupMembersScreen
- /groups/:groupId/notifications — GroupNotificationsScreen
- /groups/:groupId/settings — GroupSettingsScreen
- /groups/:groupId/tests — GroupTestsScreen
- /groups/:groupId/tests/:testId/results — GroupTestResultsScreen
- /groups/:groupId/tests/:testId/results/leaderboard — GroupLeaderboardScreen

All routes use groupId path parameter correctly. No cross-group navigation bypass. Safe back navigation after leave/remove (go('/groups')).

## Known Backend Dependencies
- fn_create_group (G1)
- fn_join_group (G5)
- fn_approve_group_join_request (G5.3)
- fn_withdraw_join_request (G5.7)
- fn_accept_group_invitation (G5.4)
- rpc_find_profile_by_student_code (G5.6)
- fn_reset_group_invite (G5.1)
- fn_has_permission (G14)
- fn_get_group_role (G3)
- fn_notify_group (G16)
- fn_delete_group_message (G8)
- role_permissions RLS (G14)
- group_members RLS (G3, G15)
- groups UPDATE RLS (G2, G13)
- group_rules RLS (G6)
- group_announcements RLS (G7)
- group_messages RLS (G8)
- notifications RLS (G16)
- group_mutes RLS (G16)

## G17 Dependency
**G18 final security/production acceptance is BLOCKED until G17 security audit is PASS.**

G17 migrations affecting acceptance:
- G17_01: fix_rpc_get_leaderboard_access.sql
- G17_02: fix_fn_increment_batch_progress.sql
- G17_03: revoke_fn_insert_system_message_execute.sql
- G17_04: fix_test_syllabus_and_announcement_author_policies.sql

## Analyze Result
flutter analyze: 0 errors, 0 warnings, 438 info-level hints (all prefer_const_constructors and similar)

## APK Result
flutter build apk --debug: SUCCESS
Output: build/app/outputs/flutter-apk/app-debug.apk

## Files Changed
- test/group/group_acceptance_test.dart (NEW — 50 tests)
- docs/G18_ACCEPTANCE_MATRIX.md (NEW)
- docs/G18_ROLE_PERMISSION_MATRIX.md (NEW)
- docs/G18_DEVICE_ACCEPTANCE_CHECKLIST.md (NEW)
- docs/G18_GROUP_HUB_E2E_PLAN.md (NEW)
- docs/G18_ACCEPTANCE_PREPARATION_REPORT.md (THIS FILE)

## Commit Hash
PENDING (to be committed after G17 passes)

## Summary
G18 preparation is COMPLETE. The acceptance layer provides:
- 50 cross-feature acceptance tests covering 15 user journeys (A–O)
- Comprehensive acceptance matrix for all G1–G16 phases
- Role/permission matrix for 7 roles × 20 features
- Device acceptance checklist (22 items)
- E2E test plan with execution order
- All validations pass (tests, analyze, APK)

The project is ready for G17 security audit completion and final acceptance verification.
