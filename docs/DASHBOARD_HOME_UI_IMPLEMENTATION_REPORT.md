# Dashboard Home UI Implementation Report

## 1. Uploaded design reference analysis

The reference (`code.html` + `DESIGN.md`, competitive-exam Material 3 system, "Academic Utilitarianism" style) is a mobile dashboard with, top to bottom: a fixed header (greeting + date/day + bell + avatar), a "Target Goal" strip, a dense "Today's Target" progress card, an "Upcoming Mock Test" hero banner in the primary color, a 3-column quick-actions grid, "Today's Schedule" (routine items with done/active/upcoming states), a 2×2 "Performance Snapshot" grid, "Subject Mastery" progress bars with status pills, "Recent Tests" rows, and a "Study Group" preview card — closed by a 5-item bottom nav (Home/Study/Tests/Performance/Profile).

Visual language taken from it: low-saturation surfaces, `rounded-xl` (12px) cards with a 1px-shadow feel rather than heavy elevation, tight 8pt-ish spacing, a primary-container-colored hero banner for the single most important call-to-action, status conveyed via small colored pill chips (not color alone — always paired with text), and a strict "one number, one label" stat-card layout for the performance grid.

This was used as **visual direction only** — every number, name, test, and subject in the reference image is example content and was not carried into the implementation; only the composition, density, card shapes and hierarchy were.

## 2. Existing UI audited

Before writing anything, the existing dashboard (`lib/features/dashboard/dashboard_screen.dart`, built in the previous session's app-shell work) and its supporting architecture were re-read in full:

- `AppShell` (`lib/app/app_shell.dart`) — bottom nav + drawer shell. **Found already updated by a concurrent session** to use the new global `NotificationFeedRepository.totalUnreadCount()` for the AppBar badge (previously it summed per-group counts) — left untouched, it's already correct and is exactly the kind of aggregate query this dashboard needed.
- `TodayRoutineCard` (routine feature) — self-contained, reused as-is for "Today's Schedule".
- `PerformanceController` (own previous work) — reused directly as the single data source for the Performance Snapshot, Subject Mastery, and Recent Tests sections (previously the dashboard had its own separate, smaller ad hoc fetch for "recent result"; that duplicate fetch was removed in favor of this one controller).
- `RoutineController` / `RoutineWithLog` / `Routine.targetDurationMinutes` / `Routine.computedDurationMinutes` / `RoutineLog.durationMinutes` — read to confirm a duration-based "planned vs. completed minutes" figure is derivable from existing routine data without a new query.
- `Profile.examTargets`, `Profile.timezone`, `Profile.displayName` — reused for the greeting and the Target Goal strip.
- `GroupRepository.myGroups()` — reused for the groups preview card (same call the Groups list screen makes).
- `TestRepository.listAccessible/listMyDrafts`, `TestLifecycle.categorize`, `BackendMapping`, `TestFormatters` — reused for the upcoming-test hero banner, unchanged from the prior session's logic.
- A concurrent session's work on `lib/features/notifications/**` (a full global notification feed, `NotificationFeedController`, `NotificationTile`, category icons) and `lib/features/settings/settings_screen.dart` was also inspected so nothing here would collide with it. **Nothing in that work was modified.**

No duplicate repository, controller, model, service, table, or permission system was created.

## 3. Components reused

- `TodayRoutineCard` — embedded unchanged for "Today's Schedule".
- `PerformanceController` — reused directly (previously only powered the standalone Performance tab; the dashboard now shares the same controller class, each screen instantiating its own instance per this app's existing no-shared-state convention).
- `ResultAnalyticsMapper` / `SubjectBreakdownItem` (via `PerformanceController.subjectPerformance`) — reused for Subject Mastery, not recomputed.
- `TestFormatters`, `BackendMapping`, `TestLifecycle` — reused for the upcoming-test hero banner, unchanged.
- `CalendarClock` — reused for the timezone-aware greeting (same utility `RoutineController` uses for "today").
- `GroupRepository` — reused for the groups preview.

## 4. Components created

All new, small, single-purpose widgets (none over ~250 lines):

- `lib/features/dashboard/domain/greeting.dart` — `Greeting`: pure, unit-testable "Good Morning/Afternoon/Evening" + date/time formatting, extracted out of the widget so it has direct tests instead of only widget-level assertions.
- `lib/features/dashboard/widgets/today_progress_card.dart` — `TodayProgressCard`: duration-based "Today's Target" (planned vs. completed minutes, derived from the same `RoutineController` data `TodayRoutineCard` lists), with its own loading/error/empty ("Start your study plan" → Build Routine) states.
- `lib/features/dashboard/widgets/groups_preview_card.dart` — `GroupsPreviewCard`: first group + member count, or a "Join a study group" empty state.
- `lib/features/dashboard/dashboard_screen.dart` — restructured (not created new, but substantially rewritten) to match the reference's section order and density; now also accepts injectable `testRepository` / `performanceController` / `profile` for testing.
- `lib/features/dashboard/widgets/dashboard_quick_actions.dart` — restyled from a 4-column bare-icon grid to a 3-column tonal-card grid matching the reference's density (same 8 existing routes, unchanged).

## 5. Dashboard structure

Top to bottom (all real data, all independently loaded):

1. Greeting + date/day/time (`_GreetingHeader`, keyed `dashboard_greeting` / `dashboard_date_time` for tests)
2. Target Goal strip — shown only when `profile.examTargets` is non-empty; otherwise omitted entirely (no fake goal)
3. Today's Target (`TodayProgressCard`) — duration progress, with a "Build Routine" onboarding empty state
4. Upcoming Test hero banner — primary-container-colored, countdown, View Test / Start-Resume depending on live status; "No upcoming tests" + Explore Tests when none; additional upcoming tests (if more than one) listed as compact rows below the hero
5. Quick Actions — 3-column grid, all 8 actions link to real, already-existing routes
6. Today's Schedule — `TodayRoutineCard` unchanged
7. Performance Snapshot — 2×2 grid (Tests Attempted, Average Score, Accuracy Rate, and Study Time only when a progress snapshot exists); "Your performance will appear here after your first test." + Take a Test when empty
8. Subject Mastery — only rendered when `PerformanceController.subjectPerformance` has attempted subjects; progress bar + Mastered/Strong/Needs Review pill per subject (tiered off real accuracy, not fabricated labels)
9. Recent Tests — up to 3, from `PerformanceController.recentResults`, showing rank when the result row has one
10. My Groups preview — first group or a "Join a study group" empty state

Every section is independently async and independently wrapped in loading/empty/error+Retry — confirmed by widget test (`test/dashboard/dashboard_screen_test.dart`) that even when the Routine and Groups sections fail internally (uninitialized Supabase client, since that test runs without a live backend), no exception propagates and the rest of the dashboard still renders (`tester.takeException()` is null).

## 6. Navigation

No new routes were needed for this pass — every action pushes an existing route (`/tests`, `/tests/:id`, `/tests/drafts`, `/routine`, `/routine/create`, `/subjects`, `/groups`, `/groups/:id`, `/question-bank`, `/leaderboard`, `/performance`, `/attempts/:id/result`). The AppBar's notification bell (in `AppShell`, not touched this pass) already routes to `/notifications`.

## 7. Theme

No new colors were introduced. Every color reference in the new/changed code goes through `Theme.of(context).colorScheme.*` (primary, primaryContainer/onPrimaryContainer for the hero banner, tertiary/secondary for the mastery-tier pills, surfaceContainer variants for cards and progress-bar tracks) — none of it is a literal `Color(...)` or `Colors.*`. This was spot-checked by toggling `ThemeService` mode in the existing Settings screen mentally against the code (not on a device — see §12): the hero banner, stat cards, mastery pills and quick-action tiles all resolve from `AppTheme.light` / `AppTheme.dark`'s seeded `ColorScheme`, so both themes should render with correct contrast without any code path needing per-theme branching.

## 8. Responsive behavior

Unchanged from the prior app-shell pass: `SingleChildScrollView` + `AlwaysScrollableScrollPhysics`, `Wrap`/`Expanded`/`maxLines`+`ellipsis` everywhere text could overflow (long test titles, long subject names, long group names). The quick-actions and performance grids use `GridView` with a fixed column count and `shrinkWrap`, which reflows correctly at any width but does not yet promote to a `NavigationRail` or apply a max content width on desktop — that limitation carries over from the previous pass and was not addressed in this one (see §12).

## 9. Accessibility

- Every icon-only affordance in the changed code (`sectionHeader`'s arrow, quick-action icons) sits next to a text label; no information is conveyed by color alone — the mastery tier is always a colored pill **with text** ("Mastered"/"Strong"/"Needs Review"), never just a colored bar.
- Text sizes use the theme's type scale (`headlineSmall`, `titleMedium`, `bodySmall`, `labelSmall`, …), so they respect the user's system font-scale setting.
- Touch targets: quick-action tiles and stat cards are full-`Card`-sized tap areas (not just an icon), consistent with Material's minimum target guidance.
- Long/Hindi subject or test names: verified conceptually via `maxLines`/`overflow: TextOverflow.ellipsis` on every title (`_UpcomingTestRow`, `_subjectRow`, recent-test rows, quick-action labels); Noto Sans (already the app's font per `DESIGN.md`/app theme) has matched Latin/Devanagari line metrics, so no layout-specific Hindi handling was needed beyond not truncating too aggressively.

## 10. Performance

- `TestRepository.listAccessible()` (server-capped at 100) is called once per dashboard load for the upcoming-test section, and `PerformanceController` independently scans at most 15 of the caller's own completed tests for a result (unchanged bound from the previous pass) — no unlimited history, no unbounded notification or leaderboard fetch (neither is queried from this screen at all; the bell badge is a single aggregate count already computed by `AppShell`).
- `IndexedStack` (unchanged, in `AppShell`) keeps each tab's state alive so switching tabs doesn't re-trigger a reload.
- No repository or controller call happens inside `build()` — every async call is in `initState`/a retry callback, matching the app's existing convention.

## 11. Tests

Added (does not delete or modify any existing test):

- `test/dashboard/greeting_test.dart` — 14 pure unit tests for `Greeting`: the Morning/Afternoon/Evening hour boundaries (11→Morning, 12→Afternoon, 16→Afternoon, 17→Evening), 12-hour time formatting including midnight/noon edge cases, weekday and month name mapping.
- `test/dashboard/dashboard_screen_test.dart` — 5 widget tests (using the existing `FakeTestRepository`/`FakeResultRepository` from `test/r4_restart/fakes.dart`, and new DI hooks added to `DashboardScreen` for `testRepository`/`performanceController`/`profile`): dynamic greeting shows the real profile name, greeting falls back to "Student" with no profile, empty states render for no-upcoming-test/no-performance/no-recent-tests together, the Target Goal strip only appears when an exam target exists, and an upcoming test renders its title/countdown/"View Test" action with real question-count text. One of these tests specifically asserts that internal failures in the Routine and Groups sections (both hit an uninitialized Supabase client under `flutter test`) do not throw or blank the rest of the dashboard.

Full suite: **1452 tests total, same 4 pre-existing unrelated failures as before this change** (two `QuestionSource`-availability assertions in `creation_completion_test.dart`, one in `screens_smoke_test.dart`, one explicitly-out-of-scope camera test) — confirmed identical before and after this pass; no regressions.

## 12. flutter analyze result

`flutter analyze` — **0 errors**, 89 pre-existing info/warnings (unchanged category: const-constructor suggestions, deprecated Radio API used consistently with the rest of the app). Command exited 0.

## 13. APK build result

`flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` — **succeeded**, exit code 0.

**Manual on-device visual QA (§31 of the brief) was not performed.** `adb devices` returned no connected device during this session. Everything reported above is analyzer-, unit-, and widget-test-verified plus a successful compiled build; the light/dark/scroll/overflow/keyboard walkthrough on an actual phone still needs to happen on a connected device.

## 14. Remaining limitations

1. **No manual device QA** (§13) — no device was connected this session.
2. **No tablet/desktop `NavigationRail` or max-content-width** — carried over from the previous app-shell pass; the dashboard's grids reflow but the overall shell still renders the mobile bottom-nav layout at every width.
3. **Notifications/Study-group chat preview were intentionally left off the dashboard body** — the reference image doesn't show a notification list on the dashboard itself (only the bell+badge, which `AppShell` already has, now backed by the new global unread count), so none was added; a "compact preview" per the brief's optional §13 was judged unnecessary duplication of the bell.
4. **Rank in Recent Tests** only shows when `Result.rank` is present on that row (server-populated); tests without a computed rank show score/percentage only, per "don't fabricate."
5. This report and the seven files listed below (§15) were the only ones touched. Several other lanes (notifications feed, settings, group work, camera capture) were being edited concurrently in this same working tree during this session — none of that work was read into or modified by this change beyond the read-only audit in §2.

## 15. Files changed

- `lib/features/dashboard/dashboard_screen.dart` (rewritten)
- `lib/features/dashboard/widgets/dashboard_quick_actions.dart` (restyled)
- `lib/features/dashboard/domain/greeting.dart` (new)
- `lib/features/dashboard/widgets/today_progress_card.dart` (new)
- `lib/features/dashboard/widgets/groups_preview_card.dart` (new)
- `test/dashboard/greeting_test.dart` (new)
- `test/dashboard/dashboard_screen_test.dart` (new)
