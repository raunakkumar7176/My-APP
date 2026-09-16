# R4.7.4 — Result Analytics + Mistake Foundation + Repeat Test

**Date:** 2026-09-13
**Status:** CONDITIONAL PASS

---

## 1. Audit Findings

### DB Schema Verified
- `results` table: `subject_breakdown` (jsonb), `topic_breakdown` (jsonb), `percentage`, `accuracy`, `correct_count`, `wrong_count`, `unanswered_count`, `rank`
- `attempts` table: `attempt_number integer NOT NULL DEFAULT 1`, unique on `(test_id, user_id, attempt_number)`
- `tests` table: `max_attempts integer NOT NULL DEFAULT 1`
- `questions` table: `subject_id`, `topic_node_id`, `difficulty`, `explanation`
- `subjects` table: `id`, `name` — accessible via `SubjectService.loadSubjects()`

### Critical Finding: Repeat Test Backend Limitation
- `_fn_start_attempt_core` creates attempts with `attempt_number` defaulting to 1
- Unique constraint `uq_attempts_test_user_number` on `(test_id, user_id, attempt_number)`
- **Second call to `rpc_start_attempt` for same test+user will fail with unique violation**
- The `max_attempts` field exists on Test but is NOT checked/enforced in `_fn_start_attempt_core`
- **This is a backend dependency** — repeat test will show appropriate error until backend supports `attempt_number` increment

### Analytics Data Source
- `subject_breakdown`: JSONB map keyed by subject ID, values: `{attempted, correct, wrong, unanswered}`
- `topic_breakdown`: JSONB map keyed by topic ID, same structure
- Both may be null/empty for tests without subject/topic tagging

---

## 2. Actual DB/Result Contracts Verified

| Contract | Status |
|----------|--------|
| `Result.fromJson` parses all fields | ✅ Verified |
| `Result.subjectBreakdown` is `Map<String, dynamic>?` | ✅ Verified |
| `Result.topicBreakdown` is `Map<String, dynamic>?` | ✅ Verified |
| `ResultService.getResultsForTest(testId)` exists | ✅ Verified |
| `ResultService.getMyResults()` exists | ✅ Verified |
| `SubjectService.loadSubjects()` exists | ✅ Verified |
| `AttemptService.startAttempt(testId)` exists | ✅ Verified |
| `questions_safe` view strips `is_correct` | ✅ Verified |
| `results` table: one result per attempt (immutable) | ✅ Verified |
| `attempts.attempt_number` defaults to 1 | ✅ Verified |

---

## 3. Files Created

| File | Purpose |
|------|---------|
| `lib/core/models/result_analytics.dart` | `SubjectBreakdownItem`, `TopicBreakdownItem`, `DifficultyBreakdownItem`, `MistakeItem` models |
| `lib/features/test/widgets/subject_analysis_card.dart` | Subject-wise performance card |
| `lib/features/test/widgets/topic_analysis_card.dart` | Topic-wise performance card |
| `lib/features/test/widgets/difficulty_analysis_extended_card.dart` | Extended difficulty analysis (correct/wrong/unanswered) |
| `lib/features/test/widgets/mistake_summary_card.dart` | Mistake summary with subject/difficulty grouping |
| `lib/features/test/widgets/result_history_card.dart` | Multi-attempt result history |
| `test/r4_7_4_test.dart` | 29 unit tests |

## 4. Files Modified

| File | Change |
|------|--------|
| `lib/core/services/result_service.dart` | Added `parseSubjectBreakdown()`, `parseTopicBreakdown()`, `parseDifficultyBreakdown()`, `getPreviousResult()` |
| `lib/features/test/test_result_screen.dart` | Full rewrite: added subject/topic/difficulty analysis, mistake summary, result history, improvement indicator, repeat test action, mistake review action |

---

## 5. Result Analytics Implementation

### Subject Analysis
- Parses `result.subjectBreakdown` JSONB into `SubjectBreakdownItem` list
- Attempts to resolve subject names via `SubjectService.loadSubjects()`
- Falls back to truncated subject ID if name unavailable
- Shows: name, attempted, correct, wrong, skipped, accuracy, progress bar
- Empty state: "Subject-wise data is not available for this test."

### Topic Analysis
- Parses `result.topicBreakdown` JSONB into `TopicBreakdownItem` list
- Requires ≥2 topic entries for meaningful display
- Sorts by wrong count descending (worst first)
- Shows: topic name, correct/attempted ratio, accuracy
- Empty state: "Topic analysis is not available for this test."

### Difficulty Analysis (Extended)
- `DifficultyAnalysisExtendedCard` created but receives empty items
- Per-question difficulty correct/wrong data requires backend support (no post-submission correct answer reveal)
- Card shows empty state gracefully when no data available

---

## 6. Subject Analysis
See Section 5.

## 7. Topic Analysis
See Section 5.

## 8. Difficulty Analysis
- Existing R4.7.3 `DifficultyAnalysisCard` (answered/total) retained
- New `DifficultyAnalysisExtendedCard` (correct/wrong/unanswered per difficulty) created
- Extended card receives empty items because per-question correct/wrong determination requires backend post-submission data
- **Backend dependency:** `fn_score_attempt` does not expose per-question correctness to client

---

## 9. Mistake Foundation

### What is a "mistake" in R4.7.4
- Question was attempted (answered)
- Server result indicates it was wrong (`wrong_count`)
- Unanswered questions are NOT classified as mistakes

### MistakeItem Model
Retains: questionId, testId, subjectId, subjectName, topicId, topicName, difficulty, selectedOptionId, explanation

### Mistake Summary
- Total mistakes = `result.wrongCount`
- Total unanswered = `result.unansweredCount`
- Accuracy from server
- Subject/difficulty grouping populated from result data where available
- "Review Mistakes" action opens filtered question review

### Mistake Categories (R4.7.4 only)
- Wrong Answer
- Unanswered
- Review Needed

**NOT classified:** silly, conceptual, calculation, careless, memory, time-pressure mistakes

---

## 10. Repeat Test Implementation

### Flow
1. User taps "Repeat Test" on result screen
2. Calls `AttemptService.startAttempt(test.id)` (existing RPC)
3. On success: navigates to `/test-taking` with new attempt
4. On failure: shows error SnackBar

### Backend Constraint
- `rpc_start_attempt` → `_fn_start_attempt_core` creates attempt with `attempt_number` DEFAULT 1
- Unique constraint `(test_id, user_id, attempt_number)` prevents duplicate
- **If user already has attempt_number=1, repeat will fail with constraint violation**
- Error is caught and displayed to user

### What is NOT modified
- Old attempt: unchanged
- Old result: unchanged (immutable)
- Historical data: preserved

---

## 11. Result History Implementation

- `ResultService.getResultsForTest(testId)` fetches all results for the test
- `ResultHistoryCard` displays attempt list with: attempt number, date, percentage, pass/fail, current badge
- Only shown when >1 result exists
- Fetched in `TestResultScreen._loadAnalytics()`

---

## 12. Improvement Comparison

- Compares current result with previous attempt (by computed_at)
- Shows: "Improved by X percentage points" / "Lower by X percentage points" / "Same percentage"
- Only shown when ≥2 results exist
- Uses factual wording, no AI inference

---

## 13. Security Verification

| Check | Status |
|-------|--------|
| No `public.questions` direct query | ✅ All queries via `questions_safe` view or RPC |
| `correct_option` protected before submission | ✅ `questions_safe` strips `is_correct` |
| Result belongs to current user | ✅ RLS + `getMyResults()` filters by `auth.uid()` |
| Historical result cannot be overwritten | ✅ No update/delete methods in `ResultService` |
| Repeat test does not modify old attempt | ✅ `startAttempt` creates new row |
| Repeat test does not modify old result | ✅ Results are immutable |
| No service-role credentials | ✅ All via `SupabaseService.client` (anon key) |
| No answer keys in logs | ✅ No `correct_option` logged |
| No client-side authoritative scoring | ✅ All scores from server `Result` model |
| R4.7.2.1 security intact | ✅ No changes to shuffle, timer, autosave |
| R4.7.3 security intact | ✅ No changes to submission, result display |
| No unnecessary RLS changes | ✅ None made |
| No unauthorized cross-user analytics | ✅ `getMyResults()` + RLS enforce ownership |

---

## 14. Error Handling

| Scenario | Handling |
|----------|----------|
| Missing result | Loading state → error message |
| Empty subject_breakdown | "Subject-wise data is not available" |
| Empty topic_breakdown | "Topic analysis is not available" |
| Malformed breakdown | Graceful skip, empty list |
| Missing question metadata | Falls back to ID display |
| Network failure | Error SnackBar |
| Unauthorized result | RLS blocks, error displayed |
| Repeat test failure | Error SnackBar with server message |
| Unavailable analytics | Error state with message |
| Previous result unavailable | Improvement indicator hidden |

---

## 15. Tests

**29 new tests in `test/r4_7_4_test.dart`:**

- Subject Breakdown Parsing: 5 tests (valid, null, empty, malformed, missing fields)
- Topic Breakdown Parsing: 5 tests (valid, null, empty, single-key, sort order)
- Difficulty Breakdown: 1 test (empty list — backend dependency)
- Mistake Foundation: 6 tests (MistakeItem, SubjectBreakdownItem, TopicBreakdownItem, DifficultyBreakdownItem accuracy)
- Previous Result Comparison: 5 tests (found, single, oldest, unknown, empty)
- Security: 5 tests (no correct_option, no correct answer in mistake, no client scoring, ownership, immutability)
- Repeat Test Constraints: 2 tests (maxAttempts field, attempt_number default)

---

## 16. Verification Results

| Check | Result |
|-------|--------|
| `flutter analyze` | **0 errors**, 68 info-level issues (all pre-existing) |
| `flutter test` | **266/266 pass** (237 existing + 29 new) |
| `flutter build apk --debug` | **SUCCESS** |

---

## 17. Backend Dependencies

| Dependency | Impact | Status |
|-----------|--------|--------|
| Repeat test `attempt_number` increment | Second attempt fails with constraint violation | **BLOCKED** — requires `_fn_start_attempt_core` to calculate next `attempt_number` |
| Per-question correct/wrong from server | Difficulty breakdown (correct/wrong per level) empty | **BLOCKED** — requires post-submission data exposure |
| Post-submission correct answer reveal | Question review cannot show correct answers | **BLOCKED** — requires `fn_reveal_answers()` or similar |
| `fn_score_attempt` subject/topic breakdown population | Analytics depend on server populating these JSONB fields | **VERIFIED** — fields exist, population depends on `fn_score_attempt` implementation |

---

## 18. Remaining Limitations

1. **Repeat test fails for second attempt** — backend `attempt_number` not incremented
2. **Difficulty breakdown empty** — no per-question correct/wrong data from server
3. **Mistake grouping by subject/topic empty** — requires per-question correctness data
4. **Correct answer not shown in review** — `questions_safe` strips `is_correct`
5. **Self-reflection session-only** — no DB persistence (from R4.7.3)
6. **MCQ Multiple deferred** — backend single-option contract (from R4.7.2)

---

## 19. Final Gate

### CONDITIONAL PASS

**Rationale:**
- All safe R4.7.4 functionality implemented and verified
- Subject/topic analysis parsing works correctly with server data
- Mistake foundation models and summary card created
- Result history and improvement comparison implemented
- Repeat Test action implemented but blocked by backend `attempt_number` constraint
- Difficulty breakdown and per-question mistake grouping blocked by backend data exposure
- **No security compromise** — all constraints respected
- **266/266 tests pass**, **0 errors**, **APK build SUCCESS**

**What works now:**
- Subject analysis (when `subject_breakdown` populated by server)
- Topic analysis (when `topic_breakdown` populated by server)
- Mistake summary (wrong count, unanswered, accuracy)
- Result history (multi-attempt listing)
- Improvement comparison (percentage point difference)
- Repeat Test button (will work once backend supports `attempt_number` increment)

**What is blocked (backend dependencies):**
- Repeat test execution (unique constraint on `attempt_number`)
- Per-difficulty correct/wrong breakdown
- Per-question mistake identification with correct answer
- Subject/topic grouping of mistakes
