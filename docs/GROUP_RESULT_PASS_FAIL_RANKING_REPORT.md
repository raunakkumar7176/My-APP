# Final Group Result + Pass/Fail + Ranking + Consolidated Report Card — Audit & Delta Report

Status: **AUDIT-DRIVEN, MOSTLY ALREADY IMPLEMENTED. Live verification BLOCKED — this environment has no Supabase access and no Android device.**

## 1. Current result architecture discovered

Group results already run on **one authoritative pipeline**, not per-student calculations:

- `public.result_batches` — one row per test (`UNIQUE(test_id)`, confirmed via `migrations/R4_BATCH_REUSE.sql`'s own postflight check `result_batches_test_id_key`). Generation is idempotent by construction: a second "Generate" call hits the existing unique row, not a duplicate.
- `public.results` — the per-student scored row, written only by server-side scoring (`rpc_submit_attempt` → batch completion), never recomputed client-side.
- `rpc_get_leaderboard` — the single server-side ranking RPC; `LeaderboardEntry.fromServerRows` (lib/features/group/domain/group_test_results.dart:295) trusts its rank/order as-is.
- `ai_reports` / coach-report jobs (`G11_rpc_request_coach_reports.sql`) — batch-level, not per-student AI calls, confirmed already in place.

## 2. Existing permissions and who can generate results

`GroupResultsAccess` (lib/features/group/domain/group_test_results.dart) already implements the exact gate the task asked for:
- `canGenerate`, `canSeeAllResults`, `canSeeAllReports`, `isResultsPhase`, `canSeeLeaderboard` — all pure functions that mirror server-side permission checks (`GENERATE_RESULTS`, `VIEW_GROUP_ANALYTICS`, etc.), used only to drive UI affordance.
- The actual enforcement is server-side: `result_repository.dart` reads `result_batches` under RLS, and `rpc_request_coach_reports`/batch RPCs are `SECURITY DEFINER` with their own permission checks — a client cannot bypass the button by calling the RPC directly, confirmed by inspecting the RPC bodies (out of scope to re-verify live, but the code path never trusts a client-sent flag).

## 3. Existing leaderboard architecture

`LeaderboardEntry` has two paths, both audited:
- `fromServerRows` — the live path; ranks come straight from `rpc_get_leaderboard`.
- `fromResults` — a documented client-side fallback with an **explicit standard-competition tie rule (1,2,2,4)**, i.e. the next distinct score gets `rank = 1 + count of entries strictly above it`. This is a fallback formatter, not a second scoring engine — it never touches marks, only display rank when the server RPC path isn't available.

No second ranking algorithm was added. `TestPdf.groupResult` (new, see §6) does not rank anything — it takes `List<GroupResultRow>` with `rank` already populated by the caller from one of the above and prints it verbatim (confirmed by the "never re-ranks" test that hands it out-of-order/tied ranks and expects them printed unchanged).

## 4. Pass/fail source and rule

- `Test.passingMarks` (`int?`, JSON key `passing_marks`) was already a live, read/write **Dart model** field (lib/core/models/test.dart:115-116), reading a column that already exists in the original DDL: `passing_marks integer NOT NULL DEFAULT 0 CHECK (passing_marks >= 0)` with an existing table-level `CHECK (passing_marks <= total_marks)` (migrations/R4_1_phase_db_foundation.sql:106-107,135).
- The gap: **no live RPC exposed a write path** to it. Both `rpc_create_test` and `rpc_update_test`'s full parameter/INSERT-column lists (read earlier this session) omit `passing_marks` — the exact same shape of gap already found and fixed once for `shuffle_questions`.
- Only ONE field was added (not both `pass_marks` and `passing_percentage`) because the architecture already standardized on absolute marks (`passing_marks integer`, not a percentage), matching `total_marks`'s own unit.
- Pass/fail itself is **not stored anywhere** and is not computed by any new RPC — it is derived as plain arithmetic, `marks >= test.passingMarks`, at the call site (Dart), from numbers the server already certified. This matches the task's explicit rule: marks must come from existing server scoring only, never recalculated.

## 5. Changes made

Only two files were modified/created, both additive, zero deletions, zero touches to any file flagged dirty by the concurrent session:

| File | Change |
|---|---|
| `lib/features/test/domain/test_pdf.dart` | +133 lines: new optional `groupName` + PASS/FAIL rows on `resultReport()` (backward compatible — all new params optional, existing callers unaffected); new `TestPdf.groupResult(...)` consolidated group PDF builder; new `GroupResultRow` plain data carrier. |
| `migrations/FINAL_AUDIT_group_result_pass_marks.sql` | New, unapplied migration: `rpc_set_test_pass_marks(p_test_id, p_passing_marks)`. |
| `test/r4_restart/pdf_test.dart` | +120 lines: 4 new tests covering the above. |
| `docs/GROUP_RESULT_PASS_FAIL_RANKING_REPORT.md` | This report. |

**Explicitly NOT touched**, because `git status --short` showed them modified by a different, concurrently-running session (collision-avoidance, per established session discipline):
- `lib/features/group/screens/group_test_results_screen.dart`
- `lib/features/group/state/group_leaderboard_controller.dart`
- `lib/features/test/data/result_repository.dart`
- `lib/features/group/domain/group_test_results.dart`

This means the live UI wiring — an actual "Generate Group Result" button, confirmation dialog, NOT_GENERATED/GENERATING/COMPLETED/FAILED state UI, the consolidated-table screen, the bulk-ZIP export — was **not implemented this pass**. Wiring `TestPdf.groupResult`/`GroupResultRow` into those screens is the natural next step once the concurrent session's changes land, to avoid a destructive merge.

## 6. SQL migrations

`migrations/FINAL_AUDIT_group_result_pass_marks.sql` (new, **UNAPPLIED** — no live DB access from this environment):
- `rpc_set_test_pass_marks(p_test_id uuid, p_passing_marks integer)` — `SECURITY DEFINER`, `SET search_path TO ''`, mirrors the exact structure of the already-applied-pattern `rpc_set_test_shuffle_questions`: `AUTH_REQUIRED` if unauthenticated, `TEST_NOT_FOUND` if missing/soft-deleted, draft-only (`VALIDATION_ERROR` otherwise — published tests are immutable, same convention as `rpc_update_test`), value must be `>= 0` and `<= total_marks` (defense-in-depth on top of the existing DB `CHECK` constraint), creator-or-`EDIT_TEST` permission via `fn_has_permission` (no new permission invented), `GRANT ... TO authenticated` / `REVOKE ... FROM anon, PUBLIC`.
- Includes preflight/postflight verification queries and a 7-case manual security test matrix, same format as prior migrations in this session.

## 7. RPCs created/modified

- Created (unapplied): `rpc_set_test_pass_marks`.
- Modified: none. No existing RPC body was touched.

## 8. Security/RLS verification

- Client-side "hide the button" is explicitly NOT treated as security anywhere in the new code — `TestPdf.groupResult`/`resultReport` are pure formatters over data the caller already obtained through authorized reads; they perform no writes and grant no access.
- The new RPC follows this project's established hardening pattern (`SECURITY DEFINER` + `SET search_path TO ''` + `auth.uid()`-derived ownership + explicit `REVOKE` from `anon`/`PUBLIC`), identical to every other RPC added this session.
- **Cannot be live-verified** — no Supabase project access from this environment. The 7-case test matrix in the migration file is written for a human with production DB access to run.

## 9. Result batch flow

Unchanged — confirmed already idempotent (`UNIQUE(test_id)` on `result_batches`) and already audited in `migrations/R4_BATCH_REUSE.sql`. No changes made to batch generation.

## 10. Ranking/tie behavior

Unchanged — confirmed already correct (`LeaderboardEntry.fromServerRows` trusts the server; `fromResults`'s documented fallback uses standard competition ranking 1,2,2,4). `TestPdf.groupResult` never re-ranks; verified by a test that feeds it tied/gapped ranks (`1,2,4`) and asserts they print unchanged.

## 11. Group summary calculation

`GroupTestResultsSummary` (existing, in the currently-dirty `group_test_results.dart`) was **read only, not modified** this pass. Its stale code comment ("no pass mark exists live, so none is invented") is now outdated by this pass's migration, but editing that file was avoided due to the active collision risk; the comment should be updated once that file's concurrent edits land.

## 12. Student result screen

Not touched (file `group_test_results_screen.dart` is dirty from the concurrent session).

## 13. Leaderboard

Not touched (`group_leaderboard_controller.dart` is dirty). Architecture confirmed correct by audit only (§3).

## 14. Consolidated PDF

New: `TestPdf.groupResult({required test, required groupName, required rows, participants, appeared, passed, failed, averagePercentage, highestPercentage, lowestPercentage, generatedAt})`:
- One PDF for the whole group (not per-student), A4, `pw.MultiPage` (multi-page-safe by construction, same pattern as `questionPaper`/`resultReport`/`answerSheet`), page-number footer (`Page X / Y`).
- Header: test title, group name, generated timestamp.
- Summary section: Participants/Appeared/Passed/Failed/Average/Highest/Lowest.
- Ranked table: Rank/Student/Marks/Total/%/Correct/Wrong/Unanswered/Result — matches the requested column set (Pass Marks is implied via the per-row Result column rather than repeated per row, since it's one constant value for the whole test — shown once in the individual report card instead, where it's more useful per-student).
- Explicit footer disclaimer: "Ranking and marks are taken as-is from the server's authoritative result dataset. This report never recomputes rank or scores."
- Takes `List<GroupResultRow>` — a new, minimal, logic-free data carrier (rank/studentName/marks/totalMarks/percentage/correctCount/wrongCount/unansweredCount/passFail) deliberately NOT coupled to `LeaderboardEntry` (which lives in the currently-dirty `group_test_results.dart`), so `test_pdf.dart` stays self-contained and this change doesn't create a merge conflict with the concurrent session. Wiring `LeaderboardEntry` → `GroupResultRow` mapping is a one-line job for whoever wires the screen next.

## 15. Individual report card

`TestPdf.resultReport` already covered nearly everything requested (student/test/score/percentage/accuracy/correct/wrong/unanswered/rank/subject+topic breakdown/attempt history/delta-from-previous) — confirmed by reading its full existing body. This pass added only the two genuinely missing pieces, both as optional/backward-compatible additions:
- `groupName` (optional param, renders a "Group" row when provided).
- Pass Marks + Result (PASS/FAIL) rows, rendered only when `test.passingMarks != null && result.score != null`, computed as `result.score! >= test.passingMarks!` — arithmetic at the call site, not a new scoring engine.

## 16. Test results

```
flutter analyze lib/features/test/domain/test_pdf.dart test/r4_restart/pdf_test.dart
  No issues found! (ran in 11.0s)

flutter test test/r4_restart/pdf_test.dart
  00:00 +11: All tests passed!

flutter analyze lib/
  21 issues found — all pre-existing, none in files touched this pass
  (verified: none reference test_pdf.dart or pdf_test.dart)
```

Also re-ran the broader r4_restart suite to confirm no regression from these changes:
- `test/r4_restart/attempt_results_test.dart` — 13/13 passed (includes the shuffle-by-attempt-id tests from the prior phase).
- `test/r4_restart/pretest_gate_test.dart` — 7/7 passed.
- `test/r4_restart/screens_smoke_test.dart` — 1 pre-existing failure ("creation wizard renders every step and gates Next", `Bad state: No element` in `WidgetController.widget`) — **not caused by this pass**; this file was not touched, and the failure is consistent with the concurrent session's in-progress edits to `configuration_step.dart`/`test_creation_screen.dart` noted in earlier phases of this session. Documented here transparently rather than silently ignored or falsely claimed fixed.

## 17. Live verification

**BLOCKED — UNVERIFIED.** Per the task's own explicit rule ("DO NOT CLAIM COMPLETE/PASS WITHOUT LIVE VERIFICATION"), the following are honestly reported as not verified, not fabricated as passing:
- The new migration has NOT been applied to any live Supabase project (no CLI/psql/credentials available in this environment).
- No live "Generate Group Result" flow, PDF download, or student-visibility check has been exercised against a real database or device.
- No Android device was connected (`adb devices` empty in prior phases of this session).

## 18. Remaining blockers

1. **Migration not applied** — `rpc_set_test_pass_marks` exists only as a reviewed SQL file; a human with production access must run it.
2. **UI not wired** — no screen calls `TestPdf.groupResult`/the new `resultReport` params yet; this was deliberately deferred to avoid colliding with the concurrent session's active edits to the group-results screen/controller/repository.
3. **`GroupTestResultsSummary`'s pass-count fields** (Passed/Failed) are not yet computed anywhere live — the new `passed`/`failed` params on `TestPdf.groupResult` are ready to receive them once the summary calculator (in the currently-dirty file) is updated to use `passingMarks`.
4. **No live device or Supabase verification possible from this environment** — all claims above are "code is provably correct by audit," never "confirmed passing in production."
