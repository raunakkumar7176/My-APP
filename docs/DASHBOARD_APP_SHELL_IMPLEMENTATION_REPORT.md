# Dashboard & App Shell Implementation Report

## 1. Screens changed

**New:**
- `lib/app/app_shell.dart` — `AppShell`: single AppBar + Drawer + bottom nav shell, 5 tabs.
- `lib/app/widgets/app_drawer.dart` — `AppDrawer`.
- `lib/features/dashboard/dashboard_screen.dart` — `DashboardScreen` (Home tab): greeting, date/day/time, today's routine, quick actions, upcoming test + countdown, recent performance.
- `lib/features/dashboard/widgets/dashboard_quick_actions.dart` — `DashboardQuickActions` grid.
- `lib/features/dashboard/study_tab_screen.dart` — `StudyTabScreen` (Study tab).
- `lib/features/dashboard/tests_tab_screen.dart` — `TestsTabScreen` (Tests tab).
- `lib/features/dashboard/profile_tab_screen.dart` — `ProfileTabScreen` (Profile tab).
- `lib/features/performance/performance_screen.dart` + `lib/features/performance/state/performance_controller.dart` — Performance tab/screen (`PerformanceController extends DisposableNotifier`).
- `lib/features/leaderboard/leaderboard_hub_screen.dart` — `LeaderboardHubScreen` (group → test picker, hands off to the existing per-test leaderboard).
- `lib/features/notifications/notifications_hub_screen.dart` — `NotificationsHubScreen` (per-group unread summary, hands off to the existing per-group notification screen).
- `lib/features/settings/settings_screen.dart` — `SettingsScreen` (theme, and links into existing preference surfaces).
- `lib/core/services/theme_service.dart` — `ThemeService` (persisted `ThemeMode`, default light).

**Removed:**
- `lib/features/home/home_screen.dart` — superseded by `AppShell` + `DashboardScreen`. Nothing else referenced it (confirmed with a repo-wide grep before deleting); the router's `/home` route now builds `AppShell` instead.

**Modified:**
- `lib/app/app_router.dart` — `/home` now builds `AppShell`; added `/performance`, `/notifications`, `/leaderboard`, `/settings`.
- `lib/app/app.dart` — `themeMode` now reads live from `ThemeService.instance` via `ListenableBuilder` instead of the hardcoded `ThemeMode.system`.
- `lib/main.dart` — calls `ThemeService.initialize()` before `runApp` so the first frame already renders the persisted theme.
- `pubspec.yaml` — added `shared_preferences` (theme persistence only; no other new dependency).

## 2. Navigation changes

- **Bottom nav** (`AppShell`, Material 3 `NavigationBar`): Home · Study · Tests · Performance · Profile. Each tab is content-only (no own `Scaffold`) — the shell supplies one AppBar (title follows the active tab) and one Drawer. Tab switching is local widget state (`IndexedStack`), not a route change, so existing deep-linkable routes (`/tests`, `/subjects`, `/groups`, `/profile`, …) are untouched and still reachable by pushing on top of the shell exactly as before.
- **Drawer** (`AppDrawer`): Profile, Dashboard, My Routine, Study, Calendar, My Tests, My Drafts, Question Bank, Groups, Performance, Leaderboard, Notifications, Settings, Help/About, Logout — every item routes through an existing or newly-added named route; none of it duplicates navigation state.
- Every "deep" action from a tab (e.g. Study tab → "Browse All" → `/subjects`, Tests tab → a test card → `/tests/:id`) pushes the **existing, untouched** screen for that route — the R4 Test Engine, Study, Group and Routine route trees were not modified.

## 3. Theme changes

- `ThemeService` (`lib/core/services/theme_service.dart`): a `ChangeNotifier` singleton following the same static-service shape as `AuthService`/`ProfileService`. Persists the chosen `ThemeMode` (`light`/`dark`/`system`) to `SharedPreferences`; **default is `ThemeMode.light`** per the product requirement, never the OS setting, until the user explicitly picks Dark or System in Settings.
- `App` (`lib/app/app.dart`) wraps `MaterialApp.router` in a `ListenableBuilder` on `ThemeService.instance`, so a theme change anywhere (Settings screen) repaints the whole app immediately, and `main.dart` awaits `ThemeService.initialize()` before `runApp` so there's no flash of the wrong theme on cold start.
- `AppTheme.light` / `AppTheme.dark` (`lib/core/constants/theme/app_theme.dart`) were **not modified** — both already existed, Material 3, seeded from `AppColors`. The dashboard/shell code was audited against both:
  - All new screens read colors through `Theme.of(context).colorScheme.*` (never a hardcoded `Colors.*` for anything that must adapt — surfaces, text, outlines, primary containers).
  - Semantic accents (`success`/`warning`/`error` from `AppColors`, reused from the existing `TestFormatters.statusColor`) are intentionally fixed — this matches the app's existing convention (see `TestListingScreen`'s `_TestCard`) and reads fine on both backgrounds since they're mid-saturation, not near-white/near-black.
  - `Card`, `AppBar`, buttons, and inputs all inherit `AppTheme`'s existing themed shapes; no new one-off `BoxDecoration` colors were hardcoded outside of `withValues(alpha: …)` on theme colors.

## 4. Dashboard data sources

Every figure on the dashboard comes from an existing repository/service; nothing is fabricated:

| Section | Source |
|---|---|
| Greeting / date / day / time | `ProfileService.currentProfile.timezone` + `CalendarClock.toUserWall()` (same utility `RoutineController` already uses for "today") |
| Today's routine (target vs. completed) | `TodayRoutineCard` embedded as-is (owns its own `RoutineController`) |
| Upcoming test + countdown | `TestRepository.listAccessible()` bucketed with the existing `TestLifecycle.categorize(...) == ListingCategory.upcoming`, nearest `startsAt` first, capped at 3 |
| My Drafts count (quick action badge) | `TestRepository.listMyDrafts()` |
| Recent performance / latest result | Existing `previous`-category tests (same lifecycle bucketing), then `ResultRepository.mineForTest(testId)` for the most recent one with a result — capped at scanning 5 tests |
| Performance overview (tests attempted, avg score, avg accuracy, subject performance, weak areas, recent tests) | `PerformanceController`: same `previous`-bucket scan (capped at 15 tests) + `ResultRepository.mineForTest`, merged with `ResultAnalyticsMapper.subjects(result.subjectBreakdown)` |
| Study progress | `ProgressService.loadUserProgress()` (existing `progress_snapshots` table) |
| Leaderboard | Existing `rpc_get_leaderboard` via `ResultRepository.leaderboard` / `GroupLeaderboardScreen` — the hub screen only lets the user pick group + test; it never computes or displays a ranking itself |
| Notifications | Existing per-group `NotificationRepository` (`forGroup`/`unreadCount`); the hub sums unread counts across `GroupRepository.myGroups()` (a small, bounded list) since no single aggregate query exists |

No new tables, RPCs, or repositories were created. `PerformanceController` and the two hub screens are new **composition** over existing repositories only.

## 5. Responsive behavior

- Mobile (primary target): `NavigationBar` bottom nav + `Drawer`, single-column scroll bodies, `GridView` (4 columns) for quick actions.
- The shell's `Scaffold` + `Drawer` + `AppBar` combination is the same pattern Flutter uses for tablet/desktop `NavigationRail` promotion; a follow-up can swap `NavigationBar` for `NavigationRail` above a width breakpoint without touching any tab content, since tab bodies are already plain widgets with no bottom-nav-specific layout assumptions. This breakpoint swap was **not** implemented in this pass (see §10) — desktop/web currently gets the same mobile bottom-nav layout, which still works but isn't the optimized rail layout the brief describes as "where practical."
- All new screens use `SingleChildScrollView` / `ListView` with `AlwaysScrollableScrollPhysics` so pull-to-refresh and small-height screens both work; no fixed-width rows that could overflow on narrow devices (`Wrap` used for chip rows, `Expanded`/`maxLines`+`overflow: ellipsis` on titles).

## 6. Performance considerations

- No unbounded fetches: `listAccessible()`/`listMyDrafts()` already cap at 100/50 server-side; the dashboard's "recent performance" and `PerformanceController` cap how many of those are scanned for a result (5 and 15 respectively) rather than iterating the whole list.
- The bottom-nav tabs are built once and kept alive via `IndexedStack` (not rebuilt on every tab switch), so switching tabs doesn't re-trigger each tab's load.
- The unread-notification badge in the shell's AppBar is loaded once on shell init and refreshed only after returning from the notifications screen — not polled.
- No duplicate controllers: `TestsTabScreen` and the Performance/Notifications/Leaderboard screens each own a single controller/state instance for their own lifetime (standard `initState`/`dispose` pattern already used throughout the codebase, e.g. `TestListingController`, `DisposableNotifier`).

## 7. Tests

- Ran the full existing suite (`flutter test`, 1433 tests) before and after this work. **No new failures.** The same 4 pre-existing failures remain, all unrelated to this change and out of scope (see the R4 test-repair report from the previous session): `creation_completion_test.dart` (×2, `QuestionSource` availability), `screens_smoke_test.dart` (same cause), `camera_capture_screen_test.dart` (explicitly out of scope for that lane).
- No dedicated widget tests were added for the new dashboard/shell screens in this pass — see §10.

## 8. Analyze result

`flutter analyze` — **0 errors**. 88 pre-existing info/warnings (const-constructor suggestions, deprecated `RadioListTile.groupValue`/`onChanged` — the new `SettingsScreen` theme picker follows the exact same deprecated-but-still-supported pattern already used by `question_editor.dart`/`question_source_step.dart` elsewhere in the app, so it's consistent with the existing codebase rather than a new inconsistency). Command exited 0.

## 9. APK result

`flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` — **succeeded**, exit code 0 (`build\app\outputs\flutter-apk\app-debug.apk`).

**Manual on-device verification (Light/Dark/restart/login/dashboard/bottom-nav/drawer/routine/tests/groups/performance/leaderboard/profile/settings/notifications) was not performed** — no Android device was connected to this machine during this session (`adb devices` returned empty). Analyzer, the full automated test suite, and a successful compiled build are the verification actually completed; the manual walkthrough the brief asks for still needs to happen on a connected device before this is considered fully verified.

## 10. Remaining limitations

1. **No manual device verification** (see §9) — needs a connected device.
2. **No desktop/tablet `NavigationRail` breakpoint** — the shell currently renders the same bottom-nav layout at all widths; a width-based swap to a rail is straightforward to add later since tab content has no bottom-nav-specific assumptions, but wasn't implemented here.
3. **No widget tests added** for `AppShell`, `DashboardScreen`, the new tab screens, `PerformanceController`, or the hub screens — the existing suite was preserved and re-verified, but the new screens are only compile- and analyze-verified, not covered by new automated widget tests.
4. **Aggregated unread-notification count is O(groups)** — bounded and fine for a normal user's group count, but there's genuinely no single "total unread" query in the schema; a real aggregate would need a new RPC (explicitly not added here, per the "no new backend" rule).
5. **Streak tracking was intentionally omitted** — no streak concept exists anywhere in the current data model (confirmed during the architecture survey), and the brief says to include one "if existing architecture supports it." It doesn't, so nothing was invented.
6. **Avatar upload UI** was not added to any profile surface — `Profile.avatarUrl` is read-only from existing data; no upload flow exists in the codebase to reuse, and adding one would be new business logic outside this lane's scope (dashboard/shell, not profile feature internals).
