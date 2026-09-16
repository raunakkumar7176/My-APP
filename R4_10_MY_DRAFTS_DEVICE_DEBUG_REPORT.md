# R4.10 My Drafts Device Debug Report

## 1. Device

| Property | Value |
|----------|-------|
| Device | Moto G31 (ZD22257XV4) |
| Android | API 31 (Android 12) |
| Flutter | Stable channel |
| APK | `build\app\outputs\flutter-apk\app-debug.apk` |

## 2. Reproduction Steps

1. Launch app on Moto G31
2. Login with existing test account
3. Open Tests screen (bottom nav or route)
4. Tap "My Drafts" tab
5. Capture Flutter debug log (logcat or `flutter run` console)

**Expected:** Draft tests appear or "No drafts yet" empty state
**Observed (previous report):** Error displayed — "Something went wrong. Please try again."

## 3. getMyDrafts Query

```sql
SELECT * FROM public.tests
WHERE is_soft_deleted = false
  AND status = 'draft'
  AND created_by = auth.uid()
ORDER BY updated_at DESC
LIMIT 50
```

**Dart equivalent** (`test_service.dart:80-86`):
```dart
_db.select()
  .eq('is_soft_deleted', false)
  .eq('status', 'draft')
  .eq('created_by', userId)
  .order('updated_at', ascending: false)
  .range(0, 49)
```

**userId source:** `SupabaseService.client.auth.currentUser?.id` (line 75)

## 4. Result

**PENDING DEVICE TEST** — Diagnostic logging added. Build ready for device deployment.

The following log lines will appear in debug output:

### On entry:
```
getMyDrafts: userId=<UUID>, limit=50, offset=0
```

### If not authenticated:
```
getMyDrafts: currentUser is NULL — not authenticated
```

### On query start:
```
getMyDrafts: querying tests WHERE is_soft_deleted=false, status=draft, created_by=<UUID>
```

### On success:
```
getMyDrafts: returned <N> rows
getMyDrafts: row[0] id=<uuid>, title=<title>, status=draft, group_id=<null|uuid>, created_by=<uuid>, updated_at=<datetime>
```

### On PostgrestException:
```
getMyDrafts PostgrestException: code=<PGRST code>, message=<message>, details=<details>, hint=<hint>
```

### On other exception:
```
getMyDrafts unexpected error: runtimeType=<type>, error=<message>
<stack trace>
```

### UI layer:
```
_loadDrafts: calling getMyDrafts
_loadDrafts: got <N> drafts
```
or
```
_loadDrafts: error runtimeType=<type>, error=<message>, displayed="<user-facing message>"
<stack trace>
```

## 5. Original Error

**PENDING** — Will be captured from device logcat after build deployment.

Possible outcomes:

| Log output | Meaning |
|------------|---------|
| `returned 0 rows` | Query succeeds, no drafts exist (NOT an error) |
| `returned N rows` with row details | Query succeeds, drafts found |
| `PostgrestException: code=..., message=...` | Exact Supabrest error captured |
| `unexpected error: runtimeType=..., error=...` | Non-PostgREST exception (parsing, network, etc.) |
| `currentUser is NULL` | Not authenticated |

## 6. Model Parsing

**Analysis (code-level):** `Test.fromJson()` at `test.dart:109-145`

| Risk | Field | Condition |
|------|-------|-----------|
| TypeError if null | `id`, `created_by`, `title` | These are `required` + non-nullable `as String` casts. If DB returns null, throws. |
| FormatException | `starts_at`, `ends_at`, `deleted_at`, `archived_at`, `created_at`, `updated_at` | `DateTime.parse()` on invalid format. Guarded by `!= null` check. |
| Enum fallback | `status` | `_parseTestStatus()` handles null → `unknown`. Safe. |
| Safe nullable | All `num?`, `bool?`, `String?` fields | Use `as Type?` or `?.toInt()`/`?.toDouble()`. Safe. |

**Verdict:** PASS for expected data. Would FAIL only if DB returns null for `id`, `created_by`, or `title` (which should be NOT NULL).

## 7. updated_at Verification

**Risk:** `getMyDrafts()` orders by `updated_at`:
```dart
.order('updated_at', ascending: false)
```

**If `updated_at` column does not exist in the live `public.tests` schema**, PostgREST returns:
```
column "updated_at" of relation "tests" does not exist
```

This error does NOT match any pattern in `mapErrorMessage()` → would produce "Something went wrong. Please try again."

**This is the #1 suspected root cause if the query fails.** Device test will confirm.

## 8. getAccessibleTests

**Query** (`test_service.dart:44-55`):
```sql
SELECT * FROM public.tests
WHERE is_soft_deleted = false
  [AND subject_id = ?]
  [AND status = ?]
ORDER BY created_at DESC
LIMIT 100
```

**Diagnostic logging added.** Device test will show:

| Tab | Expected result |
|-----|----------------|
| Upcoming | `getAccessibleTests: returned N tests` |
| Challenge with Friends | Same query, client-side filter |
| Previous | Same query, client-side filter |
| My Drafts | Separate `getMyDrafts()` query |

If `getAccessibleTests()` succeeds but `getMyDrafts()` fails, the root cause is specific to the `getMyDrafts()` query (e.g., `updated_at` column, `created_by` filter, `status` enum cast).

If both fail, the root cause is broader (e.g., auth, network, schema).

## 9. Actual Root Cause

**ROOT CAUSE STILL NOT FOUND**

Diagnostic logging is now in place. The exact PostgrestException fields (code, message, details, hint) will be captured on device. The `updated_at` column existence is the #1 suspect.

## 10. Minimum Fix

**Do not implement until root cause is confirmed from device logs.**

| If root cause is | Fix |
|-----------------|-----|
| `updated_at` column missing | Add column to schema, or change `.order('updated_at')` to `.order('created_at')` |
| `created_by` column mismatch | Verify column name in live schema |
| `status` enum cast failure | Verify enum values in live schema |
| JWT/session error | Check auth flow, add retry logic |
| Model parsing error | Add null-safety in `Test.fromJson()` for specific field |

## 11. Security

- ✅ No RLS policy changes
- ✅ No schema changes
- ✅ No RPC changes
- ✅ No credential exposure in logs
- ✅ Diagnostic logging uses `AppLogger` only (debug builds)

## 12. Final Status

**ROOT CAUSE STILL NOT FOUND**

Diagnostic logging added to:
- `TestService.getMyDrafts()` — query-level logging with full PostgrestException fields
- `TestService.getAccessibleTests()` — query-level logging for comparison
- `TestListingScreen._loadDrafts()` — UI-level error capture

**Next step:** Deploy APK to Moto G31, reproduce the error, capture logcat output. The exact `PostgrestException.code`, `message`, `details`, and `hint` will identify the root cause.
