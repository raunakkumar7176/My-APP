# Routine V1 — Implementation Report

**Date:** 2026-09-20 · **Scope:** Personal Study Routine V1 only (no Calendar / R6 / R7 / G20 file touched) · **Commit:** `feat(routine): implement routine v1`

## 1. Existing architecture reused (discovery)

| Thing | Finding | Used how |
|---|---|---|
| `public.routines` (R3) | `id, user_id, subject_id, title, start_time time, end_time time, weekdays int[] (0 = Sun … 6 = Sat), reminder_enabled, is_active, target_duration_minutes, created_at, updated_at`; RLS `own routine` (`user_id = auth.uid()`); `user_id` defaulted server-side | The one and only routine store. No second system, no new table, no schema change. |
| `public.routine_logs` (R3) | `id, routine_id, log_date date, completed bool, status ∈ COMPLETED/SKIPPED/MISSED/PENDING, completed_at, duration_minutes, created_at, updated_at`; UNIQUE `(routine_id, log_date)`; RLS via own routine | Completion model: one upsert per (routine, user-zone day). |
| `progress_snapshots` / `ProgressService` | read-only weekly/monthly jsonb, 0 live rows | Not needed; no duplicate progress system created. Per-routine completion rate is derived from `routine_logs`. |
| `subjects` / `SubjectService.loadSubjects()` | existing | Subject dropdown → `routines.subject_id`. |
| `syllabus_nodes` / `SyllabusService.loadNodesForSubject()` | existing (`parent_id` tree) | Chapter/Topic dropdown (child shown as `Parent › Child`). |
| `study_materials` | existing, node-linked | Not surfaced in V1 (topic granularity is enough for a routine slot). |
| `profiles.timezone` / `ProfileService.currentProfile` | IANA text, default `Asia/Kolkata` | Drives "today" (see §6). |
| `CalendarClock` (`lib/features/calendar/domain/calendar_clock.dart`, committed) | fixed-offset user-zone day arithmetic | Imported read-only; Calendar files untouched. |
| Reminders | server-side `fn_send_routine_reminders` (pg_cron) reads `reminder_enabled`; `notification_settings.routine_reminders`; categories `ROUTINE_REMINDER/DUE/MISSED/COMPLETED` | Only the flag is exposed in the form; no client push work (§10). |
| Flutter routine code at `HEAD` | none — an unfinished, uncommitted first pass existed in the working tree (hard-coded device `DateTime.now()`, `/routine/history` pushed but unregistered, paused routines unreachable, activity re-appended to the title on every edit, screens not testable) | Rewritten in place; everything below is what ships. |

## 2. Schema

No migration. Every column read or written already exists live. Because `routines` has no topic/activity columns and no live-DB access exists from this environment, the study context is carried by `subject_id` + a **structured title** `"<base> · <topic> · <activity>"` composed/parsed deterministically by `RoutineSchedule` (round-trip tested; editing never duplicates segments).

## 3. Files changed (Routine lane only)

| File | Purpose |
|---|---|
| `lib/core/models/routine.dart` | `Routine` (live columns), `isScheduledOn(weekday)` (no device-time getter), `computedDurationMinutes` |
| `lib/core/models/routine_log.dart` | `RoutineLog` with status getters |
| `lib/features/routine/domain/routine_schedule.dart` | **new** — pure helpers: `HH:MM` parsing, `validate()`, `overlaps()`, `composeTitle()/parseTitle()`, weekday labels, `scheduledOn()` |
| `lib/features/routine/data/routine_repository.dart` | `RoutineRepository` + `SupabaseRoutineRepository`: list (active + paused), getById, create, update (with explicit `clearSubject`/`clearTargetDuration`), deactivate/activate/delete, `hasConflict`, `getLogs`, `upsertLog`, `getToday(date, weekday)`, `getHistory(routineId?)` — all bounded, RLS-only |
| `lib/features/routine/state/routine_controller.dart` | today items + completion %, all routines, mutations, `markComplete/markIncomplete/skip`, fail-closed `hasConflict`, `getHistory`, `statsFor()` (30-day rate), `upNext`, static `revision` change bus; user-zone `todayDate`/`todayWeekday` |
| `lib/features/routine/screens/routine_list_screen.dart` | Today · Other days · Paused sections, empty/loading/error+retry, FAB, history action, auto-reload on changes |
| `lib/features/routine/screens/routine_create_screen.dart` | create/edit: Subject → Chapter/Topic → Activity, title preview, start/end pickers, target duration, weekday repeat, reminder switch; validation + conflict refusal; not-found/retry in edit mode |
| `lib/features/routine/screens/routine_detail_screen.dart` | slot, today card (Mark complete / Undo / Skip today), schedule, study context, 30-day completion bar, Edit / Pause–Resume / Delete (confirm) |
| `lib/features/routine/screens/routine_history_screen.dart` | logs grouped by user-zone day with done/total badge, paging, per-routine filter via `?routine=` |
| `lib/features/routine/widgets/today_routine_card.dart` | home card: progress bar, one-tap complete/undo, Up-next banner, empty/loading/error+retry, self-refresh |
| `lib/features/routine/widgets/routine_card.dart` | list card (time, days, PAUSED badge) |
| `lib/app/app_router.dart` | `/routine`, `/routine/create`, `/routine/history` (static, registered **before** `:routineId`), `/routine/:routineId`, `/routine/:routineId/edit` |
| `lib/features/home/home_screen.dart` | `TodayRoutineCard` section on Home ("View All" → `/routine`) |
| `test/routine/fake_routine_repository.dart` | in-memory repository honouring ownership like RLS |
| `test/routine/routine_schedule_test.dart` · `routine_model_test.dart` · `routine_controller_test.dart` · `routine_screens_test.dart` | 97 tests (§7) |

## 4. Routine lifecycle

1. **Create** — form → `RoutineSchedule.validate` (times, weekdays, duration) → `hasConflict` (active routines, shared weekday, `[start,end)` overlap) → `routines.insert`. A conflict or a failed conflict check **blocks** the save with a message; nothing is ever overwritten silently.
2. **Today** — `getToday(date, weekday)`: active routines whose `weekdays` contain the user-zone weekday, joined with the `routine_logs` row for the user-zone date.
3. **Complete / Undo / Skip** — `upsertLog` on `(routine_id, log_date)` with status COMPLETED (logs `duration_minutes` = target when set) / PENDING / SKIPPED; then reload. Same row is updated, never duplicated.
4. **Edit** — same form pre-filled (title parsed back into base/topic/activity once the subject's topics load); `update` re-validates and re-checks conflicts excluding itself; can clear subject/duration explicitly.
5. **Pause / Resume** — `is_active` toggled; a paused routine leaves "today" but keeps its history and stays visible under *Paused* so it can be resumed.
6. **Delete** — confirmation dialog → hard delete (`routine_logs` cascade server-side).
7. **History** — `routine_logs` newest first, paged 30, grouped by day, optional per-routine filter.
8. **Cross-screen refresh** — every successful mutation bumps `RoutineController.revision`; the home card and list reload themselves.

## 5. Completion model

`routine_logs` is the single source of truth. `completionPercentage` (today) = completed / scheduled-today; `statsFor(routine)` (detail) = completed / days-the-routine-was-scheduled in the last 30 user-zone days, not before `created_at`, plus skipped days and logged minutes. Persisted server-side, so it survives restart (tested with a fresh controller against the same store).

## 6. Timezone handling

"Today" = the user's calendar day in **`profiles.timezone`** via `CalendarClock` (fixed-offset table, default `Asia/Kolkata`; unknown/DST zones fall back to device time exactly as Calendar does). `routine_logs.log_date` and the weekday used for scheduling both come from that day, never from `DateTime.now()`. The repository takes `date`/`weekday` as parameters so this is enforced by construction. Tested: 20:00 UTC on Sunday 20 Sep → Monday 21 Sep IST (logs land on `2026-09-21`; a UTC profile gets Sunday). Wall-clock `start_time`/`end_time` are stored and shown as typed.

## 7. Tests (`test/routine`, 97 passing)

- **schedule** (18): time parsing, `format12h`, weekday labels, validate (valid, end ≤ start, malformed, duration 0/negative/longer than slot, no/invalid weekdays), overlap rule (overlap, touching, different days, containment), structured title compose/parse/round-trip/idempotence, `scheduledOn`.
- **model** (16): JSON parsing/defaults, computed duration, `isScheduledOn`, equality, `toInsertJson`.
- **controller** (34): timezone/date (IST vs UTC, repository gets user-zone args, log date), loadAll (active+paused order, error, retry), create (+revision), edit (clear flags, partial update, failure), deactivate/activate/delete, today (filter/order, empty, error+retry, upNext, concurrent loads), completion (complete with duration, incomplete same row, skip, percentage, **persistence across controllers**, failure), conflict (overlap, non-overlap, exclude, **fail-closed**), history (order, filter, failure), stats, **authorization** (own rows only, cannot log or edit another user's routine), repeat schedule (Mon vs Sun, upcoming weekday).
- **screens** (29): list (loading→empty, sections, error→retry, navigation, revision reload), today card (empty, complete/undo/progress/up-next, restart persistence, error→retry, failed toggle snackbar), create (subject→topic→activity composes title, invalid duration refused, no weekday refused, conflict refused, fail-closed check, edit round-trip keeps activity once and clears duration, unknown routine retry), detail (study context/schedule/stats, complete/undo/skip, pause/resume, delete confirm, not found), history (grouping/badges/paused titles, per-routine filter, empty/error/retry), route table (`/routine/history` precedes `:routineId`).

## 8. Validation

The shared working tree could not be compiled as a whole at validation time: another lane had `lib/features/test/state/test_creation_controller.dart` mid-edit (importing a non-existent `../data/group_repository.dart`) and had dropped stale untracked files (`lib/features/test/test_result_screen.dart`, `widgets/step_review.dart`, `group_rules_controller.dart`, old `test/r4_*` files) that reference services which do not exist. None are Routine files and none were touched. Validation therefore ran in a **throwaway git worktree** = `HEAD` + this lane's staged files + the other lanes' *tracked* modifications (their two mid-edit files kept at `HEAD`, their stray untracked files excluded).

| Command | Result |
|---|---|
| `flutter analyze` (lane files: `lib/features/routine/**`, `lib/core/models/routine*.dart`, `lib/app/app_router.dart`, `test/routine/**`) | **No issues found** |
| `flutter analyze` (worktree, whole project) | 55 issues, **0 in Routine files**; the single `error` is `test/group/group_test_results_test.dart` (Group lane, missing `ResultRepository.leaderboard` override) |
| `flutter test test/routine` | **97/97 passed** |
| `flutter test` (whole suite, worktree) | see §12 |
| `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` | see §12 |

## 9. Security

All reads/writes go through the live RLS policies (`own routine`, `own routine logs`); the client never sends or filters on `user_id`. No policy, grant or enum was added or widened. Error messages are mapped (permission / auth / network / unique) without leaking server details.

## 10. Notifications — data exposed for Notification V1 (nothing built here)

- `routines.reminder_enabled` (form switch) — already consumed by server `fn_send_routine_reminders` (pg_cron, every minute) and gated by `notification_settings.routine_reminders`.
- Schedule facts a client scheduler needs are all on the row: `start_time`, `end_time`, `weekdays`, `is_active`, `subject_id`, `target_duration_minutes`; today's due list is `RoutineController.loadToday()` / `upNext`.
- Categories `ROUTINE_REMINDER`, `ROUTINE_DUE`, `ROUTINE_MISSED`, `ROUTINE_COMPLETED`, and `push_subscriptions` / `push_deliveries` already exist server-side. Still needed later: device token registration, in-app notification UI, deep link to `/routine/:id`.

## 11. Limitations / blockers

- **Topic/activity live in the title** (no `topic_id` column, no migration possible from this lane). `RoutineSchedule` keeps the encoding deterministic; a future column can be back-filled from `parseTitle`.
- Conflict check is client-side (no server exclusion constraint); two devices saving simultaneously could still overlap.
- Overnight slots (end before start) are rejected in V1 — `time` columns cannot say which day the end belongs to.
- `MISSED` is never set client-side (server job territory).
- DST zones fall back to device time (same `CalendarClock` limitation as Calendar).
- Shared-tree compile state is owned by other lanes (see §8); the Routine commit itself builds on top of `HEAD`.

## 12. Full-suite and APK results (validation worktree, §8)

| Command | Result |
|---|---|
| `flutter test` (whole suite) | **1055 passed, 4 failed** — none in Routine: `test/group/group_test_results_test.dart` fails to *compile* (Group lane: fake lacks `ResultRepository.leaderboard`), and `test/r4_restart/creation_completion_test.dart` ×2 + `test/r4_restart/screens_smoke_test.dart` ×1 assert "QuestionSource.books has no pipeline", which the committed R7 question-bank work changed. Same 3 R7 failures were already present during the Calendar validation. |
| `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` | **√ Built** `build/app/outputs/flutter-apk/app-debug.apk` (Gradle `assembleDebug` 489.6s). |

**Note for other lanes:** on the shared tree, `flutter analyze`/`test`/`build` stay red until `test_creation_controller.dart` compiles again and the stray untracked `lib/features/test/test_result_screen.dart`, `lib/features/test/widgets/step_review.dart`, `lib/features/group/state/group_rules_controller.dart` and old `test/r4_5_3_ui_test.dart`, `r4_5_4_ui_test.dart`, `r4_7_2_qa_fix_test.dart`, `r4_8_test.dart` are removed or fixed by their owners. Routine has no dependency on any of them.
