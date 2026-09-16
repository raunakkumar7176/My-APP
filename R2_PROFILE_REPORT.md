# R2: Supabase Profile Integration Report

## Verification Commands

| Command | Result |
|---------|--------|
| `flutter analyze` | No issues found |
| `flutter test` | 22 tests passed |
| `flutter build apk --debug` | Success |

---

## 1. Files Created

| File | Purpose |
|------|---------|
| `lib/core/models/profile.dart` | Immutable Dart model matching verified `public.profiles` schema |
| `lib/core/services/profile_service.dart` | Profile load, ensure, update; status stream; reset on sign-out |
| `lib/features/profile/profile_screen.dart` | Profile view/edit screen with form validation |

## 2. Files Modified

| File | Change |
|------|--------|
| `lib/core/services/auth_service.dart` | Loads profile after auth; resets profile on sign-out; calls `_loadProfileForSession()` |
| `lib/app/app_router.dart` | Added `/profile` route; `_AuthRefreshListenable` now also listens to `ProfileService.statusStream` |
| `lib/features/home/home_screen.dart` | Replaced placeholder with profile-aware home (initials, display name, student code, email) |
| `test/widget_test.dart` | Added 14 profile model tests; kept 8 existing auth tests |

## 3. Dependencies Added

**None.** `supabase_flutter: ^2.8.4` already included from R1.

## 4. Database Changes

**NONE.** All existing tables, triggers, functions, and RLS policies are used as-is.

## 5. Verified DB Structures Consumed

### profiles table (read)

| Column | Type | Nullable | Dart field |
|--------|------|----------|------------|
| `id` | uuid | NO | `id` |
| `full_name` | text | NO (default '') | `fullName` |
| `avatar_url` | text | YES | `avatarUrl` |
| `timezone` | text | NO (default 'Asia/Kolkata') | `timezone` |
| `created_at` | timestamptz | NO (default now()) | `createdAt` |
| `student_code` | text | YES | `studentCode` |
| `bio` | text | NO (default '') | `bio` |
| `mobile` | text | NO (default '') | `mobile` |
| `exam_targets` | text[] | NO (default '{}') | `examTargets` |

### Functions consumed

| Function | Called from | Purpose |
|----------|------------|---------|
| `fn_ensure_profile()` | `ProfileService._ensureProfile()` | Creates profile row if missing, fills metadata from JWT |
| `fn_ensure_student_code(uuid)` | **Not called** — relies on DB trigger `fn_set_student_code()` | Generates `MP-XXXXX` if student_code is NULL on INSERT |

### Triggers (passive — not called from Flutter)

| Trigger | When | Behavior |
|---------|------|----------|
| `trg_set_student_code` | INSERT on profiles | Assigns `fn_next_student_code()` if student_code is NULL |
| `trg_ensure_notif_settings` | INSERT on profiles | Ensures notification settings |

### RLS policies consumed

| Policy | Operation | How Flutter uses it |
|--------|-----------|-------------------|
| Users can manage own profile | SELECT/UPDATE/DELETE | `loadProfile()` and `updateProfile()` both filter by `auth.uid() = id` |
| own profile insert | INSERT | Profile creation via `fn_ensure_profile()` (SECURITY DEFINER) |
| fellow members read profiles | SELECT | Passive — enables future group features |
| test participants read profiles | SELECT | Passive — enables future test features |

## 6. Profile Field Mapping

| DB column | Dart field | JSON key | Editable |
|-----------|-----------|----------|----------|
| `id` | `id` | `id` | No (read-only) |
| `full_name` | `fullName` | `full_name` | Yes |
| `avatar_url` | `avatarUrl` | `avatar_url` | No (R2 scope) |
| `timezone` | `timezone` | `timezone` | Yes |
| `created_at` | `createdAt` | `created_at` | No (read-only) |
| `student_code` | `studentCode` | `student_code` | No (DB-generated) |
| `bio` | `bio` | `bio` | Yes |
| `mobile` | `mobile` | `mobile` | Yes |
| `exam_targets` | `examTargets` | `exam_targets` | Yes |

## 7. Auth Flow Integration

```
Sign In / Sign Up
       ↓
AuthService.onAuthStateChange fires
       ↓
Status → authenticated
       ↓
ProfileService.loadProfile()
       ↓
  ┌─ profile exists? ─→ load from DB → ProfileStatus.loaded
  └─ profile missing?  → fn_ensure_profile() → reload → ProfileStatus.loaded
       ↓
GoRouter.refreshListenable notified (via _AuthRefreshListenable)
       ↓
Redirect to /home
       ↓
HomeScreen loads profile for display
```

On sign out:
```
AuthService.signOut()
       ↓
Status → unauthenticated
       ↓
ProfileService.reset()
       ↓
GoRouter redirects to /login
```

## 8. Security Verification

| Check | Status |
|-------|--------|
| No service-role key in source | PASS |
| No secrets in source | PASS |
| No hardcoded user IDs | PASS |
| No client-side student code generation | PASS (relies on DB trigger) |
| Profile access uses auth.uid() via Supabase session | PASS |
| RLS remains authoritative for all operations | PASS |
| UPDATE filtered by `id = auth.uid()` | PASS |
| No cross-user profile access | PASS |
| No authorization bypass in Flutter UI | PASS |
| Profile reset on sign-out | PASS |

## 9. Tests

| Test | Result |
|------|--------|
| Profile Model: parses from JSON correctly | PASSED |
| Profile Model: handles nullable fields as null | PASSED |
| Profile Model: defaults missing fields gracefully | PASSED |
| Profile Model: serializes to JSON correctly | PASSED |
| Profile Model: toUpdateJson excludes read-only fields | PASSED |
| Profile Model: displayName returns fullName when not empty | PASSED |
| Profile Model: displayName returns studentCode when fullName is empty | PASSED |
| Profile Model: displayName returns fallback when both empty | PASSED |
| Profile Model: initials generates correctly for full name | PASSED |
| Profile Model: initials generates correctly for single name | PASSED |
| Profile Model: initials returns ? for empty name | PASSED |
| Profile Model: copyWith creates new instance with overrides | PASSED |
| Profile Model: equality works correctly | PASSED |
| ProfileStatus: has all expected states | PASSED |
| SplashScreen: renders correctly | PASSED |
| LoginScreen: renders email and password fields | PASSED |
| LoginScreen: shows validation errors for empty fields | PASSED |
| LoginScreen: shows validation error for invalid email | PASSED |
| LoginScreen: shows validation error for short password | PASSED |
| SignUpScreen: renders all form fields | PASSED |
| SignUpScreen: shows validation errors for empty fields | PASSED |
| SignUpScreen: shows password mismatch error | PASSED |

**Total: 22 tests, all passed.**

## 10. WARN/BLOCKER

### WARN

| # | Issue | Severity |
|---|-------|----------|
| 1 | `avatar_url` upload not implemented (image picker/storage). Display reads from DB. | Low (by design — R2 scope) |
| 2 | Profile loaded asynchronously on auth state change. There may be a brief moment where home screen shows before profile loads. Home screen handles this with its own loading state. | Low |
| 3 | `fn_ensure_profile()` is SECURITY DEFINER. If it fails, the profile will not exist and user sees empty state. Error handling in `ProfileService` surfaces this. | Low |

### BLOCKER

None.

## 11. Items NOT Implemented (By Design)

- **Avatar upload/storage** — No existing image picker in project
- **Offline profile caching** — Deferred to future phase
- **Profile deletion** — Not in scope
- **Student code regeneration** — Handled by DB function, not called from Flutter in normal flow

---

## Final Verdict

# APPROVE FOR R3

- Profile model matches verified DB schema exactly
- No duplicate tables, triggers, functions, or RLS policies created
- Auth flow integration is clean: load on authenticate, reset on sign-out
- Home screen displays profile data (display name, student code, email)
- Profile screen allows editing of full_name, bio, mobile, timezone, exam_targets
- Student code is displayed but never generated client-side
- All tests pass, analysis clean, APK builds

**No database modifications were made.**
