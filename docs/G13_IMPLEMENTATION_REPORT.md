# G13 — Group Settings (Enhanced)

**Date:** 2026-09-19
**Branch:** `r4-restart`
**Status:** VERIFIED — PASS (commit `5295c56`)

---

## 1. Live-First Audit Summary

The existing `GroupSettingsScreen` (648 lines) already supported:
- Group name editing (1-80 chars)
- Group description editing
- Privacy selection (public/private/restricted)
- Logo display and removal (upload not available — no storage policy live)
- Invite code display, copy, and rotate (gated by `GROUP_SETTINGS` permission)

**G13 enhancements add:** Rules summary, Members summary, and Leave Group (danger zone).

### Schema Usage (No New Tables)
- `groups` table — name, description, privacy, logo_url, invite_code
- `group_rules` table — read-only summary in settings
- `group_members` table — member count, role display
- `group_permissions` function — `fn_has_permission` gate for all actions

### Permission Model (No Changes)
- `GROUP_SETTINGS` / owner → edit name, description, privacy, logo, invite code
- `fn_is_member` → view rules summary, members summary
- `fn_prevent_owner_removal` → owner cannot leave (danger zone shows blocked message)

---

## 2. Changes Made

### 2.1 Enhanced GroupSettingsScreen
**File:** `lib/features/group/screens/group_settings_screen.dart`

Added three new sections below the existing settings form:

1. **Rules Summary** (`_rulesSummary`)
   - Shows rule count badge
   - Displays first 3 rules with "+N more" overflow
   - Loading and error states
   - "Manage rules" link navigates to the group hub's rules section
   - Key: `settings_rules_summary`, `settings_rules_count`, `settings_rules_empty`, `settings_manage_rules`

2. **Members Summary** (`_membersSummary`)
   - Shows member count
   - Displays caller's role (Owner/Leader/Moderator/Member)
   - "Manage members" link navigates to the full members screen
   - Key: `settings_members_summary`, `settings_members_count`, `settings_my_role`, `settings_manage_members`

3. **Leave Group (Danger Zone)** (`_leaveSection`)
   - Red-themed danger zone header
   - Owner sees a blocked message explaining they cannot leave
   - Non-owners see a "Leave group" button with confirmation dialog
   - On confirm, calls `_c.leave()` and navigates to `/groups`
   - Key: `settings_leave_section`, `settings_leave_button`, `settings_leave_blocked`, `confirm_leave`

All existing functionality preserved:
- All existing keys (`settings_name_field`, `settings_save`, `invite_section`, etc.) unchanged
- No changes to the controller, repository, or permission model
- No new routes needed (reuses existing hub and members routes)

---

## 3. Tests

**File:** `test/group/group_settings_test.dart`

Added 6 new tests (22 total, up from 16):

| # | Test | Description |
|---|------|-------------|
| 17 | Rules summary shows rules count and first 3 rules | 5 rules seeded → shows count, first 3 texts, "+2 more" |
| 18 | Rules summary empty rules shows no-rules message | No rules → "No rules yet." |
| 19 | Members summary shows member count and role | 3 members, owner → count "3", "Your role: Owner" |
| 20 | Owner sees blocked message, not leave button | Owner → `settings_leave_blocked` visible, no leave button |
| 21 | Non-owner sees leave button and can leave | Member with settings grant → leave button, confirm, navigates to /groups |
| 22 | Leave cancelled does nothing | Cancel in dialog → stays on settings screen |

All 22 settings tests pass. Full suite: **854/854 passing**.

---

## 4. Validation Results

| Gate | Result |
|------|--------|
| `flutter analyze` | Clean (75 pre-existing info-level lint hints, 0 errors, 0 warnings) |
| `flutter test` | **854/854 passing** |
| `flutter build apk --debug` | Built successfully |

---

## 5. Files Changed

| File | Change |
|------|--------|
| `lib/features/group/screens/group_settings_screen.dart` | Added rules, members, and leave sections (~150 lines) |
| `test/group/group_settings_test.dart` | Added 6 G13 tests + GroupRule import |

---

## 6. What Was NOT Changed

- `GroupRepository` — no new methods
- `GroupHubController` — no new properties (used existing `rules`, `members`, `canLeave`, `leave()`)
- `InviteCodeController` — unchanged
- `Group` model — unchanged
- `GroupRole`, `GroupPermission`, `GroupPrivacy` — unchanged
- Routes — no new routes added
- Database migrations — none required
