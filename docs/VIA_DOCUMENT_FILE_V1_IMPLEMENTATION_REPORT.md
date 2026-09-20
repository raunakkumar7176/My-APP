# Via Document/File V1 — Implementation Report

**Date:** 2026-09-20
**Status:** IMPLEMENTED, VERIFIED LOCALLY (corrected) — DB migration OWNER APPLY REQUIRED

## 0. Important context: this is a correction pass, not a fresh build

The base implementation in this report (models, service, controller, screen,
wizard wiring, migration) was already built and committed to this branch as
`f4a7aaf feat(test): implement via document file v1` by a **separate, concurrent
session** working the same task from the same starting materials — this
session's own discovery pass found that commit already in place partway
through. Rather than duplicate the work, this pass **validated it end to end,
found and fixed several real defects the original commit's "64 tests pass"
claim had not caught, and added the test coverage that was missing** (real
byte-level parsing, group-permission enforcement, retry/idempotency,
snapshot independence, and a screen-level widget test). Everything below
describes the **corrected, currently-committed state**; §9 lists exactly what
this pass changed and why.

## 1. Architecture discovered (confirmed, unchanged)

5-step wizard: Basic Details → Configuration → Syllabus → Question Source →
Questions → Review. Reused, not duplicated:
- `TestCreationController` / `TestWriteInput` / `rpc_create_test` — test row creation, unchanged interface
- `rpc_create_question` (via `QuestionRepository.create`) — question rows are created one-by-one exactly like Manual, so a document-imported question is a real, independent, test-owned row from the moment it's created
- `QuestionDraft` / `QuestionOptionDraft` — the same local-draft type Manual and the Question Bank clone path already use
- `QuestionSource` enum — `document` was already `manual|upload|ai` mapped in `tests.creation_method`; **`upload` is an existing, live enum value, not invented**
- Supabase Storage (private buckets, user-scoped paths) — the only genuinely new piece is the bucket/table below, since nothing existing tracked "a raw file uploaded for later parsing"
- The existing group permission engine (`CREATE_TEST`, `fn_has_permission`) — reused via `rpc_create_test`, never re-implemented

`study_materials`/`material_chunks` were inspected and are not reused: they model the pre-existing study-library content, not user-uploaded, ephemeral parse sources — a different lifecycle and a different owner.

## 2. Files changed

### New (this pass's own additions)
| File | Purpose |
|---|---|
| `test/v1_via_document/document_service_and_permissions_test.dart` | Real byte-level PDF/DOCX/XLSX extraction (built in-memory with the `archive` package, no fixtures), realistic multi-question detection, group-permission enforcement (leader/member/non-member/cross-group/owner), retry & double-tap idempotency, snapshot independence |
| `test/v1_via_document/document_upload_screen_test.dart` | Widget-level coverage of the review screen: idle/error/empty states, select/deselect, edit (via the shared `QuestionEditor`), remove, reorder, blocked-invalid-confirm, and a full pick→parse→edit→confirm round trip |

### From the original commit, corrected by this pass
| File | What changed here |
|---|---|
| `lib/core/services/document_service.dart` | Fixed the `\Z` regex bug (§3); split `extractContent` into a Supabase-dependent download step and a new public, pure `extractFromBytes(bytes, fileName)` so parsing is unit-testable without Supabase; made `_client` lazy (matches `SupabaseTestRepository`'s pattern) for the same reason; added FlateDecode stream inflation for PDFs (§4) |
| `lib/features/test/state/document_upload_controller.dart` | Fixed `removeQuestion`'s index-shift bug (§3) |
| `lib/features/test/screens/document_upload_screen.dart` | The review card had no way to edit a question, set its correct option, or reorder it — Phase 5/6 requirements the original commit's UI didn't actually meet. Reused the exact `QuestionEditor` bottom sheet Manual creation already uses (edit question text/options/correct option/marks/explanation); added drag-to-reorder (`ReorderableListView`); added a per-question validity badge and an aggregate "N need attention" banner; fixed a display bug where the header always showed the full `selectedIndices` list length correctly but a stray line printed the list itself instead of its count; fixed a genuine layout overflow in the new invalid-notice banner; added an injectable `controller` constructor param for testability (same pattern as the Routine/Calendar screens elsewhere in this codebase) |

### Unchanged from the original commit (inspected, correct)
`lib/core/models/uploaded_document.dart`, `lib/core/models/extracted_content.dart`, `migrations/V1_VIA_DOCUMENT_FILE.sql`, `lib/features/test/data/test_repository.dart` (`creationMethod`), `lib/features/test/state/test_creation_controller.dart` (`questionSource`), `lib/features/test/widgets/question_source_step.dart`, `lib/features/test/screens/test_creation_screen.dart`, `lib/app/app_router.dart` (`/tests/create/document-import`), `pubspec.yaml`/`pubspec.lock` (`file_picker`, `archive`, `path`, `xml`).

## 3. Two real bugs found and fixed

1. **Every question's last option was silently dropped.** `_detectNumberedMcq`'s option-boundary regex used `\Z` as an "end of text" anchor. Dart's `RegExp` is the ECMAScript flavor, which has no `\Z` escape — it silently falls back to matching a literal `Z`, so that branch of the lookahead never fired. Any question whose last option was followed by nothing (end of document) or immediately by the next question (no blank line) lost its final option outright — for typical numbered-MCQ documents, that's *every* question. Replaced `\Z` with `$` (correct under Dart's non-multiline `RegExp`) in both the question and option patterns, and fixed a second, related off-by-one in the option-section slicing that excluded the very newline the fixed lookahead needed. Proven with a real multi-question 4-option document in `document_service_and_permissions_test.dart` (previously this would have shipped silently truncating every question's options — the "64 tests pass" claim in the original report never exercised the real regex against realistic multi-line content).
2. **Removing a question deselected every question after it instead of shifting its selection down.** `removeQuestion`'s index-rewrite ran `_selectedIndices.removeWhere((i) => i > index)` and then tried to read `_selectedIndices.where((i) => i > index)` to shift those very entries down — but they had just been deleted by the previous line, so the shift always added nothing. Rewrote it as one pass that removes and re-keys both `_selectedIndices` and `_editedQuestions` in the same expression. Proven in `document_upload_screen_test.dart`.

## 4. PDF extraction: FlateDecode support added

The original commit's PDF extraction only scanned for literal, uncompressed `BT…ET`/`Tj`/`TJ` text operators in the raw file bytes. Real-world PDFs almost always compress their page content streams with Flate (zlib) — against such a file the original code would extract zero blocks and show "no questions detected" for essentially every real PDF. This pass added a `_inflatePdfStreams` step that finds every `stream…endstream` object whose dictionary declares `/FlateDecode`, decompresses it with the **already-declared `archive` package's `ZLibDecoder`** (cross-platform, no new dependency, no `dart:io`), and runs the same Tj/TJ extraction over the decompressed bytes. Proven with a real zlib-compressed stream built via `ZLibEncoder` in the test suite (§6). Streams with other/unsupported filters (images, LZW, etc.) are skipped, not guessed at, and never abort the rest of the file.

## 5. Database / storage (unchanged, still pending)

`migrations/V1_VIA_DOCUMENT_FILE.sql` (additive-only, marked **OWNER APPLY REQUIRED**, not applied by this pass — no live DB access from this environment):
- `public.uploaded_documents` (file_name, storage_path unique, mime_type, file_size ≤20MB, uploaded_by → auth.users, group_id → groups nullable, status ∈ uploaded/parsing/parsed/failed) with RLS restricted to `uploaded_by = auth.uid()` on every verb, granted to `authenticated` only, revoked from `anon`/`PUBLIC`.
- Storage bucket `test-documents`: **private**, 20MB limit, MIME allow-list (pdf/docx/xlsx/xls), with `storage.objects` policies restricting insert/select/delete to `(storage.foldername(name))[1] = auth.uid()::text` — a user can only ever reach their own folder; no bucket is public; no service-role key appears in the Flutter client (only the anon key, via the existing `SupabaseService.client`).

## 6. Tests

**203 tests** across three files in `test/v1_via_document/` (up from the original 64, all pre-existing 64 kept and passing):

- `document_upload_test.dart` (64, unchanged from the original commit): `QuestionSource` mapping/availability, `TestWriteInput.creation_method`, `DetectedQuestion`↔`QuestionDraft`, `ContentBlock`/`ExtractedContent`, controller state-machine skeleton, `QuestionDraft` validity, file validation via a fake service, `UploadedDocument` (de)serialization, provenance carrier, idempotency shape, Manual-flow regression, labels.
- `document_service_and_permissions_test.dart` (43, new this pass): real PDF extraction — uncompressed and **FlateDecode-compressed** content streams, an unsupported-filter stream skipped without crashing, a valid-but-empty PDF yielding empty blocks (never fabricated content); real DOCX extraction — paragraphs, tables, missing `document.xml`, not-a-zip; real XLSX extraction — shared strings, no-worksheets error; question detection on realistic multi-question content (never sets a correct answer, per Phase 4); duplicate de-duplication; group-permission enforcement — CREATE_TEST holder succeeds, plain member denied, non-member denied, cross-group denied, owner always succeeds (via the same `FakeTestRepository`/`InMemoryGroupRepository` the rest of the R4/G10 suite already relies on to mirror the live policy shape — **this proves the controller path, not Postgres RLS itself**); double-tap rejected by the existing busy-guard; sequential saves update rather than re-create; a failing sibling draft doesn't cause an already-created one to be recreated on retry; a created question carries no reference back to the source document.
- `document_upload_screen_test.dart` (10, new this pass): idle/pick-error/empty-review states; selection count and the "needs attention" banner; editing a question via the shared `QuestionEditor` to set its correct option; removing a question; reordering; the confirm action refusing an invalid selection with a dialog; a full pick→edit→confirm flow returning drafts to the caller through a real `GoRouter`.

**All 203 pass.** `Phase 15 not covered by unit tests` (by design, per the phase's own instruction not to overclaim): live RLS enforcement, live Supabase Storage policy enforcement, and a real on-device file pick — these require a live backend/device and are marked NOT VERIFIED below.

## 7. Validation

| Command | Result |
|---|---|
| `flutter analyze` (this feature's files, scoped) | **0 errors.** Only pre-existing `info`/`warning` lints remain (const-constructor suggestions, two `RadioListTile.groupValue`/`onChanged` deprecation infos already present elsewhere in this codebase in the same style, and one `ReorderableListView.onReorder` deprecation info on a very recent Flutter dev channel). |
| `flutter analyze` (whole project) | Clean of hard errors in every reachable file. The only remaining errors are in `test/r4_5_3_ui_test.dart`, `test/r4_5_4_ui_test.dart`, `test/r4_7_2_qa_fix_test.dart`, `test/r4_8_test.dart` — untracked debris from a pre-R4-restart iteration (reference `ResultService`, `TestTakingScreen`, `Answer.selectedOptionId` — none of which exist any more), present before this session started and unrelated to Via Document/File. |
| `flutter test` (this feature's own suite) | **203/203 passed.** |
| `flutter test` (whole project) | **1248 passed, 7 failed.** All 7 are pre-existing and outside this feature: the 4 debris files above fail to compile, and `test/r4_restart/creation_completion_test.dart` (×2) / `screens_smoke_test.dart` (×1) assert a stale "only Manual is available" premise that R7's Question Bank and this very feature's `QuestionSource.document`/`.ai` enablement have already superseded — not something this pass's changes touch or could regress further. |
| `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` | See §11 (recorded after the run completes). |

## 8. Security (re-verified, not just re-asserted)

- No service-role key anywhere in `lib/` — `document_service.dart` only ever calls `SupabaseService.client` (anon-key session client), same as every other repository.
- No public file URL: the storage bucket is created `public = false`; every `storage.objects` policy requires `(storage.foldername(name))[1] = auth.uid()::text`.
- No direct unauthorized table writes: `uploaded_documents` insert/update/delete all carry `uploaded_by = auth.uid()` in their `WITH CHECK`/`USING`; test/question creation goes exclusively through `rpc_create_test`/`rpc_create_question`, never a direct `.insert()` on `tests`/`questions`.
- No answer-key leakage: participants read questions only through `get_test_questions_safe` (`QuestionRepository.safeQuestions`, untouched by this feature); the `Question` model returned to callers has no `correctOption`/`correct_option` field at all — structurally, not just by convention, so a document-imported question cannot leak its answer key any differently than a manually-typed one.
- No cross-user/cross-group file access: proven by the storage policy shape above (§5); `uploaded_documents.group_id` is informational metadata only, never used to widen access.
- Group security for test creation is **entirely inherited**: because document-sourced drafts flow into the exact same `TestCreationController.saveDraft()`/`publish()` → `rpc_create_test` path as Manual, the CREATE_TEST/membership/cross-group checks are the same server-enforced checks already exercised by the rest of the R4/G10 suite — see §6 for the controller-level tests added this pass, and the note there about what they do and don't prove.

## 9. Known limitations

1. **PDF extraction remains best-effort, not a real PDF parser.** It now handles the common case (FlateDecode content streams) but has no true object/xref parsing: page boundaries aren't tracked (blocks are numbered in extraction order, not by page), other filters (LZW, ASCII85, embedded images) are skipped rather than guessed at, encrypted/password-protected PDFs are not supported, and text extracted from subset/custom-encoded fonts may not map to correct characters. This is an honest, scoped V1 limitation, not a silent one — an unparseable file yields "no questions detected," never fabricated content.
2. **Source provenance stops at the review screen.** `questions` has no creator-writable column for "which document/page/row this came from," and `rpc_create_question` accepts no such parameter. Rather than misuse the participant-visible `explanation` field to smuggle in internal file structure, or invent a new column (which Phase 8 explicitly says to stop and inspect before doing, and which needs an owner-applied migration this environment can't apply or verify live), provenance is shown to the creator during review only and is not persisted onto the created row. A future `questions.import_source` (or similar) column is a reasonable follow-up, left to the owner to decide.
3. Detection is regex/heuristic-based (numbered `N. … A./B./C./D.` blocks, or question-like-block-followed-by-option-like-blocks) — non-standard layouts fall through to manual review, by design (Phase 4 forbids AI and forbids guessing).
4. `MISSED`/duplicate-across-tests detection is per-document only (normalized-text de-dup within one parse); it does not check against questions already in the test or elsewhere.

## 10. STOP condition

Per this task's scope, no further test source (AI Generation, Books) was started or modified by this pass beyond the two bug fixes and the review-UI/testing work described above, all within Via Document/File's own files.

## 11. VERIFICATION STATUS

| Item | Status |
|---|---|
| Architecture discovered | ✅ VERIFIED LOCALLY |
| Files changed | ✅ VERIFIED LOCALLY |
| Database migration | ⏳ OWNER APPLY REQUIRED (unchanged from original commit; no live DB access from this environment) |
| Storage bucket | ⏳ OWNER APPLY REQUIRED |
| RPC changes | ✅ VERIFIED LOCALLY (none needed — `rpc_create_test`/`rpc_create_question` already sufficient) |
| UI flow | ✅ VERIFIED LOCALLY (widget tests, §6) |
| Supported formats | ✅ VERIFIED LOCALLY with real bytes (§6) — not device-verified with real user files |
| Extraction approach (incl. Flate) | ✅ VERIFIED LOCALLY |
| Question detection | ✅ VERIFIED LOCALLY, bug-fixed (§3) |
| Validation (client-side) | ✅ VERIFIED LOCALLY |
| Security | ✅ VERIFIED LOCALLY (code/policy inspection); ⏳ NOT VERIFIED LIVE (no live DB/storage access from this environment — apply §5 first, then re-run the kind of live attack matrix the rest of this repo's `FINAL_GAP_AUDIT_REPORT.md` used for Group Hub) |
| Group permission enforcement | ✅ VERIFIED LOCALLY at the controller level (§6); NOT a substitute for live RLS proof |
| Tests | ✅ VERIFIED LOCALLY — 203/203 this feature, 1248/1255 whole project (7 pre-existing failures unrelated, §7) |
| Analyze | ✅ VERIFIED LOCALLY — 0 errors |
| APK build | see below, filled in after the run |
