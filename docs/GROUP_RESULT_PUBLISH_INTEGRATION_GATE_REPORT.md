# Result Publish System — Final Integration Gate Report

**Verdict: NOT PRODUCTION PASS.** Backend migration is reviewed and ready but **not applied to live Supabase**; UI is wired and unit-tested; **no live/authenticated Chrome E2E has been run**. Both are hard environment blockers in this session, stated up front rather than worked around:

- **No Supabase CLI, psql, `.env`, or database credentials exist anywhere in this environment** (re-confirmed this pass — no new access appeared since it was last checked). I cannot execute Phase A's "apply to live" or the live verification queries myself.
- **No browser-automation/computer-use tool is available** (re-confirmed via `ToolSearch`). I cannot execute Phase D's Chrome E2E myself.

Everything else in the gate — inspecting the concurrent session's work, merging the minimum necessary UI, reviewing the migration against already-live-proven evidence, and adding focused tests — is done and reported below. Section 6 gives the exact commands/steps for a human with production access to complete Phases A and D.

---

## 1. Backend migration — applied or not applied

**NOT APPLIED.** `migrations/FINAL_AUDIT_group_result_publish.sql` is unchanged since the prior phase (I re-read it this pass; no edits were needed — see §2). It remains a reviewed, unapplied SQL file. Section 6 gives the exact apply procedure.

## 2. Live security verification (review, not live execution)

Reviewed the migration's four steps against evidence already proven live in this repo (not migration-file assumptions — per this session's standing rule to distrust migration files against contradictory live captures):

| Claim | Evidence | Verdict |
|---|---|---|
| `result_batches` exists, `UNIQUE(test_id)`, `batch_status` enum with `pending/processing/completed/partially_completed/failed` | `docs/live/rpc_generate_results.live.sql` — verbatim `pg_get_functiondef` capture, 2026-09-17 | Confirmed live |
| `rpc_generate_results` authorization (creator or `GENERATE_RESULTS`) | Same live capture, lines 36-49 | Confirmed live; `rpc_publish_results` reuses this exact branch, not a new check |
| `results` RLS: `"own results"` = `user_id = auth.uid()`, `"analytics holders see group results"` = `VIEW_GROUP_ANALYTICS` | `docs/G11_GROUP_RESULTS_VERIFICATION_REPORT.md` §1 — live, proven via rolled-back-transaction probes with pooler credentials, 2026-09-19 | Confirmed live; step C only adds an `AND (...)` clause via `ALTER POLICY`, does not touch the analytics policy |
| `rpc_get_leaderboard` current body/grants | `migrations/G17_01_fix_rpc_get_leaderboard_access.sql` — live, dated 2026-09-20 | Confirmed live; step D is a verbatim `CREATE OR REPLACE` of this exact body with one additive `AND (...)` clause |
| `notif_category` includes `RESULTS_AVAILABLE`; `notifications` columns/RLS/dedupe | `docs/NOTIFICATION_SYSTEM_FULL_VERIFICATION_REPORT.md` §3.4/§5.2 — live, rolled-back-transaction audit, 2026-09-20 | Confirmed live; `RESULTS_AVAILABLE` was already in the enum, unused — this migration is the first thing that emits it |
| `fn_is_notification_allowed(uuid, text, uuid, ...)` signature | `migrations/G8_1_fix_fn_is_notification_allowed.sql` | Confirmed; `rpc_publish_results` calls it with the same 3-arg form other live callers use |

No schema, function, or enum value was invented — every object `rpc_publish_results` and the two `CREATE OR REPLACE`s reference was independently proven live before this migration was written. **This review is as far as it can go without database access; the "SECURITY / BEHAVIOR TEST MATRIX" at the bottom of the migration file (12 cases) still requires a human to run against the live project — see §6.**

## 3. UI integration (done this pass)

Re-inspected the concurrent session's uncommitted work before touching anything:
- `group_leaderboard_controller.dart` — substantially rewritten by the other session (switched from `resultsForTest`-based filtering to `rpc_get_leaderboard`-based reading, added `canSeeFullLeaderboard`). **Not touched** — extending it correctly requires knowing its final intended shape, which isn't mine to guess.
- `group_test_results_screen.dart` — only a 1-line diff from the other session (harmless, unrelated). `group_test_results_controller.dart` and `group_leaderboard_screen.dart` were **completely clean** (not touched by anyone). These three are what I edited.

Changes (all additive, existing behavior preserved):
- **`group_test_results_controller.dart`**: `publishResults()` — same single-flight `_run` pattern as `generateResults()`/`requestCoachReports()`, gated on `canGenerateResults && batch.canPublish`, permission-denied message takes priority over "generate first" so an unauthorized caller gets an accurate reason.
- **`group_test_results_screen.dart`**: manager section gets a "Result Pending Publication" / "Result Published" status line and a **"Publish Result"** button (`FilledButton`, disabled until `batch.canPublish`, same busy-guard as the existing buttons so a duplicate click during an in-flight request is a no-op) behind a bilingual confirmation dialog (exact Hindi/English text from the task, Cancel/Publish Result buttons, no auto-confirm on outside tap — `showDialog` default). The Publish button is inside the same `if (_c.canGenerateResults)` block as Generate — unauthorized users never see it, and the server enforces the same gate independently (UI visibility is documented as never the security boundary, per Part header comment now in the screen). The member's empty-result card now shows the bilingual "submitted successfully / available after publication" copy instead of the previous message that conflated "not generated" with "not published."
- **`group_leaderboard_screen.dart`**: the pre-generation empty-state copy was updated to the bilingual "available after publication" text (it previously said "generate results first," which is no longer the accurate/only reason results might be hidden).

No unrelated screens, colors, or layouts were touched.

## 4. Focused tests (Phase C)

`test/group/group_test_results_test.dart` — **27/27 pass** (was 23; 4 new):
1. `publish: requires a finished batch, is idempotent, notifies eligible participants only` — covers matrix items #1 (no batch → no publish), #7 (duplicate publish idempotent, no second call recorded), #10 (post-publish `isPublished`).
2. `non-member/unauthorized student cannot publish` — matrix item #4.
3. `leader: publish button disabled until generated, confirmation gate, idempotent re-tap...` (widget) — button disabled pre-generate, bilingual confirmation text present before any call fires, button disabled again post-publish (matrix #7 at the UI layer).
4. `member: no publish button, no batch status, sees the safe pre-publish note then the real result once published` (widget) — matrix #8 (pre-publish: no card, safe bilingual note only) and #10 (post-publish: real result appears) at the UI layer.

Matrix item coverage from this pass plus the prior pass's fake-repository gating (`_resultVisible`, leaderboard gate) and `attempt_results_test.dart`/scoring tests (untouched, still 13/13):

| # | Requirement | Covered by |
|---|---|---|
| 1-3 | Submit/early/late submit never publishes | `rpc_submit_attempt`/`fn_auto_submit` untouched (no code path from submission to `published_at`); `attempt_results_test.dart` unchanged, still passing |
| 4 | Unauthorized student cannot publish | New test above |
| 5-6 | Owner/authorized manager can publish | `publish: requires a finished batch...` test, `owner (no explicit permission row)` fixture reused |
| 7 | Duplicate publish idempotent | New test above (client) + migration's row-lock design (server, unverified live) |
| 8 | Pre-publish result query returns nothing unauthorized | `_resultVisible` gate in `FakeResultRepository`, exercised by the widget test above and the prior pass's controller tests |
| 9 | Pre-publish leaderboard blocked for normal students | Prior pass's `leaderboard()` fake gate (member/participant branch) — not re-tested this pass since `group_leaderboard_controller.dart` is mid-rewrite by another session (§5) |
| 10-11 | Post-publish result/leaderboard available | New widget test (result); leaderboard fake gate (prior pass) |
| 12 | Notification only after successful publish | `rpc_publish_results`'s structure (RAISE EXCEPTION before the notify loop on every failure path) — reviewed, not live-executable from here |
| 13-14 | Student A cannot access/download B's result | Existing `"forged user id"` tests (both suites, unchanged, still passing) — RLS still scopes by `user_id` post-publish, only the group_id-gated `OR` branch was added |
| 15 | Existing scoring unchanged | `fn_score_attempt`/`rpc_submit_attempt` not modified; `attempt_results_test.dart` 13/13 unchanged |

## 5. Remaining pre-existing test failures

Full regression: `flutter test test/group/ test/r4_restart/` → **736 tests, 9 failing** (up from 732/9 before this pass — the 4 new tests above are all passing; **zero new failures were introduced**). All 9 are in files this session never touched, unchanged from the prior report:

- **4 in `group_leaderboard_test.dart`** — `git diff` confirms `group_leaderboard_controller.dart` was independently rewritten by a different, concurrently-running, uncommitted session before this task began. Extending it with a client-side publish check was deliberately not attempted, to avoid guessing at an in-flight rewrite's final shape.
- **3 in `creation_completion_test.dart`, 1 in `save_status_test.dart`, 1 in `screens_smoke_test.dart`** — none of these source or test files were touched this pass or any prior pass in this session; consistent with the same broader concurrent-session collision area (test creation wizard files) documented since an earlier phase.

## 6. Exact steps to complete Phase A (apply) and Phase D (Chrome E2E)

**These steps were not run — no database or browser access exists in this environment. They are ready for a human to execute.**

### Phase A — apply

1. Open the Supabase SQL Editor for the project.
2. Run the **PREFLIGHT** block at the top of `migrations/FINAL_AUDIT_group_result_publish.sql` (3 read-only queries) — confirm `published_at`/`published_by` don't exist yet, `"own results"` qual is exactly `(user_id = auth.uid())`, and `rpc_publish_results` doesn't exist.
3. Run **Steps A–D** of the same file top to bottom (columns, `rpc_publish_results`, `ALTER POLICY`, `rpc_get_leaderboard` replace).
4. Run the **POSTFLIGHT** block — confirm both functions are `SECURITY DEFINER` with `search_path` set, and the `"own results"` qual now mentions `published_at`.

### Phase A — live security verification

Run the **12-case SECURITY / BEHAVIOR TEST MATRIX** at the bottom of the same migration file, as two or three real authenticated users (one owner/manager, one or two students) against a real group test. It already covers, in order: self-test exemption (#1), pre-publish student/leaderboard denial (#2-3), publish-before-generate rejection (#5), successful publish + per-eligible-participant notification (#6), duplicate/concurrent publish idempotency (#7), post-publish own-row-only visibility (#8), post-publish leaderboard ranking unchanged (#9), non-member/anon rejection (#10), and the manager-preview asymmetry (#11-12).

### Phase D — Chrome E2E

1. Three accounts: A (student), B (student), Owner (group owner or `GENERATE_RESULTS` holder) — all members of the same group, with a group test both A and B can take.
2. **A submits** the test; wait; **B submits** later. Do not touch any old/stale attempt — use this fresh test only.
3. As **A**: open the test's result screen → expect `result_not_published_note` copy ("Your test has been submitted successfully... will be available after publication"), no marks, no rank. Open the leaderboard → expect `leaderboard_not_published_note`, no entries.
4. As **B**: same checks.
5. As **Owner**: open the same screen → expect the manager section, `batch_status` = "Results not generated yet.", `publish_status` = "Result Pending Publication", **Publish Result** button disabled.
6. As **Owner**: tap **Generate results** → confirm → `batch_status` updates, `publish_status` stays "Result Pending Publication", Publish Result button becomes enabled.
7. As **Owner**: tap **Publish Result** → confirm the bilingual dialog → expect `publish_status` = "Result Published".
8. As **A** and **B**: refresh → each now sees **only their own** result (marks/rank/counts), `my_result_card` appears, the leaderboard shows correct ranking, and each received exactly one "Test Result Published" notification (check the notification bell/inbox) — never the other student's result.
9. As **Owner**: refresh → sees the complete group result (all participant rows, `group_summary`).
10. Optional direct-access check: as B, attempt to open A's individual result/report-card download by editing an id/URL if the app exposes one — expect denial, not A's data.
11. Tap **Publish Result** again as Owner (if still reachable) — expect no duplicate notification to A or B, no error, no new batch.

## 7. Blockers

1. **Migration not applied to live Supabase** — no credentials/CLI in this environment; §6 gives the exact procedure for someone who has them.
2. **No live/authenticated Chrome E2E was run** — no browser-automation tool in this environment; §6 gives the exact script.
3. **`group_leaderboard_controller.dart`/`group_leaderboard_test.dart` need reconciling** with the concurrent session's in-flight rewrite before a client-side publish check can be safely added there — deferred, not attempted, to avoid compounding an unfinished architecture change with guesses.
4. Until #1 is done, none of the reviewed security behavior in §2/§6 has been **confirmed** live — it is "provably correct by audit and unit test," not "confirmed passing in production." Per this task's own explicit rule, this is not called a PASS.
