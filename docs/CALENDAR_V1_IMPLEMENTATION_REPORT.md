# Calendar V1 — Implementation Report

**Date:** 2026-09-20 · **Scope:** Calendar V1 only (no Routine / R6 / R7 / G20 file touched) · **Commit:** _see §12_

## 1. Discovery (live Supabase, read-only; Flutter checkout)

| Source | Live state used |
|---|---|
| `public.routines` | `id, user_id, subject_id, title, start_time time, end_time time, weekdays int[] (0 = Sunday … 6 = Saturday, default all), reminder_enabled, is_active, target_duration_minutes, created_at, updated_at`; RLS own rows (`own routine`); 4 live rows — **weekly recurring**, no per-date rows |
| `public.routine_logs` | `routine_id, log_date date, completed, status ∈ COMPLETED/SKIPPED/MISSED/PENDING, completed_at, duration_minutes`; UNIQUE `(routine_id, log_date)`; RLS via own routine; 0 live rows |
| `public.tests` | `starts_at / ends_at timestamptz` (nullable), `status test_status`, `group_id`; existing SELECT policies (creator, group member, standalone owner) |
| `profiles.timezone` | IANA text, default `Asia/Kolkata` (all 6 live profiles); server helper `fn_user_local_date` uses it |
| `progress_snapshots` | weekly/monthly stats jsonb, 0 rows — not needed for V1 |
| calendar / event tables | **none exist; none created** |
| Flutter | no routine feature yet (another lane is building it); `Test` model with `startsAt/endsAt` (`parseTimestamp` → local); `ProfileService.currentProfile?.timezone`; no `timezone`/`intl` package installed (pub cache offline: only `intl` — not added) |

## 2. Reused data / event sources (nothing duplicated into a new table)

- **Routine → scheduled study task**: expanded client-side per day of the visible month from `weekdays` (live 0=Sun encoding mapped from Dart's Mon=1..Sun=7 via `weekday % 7`), only on/after the routine's creation day (in the user zone) while `is_active`; an inactive routine still appears on days that have a `routine_logs` row. State from the log: COMPLETED → completed (strike-through, green dot when all day's routines are done), SKIPPED, MISSED, PENDING/none → scheduled. `duration_minutes` shown as "n min logged".
- **Test → scheduled/upcoming test**: every accessible test with `starts_at` in the month; day = user-zone day of `starts_at`; time label `HH:MM – HH:MM`; state from `status` (scheduled/published/ready/draft → scheduled, live → live, ended/completed/evaluated → ended, cancelled/archived/expired → cancelled); "Group test" vs "Test" subtitle; tap opens the existing `/tests/:id` detail. Untimed tests (no `starts_at`) are not calendar events.

## 3. Files changed

| File | Purpose |
|---|---|
| `lib/features/calendar/domain/calendar_clock.dart` | `CalendarClock` (user-zone day arithmetic, month range, time labels, injectable `now`), `CalendarDates` (grid, ISO keys, live weekday encoding) |
| `lib/features/calendar/domain/calendar_event.dart` | calendar-local `CalendarRoutine`, `CalendarRoutineLog` models (exact live columns), `CalendarEvent`, `CalendarEventBuilder` (pure) |
| `lib/features/calendar/data/calendar_repository.dart` | read-only `CalendarRepository` + Supabase impl: `routines()` (own, ≤200), `routineLogs(from,to)` (month dates, ≤1000), `testsBetween(startUtc,endUtc)` (`starts_at` range, `is_soft_deleted=false`, ≤200) |
| `lib/features/calendar/state/calendar_controller.dart` | month/selected-day state, prev/next/today/select, one bounded load per month, superseded-load guard, loading/error |
| `lib/features/calendar/screens/calendar_screen.dart` | month grid (Mon-first, 6×7, today ring, selection, routine/test dots), Today action, agenda with states, empty/loading/error+retry, timezone fallback note |
| `lib/app/app_router.dart` | `/calendar` (`calendar`) |
| `lib/features/home/home_screen.dart` | "Calendar" tile next to Groups (`home_calendar`) |
| `test/calendar/calendar_test.dart` | 20 tests |
| `docs/CALENDAR_V1_IMPLEMENTATION_REPORT.md` | this report |

## 4. Routes
`/calendar` → `CalendarScreen` (top-level, auth-guarded like `/profile`). Reached from the home screen tile. Existing routes untouched; the route-table test asserts registration.

## 5. Timezone strategy
The profile timezone (`ProfileService.currentProfile?.timezone`, default `Asia/Kolkata`) drives every day boundary — never the device clock when the zone is known. Because the app ships no tz database, `CalendarClock` resolves a table of **fixed-offset (no-DST) IANA zones** (Kolkata/Calcutta +05:30, Kathmandu +05:45, Dhaka, Colombo, Karachi, Dubai, Riyadh, Singapore, Kuala Lumpur, Tokyo, Shanghai, Hong Kong, UTC). For any other zone it falls back to device time and shows an explicit note on screen (`calendar_tz_note`) — it never silently pretends. Month queries send exact UTC instants for the user-zone month (`[1st 00:00 user, next 1st 00:00 user)`), so a test at 20:00 UTC on the 20th lands on the 21st for an IST user; a test at 18:30 UTC on the 30th lands on the 1st of the next month. Routines are wall-clock (`time without time zone`) and are displayed as stored. Tested: midnight (18:29/18:30 UTC), month boundary, December→January range, IST vs Kathmandu, fallback zone.

## 6. Performance
Per visible month exactly three bounded requests: own routines (≤200), own logs in the month's date range (≤1000), accessible tests with `starts_at` in the month's UTC range (≤200, ordered). No history scan, no per-day queries, no realtime. A newer month load supersedes an in-flight one (sequence guard) so stale results never overwrite the visible month.

## 7. Tests (`test/calendar/calendar_test.dart`, 20)
Clock: IST fixed offset & user day; midnight + month boundary + December range; round-trip & Kathmandu; fallback/default zone; grid (6×7 Monday-first, live weekday encoding). Builder: weekday recurrence / creation cut-off / inactive-with-log; states from logs; tests on user-zone day with status states and other-month exclusion; multi-event ordering. Controller: initial month = today + the three bounded calls with exact ranges; next/previous (incl. year boundary) and selection kept in month; today; selecting a leading grid day switches month; empty day + error + retry; superseded load. Screen: markers/agenda/states rendering; empty day, day selection, prev/next/today; loading → error → retry; timezone note. Route registration.

## 8. Validation
See §12 (recorded after the run): `flutter analyze`, `flutter test`, `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json`.

## 9. Limitations
- Routine entries are informational in V1 (no completion toggle here — the Routine feature owns logging; the calendar re-reads on refresh).
- DST zones fall back to device time (explicit on-screen note); adding a tz database is a dependency decision.
- Only tests with `starts_at` appear; untimed published tests are not calendar items.
- Month view only (no week/year); no reminders/notifications integration (none needed for display).
- Live `routine_logs` has 0 rows today, so completion states are proven with fixtures/unit tests, not live data.

## 10. Blockers
None for the calendar itself. Device walkthrough (`/calendar` from the home tile) remains part of the pending physical-device acceptance.

## 11. Untouched (other lanes)
Routine implementation, R6, R7 client/backend, G20, device acceptance, subscriptions/ads, backend security, `tool/`, `node_modules/`, `package*.json`, every other agent's uncommitted file.

## 12. Validation results and commit

Three lanes share the working tree, and at validation time the tree did not compile as a whole: the Routine lane's in-progress `lib/features/routine/screens/routine_detail_screen.dart` (`activateRoutine` undefined) breaks every target that imports `app_router.dart`, and `HEAD` on its own lacks the Group lane's uncommitted `canSeeFullLeaderboard` fix. Neither file is in this lane's scope and neither was touched. Validation therefore ran in a **throwaway git worktree** containing the current working tree with `app_router.dart` / `home_screen.dart` carrying **only the Calendar hunks** (exactly what this commit contains) — the unfinished Routine screen is then unreachable by the compiler, and nothing Calendar-related hides behind other lanes' edits.

| Command | Result |
|---|---|
| `flutter analyze` | 465 issues, **0 in any calendar file** (`lib/features/calendar/**`, `test/calendar/**`, the two Calendar hunks). The single `error` is `routine_detail_screen.dart:147` (Routine lane); the rest are pre-existing `info`/`warning` lints in other features. |
| `flutter test test/calendar test/app_routes_test.dart` | **22/22 passed** (20 calendar tests + route audit). |
| `flutter test` (whole suite) | 1059 passed, **3 failed** — all pre-existing and outside Calendar: `test/r4_restart/creation_completion_test.dart` ×2 and `test/r4_restart/screens_smoke_test.dart` ×1 assert "QuestionSource.books has no pipeline", which the committed R7 question-bank work changed. Not touched (R7 scope). |
| `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` | **√ Built** `build/app/outputs/flutter-apk/app-debug.apk` (Gradle `assembleDebug` 424.5s). |

**Commit:** `feat(calendar): implement calendar v1` — contains only the nine files in §3; the Routine hunks of `app_router.dart` and `home_screen.dart` were left unstaged for the Routine lane to commit.

**Note for the Routine lane:** once `routine_detail_screen.dart` compiles again, the full working tree (Calendar + Routine wiring) analyzes/tests the same way; the calendar has no dependency on Routine's Flutter code (it reads `routines` / `routine_logs` through its own read-only repository).
