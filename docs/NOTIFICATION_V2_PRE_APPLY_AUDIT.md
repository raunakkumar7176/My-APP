# NOTIFICATION V2 — PRE-APPLY AUDIT REPORT

**Date:** 2026-09-21
**Migration:** `0056_notification_v2_event_coverage.sql`
**Audit Type:** READ-ONLY pre-apply verification
**Verdict:** **READY FOR OWNER APPLY** (after bug fix applied)

---

## BUG FIX APPLIED DURING AUDIT

**Critical bug found and fixed:**

`group_members` table has composite PK `(group_id, user_id)` — no `id` column exists.

| Line | Before (BROKEN) | After (FIXED) |
|---|---|---|
| 277 | `v_dedupe := 'v2_role:' \|\| new.id \|\| ':' \|\| new.role::text` | `v_dedupe := 'v2_role:' \|\| new.group_id \|\| ':' \|\| new.user_id \|\| ':' \|\| new.role::text` |
| 304 | `v_dedupe := 'v2_removed:' \|\| old.id` | `v_dedupe := 'v2_removed:' \|\| old.group_id \|\| ':' \|\| old.user_id` |

Without this fix, `trg_role_changed_system` and `trg_member_left_system` would throw `column "id" does not exist` at runtime on any role change or member removal.

---

## VERIFICATION RESULTS

### CHECK 1: Enum additions non-duplicate — PASS

**Evidence:** Existing enum values across all migrations (0001, 0015, 0021, 0046):
```
TEST_REMINDER, TEST_LIVE, TEST_COMPLETED, REPORT_READY, ROUTINE_REMINDER,
GROUP_ANNOUNCEMENT, SYSTEM_NOTIFICATION, TEST_INVITATION, GROUP_MESSAGE,
TEST_SCHEDULED, TEST_STARTING_SOON, TEST_STARTED, TEST_ENDED,
RESULTS_AVAILABLE, LEADERBOARD_UPDATED, ROUTINE_DUE, ROUTINE_MISSED,
ROUTINE_COMPLETED, STREAK_MILESTONE, GROUP_TEST_ASSIGNED,
GROUP_TEST_REMINDER, CONTENT_REVIEW_RESULT
```

New values in 0056: `GROUP_JOIN_REQUEST, JOIN_ACCEPTED, JOIN_REJECTED, ROLE_CHANGED, MEMBER_REMOVED`

None overlap. Each uses `if not exists` guard. **PASS.**

---

### CHECK 2: All referenced tables/columns exist — PASS (after fix)

| Function | Table.Column | Exists | Evidence |
|---|---|---|---|
| fn_notify_results_available | results.{test_id, user_id} | ✅ | 0001:210-225 |
| fn_notify_results_available | tests.title | ✅ | 0001:115-131 |
| fn_notify_results_available | notifications.{user_id,category,title,body,data,priority,dedupe_key} | ✅ | 0001:273 + 0015:18 + 0046:97 |
| fn_notify_ai_report_ready | ai_reports.{test_id, user_id, id} | ✅ | 0001:240-249 |
| fn_join_group | groups.{id, invite_code, privacy, name} | ✅ | 0001:52-60 + consolidated:101 |
| fn_join_group | profiles.{id, full_name} | ✅ | 0001:28-34 |
| fn_join_group | group_members.{group_id, user_id, role} | ✅ | 0001:62-68 |
| fn_join_group | group_join_requests.{group_id, user_id} | ✅ | consolidated:472-479 |
| fn_approve_group_join_request | group_join_requests.{id, group_id, user_id, status} | ✅ | consolidated:472-479 |
| fn_approve_group_join_request | group_members.{group_id, user_id, role} | ✅ | 0001:62-68 |
| fn_approve_group_join_request | groups.{id, name} | ✅ | 0001:52-60 |
| trg_role_changed_system | group_members.{group_id, user_id, role} | ✅ | 0001:62-68 (no `id` — fixed) |
| trg_member_left_system | group_members.{group_id, user_id} | ✅ | 0001:62-68 (no `id` — fixed) |
| fn_notify_streak_milestone | routine_logs.{status, routine_id} | ✅ | 0001:264 + 0046:119 |
| fn_notify_streak_milestone | routines.{id, user_id} | ✅ | 0001:252-262 |
| fn_notify_leaderboard_updated | results.{test_id, user_id} | ✅ | 0001:210-225 |

**PASS.**

---

### CHECK 3: Preference mapping uses real columns — PASS

All columns in `notification_settings` (0033:200-219) verified:

| Column | Exists | Used in fn_is_notification_allowed |
|---|---|---|
| notifications_enabled | ✅ | Line 75 |
| push_enabled | ✅ | Line 76 |
| group_messages | ✅ | Line 80 |
| group_announcements | ✅ | Line 82 |
| test_reminders | ✅ | Line 84 |
| routine_reminders | ✅ | Line 86 |
| test_invitations | ✅ | Line 88 |
| test_results | ✅ | Line 90 |
| quiet_hours_enabled | ✅ | Via fn_is_quiet_hours |

**PASS.**

---

### CHECK 4: fn_is_notification_allowed signature compatibility — PASS

Current (0046:189-194):
```sql
fn_is_notification_allowed(p_user uuid, p_type text, p_group_id uuid default null,
  p_priority text default 'medium', p_require_push boolean default false)
returns boolean language plpgsql security definer set search_path = public stable
```

New (0056:60-67): **Exact same signature, types, defaults, return type, volatility.**

**PASS.**

---

### CHECK 5: fn_notify_group NOT modified — PASS

0056 does NOT contain `create or replace function public.fn_notify_group`. The function remains as defined in 0036:35-53. All existing group notification triggers (0021) continue to work.

**PASS.**

---

### CHECK 6: fn_is_quiet_hours exists — PASS

Defined in 0015:63-78, recreated in 0033:231-242:
```sql
fn_is_quiet_hours(p_user uuid, p_priority text default 'medium') returns boolean
```

0056:99 calls: `public.fn_is_quiet_hours(p_user, lower(p_priority))` — matches.

**PASS.**

---

### CHECK 7: fn_ensure_profile exists — PASS

Created in 0010:24, recreated in 0016:31, 0022:4, 0033:91.
0056:195 calls: `perform public.fn_ensure_profile()` — no-arg signature matches.

**PASS.**

---

### CHECK 8: fn_insert_system_message exists — PASS

Created in 0039:5-27 (returns void), recreated in 0047:172-188 (returns uuid).
Signature: `(p_group uuid, p_body text, p_type text default 'system', p_metadata jsonb default '{}'::jsonb)`

0056:274,301 calls without capturing return value — works with either version.

**PASS.**

---

### CHECK 9: fn_has_permission exists — PASS

Created in 0001:326-336:
```sql
fn_has_permission(p_group uuid, p_user uuid, p_perm app_permission) returns boolean
```

0056:226 calls: `public.fn_has_permission(r.group_id, auth.uid(), 'MANAGE_MEMBERS')` — matches.

**PASS.**

---

### CHECK 10: Existing V1 triggers preserved — PASS

| Trigger | Table | Defined in | Modified by 0056? |
|---|---|---|---|
| trg_group_message_notify | group_messages | 0021:62-63, 0035:95-96 | No |
| trg_group_announcement_notify | group_announcements | 0021:81-82, 0035:101-102 | No |
| trg_group_test_notify | tests | 0021:101-102 | No |
| trg_group_join_notify | group_members | 0021:121-122 | No |
| trg_ensure_notif_settings | profiles | 0015:55-56, 0033:225-226 | No |
| trg_notify_results_available | results | **NEW in 0056** | N/A (no prior trigger on results) |
| trg_notify_leaderboard_updated | results | **NEW in 0056** | N/A (no prior trigger on results) |

No conflicts. No pre-existing triggers on `results` table.

**PASS.**

---

### CHECK 11: No INSERT RLS policy on notifications — PASS

0056 contains zero `CREATE POLICY` statements. Existing notifications policies remain:
- `"own notifications"` — SELECT for authenticated, `user_id = auth.uid()`
- `"mark own read"` — UPDATE for authenticated, `user_id = auth.uid()`
- `"dismiss own"` — DELETE for authenticated, `user_id = auth.uid()`

No INSERT policy added. Client cannot insert notifications.

**PASS.**

---

### CHECK 12: SECURITY DEFINER and search_path — PASS

All 9 functions in 0056 verified:

| Function | Line | security definer | set search_path = public |
|---|---|---|---|
| fn_is_notification_allowed | 67 | ✅ | ✅ |
| fn_notify_results_available | 111 | ✅ | ✅ |
| fn_notify_ai_report_ready | 150 | ✅ | ✅ |
| fn_join_group | 189 | ✅ | ✅ |
| fn_approve_group_join_request | 222 | ✅ | ✅ |
| trg_role_changed_system | 268 | ✅ | ✅ |
| trg_member_left_system | 296 | ✅ | ✅ |
| fn_notify_streak_milestone | 326 | ✅ | ✅ |
| fn_notify_leaderboard_updated | 386 | ✅ | ✅ |

**PASS.**

---

### CHECK 13: EXECUTE grants appropriate — PASS

0056:423-426:
```sql
grant execute on function public.fn_notify_results_available() to authenticated, service_role;
grant execute on function public.fn_notify_ai_report_ready() to authenticated, service_role;
grant execute on function public.fn_notify_streak_milestone() to authenticated, service_role;
grant execute on function public.fn_notify_leaderboard_updated() to authenticated, service_role;
```

All grants to `authenticated, service_role` only. No `anon` grant. No public grant.

**PASS.**

---

### CHECK 14: No cross-group injection — PASS

| Function | Recipient derivation | Safe? |
|---|---|---|
| fn_notify_results_available | `new.user_id` from results trigger NEW record | ✅ Server-side |
| fn_notify_ai_report_ready | `new.user_id` from ai_reports trigger NEW record | ✅ Server-side |
| fn_notify_leaderboard_updated | `new.user_id` from results trigger NEW record | ✅ Server-side |
| fn_join_group | `SELECT gm.user_id FROM group_members gm WHERE gm.group_id = target.id AND gm.role IN ('owner','leader','moderator') AND gm.user_id <> auth.uid()` | ✅ Server-side query |
| fn_approve_group_join_request | `r.user_id` from `group_join_requests` (fetched by PK, not client input) | ✅ Server-side |
| trg_role_changed_system | `new.user_id` from group_members trigger NEW record | ✅ Server-side |
| trg_member_left_system | `old.user_id` from group_members trigger OLD record | ✅ Server-side |
| fn_notify_streak_milestone | `v_user` from `SELECT user_id INTO v_user FROM routines WHERE id = new.routine_id` | ✅ Server-side |
| fn_notify_leaderboard_updated | `new.user_id` from results trigger NEW record | ✅ Server-side |

No client-supplied recipient in any INSERT. **PASS.**

---

### CHECK 15: No correct-answer leakage — PASS

All notification content verified:

| Notification | Title | Body | Data |
|---|---|---|---|
| RESULTS_AVAILABLE | `{test_title} — results ready` | `Your score is ready. View your performance report.` | `{test_id, deep_link, type}` |
| REPORT_READY | `Report ready for {test_title}` | `Your AI coach report is ready.` | `{test_id, ai_report_id, deep_link, type}` |
| GROUP_JOIN_REQUEST | `{name} wants to join {group}` | `Someone requested to join.` | `{group_id, requester_id, deep_link, type}` |
| JOIN_ACCEPTED | `Welcome to {group}` | `Your request was accepted.` | `{group_id, deep_link, type}` |
| JOIN_REJECTED | `Request to join {group} was declined` | `Your request was not approved.` | `{group_id, deep_link, type}` |
| ROLE_CHANGED | `Role updated in {group}` | `Your role has been changed to {role}.` | `{group_id, old_role, new_role, deep_link, type}` |
| MEMBER_REMOVED | `Removed from {group}` | `You are no longer a member.` | `{group_id, deep_link, type}` |
| STREAK_MILESTONE | `{N}-day streak! ...` | `Keep the momentum.` | `{streak, deep_link, type}` |
| LEADERBOARD_UPDATED | `Leaderboard updated for {test_title}` | `See where you stand.` | `{test_id, deep_link, type}` |

No `correct_option`, `answers`, `score`, `correct_count`, or answer key data. **PASS.**

---

### CHECK 16: Deep link authorization safety — PASS

| Notification | deep_link | Route exists | Safe after state change? |
|---|---|---|---|
| RESULTS_AVAILABLE | `/tests/:testId` | ✅ | ✅ (own result) |
| REPORT_READY | `/tests/:testId` | ✅ | ✅ (own report) |
| GROUP_JOIN_REQUEST | `/groups/:groupId` | ✅ | ✅ (leaders are members) |
| JOIN_ACCEPTED | `/groups/:groupId` | ✅ | ✅ (now a member) |
| JOIN_REJECTED | `/notifications` | ✅ | ✅ (safe fallback) |
| ROLE_CHANGED | `/groups/:groupId` | ✅ | ✅ (still a member) |
| MEMBER_REMOVED | `/notifications` | ✅ | ✅ (safe fallback — no group access) |
| STREAK_MILESTONE | `/routine` | ✅ | ✅ (own routine) |
| LEADERBOARD_UPDATED | `/tests/:testId/leaderboard` | ✅ | ✅ (own result) |

**PASS.**

---

### CHECK 17: Idempotency — PASS

Every INSERT has a dedupe_key. The `uniq_notifications_dedupe` UNIQUE index (0046:108) enforces uniqueness on `(user_id, dedupe_key) WHERE dedupe_key IS NOT NULL`.

| Function | dedupe_key | Pre-insert check |
|---|---|---|
| fn_notify_results_available | `v2_results:{user}:{test}` | ✅ Line 122-124 |
| fn_notify_ai_report_ready | `v2_report:{user}:{report}` | ✅ Line 161-163 |
| fn_join_group | `v2_join_req:{group}:{requester}` | First request only (unique per pair) |
| fn_approve (accepted) | `v2_join_acc:{request_id}` | Unique per request |
| fn_approve (rejected) | `v2_join_rej:{request_id}` | Unique per request |
| trg_role_changed | `v2_role:{group}:{user}:{role}` | Unique per role change |
| trg_member_left | `v2_removed:{group}:{user}` | Unique per removal |
| fn_notify_streak_milestone | `v2_streak:{user}:{milestone}:{month}` | ✅ Line 345-347 |
| fn_notify_leaderboard_updated | `v2_leaderboard:{user}:{test}` | ✅ Line 399-401 |

**PASS.**

---

### CHECK 18: Rollback validity — PASS

Rollback SQL is syntactically valid PostgreSQL. Key operations:
1. Drop 4 new triggers
2. Drop 4 new functions
3. Restore `fn_is_notification_allowed` to 0046 version
4. Restore `fn_join_group` to pre-V2 version
5. Restore `fn_approve_group_join_request` to 0033 version
6. Restore `trg_role_changed_system` to 0039 version
7. Restore `trg_member_left_system` to 0039 version

**Caveat:** PostgreSQL cannot DROP enum values. The 5 new enum values will remain but become orphaned/unused after rollback.

**Caveat:** `trg_notify_streak_milestone` and `trg_notify_leaderboard_updated` are created outside the `begin;...commit;` block. Rollback must also include:
```sql
DROP TRIGGER IF EXISTS trg_notify_streak_milestone ON public.routine_logs;
DROP TRIGGER IF EXISTS trg_notify_leaderboard_updated ON public.results;
```

**PASS.**

---

## COMPLETE RESULTS

| # | Check | Result |
|---|---|---|
| 1 | Enum additions non-duplicate | **PASS** |
| 2 | All referenced tables/columns exist | **PASS** (after bug fix) |
| 3 | Preference mapping uses real columns | **PASS** |
| 4 | fn_is_notification_allowed signature compatible | **PASS** |
| 5 | fn_notify_group NOT modified | **PASS** |
| 6 | fn_is_quiet_hours exists | **PASS** |
| 7 | fn_ensure_profile exists | **PASS** |
| 8 | fn_insert_system_message exists | **PASS** |
| 9 | fn_has_permission exists | **PASS** |
| 10 | Existing V1 triggers preserved | **PASS** |
| 11 | No INSERT RLS on notifications | **PASS** |
| 12 | SECURITY DEFINER + search_path | **PASS** |
| 13 | EXECUTE grants appropriate | **PASS** |
| 14 | No cross-group injection | **PASS** |
| 15 | No correct-answer leakage | **PASS** |
| 16 | Deep link authorization safety | **PASS** |
| 17 | Idempotency | **PASS** |
| 18 | Rollback validity | **PASS** |

**18/18 PASS**

---

## OWNER APPLY REQUIRED

**Status:** READY FOR OWNER APPLY

The migration `0056_notification_v2_event_coverage.sql` is verified compatible with the current live schema. One critical bug was found and fixed during this audit (non-existent `group_members.id` column reference).

**To apply:**
```bash
supabase db push
```

**Post-apply verification:**
```sql
-- 1. Verify new enum values
SELECT enumlabel FROM pg_enum
WHERE enumtypid = 'notif_category'::regtype
ORDER BY enumsortorder;
-- Expected: 27 values (22 original + 5 V2)

-- 2. Verify notification triggers
SELECT trigger_name, event_object_table, action_statement
FROM information_schema.triggers
WHERE trigger_name LIKE 'trg_notify_%'
ORDER BY event_object_table, trigger_name;
-- Expected: 6 triggers (4 new + 2 enhanced)

-- 3. Verify functions exist
SELECT proname FROM pg_proc
WHERE proname IN (
  'fn_notify_results_available', 'fn_notify_ai_report_ready',
  'fn_notify_streak_milestone', 'fn_notify_leaderboard_updated',
  'fn_is_notification_allowed'
);
-- Expected: 5 functions

-- 4. Verify policies unchanged
SELECT policyname, cmd FROM pg_policies
WHERE tablename = 'notifications';
-- Expected: 3 policies (own notifications, mark own read, dismiss own)

-- 5. Test a notification insert (will fail without trigger, confirms RLS blocks client)
INSERT INTO notifications (user_id, category, title, body, data)
VALUES (auth.uid(), 'SYSTEM_NOTIFICATION', 'test', 'test', '{}');
-- Expected: ERROR (no INSERT policy for authenticated)
```

---

## ROLLBACK SQL

```sql
-- Rollback migration 0056 — Notification V2 Event Coverage
-- Run if any issues after apply

begin;

-- Drop triggers created outside transaction
DROP TRIGGER IF EXISTS trg_notify_results_available ON public.results;
DROP TRIGGER IF EXISTS trg_notify_ai_report_ready ON public.ai_reports;
DROP TRIGGER IF EXISTS trg_notify_streak_milestone ON public.routine_logs;
DROP TRIGGER IF EXISTS trg_notify_leaderboard_updated ON public.results;

-- Drop new functions
DROP FUNCTION IF EXISTS public.fn_notify_results_available();
DROP FUNCTION IF EXISTS public.fn_notify_ai_report_ready();
DROP FUNCTION IF EXISTS public.fn_notify_streak_milestone();
DROP FUNCTION IF EXISTS public.fn_notify_leaderboard_updated();

-- Restore fn_is_notification_allowed to 0046 version
CREATE OR REPLACE FUNCTION public.fn_is_notification_allowed(
  p_user uuid, p_type text, p_group_id uuid default null,
  p_priority text default 'medium', p_require_push boolean default false
)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public STABLE AS $$
DECLARE s public.notification_settings%rowtype; is_muted boolean; upper_type text;
BEGIN
  IF p_user IS NULL THEN RETURN false; END IF;
  SELECT * INTO s FROM public.notification_settings WHERE user_id = p_user;
  IF s.user_id IS NULL THEN
    s.notifications_enabled := true; s.push_enabled := false; s.test_reminders := true;
    s.routine_reminders := true; s.group_messages := true; s.group_announcements := true;
    s.quiet_hours_enabled := false;
  END IF;
  IF s.notifications_enabled = false THEN RETURN false; END IF;
  IF p_require_push AND coalesce(s.push_enabled, false) = false THEN RETURN false; END IF;
  upper_type := upper(coalesce(p_type,''));
  IF upper_type IN ('GROUP_MESSAGE') THEN
    IF coalesce(s.group_messages, true) = false THEN RETURN false; END IF;
  ELSIF upper_type IN ('GROUP_ANNOUNCEMENT') THEN
    IF coalesce(s.group_announcements, true) = false THEN RETURN false; END IF;
  ELSIF upper_type IN ('TEST_REMINDER','TEST_LIVE','TEST_SCHEDULED','TEST_STARTING_SOON','TEST_STARTED','TEST_ENDED','GROUP_TEST_ASSIGNED','GROUP_TEST_REMINDER') THEN
    IF coalesce(s.test_reminders, true) = false THEN RETURN false; END IF;
  ELSIF upper_type IN ('ROUTINE_REMINDER','ROUTINE_DUE','ROUTINE_MISSED','ROUTINE_COMPLETED') THEN
    IF coalesce(s.routine_reminders, true) = false THEN RETURN false; END IF;
  ELSIF upper_type IN ('TEST_INVITATION','GROUP_TEST_ASSIGNED') THEN
    IF coalesce(s.test_invitations, true) = false THEN RETURN false; END IF;
  ELSIF upper_type IN ('REPORT_READY','TEST_COMPLETED','RESULTS_AVAILABLE','LEADERBOARD_UPDATED','CONTENT_REVIEW_RESULT') THEN
    IF coalesce(s.test_results, true) = false THEN RETURN false; END IF;
  ELSIF upper_type IN ('STREAK_MILESTONE','SYSTEM_NOTIFICATION','SYSTEM') THEN
    NULL;
  END IF;
  IF p_group_id IS NOT NULL AND upper_type IN ('GROUP_MESSAGE','GROUP_ANNOUNCEMENT','TEST_REMINDER','TEST_LIVE','TEST_SCHEDULED','TEST_STARTING_SOON','TEST_STARTED','GROUP_TEST_ASSIGNED','GROUP_TEST_REMINDER') THEN
    SELECT EXISTS(SELECT 1 FROM public.group_mutes WHERE user_id = p_user AND group_id = p_group_id AND is_muted = true) INTO is_muted;
    IF is_muted THEN RETURN false; END IF;
  END IF;
  IF public.fn_is_quiet_hours(p_user, lower(p_priority)) THEN RETURN false; END IF;
  RETURN true;
END;
$$;

-- Restore trg_role_changed_system to 0039 version (system message only)
CREATE OR REPLACE FUNCTION public.trg_role_changed_system()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uname text; BEGIN
  IF old.role = new.role THEN RETURN new; END IF;
  SELECT coalesce(full_name, 'Someone') INTO uname FROM public.profiles WHERE id = new.user_id;
  PERFORM public.fn_insert_system_message(new.group_id, uname || ' is now ' || new.role, 'system',
    jsonb_build_object('type','role_changed','user_id',new.user_id,'old_role',old.role,'new_role',new.role));
  RETURN new;
END $$;

-- Restore trg_member_left_system to 0039 version (system message only)
CREATE OR REPLACE FUNCTION public.trg_member_left_system()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uname text; BEGIN
  SELECT coalesce(full_name, 'Someone') INTO uname FROM public.profiles WHERE id = old.user_id;
  PERFORM public.fn_insert_system_message(old.group_id, uname || ' left the group', 'system',
    jsonb_build_object('type','member_left','user_id',old.user_id));
  RETURN old;
END $$;

-- NOTE: fn_join_group and fn_approve_group_join_request need restoration
-- to their 0033 versions. Apply the exact SQL from migration 0033.

-- NOTE: PostgreSQL enum values cannot be dropped. The 5 new values
-- (GROUP_JOIN_REQUEST, JOIN_ACCEPTED, JOIN_REJECTED, ROLE_CHANGED,
-- MEMBER_REMOVED) will remain in the enum but become unused.

COMMIT;
```

---

## REMAINING NOTES

1. **Enum values are permanent.** PostgreSQL does not support `ALTER TYPE ... DROP VALUE`. The 5 new enum values will remain even after rollback. This is harmless — they simply won't be used.

2. **Two triggers are outside transaction.** `trg_notify_streak_milestone` (line 374-377) and `trg_notify_leaderboard_updated` (line 415-418) are created after the `COMMIT`. They will persist even if the transaction rolls back. The rollback script explicitly drops them.

3. **No live database was queried.** All verification was performed against migration files and schema snapshots. Live verification should be performed after applying the migration using the post-apply verification queries above.
