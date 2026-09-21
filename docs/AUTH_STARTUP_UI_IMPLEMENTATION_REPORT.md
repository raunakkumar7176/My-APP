# Auth + Startup UI Implementation Report

## 1. Scope

A full audit (per the brief's own repeated instruction to inspect before building) was run before any code was written, covering app bootstrap, native Android launch screen, app icon, the Flutter-side splash, GoRouter's auth redirect, `AuthService`, the login/signup screens, and the theme system. The verdict: **the Dart-side experience the brief asks for was already built, and built well** — a branded `SplashScreen` using `AppLogo`, a polished neumorphic (`Neu`) 3D flip-card `AuthScreen` combining login and signup, an `AuthService` with friendly error mapping, and a `GoRouter` redirect architecture specifically designed to prevent any auth-state flash. The one genuine, confirmed gap was the **native Android launch screen and app icon**, which were still the stock, unbranded Flutter defaults — a plain white/black screen and the default Flutter icon — because no logo asset file had ever been placed at `assets/branding/logo.png` (only a vector fallback existed) and the native `drawable`/`mipmap` resources had never been touched. That gap is the actual scope of this pass.

## 2. Existing architecture reused (not rebuilt)

Everything on the Dart side: `AppLogo` (`lib/features/auth/widgets/app_logo.dart`), `SplashScreen` (`lib/features/auth/splash_screen.dart`), `AuthScreen` (`lib/features/auth/auth_screen.dart`, the combined login/signup flip card), the `Neu` neumorphic design-token system (`lib/features/auth/widgets/neumorphic.dart`), `AuthService` (`lib/core/services/auth_service.dart`, sign in/up/out, status stream, friendly error mapping), and the `GoRouter` redirect (`lib/app/app_router.dart`, `AuthStatus.unknown` gates everyone on `/` until the session check resolves, so there is no flash of `/login` before authentication state is known). **None of these files were modified.** No new login/signup screen, no new splash widget, no new auth logic, no new router redirect logic, no new design system was created — all of that already existed and already matched the brief's intent (premium, branded, no raw Supabase errors, no duplicate-submit risk, friendly validation).

Forgot-password: confirmed absent everywhere (no route, no screen, no `AuthService` method) — per the brief's own instruction, this was **not invented**.

## 3. What was implemented

### The actual brand logo asset

`assets/branding/logo.png` did not exist before this pass — `AppLogo` was silently falling back to its `CustomPainter` vector approximation on every screen. The user-supplied logo artwork (a JPG on a white background) was processed with a small one-off script (using the already-a-dependency `image` package) that:
1. Flood-fills from the four image corners to clear only the connected white background, leaving the white "P" glyph (which is enclosed by the black circle, not touching the corners) fully intact.
2. Crops tightly to the circle's bounding box with a small margin.
3. Resizes to a 512×512 PNG with a transparent background outside the circle.

The result was written to `assets/branding/logo.png`, which `AppLogo` already looks for by convention — so every screen using `AppLogo` (splash, login, signup) now renders the real supplied artwork instead of the vector approximation, with zero code changes to `AppLogo` itself.

### Native Android launch screen (the confirmed gap)

- `android/app/src/main/res/values/colors.xml` (new) and `values-night/colors.xml` (new): a `launch_background` color resource — `#FFEEF2F7` (matches `Neu.base`, the exact background the Dart `SplashScreen`/`AuthScreen` already use) for light, `#FF121212` (a standard dark surface tone) for the OS-level dark-mode variant. The native layer runs before the Flutter engine starts, so it can only follow the OS dark-mode setting, not the app's persisted `ThemeService` preference — this is a hard platform limitation, not an oversight.
- `android/app/src/main/res/drawable/branding_logo.png` (new): a 240×240 raster of the same logo, for the native `<bitmap>` layer.
- `android/app/src/main/res/drawable/launch_background.xml` and `drawable-v21/launch_background.xml` (both edited): replaced the stock `@android:color/white` / `?android:colorBackground` layer-list with `@color/launch_background` plus a centered `@drawable/branding_logo` bitmap layer.

Result: the OS-level launch screen (visible for the brief moment between process start and Flutter's first frame) now shows the same background color and the same logo as the Flutter `SplashScreen` that immediately follows it — no blank white/black flash, no visible color or content jump at the handoff. No new package (`flutter_native_splash` or similar) was added; this was a direct, minimal edit of the existing stock resource files, consistent with the brief's own preference for a minimal solution over introducing dependencies.

### App launcher icon

`android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` were regenerated from the same source logo at their correct recommended sizes (48/72/96/144/192px) and written in place, replacing the stock Flutter template icon. This is a **legacy (non-adaptive) icon replacement** — no `mipmap-anydpi-v26/ic_launcher.xml` foreground/background adaptive icon was added, and no `flutter_launcher_icons` package was introduced, again favoring the minimal direct edit over a new dependency. See Known limitations for what a follow-up adaptive-icon pass would add.

## 4. Startup sequence after this change

```
Process start
   ↓
Native launch screen (Neu.base #EEF2F7 / #121212 dark, centered logo)  ← was blank white/black, now branded
   ↓
Flutter engine first frame → SplashScreen (same background, AppLogo, fade+scale animation)  ← unchanged, already existed
   ↓
AuthStatus resolves (unknown → authenticated/unauthenticated)
   ↓
Authenticated → /home (AppShell)        Unauthenticated → /login (AuthScreen)
```

No redirect/flash logic was touched — the existing `_AuthRefreshListenable` + `redirect` callback in `app_router.dart` already prevented any visible auth-state flicker; this pass only removed the *pre-Flutter* blank-screen gap that existed before that logic ever runs.

## 5. Theme / dark mode

The native launch screen now has a light/dark split (see above). The Dart-side `AuthScreen`/`SplashScreen` remain light-mode-only (hardcoded `Neu.base`), exactly as they were before this pass — extending the `Neu` system to respond to dark mode is a real, separate piece of work (the audit confirmed `Neu` is entirely independent of `MaterialApp`'s `theme`/`darkTheme`) that was out of scope for this narrow, collision-safe pass; see Known limitations.

## 6. Tests

No Dart code was changed (`AppLogo`, `SplashScreen`, `AuthScreen`, `AuthService`, router — all untouched), so no test changes were needed or made. The existing auth/route tests were run to confirm the asset change didn't regress anything:
- `test/features/auth_screen_test.dart` — 4/4 pass (login/signup flip, validation, password visibility).
- `test/app_routes_test.dart` — 2/2 pass (route table completeness).

## 7. flutter analyze result

`flutter analyze lib/features/auth lib/main.dart` — **0 issues**. (Full-repo analyze was already verified clean of new errors in the immediately preceding Routine/Calendar pass this session; this pass touched no additional Dart files.)

## 8. flutter build apk result

`flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` — **succeeded**, exit code 0, after fixing one real build error along the way: AAPT2 rejected a raw hex color literal directly on `android:drawable` in the layer-list items (`'#FFEEF2F7' is incompatible with attribute drawable (attr) reference`), which is why the background is expressed as a proper `@color/launch_background` resource rather than an inline hex string.

## 9. Manual device verification

**Not performed this session — no Android device was connected** (`flutter devices` showed only Windows desktop and the two browser targets). This is an analyzer- and build-verified change, not a visually-confirmed-on-device one. Given this change is entirely to static native resources (colors, a bitmap, launcher icons) with no Dart logic involved, the risk is low, but the brief explicitly asks for device verification — flagging this honestly rather than claiming it was done.

## 10. Known limitations

1. **No device QA this session** (see §9).
2. **Legacy, non-adaptive app icon.** The `ic_launcher.png` files were replaced directly; a proper Android 8+ adaptive icon (separate foreground/background layers via `mipmap-anydpi-v26/ic_launcher.xml`, ideally via `flutter_launcher_icons` for round-icon and monochrome-icon variants too) was not implemented, in favor of the minimal, dependency-free fix. The current icon still displays correctly on all API levels, just without adaptive masking/animation.
3. **Dark mode is native-only, not Dart-side.** The native launch screen now respects OS dark mode; the Dart `SplashScreen`/`AuthScreen` do not (pre-existing behavior, unchanged) — extending `Neu` for dark mode is a separate, larger piece of work not attempted here.
4. **Forgot-password remains unimplemented**, confirmed absent and intentionally not fabricated, per the brief's own instruction.
5. The native launch bitmap (`drawable/branding_logo.png`) is a single fixed-size (240px) resource with no density-specific variants (`drawable-hdpi`, `-xhdpi`, etc.) — a deliberate minimal-solution choice; it is only on screen for a fraction of a second before Flutter's own density-correct `AppLogo` takes over, so the softness at very high densities is a non-issue in practice.

## 11. Backend dependencies

None. This entire pass is a native-resource and asset addition; no Supabase schema, RLS, auth policy, or `AuthService` logic was touched.

## 12. Files changed

- `assets/branding/logo.png` (new — the real supplied logo, processed to a transparent-background PNG)
- `android/app/src/main/res/values/colors.xml` (new)
- `android/app/src/main/res/values-night/colors.xml` (new)
- `android/app/src/main/res/drawable/branding_logo.png` (new)
- `android/app/src/main/res/drawable/launch_background.xml` (edited)
- `android/app/src/main/res/drawable-v21/launch_background.xml` (edited)
- `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher.png` (replaced)
- `docs/AUTH_STARTUP_UI_IMPLEMENTATION_REPORT.md` (this report)

**Not touched**: every Dart file in `lib/features/auth/`, `lib/app/app_router.dart`, `lib/main.dart`, `lib/core/services/auth_service.dart`, and `lib/core/services/theme_service.dart` — all confirmed already complete by the audit. `lib/features/auth/widgets/app_logo.dart` shows as modified in `git status` from a different, concurrently-running session (a purely cosmetic `dart format` reflow, confirmed via diff) and was left exactly as-is, not included in this pass's commit.
