# NOTIFICATION DISMISS FIX — BUG-1 RESOLUTION REPORT

**Date:** 2026-09-21  
**Verdict:** **PASS**

---

## BUG-1 SUMMARY

**Bug:** `NotificationFeedRepository.dismiss()` silently fails because authenticated users have no `DELETE` RLS policy on `public.notifications`.

**Root cause:** Migration `0032_security_hardening.sql` added SELECT and UPDATE policies but no DELETE policy. The `dismiss()` method in the Flutter client sends `DELETE FROM notifications WHERE id = ? AND user_id = ?` — RLS blocks this silently (returns 0 rows), and the controller's `_mutation` wrapper always returns `true` on success, masking the failure.

**Security impact:** LOW — least-privilege issue (safer to block than to allow).

**User impact:** MEDIUM — dismiss appears to work but silently does nothing.

---

## FILES CHANGED

### 1. Migration (NOT applied live)

| File | Purpose |
|---|---|
| `My-Prepration/supabase/mmigrations/0055_notification_dismiss_rls_fix.sql` | Adds `DELETE` RLS policy: `"dismiss own"` — `user_id = auth.uid()` |
| `My-Prepration/supabase/migrations/0055_ROLLBACK_notification_dismiss_rls_fix.sql` | Rollback: drops the policy |

**Migration content:**
```sql
drop policy if exists "dismiss own" on public.notifications;
create policy "dismiss own" on public.notifications
  for delete to authenticated
  using (user_id = auth.uid());
```

**Security invariant after migration:**
| Operation | Policy | Column |
|---|---|---|
| SELECT | `"own notifications"` | `user_id = auth.uid()` |
| UPDATE | `"mark own read"` | `USING user_id = auth.uid()` + `WITH CHECK user_id = auth.uid()` |
| DELETE | `"dismiss own"` | `user_id = auth.uid()` |
| INSERT | None (blocked) | Rows written by SECURITY DEFINER triggers only |
| anon | `REVOKE ALL` | Fully blocked |

### 2. Flutter controller fix

**File:** `lib/features/notifications/state/notification_feed_controller.dart`

**Change:** `dismiss()` method no longer uses `_mutation()` wrapper, which always returned `true` on success and discarded the repository's return value. The new implementation preserves the `bool` return from `FakeNotificationFeedRepository.dismiss()` / `SupabaseNotificationFeedRepository.dismiss()`.

**Before:** `_mutation` took `Future<void> Function()` — the `dismiss()` return value was discarded.

**After:** `dismiss()` implements the single-flight + server re-read pattern directly, preserving the `false` return when RLS blocks the delete.

### 3. Test infrastructure

**File:** `test/group/fakes.dart`

**Added:** `FakeNotificationFeedRepository` — in-memory implementation of `NotificationFeedRepository` mirroring live RLS rules (own rows only for SELECT/UPDATE/DELETE, no INSERT for clients).

### 4. Tests

**File:** `test/group/group_notifications_test.dart`

**Added:** 11 dismiss tests in the `BUG-1. notification dismissal (0055 migration)` group:

| # | Test | Status |
|---|---|---|
| 1 | Own notification deleted successfully | PASS |
| 2 | Another user's notification not deleted (RLS: 0 rows) | PASS |
| 3 | Forged notification ID does not delete anything | PASS |
| 4 | Dismissed notification removed from feed | PASS |
| 5 | Unread count decrements after dismissing unread | PASS |
| 6 | Double dismiss is idempotent | PASS |
| 7 | Dismiss is scoped to caller; other users' rows survive | PASS |
| 8 | markRead still works alongside dismiss | PASS |
| 9 | markAllRead still works alongside dismiss | PASS |
| 10 | Server error on dismiss surfaces to UI | PASS |
| 11 | Dismiss on empty list returns false without error | PASS |

---

## VALIDATION

| Command | Result |
|---|---|
| `flutter analyze` | 0 new errors (92 pre-existing info/warning) |
| `flutter test test/group/group_notifications_test.dart` | **31/31 PASS** |
| `flutter test test/group/group_notifications_test.dart test/group/group_acceptance_test.dart test/app_routes_test.dart` | **83/83 PASS** |

---

## LIVE STATUS

**CLIENT READY — LIVE MIGRATION NOT APPLIED**

The Flutter controller fix and tests are complete. The RLS migration (`0055`) must be applied to the live Supabase database before `dismiss()` will work in production.

**To apply:**
```bash
supabase db push
# or apply via Supabase SQL Editor:
# contents of My-Prepration/supabase/migrations/0055_notification_dismiss_rls_fix.sql
```

**To rollback:**
```bash
# apply contents of My-Prepration/supabase/migrations/0055_ROLLBACK_notification_dismiss_rls_fix.sql
```

---

## WHAT THIS FIX DOES NOT CHANGE

- No new tables created
- No duplicate infrastructure
- No changes to notification architecture
- No weakening of SELECT/UPDATE security
- No broad DELETE access (own rows only)
- No changes to notification creation triggers
- No changes to any other notification types
- No changes to R6/R7/G19/test engine/dashboard implementation
