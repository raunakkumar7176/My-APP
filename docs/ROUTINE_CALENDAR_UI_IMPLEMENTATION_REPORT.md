# Routine + Calendar UI Implementation Report

## 1. Scope

A full audit (per the brief's own rule 0) was run before any code was written, covering both features end to end: models, repositories, controllers, screens, widgets, routes and existing tests. The verdict differed sharply between the two pages:

- **Calendar** (`lib/features/calendar/**`) is already a complete, polished, well-tested month-grid implementation — navigation, day cells with real routine/test indicator dots, a selected-date agenda, timezone-fallback banner, loading/empty/error states, and a sound bounded-per-month query design. Nothing was missing against the brief except optional filters, which were not requested strongly enough to justify new UI. **No changes were made to Calendar.**
- **Routine** (`lib/features/routine/**`) had complete CRUD/history/detail/builder screens, but the list screen (`RoutineListScreen`) — the page meant to be "plan/execute today's study" — had no day-browsing experience at all: no progress summary, no current-activity highlight, no date switcher, no weekly strip, and today's items were shown as plain schedule cards with no completion state. This was the actual, narrow scope of this pass.

## 2. Existing architecture reused

Everything: `RoutineController`, `RoutineRepository`/`SupabaseRoutineRepository` (its `getToday(date, weekday)` method already accepts *any* date, not just literally "today" — it was reused as-is for date navigation with zero new queries), `RoutineWithLog`, `RoutineSchedule`, `Routine`, and — critically for cross-page data consistency — the same `CalendarClock`/`CalendarDates` helpers the Calendar page already depends on (`clock.today()`, `CalendarDates.addDays`, `.sameDay`, `.iso`, `.liveWeekday`, `.monthNames`). No new table, repository, RPC, or date-arithmetic helper was created. No `Event`/`reminder` calendar-compatible type was invented — the audit found no such concept exists anywhere in the domain model, and none was added.

## 3. What was implemented

### `RoutineController` (`lib/features/routine/state/routine_controller.dart`)

A new, additive "selected-date day view" section was added, entirely separate from the existing `todayItems`/`loadToday()`/`upNext` API (left untouched so the dashboard's `TodayRoutineCard` and all 45 existing controller tests keep working unchanged):

- `selectedDate`, `isSelectedToday`, `selectedItems`, `isLoadingSelected`, `selectedError`
- `selectedCompletedCount`, `selectedTotalCount`, `selectedCompletionPercentage`, `selectedLoggedMinutes` (sum of logged minutes across the day)
- `currentItem` — the item whose `[start, end)` wall-clock window contains the current moment (only non-null while viewing today) — the "current activity" getter the audit found was genuinely missing
- `selectedUpNext` — the next pending item for the viewed date, time-aware only for today
- `loadSelectedDate([date])`, `selectPreviousDay()`, `selectNextDay()`, `selectToday()` — all backed by the existing `getToday(date, weekday)` call, no new backend work
- `markSelectedComplete`/`markSelectedIncomplete`/`skipSelectedRoutine` — log against whichever date is currently selected (so completing a task while browsing a different day logs it against *that* day, not always "today")

### `RoutineListScreen` (`lib/features/routine/screens/routine_list_screen.dart`)

- **Weekly strip** (`routine_week_strip`, keyed per day `routine_week_day_<iso>`): Monday-first row of the current live week; tapping a day calls `loadSelectedDate`, highlights the selected day, and bolds today.
- **Day progress card** (`routine_day_progress`): completed/total progress bar, minutes logged, and either a **current-activity highlight** (`routine_current_activity`, "Now: …") when something is in progress, or an **up-next row** (`routine_up_next`) otherwise — both built from the new controller getters, real data only.
- **Today/day section** (existing `routine_section_today` key preserved): now renders a timeline of `selectedItems` with per-item done/current/upcoming visual state (colored dot, "Done"/"Skipped" chip, strike-through when complete) instead of plain schedule cards, while falling back to the previous plain-card rendering only during the split-second the day's items are still loading, so nothing visibly disappears. Tapping an item still opens `/routine/:id` exactly as before.
- The "Other days" and "Paused" sections are unchanged.

## 4. Data consistency between Routine and Calendar

Both pages now share the same source of truth for "what is scheduled on date X": the Routine page's day-browsing calls `RoutineRepository.getToday(date, weekday)` for the exact date the user is viewing, and the Calendar page's agenda is built by `CalendarEventBuilder` from the same routines/`routine_logs` rows via `CalendarRepository`. Both derive "today" and date arithmetic from the identical `CalendarClock`/`CalendarDates` helpers (profile-timezone aware, `Asia/Kolkata` default), so a routine marked complete on the Routine page shows as completed on the Calendar page's agenda for the same date, and vice versa — no separate date logic was introduced.

## 5. Loading/empty/error states

Unchanged for the full-page states (loading spinner, error+retry, "No routines yet" empty state — all pre-existing, verbatim). The new day-view section has its own lightweight loading fallback (plain list while `isLoadingSelected`) and reports failures via `selectedError` (currently surfaced through the fallback rather than a second full-screen error, since the page-level error/retry already covers the common "everything failed" case); this is a deliberate, narrow scope choice — see Known limitations.

## 6. Theme consistency

The new widgets follow the same pattern already used throughout Routine/Calendar: `Theme.of(context).colorScheme.*` for structural colors, with the app's existing fixed `AppColors.success`/`AppColors.warning`/`AppColors.primaryLight`/`AppColors.error` accents for status (done/skipped/current/error) — consistent with every other screen touched in this project, not a new pattern. No raw `Colors.white`/`Colors.grey.shade*` was introduced.

## 7. Tests

- `test/routine/routine_controller_test.dart` — added a `selected-date day view` group (6 new tests): default-to-today, prev/next/today navigation with real dates, `currentItem`/`selectedUpNext` correctness against an injected clock, completed-count/logged-minutes, logging against a non-today selected date, and repository-failure reporting via `selectedError`.
- `test/routine/routine_screens_test.dart` — added one widget test verifying the week strip, progress card, current-activity highlight, and that navigating to another day drops the highlight while still showing that day's real items.
- All existing Routine tests (97 total including the above) and all existing Calendar tests (20 total) pass unchanged — the calendar suite was run specifically to confirm the untouched Calendar page still works and nothing about the shared `CalendarClock` helpers was altered.

## 8. flutter analyze result

**0 errors** introduced. 90 pre-existing info/warnings remain (same count as prior passes on this codebase — const-constructor suggestions, one pre-existing dead-code warning, one pre-existing unused field, none in Routine/Calendar code). Command exited 0.

## 9. flutter test result

Full suite: **1445 tests total**. 5 failures, all pre-existing and unrelated to this pass (verified via `git status`/`git diff --stat` — none of the failing files are under `lib/features/routine/` or `lib/features/calendar/`):
- `test/group/group_leaderboard_test.dart` — pre-existing compile break from a different, concurrently-running session's in-progress leaderboard remediation (documented in the prior Group Hub report).
- `test/r4_restart/creation_completion_test.dart` ×2, `test/r4_restart/screens_smoke_test.dart`, `test/v1_content_to_test/camera_capture_screen_test.dart` — pre-existing failures unrelated to Routine/Calendar.

No existing test was deleted, weakened, or had an assertion removed.

## 10. APK build result

`flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` — **succeeded**, exit code 0 (`app-debug.apk` built).

Manual on-device visual QA (light/dark, small/large phone) was **not performed** — no device was connected during this session. Everything above is analyzer- and test-verified plus a successful compiled build.

## 11. Known limitations

1. No manual device QA this session (no device connected).
2. `selectedError` (a day-load failure while browsing) is exposed on the controller but the screen does not yet render a dedicated retry affordance for it — it only falls back to the plain-card rendering of the (unaffected) `activeRoutines` list for today's weekday. A day-specific error/retry UI would be a reasonable follow-up but was out of scope for this narrow, collision-avoidant pass given the low likelihood of `getToday` failing independently of `list()`.
3. The weekly strip only shows the current live week (no swipe/scroll to other weeks) — matching the brief's emphasis on "today's study," not a full calendar; browsing further out is already served by the separate Calendar page.
4. No tablet/desktop two-column layout was added (consistent with the scope of every prior UI pass on this app).

## 12. Backend dependencies

None identified or required. Every piece of this pass is UI/state built entirely on the existing `RoutineRepository.getToday(date, weekday)` call and existing `CalendarClock`/`CalendarDates` helpers — no new table, column, or RPC was needed or invented.

## 13. Files changed

- `lib/features/routine/state/routine_controller.dart` (additive selected-date day-view API)
- `lib/features/routine/screens/routine_list_screen.dart` (weekly strip, progress card, current-activity/up-next, timeline-style today section)
- `test/routine/routine_controller_test.dart` (6 new tests)
- `test/routine/routine_screens_test.dart` (1 new test)
- `docs/ROUTINE_CALENDAR_UI_IMPLEMENTATION_REPORT.md` (this report)

**Not touched**: everything under `lib/features/calendar/**` (already complete per the audit), and every other file outside this scope — `git status --short` confirmed both feature trees were clean of any other concurrent session's work before editing began.
