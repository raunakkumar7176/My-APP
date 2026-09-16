# R4.7.3 — Result, Question Review & Self-Reflection

**Date:** 2026-09-13
**Status:** COMPLETE

---

## Summary

Implemented the full result display, question-wise review, difficulty analysis, and self-reflection features for the test-taking engine. The flow is: Test Taking → Self-Reflection Dialog → Submission → Result Screen → Question Review.

## Files Created

| File | Purpose |
|------|---------|
| `lib/core/models/self_reflection.dart` | SelfReflection model with confidence + expected score |
| `lib/features/test/widgets/self_reflection_dialog.dart` | Pre-submission reflection dialog |
| `lib/features/test/test_result_screen.dart` | Full result screen with score, stats, reflection comparison |
| `lib/features/test/question_review_screen.dart` | Question-by-question review with PageView |
| `lib/features/test/widgets/question_review_card.dart` | Individual question review widget |
| `lib/features/test/widgets/difficulty_analysis_card.dart` | Easy/Medium/Hard breakdown |
| `test/r4_7_3_test.dart` | 30 unit tests |

## Files Modified

| File | Change |
|------|--------|
| `lib/app/app_router.dart` | Replaced placeholder `/test-result` route with real screen; added `/question-review` route |
| `lib/features/test/test_taking_screen.dart` | Integrated self-reflection dialog before submit; pass full data map to result; read-only route fetches questions/answers |

## Architecture

### Flow

```
TestTakingScreen
  → _showSubmitDialog()
    → SelfReflectionDialog.show()  [captures reflection or skip]
    → _flushAndSubmit(reflection: ...)
      → AttemptService.submitAttempt() → Result
      → Navigate to /test-result with {result, test, questions, answers, reflection}
        → TestResultScreen
          → /question-review with {test, questions, answers, result}
```

### Key Decisions

1. **Self-reflection is client-session only** — no database persistence. The model passes through the navigation stack. No schema changes required.

2. **Self-reflection NEVER affects score** — The `Result` is entirely server-authoritative. The reflection comparison on the result screen is display-only.

3. **Question review shows user's answers + question text + explanations** — Correct answer reveal is NOT implemented because:
   - `questions_safe` view strips `is_correct` from options
   - No post-submission RPC exists that returns correct answers
   - This is a backend dependency requiring `fn_reveal_answers()` or similar

4. **Result passed as Map<String, dynamic>** — All required data bundled in `extra` parameter to avoid async fetches on result screen.

5. **Read-only route (submitted attempt)** — `_routeToResultIfAvailable()` fetches questions + answers via service before navigation, with `mounted` guard after async gap.

## Test Results

- **Flutter Analyze:** 0 errors, 0 warnings (58 pre-existing info-level issues)
- **Tests:** 237/237 pass (30 new in `r4_7_3_test.dart`)
- **APK Build:** SUCCESS

## Known Limitations

| Limitation | Reason | Impact |
|-----------|--------|--------|
| No correct answer reveal in question review | `questions_safe` view strips `is_correct`; no post-submission RPC | Users see their answers but not correct answers |
| Self-reflection not persisted | No DB column available without schema change | Reflection lost on app restart |
| MCQ Multiple deferred | Backend `answers.selected_option_id` is single text column | Multi-select questions use radio UI |

## Security Verification

- `correct_option` NOT exposed in `Question.toJson()` ✓
- `correct_option` NOT exposed in `QuestionOption` model ✓
- `Answer.toJson()` does not leak correctness info ✓
- `Result` is server-authoritative; reflection does not modify score ✓
- Shuffle does not sort by correctness ✓
