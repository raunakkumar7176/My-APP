# G11 — Group Test Results & AI Coach Report: Backend Verification Report

**Branch:** `r4-restart` · **Flutter impl:** `4a5e6ff` (report `1dd82dd`) · **This report:** `41c66f3` · **Date:** 2026-09-19
**Scope:** the G11 backend dependency only — `migrations/G11_rpc_request_coach_reports.sql`. No Flutter change, no G9/G10.2/G12 file touched. Live access: read-only + rolled-back transactions via the pooler credentials in the untracked `tool/` scripts (never printed); the live database is unchanged (`rpc live=false`, residue 0 after every run).

## FINAL STATUS

**G11 BACKEND READY — OWNER APPLY REQUIRED**

Not called PASS: the RPC is not applied live and no `ai_jobs` worker exists. **Job enqueue is implemented; worker/AI execution is a separate future phase.**

---

## 1. What was already live (re-audited, actual grids)

| Object | Live state |
|---|---|
| `public.results` | PK `attempt_id`; `score, max_score, correct_count, wrong_count, unanswered_count, accuracy, percentage, rank, subject_breakdown, topic_breakdown, computed_at`; SELECT `own results` (`user_id = auth.uid()`), `analytics holders see group results` (`VIEW_GROUP_ANALYTICS`); no client write policy |
| `public.result_batches` | `UNIQUE(test_id)`; `status batch_status` (pending → processing → completed / partially_completed / failed), `reports_done/total`, `totals`, `completed_at`; SELECT `trigger sees batches` (`GENERATE_RESULTS`) |
| `public.ai_reports` | `UNIQUE(test_id, user_id)`, `payload jsonb`, `model text`, FK → batch; SELECT `own reports`, `report trigger reads` (`GENERATE_RESULTS`); **0 rows** |
| `public.ai_jobs` | `type CHECK IN ('gen_questions','coach_reports')`, `test_id`, `result_batch_id`, `idempotency_key UNIQUE`, `payload`, `status job_status`, `attempts/max_attempts/next_run_at/last_error/tokens_*`; policy `no direct ai_jobs access` (SELECT `false`, no INSERT); **0 rows; no function or cron references it; no edge functions** |
| `rpc_generate_results(uuid)` | SECURITY DEFINER; auth required; creator OR `GENERATE_RESULTS`; single batch per test (reused); `fn_score_attempt` per submitted attempt (deterministic); **no AI, no `ai_jobs`** |
| cron | only `my-prep-sweep` → `fn_sweep_deadlines()` |

`docs/G11_PRECHECK.sql` run live: `results/result_batches/ai_reports/ai_jobs = true`, `rpc_generate_results/fn_score_attempt = true`, `request_rpc = false`; policies and uniqueness exactly as above.

## 2. What was missing

A client entry point to the existing queue: `ai_jobs` is closed to clients (SELECT false, no INSERT policy) and nothing enqueues `coach_reports` jobs. Everything else G11's Flutter code reads (`results`, `ai_reports`, `result_batches`) already works under the live policies.

## 3. Exact migration (audited; no correction needed)

`migrations/G11_rpc_request_coach_reports.sql` — `CREATE OR REPLACE FUNCTION public.rpc_request_coach_reports(p_test_id uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''`:

1. `auth.uid()` NULL → `AUTH_REQUIRED`.
2. Test by exact id, `is_soft_deleted = false` → else `TEST_NOT_FOUND`.
3. `created_by <> uid` → requires `group_id IS NOT NULL AND public.fn_has_permission(group_id, uid, 'GENERATE_RESULTS')` → else `GENERATE_RESULTS_FORBIDDEN` (identical gate to `rpc_generate_results`; owner passes through the function's bypass).
4. `result_batches` row for the test must exist with status `completed` or `partially_completed` → else `RESULTS_NOT_GENERATED`.
5. `INSERT INTO public.ai_jobs (type='coach_reports', test_id, result_batch_id, idempotency_key = 'coach_reports:<test_id>:<batch_id>', payload {group_id, requested_by, requested_at}) ON CONFLICT (idempotency_key) DO NOTHING`; on conflict the existing job is read back.
6. Returns `{job_id, status, reports_done (count of ai_reports for the test), reports_total (batch), created}`.
7. `REVOKE ALL … FROM PUBLIC, anon; GRANT EXECUTE … TO authenticated, service_role; NOTIFY pgrst`; read-only postflight.

No table, column, policy, grant or enum is changed; `rpc_generate_results` is untouched; no second queue or report table. Rollback: `DROP FUNCTION public.rpc_request_coach_reports(uuid);`.

## 4. Authorization model

| Caller | `rpc_generate_results` (live) | `rpc_request_coach_reports` (proposed) | read results | read batch / all reports |
|---|---|---|---|---|
| anon | denied | **permission denied (no EXECUTE)** | denied | denied |
| non-member | `GENERATE_RESULTS_FORBIDDEN` | `GENERATE_RESULTS_FORBIDDEN` | none | none |
| member (no perms) | forbidden | forbidden | own row only | none / own report |
| creator (any role) | ✓ | ✓ (after finished batch) | own rows (+ all if VIEW_GROUP_ANALYTICS) | batch/reports if GENERATE_RESULTS |
| leader (seeded GENERATE_RESULTS + VIEW_GROUP_ANALYTICS) | ✓ | ✓ | all | all |
| owner (fn bypass) | ✓ | ✓ | all | all |

User identity comes only from `auth.uid()`; the RPC takes only `p_test_id`, so forged user ids are impossible; cross-group targets fail the permission check on the test's own `group_id`. `VIEW_GROUP_ANALYTICS` intentionally does **not** grant queuing (matches the batch/report policies which are `GENERATE_RESULTS`-only).

## 5. Idempotency

One job per (test, batch) via `idempotency_key` — first call `created: true`, every later call `created: false` with the same `job_id`; proven (rows 12–14). Per-user reports remain unique through `ai_reports UNIQUE(test_id, user_id)` (worker-side upsert target). A `failed` job is not automatically re-queued (documented; owner/worker policy).

## 6. Security proof (rolled-back transaction; RPC applied only inside it; fixtures: B = leader of "Nn", C = member, D = non-member, A = owner; two attempts + two approved questions; second test in "INDIAN ARMY")

| # | Requirement | Result |
|---|---|---|
| 1 | migration object exists after apply | *pending owner* — postflight/`POSTCHECK` statement 1 checks `fn_present` |
| 2/3/4 | SECURITY DEFINER, `search_path=''`, authenticated-only | in-tx definition verified; anon → `permission denied for function` (row 18); postflight checks `prosecdef`, `proconfig`, `has_function_privilege` |
| 5 | member authorization | creator/leader ✓ (12), owner via bypass (G11 tests) |
| 6 | non-member rejection | D → `GENERATE_RESULTS_FORBIDDEN` (16); member C (no perm) → forbidden (2) |
| 7 | cross-group rejection | leader of "Nn" on an "INDIAN ARMY" test → `GENERATE_RESULTS_FORBIDDEN` (13b; 13c same for `rpc_generate_results`) |
| 8 | anon rejection | RPC: permission denied (18); `results` read: permission denied (17 — stricter than "0 rows") |
| 9 | unfinished batch rejection | `processing` → `RESULTS_NOT_GENERATED` (13d); `failed` → rejected (13e); no batch → rejected (3) |
| 10 | completed batch acceptance | after `rpc_generate_results` → `created: true` (12) |
| 11/12/13 | first request creates exactly one job; second reuses; no duplicate | one `coach_reports` job, `pending`, key `coach_reports:<test>:<batch>` (12–14) |
| 14 | `ai_jobs` inaccessible to client | member SELECT → 0 rows (9) |
| 15 | `rpc_generate_results` deterministic, no AI | 2 `results` rows with counts/marks; `ai_jobs` count 0 after generation (4–6) |
| 16 | opening the result screen invokes no generation/queuing | Flutter tests assert no `generate`/`requestCoach`/`batch` call on member open and no re-queue on refresh (`group_test_results_test.dart`) |
| 17 | members read only authorized rows | C sees own row only, no batch (7, 8); removed leader sees 0 rows (21); leader sees all (10, 11) |
| 18 | `correct_option` protected | safe RPC columns have none (19); direct `questions` read denied (20) |
| 19 | G10/G8/R4 regression | `flutter test` **818/818**, `analyze` 0 errors / 0 warnings, APK built (no code change) |

Residue after rollback: proof tests 0, `ai_jobs` 0, RPC absent.

## 7. AI worker limitation

**Job enqueue is implemented; worker/AI execution is a separate future phase.** No process consumes `ai_jobs` live; queued jobs stay `pending` and the G11 UI shows exactly that. No AI report is produced by this phase. The legacy inline Gemini path is out of scope and untouched.

## 8. Flutter regression

No Flutter change in this task. `flutter analyze` → 0 errors / 0 warnings (info lints only) · `flutter test` → **818 passed** · `flutter build apk --debug --dart-define-from-file=dart-defines.dev.json` → **√ Built**.

## 9. Owner steps

1. SQL Editor → `docs/G11_PRECHECK.sql` (expect `request_rpc=false`, policies as in §1).
2. Paste and run `migrations/G11_rpc_request_coach_reports.sql` → postflight: `fn_present=true, security_definer=true, search_path={search_path=}, anon_can_execute=false, authenticated_can_execute=true`.
3. `docs/G11_POSTCHECK.sql` → statement 1 all true/false as expected; statement 2 unchanged policies; statement 3 queue state.
4. Reply "G11 applied" — I re-run the 25-check proof live (rolled back) against the applied function and close G11 as VERIFIED (worker still pending).

**FINAL STATUS: G11 BACKEND READY — OWNER APPLY REQUIRED**
