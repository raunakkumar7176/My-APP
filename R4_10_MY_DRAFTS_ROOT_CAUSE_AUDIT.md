# R4.10 My Drafts Root Cause Audit

## 1. Live RLS Evidence

**Verified LIVE policies on `public.tests`:**

| Policy | Command | Roles | USING |
|--------|---------|-------|-------|
| "standalone owner read test" | SELECT | authenticated | `(group_id IS NULL) AND (created_by = auth.uid())` |
| "creator sees soft-deleted" | SELECT | authenticated | `created_by = auth.uid()` |
| "member read tests" | SELECT | authenticated | `(group_id IS NOT NULL) AND (is_soft_deleted = false) AND fn_is_member(group_id, auth.uid())` |

**Conclusion:** RLS policies are OR-combined. Policy 2 ("creator sees soft-deleted") grants the creator read access to ALL their own tests regardless of `group_id`, `status`, or `is_soft_deleted`. A creator CAN read their own standalone draft tests. **The previous conclusion "There is no authenticated SELECT policy for own drafts" is INCORRECT.**

---

## 2. Runtime Reproduction

**User action:**
1. Authenticated user opens Tests screen
2. Taps "My Drafts" tab
3. Expected: sees draft tests or empty state
4. Observed: error displayed (per previous report)

**Exact error flow:**
```
TestListingScreen.initState()
  → _loadDrafts()
    → TestService.getMyDrafts(limit: 50)
      → SupabaseService.client.from('tests').select()...
        → PostgrestException OR success
      → [on PostgrestException]: DataError(message: mapErrorMessage(e.message))
      → [on other error]: DataError(message: 'Failed to load drafts. Please try again.')
    → [on DataError]: _draftsError = e.toString().replaceFirst('AppError: ', '')
```

**Note:** Cannot reproduce device-side from this environment. Analysis is code-level only.

---

## 3. getMyDrafts Query

**Exact Supabase query structure:**

```dart
_db                         // SupabaseService.client.from('tests')
  .select()                 // SELECT *
  .eq('is_soft_deleted', false)  // WHERE is_soft_deleted = false
  .eq('status', 'draft')         // AND status = 'draft' (enum 'test_status')
  .eq('created_by', userId)      // AND created_by = <auth.uid()>
  .order('updated_at', ascending: false)  // ORDER BY updated_at DESC
  .range(0, 49)                 // LIMIT 50 OFFSET 0
```

**SQL equivalent:**
```sql
SELECT * FROM public.tests
WHERE is_soft_deleted = false
  AND status = 'draft'
  AND created_by = auth.uid()
ORDER BY updated_at DESC
LIMIT 50
```

**userId source:** `SupabaseService.client.auth.currentUser?.id` (line 75)
**status value:** String `'draft'` (literal), compared against `test_status` enum
**is_soft_deleted condition:** Boolean `false`

**Query parameters:** `table=tests`, no specific columns (SELECT *), filters on 3 columns, ordered by `updated_at`, range-limited.

---

## 4. User Identity

| Field | Source | Value |
|-------|--------|-------|
| Authenticated user ID | `SupabaseService.client.auth.currentUser?.id` | Runtime UUID |
| getMyDrafts userId | Same as above (line 75) | Same UUID |
| RPC-created draft `created_by` | `auth.uid()` inside `rpc_create_test` (SECURITY DEFINER, line 274) | Same auth context |
| Policy `created_by = auth.uid()` | Server-side JWT | Must match |

**Identity chain is consistent.** The `auth.uid()` used in `rpc_create_test` (to set `created_by`) is the same `auth.uid()` evaluated in RLS policy `created_by = auth.uid()`. The Flutter client's `currentUser.id` is the same UUID.

**Potential edge case:** If the JWT expires between test creation and draft listing, `auth.uid()` inside `rpc_create_test` would still match because the RPC executes within the original session. But `getMyDrafts()` executes as a new PostgREST request with the (possibly refreshed) JWT. If the Supabase client auto-refreshes the JWT, `auth.uid()` in the new request should match. If not, `auth.uid()` could return NULL or a different user, causing the query to return 0 rows (not a PostgrestException).

---

## 5. Draft Data

**For the getMyDrafts query to return results, the draft test must satisfy:**

| Column | Required Value | RLS Policy | Notes |
|--------|---------------|------------|-------|
| `id` | Any UUID | No filter | Always present |
| `created_by` | Must equal `auth.uid()` | Policy 2: `created_by = auth.uid()` | ✅ Matches query |
| `group_id` | NULL (for Policy 1) or any (Policy 2 overrides) | Policy 2 is broader | Policy 2 allows any group_id |
| `status` | `'draft'` (enum) | No filter in policy | Query-side filter |
| `is_soft_deleted` | `false` | No filter in policy | Query-side filter |
| `title` | Any string | No filter | Always present |

**Does the draft actually exist?** Cannot verify without live database access.

**Does `created_by = auth.uid()`?** Should be true if the same user created the draft.

**Does `group_id IS NULL`?** Required for Policy 1 only. Policy 2 ("creator sees soft-deleted") overrides this — the creator can see drafts with any `group_id` value.

**Does `status = 'draft'`?** Should be true — `rpc_create_test` always sets `status = 'draft'::test_status`.

**Does `is_soft_deleted = false`?** Should be true for non-deleted drafts.

---

## 6. Original Supabase Error

**Cannot capture the original error** from this environment. The mapped error flows through:

```
PostgrestException.message → mapErrorMessage(message) → DataError.message → e.toString() → displayed
```

**Error mapping analysis** (`test_service.dart:470-484`):

```dart
static String mapErrorMessage(String message) {
  final lower = message.toLowerCase();
  if (lower.contains('permission') || lower.contains('denied')) {
    return 'You do not have permission to perform this action.';
  }
  if (lower.contains('row-level security') || lower.contains('rls')) {
    return 'You do not have permission to view these tests.';
  }
  if (lower.contains('not found')) {
    return 'Test not found.';
  }
  if (lower.contains('network') || lower.contains('timeout')) {
    return 'Network error. Please check your connection and try again.';
  }
  return 'Something went wrong. Please try again.';
}
```

**If the displayed error is "Something went wrong. Please try again."**, the original PostgrestException message does NOT contain: `permission`, `denied`, `row-level security`, `rls`, `not found`, `network`, `timeout`.

**If the displayed error is "Failed to load drafts. Please try again."**, the error is NOT a `PostgrestException` — it's caught by the outer `catch (e)` block (`test_service.dart:94-97`).

**If the displayed error is "You must be logged in to view drafts."**, `currentUser` was null when `getMyDrafts()` was called.

**These are the only three possible error messages from `getMyDrafts()`.** Any other message comes from a different code path.

---

## 7. Model Parsing

**`Test.fromJson()` field analysis** (`test.dart:109-145`):

| Field | Type | Required | Nullable | Risk |
|-------|------|----------|----------|------|
| `id` | String | Yes | No | `as String` throws if null |
| `created_by` | String | Yes | No | `as String` throws if null |
| `title` | String | Yes | No | `as String` throws if null |
| `status` | String? → TestStatus | Yes | Via enum parser | `_parseTestStatus` handles null → `unknown` |
| `description` | String? | No | Yes | Safe |
| `duration_sec` | num? → int | No | Yes | `(json['duration_sec'] as num?)?.toInt()` safe |
| `marks_per_question` | num? → double | No | Yes | Safe |
| `starts_at` | String? → DateTime | No | Yes | `DateTime.parse` throws on invalid format |
| `ends_at` | String? → DateTime | No | Yes | Same risk |
| `deleted_at` | String? → DateTime | No | Yes | Same risk |
| `group_id` | String? | No | Yes | Safe |
| `test_mode` | String? | No | Yes | Safe |
| `updated_at` | String? → DateTime | No | Yes | `DateTime.parse` on invalid format throws |
| `tags` | List? → List\<String\> | No | Yes | Safe |

**Parsing risk:** `DateTime.parse()` calls at `starts_at`, `ends_at`, `deleted_at`, `archived_at`, `created_at`, `updated_at` will throw `FormatException` if the database returns an unparseable date string. However, these are nullable and guarded by `!= null` checks, so only non-null values are parsed.

**The `status` field** is parsed via `_parseTestStatus()` which handles null and unknown values gracefully (returns `TestStatus.unknown`).

**The `created_by` and `id` fields** are `required` and non-nullable. If the database returns null for either, `as String` would throw `TypeError`. This would be caught by the outer `catch (e)` and produce "Failed to load drafts. Please try again."

**PASS/FAIL: PASS** — No parsing issues found for expected data. Model parsing would only fail if the database returns null for `id`, `created_by`, or `title`, which should not happen given the NOT NULL constraints.

---

## 8. getAccessibleTests Audit

**`getAccessibleTests()` query structure** (`test_service.dart:37-68`):

```dart
_db.select()                          // SELECT *
  .eq('is_soft_deleted', false)       // WHERE is_soft_deleted = false
  .eq('subject_id', subjectId)        // AND subject_id = ? (if provided)
  .eq('status', status)               // AND status = ? (if provided)
  .order('created_at', ascending: false)  // ORDER BY created_at DESC
  .range(offset, offset + limit - 1)     // LIMIT/OFFSET
```

**Key difference from getMyDrafts:** No `created_by` filter. Returns ALL tests visible to the authenticated user via RLS.

**RLS policies that grant access:**
- Policy 1: `(group_id IS NULL) AND (created_by = auth.uid())` → creator's own standalone tests
- Policy 2: `created_by = auth.uid()` → ALL creator's own tests
- Policy 3: `(group_id IS NOT NULL) AND (is_soft_deleted = false) AND fn_is_member(group_id, auth.uid())` → group tests the user is a member of

**Impact on tabs:**

| Tab | Filter Applied | RLS Access | Status |
|-----|---------------|------------|--------|
| Upcoming | status ∈ {scheduled, published+future start} | Via getAccessibleTests + client-side filter | ✅ Should work |
| Challenge with Friends | testMode='live' + status ∈ {live, ready, published-in-window} | Via getAccessibleTests + client-side filter | ✅ Should work |
| Previous | status ∈ {completed, ended, evaluated, cancelled, archived, expired} + published+past end | Via getAccessibleTests + client-side filter | ✅ Should work |
| My Drafts | Separate query: status='draft', created_by=auth.uid() | Via getMyDrafts + RLS | ✅ Should work (RLS allows) |

**`getAccessibleTests()` can actually return draft tests too**, because there's no `status` filter in the query (only `is_soft_deleted = false`). RLS Policy 2 allows the creator to see all their own tests. So `getAccessibleTests()` would return the user's draft tests in the `_allTests` list. However, the client-side category filters (`_isUpcoming`, `_isChallengeWithFriends`, `_isPrevious`) would exclude draft tests from those tabs. Drafts would only appear in the "My Drafts" tab, which uses the separate `getMyDrafts()` query.

**If `getAccessibleTests()` fails**, it would show an error on the Upcoming/Challenge/Previous tabs, not on the My Drafts tab. The My Drafts tab has its own independent error state (`_draftsError`).

---

## 9. Actual Root Cause

**ROOT CAUSE NOT DEFINITIVELY IDENTIFIED** — Cannot reproduce from this environment.

**Ranked hypotheses based on code analysis:**

### Hypothesis A (Most Likely): No actual error — empty results misperceived as failure

`getMyDrafts()` returns an empty list successfully. The UI shows "No drafts yet" (`_buildDraftsEmptyState()`). If the user expects to see a draft they created, this could be perceived as a failure.

**Possible reasons for empty list:**
1. The test was created under a different user account
2. The test was soft-deleted
3. The test status was changed from 'draft' (e.g., published)
4. The test was created with `group_id` set (via group mode) — BUT Policy 2 ("creator sees soft-deleted") still allows this, so the draft SHOULD appear

### Hypothesis B: Non-RLS PostgREST error

A PostgREST error occurs that doesn't match any pattern in `mapErrorMessage()`. Possible errors:
- `"JWT expired"` / `"invalid JWT signature"` — JWT validation failure
- `"column \"X\" does not exist"` — schema mismatch (e.g., `updated_at` column missing)
- `"invalid input value for enum test_status: \"draft\""` — enum casting failure
- `"relation \"tests\" does not exist"` — schema cache issue

These would all produce "Something went wrong. Please try again."

### Hypothesis C: Model parsing error

`Test.fromJson()` throws a `TypeError` or `FormatException` when parsing a specific test record. This would produce "Failed to load drafts. Please try again." (different from "Something went wrong.").

**Most likely scenario:** A test has a non-null `created_by`, `id`, or `title` that is somehow not a String (e.g., integer from a different client), causing `as String` to throw.

### Hypothesis D: Transient network error

The PostgREST request fails with a non-timeout network error (e.g., connection reset, DNS failure) that doesn't contain 'network' or 'timeout' in the error message.

---

## 10. Minimum Fix

**No fix can be prescribed without confirming the actual error.** The fix depends on which hypothesis is correct:

| Hypothesis | Fix |
|------------|-----|
| A: Empty results | No fix needed — user education or debug logging |
| B: Non-RLS PostgREST error | Add error pattern for JWT/schema errors to `mapErrorMessage()` |
| C: Model parsing error | Add null-safety checks in `Test.fromJson()` for required fields |
| D: Transient network error | Add 'connection' to network error pattern in `mapErrorMessage()` |

**Recommended immediate action:** Add verbose logging to capture the ORIGINAL `PostgrestException.message` (not the mapped message) so the actual error can be identified during device testing.

**Current logging** (`test_service.dart:92`):
```dart
AppLogger.error('getMyDrafts PostgrestException: ${e.message}');
```

This already logs the original error. To expose it in the UI during development, temporarily display `e.message` instead of the mapped message.

---

## 11. Security Impact

- ✅ No new RLS policy required
- ✅ No broad SELECT access
- ✅ No access to other users' private drafts
- ✅ Group access unchanged (Policy 3)
- ✅ No schema changes
- ✅ No RPC changes
- ✅ No credential exposure

---

## 12. Final Status

**ROOT CAUSE NOT FOUND**

The live RLS policies DO permit own-draft reads. The previous conclusion was wrong. The actual runtime error (if any) cannot be identified from code analysis alone. Device testing with verbose logging is required to capture the original PostgREST error message.
