# R4.10 Device Bug Fix Report

## 1. Bugs Fixed

### Bug 1: Publish Question Read-Back (PUBLISH)
`QuestionService.createQuestion()` performed an unnecessary `getQuestionById()` call after `rpc_create_question` succeeded. This did a direct client-side SELECT on `public.questions`, which is blocked by the secure questions RLS architecture. The created question already existed; the read-back was unnecessary overhead that triggered RLS failure.

**Fix:** Removed the `getQuestionById()` read-back. Changed return type from `Future<Question>` to `Future<String>` (returning the `question_id`). Both callers (`_saveDraft` and `_publishTest`) discard the returned object anyway.

### Bug 2: My Drafts RLS (MY DRAFTS)
`TestService.getMyDrafts()` does a direct SELECT on `public.tests` filtered by `status = 'draft'` and `created_by = userId`. The only SELECT policy on `tests` ("coded tests readable") was dropped in R4_3 with no replacement. RLS is enabled on the table (Supabase default). The authenticated user cannot SELECT their own drafts.

**Fix:** Created a conditional migration `R4_10_my_drafts_rls_fix.sql` that adds a minimal creator-drafts SELECT policy:
```sql
CREATE POLICY "creator_select_own_drafts" ON public.tests
  FOR SELECT TO authenticated
  USING (auth.uid() = created_by AND is_soft_deleted = false);
```
The migration uses `IF NOT EXISTS` for safety. It must be applied via Supabase SQL Editor after live verification.

**Also improved:** `TestService.mapErrorMessage()` now detects RLS-specific errors (`row-level security`) and maps them to a user-friendly message.

### Bug 3: Review State Synchronization (REVIEW)
`StepConfiguration.initState()` initialized controllers from parent props but never called `_update()` to push those values back to the parent. When the user entered `marksPerQuestion = 4` and navigated forward, the parent's `_marksPerQuestion` was only updated by `onChanged` callbacks. If `_update()` wasn't triggered before navigation (e.g., the field wasn't re-focused), the parent state remained null.

**Fix:** Added `WidgetsBinding.instance.addPostFrameCallback` in `StepConfiguration.initState()` to call `_update()` after the first frame. This ensures the parent state is synchronized with the controller values on mount.

### Bug 4: Review Data Consistency
After Bug 3 fix, the Review screen correctly receives values from the canonical parent state. `StepReview` is a `StatelessWidget` that receives `testMode` and `marksPerQuestion` directly from `_TestCreationScreenState` via `_buildCurrentStep()`.

## 2. Exact Root Cause

| Bug | Root Cause | Location |
|-----|-----------|----------|
| 1 | `getQuestionById()` does direct SELECT on `questions` table; RLS blocks client reads | `question_service.dart:186` (removed) |
| 2 | No authenticated SELECT policy on `tests` table; "coded tests readable" was dropped in R4_3 | Database RLS |
| 3 | `StepConfiguration._update()` not called during `initState()`; parent state not synced | `step_configuration.dart:56` |

## 3. Files Changed

| File | Change |
|------|--------|
| `lib/core/services/question_service.dart` | Removed `getQuestionById()` read-back from `createQuestion()`; added RLS error detection in `mapErrorMessage()` |
| `lib/core/services/test_service.dart` | Added RLS error detection in `mapErrorMessage()` |
| `lib/features/test/widgets/step_configuration.dart` | Added `addPostFrameCallback` to call `_update()` in `initState()` |
| `migrations/R4_10_my_drafts_rls_fix.sql` | New: Conditional migration for creator-drafts SELECT policy |

## 4. Supabase Changes

**MIGRATION REQUIRED** (not auto-applied):
```sql
-- R4_10_my_drafts_rls_fix.sql
-- Must be run via Supabase SQL Editor AFTER live verification
CREATE POLICY "creator_select_own_drafts" ON public.tests
  FOR SELECT TO authenticated
  USING (auth.uid() = created_by AND is_soft_deleted = false);
```

**Security impact:**
- Only authenticated users can SELECT
- Only their own non-soft-deleted tests are visible
- Does NOT expose other users' private drafts
- Does NOT expose access_code or join_code
- Does NOT change existing group access rules

**⚠️ BLOCKED:** Cannot verify live RLS state due to signup rate limiting. The migration should be applied only after confirming via Supabase dashboard that no existing creator-read policy exists.

## 5. Automated Verification

| Command | Result |
|---------|--------|
| `flutter analyze` | 132 issues (all info/warning, no errors, same count as before) |
| `flutter test` | 536 tests pass |
| `flutter build apk --debug` | Built successfully |

## 6. Device Verification

| Flow | Status |
|------|--------|
| Create Test → Step 1 (Self) → Step 2 (Duration=60, Marks=4) → Add Question → Review | **BLOCKED** (device test pending) |
| Save Draft | **BLOCKED** |
| My Drafts → Draft appears | **BLOCKED** (requires RLS migration) |
| Open Draft → Continue Editing → values preserved | **BLOCKED** |
| Publish | **BLOCKED** (Bug 1 fixed; pending device test) |
| Browse Tests → Listing loads | **BLOCKED** |

**Note:** Device verification requires:
1. Applying the RLS migration via Supabase SQL Editor
2. Running the app on the Moto G31 device

## 7. Security Verification

- ✅ `public.questions` direct SELECT remains protected (no new policies added)
- ✅ `correct_option` remains unavailable through client-safe question reads
- ✅ No service_role credentials used
- ✅ No client-side scoring
- ✅ No deadline manipulation
- ✅ No RLS bypass
- ✅ My Drafts policy only exposes creator's own non-soft-deleted tests
- ✅ Other users' private drafts are not visible

## 8. Remaining Issues

### BLOCKED: RLS Migration Not Applied
The `R4_10_my_drafts_rls_fix.sql` migration must be applied via Supabase SQL Editor. Cannot verify live RLS state due to signup rate limiting.

### BLOCKED: Device Testing Required
All device verification flows are pending. The APK is built and ready for testing on the Moto G31.

### NOTE: Publish Requires Approved Questions
`rpc_publish_test` requires at least one question with `status = 'approved'`. The UI creates questions with `status = 'pending_review'` (the RPC default). Publishing will fail with "Test must have at least one approved question" unless:
- Questions are manually approved via `rpc_update_question` with `p_status = 'approved'`
- Or the RPC default is changed (separate task, not in scope)

### NOTE: `getAccessibleTests()` Also Uses Direct SELECT
`TestService.getAccessibleTests()` also does a direct SELECT on `tests`. If the same RLS issue applies, the main test listing may also fail. This was not reported but should be verified during device testing.

## 9. Final Status

**CONDITIONAL PASS**

- ✅ Bug 1 (Publish read-back): Code fix complete
- ⚠️ Bug 2 (My Drafts): Migration created but not applied; requires live verification + SQL Editor application
- ✅ Bug 3 (Review state sync): Code fix complete
- ✅ Automated verification: All 536 tests pass, APK builds
- ❌ Device verification: Pending (requires RLS migration + device test)

**Cannot claim PASS because:**
1. RLS migration has not been applied to the live database
2. Device testing has not been performed
3. `getAccessibleTests()` may have the same RLS issue (untested)
