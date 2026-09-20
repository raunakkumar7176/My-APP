# R4 Test Compatibility Repair Report

## 1. Files changed

Test-only changes, four files:

- `test/r4_5_3_ui_test.dart` (untracked/new file — edited in place)
- `test/r4_5_4_ui_test.dart` (untracked/new file — edited in place)
- `test/v1_via_document/document_upload_test.dart`
- `test/v1_via_document/document_upload_screen_test.dart`

No production code, no migrations, and no `group_repository.dart` were touched. `test/r4_8_test.dart` was inspected but required no edits (see §2).

## 2. ResultService decision and rationale

**No `ResultService` was created.** `test/r4_8_test.dart` already imports and exercises `lib/features/test/domain/result_analytics_mapper.dart` (`ResultAnalyticsMapper.previous`, `.subjects`, `.topics`), which is the current production equivalent of the `getPreviousResult` / `parseSubjectBreakdown` / `parseTopicBreakdown` / `parseDifficultyBreakdown` behavior named in the diagnosis. The mapper's implementation matches every assertion in the test file exactly (verified line-by-line), and `flutter analyze` / `flutter test` both pass on this file with zero changes. The diagnosis's premise (that `r4_8_test.dart` depends on a missing `ResultService`) did not hold against the current checkout — the test was already migrated to `ResultAnalyticsMapper` in an earlier pass. `parseDifficultyBreakdown` has no production analogue because difficulty breakdown is not implemented server-side; the test already reflects that (asserts against a literal empty list, not a mapper call).

## 3. Stale test → current API migrations

### `test/r4_5_3_ui_test.dart`
- `QuestionDraft` V1 rule changed: `minOptions` is now `4` (was effectively 2 in the old test) and `isSupportedType` only accepts `mcqSingle` (True/False is no longer valid). Updated:
  - `isValid returns true for valid MCQ` → uses 4 options.
  - `isValid returns true for True/False without options` → renamed to `isValid returns false for True/False (unsupported type in V1)`, assertion flipped to `isFalse`.
  - `hasValidOptions validates MCQ options` → both cases now use 4 options.
- `BasicDetailsStep shows all test kind options in dropdown`: the selected value ("Self") now renders both in the closed field and again in the open menu — changed `findsOneWidget` to `findsWidgets` for that one assertion.
- `ConfigurationStep displays all configuration fields`: Max Participants / Allow Late Joining only render for scheduled kinds, and Join Code / Access Code only render when the kind requires a join code (`TestKind.isScheduled` / `.requiresJoinCode`). The default `kind: TestKind.self` used by the old test renders none of them. Pumped with `kind: TestKind.challengeWithFriends` instead (satisfies both conditions), and corrected the button label from `'Allow Late Join'` to the current `'Allow Late Joining'` and `'Join Code'` to `'Join Code *'`.
- `ReviewStep displays test summary correctly`: `TestFormatters.duration(3600)` renders `'1h'`, not `'60 minutes'`. Updated the expected text.
- `QuestionEditor saves draft when save button is tapped with valid data`: the editor always pads to `QuestionDraft.minOptions` (4) fields; the old test only filled 2 of them, leaving 2 empty and failing `hasValidOptions`. Fills all 4, and added `ensureVisible` before tapping the (now off-screen, in the taller sheet) `Radio<int>`.
- `QuestionEditor changes question type`: in the current widget only `mcqSingle` is selectable — every other `QuestionType` is a disabled `"… — Coming soon"` menu item (V1 only supports MCQ end-to-end). Renamed the test to `other question types are shown as Coming soon and stay unselectable` and rewrote it to assert the disabled item is present and that tapping it leaves MCQ selected, instead of trying to select True/False.

### `test/r4_5_4_ui_test.dart`
- `ReviewStep - Combined Questions shows total questions from server and local`: asserted a `'5'` total-marks figure that the current `ReviewStep` never renders (it only shows a combined `Questions` count row, no total-marks summary). Removed the total-marks half of the assertion; kept the question-count assertion, which matches current behavior.

### `test/v1_via_document/document_upload_test.dart`
- `QuestionSource.isAvailable ai is NOT available`: AI-generated questions are now implemented in production (`QuestionSource.ai.isAvailable` is `true`, matching the widget's own doc comment "V1 — implemented" and the recent `feat(test): implement via ai generated v1` commit). Renamed to `ai is available (V1 — implemented)` and flipped the assertion.
- `FakeDocumentService` already implements `extractFromImages(List<Uint8List> pages)` per the current `DocumentService` interface — no change was needed here (Step 5's stub was already present).

### `test/v1_via_document/document_upload_screen_test.dart`
- The idle state was redesigned for the camera/content-to-test convergence: there is no longer an `"Import Questions from Document"` headline or a `"Select File"` button — instead there's `"How do you want to add it?"` with two entry points, `Take Photos` (key `doc_import_take_photos`) and `Choose File` (key `doc_import_choose_file`). Updated the idle-state assertions and every tap that previously targeted `find.text('Select File')` to use `find.byKey(const Key('doc_import_choose_file'))` instead (5 call sites). No production code was touched — this is purely following the already-shipped camera/content-to-test screen through the test.

## 4. Analyzer result

`flutter analyze` — **0 errors**, 85 pre-existing info/warnings (const-constructor suggestions, deprecated API usages, unused variables), unchanged before and after this repair. Command exited 0.

## 5. Test result

`flutter test` — exit code **1**. Of 1433 total tests, **1429 pass**; **4 fail**, all outside this task's explicit scope and left untouched per instructions:

- `test/r4_restart/creation_completion_test.dart`: `N question source (truthful) only Manual is available; creation_method never pretends` and `unavailable source shows Not configured and cannot proceed` — these assert `QuestionSource.document`/`.ai` have no pipeline and that an "unavailable" UI state exists, which contradicts the now-implemented Document and AI pipelines. Not part of Steps 1–5 (ResultService, Answer model, R4.7.2, R4.5.3/5.4, DocumentService fakes) and touches `QuestionSource` availability semantics adjacent to, but not requested by, this task.
- `test/r4_restart/screens_smoke_test.dart`: `creation wizard renders every step and gates Next` — fails on the same `'Not configured'` text no longer present for the now-available sources; same reasoning as above.
- `test/v1_content_to_test/camera_capture_screen_test.dart`: `deleting the only page returns to the empty state` — explicitly excluded ("Do NOT touch … camera/content-to-test work").

None of these were introduced by this repair; all four failed identically before any of today's edits (confirmed via the pre-repair baseline run).

## 6. APK result

`flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` — **failed**, exit code 1. Cause is unrelated to the Dart/test work in this task:

```
Dependency ':flutter_plugin_android_lifecycle' requires libraries and applications that
depend on it to compile against version 36 or later of the Android APIs.
:file_picker is currently compiled against android-34.
```

This is a pre-existing Android Gradle `compileSdk` mismatch between the `file_picker` plugin and `flutter_plugin_android_lifecycle`'s transitive requirement. It predates this repair (not caused by any test-file edit) and is out of scope for a test-compatibility repair — bumping `compileSdk` is a build-configuration change with app-wide implications that needs an explicit decision, not something to make speculatively while fixing tests.

## 7. Remaining blockers

1. **4 failing tests** (listed in §5) — require either an explicit decision to update `creation_completion_test.dart` / `screens_smoke_test.dart` for the now-available Document/AI sources, or leaving them as intentionally-skipped/known-failing until that's decided. Camera test is out of scope by instruction.
2. **APK build** — blocked on the Android `compileSdk` version (34 → 36) needed to satisfy `flutter_plugin_android_lifecycle`'s AAR metadata requirement, unrelated to this repair.
