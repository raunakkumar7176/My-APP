# Group Test Result Publish System — Audit, Backend, and Delta Report

Status: **BACKEND DESIGNED (unapplied), Dart data-layer wired, UI wiring deferred. Live verification BLOCKED — no Supabase/device access from this environment.**

## 1. Existing architecture discovered

- `result_batches` (`UNIQUE(test_id)`, `batch_status`: pending→processing→completed/partially_completed/failed) + `rpc_generate_results(p_test_id)` — live, verbatim-captured (`docs/live/rpc_generate_results.live.sql`, `migrations/R4_HOTFIX_submit_autosubmit_batch_reuse.sql`). Idempotent (returns any existing batch row unchanged, `result_batches_test_id_key` unique constraint makes a second row impossible), permission-gated (owner or `GENERATE_RESULTS`).
- `rpc_submit_attempt` / `fn_auto_submit` (live, same capture) call `fn_score_attempt(p_attempt)` **synchronously** at submit/auto-submit time.
- `notifications` table + `notif_category` enum + `fn_notify_group`/`fn_is_notification_allowed` — fully live-verified (`docs/NOTIFICATION_SYSTEM_FULL_VERIFICATION_REPORT.md`, an earlier phase's rolled-back-transaction audit). `RESULTS_AVAILABLE` already exists in the enum but no trigger/RPC ever creates it.
- `rpc_get_leaderboard(p_test)` (live, `migrations/G17_01_fix_rpc_get_leaderboard_access.sql`) — server-ranked, `SECURITY DEFINER`.

## 2. Existing result states

`batch_status`: pending, processing, completed, partially_completed, failed. **No "published" state existed** — this task's own gap (§4).

## 3. Existing result permissions

`GENERATE_RESULTS` (batch generation, `ai_reports`/`result_batches` trigger-read) and `VIEW_GROUP_ANALYTICS` (unrestricted `results` read for managers) are the two live permissions this system reuses as-is. No new permission was created.

## 4. Who can publish result

Identical authorization to `rpc_generate_results`: test creator always; group members need `GENERATE_RESULTS`; everyone else `GENERATE_RESULTS_FORBIDDEN`. Reused, not reinvented, in the new `rpc_publish_results`.

## 5. Database changes (new, unapplied)

`migrations/FINAL_AUDIT_group_result_publish.sql`:
- **A.** `result_batches` + `published_at timestamptz`, `+ published_by uuid`.
- **B.** `rpc_publish_results(p_test_id)` — new, separate from `rpc_generate_results`. Requires an already-completed/partially-completed batch (`RESULTS_NOT_GENERATED` otherwise); idempotent (second call/concurrent call returns the same published state, no duplicate); notifies only eligible participants (attempts with `status IN (submitted, auto_submitted, scored)` — the exact set `rpc_generate_results` itself already scores, never `group_members`).
- **C.** `ALTER POLICY "own results" ON results` — adds a publish check, exempting every self/practice test (`group_id IS NULL`, completely unaffected) and requiring `result_batches.published_at IS NOT NULL` for group tests. `"analytics holders see group results"` (VIEW_GROUP_ANALYTICS) is untouched — managers keep pre-publish preview by design.
- **D.** `rpc_get_leaderboard` — `CREATE OR REPLACE`, identical signature/columns/ordering, same publish gate as C, with the same manager-preview exemption (creator or `VIEW_GROUP_ANALYTICS`) so Part 14's "owner sees complete result" requirement still holds pre-publish.

## 6. The two live security gaps this closes

Both proven from live-captured/live-audited sources already in this repo, not assumed:
1. `results` RLS `"own results"` was `user_id = auth.uid()` with no publish gate — combined with synchronous scoring at submit, a student could read their own final marks the instant they submitted. This directly violated the Core Product Rule ("submission" ≠ "published").
2. `rpc_get_leaderboard` had no publish gate at all — any creator/group-member/participant could see **everyone's** scores and rank the moment attempts were scored, a bigger leak than #1.

## 7. RPCs/functions changed

- New: `rpc_publish_results(uuid)`.
- Replaced (same signature/columns, additive WHERE clause only): `rpc_get_leaderboard(uuid)`.
- `ALTER POLICY` (not recreated) on `results`.
- Not touched: `fn_score_attempt`, `rpc_generate_results`, `rpc_submit_attempt`, `fn_auto_submit`, `fn_notify_group`, `fn_is_notification_allowed`, `notifications` schema/RLS, any grant.

## 8. Result publication lifecycle

```
attempt submitted/auto-submitted → fn_score_attempt (synchronous, unchanged)
        ↓
result_batches: (none) → owner/GENERATE_RESULTS calls rpc_generate_results → completed
        ↓  (published_at still NULL — results/leaderboard still hidden from students)
owner/GENERATE_RESULTS calls rpc_publish_results → RESULTS_NOT_GENERATED unless batch completed/partially_completed
        ↓
published_at set once, idempotently → eligible participants notified (RESULTS_AVAILABLE) → results/leaderboard visible
```

## 9. Pre-publication visibility rules

- Self/practice test (`group_id IS NULL`): unchanged, visible immediately — never gated.
- Group test, student: own `results` row → 0 rows under RLS. `rpc_get_leaderboard` → 0 rows.
- Group test, owner or `VIEW_GROUP_ANALYTICS` holder: full `results` read (existing "analytics holders" policy, untouched) and full leaderboard (new exemption in step D) — internal preview preserved, per Part 14.

## 10. Post-publication visibility rules

- Student: own `results` row only (RLS still scopes by `user_id`; another student's row remains 0 rows). Leaderboard: all eligible rows, server-ranked, unchanged ordering.
- Manager: unchanged (was already unrestricted).

## 11. Notification flow

`rpc_publish_results` loops the eligible-participant set (not `group_members`) and, for each, checks `fn_is_notification_allowed(uid, 'RESULTS_AVAILABLE', group_id)` before inserting into `notifications` with `dedupe_key = 'results_published:<test_id>'` (existing `uniq_notifications_dedupe (user_id, dedupe_key)` index makes a repeat publish a guaranteed no-op, never a duplicate row). Title/body match the task's requested English copy; Hindi equivalents belong at the Flutter presentation layer (the `notifications` row itself is language-neutral data, matching the existing convention for every other category in this table). Never fires on submit, on a still-processing batch, on a failed publish, or for an unauthorized caller (those paths `RAISE EXCEPTION` before reaching the notify loop).

## 12. Student download flow

Not implemented this pass — `TestPdf.resultReport`/`answerSheet` (existing, and extended with `groupName`/pass-fail in the prior phase) already scope to the caller's own attempt/result by construction (they take already-loaded, RLS-scoped data, never an arbitrary id); once `results` RLS is applied, a pre-publish download attempt fails the same way a pre-publish read does — no separate gate needed. Wiring an actual "Download My Result" affordance into the results screen was not done (§14).

## 13. Owner consolidated result flow

`TestPdf.groupResult` (added in the prior phase) already builds the one-PDF-per-group consolidated report from an already-ranked `List<GroupResultRow>`. It is unaware of publish state by design — the caller (once wired) would only build it after confirming `ResultBatch.isPublished`.

## 14. Leaderboard behavior

Ranking/tie logic itself is untouched (`ORDER BY r.score DESC, r.percentage DESC, a.submitted_at ASC, a.id ASC`, unchanged from the live G17-01 body) — only a WHERE-clause visibility gate was added. `LeaderboardEntry.fromServerRows` (existing) still trusts the RPC's own rank as-is.

## 15. Security verification

Cannot be live-verified (no Supabase access). The migration file's 12-case matrix (§ "SECURITY / BEHAVIOR TEST MATRIX") is written for a human with production access to run, covering: self-test exemption, pre-publish student/leaderboard denial, `RESULTS_NOT_GENERATED` ordering, double/concurrent publish idempotency, post-publish own-row-only visibility, non-member/anon rejection, and the manager-preview asymmetry.

## 16. Idempotency/concurrency verification

- Server: `rpc_publish_results` locks the `result_batches` row `FOR UPDATE`, checks `published_at IS NOT NULL` before doing anything, and returns the existing state (`reused: true`, `notified: 0`) on a repeat/concurrent call — the row lock serializes a race between two simultaneous publishers so only one can win the `UPDATE`.
- Client: `ResultBatch.fromPublishRpcJson` / `publishFromRpcResponse` parse this response symmetrically to the existing `generateResults` path.
- Dart-side (`FakeResultRepository.publishResults`), mirrored and tested: same-authorization check, `RESULTS_NOT_GENERATED` when no completed batch exists, idempotent return on a second call.

## 17. Automated test results

```
flutter analyze lib/core/models/result_batch.dart lib/features/test/data/result_repository.dart \
  test/r4_restart/fakes.dart test/group/group_test_results_test.dart test/group/group_leaderboard_test.dart migrations/
  1 issue found — unused_field at fakes.dart:402, pre-existing, unrelated to this change (verified: outside the
  899+ region touched this pass)

flutter test test/group/group_test_results_test.dart
  00:02 +23: All tests passed!   (this file's controller is clean — no collision; every fix here is a genuine
  publish-gate correction, not a workaround)

flutter test test/group/ test/r4_restart/
  732 tests, 9 failing:
    - 4 in group_leaderboard_test.dart — confirmed pre-existing collision: `git diff` shows
      lib/features/group/state/group_leaderboard_controller.dart was independently rewritten by a concurrent,
      uncommitted session (switching _readResults()/resultsForTest() to _readLeaderboard()/leaderboard(),
      adding canSeeFullLeaderboard) *before* this task started; this file was never touched in this pass.
    - 3 in creation_completion_test.dart, 1 in save_status_test.dart, 1 in screens_smoke_test.dart — none of
      these source or test files were touched this pass; consistent with the same actively-edited-by-another-
      session area (test_creation_screen.dart / configuration_step.dart) already documented as colliding in
      this session's earlier phases.
  None of the 9 failures are in a file this pass edited.
```

## 18. Live/authenticated E2E verification

**BLOCKED — UNVERIFIED.** No Supabase CLI/psql/credentials and no Android device are available in this environment (established fact, re-confirmed this session). Per this task's own explicit rule, this is reported honestly rather than fabricated as passing. Specifically not run: the migration against a live project, an authenticated Ramu/Kalu/Sita/Ravi-style multi-student submit → hidden-result → publish → notified → own-download → owner-consolidated → leaderboard-matches walkthrough.

## Remaining blockers / explicitly deferred scope

1. **Migration not applied** — a human with production Supabase access must run `migrations/FINAL_AUDIT_group_result_publish.sql` and its postflight checks.
2. **Flutter UI not wired**: no "Publish Result" button, confirmation dialog, `NOT_GENERATED/GENERATING/COMPLETED/PUBLISHED` state UI, pre-publish "submitted successfully / result pending" student copy (bilingual), or download affordances exist yet. `group_test_results_screen.dart`, `group_leaderboard_controller.dart`, and `result_repository.dart`'s sibling UI files are all currently modified by a different, concurrently-running, uncommitted session (confirmed via `git status --short` at the start and end of this pass) — wiring the actual screens was deliberately deferred to avoid a destructive collision, exactly as documented in the prior Group Result report. The backend contract (`ResultBatch.isPublished`/`canPublish`, `ResultRepository.publishResults`) is ready for that screen to call once the concurrent rewrite lands.
3. **`group_leaderboard_controller.dart`'s own tests are currently broken independent of this task** (§17) — needs reconciling with the concurrent rewrite before it can be extended with a publish check on the client side; not attempted here to avoid compounding an in-flight architecture change with guesses about its final shape.
4. **No live device or Supabase verification possible from this environment** — every claim above is "code is provably correct by audit and unit test," never "confirmed passing in production."
