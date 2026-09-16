# R4 RESTART — Forensic Audit of the Current Flutter Test System

Date: 2026-09-16. Read-only. No production code changed for this audit.
Baseline: 626 tests passing, `flutter analyze` 0 errors, debug APK builds.
Surface audited: `lib/features/test/**` (≈8,900 lines), test-related
`lib/core/models/**` and `lib/core/services/**` (≈3,300 lines).

Classification: **KEEP** (reuse as-is or with trivial moves) · **REWRITE**
(concept stays, implementation replaced) · **REMOVE** · **DEFER** (out of the
rebuild's first phases) · **BACKEND-DEPENDENT** · **UNKNOWN**.

## 1. Models (`lib/core/models`)

| Item | Finding | Class |
|---|---|---|
| `Test` (218 lines) | One class mixes DB row (`config`, `settings`, soft-delete fields) with UI conveniences (`isCoded`, `isActive`, `typeLabel`); 13-value status enum; `test_mode` as raw `String?`. `toJson` is never sent to the server (only router extras). Fields `instructions, class_level, tags, language, difficulty, total_marks, passing_marks, total_questions, shuffle_questions, show_answers_after, is_public` come from the R4_1 DDL and are LIVE-UNVERIFIED (all tolerated as null). | REWRITE — split into a lean row model + a `TestMode` enum + centralized kind/label mapping; drop `toJson`. |
| `TestKind` (R4.11a) | Clean, centralized, tested; but a *Self-family* enum, not the full product enum the restart asks for (Challenge/Group are `test_mode`). | REWRITE into the full domain `TestKind` with ONE `toBackend()/fromBackend()` mapping (mode + settings). |
| `Question` | Never parses `correct_option` (good). `status` defaults to `'active'` when absent — masks the LIVE-UNVERIFIED `status` column. `copyWith` only handles `status`. Option ids sent as `''` for new options. | KEEP shape; REWRITE parsing (no silent default for `status`). |
| `QuestionDraft` + `QuestionOptionDraft` (feature model) | Reasonable; `toCreateParams()` and `_generateOptionId()` unused; `_questionTypeToRpc` duplicates `QuestionService.questionTypeToRpc`. | KEEP, REMOVE dead members, single type mapping. |
| `Attempt` | Parses `integrity_event_count`, `auto_submit_threshold` (unused anywhere), `timeRemaining` (unused, duplicates timer). `userId` is `''` on the jsonb path. | REWRITE lean; BACKEND-DEPENDENT for shape. |
| `Answer` | Column names (`selected_option_id`, `is_marked_for_review`, `is_answered`, `text_answer`) conflict with the owner-stated live columns (`selected_option`, `marked_for_review`). `copyWith` cannot clear fields (led to the typed-answer bug). | BACKEND-DEPENDENT → REWRITE once columns are proven. |
| `Result` | Matches owner list; tolerant parsing. | KEEP. |
| `ResultBatch` | Matches owner list. | KEEP. |
| `ResultAnalytics` (Subject/Topic/Difficulty/Mistake items) | Difficulty and Mistake items have no data source (server exposes no per-question correctness); `parseDifficultyBreakdown` always returns `[]`. | KEEP subject/topic; REMOVE difficulty/mistake until backend provides data. |
| `SelfReflection` | Pure in-memory, never persisted, lost on navigation. | DEFER (needs storage decision) — REMOVE from the taking flow for now. |
| `AiReport` | Does not match the owner-listed `ai_reports` columns; no screen uses it. | REMOVE (rebuild from live shape when the feature is scheduled). |
| `TestInvitation` | Service unused by any screen; direct table update bypasses RPC. | REMOVE from the client until a server contract exists. |
| `TestSyllabus` | Fine; `id` fabricated as `''` after add. | KEEP. |
| `Group` | Only leader/member roles; owner/moderator absent server-side too. | KEEP; permissions are BACKEND-DEPENDENT. |

## 2. Services (`lib/core/services`)

| Item | Finding | Class |
|---|---|---|
| `TestService` (588 lines) | Mixes: direct `tests` SELECTs (`getTestById`, `getAccessibleTests` — client-side categorisation, limit 100, no server filter), RPC writes, **read-after-write** `getTestById` inside `createTest` / `updateTest` / `publishTest`, three error mappers (`mapErrorMessage`, `mapPublishError`, `mapStartAttemptError` — the last is unused; `AttemptService` has its own), unused direct `deleteTest` table update, diagnostic per-row logging left from R4.10. | REWRITE as a repository (`TestRepository`) with RPC-returned data used directly where sufficient; ONE error-mapping module. |
| `QuestionService` (367 lines) | Correct safe path (`get_test_questions_safe`) and RPC writes. `getQuestionById()` does a raw `from('questions').select()` — unused but a latent answer-key exposure if grants differ. Two type-mapping copies. | KEEP RPC builders; **REMOVE `getQuestionById`**; single type mapping. |
| `AttemptService` | Parses two response shapes plus a bare-string fallback (`testId=''`) → `joinByCode` had to reject that case. `_mapAttemptErrorMessage` duplicates `TestService.mapStartAttemptError`. | REWRITE parsing against the verified live shape; one mapper. BACKEND-DEPENDENT. |
| `AnswerService` | `saveSingleAnswer` unused; `getAnswersForAttempt` is a direct `answers` SELECT with the conflicting column names. | BACKEND-DEPENDENT → REWRITE. |
| `ResultService` | `getMyResults` unused; `parseDifficultyBreakdown` dead; subject parsing triggers a `subjects` fetch inside a parse helper (hidden network call). | REWRITE: repository returns rows; analytics mapping in domain; subjects fetched once by the results controller. |
| `BatchResultService` | Read-after-RPC when the RPC returns a string; `getBatchesForTest` unused. | KEEP core; REMOVE unused. |
| `GroupService` | Fine (`rpc_get_user_groups`). No create/join. | KEEP. |
| `InvitationService`, `AiReportService`, `ProgressService` | No screen uses them; invitation update writes a table directly. | REMOVE from the test system (park until contracts exist). |
| `SupabaseService`, `AuthService`, `ProfileService` (R0–R2) | Out of scope. | KEEP (untouched). |

## 3. Screens and widgets (`lib/features/test`)

| Item | Finding | Class |
|---|---|---|
| `test_creation_screen.dart` (1,157 lines) | State class holds 20+ fields, wizard step logic, persistence orchestration (`_saveDraft` / `_publishTest` are still ~60% duplicated), kind defaults, settings merge, three dialogs. Static helpers were bolted on for testability. Edit-mode = `widget.testId != null \|\| _loadedTest != null`. | REWRITE as `TestCreationController` (state + persistence orchestration, unit-testable) + thin step widgets. Reuse: `persistDraftQuestions`, `persistSyllabusSelection` (tested), kind defaults, settings merge. |
| `step_basic_details.dart` | Clean after R4.11a; `TestTypeOption` mapping lives here (should move to domain). | KEEP widget; move mapping. |
| `step_configuration.dart` (484) | Pushes state to parent via post-frame callback on mount (workaround for a state-sync bug); echoes `testMode` back to the parent on every change. Group loading inside the widget. | REWRITE against the controller; group fetch in controller. |
| `step_questions.dart` (486), `question_editor.dart` (384) | Server-question edit flow, editor validation and the `''` option-id convention; `QuestionEditor` uses deprecated `Radio.groupValue`. | KEEP with cleanup (RadioGroup, option ids). |
| `step_review.dart` (783) | Own readiness rules that differ from the parent's `_getPublishErrors`; approval RPC calls inside a widget (fixed to propagate, but still UI-owned). | REWRITE: readiness computed in ONE place (domain); widget renders it; approval via controller. |
| `step_syllabus.dart` | Fine. | KEEP. |
| `test_listing_screen.dart` (810) | Client-side categorisation of up to 100 rows into 4 tabs; duplicated status/mode/format helpers with detail; `_pushThenRefresh` workaround; diagnostic logging; two data sources (`getAccessibleTests`, `getMyDrafts`). | REWRITE: `TestListingController` + shared `TestLifecycle` helpers + shared formatters. |
| `test_detail_screen.dart` (727) | Receives `Test` via route `extra` and refetches; own lifecycle rules (`_getStartTestDisabledReason`, `_canEdit`, `_canPublish`); batch polling; join code shown in plaintext; group shown as raw UUID. | REWRITE: route by id, controller loads; lifecycle from the shared helper. |
| `test_taking_screen.dart` (716) | Sound core (server deadline, 5 s autosave, submit guard, deterministic shuffle, PopScope). Accumulated: FIX-2/3/7 comments, read-only mode, result routing, reflection dialog, typed-answer handling, kind awareness, an "untimed" branch that is dormant. Route `extra` carries attempt+questions+test objects. | REWRITE thin: `AttemptController` (answers, dirty flag, autosave, submit) + `TakingScreen`; keep `CountdownTimer`, shuffle helpers, `AnswerGrid`, `QuestionCard`. |
| `countdown_timer.dart` | Single implementation; server deadline only. | KEEP. |
| `question_card.dart`, `answer_grid.dart` | Fine after P1-6; "is answered" predicate duplicated in 6 files. | KEEP; predicate moves to `Answer`. |
| `test_result_screen.dart` (691), `question_review_screen.dart`, review/analysis cards | Result payload passed via `extra` from three places; `_buildMistakeSummary` counts only unanswered but is labelled as mistakes; difficulty card is always empty; `QuestionReviewCard` has unreachable correct/wrong states; reflection comparison UI for a value that is never stored; repeat logic duplicated with detail. | REWRITE: `ResultsController` loads by attempt/result id; remove difficulty/mistake/reflection cards until backed by data; one `startAttempt` path. |
| `join_with_code_sheet.dart` (R4.10) | Clean; fallback `Test` construction is a consequence of routing by object. | KEEP; simplify once routes carry ids. |
| `self_reflection_dialog.dart` | Value never persisted. | DEFER/REMOVE from flow. |
| `difficulty_analysis_card.dart` | Unused. | REMOVE. |

## 4. Cross-cutting findings

| # | Finding | Class |
|---|---|---|
| C1 | **Routing by object**: `/test-detail`, `/test-taking`, `/test-result`, `/question-review` pass whole models via `extra`; stale-state bugs (P1-3/P1-4) and the join-by-code fallback all stem from this. | REWRITE: routes carry ids; screens load via controllers. |
| C2 | **Lifecycle rules in 4 places**: listing tab filters, detail start/edit/publish gates, creation readiness, review readiness — with differing rules. | REWRITE: one `TestLifecycle` + `AttemptLifecycle` helper. |
| C3 | **Error mapping in 5 places** (`TestService` ×3, `AttemptService`, `QuestionService`), string-contains matching on server messages; the generic mapper hid the live publish error until R4.10. | REWRITE: one mapper keyed on server error codes (`VALIDATION_ERROR`, `TEST_CODE_INVALID`, ...) with a generic fallback that keeps the server text. |
| C4 | **Read-after-RPC-write** in `createTest`, `updateTest`, `publishTest`, `BatchResultService`, `ProfileService` (R2, out of scope). RPCs return jsonb; whether they return enough to skip the read is BACKEND-DEPENDENT (`rpc_create_test` returns only `test_id` per R4_5_1). | REWRITE where the RPC suffices; otherwise one read, in the repository. |
| C5 | **Direct table reads** used as the read model: `tests`, `test_syllabus`, `answers`, `results`, `result_batches`. Acceptable under RLS, but policy text is not in the repo. | KEEP pattern, isolate in repositories; BACKEND-DEPENDENT for visibility. |
| C6 | **Answer-key boundary**: no client code parses `correct_option`; only `getQuestionById` (unused) could fetch it. The R4.10 `SECURITY:` log guard exists. | KEEP guard; REMOVE the raw select. |
| C7 | **Timer/deadline**: single timer, server deadline, no fallback; the R4.11b "untimed" branch is dormant and gated. | KEEP; the branch is BACKEND-DEPENDENT. |
| C8 | **Terminology**: user-facing strings are compliant ("Challenge with Friends", "Ongoing"); DB `live` kept. | KEEP. |
| C9 | **Practice/Quick/Sectional**: metadata + defaults + guidance only; no server semantics; documented honestly. | KEEP as foundation; behaviour BACKEND-DEPENDENT. |
| C10 | **Tests**: 626 tests, none touch Supabase; many "mirror" screen logic by re-implementing it in the test file (`test_listing_logic_test.dart`, `r4_7_7b_test.dart`) rather than exercising app code. | REWRITE those to target the new domain helpers; keep model/param-builder tests. |
| C11 | **Unused surface** (`deleteTest`, `saveSingleAnswer`, `getMyResults`, `getBatchesForTest`, invitations, AI reports, progress, `QuestionDraft.toCreateParams`, `DifficultyAnalysisCard`, `Attempt.timeRemaining`, `TestService.mapStartAttemptError`). | REMOVE. |
| C12 | **Diagnostic logging** left in `getMyDrafts` (per-row titles) and listing. Shape-only RPC logging (R4.10) is intentional. | REMOVE row logging; KEEP `rpcShape`. |
| C13 | **Group roles**: client and repo know only leader/member; owner/moderator and `role_permissions` are UNKNOWN server-side. | UNKNOWN — do not model permissions until verified. |
| C14 | `Question.status` default `'active'` and `Attempt.userId=''` are silent fallbacks that hide contract gaps. | REWRITE: fail loudly (log) instead of defaulting. |

## 5. Reuse list (verbatim or near-verbatim)
`CountdownTimer`, `AnswerGrid`, `QuestionCard`, `QuestionEditor` (minus deprecation), `StepSyllabus`, `StepBasicDetails`, `JoinWithCodeSheet`, `SubjectAnalysisCard`, `TopicAnalysisCard`, `ResultHistoryCard`, `Result`, `ResultBatch`, `TestSyllabus`, `Group`, RPC param builders in `TestService`/`QuestionService`, `persistDraftQuestions`, `persistSyllabusSelection`, `TestKind` values/labels, `AppLogger.rpcShape`, deterministic shuffle helpers, all model/param-builder tests.
