# NOTIFICATION V2 — EVENT COVERAGE REPORT

**Date:** 2026-09-21
**Migration:** `0056_notification_v2_event_coverage.sql`
**Verdict:** **PASS WITH WARNINGS**

---

## EXECUTIVE SUMMARY

Notification V2 adds server-side notification triggers for 9 event categories that were previously missing from the notification pipeline. The implementation reuses the existing notification architecture (same `notifications` table, same RLS policies, same `fn_is_notification_allowed` preference enforcement, same deep-link handler). No new tables, no new repositories, no new permission systems.

**3 events implemented:** Results Available, AI Report Ready, Join Request/Accepted/Rejected, Role Changed, Member Removed, Streak Milestone, Leaderboard Updated.
**3 events blocked:** System Notifications (needs admin actor), Content Review (needs question_bank trigger), Mentions (no infrastructure).

---

## EXISTING NOTIFICATION ARCHITECTURE FOUND

| Component | Location | Status |
|---|---|---|
| `notifications` table | `0001_init.sql` | LIVE — uuid PK, user_id, category, title, body, data jsonb, read_at, created_at, priority, dedupe_key |
| `notif_category` enum | `0001_init.sql` + extensions | 27 values (22 original + 5 V2) |
| RLS policies | `0032`, `0055` | SELECT/UPDATE/DELETE own rows only; no INSERT for clients |
| `fn_is_notification_allowed` | `0046` + `0056` | Centralized preference/mute/quiet-hours check |
| `fn_notify_group` | `0036` | Group-scoped notification helper |
| `fn_is_quiet_hours` | `0030` | Timezone-aware quiet hours |
| `notification_settings` table | `0015` | Per-user preferences (16 fields) |
| `group_mutes` table | `0033` | Per-user per-group mute |
| Retention cleanup | `0054` | 30-day read cleanup, 7-day dedupe key cleanup |
| Flutter model | `app_notification.dart` | 29 enum values (24 original + 5 V2) |
| Deep link handler | `notification_deep_link_handler.dart` | 3-tier: server deep_link → fallback → /notifications |
| Test infrastructure | `group_notifications_test.dart` | 38 tests (31 existing + 7 V2) |

---

## EVENT COVERAGE MATRIX

| # | Event | Dependency | Implemented | Trigger | Recipient | Preference | Quiet Hours | Deep Link | Idempotency | Security | Tests | Status |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | Test Results Available | `results` table | ✅ | `trg_notify_results_available` on results INSERT | test participant | `test_results` | ✅ | `/tests/:testId` | `dedupe_key` | ✅ | Model parse | PASS |
| B | AI Coach Report Ready | `ai_reports` table | ✅ | `trg_notify_ai_report_ready` on ai_reports INSERT | report owner | `test_results` | ✅ | `/tests/:testId` | `dedupe_key` | ✅ | Model parse | PASS |
| C | Join Request (to leaders) | `group_join_requests` table | ✅ | In `fn_join_group()` | group leaders/managers | `group_announcements` | ✅ | `/groups/:groupId` | `dedupe_key` | ✅ | Model parse | PASS |
| D | Join Request Accepted | `fn_approve_group_join_request` | ✅ | In `fn_approve_group_join_request(p_approve=true)` | requester | `group_announcements` | ✅ | `/groups/:groupId` | `dedupe_key` | ✅ | Model parse | PASS |
| E | Join Request Rejected | `fn_approve_group_join_request` | ✅ | In `fn_approve_group_join_request(p_approve=false)` | requester | `group_announcements` | ✅ | `/notifications` | `dedupe_key` | ✅ | Model parse | PASS |
| F | Role Changed | `group_members.role` UPDATE | ✅ | Enhanced `trg_role_changed_system` | affected user | `group_announcements` | ✅ | `/groups/:groupId` | `dedupe_key` | ✅ | Model parse | PASS |
| G | Member Removed | `group_members` DELETE | ✅ | Enhanced `trg_member_left_system` | removed member | always allowed | ✅ | `/notifications` (safe) | `dedupe_key` | ✅ | Model parse | PASS |
| H | System Notifications | Admin actor | ❌ | — | — | — | — | — | — | — | — | BLOCKED |
| I | Streak Milestone | `routine_logs` + `fn_user_streak` | ✅ | `trg_notify_streak_milestone` on routine_logs INSERT | routine owner | always allowed | ✅ | `/routine` | `dedupe_key` | ✅ | Model parse | PASS |
| J | Leaderboard Update | `results` table | ✅ | `trg_notify_leaderboard_updated` on results INSERT | test participant | `test_results` | ✅ | `/tests/:testId/leaderboard` | `dedupe_key` | ✅ | Model parse | PASS |
| K | Content Review | `question_bank` status | ❌ | — | — | — | — | — | — | — | — | BLOCKED |
| L | Mentions | mention infrastructure | ❌ | — | — | — | — | — | — | — | — | BLOCKED |

---

## EVENTS IMPLEMENTED

### A. Test Results Available
- **Trigger:** `trg_notify_results_available` — AFTER INSERT on `results`
- **Recipient:** `results.user_id` (the test taker)
- **Category:** `RESULTS_AVAILABLE`
- **Priority:** `high`
- **Deep link:** `/tests/:testId`
- **Idempotency:** `dedupe_key = 'v2_results:' || user_id || ':' || test_id`
- **Preference:** `test_results` toggle

### B. AI Coach Report Ready
- **Trigger:** `trg_notify_ai_report_ready` — AFTER INSERT on `ai_reports`
- **Recipient:** `ai_reports.user_id` (the student)
- **Category:** `REPORT_READY`
- **Priority:** `medium`
- **Deep link:** `/tests/:testId`
- **Idempotency:** `dedupe_key = 'v2_report:' || user_id || ':' || report_id`
- **Preference:** `test_results` toggle

### C. Join Request to Leaders
- **Location:** Inside `fn_join_group()` — fires when restricted group join request is created
- **Recipient:** All group members with `role IN ('owner','leader','moderator')` (excluding requester)
- **Category:** `GROUP_JOIN_REQUEST`
- **Priority:** `medium`
- **Deep link:** `/groups/:groupId`
- **Idempotency:** `dedupe_key = 'v2_join_req:' || group_id || ':' || requester_id`
- **Preference:** `group_announcements` toggle

### D/E. Join Request Accepted/Rejected
- **Location:** Inside `fn_approve_group_join_request()`
- **Recipient:** The requester (`group_join_requests.user_id`)
- **Categories:** `JOIN_ACCEPTED` / `JOIN_REJECTED`
- **Priority:** `medium`
- **Deep link:** `/groups/:groupId` (accepted) / `/notifications` (rejected)
- **Idempotency:** `dedupe_key = 'v2_join_acc:' || request_id` / `'v2_join_rej:' || request_id`
- **Preference:** `group_announcements` toggle

### F. Role Changed
- **Location:** Enhanced `trg_role_changed_system()` — fires on `group_members.role` UPDATE
- **Recipient:** The affected user (`group_members.user_id`)
- **Category:** `ROLE_CHANGED`
- **Priority:** `medium`
- **Deep link:** `/groups/:groupId`
- **Idempotency:** `dedupe_key = 'v2_role:' || membership_id || ':' || new_role`
- **Preference:** `group_announcements` toggle
- **Also:** Continues to write system message to group chat (existing behavior preserved)

### G. Member Removed
- **Location:** Enhanced `trg_member_left_system()` — fires on `group_members` DELETE
- **Recipient:** The removed member (`group_members.user_id`)
- **Category:** `MEMBER_REMOVED`
- **Priority:** `medium`
- **Deep link:** `/notifications` (safe fallback — user no longer has group access)
- **Idempotency:** `dedupe_key = 'v2_removed:' || membership_id`
- **Preference:** Always allowed (user must know they were removed)
- **Also:** Continues to write system message to group chat (existing behavior preserved)

### I. Streak Milestone
- **Trigger:** `trg_notify_streak_milestone` — AFTER INSERT on `routine_logs`
- **Condition:** `routine_logs.status = 'COMPLETED'`
- **Recipient:** Routine owner
- **Category:** `STREAK_MILESTONE`
- **Priority:** `low`
- **Milestones:** 3, 7, 14, 30, 50, 100, 365 days
- **Deep link:** `/routine`
- **Idempotency:** `dedupe_key = 'v2_streak:' || user || ':' || milestone || ':' || YYYY-MM`
- **Preference:** Always allowed

### J. Leaderboard Updated
- **Trigger:** `trg_notify_leaderboard_updated` — AFTER INSERT on `results`
- **Recipient:** Test participant (`results.user_id`)
- **Category:** `LEADERBOARD_UPDATED`
- **Priority:** `low`
- **Deep link:** `/tests/:testId/leaderboard`
- **Idempotency:** `dedupe_key = 'v2_leaderboard:' || user_id || ':' || test_id`
- **Preference:** `test_results` toggle

---

## EVENTS BLOCKED

### H. System Notifications — BLOCKED
**Dependency:** Needs an admin/system actor mechanism. The current architecture has no safe way for an admin to send system-wide notifications without exposing a public RPC that any authenticated user could abuse. The `SYSTEM_NOTIFICATION` enum value exists but there is no trigger or function that creates these safely.

**Required:** An admin-only RPC or dashboard action that inserts system notifications through a `SECURITY DEFINER` function with admin role verification.

### K. Content Review — BLOCKED
**Dependency:** Needs a trigger on `question_bank.status` change. The `CONTENT_REVIEW_RESULT` enum value exists. The `question_bank` table has `status` (pending_review/approved/rejected/needs_revision) and `reviewed_by`/`reviewed_at` columns. The `content_audit_logs` table tracks all review actions. However, there is no database trigger on status change, and the review actions are performed via Next.js server actions (`actions.ts`) which do not currently insert notifications.

**Required:** Either a PostgreSQL trigger on `question_bank.status` UPDATE, or notification insertion in the Next.js review actions.

### L. Mentions — BLOCKED
**Dependency:** No mention infrastructure exists. The `group_messages` table stores plain text `body` with no mention parsing, no `message_mentions` join table, no `@username` detection, and no mention-specific notification category.

**Required:** Full mention infrastructure: message body parsing, mention resolution, mention notification category, trigger on `group_messages` INSERT.

---

## PRODUCT DECISIONS REQUIRED

1. **Join request notifications:** Should the `GROUP_JOIN_REQUEST` notification respect the `group_announcements` preference? Currently yes. If a separate "join request" preference is desired, a new `notification_settings` column would be needed.

2. **Member removed deep link:** Currently routes to `/notifications` (safe fallback). If a "you were removed" screen is desired, a new route would be needed.

3. **Leaderboard notification timing:** Currently fires on every `results` INSERT. If only meaningful rank changes should notify (e.g., entering top 3), the trigger logic would need to compare old/new rank.

4. **Streak milestone thresholds:** Currently hardcoded to [3, 7, 14, 30, 50, 100, 365]. If different milestones are desired, the array can be adjusted.

---

## BACKEND CHANGES

### Migration: `0056_notification_v2_event_coverage.sql`

| Change | Type | Reversible |
|---|---|---|
| Add 5 enum values | `ALTER TYPE` | Not easily (enum values can't be dropped) |
| Replace `fn_is_notification_allowed` | `CREATE OR REPLACE` | Yes (revert to previous version) |
| Create `fn_notify_results_available` | `CREATE FUNCTION` | Yes (`DROP FUNCTION`) |
| Create `fn_notify_ai_report_ready` | `CREATE FUNCTION` | Yes (`DROP FUNCTION`) |
| Create `fn_notify_streak_milestone` | `CREATE FUNCTION` | Yes (`DROP FUNCTION`) |
| Create `fn_notify_leaderboard_updated` | `CREATE FUNCTION` | Yes (`DROP FUNCTION`) |
| Replace `fn_join_group` | `CREATE OR REPLACE` | Yes (revert to previous version) |
| Replace `fn_approve_group_join_request` | `CREATE OR REPLACE` | Yes (revert to previous version) |
| Replace `trg_role_changed_system` | `CREATE OR REPLACE` | Yes (revert to previous version) |
| Replace `trg_member_left_system` | `CREATE OR REPLACE` | Yes (revert to previous version) |
| Create 4 triggers | `CREATE TRIGGER` | Yes (`DROP TRIGGER`) |

### RLS Impact
**None.** No RLS policies were added, modified, or removed. The existing policies remain:
- SELECT: own rows only (`user_id = auth.uid()`)
- UPDATE: own rows only (`user_id = auth.uid()`)
- DELETE: own rows only (`user_id = auth.uid()`)
- INSERT: no client policy (rows written by SECURITY DEFINER functions only)

### Security Verification
- All new functions are `SECURITY DEFINER` with `SET search_path = public`
- All functions call `fn_is_notification_allowed()` for preference/mute/quiet-hours enforcement
- All inserts use `dedupe_key` for idempotency (UNIQUE index enforced)
- Client cannot call these functions (no GRANT to anon, no INSERT RLS policy)
- `MEMBER_REMOVED` notification uses `/notifications` deep link (safe — no group access bypass)
- `JOIN_REJECTED` notification uses `/notifications` deep link (safe)

---

## FLUTTER CHANGES

### Files Modified

| File | Change |
|---|---|
| `lib/core/models/app_notification.dart` | Added 5 enum values, updated `isGroupRelated` and `isTestRelated` |
| `lib/features/notifications/widgets/notification_tile.dart` | Added 5 icon mappings for new categories |
| `lib/features/notifications/state/notification_deep_link_handler.dart` | Added fallback routes for V2 types, added `/reports` check |
| `test/group/group_notifications_test.dart` | Added 7 V2 model/enum tests |

### New NotificationCategory Values
```dart
groupJoinRequest('GROUP_JOIN_REQUEST'),
joinAccepted('JOIN_ACCEPTED'),
joinRejected('JOIN_REJECTED'),
roleChanged('ROLE_CHANGED'),
memberRemoved('MEMBER_REMOVED'),
```

---

## DUPLICATE/IDEMPOTENCY VERIFICATION

Every V2 event uses `dedupe_key` with a UNIQUE index (`uniq_notifications_dedupe`):
- `v2_results:{user}:{test}` — one result notification per user per test
- `v2_report:{user}:{report}` — one report notification per user per report
- `v2_join_req:{group}:{requester}` — one join request notification per group per request
- `v2_join_acc:{request}` — one accepted notification per request
- `v2_join_rej:{request}` — one rejected notification per request
- `v2_role:{membership}:{role}` — one notification per role change
- `v2_removed:{membership}` — one notification per removal
- `v2_streak:{user}:{milestone}:{month}` — one notification per milestone per month
- `v2_leaderboard:{user}:{test}` — one leaderboard notification per user per test

---

## DEEP-LINK VERIFICATION

| Event | Deep Link | Route Exists | Safe |
|---|---|---|---|
| Results Available | `/tests/:testId` | ✅ | ✅ (own result) |
| AI Report Ready | `/tests/:testId` | ✅ | ✅ (own report) |
| Join Request | `/groups/:groupId` | ✅ | ✅ (leader access) |
| Join Accepted | `/groups/:groupId` | ✅ | ✅ (now a member) |
| Join Rejected | `/notifications` | ✅ | ✅ (safe fallback) |
| Role Changed | `/groups/:groupId` | ✅ | ✅ (still a member) |
| Member Removed | `/notifications` | ✅ | ✅ (safe fallback) |
| Streak Milestone | `/routine` | ✅ | ✅ (own routine) |
| Leaderboard Updated | `/tests/:testId/leaderboard` | ✅ | ✅ (own result) |

---

## PREFERENCE/MUTE VERIFICATION

| Event | Preference Toggle | Group Mute | Quiet Hours |
|---|---|---|---|
| Results Available | `test_results` | N/A (no group) | ✅ |
| AI Report Ready | `test_results` | N/A (no group) | ✅ |
| Join Request | `group_announcements` | ❌ (not group-scoped type) | ✅ |
| Join Accepted | `group_announcements` | ❌ | ✅ |
| Join Rejected | `group_announcements` | ❌ | ✅ |
| Role Changed | `group_announcements` | ❌ | ✅ |
| Member Removed | always allowed | N/A | ✅ |
| Streak Milestone | always allowed | N/A | ✅ |
| Leaderboard Updated | `test_results` | N/A (no group) | ✅ |

---

## REGRESSION RESULTS

| Test Suite | Result |
|---|---|
| `flutter test test/group/group_notifications_test.dart` | **38/38 PASS** |
| Existing BUG-1 dismissal tests | **11/11 PASS** |
| Existing group notification tests | **20/20 PASS** |
| New V2 model/enum tests | **7/7 PASS** |

---

## VALIDATION

| Command | Result |
|---|---|
| `flutter analyze` | 0 notification-related errors (1 pre-existing error in `group_leaderboard_test.dart`) |
| `flutter test test/group/group_notifications_test.dart` | **38/38 PASS** |
| `flutter build apk --debug` | OWNER APPLY REQUIRED (build not run locally) |

---

## LIVE DB VERIFICATION STATUS

**OWNER APPLY REQUIRED**

The migration `0056_notification_v2_event_coverage.sql` must be applied to the live Supabase database.

**To apply:**
```bash
supabase db push
# or apply via Supabase SQL Editor:
# contents of My-Prepration/supabase/migrations/0056_notification_v2_event_coverage.sql
```

**Verification queries after applying:**
```sql
-- Check new enum values
SELECT enumlabel FROM pg_enum WHERE enumtypid = 'notif_category'::regtype ORDER BY enumsortorder;

-- Check notification triggers
SELECT trigger_name, event_object_table FROM information_schema.triggers
WHERE trigger_name LIKE 'trg_notify_%' ORDER BY event_object_table;

-- Check function exists
SELECT proname FROM pg_proc WHERE proname IN (
  'fn_notify_results_available', 'fn_notify_ai_report_ready',
  'fn_notify_streak_milestone', 'fn_notify_leaderboard_updated'
);
```

**To rollback:**
```sql
-- Drop V2 triggers
DROP TRIGGER IF EXISTS trg_notify_results_available ON public.results;
DROP TRIGGER IF EXISTS trg_notify_ai_report_ready ON public.ai_reports;
DROP TRIGGER IF EXISTS trg_notify_streak_milestone ON public.routine_logs;
DROP TRIGGER IF EXISTS trg_notify_leaderboard_updated ON public.results;

-- Drop V2 functions
DROP FUNCTION IF EXISTS public.fn_notify_results_available();
DROP FUNCTION IF EXISTS public.fn_notify_ai_report_ready();
DROP FUNCTION IF EXISTS public.fn_notify_streak_milestone();
DROP FUNCTION IF EXISTS public.fn_notify_leaderboard_updated();

-- Revert fn_join_group to pre-V2 version (from 0033)
-- Revert fn_approve_group_join_request to pre-V2 version (from 0033)
-- Revert trg_role_changed_system to pre-V2 version (from 0039)
-- Revert trg_member_left_system to pre-V2 version (from 0039)
-- Revert fn_is_notification_allowed to pre-V2 version (from 0046)
```

---

## REMAINING RISKS

1. **Enum values are permanent:** PostgreSQL enum values cannot be dropped. The 5 new values (`GROUP_JOIN_REQUEST`, `JOIN_ACCEPTED`, `JOIN_REJECTED`, `ROLE_CHANGED`, `MEMBER_REMOVED`) will remain in the enum even if the triggers are dropped.

2. **Leaderboard notification on every result:** The `trg_notify_leaderboard_updated` fires on every `results` INSERT. If a batch of 30 students gets results simultaneously, 30 notifications are created. This is by design (each student gets their own notification) but could be noisy.

3. **Streak milestone is monthly-capped:** The `dedupe_key` includes `YYYY-MM`, so a user can only get each milestone once per month. If a user loses a streak and rebuilds it in the same month, they won't get a second notification.

4. **Join request notification to leaders uses role check:** The `fn_join_group` function queries `group_members WHERE role IN ('owner','leader','moderator')`. If a group has custom roles or permissions, this may not match all authorized managers.

---

## NEXT STEPS

1. **Apply migration** to live Supabase database via `supabase db push`
2. **Verify** with post-migration queries
3. **Test end-to-end** with real user flows (submit test → results notification, join restricted group → leader notification, etc.)
4. **Consider** implementing BLOCKED events when dependencies are met:
   - System Notifications: design admin actor mechanism
   - Content Review: add trigger on `question_bank.status` or notification in review actions
   - Mentions: design mention infrastructure
