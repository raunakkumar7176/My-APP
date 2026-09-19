# G11 — Group Test Results & AI Coach Report: Implementation Report (builder)

**Branch:** `r4-restart` · **Base:** `f0c6136` · **Commit:** `__COMMIT__` · **Date:** 2026-09-19
**Role:** implementer (not audited). G10.2 files untouched; G9's uncommitted doc-comment left in place. An earlier uncommitted G11 draft found in the working tree (from the other agent) was taken over and corrected — it called `rpc_generate_results` on screen open (a mutation) and parsed non-live AI payload keys; both are fixed here.

## FINAL STATUS

**G11 IMPLEMENTATION COMPLETE — BACKEND PENDING**

Reading results/reports works against the live schema as-is (no migration). "Backend pending" = the one proposed additive RPC that lets the Flutter client **queue** AI coach reports into the existing `ai_jobs` table (`migrations/G11_rpc_request_coach_reports.sql`, PROPOSED, **not applied**), and the fact that **no worker processes `ai_jobs` live** (the legacy web app generated reports inline; the queue has never been consumed). No AI runs anywhere in the Flutter path.

---

## 1. Live schema inspected (read-only, actual grids, 2026-09-19)

- **`results`** (PK `attempt_id`; FK attempts/tests/profiles): `test_id, user_id, score, max_score, correct_count, wrong_count, unanswered_count, accuracy, percentage, rank, subject_breakdown jsonb, topic_breakdown jsonb, computed_at`. RLS SELECT: `own results` (`user_id = auth.uid()`), `analytics holders see group results` (`VIEW_GROUP_ANALYTICS` in the test's group). No client write policy.
- **`result_batches`** (`UNIQUE(test_id)`): `requested_by, status batch_status(pending|processing|partially_completed|completed|failed), reports_done, reports_total, totals, created_at, completed_at`. RLS SELECT: `trigger sees batches` (`GENERATE_RESULTS`).
- **`ai_reports`** (`UNIQUE(test_id, user_id)`; FK batch/test/profile): `payload jsonb NOT NULL, model text NOT NULL, created_at`. RLS SELECT: `own reports`, `report trigger reads` (`GENERATE_RESULTS`). **0 rows live.**
- **`ai_jobs`**: `type CHECK('gen_questions','coach_reports'), test_id, result_batch_id, idempotency_key UNIQUE, payload, status job_status(pending|processing|completed|failed), attempts, max_attempts, next_run_at, last_error, tokens_in/out`. RLS: `no direct ai_jobs access` (SELECT false; no INSERT). **0 rows live; no function or cron references it; no edge functions exist.**
- **`attempts`** (`deadline_at` NOT NULL; `UNIQUE(test_id,user_id,attempt_number)`), **`answers`** (`selected_option int`, own-attempt policies, `authenticated` SELECT only).
- **RPCs:** `rpc_generate_results(p_test_id)` — SECURITY DEFINER: auth required; creator OR `GENERATE_RESULTS`; reuses the test's single batch (`reused: true`) else creates it (pending → processing), scores every submitted/auto_submitted/scored attempt via `fn_score_attempt` (deterministic: counts, marks − wrong × negative_marks, accuracy, percentage, subject/topic breakdown; `ON CONFLICT (attempt_id) DO NOTHING`), sets completed / partially_completed / failed. **No AI, no `ai_jobs`.** `fn_score_attempt` is also what `rpc_submit_attempt` uses. Cron: only `fn_sweep_deadlines`.
- Live data: 8 results, 1 completed batch (a standalone test), 0 ai_reports, 0 ai_jobs.
- **AI payload contract** (only producer: legacy `My-Prepration/src/lib/ai/coach.ts` `reportBatchSchema`): `summary, strengths[], weaknesses[], mistake_patterns[], subject_analysis[{subject, performance, note}], revision_plan[], practice_plan[], next_week_action_plan[], coach_message`; `model` e.g. `gemini-2.0-flash`.

## 2. Existing R4 result infrastructure reused

`ResultRepository` (existing `byAttempt`, `mineForTest`, `generateResults` → `rpc_generate_results`), `Result` / `ResultBatch` models, the R4 result screen `/attempts/:id/result` (question-wise review through `get_test_questions_safe` — no answer key), `TestRepository.getById`, `GroupRepository.groupForMember / permissionsFor / members`, `GroupPermissions` (`GENERATE_RESULTS`, `VIEW_GROUP_ANALYTICS`), `DisposableNotifier`, `TestLifecycle.statusLabel`, `TestFormatters`; fakes `FakeResultRepository` / `FakeTestRepository` / `InMemoryGroupRepository`. No new result, report or job table; no second permission engine.

## 3. Screens / features implemented

- **Route** `/groups/:groupId/tests/:testId/results` (`group-test-results`), opened from the G10 manage sheet ("Results" button, shown for completed / ended / evaluated tests) — `GroupTestResultsScreen`.
- **Participant view (every member):** own stored result — score / max, percentage, rank, correct / wrong / unanswered, accuracy, negative-marking impact (`wrong × negative_marks`), computed time; **deterministic insights** (`ResultInsights`): strong areas (≥ 75 %) and weak areas (< 50 %) from `subject_breakdown`, improvement points (weak subjects, unanswered pacing, negative-marking loss, accuracy-before-speed, clean run); "Question-wise review" → existing R4 result/review screen; **AI Coach Report** card rendered from the stored `ai_reports.payload` (summary, strengths, weak areas, repeated mistakes, subject analysis, revision / practice / next-week plans, coach message, model + time) or an honest empty card.
- **Manager view (GENERATE_RESULTS or owner; VIEW_GROUP_ANALYTICS or owner):** batch status line, **Generate results** (confirmation → `rpc_generate_results`), **Request AI coach reports** (enabled only when the batch is completed/partially completed; → proposed RPC; shows job status), group summary (participants, average / median / best %), every participant's row (name from the roster, score, %, C/W/U, report-stored flag).
- States: loading, loaded, empty (no results / no own result), error + retry, access denied (non-member, test of another group), "not over yet" note, busy + single-flight, mutation success/error snackbars, server re-read after every action.

## 4. Permissions used (existing only)

| Action | Server rule (live) | UX gate |
|---|---|---|
| read own result / own report | `own results` / `own reports` policies | member of the group |
| read all results | `VIEW_GROUP_ANALYTICS` policy | `canSeeAllResults` (probe ∨ owner) |
| read batch / all reports | `GENERATE_RESULTS` policies | `canSeeAllReports` / `canGenerateResults` |
| generate results | `rpc_generate_results`: creator ∨ `GENERATE_RESULTS` | `canGenerateResults` (creator ∨ probe ∨ owner) |
| request coach reports | proposed RPC: same gate + finished batch | same + batch completed |

## 5. AI token-saving flow

Screen open = reads only (`results`, `ai_reports`, `result_batches` for permitted callers, roster, permission probes) — asserted by tests ("opening never generates / never queues"). Flow: manager taps **Generate results** → `rpc_generate_results` (deterministic, stored) → manager taps **Request AI coach reports** → `rpc_request_coach_reports` inserts **one** `ai_jobs` row per (test, batch) with idempotency key `coach_reports:<test_id>:<batch_id>` (`ON CONFLICT DO NOTHING`; a second tap returns `created: false`) → a worker (not part of G11) processes the queue and upserts `ai_reports` (`UNIQUE(test_id,user_id)`) → users read stored reports. Re-opening screens, refreshing, or re-tapping never triggers a model call.

## 6. Security assumptions

Membership + group scope: `groupForMember` must return the group and `test.groupId` must equal the route's group, otherwise access denied; RLS additionally scopes every read. Members receive only their own `results` / `ai_reports` rows; managers' broader reads are policy-driven, not client-filtered. `correct_option` is never queried (management reads `results` only; review uses the safe RPC). Forged user ids are irrelevant (all reads keyed by `auth.uid()` server-side). Anon holds table grants on `results`/`ai_reports`/`result_batches` (pre-existing) but no policy applies to it — verified denied. **Live proof (rolled-back transaction, with the proposed RPC applied inside it):** member cannot generate/request; creator request before a batch → `RESULTS_NOT_GENERATED`; `rpc_generate_results` stores 2 result rows and creates no `ai_jobs`; member reads own row only, no batch, no `ai_jobs`; leader reads all rows + batch; request creates exactly one pending `coach_reports` job, second call reused; non-member / anon denied; safe question RPC has no `correct_option`; removed leader sees 0 rows. Residue 0, RPC not live afterwards. These are auditor-style checks by the builder — **not** a verification claim.

## 7. Tests (`test/group/group_test_results_test.dart` → 23; full suite 818)

Models (payload parsing, job parsing, insights, summary, gates); member (own result only, no other report, no generate/batch/AI call on open; stored report readable; cannot generate/request — controller and fake server); access (non-member denied, other group's test denied, cross-group results empty, removed member, forged user row invisible); manager (sees all + batch + reports, explicit generation with server re-read, batch reuse, coach request only after a finished batch and idempotent, owner bypass, server rejection surfaced, single-flight); states + widgets (loading/empty/error/retry; member card/insights/review button/no manager section/no other names; coach card sections; leader generate → batch status → request coach; denied state). Fakes mirror the live policies and RPC gates.

## 8 / 9. `flutter analyze` / APK

`flutter analyze` → 0 errors, 0 warnings (info lints only). `flutter test` → **818 passed** (795 + 23). `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` → **√ Built build/app/outputs/flutter-apk/app-debug.apk**.

## 10. Migrations created

`migrations/G11_rpc_request_coach_reports.sql` — one SECURITY DEFINER RPC (`search_path=''`, `auth.uid()` required, EXECUTE authenticated only, anon/public revoked), inserts into the existing `ai_jobs`; no table, column, policy or permission change. `docs/G11_PRECHECK.sql` (live-run: all present, RPC absent) / `docs/G11_POSTCHECK.sql`.

## 11. Live backend changes

**None applied.** Pending: (a) owner applies the RPC in the SQL Editor (postflight `fn_present=true, anon_can_execute=false`), (b) a coach-report **worker** for `ai_jobs` (not in scope; without it requested jobs stay `pending` and the UI says so honestly). Everything else G11 needs is already live.

## 12. Files

| File | Change |
|---|---|
| `lib/features/group/domain/group_test_results.dart` | rewritten: `AiCoachReport` (live payload keys), `SubjectAnalysis`, `CoachReportJob`, `ResultInsights`, `GroupTestResultsSummary`, `GroupResultsAccess` |
| `lib/features/group/state/group_test_results_controller.dart` | rewritten: reads only on load, permission probes, own result/insights, manager actions single-flight with re-read |
| `lib/features/group/screens/group_test_results_screen.dart` | rewritten: participant + coach + manager sections |
| `lib/features/test/data/result_repository.dart` | `resultsForTest`, `myAiReport`, `allAiReports` (draft), + `batchForTest` (plain read), `requestCoachReports` (proposed RPC) |
| `lib/app/app_router.dart` | `/groups/:groupId/tests/:testId/results` |
| `lib/features/group/screens/group_tests_screen.dart` | "Results" action in the manage sheet for finished tests |
| `lib/features/group/screens/group_hub_screen.dart` | doc-comment only |
| `test/r4_restart/fakes.dart` | `FakeResultRepository` mirrors live RLS/RPC rules (groups/tests hooks) |
| `test/group/group_test_results_test.dart` | 23 tests |
| `migrations/G11_rpc_request_coach_reports.sql`, `docs/G11_PRECHECK.sql`, `docs/G11_POSTCHECK.sql`, this report | new |

## 13. Known limitations

No live worker for `ai_jobs` (queued reports are not produced until one exists); time-taken per attempt not shown (results carry no attempt timing; attempts would need a second query); `rank` is only what the server stored (live scorer does not assign it); topic breakdown keyed by node ids is not rendered (no name lookup); no device run.

**FINAL STATUS: G11 IMPLEMENTATION COMPLETE — BACKEND PENDING**
