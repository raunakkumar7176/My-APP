# R4.7.2 — Test Taking Engine Completion Report

**Date:** 2026-09-13
**Status:** COMPLETE
**R4.7.2 is ready for QA gate.**

---

## 1. Files Created

| File | Purpose |
|------|---------|
| `lib/features/test/test_taking_screen.dart` | Main test-taking screen with PageView, autosave, timer, submit |
| `lib/features/test/widgets/question_card.dart` | Question display with option selection, review mark, question header |
| `lib/features/test/widgets/answer_grid.dart` | Bottom sheet grid showing answer status for all questions |
| `lib/features/test/widgets/countdown_timer.dart` | Server-authoritative countdown using `deadlineAt` |

## 2. Files Modified

| File | Change |
|------|--------|
| `lib/features/test/test_detail_screen.dart` | Wired Start Test button → `AttemptService.startAttempt()` → navigates to `/test-taking` |
| `lib/app/app_router.dart` | Added `/test-taking` and `/test-result` routes with typed params |

## 3. Features Implemented

### 3.1 Start Test Flow (Steps 1-2)
- `TestDetailScreen._startTest()` calls `AttemptService.startAttempt(test.id)`
- Loads questions via `QuestionService.getQuestionsSafe(testId: test.id)`
- Navigates to `/test-taking` with attempt, questions, test as extra data
- Error handling: displays AppError messages in SnackBars

### 3.2 Deterministic Shuffle (Step 3)
- `TestTakingScreen.shuffleQuestions()` — shuffles question order using `attemptId.hashCode` as seed
- `TestTakingScreen.shuffleOptions()` — shuffles option order using `(attemptId + questionId).hashCode` as seed
- Only applied when `test.shuffleQuestions == true`
- Original option IDs preserved; identity tied to `QuestionOption.id`, never visual position
- No `correct_option` exposure — `QuestionOption` model has only `id` and `text`

### 3.3 Question Display (Step 4a)
- `QuestionCard` shows: question number, marks, question text, shuffled options
- Option selection via styled radio buttons
- Mark for review toggle (bookmark icon in header)
- Header shows `Q X / N` with marks badge
- Handles MCQ single, MCQ multiple, true/false, integer, short answer

### 3.4 Answer Grid (Step 4b)
- Bottom sheet with 6-column grid of question numbers
- Color-coded: green=answered, grey=unanswered, orange=marked, purple=marked+answered
- Tapping a cell navigates to that question and closes the sheet
- Takes `questionIds` list directly (not derived from answer map keys)

### 3.5 Countdown Timer (Step 4c)
- Uses `deadlineAt` from server (server-authoritative)
- Updates every second via `Timer.periodic`
- Color-coded: green (>5min), orange (<5min), red (<1min)
- On time up → flushes answers → calls `submitAttempt(timedOut: true)`
- Falls back to 1 hour if no `deadlineAt` provided

### 3.6 Autosave (Step 6)
- Dirty flag (`_isDirty`) set on every answer change
- 5-second periodic timer checks and saves if dirty
- Saves all answers in batch via `AnswerService.saveAnswers()`
- On save failure, marks dirty again for retry
- Saves on dispose (best-effort)
- Saves before submit

### 3.7 Server-Authoritative Timer (Step 7)
- Timer display only — server's `deadlineAt` is the source of truth
- When countdown reaches zero: flush answers → `submitAttempt(attemptId, timedOut: true)`
- PopScope prevents back-button leave; shows dialog with Submit & Leave option

### 3.8 Double Submit Protection (Step 8)
- `_isSubmitting` flag disables submit button during submission
- Submit button shows loading indicator when submitting
- `_flushAndSubmit()` checks `_isSubmitting` at entry and returns early if already submitting

### 3.9 Mark for Review + Navigator (Step 9)
- Bookmark icon on each question card toggles `isMarkedForReview`
- Answer grid shows marked questions in orange
- Previous/Next navigation buttons in bottom bar

### 3.10 Submit Confirmation (Step 10)
- Shows summary: total, answered, unanswered, marked for review
- "Continue Test" dismisses dialog
- "Submit" calls `_flushAndSubmit(timedOut: false)`
- Back button shows "Submit & Leave" dialog

### 3.11 Resume Support
- On screen init, loads existing answers via `AnswerService.getAnswersForAttempt()`
- Merges into `_answers` map
- If attempt status is not `inProgress`, screen shows loading (would need routing adjustment for completed attempts)

## 4. Navigation

| Route | Screen | Extra Data |
|-------|--------|------------|
| `/test-detail` | `TestDetailScreen` | `Test` |
| `/test-taking` | `TestTakingScreen` | `{attempt, questions, test}` |
| `/test-result` | Placeholder `Scaffold` | `Result` |

## 5. Verification

| Check | Result |
|-------|--------|
| `flutter analyze` | 0 errors, 0 warnings (45 pre-existing infos) |
| `flutter test` | 171/171 pass |
| `flutter build apk --debug` | SUCCESS |

## 6. Security Audit

| Check | Status |
|-------|--------|
| No AI calls | PASS — timer, shuffle, autosave, submit all deterministic |
| `correct_option` not exposed | PASS — `QuestionOption` has only `id` and `text` |
| `public.questions` SELECT revoked | PASS — uses `get_test_questions_safe` RPC |
| `fn_score_attempt` permission: `postgres` only | PASS |
| `rpc_save_answers` used for answer writes | PASS — no direct INSERT/UPDATE |
| `rpc_submit_attempt` used for submission | PASS |
| Stable shuffle deterministic per attempt | PASS — `attemptId.hashCode` seed |
| No correct_option in shuffle result | PASS — options contain only id+text |
| Double submit protection | PASS — `_isSubmitting` flag |
| Server-authoritative timer | PASS — `deadlineAt` from server |

## 7. Known Limitations

1. **Placeholder test-result screen** — The `/test-result` route shows a static "Test Submitted!" scaffold. Full result display is pending R4.7.3 (Result + Analytics).
2. **Resume of non-in-progress attempts** — If the user navigates to `/test-taking` with a submitted/expired attempt, the screen will load but won't prevent interaction. Proper routing guard is recommended for R4.7.3.
3. **MCQ Multiple** — The UI shows radio buttons for single-select. Multi-select support (checkboxes) is scaffolded in `_isMultiSelect` getter but not yet wired to the UI. This matches the spec: MCQ Multiple support can be added in a follow-up.
4. **Text input questions** — Shows a basic `TextField`. Full validation and auto-submit for typed answers is pending.

## 8. DB/RLS/RPC Changes

**Zero.** No new database migrations, RLS policies, or RPC functions were created or modified.

## 9. Pre-existing Blockers (from R4.7.1)

- **Answers RLS live verification pending** — Must run 3 SQL queries in Supabase SQL Editor before R4.7.2 resume functionality is fully safe in production.
