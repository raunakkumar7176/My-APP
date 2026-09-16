# R4.7.2.1 — Test Taking QA Fix Report

**Date:** 2026-09-13
**Status:** COMPLETE — All fixes applied and verified
**AI calls added:** 0

---

## 1. Files Changed

| File | Change |
|------|--------|
| `lib/features/test/test_taking_screen.dart` | FIX 1 (FNV-1a hash), FIX 2 (no timer fallback), FIX 3 (attempt guard), FIX 7 (autosave safety) |
| `lib/features/test/widgets/question_card.dart` | FIX 3 (interactive flag for read-only mode) |
| `test/r4_7_2_qa_fix_test.dart` | **NEW** — 36 tests covering all fixes |

## 2. Fix Details

### FIX 1 — Stable Cross-Run Shuffle

**Original issue:** `String.hashCode` in Dart is not guaranteed stable across runs/platforms/Dart versions.

**Root cause:** Used `seed.hashCode` as `Random` constructor argument.

**Fix:** Replaced with FNV-1a 64-bit hash (truncated to 63-bit positive), implemented as a pure Dart function with no external dependencies.

**Algorithm:**
```
FNV-1a 64-bit:
  offset_basis = 0xcbf29ce484222325
  prime = 0x100000001b3
  for each byte in UTF-8 encoded input:
    hash = hash XOR byte
    hash = hash * prime (mod 2^63)
  return hash
```

**Seed derivation:**
- Questions: `Random(fnv1aHash(attemptId))`
- Options: `Random(fnv1aHash('${attemptId}_${questionId}'))`

**Verified:** Same attempt ID → identical question and option order across repeated calls.

### FIX 2 — Remove Unsafe Timer Fallback

**Original issue:** When `deadlineAt` was null, screen fell back to `DateTime.now().add(Duration(hours: 1))`.

**Root cause:** Fabricated an authoritative deadline from client side.

**Fix:** Removed fallback entirely. When `deadlineAt` is null:
- No timer displayed
- Shows `_buildNoDeadlineScreen()` with error state: "Timer Not Available — The server did not provide a deadline for this attempt."
- Button: "Back to Tests"

### FIX 3 — Non-In-Progress Attempt Guard

**Original issue:** Screen was fully interactive regardless of attempt status.

**Root cause:** No status check before enabling answer changes.

**Fix:** Added `_isInteractive = widget.attempt.isInProgress` in `initState`:
- `in_progress` / `active` → interactive (full test-taking UI)
- `submitted` → `_buildReadOnlyScreen()` with "Test Submitted" + "View Result" button
- `expired` → `_buildReadOnlyScreen()` with "Test Auto-Submitted (Time Expired)"
- `unknown` → `_buildReadOnlyScreen()` with "Test Status Unknown"
- Autosave timer only starts for interactive attempts
- `_onOptionSelected` and `_onMarkReview` return early if `!_isInteractive`
- `QuestionCard` receives `interactive` flag; read-only mode shows selected answers without tap handlers

### FIX 4 — MCQ Multiple

**Decision:** DEFERRED.

**Evidence:**
- `answers` table: `selected_option_id text` — single value, not array
- `QuestionOption` model: `{id, text}` — no `correct_option` exposure
- `Answer.toJson`: `selected_option_id: String?` — single option
- DB enum `question_type` includes `mcq_multiple`, but the answer/scoring contract is single-option only

**Action taken:** No misleading multi-select UI introduced. Radio button behavior retained for all MCQ types. Documented as deferred.

### FIX 5 — Answer State Safety

**Verified:**
- Answer map key = `questionId` (not index)
- `selectedOptionId` = original option ID (not visual position)
- After shuffle, option IDs preserved in `QuestionOption.id`
- Answer state persists correctly across question reordering

### FIX 6 — Timer Behavior

**Verified:**
- Timer starts from `widget.attempt.deadlineAt` (server-provided)
- `CountdownTimer.remainingAt()` computes from stored `deadlineAt`
- Widget rebuilds (`didUpdateWidget`) only restart timer if `deadlineAt` changes
- Page navigation does not affect timer (timer is in AppBar, separate from PageView)
- Reopening attempt uses server's `deadlineAt` from the Attempt model
- Reaching zero triggers `onTimeUp` → `_flushAndSubmit(timedOut: true)`
- Client time is never used to score or extend the attempt

### FIX 7 — Autosave Safety

**Verified:**
- `_isDirty = false` set optimistically before save attempt
- On failure: `_isDirty = true` (dirty state retained)
- Successful save keeps `_isDirty = false`
- No infinite retry — 5-second interval timer, one attempt per tick
- No answer keys logged — only `AppLogger.warning('Autosave failed: $e')`
- Autosave only runs on timer tick, not on widget rebuild
- Autosave only runs when `_isInteractive` is true

### FIX 8 — Security Regression

**Read-only verification:**
- No `public.questions` direct query — uses `get_test_questions_safe` RPC ✓
- `correct_option` absent from `QuestionOption` model ✓
- `correct_option` absent from `Question.toJson()` ✓
- `rpc_save_answers` used for answer writes ✓
- `rpc_submit_attempt` used for submission ✓
- No service-role key in client code ✓
- No answer keys in logs ✓
- No RLS changes ✓
- No new security bypass ✓

### FIX 9 — Tests

**Created:** `test/r4_7_2_qa_fix_test.dart` — 36 tests

| Group | Tests | Coverage |
|-------|-------|----------|
| FIX 1 — Deterministic shuffle | 7 | Stability, FNV-1a hash, option order |
| FIX 5 — Answer state identity | 4 | Question ID key, option ID selection, shuffle persistence |
| FIX 2 — No fake deadline | 3 | Null deadline, valid deadline, past deadline |
| FIX 3 — Attempt state | 5 | in_progress, active, submitted, expired, unknown |
| FIX 7 — Autosave safety | 4 | Dirty retention, clear on success, skip when clean/empty |
| FIX 4 — MCQ Multiple | 4 | Enum exists, single-option contract, deferred |
| FIX 6 — Timer behavior | 4 | Compute, past deadline, server deadline, null deadline |
| FIX 8 — Security | 4 | No correct_option in Option/Question/Answer, no correctness sort |
| Double submit | 1 | Concurrent submission blocked |

## 3. Verification

| Check | Result |
|-------|--------|
| `flutter analyze` | 0 errors, 0 warnings |
| `flutter test` | 207/207 pass (171 existing + 36 new) |
| `flutter build apk --debug` | SUCCESS |

## 4. DB/RLS/RPC Changes

**None.** Zero database, RLS, or RPC modifications.

## 5. Remaining Limitations

1. **MCQ Multiple** — Deferred. Backend answer contract is single-option (`selected_option_id text`). Multi-select requires schema change + scoring contract update.
2. **Test result screen** — Placeholder "Test Submitted!" scaffold. Full result display pending R4.7.3.
3. **Resume of non-in-progress attempts** — Screen shows read-only state. No automatic routing to result if result doesn't exist yet.
4. **Text input questions** — Basic TextField. Full validation pending.

## 6. Final Gate

| Requirement | Status |
|-------------|--------|
| Stable shuffle across app restart/resume | ✅ FNV-1a, verified identical across runs |
| No fake deadline fallback | ✅ Null deadline shows error state |
| Only in_progress attempts interactive | ✅ Status guard in initState + UI |
| submitted/auto_submitted/scored cannot be modified | ✅ Read-only screen + no-op handlers |
| Answer identity = question-ID / option-ID | ✅ Verified in tests |
| Autosave safe (dirty on fail, no infinite retry) | ✅ Verified in tests |
| Server remains authoritative | ✅ No client-side deadline fabrication |
| Security intact | ✅ No regressions |
| AI calls added | 0 |
| flutter analyze: 0 errors, 0 warnings | ✅ |
| All tests pass | ✅ 207/207 |
| APK builds | ✅ |
