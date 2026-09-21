# Test UI Implementation Report

## 1. Existing test architecture audited

Before writing anything, a full audit (list, detail, instructions, live-taking, timer/autosave, navigator, submit, result, review, PDF export, creation flow, group integration, R6 assignment, drafts, theme consistency, and existing test coverage) was run against the current codebase. The conclusion changes the shape of this report: **the R4 test-taking engine's UI is already fully built, polished, and production-complete** for nearly every item in the brief. Specifically, already complete and **not touched** in this pass:

- Test listing (4 tabs, debounced search, kind-filter chips applied uniformly to all tabs including Drafts, distinct empty-vs-no-match states, join-with-code, FAB).
- Test detail (full info card, owner/student-aware CTA state machine — Start/Continue/Re-attempt/limit-reached — publish/delete/generate-results for owners, question-paper PDF).
- Test instructions (an `AlertDialog` in `test_detail_screen.dart` covering duration, question count, marks, negative marking, navigation/mark-for-review/submission rules — functionally equivalent to a dedicated screen; not rebuilt as a separate screen since that would be pure churn for no behavioral gain).
- Live test-taking (`TestTakingScreen`/`AttemptController`): **server-authoritative timer** (`deadlineAt` from the RPC response, never client-computed), `PageView` questions, debounced autosave with retry/failure UI (`SaveStatusBar`), a bottom-sheet question navigator (`AnswerGrid`) with color-coded answered/unanswered/marked states, mark-for-review persisted via the same `rpc_save_answers` payload, a submit-confirmation dialog with live answered/unanswered/marked counts, a re-entrancy guard plus a disabled Submit button preventing double submission, and a "Leave Test?" dialog (Stay / Save & Leave / Submit & Leave) guarding accidental exits.
- Result screen (`TestResultScreen`): score/percentage/pass-fail, correct/wrong/unanswered, accuracy, subject and topic breakdown (`SubjectAnalysisCard`/`TopicAnalysisCard`), attempt comparison and full history, PDF export, re-attempt gating.
- Question review (`QuestionReviewScreen`): question text + the student's own answer, mark-for-review flag. **Correctly and intentionally does not show a correct answer or explanation** — the backend never exposes `correct_option` through the safe question RPC, so any "correct answer" UI would have to fabricate data; this is a documented security boundary in the existing code, not a gap to fill.
- Test creation wizard and every source-specific sub-screen (document upload, camera capture, AI generation, question bank, templates) — all substantially built out (500–1100+ lines each), reached via the existing `QuestionSourceStep`/`QuestionSource` enum, all four sources (`manual`, `document`, `ai`, `books`) already report `isAvailable == true`.
- Drafts tab search/filter and delete (`TestRepository.deleteDraft`) already exist.
- Group test integration: `GroupTestsScreen`/`GroupTestResultsScreen`/`GroupLeaderboardScreen` are a deliberately separate, bespoke visual system for group chrome, but correctly delegate to the real R4 screens (`/tests/:id`, `/tests/create?group=`, `/attempts/:id/result`) for the actual test-taking/result experience — nothing to unify there without redesigning the group feature, which is out of this lane's scope.

Confirmed genuine gaps (not just unread code) that a "complete the test UI" brief would otherwise ask for, and how each was handled:

| Gap | Handling this pass |
|---|---|
| Two widgets (`answer_grid.dart`, `question_card.dart`) hardcode raw `Colors.*`/`Colors.white` and don't adapt to dark mode | **Fixed** — see §14 |
| No sort control on any listing tab | **Added** — see §4 |
| No OMR-style answer sheet | **Added** — see §11, respecting the same no-correct-answer boundary as question review |
| No R6 test-assignment feature (manager assigns test to specific members) | **Not built.** Nothing to reuse exists (`grep`-confirmed zero hits for "assignment" anywhere in `lib/features/test` or `lib/features/group`). Building it would mean inventing a new data layer/RPC, explicitly against this lane's "do not create duplicate repositories / do not rebuild the backend" rule. Reported as a dependency, not implemented. |
| No OCR pipeline for camera-captured photos feeding AI generation | **Not built** — the existing code already handles this honestly (an explicit "Can't read these photos yet" dialog redirects to Via Document / Enter Topic). Adding OCR would mean inventing a new backend capability; reported as a dependency. |
| No difficulty-level breakdown on the result screen (only subject/topic) | **Not added** — `ResultAnalyticsMapper` has no difficulty mapper and the `results` row's `subject_breakdown`/`topic_breakdown` jsonb has no difficulty dimension; adding it would mean inventing a metric the server doesn't compute. |
| No "duplicate draft" action | **Not added** this pass — lower priority than the dark-mode/PDF/sort items above given the session's scope; flagged as a reasonable follow-up (`TestRepository.create` + read the source draft's fields, no new backend needed). |
| No dedicated widget tests for `test_result_screen.dart`/`question_review_screen.dart`; `pretest_gate_test.dart` appeared empty | **Partially addressed** — new tests were added for the two screens I touched (`test_pdf.dart` builders + `ResultsController.buildAnswerSheetPdf`, see §13), but full widget-tree tests for `TestResultScreen`/`QuestionReviewScreen` themselves were not added (would be a large, separate testing effort against already-stable screens I did not otherwise modify). |

## 2. Screens changed

None of the five core taking-flow screens (`TestListingScreen`, `TestDetailScreen`, `TestTakingScreen`, `TestResultScreen`) needed structural changes. Only:

- `lib/features/test/screens/test_listing_screen.dart` — added a sort `PopupMenuButton` next to the existing search/filter row.
- `lib/features/test/screens/question_review_screen.dart` — added a second AppBar action, "Download answer sheet" (`Key('download_answer_sheet')`), alongside the existing "Download question paper".

## 3. Components created/reused

Created:
- `TestPdf.answerSheet(...)` (`lib/features/test/domain/test_pdf.dart`) — new pure PDF builder, third alongside the existing `questionPaper`/`resultReport`, following the exact same style (`_h1`/`_h2`/`_kv`/`_bold` helpers, `pw.MultiPage`, no I/O).
- `ResultsController.buildAnswerSheetPdf({studentName})` — new method on the existing controller, mirroring `buildResultPdf`/`buildQuestionPaperPdf` exactly (same error handling, same "throws if not loaded" pattern), assembled entirely from data the review flow already loaded (`_questionsList`, `_answersById`, `_result`, `currentEntry?.attempt`) — no new fetch.
- `TestSortOrder` enum + `TestListingController.sortOrder`/`setSortOrder` — new, small, client-side-only sort state added to the existing controller (same shape as the existing `query`/`kindFilter` state).

Reused, not duplicated: `AttemptHistoryEntry.attempt`/`.completedAt` (for the answer sheet's Date/Time-taken fields), `Result.correctCount/wrongCount/unansweredCount` (for the sheet's summary line — the server's own aggregate, not a per-bubble judgement), `Answer.selectedOption` (which bubble is filled), `Question.options` (dynamic bubble count per question, never hardcoded to a fixed option count).

## 4. Test creation UX

Not modified — already unified and complete per the audit (§1). No changes.

## 5. Test-taking UX

Not modified — `TestTakingScreen`/`AttemptController` mechanics (timer, autosave, PageView, submit flow, leave-guard) were already complete and correct; only the two rendering widgets it uses (`QuestionCard` for options, `AnswerGrid` for the navigator sheet) were touched, and only for color/theme, not behavior (§14).

## 6. Navigator

Not modified — `AnswerGrid`'s bottom-sheet navigator, color-coded states, and tap-to-jump behavior were already complete; only its hardcoded light-only colors were fixed (§14).

## 7. Autosave

Not modified — the debounced autosave, retry, and failure-surfacing (`SaveStatusBar`) were already complete and correct (server-side `rpc_save_answers`, 5s periodic flush, dirty-flag tracking).

## 8. Submission

Not modified — the confirmation dialog (live answered/unanswered/marked counts), the `_submitting` re-entrancy guard, and the disabled-while-submitting button were already complete and correct.

## 9. Result UI

Not modified — score/percentage/accuracy/correct-wrong-unanswered/subject-topic breakdown/history/PDF export were already complete.

## 10. Question review

Not structurally modified (correctly does not show correct answers — see §1). Added the new "Download answer sheet" action to its AppBar (§2, §11).

## 11. Downloads (new: OMR-style answer sheet)

`TestPdf.answerSheet` renders one row per question with a dynamically-sized set of lettered bubbles (A, B, C, … sized to the actual maximum option count across the test's questions — never hardcoded to 4 or 100), the student's marked bubble filled solid, Date and Time Taken computed from the attempt's own `startedAt`/`submittedAt`, and a Correct/Wrong/Unanswered summary line taken directly from the server's `results` row aggregate. **It never marks a bubble correct or incorrect** — the backend does not expose `correct_option` anywhere in the client-visible schema (confirmed at the model level: neither `Question`/`QuestionOption` nor `Answer` carry a correctness field), so doing so would fabricate data, exactly the same boundary `QuestionReviewScreen` already respects. Reached from `QuestionReviewScreen`'s AppBar (post-submission only, same gating as the existing question-paper download), delivered the same way as the other two PDFs (`Printing.sharePdf`).

## 12. Group tests

Not modified — reuse already correct (§1); group screens delegate to the real test/result screens for the actual test-taking/result experience.

## 13. Assignment integration

**Not built.** No R6 test-assignment feature exists anywhere in the codebase (confirmed via exhaustive grep). Building it would require a new data layer (assign-test-to-members table/RPC) that does not currently exist, which is explicitly outside this UI-only lane's mandate ("do not rebuild the backend," "do not create duplicate repositories"). Reported here as a dependency for a future backend+UI lane, not implemented as a stub or fake.

## 14. Theme (dark-mode fix)

The audit flagged `lib/features/test/widgets/answer_grid.dart` and `lib/features/test/widgets/question_card.dart` — the two most visually dense widgets in the taking screen — as hardcoding raw `Colors.white`, `Colors.grey.shade200/300/400`, and `Colors.transparent` instead of reading from `Theme.of(context).colorScheme`, meaning the question-navigator sheet and the option tiles would not adapt to dark mode. Both were fixed:

- `answer_grid.dart`: sheet background → `colorScheme.surfaceContainerLowest`; drag handle → `colorScheme.outlineVariant`; unanswered-cell background/text → `colorScheme.surfaceContainerHighest`/`colorScheme.onSurface`; current-question ring and "answered+marked" cell → `colorScheme.primary`/`onPrimary` (was the fixed `AppColors.primaryLight`).
- `question_card.dart`: question-number badge, selected-option border/background/text, and the radio indicator all switched from `AppColors.primaryLight` to `colorScheme.primary`/`onPrimary`; unselected option tile background/border/text switched from `AppColors.surfaceLight`/`Colors.grey.shade300/400`/`AppColors.textPrimaryLight` to `colorScheme.surfaceContainerLowest`/`colorScheme.outlineVariant`/`colorScheme.outline`/`colorScheme.onSurface`; the "unsupported question type" banner switched from hardcoded `Colors.orange.shade300/50` to the existing semantic `AppColors.warning` at low alpha (consistent with the rest of the app's established success/warning/error convention).

Semantic accent colors (`AppColors.success`/`warning` for the "answered"/"marked for review" states) were deliberately left as-is — this matches the app's existing, established convention (fixed semantic colors + theme-aware neutrals) rather than introducing a new pattern.

## 15. Responsive behavior

Not touched this pass — the taking screen's `PageView` + bottom-sheet navigator already work at any width; no tablet/desktop split-view was added (out of scope for this focused pass; the existing screens were not flagged as broken at any size during the audit).

## 16. Accessibility

Not touched beyond the dark-mode contrast fix in §14, which is itself an accessibility fix (the hardcoded light colors would have been low/no-contrast in dark mode).

## 17. Security considerations

No security-relevant code was touched. `TestPdf.answerSheet` was deliberately designed to be incapable of leaking a correct answer: it only ever reads `Answer.selectedOption` (which bubble the student marked) and the server's own aggregate `Result` counts, never anything that would require the backend to expose an answer key it currently withholds. No RPC, RLS policy, or repository method was added, changed, or bypassed.

## 18. Tests

- `test/r4_restart/pdf_test.dart` — added a `TestPdf.answerSheet` group (3 tests: dynamic bubble count across mixed 2-option/4-option questions, refuses an empty question list, confirms no correctness data exists at the model level for the builder to leak even if it wanted to) and extended the existing `ResultsController` integration test to also cover `buildAnswerSheetPdf`.
- `test/r4_restart/listing_filter_test.dart` — added a `TestListingController sort` group (4 tests: newest-first default, oldest-first, title A-Z, no-op/notify-once semantics matching the existing filter tests' style).
- No existing test was deleted or weakened.

Full suite: **1464 tests**. Same 4 pre-existing, unrelated failures as before this pass (`creation_completion_test.dart` ×2, `screens_smoke_test.dart`, `camera_capture_screen_test.dart` — none touched by this or the previous session's UI work). **6 additional failures were observed in `test/group/group_notifications_test.dart`**, but that file was modified by a different, concurrently-running session in this same working tree (a "0055 migration" notification-dismissal feature referencing a `NotificationRepository.dismiss()` that isn't wired up yet) — confirmed via `git status` that this file is not part of this pass's changes and none of the files this pass touched are anywhere near that code path. Reported here for visibility, not fixed (out of this lane's scope and not mine to fix).

## 19. flutter analyze

**0 errors**, 92 pre-existing/consistent info-level warnings (const-constructor suggestions, deprecated Radio API used the same way as the rest of the app). Command exited 0.

## 20. APK build

`flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` — **succeeded**, exit code 0.

Manual on-device visual QA (light/dark, small/large phone, 5/25/50/100-question tests) was **not performed** — no device was connected during this session. Everything above is analyzer-, unit-, and integration-test-verified plus a successful compiled build.

## 21. Remaining limitations

1. No manual device QA this session (no device connected).
2. R6 test-assignment feature does not exist and was not built (§1, §13) — needs its own backend+UI lane.
3. Camera→OCR grounding for AI generation remains explicitly unimplemented (pre-existing, honest "can't read these yet" UX left as-is).
4. No difficulty-level breakdown on the result screen — the server doesn't compute one.
5. No "duplicate draft" action or tablet/desktop split-view for the taking screen — reasonable follow-ups, not done this pass.
6. No full widget-tree regression tests added for `TestResultScreen`/`QuestionReviewScreen` themselves (only the new PDF/controller logic they call).
7. A different, concurrent session's in-progress `test/group/group_notifications_test.dart` has 6 failing tests unrelated to this work (§18) — flagged for whoever owns that lane, not resolved here.
