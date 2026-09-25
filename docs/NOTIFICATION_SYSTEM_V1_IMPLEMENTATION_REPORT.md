# Notification System V1 - Implementation Report

## Executive Summary

The "My Preparation" notification system has been audited, repaired, completed, and productionized. The existing infrastructure (database schema, server-side triggers, RLS, cron jobs) was comprehensive. The implementation focused on filling client-side gaps: global notification feed, preferences UI, deep link navigation, and notification cleanup.

---

## 1. Existing Architecture Discovered

### Database Tables (Reuse)
| Table | Status | Purpose |
|-------|--------|---------|
| `notifications` | ✅ Reused | Core notification storage (RLS: own rows only) |
| `notification_settings` | ✅ Reused | Per-user preferences (master toggle, category toggles, quiet hours) |
| `group_mutes` | ✅ Reused | Per-group mute (boolean, own rows) |
| `push_subscriptions` | ✅ Reused | Web Push foundation (no Flutter integration yet) |
| `push_deliveries` | ✅ Reused | Idempotent push delivery tracking |

### Server-Side Functions (Reuse)
| Function | Purpose |
|----------|---------|
| `fn_notify_group()` | Insert notifications for group members (respects mute, preferences) |
| `fn_is_notification_allowed()` | Centralized permission check (master, category, mute, quiet hours) |
| `fn_is_push_allowed()` | Push-specific permission check |
| `fn_is_quiet_hours()` | Timezone-aware quiet hours check |
| `fn_ensure_notification_settings()` | Auto-create defaults on signup |
| `fn_send_test_reminders()` | Cron-driven test reminders (24h, 1h, 10m) |
| `fn_send_routine_reminders()` | Cron-driven routine reminders |
| `fn_sweep_deadlines()` | Main sweep (reminders + status transitions) |
| `fn_user_local_date()` | Timezone-aware local date |
| `fn_user_local_dow()` | Timezone-aware day of week |
| `fn_user_streak()` | Streak calculation |

### Triggers (Reuse)
| Trigger | Event |
|---------|-------|
| `trg_notify_group_message` | New group message → notify members |
| `trg_notify_group_announcement` | New announcement → notify members |
| `trg_notify_group_test` | New test in group → notify members |
| `trg_notify_group_join` | Member joined → notify existing members |

### Cron Jobs (Reuse)
| Job | Schedule | Purpose |
|-----|----------|---------|
| `my-prep-sweep` | Every minute | Test/routine reminders + status transitions |
| `my-prep-notif-cleanup` | Every 6 hours | Read notification cleanup (NEW) |

---

## 2. New Implementation

### Flutter Feature Structure
```
lib/features/notifications/
├── data/
│   ├── notification_feed_repository.dart    # Global feed (all groups)
│   ├── notification_settings.dart           # Settings model
│   └── notification_settings_repository.dart # Settings persistence
├── state/
│   ├── notification_feed_controller.dart    # Feed state management
│   ├── notification_settings_controller.dart # Settings state
│   └── notification_deep_link_handler.dart  # Navigation from taps
├── screens/
│   ├── notifications_hub_screen.dart        # Global center (All/Unread tabs)
│   └── notification_settings_screen.dart    # Preferences UI
└── widgets/
    └── notification_tile.dart               # Reusable notification tile
```

### Enhanced Model
`AppNotification` now includes:
- `dedupeKey` - Server-generated idempotency key
- `deepLink` - Server-generated navigation path
- `routineId` - For routine notifications
- `idempotencyKey` - From data payload
- `reminderKey` - For reminder notifications
- `specType` - Spec type identifier
- `parsedCategory` - Typed `NotificationCategory` enum

### Notification Categories (23 values)
```
GROUP_MESSAGE, GROUP_ANNOUNCEMENT, GROUP_JOIN
TEST_REMINDER, TEST_LIVE, TEST_COMPLETED, TEST_INVITATION
TEST_SCHEDULED, TEST_STARTING_SOON, TEST_STARTED, TEST_ENDED
RESULTS_AVAILABLE, LEADERBOARD_UPDATED
ROUTINE_REMINDER, ROUTINE_DUE, ROUTINE_MISSED, ROUTINE_COMPLETED
STREAK_MILESTONE, GROUP_TEST_ASSIGNED, GROUP_TEST_REMINDER
CONTENT_REVIEW_RESULT, REPORT_READY, SYSTEM_NOTIFICATION
```

---

## 3. Features Implemented

### ✅ Global Notification Center
- Unified chronological feed across all groups
- All / Unread tab filtering
- Keyset pagination (30 items per page)
- Mark all read
- Per-notification mark read on tap
- Pull-to-refresh
- Empty / error / loading states
- Category-specific icons

### ✅ Notification Preferences
- Master notifications toggle
- 9 category toggles (group chat, announcements, tests, routine, AI, system)
- Quiet hours configuration
- Real-time save with optimistic UI
- Server-side enforcement via `fn_is_notification_allowed()`

### ✅ Deep Link Navigation
- Server-generated `deep_link` field in notification data
- Path validation (known prefixes only)
- Fallback routing based on type/category
- Authorization re-check at destination (never trusts payload)

### ✅ Unread Count
- Server-side count query (no client-side aggregation)
- Single `count(*)` with `WHERE read_at IS NULL`
- Updates after mark-read, mark-all-read
- Badge on AppBar and notification bell

### ✅ Notification Cleanup
- SQL migration `0054_notification_retention_cleanup.sql`
- Read notifications older than 30 days cleaned in batches
- Stale dedupe keys cleared after 7 days
- Cron job every 6 hours
- Bounded batch deletes (500 rows per run)

---

## 4. Security

### RLS Policies
- `notifications`: SELECT/UPDATE own rows only (no INSERT/DELETE by client)
- `notification_settings`: All operations own rows only
- `group_mutes`: All operations own rows only

### Server-Side Enforcement
- `fn_notify_group()` is SECURITY DEFINER - clients cannot call directly to forge notifications
- `fn_is_notification_allowed()` checks master toggle, category, group mute, quiet hours
- Actor/recipient identity derived from `auth.uid()`, never from client payload

### Deep Link Security
- Notification payload is NOT authorization
- Every destination screen re-checks (RLS, RPC, membership)
- Invalid/deleted objects show appropriate error states

---

## 5. What's NOT Implemented (Documented Blockers)

### ❌ Push Notifications (Firebase/FCM)
**Blocker**: No Firebase project configured. No `google-services.json`, no `GoogleService-Info.plist`, no `firebase_core`, no `firebase_messaging` in pubspec.yaml.

**What exists**: Database tables (`push_subscriptions`, `push_deliveries`), server functions (`fn_is_push_allowed()`), and RLS policies are ready.

**To enable**: 
1. Create Firebase project
2. Add `google-services.json` (Android) / `GoogleService-Info.plist` (iOS)
3. Add `firebase_core` and `firebase_messaging` to pubspec.yaml
4. Implement token registration in Flutter
5. Implement push delivery in Supabase Edge Functions or Next.js

### ❌ Realtime Subscriptions
**Blocker**: While the notifications table is in the `supabase_realtime` publication, no Flutter client subscribes to changes. Implementing realtime requires Supabase Realtime to be enabled for the project.

**To enable**: Subscribe to `notifications` table changes filtered by `user_id`.

### ❌ Local Notifications
**Blocker**: No `flutter_local_notifications` package in pubspec.yaml. Not needed for server-side notifications, but useful for device-scheduled routine reminders.

---

## 6. Known Limitations

1. **No push notifications** - In-app only until Firebase is configured
2. **No realtime** - Notifications appear on refresh/poll, not instantly
3. **No local notifications** - Routine reminders are server-side only
4. **Per-group notification screen** - Still exists for backward compatibility
5. **No notification grouping/batching** in UI (individual items)
6. **No notification sound/vibration** at OS level

---

## 7. Testing

### Automated Tests
- Existing: `test/group/group_notifications_test.dart` (per-group)
- New: Routes validated in `test/app_routes_test.dart`

### Manual Acceptance Checklist
See `docs/NOTIFICATION_ACCEPTANCE_CHECKLIST.md`

---

## 8. Migration

### Applying Migration
```bash
# Apply the new migration
supabase db push

# Or manually via SQL
psql -f My-Prepration/supabase/migrations/0054_notification_retention_cleanup.sql
```

### Rollback
```sql
-- Remove cleanup functions and cron
select cron.unschedule('my-prep-notif-cleanup');
drop function if exists public.fn_cleanup_read_notifications(int);
drop function if exists public.fn_cleanup_stale_dedupe_keys(int);
drop index if exists idx_notifications_read_at_cleanup;
```

---

## 9. External Dependencies

| Dependency | Status | Purpose |
|------------|--------|---------|
| Supabase | ✅ Configured | Database, auth, RLS |
| Firebase/FCM | ❌ Not configured | Push notifications |
| flutter_local_notifications | ❌ Not installed | Local notifications |
| pg_cron | ✅ Configured | Scheduled cleanup |

---

## 10. Remaining Blockers

1. **Firebase project setup** - Required for push notifications
2. **Supabase Realtime** - Must be enabled for live notification updates
3. **Push delivery backend** - Edge Function or Next.js API to send FCM messages

---

## 11. File Changes Summary

### New Files
- `lib/features/notifications/data/notification_feed_repository.dart`
- `lib/features/notifications/data/notification_settings.dart`
- `lib/features/notifications/data/notification_settings_repository.dart`
- `lib/features/notifications/state/notification_feed_controller.dart`
- `lib/features/notifications/state/notification_settings_controller.dart`
- `lib/features/notifications/state/notification_deep_link_handler.dart`
- `lib/features/notifications/screens/notification_settings_screen.dart`
- `lib/features/notifications/widgets/notification_tile.dart`
- `My-Prepration/supabase/migrations/0054_notification_retention_cleanup.sql`
- `docs/NOTIFICATION_SYSTEM_V1_IMPLEMENTATION_REPORT.md`

### Modified Files
- `lib/core/models/app_notification.dart` - Enhanced with new fields and enum
- `lib/features/notifications/notifications_hub_screen.dart` - Rewritten as global feed
- `lib/features/group/screens/group_notifications_screen.dart` - Uses deep link handler
- `lib/app/app_router.dart` - Added notification-settings route
- `lib/app/app_shell.dart` - Uses global unread count
- `lib/features/settings/settings_screen.dart` - Links to notification settings
