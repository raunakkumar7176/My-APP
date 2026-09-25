# Supabase Email Verification — Localhost Redirect Fix

## Root cause (audit)

`AuthService.signUp()` (`lib/core/services/auth_service.dart`) called `GoTrueClient.signUp()` with **no `emailRedirectTo`**. With none supplied, Supabase falls back to the project's dashboard **Site URL**, which for this project is still the Next.js dev default (`http://localhost:3000`, the same default seen in `lib/app/app_config.dart`'s unrelated `nextApiUrl`). That is the entire bug — not a bad app_config value, not a missing web build, just a missing `emailRedirectTo` parameter.

`AndroidManifest.xml` had **no deep-link intent-filter at all** — even with a correct `emailRedirectTo`, tapping the email link would have had no app to open.

`supabase_flutter: ^2.17.2` (checked in the pub cache, `lib/src/supabase_auth.dart`) already registers its own deep-link listener inside `Supabase.initialize()` whenever `FlutterAuthClientOptions.detectSessionInUri` is true — the **default**, and this project never overrides it. That listener watches every incoming app link, and for any link carrying `code`/`access_token`/`error` (query or fragment) it calls `getSessionFromUrl(uri)` automatically, which fires `onAuthStateChange`. `AuthService.initialize()` already subscribes to that stream and flips `AuthStatus`, and `app_router.dart` already redirects based on `AuthStatus` (`redirect:` at line 64, subscribed via `AuthService.authStatusStream` at line 490). **This whole chain already existed and needed zero changes** — the only two things missing were the redirect URL itself and the manifest entry to open the app for it.

## Files changed

| File | Change |
|---|---|
| `lib/core/services/auth_service.dart` | Added `AuthService.emailVerificationRedirectUrl` constant (`my-preparation://auth-callback`) and passed it as `emailRedirectTo:` in `signUp()`. No other method touched. |
| `android/app/src/main/AndroidManifest.xml` | Added one `VIEW`/`BROWSABLE` intent-filter (`android:scheme="my-preparation" android:host="auth-callback"`) inside the existing `MainActivity` block. `android:exported="true"` was already set (needed for any deep link to reach the activity). Nothing else in the manifest changed. |
| `test/auth_email_redirect_test.dart` | New — 4 focused tests (see below). |

Nothing in `app_router.dart`, `supabase_service.dart`, the sign-in/sign-out paths, or any DB/RLS/schema was touched.

## Exact Supabase Dashboard settings required

**Authentication → URL Configuration → Redirect URLs** — add exactly:

```
my-preparation://auth-callback
```

(Site URL can stay as-is; GoTrue only needs the callback URL in the redirect **allow-list** — `emailRedirectTo` values not on this list are rejected.)

**Authentication → Email Templates → Confirm signup** — no edit needed if it uses the default `{{ .ConfirmationURL }}` variable (Supabase builds this from the `emailRedirectTo` passed at signup, not from a hardcoded host). Only check this if someone previously hand-edited the template to hardcode a `localhost` URL instead of using `{{ .ConfirmationURL }}` — the repo itself has no custom template files (confirmed by search), so any template edit needed is dashboard-only and outside this repo's scope.

## Exact redirect URI

```
my-preparation://auth-callback
```

Must match **exactly** in three places: `AuthService.emailVerificationRedirectUrl`, the manifest's `android:scheme`/`android:host`, and the Dashboard allow-list. `test/auth_email_redirect_test.dart` guards the first two against drifting apart; the third is manual (dashboard is outside the repo).

## APK output path

```
D:\my_praperation\build\app\outputs\flutter-apk\app-release.apk
```

Built with `flutter build apk --release --dart-define-from-file=dart-defines.dev.json` (65.8MB, real release keystore signing already configured from an earlier phase this session).

## Test results

```
flutter analyze lib/core/services/auth_service.dart test/auth_email_redirect_test.dart
  No issues found!

flutter test test/auth_email_redirect_test.dart
  4/4 passed:
    - emailVerificationRedirectUrl is a custom scheme, never localhost or an http(s) URL
    - AndroidManifest.xml declares a VIEW/BROWSABLE intent-filter for the callback scheme
    - scheme/host in the manifest match AuthService.emailVerificationRedirectUrl exactly
    - MainActivity is exported

flutter test (full suite)
  1491 tests, 10 failing — all 10 in files this change never touched:
    - 4 in group_leaderboard_test.dart (pre-existing collision with a concurrent
      session's in-progress rewrite of group_leaderboard_controller.dart, documented
      in earlier reports this session)
    - 3 in creation_completion_test.dart, 1 in save_status_test.dart, 1 in
      screens_smoke_test.dart (pre-existing, same documented collision area)
    - 1 in camera_capture_screen_test.dart (new file from the same concurrent
      session's untracked work, not touched by this change)
  Zero new failures from this change.

flutter build apk --release --dart-define-from-file=dart-defines.dev.json
  √ Built build\app\outputs\flutter-apk\app-release.apk (65.8MB)
```

## Manual verification still required (fresh signup → tap link → app opens)

Could not be executed from this environment — no browser-automation tool and, per the task's own step 3/8, the Dashboard redirect-URL allow-list must be updated by a human with project access before any real confirmation email will work end-to-end. Once that's done, the manual check is:

1. Install `app-release.apk` on a device.
2. Sign up with a real email.
3. Confirm the email lands with a link starting `my-preparation://auth-callback?...` (not `localhost`).
4. Tap it → My Preparation opens directly (no browser chooser prompt persisting, no "page not found").
5. App reaches the authenticated screen without a manual re-login (proves `getSessionFromUrl` → `onAuthStateChange` → router redirect fired).
6. Existing password login and logout — unchanged code paths, verified by inspection only (not re-tested live) since neither was touched.

## Remaining limitations

1. **Dashboard redirect URL is not something I can add** — no Supabase credentials/CLI in this environment. Until a human adds `my-preparation://auth-callback` to the allow-list, GoTrue will reject the `emailRedirectTo` and may fall back to the Site URL again.
2. **No live device/email verification was run** — same missing-access reason as every other phase this session; the manual steps above are ready for whoever has dashboard + device access.
3. iOS was not touched (no `Info.plist` URL scheme added) — this task was scoped to Android only, per the request.
